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
  private var pendingChangedPaths: Set<URL> = []
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
    changedPaths: [URL],
    keywordScanner: KeywordFileScanner,
    store: AssetGraphStore,
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) {
    fileSystemProcessingQueue.async {
      let relevantPaths = filteredChangedPaths(changedPaths)
      guard !relevantPaths.isEmpty else { return }
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
    changedPaths: [URL],
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) {
    let relevantPaths = Self.filteredChangedPaths(changedPaths)
    guard !relevantPaths.isEmpty else { return }

    pendingPathLock.lock()
    pendingChangedPaths.formUnion(relevantPaths)
    guard !isFileSystemBatchScheduled else {
      pendingPathLock.unlock()
      return
    }
    isFileSystemBatchScheduled = true
    pendingPathLock.unlock()

    Self.fileSystemProcessingQueue.asyncAfter(deadline: .now() + Self.fileSystemBatchWindow) {
      self.pendingPathLock.lock()
      let paths = Array(self.pendingChangedPaths)
      self.pendingChangedPaths.removeAll()
      self.isFileSystemBatchScheduled = false
      self.pendingPathLock.unlock()

      Self.processFileSystemChanges(
        changedPaths: paths,
        keywordScanner: self.keywordScanner,
        store: self.store,
        onUpdate: onUpdate
      )
    }
  }

  private static func filteredChangedPaths(_ paths: [URL]) -> [URL] {
    paths.map(\.standardizedFileURL).filter { url in
      let ignoredNames: Set<String> = [
        ".build", "build", "dist", ".git", ".swiftpm", "deriveddata", "node_modules",
      ]
      return url.pathComponents.map { $0.lowercased() }.allSatisfy { !ignoredNames.contains($0) }
    }.uniqueSorted()
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
