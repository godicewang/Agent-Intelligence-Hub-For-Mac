import Foundation

final class RuntimeEventStore: @unchecked Sendable {
  struct Retention: Hashable {
    var maxStoredEvents: Int
    var maxGraphNodesPerSession: Int
    var maxFileEvents: Int = 240
    var maxNetworkEvents: Int = 160
    var maxProcessObservations: Int = 32

    static let `default` = Retention(maxStoredEvents: 1_200, maxGraphNodesPerSession: 240)
  }

  private let database: FrostDatabase
  private let retention: Retention
  private let lock = NSLock()

  init(database: FrostDatabase, retention: Retention = .default) {
    self.database = database
    self.retention = retention
  }

  convenience init(url: URL = FrostDatabase.defaultURL(), retention: Retention = .default) throws {
    try self.init(database: FrostDatabase(url: url), retention: retention)
  }

  @discardableResult
  func append(_ event: RuntimeEventRecord) throws -> [RuntimeSessionGraph] {
    try append([event])
  }

  @discardableResult
  func append(_ events: [RuntimeEventRecord]) throws -> [RuntimeSessionGraph] {
    guard !events.isEmpty else { return try loadSessionGraphs() }
    return try withLock {
      for event in events {
        try database.upsert(
          event, kind: .runtimeEvent, key: event.persistenceKey, updatedAt: event.timestamp)
      }
      var allEvents = try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
      let kindPruned = try trimNoisyEventKinds(allEvents)
      if kindPruned > 0 {
        allEvents = try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
      }
      let globalPruned = try database.trimToNewest(retention.maxStoredEvents, kind: .runtimeEvent)
      if globalPruned > 0 {
        allEvents = try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
      }
      let removedCount = kindPruned + globalPruned
      let sessionIds: Set<String>
      if removedCount > 0 {
        try database.delete(kind: .runtimeSessionGraph)
        sessionIds = Set(allEvents.map(\.sessionId))
        try? database.optimize()
      } else {
        sessionIds = Set(events.map(\.sessionId))
      }
      return try rebuildSessionGraphs(sessionIds: sessionIds, allEvents: allEvents)
    }
  }

  func loadEvents() throws -> [RuntimeEventRecord] {
    try withLock {
      try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
        .sorted(by: runtimeEventSort)
    }
  }

  func loadEvents(sessionId: String) throws -> [RuntimeEventRecord] {
    try loadEvents().filter { $0.sessionId == sessionId }
  }

  func loadRecentEvents(limit: Int) throws -> [RuntimeEventRecord] {
    Array(try loadEvents().sorted { $0.timestamp > $1.timestamp }.prefix(max(0, limit)))
  }

  func loadSessionGraphs() throws -> [RuntimeSessionGraph] {
    try withLock {
      try database.loadAll(RuntimeSessionGraph.self, kind: .runtimeSessionGraph)
        .sorted { $0.startedAt > $1.startedAt }
    }
  }

  @discardableResult
  func rebuildAllSessionGraphs() throws -> [RuntimeSessionGraph] {
    try withLock {
      let allEvents = try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
      let sessionIds = Set(allEvents.map(\.sessionId))
      return try rebuildSessionGraphs(sessionIds: sessionIds, allEvents: allEvents)
    }
  }

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func rebuildSessionGraphs(
    sessionIds: Set<String>, allEvents: [RuntimeEventRecord]
  ) throws -> [RuntimeSessionGraph] {
    let grouped = Dictionary(grouping: allEvents.filter { sessionIds.contains($0.sessionId) }) {
      $0.sessionId
    }
    var graphs: [RuntimeSessionGraph] = []
    for sessionId in sessionIds.sorted() {
      guard let events = grouped[sessionId], !events.isEmpty else { continue }
      let graph = makeGraph(sessionId: sessionId, events: events.sorted(by: runtimeEventSort))
      try database.upsert(
        graph, kind: .runtimeSessionGraph, key: sessionId, updatedAt: graph.updatedAt)
      graphs.append(graph)
    }
    return graphs
  }

