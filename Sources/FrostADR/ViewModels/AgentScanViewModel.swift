import Combine
import Foundation

@MainActor
final class AgentScanViewModel: ObservableObject {
  @Published var snapshot: DiscoverySnapshot = .empty
  @Published var isScanning = false
  @Published var errorMessage: String?
  @Published var exportMessage: String?
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
      service.$lastExportURL
        .receive(on: DispatchQueue.main)
        .map { url in
          url.map { "已导出到 \($0.path)" }
        }
        .assign(to: &$exportMessage)
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
    exportMessage = nil
    Task {
      await service.runColdStartScan()
      bind(from: service)
    }
  }

  func exportJSONL() {
    exportMessage = nil
    guard let service else { return }
    _ = service.exportJSONL()
    bind(from: service)
  }

  private func bind(from service: AgentDiscoveryService) {
    snapshot = service.snapshot
    isScanning = service.isScanning
    errorMessage = service.lastError
  }
}
