import Foundation

struct AgentFingerprint: Codable, Hashable {
  var displayName: String
  var normalizedName: String
  var vendor: String?
  var agentType: AgentAssetType
  var processNames: [String]
  var installPaths: [String]
  var configPaths: [String]
  var projectMarkers: [String]
  var mcpConfigPaths: [String]
  var skillPaths: [String]
  var cachePaths: [String]
  var extensionPaths: [String]
  var memoryPaths: [String]
  var confidenceWeights: ConfidenceWeights
}

struct ConfidenceWeights: Codable, Hashable {
  var installPath: Int
  var configPath: Int
  var process: Int
  var projectMarker: Int
  var mcpConfig: Int
  var skill: Int
  var cache: Int
  var memory: Int
}

final class FingerprintRegistry {
  let fingerprints: [AgentFingerprint]

  init(fingerprints: [AgentFingerprint]) {
    self.fingerprints = fingerprints
  }

  static func bundled() throws -> FingerprintRegistry {
    let url = Bundle.module.url(forResource: "agent_fingerprints", withExtension: "json")
    guard let url else {
      throw DiscoveryError.resourceMissing("agent_fingerprints.json")
    }
    return try load(from: url)
  }

  static func load(from url: URL) throws -> FingerprintRegistry {
    let data = try Data(contentsOf: url)
    return FingerprintRegistry(
      fingerprints: try JSONDecoder.frost.decode([AgentFingerprint].self, from: data))
  }
}

enum DiscoveryError: Error, LocalizedError {
  case resourceMissing(String)
  case parseFailed(String)

  var errorDescription: String? {
    switch self {
    case .resourceMissing(let name):
      "Missing bundled discovery resource: \(name)"
    case .parseFailed(let message):
      "Discovery parse failed: \(message)"
    }
  }
}
