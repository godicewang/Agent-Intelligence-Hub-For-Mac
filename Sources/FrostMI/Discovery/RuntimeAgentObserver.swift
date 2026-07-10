import Foundation

final class RuntimeAgentObserver: @unchecked Sendable {
  private static let fileSystemProcessingQueue = DispatchQueue(
    label: "frostadr.fsevents.processing",
    qos: .utility
  )
  private static let fileSystemBatchWindow: TimeInterval = 1.2
  private static let networkEvidenceInterval: TimeInterval = 300

  private let keywordScanner: KeywordFileScanner
  private let processInspector: ProcessInspector
  private let endpointSecurityMonitor: EndpointSecurityMonitor
  private let networkFlowMonitor: NetworkFlowMonitor
  private let store: AssetGraphStore
  private let config: DiscoveryConfiguration
  private let pendingPathLock = NSLock()
  private let networkObservationLock = NSLock()
  private var pendingChangedPaths: [String: FSEventsChange] = [:]
  private var isFileSystemBatchScheduled = false
  private var lastNetworkEvidenceAt: [String: Date] = [:]

  init(
    keywordScanner: KeywordFileScanner,
    processInspector: ProcessInspector,
    endpointSecurityMonitor: EndpointSecurityMonitor,
    networkFlowMonitor: NetworkFlowMonitor,
    store: AssetGraphStore,
    config: DiscoveryConfiguration
  ) {
    self.keywordScanner = keywordScanner
    self.processInspector = processInspector
    self.endpointSecurityMonitor = endpointSecurityMonitor
    self.networkFlowMonitor = networkFlowMonitor
    self.store = store
    self.config = config
  }

  @MainActor
  func start(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void)
    -> [DiscoveryPermissionState]
  {
    guard config.enableRuntimeObserver else { return [] }
    var states: [DiscoveryPermissionState] = []

    if config.enableFSEventsWatcher && !runtimeWatchRoots().isEmpty {
      states.append(startFileSystemWatcher(onUpdate: onUpdate))
    }
    return states
  }

  @MainActor
  private func startFileSystemWatcher(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void)
    -> DiscoveryPermissionState
  {
    runtimeWatcher?.stop()
    let watcher = makeFileSystemWatcher(onUpdate: onUpdate)
    let state = watcher.start(paths: runtimeWatchRoots(), useRootFallback: true)
    runtimeWatcher = watcher
    return state
  }

  private func runtimeWatchRoots() -> [URL] {
    let home = config.homeDirectory
    let applicationSupport =
      (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? home.appendingPathComponent("Library/Application Support", isDirectory: true))
    let agentRuntimeRoots = [
      home.appendingPathComponent(".codex", isDirectory: true),
      home.appendingPathComponent(".claude", isDirectory: true),
      home.appendingPathComponent(".gemini", isDirectory: true),
      home.appendingPathComponent(".cursor", isDirectory: true),
      home.appendingPathComponent(".continue", isDirectory: true),
      home.appendingPathComponent(".aider", isDirectory: true),
      applicationSupport.appendingPathComponent("Codex", isDirectory: true),
      applicationSupport.appendingPathComponent("Claude", isDirectory: true),
      applicationSupport.appendingPathComponent("Cursor", isDirectory: true),
      applicationSupport.appendingPathComponent("Windsurf", isDirectory: true),
      applicationSupport.appendingPathComponent("Code", isDirectory: true),
      applicationSupport.appendingPathComponent("Code - Insiders", isDirectory: true),
    ]
    return (config.scanRoots + agentRuntimeRoots)
      .filter {
        DiscoveryUtilities.directoryExists($0) && config.allowsAutomaticAccess(to: $0)
      }
      .map { $0.standardizedFileURL }
      .uniqueSorted()
  }

  private func makeFileSystemWatcher(
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) -> FSEventsWatcher {
    FSEventsWatcher { [weak self] changedPaths in
      self?.scheduleFileSystemBatch(changedPaths: changedPaths, onUpdate: onUpdate)
    }
  }

