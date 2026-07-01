import Foundation

final class RuntimeAgentObserver {
  private static let fileSystemProcessingQueue = DispatchQueue(
    label: "frostadr.fsevents.processing",
    qos: .utility
  )

  private let keywordScanner: KeywordFileScanner
  private let processInspector: ProcessInspector
  private let store: AssetGraphStore
  private let config: DiscoveryConfiguration

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
    let watcher = Self.makeFileSystemWatcher(
      keywordScanner: keywordScanner,
      store: store,
      onUpdate: onUpdate
    )
    let state = watcher.start(paths: config.scanRoots)
    runtimeWatcher = watcher
    return state
  }

  private static func makeFileSystemWatcher(
    keywordScanner: KeywordFileScanner,
    store: AssetGraphStore,
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) -> FSEventsWatcher {
    FSEventsWatcher { changedPaths in
      processFileSystemChanges(
        changedPaths: changedPaths,
        keywordScanner: keywordScanner,
        store: store,
        onUpdate: onUpdate
      )
    }
  }

  private static func processFileSystemChanges(
    changedPaths: [URL],
    keywordScanner: KeywordFileScanner,
    store: AssetGraphStore,
    onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void
  ) {
    fileSystemProcessingQueue.async {
      let deadline = Date().addingTimeInterval(3)
      var result = DiscoveryScanResult()
      result.events.append(
        DiscoveryEvent(
          id: UUID(),
          kind: .fileSystemChange,
          path: changedPaths.first?.path,
          message: "FSEvents reported \(changedPaths.count) changed paths.",
          createdAt: Date()
        ))
      result.merge(
        keywordScanner.scan(
          additionalRoots: changedPaths.map {
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

  @MainActor
  func refreshProcesses(onUpdate: @escaping @MainActor (DiscoverySnapshot) -> Void) {
    do {
      let snapshot = try store.merge(processInspector.inspectRunningProcesses())
      onUpdate(snapshot)
    } catch {
      // Runtime observation errors are surfaced through persisted events during cold scans.
    }
  }

  func stop() {
    runtimeWatcher?.stop()
    runtimeWatcher = nil
  }

  private var runtimeWatcher: FSEventsWatcher?
}
