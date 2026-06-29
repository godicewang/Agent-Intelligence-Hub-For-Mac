import Foundation

struct SkillAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var name: String
  var sourceAgentId: UUID?
  var path: String
  var scope: DiscoveryScope
  var description: String?
  var hasSkillMarkdown: Bool
  var hasScripts: Bool
  var hasExternalURLs: Bool
  var hasInstallInstructions: Bool
  var hasSensitivePermissionHints: Bool
  var hash: String
  var scanStatus: SkillScanStatus
  var riskLevel: RiskLevel
  var discoveredAt: Date
  var lastModifiedAt: Date?

  init(
    id: UUID = UUID(),
    name: String,
    sourceAgentId: UUID? = nil,
    path: String,
    scope: DiscoveryScope,
    description: String? = nil,
    hasSkillMarkdown: Bool,
    hasScripts: Bool,
    hasExternalURLs: Bool,
    hasInstallInstructions: Bool,
    hasSensitivePermissionHints: Bool,
    hash: String,
    scanStatus: SkillScanStatus,
    riskLevel: RiskLevel,
    discoveredAt: Date = Date(),
    lastModifiedAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.sourceAgentId = sourceAgentId
    self.path = path
    self.scope = scope
    self.description = description
    self.hasSkillMarkdown = hasSkillMarkdown
    self.hasScripts = hasScripts
    self.hasExternalURLs = hasExternalURLs
    self.hasInstallInstructions = hasInstallInstructions
    self.hasSensitivePermissionHints = hasSensitivePermissionHints
    self.hash = hash
    self.scanStatus = scanStatus
    self.riskLevel = riskLevel
    self.discoveredAt = discoveredAt
    self.lastModifiedAt = lastModifiedAt
  }
}

enum SkillScanStatus: String, Codable, CaseIterable, Hashable {
  case discovered
  case preScanned
  case failed
}
