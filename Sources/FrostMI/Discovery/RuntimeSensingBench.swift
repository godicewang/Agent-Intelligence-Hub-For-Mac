import Foundation

enum RuntimeSensingBench {
  static func run() -> Int32 {
    let failOnOpenGaps =
      CommandLine.arguments.contains("--target")
      || CommandLine.arguments.contains("--fail-on-gaps")
    let manifestURLs = runtimeManifestURLs()
    guard !manifestURLs.isEmpty else {
      print("FrostMI Runtime Sensing Bench failed: no runtime manifest.json files found.")
      return 1
    }

    let startedAt = Date()
    var rows: [RuntimeBenchRow] = []
    for manifestURL in manifestURLs {
      do {
        rows.append(try runFixture(manifestURL: manifestURL))
      } catch {
        rows.append(
          RuntimeBenchRow(
            id: manifestURL.deletingLastPathComponent().lastPathComponent,
            baseline: "unknown",
            passed: false,
            elapsedSeconds: 0,
            agents: 0,
            runtimeProcesses: 0,
            evidence: 0,
            contextFiles: 0,
            memoryAssets: 0,
            permissionStates: 0,
            runtimeEvents: 0,
            sessionGraphs: 0,
            sessionGraphEdges: 0,
            inputEvents: 0,
            sessions: 0,
            eventKinds: 0,
            openGaps: 0,
            resolvedGaps: 0,
            gapDetails: [],
            failures: [error.localizedDescription]))
      }
    }

    let passed = rows.filter(\.passed).count
    let failed = rows.count - passed
    let openGapCount = rows.map(\.openGaps).reduce(0, +)
    let targetFailed = failOnOpenGaps && openGapCount > 0
    print("FrostMI Runtime Sensing Bench")
    print("dataset=Tests/FrostMITests/Bench/runtime")
    print("mode=\(failOnOpenGaps ? "target" : "regression")")
    print(
      "fixtures=\(rows.count) passed=\(passed) failed=\(failed) elapsed=\(formatSeconds(Date().timeIntervalSince(startedAt)))s"
    )
    print(
      "totals inputEvents=\(rows.map(\.inputEvents).reduce(0, +)) sessions=\(rows.map(\.sessions).reduce(0, +)) runtimeEvents=\(rows.map(\.runtimeEvents).reduce(0, +)) sessionGraphs=\(rows.map(\.sessionGraphs).reduce(0, +)) graphEdges=\(rows.map(\.sessionGraphEdges).reduce(0, +)) agents=\(rows.map(\.agents).reduce(0, +)) runtimeProcesses=\(rows.map(\.runtimeProcesses).reduce(0, +)) evidence=\(rows.map(\.evidence).reduce(0, +)) context=\(rows.map(\.contextFiles).reduce(0, +)) memory=\(rows.map(\.memoryAssets).reduce(0, +)) permissionStates=\(rows.map(\.permissionStates).reduce(0, +)) resolvedCapabilityGaps=\(rows.map(\.resolvedGaps).reduce(0, +)) openCapabilityGaps=\(rows.map(\.openGaps).reduce(0, +))"
    )
    for row in rows {
      print(
        "- \(row.id) \(row.passed ? "PASS" : "FAIL") baseline=\(row.baseline) inputEvents=\(row.inputEvents) sessions=\(row.sessions) eventKinds=\(row.eventKinds) runtimeEvents=\(row.runtimeEvents) sessionGraphs=\(row.sessionGraphs) graphEdges=\(row.sessionGraphEdges) agents=\(row.agents) runtimeProcesses=\(row.runtimeProcesses) evidence=\(row.evidence) context=\(row.contextFiles) memory=\(row.memoryAssets) permissionStates=\(row.permissionStates) resolvedCapabilityGaps=\(row.resolvedGaps) openCapabilityGaps=\(row.openGaps) elapsed=\(formatSeconds(row.elapsedSeconds))s"
      )
      for failure in row.failures {
        print("  ! \(failure)")
      }
      for gap in row.gapDetails.prefix(4) {
        print("  ~ [gap] \(gap.capability): \(gap.reason)")
      }
      if row.gapDetails.count > 4 {
        print("  ~ ... \(row.gapDetails.count - 4) more open gaps")
      }
    }
    if targetFailed {
      print(
        "targetStatus=NEEDS_WORK openCapabilityGaps=\(openGapCount) regressionFailures=\(failed)")
    }
    return failed == 0 && !targetFailed ? 0 : 1
  }

