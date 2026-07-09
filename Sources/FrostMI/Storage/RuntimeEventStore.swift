import Foundation

final class RuntimeEventStore: @unchecked Sendable {
  private let database: FrostDatabase
  private let lock = NSLock()

  init(database: FrostDatabase) {
    self.database = database
  }

  convenience init(url: URL = FrostDatabase.defaultURL()) throws {
    try self.init(database: FrostDatabase(url: url))
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
          event, kind: .runtimeEvent, key: event.id.uuidString, updatedAt: event.timestamp)
      }
      return try rebuildSessionGraphs(sessionIds: Set(events.map(\.sessionId)))
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
      let sessionIds = Set(
        try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent).map(\.sessionId))
      return try rebuildSessionGraphs(sessionIds: sessionIds)
    }
  }

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func rebuildSessionGraphs(sessionIds: Set<String>) throws -> [RuntimeSessionGraph] {
    let allEvents = try database.loadAll(RuntimeEventRecord.self, kind: .runtimeEvent)
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
    let nodes = events.map { event in
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
