import AppKit
import Foundation

final class ProcessInspector {
  private let behaviorEngine: BehaviorFingerprintEngine
  private let config: DiscoveryConfiguration
  private let registry: FingerprintRegistry?

  init(
    behaviorEngine: BehaviorFingerprintEngine, config: DiscoveryConfiguration,
    registry: FingerprintRegistry? = nil
  ) {
    self.behaviorEngine = behaviorEngine
    self.config = config
    self.registry = registry
  }

  func inspectRunningProcesses(deadline: Date? = nil) -> DiscoveryScanResult {
    guard !isExpired(deadline) else { return DiscoveryScanResult() }
    let rows = runtimeProcessRows(timeout: 2)
    var result = inspect(observations: rows, deadline: deadline)
    result.events.append(
      DiscoveryEvent(
        id: DiscoveryEvent.runtimeProcessSnapshotId,
        kind: .processObservation,
        path: nil,
        message:
          "Runtime process snapshot inspected \(rows.count) processes and matched \(result.runtimeProcesses.count) agent-like runtime processes.",
        createdAt: Date()
      ))
    return result
  }

  func inspect(observations rows: [ProcessObservation], deadline: Date? = nil)
    -> DiscoveryScanResult
  {
    var result = DiscoveryScanResult()
    let rowsByPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
    for row in rows {
      guard !isExpired(deadline) else { break }
      let parentChain = parentChain(for: row, rowsByPID: rowsByPID)
      let knownResult = knownProcessResult(
        for: row, parentChain: parentChain, rowsByPID: rowsByPID)
      result.merge(knownResult)
      guard knownResult.runtimeProcesses.isEmpty else { continue }

      let input = BehaviorFingerprintInput(
        processName: URL(fileURLWithPath: row.command).lastPathComponent,
        executablePath: row.command,
        argv: [row.arguments],
        cwd: nil,
        parentChain: parentChain,
        connectedLLMProviders: providers(in: row.arguments),
        spawnedCommandCount: commandScore(in: row.arguments),
        workspaceTouched: workspace(in: row.arguments),
        hasWorkspaceAgentContext: workspace(in: row.arguments).map {
          hasAgentContext(URL(fileURLWithPath: $0))
        } ?? false,
        hasMCPOrToolSchema: row.arguments.range(
          of: #"mcpServers|tools/list|function_call|tool_choice"#,
          options: [.regularExpression, .caseInsensitive]) != nil,
        wroteSessionLikeFile: row.arguments.range(
          of: #"jsonl|sqlite|memory|conversation|history"#,
          options: [.regularExpression, .caseInsensitive])
          != nil,
        observedLLMCommandLoop: isLLMCommandLoop(arguments: row.arguments)
      )
      let behavior = behaviorEngine.evaluate(input)
      guard behavior.score >= 40 else { continue }

      let agentId = UUID()
      let processName = URL(fileURLWithPath: row.command).lastPathComponent
      let runtime = RuntimeProcessAsset(
        sourceAgentId: agentId,
        pid: row.pid,
        ppid: row.ppid,
        processName: processName,
        executablePath: row.command,
        bundleIdentifier: row.bundleIdentifier,
        bundlePath: row.bundlePath,
        argv: [DiscoveryUtilities.sanitizeArgument(row.arguments)],
        cwd: input.cwd,
        parentChain: parentChain,
        connectedLLMProviders: input.connectedLLMProviders,
        spawnedCommandCount: input.spawnedCommandCount,
        workspaceTouched: input.workspaceTouched,
        agentCandidateScore: behavior.score
      )
      result.runtimeProcesses.append(runtime)

      let agent = AgentAsset(
        id: agentId,
        displayName: "Runtime Agent Candidate: \(runtime.processName)",
        normalizedName: "runtime-\(runtime.processName.normalizedAssetName)-\(runtime.pid)",
        agentType: behavior.score >= 60 ? .customTerminal : .unknownCandidate,
        confidence: behavior.score,
        discoveryMethods: [.processFingerprint, .behaviorFingerprint],
        scopes: [.runtime],
        workspacePaths: runtime.workspaceTouched.map { [$0] } ?? [],
        processIds: [runtime.pid],
        executablePaths: runtime.executablePath.map { [$0] } ?? [],
        managedStatus: .observableOnly,
        runtimeStatus: .running,
        riskLevel: DiscoveryUtilities.riskLevel(for: behavior.score),
        metadataSummary: behavior.evidenceSummaries.joined(separator: "; ")
      )
      result.agents.append(agent)
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agent.id,
          evidenceType: .behavior,
          source: "process-inspector",
          processId: runtime.pid,
          confidenceDelta: behavior.score,
          summary: behavior.evidenceSummaries.joined(separator: "; "),
          rawKey: runtime.processName
        ))
    }
    return result
  }

  private func knownProcessResult(
    for row: ProcessObservation,
    parentChain: [String],
    rowsByPID: [Int32: ProcessObservation]
  )
    -> DiscoveryScanResult
  {
    var result = DiscoveryScanResult()
    guard let registry else { return result }

    let processName = observedProcessName(for: row)
    let pathScopedMatches = registry.fingerprints.compactMap { fingerprint -> ProcessMatch? in
      guard fingerprint.confidenceWeights.process >= 20 else { return nil }
      let scope = installScope(for: row, fingerprint: fingerprint, rowsByPID: rowsByPID)
      guard scope != .none else { return nil }
      return ProcessMatch(fingerprint: fingerprint, installScope: scope)
    }
    let nameMatches = registry.fingerprints.compactMap { fingerprint -> ProcessMatch? in
      guard fingerprint.confidenceWeights.process >= 20,
        processNameMatches(processName, fingerprint: fingerprint)
      else { return nil }
      return ProcessMatch(fingerprint: fingerprint, installScope: .none)
    }
    let matchingFingerprints = preferredProcessMatches(
      pathScopedMatches.isEmpty ? nameMatches : pathScopedMatches)

    for match in matchingFingerprints {
      let fingerprint = match.fingerprint
      let runtimeContext = knownRuntimeContext(for: row)
      let installBonus = installConfidenceBonus(for: match)
      let confidence = (fingerprint.confidenceWeights.process + runtimeContext.bonus + installBonus)
        .clampedConfidence
      let agent = AgentAsset(
        displayName: fingerprint.displayName,
        normalizedName: fingerprint.normalizedName,
        agentType: fingerprint.agentType,
        vendor: fingerprint.vendor,
        confidence: confidence,
        discoveryMethods: [.processFingerprint],
        scopes: [.runtime],
        processIds: [row.pid],
        executablePaths: [observedExecutablePath(for: row)],
        managedStatus: .observableOnly,
        runtimeStatus: .running,
        riskLevel: .informational,
        metadataSummary: (["Running process matched known fingerprint: \(processName)"]
          + runtimeContext.summaries).joined(separator: "; ")
      )
      result.agents.append(agent)
      result.runtimeProcesses.append(
        RuntimeProcessAsset(
          sourceAgentId: agent.id,
          pid: row.pid,
          ppid: row.ppid,
          processName: processName,
          executablePath: observedExecutablePath(for: row),
          bundleIdentifier: row.bundleIdentifier,
          bundlePath: row.bundlePath,
          argv: [DiscoveryUtilities.sanitizeArgument(row.arguments)],
          parentChain: parentChain,
          connectedLLMProviders: providers(in: row.arguments),
          spawnedCommandCount: commandScore(in: row.arguments),
          workspaceTouched: workspace(in: row.arguments),
          agentCandidateScore: confidence
        ))
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agent.id,
          evidenceType: .process,
          source: fingerprint.normalizedName,
          processId: row.pid,
          confidenceDelta: confidence,
          summary: (["Known process fingerprint matched"]
            + installEvidenceSummaries(for: match)
            + runtimeContext.summaries).joined(separator: "; "),
          rawKey: processName
        ))
    }
    return result
  }

  private func knownRuntimeContext(for row: ProcessObservation) -> (
    bonus: Int, summaries: [String]
  ) {
    var bonus = 0
    var summaries: [String] = []
    let arguments = row.arguments
    let lower = arguments.lowercased()
    let providerNames = providers(in: arguments)
    if !providerNames.isEmpty {
      bonus += 20
      summaries.append("Runtime arguments reference \(providerNames.joined(separator: ", "))")
    }
    if commandScore(in: arguments) > 0 {
      bonus += 10
      summaries.append("Runtime arguments reference tool execution")
    }
    if workspace(in: arguments) != nil {
      bonus += 10
      summaries.append("Runtime arguments reference a known workspace")
    }
    if lower.range(
      of: #"mcpservers|tools/list|function_call|tool_choice"#,
      options: [.regularExpression]) != nil
    {
      bonus += 15
      summaries.append("Runtime arguments reference MCP/tool schemas")
    }
    if isLLMCommandLoop(arguments: arguments) {
      bonus += 25
      summaries.append("LLM request and tool feedback loop markers observed")
    }
    return (min(bonus, 70), summaries)
  }

  private func observedProcessName(for row: ProcessObservation) -> String {
    if let executable = firstArgumentExecutablePath(for: row),
      executable.hasPrefix(row.command), executable != row.command
    {
      return URL(fileURLWithPath: executable).lastPathComponent
    }

    let commandName = URL(fileURLWithPath: row.command).lastPathComponent
    return commandName
  }

  private func observedExecutablePath(for row: ProcessObservation) -> String {
    firstArgumentExecutablePath(for: row) ?? row.command
  }

  private func firstArgumentExecutablePath(for row: ProcessObservation) -> String? {
    guard
      let firstArgument = row.arguments.split(whereSeparator: { $0 == " " || $0 == "\t" })
        .first
    else {
      return nil
    }
    let executable = String(firstArgument)
    return executable.hasPrefix("/") ? executable : nil
  }

  private func processNameMatches(_ processName: String, fingerprint: AgentFingerprint) -> Bool {
    fingerprint.processNames.contains {
      $0 == processName
    }
  }

  private func processBelongsToInstallPath(
    _ row: ProcessObservation, fingerprint: AgentFingerprint
  ) -> Bool {
    let text = "\(row.command) \(row.arguments) \(row.bundlePath ?? "")"
    return fingerprint.installPaths
      .map { DiscoveryUtilities.expandedPath($0, home: config.homeDirectory).path }
      .filter { $0.hasSuffix(".app") }
      .contains { installPath in
        text == installPath || text.contains("\(installPath)/")
      }
  }

  private func installScope(
    for row: ProcessObservation,
    fingerprint: AgentFingerprint,
    rowsByPID: [Int32: ProcessObservation]
  ) -> ProcessInstallScope {
    if processBelongsToInstallPath(row, fingerprint: fingerprint) {
      return .direct
    }
    var currentParent = row.ppid
    var seen: Set<Int32> = [row.pid]
    while currentParent > 0, !seen.contains(currentParent), seen.count < 16 {
      seen.insert(currentParent)
      guard let parent = rowsByPID[currentParent] else { break }
      if processBelongsToInstallPath(parent, fingerprint: fingerprint) {
        return .ancestor
      }
      currentParent = parent.ppid
    }
    return .none
  }

  private func preferredProcessMatches(_ matches: [ProcessMatch]) -> [ProcessMatch] {
    let appScoped = matches.filter { match in
      match.installScope != .none
        && match.fingerprint.installPaths.contains { $0.hasSuffix(".app") }
    }
    if !appScoped.isEmpty {
      return appScoped
    }
    return matches
  }

  private func installConfidenceBonus(for match: ProcessMatch) -> Int {
    switch match.installScope {
    case .direct:
      min(60, match.fingerprint.confidenceWeights.installPath)
    case .ancestor:
      min(50, match.fingerprint.confidenceWeights.installPath)
    case .none:
      0
    }
  }

  private func installEvidenceSummaries(for match: ProcessMatch) -> [String] {
    switch match.installScope {
    case .direct:
      ["Runtime executable is inside known install path"]
    case .ancestor:
      ["Runtime process is a child of a known app process"]
    case .none:
      []
    }
  }

  private func runtimeProcessRows(timeout: TimeInterval) -> [ProcessObservation] {
    let shellRows = processRows(timeout: timeout)
    let appRows = runningApplicationRows()
    var keyed: [Int32: ProcessObservation] = [:]
    for row in shellRows {
      keyed[row.pid] = row
    }
    for appRow in appRows {
      if var existing = keyed[appRow.pid] {
        existing.command = appRow.command
        existing.arguments = "\(existing.arguments) \(appRow.arguments)"
        existing.bundleIdentifier = appRow.bundleIdentifier
        existing.bundlePath = appRow.bundlePath
        existing.localizedName = appRow.localizedName
        keyed[appRow.pid] = existing
      } else {
        keyed[appRow.pid] = appRow
      }
    }
    return keyed.values.sorted { $0.pid < $1.pid }
  }

  private func runningApplicationRows() -> [ProcessObservation] {
    guard !usesIsolatedHomeDirectory else { return [] }
    return NSWorkspace.shared.runningApplications.compactMap { app -> ProcessObservation? in
      guard app.processIdentifier > 0 else { return nil }
      let executablePath = app.executableURL?.path ?? app.bundleURL?.path ?? app.localizedName ?? ""
      guard !executablePath.isEmpty else { return nil }
      let evidence = [
        app.executableURL?.path,
        app.bundleURL?.path,
        app.bundleIdentifier,
        app.localizedName,
      ].compactMap { $0 }.joined(separator: " ")
      return ProcessObservation(
        pid: app.processIdentifier,
        ppid: 0,
        command: executablePath,
        arguments: evidence,
        bundleIdentifier: app.bundleIdentifier,
        bundlePath: app.bundleURL?.path,
        localizedName: app.localizedName
      )
    }
  }

  private var usesIsolatedHomeDirectory: Bool {
    config.homeDirectory.standardizedFileURL.path
      != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
  }

  private func processRows(timeout: TimeInterval) -> [ProcessObservation] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid=,comm=,args="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      let startedAt = Date()
      while process.isRunning && Date().timeIntervalSince(startedAt) < timeout {
        Thread.sleep(forTimeInterval: 0.03)
      }
      if process.isRunning {
        process.terminate()
        return []
      }
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
    return output.components(separatedBy: .newlines).compactMap(ProcessObservation.init(line:))
  }

  private func isExpired(_ deadline: Date?) -> Bool {
    guard let deadline else { return false }
    return Date() >= deadline
  }

  private func providers(in text: String) -> [String] {
    let lower = text.lowercased()
    var providers: [String] = []
    if lower.contains("api.openai.com") || lower.contains("openai") { providers.append("OpenAI") }
    if lower.contains("anthropic") || lower.contains("claude") { providers.append("Anthropic") }
    if lower.contains("generativelanguage.googleapis.com") || lower.contains("gemini") {
      providers.append("Gemini")
    }
    if lower.contains("deepseek") { providers.append("DeepSeek") }
    if lower.contains("ollama") || lower.contains("localhost:11434") { providers.append("Ollama") }
    if lower.contains("litellm") { providers.append("LiteLLM") }
    return providers.uniqueSorted()
  }

  private func commandScore(in text: String) -> Int {
    let lower = " \(text.lowercased()) "
    return ["bash", "python", "node", "git", "npm", "curl"].filter {
      lower.contains(" \($0) ") || lower.contains("/\($0) ")
    }.count
  }

  private func isLLMCommandLoop(arguments: String) -> Bool {
    let lower = arguments.lowercased()
    let hasLLMRequest =
      !providers(in: arguments).isEmpty
      || lower.contains("/v1/chat/completions")
      || lower.contains("/v1/responses")
      || lower.contains("/messages")
    let hasToolExecution = commandScore(in: arguments) > 0
    let hasToolSchema =
      lower.range(
        of: #"mcpservers|tools/list|function_call|tool_choice"#,
        options: [.regularExpression]) != nil
    let writesRuntimeTrace =
      lower.range(
        of: #"jsonl|sqlite|memory|conversation|history|tool_result|tool_call"#,
        options: [.regularExpression]) != nil
    return hasLLMRequest && (hasToolExecution || hasToolSchema || writesRuntimeTrace)
  }

  private func workspace(in text: String) -> String? {
    config.scanRoots.map(\.path).first { text.contains($0) }
  }

  private func hasAgentContext(_ workspace: URL) -> Bool {
    ["AGENTS.md", "CLAUDE.md", "GEMINI.md", ".mcp.json", "SKILL.md"].contains {
      DiscoveryUtilities.fileExists(workspace.appendingPathComponent($0))
    }
  }

  private func parentChain(for row: ProcessObservation, rowsByPID: [Int32: ProcessObservation])
    -> [String]
  {
    var chain: [String] = []
    var currentParent = row.ppid
    var seen: Set<Int32> = [row.pid]
    while currentParent > 0, !seen.contains(currentParent), chain.count < 8 {
      seen.insert(currentParent)
      guard let parent = rowsByPID[currentParent] else { break }
      chain.append(URL(fileURLWithPath: parent.command).lastPathComponent)
      currentParent = parent.ppid
    }
    return chain
  }
}

struct ProcessObservation: Hashable {
  var pid: Int32
  var ppid: Int32
  var command: String
  var arguments: String
  var bundleIdentifier: String?
  var bundlePath: String?
  var localizedName: String?

  init(
    pid: Int32,
    ppid: Int32,
    command: String,
    arguments: String,
    bundleIdentifier: String? = nil,
    bundlePath: String? = nil,
    localizedName: String? = nil
  ) {
    self.pid = pid
    self.ppid = ppid
    self.command = command
    self.arguments = arguments
    self.bundleIdentifier = bundleIdentifier
    self.bundlePath = bundlePath
    self.localizedName = localizedName
  }

  init?(line: String) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
    guard parts.count >= 3, let pidInt = Int32(parts[0]), let ppidInt = Int32(parts[1]) else {
      return nil
    }
    pid = pidInt
    ppid = ppidInt
    command = String(parts[2])
    arguments = parts.count >= 4 ? String(parts[3]) : command
    bundleIdentifier = nil
    bundlePath = nil
    localizedName = nil
  }
}

private struct ProcessMatch {
  var fingerprint: AgentFingerprint
  var installScope: ProcessInstallScope
}

private enum ProcessInstallScope {
  case none
  case direct
  case ancestor
}
