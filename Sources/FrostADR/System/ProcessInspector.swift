import Foundation

final class ProcessInspector {
  private let behaviorEngine: BehaviorFingerprintEngine
  private let config: DiscoveryConfiguration

  init(behaviorEngine: BehaviorFingerprintEngine, config: DiscoveryConfiguration) {
    self.behaviorEngine = behaviorEngine
    self.config = config
  }

  func inspectRunningProcesses() -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    for row in processRows() {
      let input = BehaviorFingerprintInput(
        processName: URL(fileURLWithPath: row.command).lastPathComponent,
        executablePath: row.command,
        argv: [row.arguments],
        cwd: nil,
        parentChain: [],
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
          of: #"jsonl|sqlite|memory|conversation"#, options: [.regularExpression, .caseInsensitive])
          != nil,
        observedLLMCommandLoop: false
      )
      let behavior = behaviorEngine.evaluate(input)
      guard behavior.score >= 40 else { continue }

      let runtime = RuntimeProcessAsset(
        pid: row.pid,
        ppid: row.ppid,
        processName: URL(fileURLWithPath: row.command).lastPathComponent,
        executablePath: row.command,
        argv: [DiscoveryUtilities.sanitizeArgument(row.arguments)],
        cwd: input.cwd,
        connectedLLMProviders: input.connectedLLMProviders,
        spawnedCommandCount: input.spawnedCommandCount,
        workspaceTouched: input.workspaceTouched,
        agentCandidateScore: behavior.score
      )
      result.runtimeProcesses.append(runtime)

      let agent = AgentAsset(
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

  private func processRows() -> [ProcessRow] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid=,comm=,args="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.components(separatedBy: .newlines).compactMap(ProcessRow.init(line:))
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
    [" bash ", " python ", " node ", " git ", " npm ", " curl "].filter {
      text.lowercased().contains($0)
    }.count
  }

  private func workspace(in text: String) -> String? {
    config.scanRoots.map(\.path).first { text.contains($0) }
  }

  private func hasAgentContext(_ workspace: URL) -> Bool {
    ["AGENTS.md", "CLAUDE.md", "GEMINI.md", ".mcp.json", "SKILL.md"].contains {
      DiscoveryUtilities.fileExists(workspace.appendingPathComponent($0))
    }
  }
}

private struct ProcessRow {
  var pid: Int32
  var ppid: Int32
  var command: String
  var arguments: String

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
  }
}
