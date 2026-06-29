import Foundation

struct AgentAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var displayName: String
  var normalizedName: String
  var agentType: AgentAssetType
  var vendor: String?
  var confidence: Int
  var discoveryMethods: [DiscoveryMethod]
  var discoveryEvidenceIds: [UUID]
  var scopes: [DiscoveryScope]
  var installPaths: [String]
  var configPaths: [String]
  var workspacePaths: [String]
  var cachePaths: [String]
  var mcpConfigPaths: [String]
  var skillPaths: [String]
  var memoryPaths: [String]
  var processIds: [Int32]
  var executablePaths: [String]
  var bundleIdentifiers: [String]
  var codeSigningTeamIds: [String]
  var managedStatus: ManagedStatus
  var runtimeStatus: RuntimeStatus
  var riskLevel: RiskLevel
  var firstSeenAt: Date
  var lastSeenAt: Date
  var lastScannedAt: Date
  var permissionErrors: [String]
  var metadataSummary: String?

  init(
    id: UUID = UUID(),
    displayName: String,
    normalizedName: String? = nil,
    agentType: AgentAssetType,
    vendor: String? = nil,
    confidence: Int,
    discoveryMethods: [DiscoveryMethod],
    discoveryEvidenceIds: [UUID] = [],
    scopes: [DiscoveryScope] = [],
    installPaths: [String] = [],
    configPaths: [String] = [],
    workspacePaths: [String] = [],
    cachePaths: [String] = [],
    mcpConfigPaths: [String] = [],
    skillPaths: [String] = [],
    memoryPaths: [String] = [],
    processIds: [Int32] = [],
    executablePaths: [String] = [],
    bundleIdentifiers: [String] = [],
    codeSigningTeamIds: [String] = [],
    managedStatus: ManagedStatus = .observableOnly,
    runtimeStatus: RuntimeStatus = .unknown,
    riskLevel: RiskLevel = .informational,
    firstSeenAt: Date = Date(),
    lastSeenAt: Date = Date(),
    lastScannedAt: Date = Date(),
    permissionErrors: [String] = [],
    metadataSummary: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.normalizedName = normalizedName ?? displayName.normalizedAssetName
    self.agentType = agentType
    self.vendor = vendor
    self.confidence = confidence.clampedConfidence
    self.discoveryMethods = discoveryMethods
    self.discoveryEvidenceIds = discoveryEvidenceIds
    self.scopes = scopes
    self.installPaths = installPaths.uniqueSorted()
    self.configPaths = configPaths.uniqueSorted()
    self.workspacePaths = workspacePaths.uniqueSorted()
    self.cachePaths = cachePaths.uniqueSorted()
    self.mcpConfigPaths = mcpConfigPaths.uniqueSorted()
    self.skillPaths = skillPaths.uniqueSorted()
    self.memoryPaths = memoryPaths.uniqueSorted()
    self.processIds = processIds.uniqueSorted()
    self.executablePaths = executablePaths.uniqueSorted()
    self.bundleIdentifiers = bundleIdentifiers.uniqueSorted()
    self.codeSigningTeamIds = codeSigningTeamIds.uniqueSorted()
    self.managedStatus = managedStatus
    self.runtimeStatus = runtimeStatus
    self.riskLevel = riskLevel
    self.firstSeenAt = firstSeenAt
    self.lastSeenAt = lastSeenAt
    self.lastScannedAt = lastScannedAt
    self.permissionErrors = permissionErrors.uniqueSorted()
    self.metadataSummary = metadataSummary
  }
}

enum AgentAssetType: String, Codable, CaseIterable, Hashable {
  case known
  case customTerminal
  case ideExtension
  case desktop
  case cli
  case unknownCandidate
}

enum ManagedStatus: String, Codable, CaseIterable, Hashable {
  case managed
  case manageable
  case observableOnly
  case unmanaged
  case permissionRequired
}

