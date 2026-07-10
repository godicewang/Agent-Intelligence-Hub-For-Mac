import Foundation

final class AssetGraphStore: @unchecked Sendable {
  private let database: FrostDatabase
  private let lock = NSLock()

  init(database: FrostDatabase) {
    self.database = database
  }

  convenience init() throws {
    try self.init(database: FrostDatabase())
  }

  func loadSnapshot() throws -> DiscoverySnapshot {
    try lock.withLock {
      try loadSnapshotUnlocked()
    }
  }

  private func loadSnapshotUnlocked() throws -> DiscoverySnapshot {
    let agents = try database.loadAll(AgentAsset.self, kind: .agent)
    let mcpServers = try database.loadAll(MCPServerAsset.self, kind: .mcpServer)
    let skills = try database.loadAll(SkillAsset.self, kind: .skill)
    let contextFiles = try database.loadAll(ContextFileAsset.self, kind: .contextFile)
    let memories = try database.loadAll(MemoryAsset.self, kind: .memory)
    let runtimeProcesses = try database.loadAll(RuntimeProcessAsset.self, kind: .runtimeProcess)
    let evidence = try database.loadAll(DiscoveryEvidence.self, kind: .evidence)
    let permissionStates = try database.loadAll(
      DiscoveryPermissionState.self, kind: .permissionState)
    let events = try database.loadAll(DiscoveryEvent.self, kind: .event)

    return DiscoverySnapshot(
      agents: agents,
      mcpServers: mcpServers,
      skills: skills,
      contextFiles: contextFiles,
      memories: memories,
      runtimeProcesses: runtimeProcesses,
      evidence: evidence,
      permissionStates: permissionStates,
      events: events,
      lastScannedAt: latestScanTime(
        agents: agents, mcpServers: mcpServers, skills: skills, contextFiles: contextFiles,
        memories: memories, runtimeProcesses: runtimeProcesses, evidence: evidence, events: events)
    )
  }

  @discardableResult
  func merge(_ result: DiscoveryScanResult) throws -> DiscoverySnapshot {
    try lock.withLock {
      let replacesColdStartSnapshot = result.hasColdStartCompletionEvent
      var snapshot = replacesColdStartSnapshot ? DiscoverySnapshot() : try loadSnapshotUnlocked()

      for evidence in result.evidence {
        if !snapshot.evidence.contains(where: { $0.id == evidence.id }) {
          snapshot.evidence.append(evidence)
        }
      }
      snapshot.evidence = trimmedEvidence(snapshot.evidence)

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
      snapshot.events = trimmedObservationEvents(snapshot.events)
      if result.hasColdStartCompletionEvent {
        snapshot.lastScannedAt = result.scannedAt
      } else {
        snapshot.lastScannedAt = latestScanTime(
          agents: snapshot.agents, mcpServers: snapshot.mcpServers, skills: snapshot.skills,
          contextFiles: snapshot.contextFiles, memories: snapshot.memories,
          runtimeProcesses: snapshot.runtimeProcesses, evidence: snapshot.evidence,
          events: snapshot.events)
      }

      try persist(snapshot)
      return snapshot
    }
  }

  @discardableResult
  func replaceRuntimeObservation(_ result: DiscoveryScanResult) throws -> DiscoverySnapshot {
    try lock.withLock {
      var snapshot = try loadSnapshotUnlocked()
      let activeProcessIds = Set(result.runtimeProcesses.map(\.pid))

      for index in snapshot.agents.indices
      where !snapshot.agents[index].processIds.isEmpty
        && snapshot.agents[index].runtimeStatus == .running
        && Set(snapshot.agents[index].processIds).isDisjoint(with: activeProcessIds)
      {
        snapshot.agents[index].runtimeStatus = .recentlySeen
      }

      for incoming in result.agents {
        if let index = snapshot.agents.firstIndex(where: { $0.mergeKeyMatches(incoming) }) {
          snapshot.agents[index].merge(with: incoming)
        } else {
          snapshot.agents.append(incoming)
        }
      }

      snapshot.runtimeProcesses = mergeByKey(result.runtimeProcesses) { String($0.pid) }
      for evidence in result.evidence {
        if !snapshot.evidence.contains(where: { $0.id == evidence.id }) {
          snapshot.evidence.append(evidence)
        }
      }
      snapshot.evidence = trimmedEvidence(snapshot.evidence)
      snapshot.permissionStates = mergeByKey(snapshot.permissionStates + result.permissionStates) {
        $0.capability.rawValue
      }
      snapshot.events = mergeByKey(snapshot.events + result.events) { $0.id.uuidString }
      snapshot.events = trimmedObservationEvents(snapshot.events)
      snapshot.lastScannedAt = latestScanTime(
        agents: snapshot.agents, mcpServers: snapshot.mcpServers, skills: snapshot.skills,
        contextFiles: snapshot.contextFiles, memories: snapshot.memories,
        runtimeProcesses: snapshot.runtimeProcesses, evidence: snapshot.evidence,
        events: snapshot.events)

      try persist(snapshot, replacing: Self.runtimeObservationRecordKinds)
      return snapshot
    }
  }

