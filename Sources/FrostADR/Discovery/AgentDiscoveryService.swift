import Foundation

@MainActor
final class AgentDiscoveryService: ObservableObject {
  @Published private(set) var snapshot: DiscoverySnapshot = .empty
  @Published private(set) var isScanning = false
  @Published private(set) var lastError: String?
  @Published private(set) var lastExportURL: URL?

  private let store: AssetGraphStore
  private let scanner: ColdStartScanner
  private let runtimeObserver: RuntimeAgentObserver

  init(
    configuration: DiscoveryConfiguration = .default(),
    store: AssetGraphStore? = nil
  ) throws {
    let registry = try FingerprintRegistry.bundled()
    let actualStore: AssetGraphStore
    if let store {
      actualStore = store
    } else {
      actualStore = try AssetGraphStore()
    }
    let skillScanner = SkillScanner(limits: configuration.limits)
    let memoryScanner = MemoryFileScanner(limits: configuration.limits)
    let keywordScanner = KeywordFileScanner(
      config: configuration, skillScanner: skillScanner, memoryScanner: memoryScanner)
    let processInspector = ProcessInspector(
      behaviorEngine: BehaviorFingerprintEngine(), config: configuration)
    self.store = actualStore
    scanner = ColdStartScanner(
      knownAgentScanner: KnownAgentScanner(
        registry: registry,
        skillScanner: skillScanner,
        memoryScanner: memoryScanner,
        config: configuration
      ),
      keywordScanner: keywordScanner,
      processInspector: processInspector,
      permissionInspector: FileSystemPermissionInspector(),
      endpointSecurityMonitor: EndpointSecurityMonitor(),
      networkFlowMonitor: NetworkFlowMonitor(),
      config: configuration
    )
    runtimeObserver = RuntimeAgentObserver(
      keywordScanner: keywordScanner,
      processInspector: processInspector,
      store: actualStore,
      config: configuration
    )
    snapshot = (try? actualStore.loadSnapshot()) ?? .empty
  }

  func start() async {
    await runColdStartScan()
    let states = runtimeObserver.start { [weak self] snapshot in
      self?.snapshot = snapshot
    }
    if !states.isEmpty {
      var result = DiscoveryScanResult()
      result.permissionStates = states
      if let snapshot = try? store.merge(result) {
        self.snapshot = snapshot
      }
    }
  }

  func runColdStartScan() async {
    isScanning = true
    lastError = nil
    do {
      let result = scanner.runFullScan()
      snapshot = try store.merge(result)
    } catch {
      lastError = error.localizedDescription
    }
    isScanning = false
  }

  @discardableResult
  func exportJSONL() -> URL? {
    do {
      let directory =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
          "Library/Application Support")
      let url = directory.appendingPathComponent("FrostADR", isDirectory: true)
        .appendingPathComponent("discovery-export.jsonl")
      try store.exportJSONL(to: url)
      lastExportURL = url
      lastError = nil
      return url
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }
}