  private static func runFixture(manifestURL: URL) throws -> RuntimeBenchRow {
    let startedAt = Date()
    let manifest = try JSONDecoder.frost.decode(
      RuntimeBenchManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let root = manifestURL.deletingLastPathComponent()
    let context = RuntimeBenchContext(root: root)
    let eventsURL = root.appendingPathComponent(manifest.input.events)
    let events = try loadEvents(from: eventsURL)
    let output = try snapshot(from: events, context: context)
    let snapshot = output.snapshot
    let failures = validationFailures(output: output, expected: manifest.expected)
    let assessment = RuntimeBenchAssessment(
      events: events,
      snapshot: snapshot,
      sessionGraphs: output.sessionGraphs
    )
    let openGaps = manifest.expected.knownGaps.filter { !assessment.resolves($0.capability) }

    return RuntimeBenchRow(
      id: manifest.id,
      baseline: manifest.baseline,
      passed: failures.isEmpty,
      elapsedSeconds: Date().timeIntervalSince(startedAt),
      agents: snapshot.agents.count,
      runtimeProcesses: snapshot.runtimeProcesses.count,
      evidence: snapshot.evidence.count,
      contextFiles: snapshot.contextFiles.count,
      memoryAssets: snapshot.memories.count,
      permissionStates: snapshot.permissionStates.count,
      runtimeEvents: output.runtimeEvents.count,
      sessionGraphs: output.sessionGraphs.count,
      sessionGraphEdges: output.sessionGraphs.map(\.edgeCount).reduce(0, +),
      inputEvents: events.count,
      sessions: Set(events.compactMap(\.sessionId)).count,
      eventKinds: Set(events.map(\.kind)).count,
      openGaps: openGaps.count,
      resolvedGaps: manifest.expected.knownGaps.count - openGaps.count,
      gapDetails: openGaps,
      failures: failures)
  }

  private static func snapshot(
    from events: [RuntimeBenchEvent],
    context: RuntimeBenchContext
  ) throws -> RuntimeBenchOutput {
    let registry = try FingerprintRegistry.bundled()
    let config = DiscoveryConfiguration(
      homeDirectory: context.home,
      projectRoot: context.project,
      scanRoots: [context.project],
      limits: .lightweightDefault,
      enableColdStartScan: false,
      enableRuntimeObserver: true,
      enableFSEventsWatcher: true,
      enableEndpointSecurityMonitor: false,
      enableNetworkMonitor: false,
      enableUserApplicationSupportScan: false
    )
    let processInspector = ProcessInspector(
      behaviorEngine: BehaviorFingerprintEngine(),
      config: config,
      registry: registry
    )

    let processRows = events.filter { $0.kind == .process }.map {
      ProcessObservation(
        pid: $0.pid ?? 0,
        ppid: $0.ppid ?? 1,
        command: context.expand($0.executablePath ?? "/usr/bin/\($0.processName ?? "agent")"),
        arguments: context.expand($0.argv ?? $0.processName ?? ""),
        bundleIdentifier: $0.bundleIdentifier,
        bundlePath: $0.bundlePath.map(context.expand),
        localizedName: $0.processName
      )
    }

    var result = processInspector.inspect(observations: processRows)
    if !processRows.isEmpty {
      result.events.append(
        DiscoveryEvent(
          id: DiscoveryEvent.runtimeProcessSnapshotId,
          kind: .processObservation,
          path: nil,
          message:
            "Runtime bench process snapshot inspected \(processRows.count) process observations and matched \(result.runtimeProcesses.count) agent-like runtime processes.",
          createdAt: events.map(\.timestampDate).min() ?? Date()
        ))
    }
    for event in events where event.kind != .process {
      merge(event: event, into: &result, context: context)
    }

    let storeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("FrostMIRuntimeBench-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("runtime.sqlite")
    let store = try AssetGraphStore(database: FrostDatabase(url: storeURL))
    let snapshot = try store.merge(result)
    let runtimeEvents = events.map { runtimeEvent(from: $0, context: context) }
    let sessionGraphs = try store.appendRuntimeEvents(runtimeEvents)
    return RuntimeBenchOutput(
      snapshot: snapshot,
      runtimeEvents: runtimeEvents,
      sessionGraphs: sessionGraphs
    )
  }

  private static func runtimeEvent(
    from event: RuntimeBenchEvent,
    context: RuntimeBenchContext
  ) -> RuntimeEventRecord {
    RuntimeEventRecord(
      sessionId: event.sessionId
        ?? RuntimeEventRecord.localSessionId(prefix: "runtime-bench", timestamp: event.timestampDate),
      agentName: event.agent,
      kind: event.runtimeEventKind,
      timestamp: event.timestampDate,
      source: event.source ?? "runtime-bench",
      processId: event.pid,
      parentProcessId: event.ppid,
      path: event.path.map(context.expand),
      url: event.url,
      method: event.kind == .toolCall ? "tools/call" : nil,
      toolName: event.toolName,
      provider: event.provider,
      message: event.message,
      riskSignal: event.riskSignal,
      untrusted: event.untrusted ?? false,
      correlationKey: event.sessionId,
      metadata: [
        "benchKind": event.kind.rawValue
      ]
    )
  }

  private static func merge(
    event: RuntimeBenchEvent,
    into result: inout DiscoveryScanResult,
    context: RuntimeBenchContext
  ) {
    let agentId = result.agents.first { $0.normalizedName == event.agent }?.id
    let eventDate = event.timestampDate
    let expandedPath = event.path.map(context.expand)
    switch event.kind {
    case .llmRequest:
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: .behavior,
          source: event.source ?? "runtime-bench",
          processId: event.pid,
          confidenceDelta: 20,
          summary: "LLM request observed for \(event.provider ?? "unknown provider")",
          observedAt: eventDate,
          rawKey: event.sessionId
        ))
    case .toolCall:
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: .behavior,
          source: event.source ?? "runtime-bench",
          processId: event.pid,
          confidenceDelta: event.riskSignal == nil ? 15 : 35,
          summary: "Tool call observed: \(event.toolName ?? "unknown")",
          observedAt: eventDate,
          rawKey: event.sessionId
        ))
    case .toolResult:
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: event.untrusted == true ? .keyword : .behavior,
          source: event.source ?? "runtime-bench",
          processId: event.pid,
          confidenceDelta: event.untrusted == true ? 35 : 10,
          summary: event.untrusted == true
            ? "Untrusted tool result observed: \(event.message ?? "runtime result")"
            : "Tool result observed: \(event.toolName ?? "unknown")",
          observedAt: eventDate,
          rawKey: event.sessionId
        ))
    case .fileEvent:
      if let expandedPath {
        if isContextPath(expandedPath) {
          result.contextFiles.append(
            ContextFileAsset(
              path: expandedPath,
              workspace: context.project.path,
              detectedAgent: event.agent,
              keywordHits: ["runtime"],
              hash: "runtime-\(expandedPath.hashValue.magnitude)",
              discoveredAt: eventDate,
              lastModifiedAt: eventDate
            ))
        }
        if isMemoryPath(expandedPath) {
          result.memories.append(
            MemoryAsset(
              id: UUID(),
              path: expandedPath,
              format: expandedPath.hasSuffix(".jsonl") ? .jsonl : .unknown,
              sourceAgentId: agentId,
              estimatedRecordCount: nil,
              containsToolHistory: true,
              containsConversationHistory: true,
              containsProceduralMemory: false,
              lastModifiedAt: eventDate,
              privacySensitivity: .medium
            ))
        }
      }
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: isMemoryPath(expandedPath ?? "") ? .memoryFile : .contextFile,
          source: event.source ?? "runtime-bench",
          path: expandedPath,
          processId: event.pid,
          confidenceDelta: 20,
          summary: "Runtime file event observed",
          observedAt: eventDate,
          rawKey: event.sessionId
        ))
    case .networkEvent:
      let isRealFlow = event.source == "macos-lsof-network-flow"
        || event.source == "network-extension-flow"
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: .behavior,
          source: event.source ?? "runtime-bench",
          processId: event.pid,
          confidenceDelta: isRealFlow ? 30 : 20,
          summary: isRealFlow
            ? "Real network flow observed: \(event.url ?? "unknown")"
            : "Network destination observed: \(event.url ?? "unknown")",
          observedAt: eventDate,
          rawKey: event.sessionId
        ))
    case .permissionState:
      if let capability = DiscoveryCapability(rawValue: event.capability ?? ""),
        let status = PermissionStatus(rawValue: event.status ?? "")
      {
        result.permissionStates.append(
          DiscoveryPermissionState(
            id: UUID(),
            capability: capability,
            status: status,
            message: event.message ?? "Runtime bench permission state",
            checkedAt: eventDate
          ))
      }
    case .process:
      break
    }

    result.events.append(
      DiscoveryEvent(
        id: UUID(),
        kind: event.discoveryEventKind,
        path: expandedPath,
        message: event.message ?? event.kind.rawValue,
        createdAt: eventDate
      ))
  }

  private static func validationFailures(
    output: RuntimeBenchOutput,
    expected: RuntimeBenchExpected
  ) -> [String] {
    let snapshot = output.snapshot
    var failures: [String] = []
    let agentNamesById = Dictionary(
      uniqueKeysWithValues: snapshot.agents.map {
        ($0.id, $0.normalizedName)
      })

    for expectedAgent in expected.agents {
      let matches = snapshot.agents.filter { $0.normalizedName == expectedAgent.normalizedName }
      if matches.isEmpty {
        failures.append("expected agent \(expectedAgent.normalizedName)")
        continue
      }
      if let minConfidence = expectedAgent.minConfidence,
        !matches.contains(where: { $0.confidence >= minConfidence })
      {
        failures.append(
          "expected agent \(expectedAgent.normalizedName) confidence >= \(minConfidence)")
      }
      if let runtimeStatus = expectedAgent.runtimeStatus,
        !matches.contains(where: { $0.runtimeStatus.rawValue == runtimeStatus })
      {
        failures.append(
          "expected agent \(expectedAgent.normalizedName) runtimeStatus \(runtimeStatus)")
      }
    }

    for absentAgent in expected.absentAgents
    where snapshot.agents.contains(where: { $0.normalizedName == absentAgent }) {
      failures.append("expected agent \(absentAgent) to be absent")
    }

    if !expected.allowExtraAgents {
      let expectedAgentNames = Set(expected.agents.map(\.normalizedName))
      let actualAgentNames = Set(snapshot.agents.map(\.normalizedName))
      for extraAgent in actualAgentNames.subtracting(expectedAgentNames).sorted() {
        failures.append("unexpected agent \(extraAgent)")
      }
    }

    if snapshot.runtimeProcesses.count < expected.runtimeProcessesMinCount {
      failures.append(
        "expected runtimeProcesses >= \(expected.runtimeProcessesMinCount), got \(snapshot.runtimeProcesses.count)"
      )
    }
    if snapshot.evidence.count < expected.evidenceMinCount {
      failures.append(
        "expected evidence >= \(expected.evidenceMinCount), got \(snapshot.evidence.count)")
    }
    if let exactCounts = expected.exactCounts {
      failures.append(contentsOf: exactCountFailures(snapshot: snapshot, exactCounts: exactCounts))
    }
    if output.runtimeEvents.count < expected.runtimeEventsMinCount {
      failures.append(
        "expected runtimeEvents >= \(expected.runtimeEventsMinCount), got \(output.runtimeEvents.count)"
      )
    }
    if output.sessionGraphs.map(\.edgeCount).reduce(0, +) < expected.sessionGraphEdgesMinCount {
      failures.append(
        "expected sessionGraphEdges >= \(expected.sessionGraphEdgesMinCount), got \(output.sessionGraphs.map(\.edgeCount).reduce(0, +))"
      )
    }
    failures.append(contentsOf: sessionGraphFailures(output: output))

    failures.append(
      contentsOf: duplicateFailures(
        label: "agent normalized name", values: snapshot.agents.map(\.normalizedName)))
    failures.append(
      contentsOf: duplicateFailures(
        label: "runtime pid", values: snapshot.runtimeProcesses.map { String($0.pid) }))
    failures.append(
      contentsOf: duplicateFailures(
        label: "context path", values: snapshot.contextFiles.map(\.path)))
    failures.append(
      contentsOf: duplicateFailures(
        label: "memory path", values: snapshot.memories.map(\.path)))

    for path in expected.contextFiles {
      if !snapshot.contextFiles.map(\.path).contains(where: { $0.hasSuffix(path) || $0 == path }) {
        failures.append("expected context path \(path)")
      }
    }
    for path in expected.memoryAssets {
      if !snapshot.memories.map(\.path).contains(where: { $0.hasSuffix(path) || $0 == path }) {
        failures.append("expected memory path \(path)")
      }
    }
    for permission in expected.permissionStates {
      if !snapshot.permissionStates.contains(where: {
        $0.capability.rawValue == permission.capability && $0.status.rawValue == permission.status
      }) {
        failures.append("expected permission \(permission.capability)=\(permission.status)")
      }
    }
    for eventKind in expected.requiredEventKinds {
      if !snapshot.events.contains(where: { $0.kind.rawValue == eventKind }) {
        failures.append("expected event kind \(eventKind)")
      }
    }
    for summary in expected.requiredEvidenceSummaries {
      if !snapshot.evidence.contains(where: { $0.summary.localizedCaseInsensitiveContains(summary) }
      ) {
        failures.append("expected evidence summary containing \(summary)")
      }
    }
    for expectedProcess in expected.runtimeProcesses {
      if !runtimeProcessExists(
        expectedProcess,
        in: snapshot.runtimeProcesses,
        agentNamesById: agentNamesById)
      {
        failures.append("expected runtime process \(expectedProcess.describe())")
      }
    }
    for expectedEvidence in expected.requiredEvidence {
      if !evidenceExists(
        expectedEvidence,
        in: snapshot.evidence,
        agentNamesById: agentNamesById)
      {
        failures.append("expected runtime evidence \(expectedEvidence.describe())")
      }
    }
    if expected.requireLinkedEvidence {
      for evidence in snapshot.evidence where evidence.assetId == nil {
        failures.append("expected evidence \(evidence.summary) to be linked to an agent")
      }
      for runtimeProcess in snapshot.runtimeProcesses where runtimeProcess.sourceAgentId == nil {
        failures.append(
          "expected runtime process \(runtimeProcess.processName) to be linked to an agent")
      }
    }
    return failures
  }

  private static func sessionGraphFailures(output: RuntimeBenchOutput) -> [String] {
    let groupedEvents = Dictionary(grouping: output.runtimeEvents, by: \.sessionId)
    var failures: [String] = []
    for (sessionId, events) in groupedEvents {
      guard let graph = output.sessionGraphs.first(where: { $0.sessionId == sessionId }) else {
        failures.append("expected session graph for \(sessionId)")
        continue
      }
      if graph.nodeCount != events.count {
        failures.append(
          "expected session graph \(sessionId) nodes=\(events.count), got \(graph.nodeCount)")
      }
      let expectedEdges = max(0, events.count - 1)
      if graph.edgeCount != expectedEdges {
        failures.append(
          "expected session graph \(sessionId) edges=\(expectedEdges), got \(graph.edgeCount)")
      }
    }
    return failures
  }

  private static func exactCountFailures(
    snapshot: DiscoverySnapshot,
    exactCounts: RuntimeBenchExactCounts
  ) -> [String] {
    [
      ("agents", exactCounts.agents, snapshot.agents.count),
      ("runtimeProcesses", exactCounts.runtimeProcesses, snapshot.runtimeProcesses.count),
      ("evidence", exactCounts.evidence, snapshot.evidence.count),
      ("contextFiles", exactCounts.contextFiles, snapshot.contextFiles.count),
      ("memoryAssets", exactCounts.memoryAssets, snapshot.memories.count),
      ("permissionStates", exactCounts.permissionStates, snapshot.permissionStates.count),
    ].compactMap { label, expected, actual in
      guard let expected, expected != actual else { return nil }
      return "expected exact \(label)=\(expected), got \(actual)"
    }
  }

  private static func duplicateFailures(label: String, values: [String]) -> [String] {
    Dictionary(grouping: values, by: { $0 })
      .filter { $0.value.count > 1 }
      .keys
      .sorted()
      .map { "unexpected duplicate \(label) \($0)" }
  }

  private static func runtimeProcessExists(
    _ expectedProcess: ExpectedRuntimeProcess,
    in runtimeProcesses: [RuntimeProcessAsset],
    agentNamesById: [UUID: String]
  ) -> Bool {
    runtimeProcesses.contains { runtimeProcess in
      if let agent = expectedProcess.agent {
        guard let sourceAgentId = runtimeProcess.sourceAgentId,
          agentNamesById[sourceAgentId] == agent
        else { return false }
      }
      if let processName = expectedProcess.processName,
        runtimeProcess.processName != processName
      {
        return false
      }
      if let minScore = expectedProcess.minScore,
        runtimeProcess.agentCandidateScore < minScore
      {
        return false
      }
      if let workspaceSuffix = expectedProcess.workspaceSuffix,
        !(runtimeProcess.workspaceTouched?.hasSuffix(workspaceSuffix) ?? false)
      {
        return false
      }
      if !Set(expectedProcess.providers).isSubset(of: Set(runtimeProcess.connectedLLMProviders)) {
        return false
      }
      return true
    }
  }

  private static func evidenceExists(
    _ expectedEvidence: ExpectedRuntimeEvidence,
    in evidence: [DiscoveryEvidence],
    agentNamesById: [UUID: String]
  ) -> Bool {
    evidence.contains { item in
      if let agent = expectedEvidence.agent {
        guard let assetId = item.assetId, agentNamesById[assetId] == agent else { return false }
      }
      if let type = expectedEvidence.type,
        item.evidenceType.rawValue != type
      {
        return false
      }
      if let source = expectedEvidence.source,
        item.source != source
      {
        return false
      }
      if let processId = expectedEvidence.processId,
        item.processId != processId
      {
        return false
      }
      if let pathSuffix = expectedEvidence.pathSuffix,
        !(item.path?.hasSuffix(pathSuffix) ?? false)
      {
        return false
      }
      if let summaryContains = expectedEvidence.summaryContains,
        !item.summary.localizedCaseInsensitiveContains(summaryContains)
      {
        return false
      }
      return true
    }
  }

  private static func loadEvents(from url: URL) throws -> [RuntimeBenchEvent] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text.split(separator: "\n").map { line in
      try JSONDecoder.frost.decode(RuntimeBenchEvent.self, from: Data(line.utf8))
    }
  }

  private static func runtimeManifestURLs() -> [URL] {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Tests/FrostMITests/Bench/runtime", isDirectory: true)
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { $0 as? URL }
      .filter { $0.lastPathComponent == "manifest.json" }
      .sorted { $0.path < $1.path }
  }

  private static func isContextPath(_ path: String) -> Bool {
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return ["agents.md", "claude.md", "gemini.md", "settings.json", "mcp.json"].contains(name)
      || path.lowercased().contains("/.cursor/rules/")
  }

  private static func isMemoryPath(_ path: String) -> Bool {
    let lower = path.lowercased()
    return lower.contains("memory") || lower.contains("session") || lower.contains("conversation")
      || lower.contains("history")
  }

  private static func formatSeconds(_ value: TimeInterval) -> String {
    String(format: "%.3f", value)
  }
}

