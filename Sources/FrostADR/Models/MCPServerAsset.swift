import Foundation

struct MCPServerAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var name: String
  var sourceAgentId: UUID?
  var transport: MCPTransport
  var configPath: String
  var command: String?
  var args: [String]
  var envKeyNames: [String]
  var scope: DiscoveryScope
  var workspacePath: String?
  var manifestHash: String
  var inspectionStatus: MCPInspectionStatus
  var riskPreScore: Int
  var riskLevel: RiskLevel
  var discoveredAt: Date
  var lastModifiedAt: Date?

  init(
    id: UUID = UUID(),
    name: String,
    sourceAgentId: UUID? = nil,
    transport: MCPTransport,
    configPath: String,
    command: String? = nil,
    args: [String] = [],
    envKeyNames: [String] = [],
    scope: DiscoveryScope,
    workspacePath: String? = nil,
    manifestHash: String,
    inspectionStatus: MCPInspectionStatus = .noExecDiscovered,
    riskPreScore: Int = 0,
    riskLevel: RiskLevel = .informational,
    discoveredAt: Date = Date(),
    lastModifiedAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.sourceAgentId = sourceAgentId
    self.transport = transport
    self.configPath = configPath
    self.command = command
    self.args = args
    self.envKeyNames = envKeyNames.uniqueSorted()
    self.scope = scope
    self.workspacePath = workspacePath
    self.manifestHash = manifestHash
    self.inspectionStatus = inspectionStatus
    self.riskPreScore = riskPreScore
    self.riskLevel = riskLevel
    self.discoveredAt = discoveredAt
    self.lastModifiedAt = lastModifiedAt
  }
}

enum MCPTransport: String, Codable, CaseIterable, Hashable {
  case stdio
  case http
  case sse
  case streamableHttp
  case unknown
}

enum MCPInspectionStatus: String, Codable, CaseIterable, Hashable {
  case noExecDiscovered
  case preScanned
  case safeToInspect
  case blockedUntilApproved
  case inspected
  case failed
}