  private static func processFileSystemChanges(
    changes: [FSEventsChange],
    keywordScanner: KeywordFileScanner,
    store: AssetGraphStore,
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) {
    fileSystemProcessingQueue.async {
      let relevantChanges = filteredChangedChanges(changes)
      guard !relevantChanges.isEmpty else { return }
      let relevantPaths = relevantChanges.map(\.path)
      let deadline = Date().addingTimeInterval(3)
      var result = DiscoveryScanResult()
      result.events.append(
        DiscoveryEvent(
          id: UUID(),
          kind: .fileSystemChange,
          path: relevantPaths.first?.path,
          message: "FSEvents reported \(relevantPaths.count) relevant changed paths.",
          createdAt: Date()
        ))
      _ = try? store.appendRuntimeEvents(runtimeEvents(from: relevantChanges))
      result.merge(
        keywordScanner.scan(
          additionalRoots: relevantPaths.map {
            $0.hasDirectoryPath ? $0 : $0.deletingLastPathComponent()
          },
          deadline: deadline
        ))
      if let snapshot = try? store.merge(result) {
        Task { @MainActor in
          onUpdate(snapshot)
        }
      }
    }
  }

  private func scheduleFileSystemBatch(
    changedPaths: [FSEventsChange],
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) {
    let relevantChanges = Self.filteredChangedChanges(changedPaths)
    guard !relevantChanges.isEmpty else { return }

    pendingPathLock.lock()
    for change in relevantChanges {
      pendingChangedPaths[change.path.path] = change
    }
    guard !isFileSystemBatchScheduled else {
      pendingPathLock.unlock()
      return
    }
    isFileSystemBatchScheduled = true
    pendingPathLock.unlock()

    Self.fileSystemProcessingQueue.asyncAfter(deadline: .now() + Self.fileSystemBatchWindow) {
      self.pendingPathLock.lock()
      let changes = Array(self.pendingChangedPaths.values)
      self.pendingChangedPaths.removeAll()
      self.isFileSystemBatchScheduled = false
      self.pendingPathLock.unlock()

      Self.processFileSystemChanges(
        changes: changes,
        keywordScanner: self.keywordScanner,
        store: self.store,
        onUpdate: onUpdate
      )
    }
  }

  private static func filteredChangedChanges(_ changes: [FSEventsChange]) -> [FSEventsChange] {
    changes.map { change in
      FSEventsChange(
        path: change.path.standardizedFileURL,
        eventId: change.eventId,
        flags: change.flags,
        observedAt: change.observedAt
      )
    }.filter { change in
      let url = change.path
      let ignoredNames: Set<String> = [
        ".build", "build", "dist", ".git", ".swiftpm", "deriveddata", "node_modules",
      ]
      return url.pathComponents.map { $0.lowercased() }.allSatisfy { !ignoredNames.contains($0) }
    }
    .reduce(into: [String: FSEventsChange]()) { partial, change in
      partial[change.path.path] = change
    }
    .values
    .sorted { $0.path.path < $1.path.path }
  }

  private static func runtimeEvents(from changes: [FSEventsChange]) -> [RuntimeEventRecord] {
    changes.map { change in
      RuntimeEventRecord(
        sessionId: RuntimeEventRecord.localSessionId(
          prefix: "fsevents", timestamp: change.observedAt),
        kind: .fileEvent,
        timestamp: change.observedAt,
        source: "macos-fsevents",
        path: change.path.path,
        message: "FSEvents observed \(change.flagSummary) change.",
        correlationKey: String(change.eventId),
        metadata: [
          "eventId": String(change.eventId),
          "flags": String(change.flags),
          "flagSummary": change.flagSummary,
        ]
      )
    }
  }

  @MainActor
  func refreshProcesses(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void) {
    if let snapshot = refreshProcessesSnapshot() {
      onUpdate(snapshot)
    }
  }

  func refreshProcessesSnapshot() -> DiscoverySnapshot? {
    do {
      var result = processInspector.inspectRunningProcesses()
      var runtimeEvents: [RuntimeEventRecord] = []
      runtimeEvents.append(runtimeProcessSnapshotEvent(for: result))
      if config.enableNetworkMonitor {
        result.permissionStates.append(networkFlowMonitor.flowSnapshotState())
        result.permissionStates.append(networkFlowMonitor.permissionState())
        let network = networkFlowResult(for: result)
        result.merge(network.result)
        runtimeEvents.append(contentsOf: network.runtimeEvents)
      }
      if config.enableEndpointSecurityMonitor {
        result.permissionStates.append(endpointSecurityMonitor.start())
      }
      let snapshot = try store.replaceRuntimeObservation(result)
      if !runtimeEvents.isEmpty {
        _ = try store.appendRuntimeEvents(runtimeEvents)
      }
      return snapshot
    } catch {
      return nil
    }
  }