private struct RuntimeBenchContext {
  let root: URL
  var home: URL { root.appendingPathComponent("home", isDirectory: true) }
  var project: URL { root.appendingPathComponent("project", isDirectory: true) }

  func expand(_ value: String) -> String {
    value
      .replacingOccurrences(of: "{ROOT}", with: root.path)
      .replacingOccurrences(of: "{HOME}", with: home.path)
      .replacingOccurrences(of: "{PROJECT}", with: project.path)
  }
}

private struct RuntimeBenchRow {
  var id: String
  var baseline: String
  var passed: Bool
  var elapsedSeconds: TimeInterval
  var agents: Int
  var runtimeProcesses: Int
  var evidence: Int
  var contextFiles: Int
  var memoryAssets: Int
  var permissionStates: Int
  var runtimeEvents: Int
  var sessionGraphs: Int
  var sessionGraphEdges: Int
  var inputEvents: Int
  var sessions: Int
  var eventKinds: Int
  var openGaps: Int
  var resolvedGaps: Int
  var gapDetails: [ExpectedRuntimeGap]
  var failures: [String]
}

private struct RuntimeBenchOutput {
  var snapshot: DiscoverySnapshot
  var runtimeEvents: [RuntimeEventRecord]
  var sessionGraphs: [RuntimeSessionGraph]
}

