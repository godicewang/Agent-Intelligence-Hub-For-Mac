import Foundation

@MainActor
final class AgentDiscoveryService: ObservableObject {
  @Published private(set) var snapshot: DiscoverySnapshot = .empty
  @Published private(set) var isScanning = false
  @Published private(set) var lastError: String?
  @Published private(set) var lastExportURL: URL?
  let configuration: DiscoveryConfiguration

  private let store: AssetGraphStore
  private let scanner: ColdStartScanner
  private let runtimeObserver: RuntimeAgentObserver

  init(
    configuration: DiscoveryConfiguration = .default(),
    store: AssetGraphStore? = nil
  ) throws {
    self.configuration = configuration
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
      behaviorEngine: BehaviorFingerprintEngine(), config: configuration, registry: registry)
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
    if scanner.isColdStartEnabled && snapshot.lastColdStartScannedAt == nil {
      await runColdStartScan()
    }
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
    guard !isScanning else { return }
    isScanning = true
    lastError = nil
    do {
      let result = await runScannerInBackground()
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

  private func runScannerInBackground() async -> DiscoveryScanResult {
    let scanner = self.scanner
    let timeout = max(1, configuration.limits.maxScanSeconds + 2)
    return await withCheckedContinuation { continuation in
      let box = ScanContinuationBox(continuation)
      DispatchQueue.global(qos: .userInitiated).async {
        box.resume(with: scanner.runFullScan())
      }
      DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
        var result = DiscoveryScanResult()
        result.events.append(
          DiscoveryEvent(
            id: UUID(),
            kind: .coldStartScan,
            path: nil,
            message: "Cold start discovery scan exceeded the UI time budget and was stopped.",
            createdAt: Date()
          ))
        box.resume(with: result)
      }
    }
  }
}

private final class ScanContinuationBox: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<DiscoveryScanResult, Never>?

  init(_ continuation: CheckedContinuation<DiscoveryScanResult, Never>) {
    self.continuation = continuation
  }

  func resume(with result: DiscoveryScanResult) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(returning: result)
  }
}