enum RuntimeStatus: String, Codable, CaseIterable, Hashable {
  case running
  case inactive
  case recentlySeen
  case unknown
}

enum RiskLevel: String, Codable, CaseIterable, Hashable {
  case informational
  case low
  case medium
  case high
  case critical
}

typealias AgentRiskLevel = RiskLevel

extension AgentAsset {
  mutating func merge(with other: AgentAsset) {
    displayName = displayName.isEmpty ? other.displayName : displayName
    vendor = vendor ?? other.vendor
    confidence = max(confidence, other.confidence).clampedConfidence
    discoveryMethods = (discoveryMethods + other.discoveryMethods).uniqueSorted()
    discoveryEvidenceIds = (discoveryEvidenceIds + other.discoveryEvidenceIds).uniqueSorted()
    scopes = (scopes + other.scopes).uniqueSorted()
    installPaths = (installPaths + other.installPaths).uniqueSorted()
    configPaths = (configPaths + other.configPaths).uniqueSorted()
    workspacePaths = (workspacePaths + other.workspacePaths).uniqueSorted()
    cachePaths = (cachePaths + other.cachePaths).uniqueSorted()
    mcpConfigPaths = (mcpConfigPaths + other.mcpConfigPaths).uniqueSorted()
    skillPaths = (skillPaths + other.skillPaths).uniqueSorted()
    memoryPaths = (memoryPaths + other.memoryPaths).uniqueSorted()
    processIds = (processIds + other.processIds).uniqueSorted()
    executablePaths = (executablePaths + other.executablePaths).uniqueSorted()
    bundleIdentifiers = (bundleIdentifiers + other.bundleIdentifiers).uniqueSorted()
    codeSigningTeamIds = (codeSigningTeamIds + other.codeSigningTeamIds).uniqueSorted()
    permissionErrors = (permissionErrors + other.permissionErrors).uniqueSorted()
    firstSeenAt = min(firstSeenAt, other.firstSeenAt)
    lastSeenAt = max(lastSeenAt, other.lastSeenAt)
    lastScannedAt = max(lastScannedAt, other.lastScannedAt)
    runtimeStatus = runtimeStatus.merging(with: other.runtimeStatus)
    managedStatus = managedStatus.merging(with: other.managedStatus)
    riskLevel = riskLevel.merging(with: other.riskLevel)
    metadataSummary = metadataSummary ?? other.metadataSummary
  }
}

extension String {
  var normalizedAssetName: String {
    lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

extension Int {
  var clampedConfidence: Int { Swift.min(100, Swift.max(0, self)) }
}

extension Array where Element: Hashable {
  func uniqueSorted() -> [Element] {
    Array(Set(self)).sorted { String(describing: $0) < String(describing: $1) }
  }
}

extension RuntimeStatus {
  fileprivate func merging(with other: RuntimeStatus) -> RuntimeStatus {
    let order: [RuntimeStatus] = [.unknown, .inactive, .recentlySeen, .running]
    return order.firstIndex(of: other, default: 0) > order.firstIndex(of: self, default: 0)
      ? other : self
  }
}

extension ManagedStatus {
  fileprivate func merging(with other: ManagedStatus) -> ManagedStatus {
    let order: [ManagedStatus] = [
      .unmanaged, .observableOnly, .permissionRequired, .manageable, .managed,
    ]
    return order.firstIndex(of: other, default: 0) > order.firstIndex(of: self, default: 0)
      ? other : self
  }
}

extension RiskLevel {
  fileprivate func merging(with other: RiskLevel) -> RiskLevel {
    let order: [RiskLevel] = [.informational, .low, .medium, .high, .critical]
    return order.firstIndex(of: other, default: 0) > order.firstIndex(of: self, default: 0)
      ? other : self
  }
}

extension Array where Element: Equatable {
  fileprivate func firstIndex(of element: Element, default defaultValue: Int) -> Int {
    firstIndex(of: element) ?? defaultValue
  }
}