private struct RuntimeBenchAssessment {
  var events: [RuntimeBenchEvent]
  var snapshot: DiscoverySnapshot
  var sessionGraphs: [RuntimeSessionGraph]

  private var sortedEvents: [RuntimeBenchEvent] {
    events.sorted { $0.timestampDate < $1.timestampDate }
  }

  func resolves(_ capability: String) -> Bool {
    switch capability {
    case "session_graph_edges":
      hasSessionGraphEdges
    case "turn_order_reconstruction":
      hasTurnOrderReconstruction
    case "cross_agent_session_correlation":
      hasCrossAgentSessionCorrelation
    case "taint_propagation":
      hasTaintPropagation
    case "tool_call_policy_verdict", "runtime_policy_action":
      hasDeterministicPolicyVerdict
    case "attack_goal_separation":
      hasAttackGoalSeparation
    case "degraded_mode_explanation":
      hasDegradedModeExplanation
    case "real_network_flow_capture":
      hasRealNetworkFlowCapture
    case "network_extension_flow_detail":
      hasNetworkExtensionFlowDetail
    case "endpoint_security_auth_events":
      hasEndpointSecurityAuthEvents
    default:
      false
    }
  }

  private var sessions: [[RuntimeBenchEvent]] {
    Dictionary(grouping: sortedEvents.filter { $0.sessionId != nil }, by: { $0.sessionId ?? "" })
      .values
      .map { $0.sorted { $0.timestampDate < $1.timestampDate } }
  }