  func exportJSONL(to url: URL) throws {
    let snapshot = try loadSnapshot()
    let runtimeEvents = try loadRuntimeEvents()
    let runtimeSessionGraphs = try loadRuntimeSessionGraphs()
    var lines: [String] = []
    try append(snapshot.agents, kind: "agent", to: &lines)
    try append(snapshot.mcpServers, kind: "mcpServer", to: &lines)
    try append(snapshot.skills, kind: "skill", to: &lines)
    try append(snapshot.contextFiles, kind: "contextFile", to: &lines)
    try append(snapshot.memories, kind: "memory", to: &lines)
    try append(snapshot.runtimeProcesses, kind: "runtimeProcess", to: &lines)
    try append(snapshot.evidence, kind: "evidence", to: &lines)
    try append(snapshot.permissionStates, kind: "permissionState", to: &lines)
    try append(snapshot.events, kind: "event", to: &lines)
    try append(runtimeEvents, kind: "runtimeEvent", to: &lines)
    try append(runtimeSessionGraphs, kind: "runtimeSessionGraph", to: &lines)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let output = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
  }

  @discardableResult
  func appendRuntimeEvents(_ events: [RuntimeEventRecord]) throws -> [RuntimeSessionGraph] {
    try lock.withLock {
      guard !events.isEmpty else {
        return try database.loadAll(RuntimeSessionGraph.self, kind: .runtimeSessionGraph)
      }
      let runtimeStore = RuntimeEventStore(database: database)
      return try runtimeStore.append(events)
    }
  }

  func loadRuntimeEvents() throws -> [RuntimeEventRecord] {
    try lock.withLock {
      try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
    }
  }

  func loadRuntimeSessionGraphs() throws -> [RuntimeSessionGraph] {
    try lock.withLock {
      try database.loadAll(RuntimeSessionGraph.self, kind: .runtimeSessionGraph)
    }
  }

  private func persist(_ snapshot: DiscoverySnapshot) throws {
    try persist(snapshot, replacing: Self.snapshotRecordKinds)
  }

  private func persist(_ snapshot: DiscoverySnapshot, replacing kinds: [RecordKind]) throws {
    try database.delete(kinds: kinds)
    if kinds.contains(.agent) {
      for asset in snapshot.agents {
        try database.upsert(asset, kind: .agent, key: asset.primaryStoreKey)
      }
    }
    if kinds.contains(.mcpServer) {
      for asset in snapshot.mcpServers {
        try database.upsert(
          asset, kind: .mcpServer, key: "\(asset.configPath)|\(asset.name)|\(asset.manifestHash)")
      }
    }
    if kinds.contains(.skill) {
      for asset in snapshot.skills {
        try database.upsert(asset, kind: .skill, key: "\(asset.path)|\(asset.hash)")
      }
    }
    if kinds.contains(.contextFile) {
      for asset in snapshot.contextFiles {
        try database.upsert(asset, kind: .contextFile, key: asset.path)
      }
    }
    if kinds.contains(.memory) {
      for asset in snapshot.memories {
        try database.upsert(asset, kind: .memory, key: asset.path)
      }
    }
    if kinds.contains(.runtimeProcess) {
      for asset in snapshot.runtimeProcesses {
        try database.upsert(asset, kind: .runtimeProcess, key: String(asset.pid))
      }
    }
    if kinds.contains(.evidence) {
      for evidence in snapshot.evidence {
        try database.upsert(evidence, kind: .evidence, key: evidence.id.uuidString)
      }
    }
    if kinds.contains(.permissionState) {
      for state in snapshot.permissionStates {
        try database.upsert(state, kind: .permissionState, key: state.capability.rawValue)
      }
    }
    if kinds.contains(.event) {
      for event in snapshot.events {
        try database.upsert(event, kind: .event, key: event.id.uuidString)
      }
    }
  }