  private func networkFlowResult(
    for processResult: DiscoveryScanResult
  ) -> (result: DiscoveryScanResult, runtimeEvents: [RuntimeEventRecord]) {
    let processIds = Set(processResult.runtimeProcesses.map(\.pid))
    guard !processIds.isEmpty else { return (DiscoveryScanResult(), []) }
    let flows = networkFlowMonitor.captureEstablishedTCPFlows(
      forProcessIds: processIds,
      limit: 96,
      timeout: 1.5
    )
    guard !flows.isEmpty else { return (DiscoveryScanResult(), []) }

    let processesByPID = Dictionary(
      uniqueKeysWithValues: processResult.runtimeProcesses.map { ($0.pid, $0) })
    let agentsById = Dictionary(uniqueKeysWithValues: processResult.agents.map { ($0.id, $0) })
    var result = DiscoveryScanResult()
    var runtimeEvents: [RuntimeEventRecord] = []
    for flow in flows {
      guard shouldRecordNetworkObservation(for: flow) else { continue }
      let runtimeProcess = processesByPID[flow.pid]
      let agent = runtimeProcess?.sourceAgentId.flatMap { agentsById[$0] }
      let provider = networkFlowMonitor.knownProviderName(for: flow.remoteAddress)
      let summary =
        "Real network flow observed: \(flow.processName) -> \(flow.remoteEndpoint)"
      result.evidence.append(
        DiscoveryEvidence(
          assetId: agent?.id,
          evidenceType: .behavior,
          source: flow.source,
          processId: flow.pid,
          confidenceDelta: provider == nil ? 15 : 25,
          summary: summary,
          observedAt: flow.observedAt,
          rawKey: flow.remoteEndpoint
        ))
      result.events.append(
        DiscoveryEvent(
          id: UUID(),
          kind: .networkFlow,
          path: nil,
          message: summary,
          createdAt: flow.observedAt
        ))
      runtimeEvents.append(
        RuntimeEventRecord(
          sessionId: RuntimeEventRecord.localSessionId(
            prefix: "network-flow", timestamp: flow.observedAt),
          agentId: agent?.id,
          agentName: agent?.normalizedName,
          kind: .networkEvent,
          timestamp: flow.observedAt,
          source: flow.source,
          processId: flow.pid,
          url: flow.urlString,
          provider: provider,
          message: summary,
          correlationKey: "\(flow.pid)|\(flow.processName)|\(flow.remoteEndpoint)",
          metadata: [
            "captureMode": "lsof",
            "protocol": flow.protocolName,
            "localEndpoint": flow.localEndpoint,
            "remoteEndpoint": flow.remoteEndpoint,
            "remoteAddress": flow.remoteAddress,
            "remotePort": flow.remotePort.map(String.init) ?? "",
            "state": flow.state,
          ]
        ))
    }
    return (result, runtimeEvents)
  }

  private func runtimeProcessSnapshotEvent(for result: DiscoveryScanResult) -> RuntimeEventRecord {
    let observedAt = Date()
    return RuntimeEventRecord(
      sessionId: RuntimeEventRecord.localSessionId(prefix: "process-snapshot", timestamp: observedAt),
      kind: .processObservation,
      timestamp: observedAt,
      source: "macos-process-snapshot",
      message: "Observed \(result.runtimeProcesses.count) agent-like runtime processes across \(result.agents.count) Agent candidates.",
      correlationKey: "agent-process-snapshot",
      metadata: [
        "runtimeProcessCount": String(result.runtimeProcesses.count),
        "agentCount": String(result.agents.count),
      ]
    )
  }

  private func shouldRecordNetworkObservation(for flow: NetworkFlowSnapshot) -> Bool {
    let key = "\(flow.pid)|\(flow.processName)|\(flow.remoteEndpoint)"
    networkObservationLock.lock()
    defer { networkObservationLock.unlock() }
    let cutoff = flow.observedAt.addingTimeInterval(-Self.networkEvidenceInterval)
    lastNetworkEvidenceAt = lastNetworkEvidenceAt.filter { $0.value >= cutoff }
    if let previous = lastNetworkEvidenceAt[key], previous >= cutoff {
      return false
    }
    lastNetworkEvidenceAt[key] = flow.observedAt
    return true
  }

  func stop() {
    runtimeWatcher?.stop()
    runtimeWatcher = nil
  }

  private var runtimeWatcher: FSEventsWatcher?
}