  private var hasSessionGraphEdges: Bool {
    sessionGraphs.contains { $0.edgeCount > 0 }
  }

  private var hasTurnOrderReconstruction: Bool {
    sessions.contains { sessionEvents in
      hasOrderedKinds([.llmRequest, .toolCall, .toolResult], in: sessionEvents)
    }
  }

  private var hasCrossAgentSessionCorrelation: Bool {
    let sessionAgents = sessions.compactMap { sessionEvents in
      sessionEvents.compactMap(\.agent).first
    }
    guard Set(sessionAgents).count > 1, sessions.count > 1 else { return false }
    return events.contains { event in
      event.path?.contains("{PROJECT}") == true || event.argv?.contains("{PROJECT}") == true
    }
  }

  private var hasTaintPropagation: Bool {
    sessions.contains { sessionEvents in
      var tainted = false
      for event in sessionEvents {
        if tainted, [.llmRequest, .toolCall, .networkEvent].contains(event.kind) {
          return true
        }
        if event.untrusted == true
          || event.riskSignal?.localizedCaseInsensitiveContains("prompt")
            == true
        {
          tainted = true
        }
      }
      return false
    }
  }

  private var hasDeterministicPolicyVerdict: Bool {
    sessions.contains { sessionEvents in
      var tainted = false
      for event in sessionEvents {
        if tainted,
          event.kind == .toolCall || event.kind == .networkEvent,
          isRiskyRuntimeAction(event)
        {
          return true
        }
        if event.riskSignal != nil, event.kind == .toolCall {
          return true
        }
        if event.untrusted == true
          || event.riskSignal?.localizedCaseInsensitiveContains("prompt")
            == true
        {
          tainted = true
        }
      }
      return false
    }
  }

