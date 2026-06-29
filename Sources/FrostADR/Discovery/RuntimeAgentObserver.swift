import Foundation

final class RuntimeAgentObserver {
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
    let watcher = FSEventsWatcher { [keywordScanner, store] changedPaths in
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
          }))
      if let snapshot = try? store.merge(result) {
        Task { @MainActor in
          onUpdate(snapshot)
        }
      }
    }
    let state = watcher.start(paths: config.scanRoots)
    runtimeWatcher = watcher
    refreshProcesses(onUpdate: onUpdate)
    return [state]
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