  private func makeGraph(sessionId: String, events: [RuntimeEventRecord]) -> RuntimeSessionGraph {
    let visibleEvents = Array(events.suffix(retention.maxGraphNodesPerSession))
    let nodes = visibleEvents.map { event in
      RuntimeSessionNode(
        id: event.id.uuidString,
        eventId: event.id,
        kind: event.kind,
        title: title(for: event),
        timestamp: event.timestamp,
        source: event.source,
        path: event.path,
        toolName: event.toolName,
        message: event.message
      )
    }
    let edges = zip(nodes, nodes.dropFirst()).map { source, target in
      RuntimeSessionEdge(
        id: "\(source.id)->\(target.id)",
        sourceNodeId: source.id,
        targetNodeId: target.id,
        relation: "next_observed",
        timestamp: target.timestamp
      )
    }
    return RuntimeSessionGraph(
      sessionId: sessionId,
      agentNames: events.compactMap(\.agentName).uniqueSorted(),
      startedAt: events.map(\.timestamp).min() ?? Date(),
      endedAt: events.map(\.timestamp).max() ?? Date(),
      nodeCount: nodes.count,
      edgeCount: edges.count,
      nodes: nodes,
      edges: edges,
      updatedAt: Date()
    )
  }

  private func trimNoisyEventKinds(_ events: [RuntimeEventRecord]) throws -> Int {
    let limits: [(RuntimeEventKind, Int)] = [
      (.fileEvent, retention.maxFileEvents),
      (.networkEvent, retention.maxNetworkEvents),
      (.processObservation, retention.maxProcessObservations),
    ]
    var removedCount = 0
    for (kind, limit) in limits {
      let overflow = events.filter { $0.kind == kind }
        .sorted { $0.timestamp > $1.timestamp }
        .dropFirst(max(0, limit))
      for event in overflow {
        try database.delete(kind: .runtimeEvent, key: event.persistenceKey)
        if event.persistenceKey != event.id.uuidString {
          try database.delete(kind: .runtimeEvent, key: event.id.uuidString)
        }
        removedCount += 1
      }
    }
    return removedCount
  }

  private func title(for event: RuntimeEventRecord) -> String {
    switch event.kind {
    case .processObservation:
      event.message ?? "Process observed"
    case .llmRequest:
      "LLM request\(event.provider.map { " via \($0)" } ?? "")"
    case .llmResponse:
      "LLM response\(event.provider.map { " via \($0)" } ?? "")"
    case .mcpToolList:
      event.message ?? "MCP tools/list"
    case .mcpToolCall:
      "MCP tool call: \(event.toolName ?? "unknown")"
    case .mcpToolResult:
      "MCP tool result: \(event.toolName ?? "unknown")"
    case .mcpError:
      event.message ?? "MCP error"
    case .toolCall:
      "Tool call: \(event.toolName ?? "unknown")"
    case .toolResult:
      "Tool result: \(event.toolName ?? "unknown")"
    case .commandExec:
      event.message ?? "Command executed"
    case .fileEvent:
      event.path.map { "File event: \(URL(fileURLWithPath: $0).lastPathComponent)" }
        ?? "File event"
    case .networkEvent:
      event.url.map { "Network event: \($0)" } ?? "Network event"
    case .memoryWrite:
      event.path.map { "Memory write: \(URL(fileURLWithPath: $0).lastPathComponent)" }
        ?? "Memory write"
    case .permissionState:
      event.message ?? "Permission state"
    }
  }
}

private func runtimeEventSort(_ lhs: RuntimeEventRecord, _ rhs: RuntimeEventRecord) -> Bool {
  if lhs.timestamp != rhs.timestamp {
    return lhs.timestamp < rhs.timestamp
  }
  if lhs.kind.graphOrder != rhs.kind.graphOrder {
    return lhs.kind.graphOrder < rhs.kind.graphOrder
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