  private var hasAttackGoalSeparation: Bool {
    sessions.contains { sessionEvents in
      let hasUserGoal = sessionEvents.contains {
        $0.kind == .llmRequest && !($0.message ?? "").isEmpty
      }
      let hasAttackerGoal = sessionEvents.contains {
        $0.untrusted == true
          && (($0.message ?? "").localizedCaseInsensitiveContains("ignore")
            || $0.riskSignal?.localizedCaseInsensitiveContains("prompt") == true)
      }
      return hasUserGoal && hasAttackerGoal
    }
  }

  private var hasDegradedModeExplanation: Bool {
    let statuses = Dictionary(
      uniqueKeysWithValues: snapshot.permissionStates.map {
        ($0.capability, $0.status)
      })
    let hasAvailableFallback = statuses[.fileSystemEvents] == .available
    let hasMissingRuntimeEntitlement =
      statuses[.endpointSecurity] == .missingEntitlement
      || statuses[.networkExtension] == .missingEntitlement
    return hasAvailableFallback && hasMissingRuntimeEntitlement
  }

  private var hasRealNetworkFlowCapture: Bool {
    events.contains {
      $0.kind == .networkEvent
        && $0.url != nil
        && ($0.source == "macos-lsof-network-flow" || $0.source == "network-extension-flow")
    }
  }

