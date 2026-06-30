import AppKit
import Combine
import Foundation

@MainActor
final class AgentScanViewModel: ObservableObject {
  @Published var snapshot: DiscoverySnapshot = .empty
  @Published var isScanning = false
  @Published var errorMessage: String?
  @Published var configuration: DiscoveryConfiguration = .default()

  private let service: AgentDiscoveryService?
  private var hasStarted = false
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

  func openRootDirectory(for agent: AgentAsset) {
    guard let url = rootURL(for: agent) else {
      errorMessage = "未找到可打开的 Agent 根目录。"
      return
    }
    errorMessage = nil
    NSWorkspace.shared.open(url)
  }

  func openPath(_ path: String) {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      errorMessage = "路径不存在或暂时无法访问：\(path)"
      return
    }

    errorMessage = nil
    if isDirectory.boolValue {
      NSWorkspace.shared.open(url)
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
  }

  private func bind(from service: AgentDiscoveryService) {
    snapshot = service.snapshot
    isScanning = service.isScanning
    errorMessage = service.lastError
  }

  private func rootURL(for agent: AgentAsset) -> URL? {
    let candidates =
      agent.workspacePaths.map(URL.init(fileURLWithPath:))
      + agent.installPaths.map(URL.init(fileURLWithPath:))
      + agent.configPaths.map(URL.init(fileURLWithPath:))
      + agent.mcpConfigPaths.map(URL.init(fileURLWithPath:))
      + agent.skillPaths.map(URL.init(fileURLWithPath:))
      + agent.memoryPaths.map(URL.init(fileURLWithPath:))
      + agent.executablePaths.map(URL.init(fileURLWithPath:))

    for candidate in candidates {
      if let directory = existingRootDirectory(for: candidate) {
        return directory
      }
    }
    return nil
  }

  private func existingRootDirectory(for url: URL) -> URL? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return nil
    }
    if isDirectory.boolValue {
      return url.pathExtension == "app" ? url.deletingLastPathComponent() : url
    }
    return url.deletingLastPathComponent()
  }
}
