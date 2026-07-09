import Foundation

enum RuntimeSensingBench {
  static func run() -> Int32 {
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
            knownGaps: 0,
            failures: [error.localizedDescription]))
      }
    }

    let passed = rows.filter(\.passed).count
    let failed = rows.count - passed
    print("FrostMI Runtime Sensing Bench")
    print("dataset=Tests/FrostMITests/Bench/runtime")
    print(
      "fixtures=\(rows.count) passed=\(passed) failed=\(failed) elapsed=\(formatSeconds(Date().timeIntervalSince(startedAt)))s"
    )
    print(
      "totals agents=\(rows.map(\.agents).reduce(0, +)) runtimeProcesses=\(rows.map(\.runtimeProcesses).reduce(0, +)) evidence=\(rows.map(\.evidence).reduce(0, +)) context=\(rows.map(\.contextFiles).reduce(0, +)) memory=\(rows.map(\.memoryAssets).reduce(0, +)) permissionStates=\(rows.map(\.permissionStates).reduce(0, +)) knownGaps=\(rows.map(\.knownGaps).reduce(0, +))"
    )
    for row in rows {
      print(
        "- \(row.id) \(row.passed ? "PASS" : "FAIL") baseline=\(row.baseline) agents=\(row.agents) runtimeProcesses=\(row.runtimeProcesses) evidence=\(row.evidence) context=\(row.contextFiles) memory=\(row.memoryAssets) permissionStates=\(row.permissionStates) knownGaps=\(row.knownGaps) elapsed=\(formatSeconds(row.elapsedSeconds))s"
      )
      for failure in row.failures {
        print("  ! \(failure)")
      }
    }
    return failed == 0 ? 0 : 1
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
    let snapshot = try snapshot(from: events, context: context)
    let failures = validationFailures(snapshot: snapshot, expected: manifest.expected)

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
      knownGaps: manifest.expected.knownGaps.count,
      failures: failures)
  }

  private static func snapshot(
    from events: [RuntimeBenchEvent],
    context: RuntimeBenchContext
  ) throws -> DiscoverySnapshot {
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
    for event in events where event.kind != .process {
      merge(event: event, into: &result, context: context)
    }

    let storeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("FrostMIRuntimeBench-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("runtime.sqlite")
    let store = try AssetGraphStore(database: FrostDatabase(url: storeURL))
    return try store.merge(result)
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
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agentId,
          evidenceType: .behavior,
          source: event.source ?? "runtime-bench",
          processId: event.pid,
          confidenceDelta: 20,
          summary: "Network destination observed: \(event.url ?? "unknown")",
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
    snapshot: DiscoverySnapshot,
    expected: RuntimeBenchExpected
  ) -> [String] {
    var failures: [String] = []
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

    if snapshot.runtimeProcesses.count < expected.runtimeProcessesMinCount {
      failures.append(
        "expected runtimeProcesses >= \(expected.runtimeProcessesMinCount), got \(snapshot.runtimeProcesses.count)"
      )
    }
    if snapshot.evidence.count < expected.evidenceMinCount {
      failures.append(
        "expected evidence >= \(expected.evidenceMinCount), got \(snapshot.evidence.count)")
    }
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
    return failures
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
  var knownGaps: Int
  var failures: [String]
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
  var runtimeProcessesMinCount: Int = 0
  var evidenceMinCount: Int = 0
  var contextFiles: [String] = []
  var memoryAssets: [String] = []
  var permissionStates: [ExpectedPermissionState] = []
  var requiredEventKinds: [String] = []
  var requiredEvidenceSummaries: [String] = []
  var knownGaps: [ExpectedRuntimeGap] = []

  private enum CodingKeys: String, CodingKey {
    case agents
    case runtimeProcessesMinCount
    case evidenceMinCount
    case contextFiles
    case memoryAssets
    case permissionStates
    case requiredEventKinds
    case requiredEvidenceSummaries
    case knownGaps
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    agents = try container.decodeIfPresent([ExpectedRuntimeAgent].self, forKey: .agents) ?? []
    runtimeProcessesMinCount =
      try container.decodeIfPresent(Int.self, forKey: .runtimeProcessesMinCount) ?? 0
    evidenceMinCount = try container.decodeIfPresent(Int.self, forKey: .evidenceMinCount) ?? 0
    contextFiles = try container.decodeIfPresent([String].self, forKey: .contextFiles) ?? []
    memoryAssets = try container.decodeIfPresent([String].self, forKey: .memoryAssets) ?? []
    permissionStates =
      try container.decodeIfPresent([ExpectedPermissionState].self, forKey: .permissionStates)
      ?? []
    requiredEventKinds =
      try container.decodeIfPresent([String].self, forKey: .requiredEventKinds) ?? []
    requiredEvidenceSummaries =
      try container.decodeIfPresent([String].self, forKey: .requiredEvidenceSummaries) ?? []
    knownGaps =
      try container.decodeIfPresent([ExpectedRuntimeGap].self, forKey: .knownGaps) ?? []
  }
}

private struct ExpectedRuntimeAgent: Decodable {
  var normalizedName: String
  var minConfidence: Int?
  var runtimeStatus: String?
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
    case .permissionState:
      .permissionState
    default:
      .processObservation
    }
  }
}

private enum RuntimeBenchEventKind: String, Decodable {
  case process
  case llmRequest
  case toolCall
  case toolResult
  case fileEvent
  case networkEvent
  case permissionState
}