  private var hasNetworkExtensionFlowDetail: Bool {
    snapshot.permissionStates.contains {
      $0.capability == .networkExtension && $0.status == .available
    } && events.contains {
      $0.kind == .networkEvent && $0.url != nil && $0.source == "network-extension-flow"
    }
  }

  private var hasEndpointSecurityAuthEvents: Bool {
    snapshot.permissionStates.contains {
      $0.capability == .endpointSecurity && $0.status == .available
    } && events.contains {
      [.process, .fileEvent].contains($0.kind) && $0.source == "endpoint-security-auth"
    }
  }

  private func hasOrderedKinds(
    _ requiredKinds: [RuntimeBenchEventKind],
    in events: [RuntimeBenchEvent]
  ) -> Bool {
    var index = 0
    for event in events where index < requiredKinds.count {
      if event.kind == requiredKinds[index] {
        index += 1
      }
    }
    return index == requiredKinds.count
  }

  private func isRiskyRuntimeAction(_ event: RuntimeBenchEvent) -> Bool {
    event.riskSignal != nil
      || event.url?.localizedCaseInsensitiveContains("attacker") == true
      || event.message?.localizedCaseInsensitiveContains("secret") == true
      || event.toolName?.localizedCaseInsensitiveContains("shell") == true
  }
}

private struct RuntimeBenchManifest: Decodable {
  var id: String
  var baseline: String
  var reference: String
  var license: String
  var focus: String
  var input: RuntimeBenchInput
  var expected: RuntimeBenchExpected
}

private struct RuntimeBenchInput: Decodable {
  var events: String
}

private struct RuntimeBenchExpected: Decodable {
  var agents: [ExpectedRuntimeAgent] = []
  var absentAgents: [String] = []
  var allowExtraAgents: Bool = false
  var runtimeProcessesMinCount: Int = 0
  var evidenceMinCount: Int = 0
  var runtimeEventsMinCount: Int = 0
  var sessionGraphEdgesMinCount: Int = 0
  var exactCounts: RuntimeBenchExactCounts?
  var contextFiles: [String] = []
  var memoryAssets: [String] = []
  var permissionStates: [ExpectedPermissionState] = []
  var requiredEventKinds: [String] = []
  var requiredEvidenceSummaries: [String] = []
  var runtimeProcesses: [ExpectedRuntimeProcess] = []
  var requiredEvidence: [ExpectedRuntimeEvidence] = []
  var requireLinkedEvidence: Bool = false
  var knownGaps: [ExpectedRuntimeGap] = []

  private enum CodingKeys: String, CodingKey {
    case agents
    case absentAgents
    case allowExtraAgents
    case runtimeProcessesMinCount
    case evidenceMinCount
    case runtimeEventsMinCount
    case sessionGraphEdgesMinCount
    case exactCounts
    case contextFiles
    case memoryAssets
    case permissionStates
    case requiredEventKinds
    case requiredEvidenceSummaries
    case runtimeProcesses
    case requiredEvidence
    case requireLinkedEvidence
    case knownGaps
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    agents = try container.decodeIfPresent([ExpectedRuntimeAgent].self, forKey: .agents) ?? []
    absentAgents = try container.decodeIfPresent([String].self, forKey: .absentAgents) ?? []
    allowExtraAgents = try container.decodeIfPresent(Bool.self, forKey: .allowExtraAgents) ?? false
    runtimeProcessesMinCount =
      try container.decodeIfPresent(Int.self, forKey: .runtimeProcessesMinCount) ?? 0
    evidenceMinCount = try container.decodeIfPresent(Int.self, forKey: .evidenceMinCount) ?? 0
    runtimeEventsMinCount =
      try container.decodeIfPresent(Int.self, forKey: .runtimeEventsMinCount) ?? 0
    sessionGraphEdgesMinCount =
      try container.decodeIfPresent(Int.self, forKey: .sessionGraphEdgesMinCount) ?? 0
    exactCounts =
      try container.decodeIfPresent(RuntimeBenchExactCounts.self, forKey: .exactCounts)
    contextFiles = try container.decodeIfPresent([String].self, forKey: .contextFiles) ?? []
    memoryAssets = try container.decodeIfPresent([String].self, forKey: .memoryAssets) ?? []
    permissionStates =
      try container.decodeIfPresent([ExpectedPermissionState].self, forKey: .permissionStates)
      ?? []
    requiredEventKinds =
      try container.decodeIfPresent([String].self, forKey: .requiredEventKinds) ?? []
    requiredEvidenceSummaries =
      try container.decodeIfPresent([String].self, forKey: .requiredEvidenceSummaries) ?? []
    runtimeProcesses =
      try container.decodeIfPresent([ExpectedRuntimeProcess].self, forKey: .runtimeProcesses) ?? []
    requiredEvidence =
      try container.decodeIfPresent([ExpectedRuntimeEvidence].self, forKey: .requiredEvidence) ?? []
    requireLinkedEvidence =
      try container.decodeIfPresent(Bool.self, forKey: .requireLinkedEvidence) ?? false
    knownGaps =
      try container.decodeIfPresent([ExpectedRuntimeGap].self, forKey: .knownGaps) ?? []
  }
}

