import AppKit
import Combine
import Foundation

enum DiscoveryPathOpenTarget: Equatable {
  case directory(URL)
  case file(URL)
}

enum DiscoveryPathResolver {
  static func target(
    for rawPath: String, preferDirectory: Bool = false, fileManager: FileManager = .default
  ) -> DiscoveryPathOpenTarget? {
    let url = normalizedURL(rawPath)
    var isDirectory: ObjCBool = false

    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      if isDirectory.boolValue {
        let directory = url.pathExtension == "app" ? url.deletingLastPathComponent() : url
        return .directory(directory.standardizedFileURL)
      }

      if preferDirectory {
        return .directory(url.deletingLastPathComponent().standardizedFileURL)
      }
      return .file(url.standardizedFileURL)
    }

    guard let fallback = nearestExistingDirectory(from: url, fileManager: fileManager) else {
      return nil
    }
    return .directory(fallback.standardizedFileURL)
  }

  private static func normalizedURL(_ rawPath: String) -> URL {
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath).standardizedFileURL
  }

  private static func nearestExistingDirectory(from url: URL, fileManager: FileManager) -> URL? {
    var candidate = url.deletingLastPathComponent()

    while true {
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return candidate
      }

      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path {
        return nil
      }
      candidate = parent
    }
  }
}

@MainActor
final class AgentScanViewModel: ObservableObject {
  @Published var snapshot: DiscoverySnapshot = .empty
  @Published var isScanning = false
  @Published var isRuntimeRefreshing = false
  @Published var isRuntimeMonitoring = false
  @Published var lastRuntimeRefreshedAt: Date?
  @Published var errorMessage: String?
  @Published var configuration: DiscoveryConfiguration = .default()

  private let service: AgentDiscoveryService?
  private var hasStarted = false
  private var runtimeRefreshTask: Task<Void, Never>?
  private var cancellables: Set<AnyCancellable> = []

  init() {
    do {
      let service = try AgentDiscoveryService()
      self.service = service
      configuration = service.configuration
      snapshot = service.snapshot
      service.$snapshot
        .receive(on: DispatchQueue.main)
        .assign(to: &$snapshot)
      service.$isScanning
        .receive(on: DispatchQueue.main)
        .assign(to: &$isScanning)
      service.$lastError
        .receive(on: DispatchQueue.main)
        .assign(to: &$errorMessage)
    } catch {
      service = nil
      errorMessage = error.localizedDescription
    }
  }

  func startIfNeeded() {
    guard !hasStarted, let service else { return }
    hasStarted = true
    Task {
      await service.start()
      bind(from: service)
      startRuntimeRefreshLoop()
    }
  }

  func rescan() {
    guard let service else { return }
    Task {
      await service.runColdStartScan()
      bind(from: service)
    }
  }

  func exportJSONL() {
    guard let service else { return }
    if let url = service.exportJSONL() {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    bind(from: service)
  }

  func refreshRuntimeNow() {
    guard let service, !isRuntimeRefreshing else { return }
    isRuntimeRefreshing = true
    service.refreshRuntimeObservation()
    bind(from: service)
    lastRuntimeRefreshedAt = Date()
    isRuntimeRefreshing = false
  }

  @discardableResult
  func openRootDirectory(for agent: AgentAsset) -> Bool {
    for path in rootPathCandidates(for: agent) {
      if openPath(path, preferDirectory: true, reportsMissingPath: false) {
        return true
      }
    }

    errorMessage = "未找到可打开的 Agent 根目录。"
    return false
  }

  @discardableResult
  func openPath(_ path: String) -> Bool {
    openPath(path, preferDirectory: false, reportsMissingPath: true)
  }

  @discardableResult
  func openDirectoryPath(_ path: String) -> Bool {
    openPath(path, preferDirectory: true, reportsMissingPath: true)
  }

  @discardableResult
  private func openPath(
    _ path: String, preferDirectory: Bool, reportsMissingPath: Bool
  ) -> Bool {
    guard let target = DiscoveryPathResolver.target(for: path, preferDirectory: preferDirectory)
    else {
      if reportsMissingPath {
        errorMessage = "路径不存在或暂时无法访问：\(path)"
      }
      return false
    }

    errorMessage = nil
    switch target {
    case .directory(let url):
      let opened = NSWorkspace.shared.open(url)
      if !opened {
        errorMessage = "Finder 无法打开目录：\(url.path)"
      }
      return opened
    case .file(let url):
      NSWorkspace.shared.activateFileViewerSelecting([url])
      return true
    }
  }

  private func bind(from service: AgentDiscoveryService) {
    snapshot = service.snapshot
    isScanning = service.isScanning
    errorMessage = service.lastError
  }

  private func startRuntimeRefreshLoop() {
    guard configuration.enableRuntimeObserver, runtimeRefreshTask == nil else { return }
    isRuntimeMonitoring = true
    runtimeRefreshTask = Task { [weak self] in
      while !Task.isCancelled {
        await MainActor.run {
          self?.refreshRuntimeNow()
        }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
      }
    }
  }

  private func rootPathCandidates(for agent: AgentAsset) -> [String] {
    agent.workspacePaths
      + agent.installPaths
      + agent.configPaths
      + agent.mcpConfigPaths
      + agent.skillPaths
      + agent.memoryPaths
      + agent.executablePaths
  }

  deinit {
    runtimeRefreshTask?.cancel()
  }
}
