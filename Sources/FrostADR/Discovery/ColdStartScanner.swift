import Foundation

final class ColdStartScanner {
  private let knownAgentScanner: KnownAgentScanner
  private let keywordScanner: KeywordFileScanner
  private let processInspector: ProcessInspector
  private let permissionInspector: FileSystemPermissionInspector
  private let endpointSecurityMonitor: EndpointSecurityMonitor
  private let networkFlowMonitor: NetworkFlowMonitor
  private let config: DiscoveryConfiguration

  init(
    knownAgentScanner: KnownAgentScanner,
    keywordScanner: KeywordFileScanner,
    processInspector: ProcessInspector,
    permissionInspector: FileSystemPermissionInspector,
    endpointSecurityMonitor: EndpointSecurityMonitor,
    networkFlowMonitor: NetworkFlowMonitor,
    config: DiscoveryConfiguration
  ) {
    self.knownAgentScanner = knownAgentScanner
    self.keywordScanner = keywordScanner
    self.processInspector = processInspector
    self.permissionInspector = permissionInspector
    self.endpointSecurityMonitor = endpointSecurityMonitor
    self.networkFlowMonitor = networkFlowMonitor
    self.config = config
  }

  func runFullScan() -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    result.events.append(
      DiscoveryEvent(
        id: UUID(), kind: .coldStartScan, path: nil, message: "Cold start discovery scan started.",
        createdAt: result.scannedAt)
    )

    result.merge(knownAgentScanner.scan())
    result.merge(
      keywordScanner.scan(
        additionalRoots: result.agents.flatMap { $0.workspacePaths.map(URL.init(fileURLWithPath:)) }
      ))
    result.merge(processInspector.inspectRunningProcesses())
    result.permissionStates.append(contentsOf: permissionInspector.inspect(paths: config.scanRoots))
    result.permissionStates.append(endpointSecurityMonitor.permissionState())
    result.permissionStates.append(networkFlowMonitor.permissionState())
    result.events.append(
      DiscoveryEvent(
        id: UUID(),
        kind: .coldStartScan,
        path: nil,
        message:
          "Cold start discovery scan completed with \(result.agents.count) agent candidates.",
        createdAt: Date()
      ))
    return result
  }
}

extension DiscoveryScanResult {
  mutating func merge(_ other: DiscoveryScanResult) {
    agents.append(contentsOf: other.agents)
    mcpServers.append(contentsOf: other.mcpServers)
    skills.append(contentsOf: other.skills)
    contextFiles.append(contentsOf: other.contextFiles)
    memories.append(contentsOf: other.memories)
    runtimeProcesses.append(contentsOf: other.runtimeProcesses)
    evidence.append(contentsOf: other.evidence)
    permissionStates.append(contentsOf: other.permissionStates)
    events.append(contentsOf: other.events)
    scannedAt = max(scannedAt, other.scannedAt)
  }
}