private struct RuntimeBenchExactCounts: Decodable {
  var agents: Int?
  var runtimeProcesses: Int?
  var evidence: Int?
  var contextFiles: Int?
  var memoryAssets: Int?
  var permissionStates: Int?
}

private struct ExpectedRuntimeAgent: Decodable {
  var normalizedName: String
  var minConfidence: Int?
  var runtimeStatus: String?
}

private struct ExpectedRuntimeProcess: Decodable {
  var agent: String?
  var processName: String?
  var minScore: Int?
  var providers: [String] = []
  var workspaceSuffix: String?

  private enum CodingKeys: String, CodingKey {
    case agent
    case processName
    case minScore
    case providers
    case workspaceSuffix
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    agent = try container.decodeIfPresent(String.self, forKey: .agent)
    processName = try container.decodeIfPresent(String.self, forKey: .processName)
    minScore = try container.decodeIfPresent(Int.self, forKey: .minScore)
    providers = try container.decodeIfPresent([String].self, forKey: .providers) ?? []
    workspaceSuffix = try container.decodeIfPresent(String.self, forKey: .workspaceSuffix)
  }

  func describe() -> String {
    [
      agent.map { "agent=\($0)" },
      processName.map { "processName=\($0)" },
      minScore.map { "minScore=\($0)" },
    ].compactMap { $0 }.joined(separator: " ")
  }
}

private struct ExpectedRuntimeEvidence: Decodable {
  var agent: String?
  var type: String?
  var source: String?
  var processId: Int32?
  var pathSuffix: String?
  var summaryContains: String?

  func describe() -> String {
    [
      agent.map { "agent=\($0)" },
      type.map { "type=\($0)" },
      source.map { "source=\($0)" },
      processId.map { "processId=\($0)" },
      pathSuffix.map { "pathSuffix=\($0)" },
      summaryContains.map { "summaryContains=\($0)" },
    ].compactMap { $0 }.joined(separator: " ")
  }
}

private struct ExpectedPermissionState: Decodable {
  var capability: String
  var status: String
}

private struct ExpectedRuntimeGap: Decodable {
  var capability: String
  var reason: String
}

private struct RuntimeBenchEvent: Decodable {
  var timestamp: String?
  var kind: RuntimeBenchEventKind
  var source: String?
  var agent: String?
  var sessionId: String?
  var pid: Int32?
  var ppid: Int32?
  var processName: String?
  var executablePath: String?
  var bundleIdentifier: String?
  var bundlePath: String?
  var argv: String?
  var cwd: String?
  var provider: String?
  var toolName: String?
  var path: String?
  var url: String?
  var message: String?
  var riskSignal: String?
  var untrusted: Bool?
  var capability: String?
  var status: String?

  var timestampDate: Date {
    guard let timestamp else { return Date(timeIntervalSince1970: 0) }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: timestamp) else { return Date(timeIntervalSince1970: 0) }
    return date
  }

  var discoveryEventKind: DiscoveryEventKind {
    switch kind {
    case .fileEvent:
      .fileSystemChange
    case .networkEvent:
      .networkFlow
    case .permissionState:
      .permissionState
    default:
      .processObservation
    }
  }

  var runtimeEventKind: RuntimeEventKind {
    switch kind {
    case .process:
      .processObservation
    case .llmRequest:
      .llmRequest
    case .toolCall:
      .toolCall
    case .toolResult:
      .toolResult
    case .fileEvent:
      isMemoryLikePath ? .memoryWrite : .fileEvent
    case .networkEvent:
      .networkEvent
    case .permissionState:
      .permissionState
    }
  }

  private var isMemoryLikePath: Bool {
    guard let path else { return false }
    let lower = path.lowercased()
    return lower.contains("memory") || lower.contains("session") || lower.contains("conversation")
      || lower.contains("history")
  }
}

private enum RuntimeBenchEventKind: String, Decodable, Hashable {
  case process
  case llmRequest
  case toolCall
  case toolResult
  case fileEvent
  case networkEvent
  case permissionState

  var graphOrder: Int {
    switch self {
    case .process:
      0
    case .llmRequest:
      1
    case .toolCall:
      2
    case .fileEvent, .networkEvent:
      3
    case .toolResult:
      4
    case .permissionState:
      5
    }
  }
}
