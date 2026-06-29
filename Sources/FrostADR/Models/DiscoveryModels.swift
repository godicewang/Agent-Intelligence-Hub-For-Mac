import Foundation

struct DiscoveryEvidence: Identifiable, Codable, Hashable {
  var id: UUID
  var assetId: UUID?
  var evidenceType: DiscoveryEvidenceType
  var source: String
  var path: String?
  var processId: Int32?
  var confidenceDelta: Int
  var summary: String
  var observedAt: Date
  var rawKey: String?

  init(
    id: UUID = UUID(),
    assetId: UUID? = nil,
    evidenceType: DiscoveryEvidenceType,
    source: String,
    path: String? = nil,
    processId: Int32? = nil,
    confidenceDelta: Int,
    summary: String,
    observedAt: Date = Date(),
    rawKey: String? = nil
  ) {
    self.id = id
    self.assetId = assetId
    self.evidenceType = evidenceType
    self.source = source
    self.path = path
    self.processId = processId
    self.confidenceDelta = confidenceDelta
    self.summary = summary
    self.observedAt = observedAt
    self.rawKey = rawKey
  }
}

enum DiscoveryEvidenceType: String, Codable, CaseIterable, Hashable {
  case knownPath
  case process
  case config
  case mcpConfig
  case skill
  case contextFile
  case memoryFile
  case keyword
  case behavior
  case permission
}

enum DiscoveryScope: String, Codable, CaseIterable, Hashable {
  case system
  case user
  case project
  case workspace
  case extensionScope
  case plugin
  case runtime
  case unknown
}

enum DiscoveryMethod: String, Codable, CaseIterable, Hashable {
  case knownPath
  case processFingerprint
  case configSchema
  case workspaceScan
  case keywordScan
  case mcpConfigParse
  case skillScan
  case memoryScan
  case behaviorFingerprint
  case fileSystemEvent
}

struct ContextFileAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var path: String
  var workspace: String?
  var detectedAgent: String?
  var keywordHits: [String]
  var riskHints: [String]
  var hash: String
  var discoveredAt: Date
  var lastModifiedAt: Date?

  init(
    id: UUID = UUID(),
    path: String,
    workspace: String? = nil,
    detectedAgent: String? = nil,
    keywordHits: [String] = [],
    riskHints: [String] = [],
    hash: String,
    discoveredAt: Date = Date(),
    lastModifiedAt: Date? = nil
  ) {
    self.id = id
    self.path = path
    self.workspace = workspace
    self.detectedAgent = detectedAgent
    self.keywordHits = keywordHits.uniqueSorted()
    self.riskHints = riskHints.uniqueSorted()
    self.hash = hash
    self.discoveredAt = discoveredAt
    self.lastModifiedAt = lastModifiedAt
  }
}

struct MemoryAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var path: String
  var format: MemoryFormat
  var sourceAgentId: UUID?
  var estimatedRecordCount: Int?
  var containsToolHistory: Bool
  var containsConversationHistory: Bool
  var containsProceduralMemory: Bool
  var lastModifiedAt: Date?
  var privacySensitivity: PrivacySensitivity
}

enum MemoryFormat: String, Codable, CaseIterable, Hashable {
  case jsonl
  case sqlite
  case json
  case vectorDb
  case unknown
}

enum PrivacySensitivity: String, Codable, CaseIterable, Hashable {
  case low
  case medium
  case high
}

struct RuntimeProcessAsset: Identifiable, Codable, Hashable {
  var id: UUID
  var pid: Int32
  var ppid: Int32
  var processName: String
  var executablePath: String?
  var argv: [String]
  var cwd: String?
  var parentChain: [String]
  var codeSigningInfo: String?
  var connectedLLMProviders: [String]
  var spawnedCommandCount: Int
  var workspaceTouched: String?
  var agentCandidateScore: Int
  var firstSeenAt: Date
  var lastSeenAt: Date

  init(
    id: UUID = UUID(),
    pid: Int32,
    ppid: Int32,
    processName: String,
    executablePath: String? = nil,
    argv: [String] = [],
    cwd: String? = nil,
    parentChain: [String] = [],
    codeSigningInfo: String? = nil,
    connectedLLMProviders: [String] = [],
    spawnedCommandCount: Int = 0,
    workspaceTouched: String? = nil,
    agentCandidateScore: Int = 0,
    firstSeenAt: Date = Date(),
    lastSeenAt: Date = Date()
  ) {
    self.id = id
    self.pid = pid
    self.ppid = ppid
    self.processName = processName
    self.executablePath = executablePath
    self.argv = argv
    self.cwd = cwd
    self.parentChain = parentChain
    self.codeSigningInfo = codeSigningInfo
    self.connectedLLMProviders = connectedLLMProviders.uniqueSorted()
    self.spawnedCommandCount = spawnedCommandCount
    self.workspaceTouched = workspaceTouched
    self.agentCandidateScore = agentCandidateScore.clampedConfidence
    self.firstSeenAt = firstSeenAt
    self.lastSeenAt = lastSeenAt
  }
}

struct DiscoveryEvent: Identifiable, Codable, Hashable {
  var id: UUID
  var kind: DiscoveryEventKind
  var path: String?
  var message: String
  var createdAt: Date
}

enum DiscoveryEventKind: String, Codable, CaseIterable, Hashable {
  case coldStartScan
  case fileSystemChange
  case processObservation
  case permissionState
  case storage
}

struct DiscoveryPermissionState: Identifiable, Codable, Hashable {
  var id: UUID
  var capability: DiscoveryCapability
  var status: PermissionStatus
  var message: String
  var checkedAt: Date
}

enum DiscoveryCapability: String, Codable, CaseIterable, Hashable {
  case fullDiskAccess
  case endpointSecurity
  case networkExtension
  case fileSystemEvents
}

enum PermissionStatus: String, Codable, CaseIterable, Hashable {
  case available
  case restricted
  case missingEntitlement
  case notConfigured
  case failed
}

struct DiscoverySnapshot: Codable, Hashable {
  var agents: [AgentAsset] = []
  var mcpServers: [MCPServerAsset] = []
  var skills: [SkillAsset] = []
  var contextFiles: [ContextFileAsset] = []
  var memories: [MemoryAsset] = []
  var runtimeProcesses: [RuntimeProcessAsset] = []
  var evidence: [DiscoveryEvidence] = []
  var permissionStates: [DiscoveryPermissionState] = []
  var events: [DiscoveryEvent] = []
  var lastScannedAt: Date?

  static let empty = DiscoverySnapshot()
}

struct DiscoveryScanResult: Codable, Hashable {
  var agents: [AgentAsset] = []
  var mcpServers: [MCPServerAsset] = []
  var skills: [SkillAsset] = []
  var contextFiles: [ContextFileAsset] = []
  var memories: [MemoryAsset] = []
  var runtimeProcesses: [RuntimeProcessAsset] = []
  var evidence: [DiscoveryEvidence] = []
  var permissionStates: [DiscoveryPermissionState] = []
  var events: [DiscoveryEvent] = []
  var scannedAt: Date = Date()
}
