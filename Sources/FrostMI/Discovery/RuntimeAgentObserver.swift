import Foundation

final class RuntimeAgentObserver: @unchecked Sendable {
  private static let fileSystemProcessingQueue = DispatchQueue(
    label: "frostadr.fsevents.processing",
    qos: .utility
  )
  private static let fileSystemBatchWindow: TimeInterval = 1.2

  private let keywordScanner: KeywordFileScanner
  private let processInspector: ProcessInspector
  private let store: AssetGraphStore
  private let config: DiscoveryConfiguration
  private let pendingPathLock = NSLock()
  private var pendingChangedPaths: [String: FSEventsChange] = [:]
  private var isFileSystemBatchScheduled = false

  init(
    keywordScanner: KeywordFileScanner,
    processInspector: ProcessInspector,
    store: AssetGraphStore,
    config: DiscoveryConfiguration
  ) {
    self.keywordScanner = keywordScanner
    self.processInspector = processInspector
    self.store = store
    self.config = config
  }

  @MainActor
  func start(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void)
    -> [DiscoveryPermissionState]
  {
    guard config.enableRuntimeObserver else { return [] }
    var states: [DiscoveryPermissionState] = []

    if config.enableFSEventsWatcher && !config.scanRoots.isEmpty {
      states.append(startFileSystemWatcher(onUpdate: onUpdate))
    }
    refreshProcesses(onUpdate: onUpdate)
    return states
  }

  @MainActor
  private func startFileSystemWatcher(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void)
    -> DiscoveryPermissionState
  {
    runtimeWatcher?.stop()
    let watcher = makeFileSystemWatcher(onUpdate: onUpdate)
    let state = watcher.start(paths: config.scanRoots)
    runtimeWatcher = watcher
    return state
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
      return try store.replaceRuntimeObservation(processInspector.inspectRunningProcesses())
    } catch {
      return nil
    }
  }

  func stop() {
    runtimeWatcher?.stop()
    runtimeWatcher = nil
  }

  private var runtimeWatcher: FSEventsWatcher?
}
