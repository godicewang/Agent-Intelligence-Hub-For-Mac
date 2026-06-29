import Foundation

final class AssetGraphStore {
  private let database: FrostDatabase

  init(database: FrostDatabase) {
    self.database = database
  }

  convenience init() throws {
    try self.init(database: FrostDatabase())
  }

  func loadSnapshot() throws -> DiscoverySnapshot {
    DiscoverySnapshot(
      agents: try database.loadAll(AgentAsset.self, kind: .agent),
      mcpServers: try database.loadAll(MCPServerAsset.self, kind: .mcpServer),
      skills: try database.loadAll(SkillAsset.self, kind: .skill),
      contextFiles: try database.loadAll(ContextFileAsset.self, kind: .contextFile),
      memories: try database.loadAll(MemoryAsset.self, kind: .memory),
      runtimeProcesses: try database.loadAll(RuntimeProcessAsset.self, kind: .runtimeProcess),
      evidence: try database.loadAll(DiscoveryEvidence.self, kind: .evidence),
      permissionStates: try database.loadAll(DiscoveryPermissionState.self, kind: .permissionState),
      events: try database.loadAll(DiscoveryEvent.self, kind: .event),
      lastScannedAt: try database.loadAll(DiscoveryEvent.self, kind: .event).map(\.createdAt).max()
    )
  }

  @discardableResult
  func merge(_ result: DiscoveryScanResult) throws -> DiscoverySnapshot {
    var snapshot = try loadSnapshot()

    for evidence in result.evidence {
      if !snapshot.evidence.contains(where: { $0.id == evidence.id }) {
        snapshot.evidence.append(evidence)
      }
    }

    for incoming in result.agents {
      if let index = snapshot.agents.firstIndex(where: { $0.mergeKeyMatches(incoming) }) {
        snapshot.agents[index].merge(with: incoming)
      } else {
        snapshot.agents.append(incoming)
      }
    }

    snapshot.mcpServers = mergeByKey(snapshot.mcpServers + result.mcpServers) {
      "\($0.configPath)|\($0.name)|\($0.manifestHash)"
    }
    snapshot.skills = mergeByKey(snapshot.skills + result.skills) { "\($0.path)|\($0.hash)" }
    snapshot.contextFiles = mergeByKey(snapshot.contextFiles + result.contextFiles) { $0.path }
    snapshot.memories = mergeByKey(snapshot.memories + result.memories) { $0.path }
    snapshot.runtimeProcesses = mergeByKey(snapshot.runtimeProcesses + result.runtimeProcesses) {
      String($0.pid)
    }
    snapshot.permissionStates = mergeByKey(snapshot.permissionStates + result.permissionStates) {
      $0.capability.rawValue
    }
    snapshot.events = mergeByKey(snapshot.events + result.events) { $0.id.uuidString }
    snapshot.lastScannedAt = result.scannedAt

    try persist(snapshot)
    return snapshot
  }

  func exportJSONL(to url: URL) throws {
    let snapshot = try loadSnapshot()
    var lines: [String] = []
    try append(snapshot.agents, kind: "agent", to: &lines)
    try append(snapshot.mcpServers, kind: "mcpServer", to: &lines)
    try append(snapshot.skills, kind: "skill", to: &lines)
    try append(snapshot.contextFiles, kind: "contextFile", to: &lines)
    try append(snapshot.memories, kind: "memory", to: &lines)
    try append(snapshot.runtimeProcesses, kind: "runtimeProcess", to: &lines)
    try append(snapshot.evidence, kind: "evidence", to: &lines)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  private func persist(_ snapshot: DiscoverySnapshot) throws {
    for asset in snapshot.agents {
      try database.upsert(asset, kind: .agent, key: asset.primaryStoreKey)
    }
    for asset in snapshot.mcpServers {
      try database.upsert(
        asset, kind: .mcpServer, key: "\(asset.configPath)|\(asset.name)|\(asset.manifestHash)")
    }
    for asset in snapshot.skills {
      try database.upsert(asset, kind: .skill, key: "\(asset.path)|\(asset.hash)")
    }
    for asset in snapshot.contextFiles {
      try database.upsert(asset, kind: .contextFile, key: asset.path)
    }
    for asset in snapshot.memories {
      try database.upsert(asset, kind: .memory, key: asset.path)
    }
    for asset in snapshot.runtimeProcesses {
      try database.upsert(asset, kind: .runtimeProcess, key: String(asset.pid))
    }
    for evidence in snapshot.evidence {
      try database.upsert(evidence, kind: .evidence, key: evidence.id.uuidString)
    }
    for state in snapshot.permissionStates {
      try database.upsert(state, kind: .permissionState, key: state.capability.rawValue)
    }
    for event in snapshot.events {
      try database.upsert(event, kind: .event, key: event.id.uuidString)
    }
  }

  private func mergeByKey<T>(_ values: [T], key: (T) -> String) -> [T] {
    var keyed: [String: T] = [:]
    for value in values {
      keyed[key(value)] = value
    }
    return keyed.values.sorted { key($0) < key($1) }
  }

  private func append<T: Encodable>(_ values: [T], kind: String, to lines: inout [String]) throws {
    for value in values {
      let payload = try JSONEncoder.frost.encode(JSONLRecord(kind: kind, payload: value))
      if let line = String(data: payload, encoding: .utf8) {
        lines.append(line)
      }
    }
  }
}

private struct JSONLRecord<T: Encodable>: Encodable {
  var kind: String
  var payload: T
}

extension AgentAsset {
  fileprivate var primaryStoreKey: String {
    if let path = configPaths.first {
      return "config:\(path)"
    }
    if let path = installPaths.first {
      return "install:\(path)"
    }
    if let path = executablePaths.first {
      return "exec:\(path)"
    }
    if let workspace = workspacePaths.first {
      return "workspace:\(normalizedName):\(workspace)"
    }
    return "name:\(normalizedName)"
  }

  fileprivate func mergeKeyMatches(_ other: AgentAsset) -> Bool {
    intersects(configPaths, other.configPaths)
      || intersects(installPaths, other.installPaths)
      || intersects(executablePaths, other.executablePaths)
      || intersects(bundleIdentifiers, other.bundleIdentifiers)
      || (normalizedName == other.normalizedName
        && intersects(workspacePaths, other.workspacePaths))
      || (normalizedName == other.normalizedName && !normalizedName.isEmpty)
  }
}

private func intersects<T: Hashable>(_ lhs: [T], _ rhs: [T]) -> Bool {
  !Set(lhs).intersection(Set(rhs)).isEmpty
}