  private func mergeByKey<T>(_ values: [T], key: (T) -> String) -> [T] {
    var keyed: [String: T] = [:]
    for value in values {
      keyed[key(value)] = value
    }
    return keyed.values.sorted { key($0) < key($1) }
  }

  private func trimmedObservationEvents(_ events: [DiscoveryEvent]) -> [DiscoveryEvent] {
    let limits: [DiscoveryEventKind: Int] = [
      .coldStartScan: 12,
      .processObservation: 20,
      .fileSystemChange: 120,
      .networkFlow: 120,
      .permissionState: 24,
      .storage: 24,
    ]
    let retainedIds = Set(
      DiscoveryEventKind.allCases.flatMap { kind in
        events.filter { $0.kind == kind }
          .sorted { $0.createdAt > $1.createdAt }
          .prefix(limits[kind] ?? 0)
          .map(\.id)
      })
    return events.filter { retainedIds.contains($0.id) }
      .sorted { $0.createdAt > $1.createdAt }
      .prefix(256)
      .map { $0 }
  }

  private func trimmedEvidence(_ evidence: [DiscoveryEvidence]) -> [DiscoveryEvidence] {
    let behaviorEvidence = evidence.filter { $0.evidenceType == .behavior }
      .sorted { $0.observedAt > $1.observedAt }
      .prefix(180)
    let assetEvidence = evidence.filter { $0.evidenceType != .behavior }
      .sorted { $0.observedAt > $1.observedAt }
      .prefix(720)
    return (behaviorEvidence + assetEvidence)
      .sorted { $0.observedAt > $1.observedAt }
      .map { $0 }
  }

  private static let snapshotRecordKinds: [RecordKind] = [
    .agent,
    .mcpServer,
    .skill,
    .contextFile,
    .memory,
    .runtimeProcess,
    .evidence,
    .permissionState,
    .event,
  ]

  private static let runtimeObservationRecordKinds: [RecordKind] = [
    .agent,
    .runtimeProcess,
    .evidence,
    .permissionState,
    .event,
  ]

  private func append<T: Encodable>(_ values: [T], kind: String, to lines: inout [String]) throws {
    for value in values {
      let payload = try JSONEncoder.frost.encode(JSONLRecord(kind: kind, payload: value))
      if let line = String(data: payload, encoding: .utf8) {
        lines.append(line)
      }
    }
  }

  private func latestScanTime(
    agents: [AgentAsset],
    mcpServers: [MCPServerAsset],
    skills: [SkillAsset],
    contextFiles: [ContextFileAsset],
    memories: [MemoryAsset],
    runtimeProcesses: [RuntimeProcessAsset],
    evidence: [DiscoveryEvidence],
    events: [DiscoveryEvent]
  ) -> Date? {
    if let coldStartScan = events.filter({
      $0.kind == .coldStartScan && $0.isColdStartCompletionEvent
    }).map(\.createdAt).max() {
      return coldStartScan
    }

    return
      (events.map(\.createdAt)
      + agents.map(\.lastScannedAt)
      + mcpServers.map(\.discoveredAt)
      + skills.map(\.discoveredAt)
      + contextFiles.map(\.discoveredAt)
      + runtimeProcesses.map(\.lastSeenAt)
      + evidence.map(\.observedAt)
      + memories.compactMap(\.lastModifiedAt)).max()
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

private struct JSONLRecord<T: Encodable>: Encodable {
  var kind: String
  var payload: T
}

extension AgentAsset {
  fileprivate var primaryStoreKey: String {
    if let path = configPaths.first {
      return "agent:\(normalizedName):config:\(path)"
    }
    if let path = installPaths.first {
      return "agent:\(normalizedName):install:\(path)"
    }
    if let path = executablePaths.first {
      return "agent:\(normalizedName):exec:\(path)"
    }
    if let workspace = workspacePaths.first {
      return "agent:\(normalizedName):workspace:\(workspace)"
    }
    return "agent:\(normalizedName)"
  }

  fileprivate func mergeKeyMatches(_ other: AgentAsset) -> Bool {
    guard normalizedName == other.normalizedName else {
      return false
    }

    return intersects(configPaths, other.configPaths)
      || intersects(installPaths, other.installPaths)
      || intersects(executablePaths, other.executablePaths)
      || intersects(bundleIdentifiers, other.bundleIdentifiers)
      || intersects(workspacePaths, other.workspacePaths)
      || !normalizedName.isEmpty
  }
}

private func intersects<T: Hashable>(_ lhs: [T], _ rhs: [T]) -> Bool {
  !Set(lhs).intersection(Set(rhs)).isEmpty
}
