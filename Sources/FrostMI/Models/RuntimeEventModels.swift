import Foundation

enum RuntimeEventKind: String, Codable, CaseIterable, Hashable {
  case processObservation
  case llmRequest
  case llmResponse
  case mcpToolList
  case mcpToolCall
  case mcpToolResult
  case mcpError
  case toolCall
  case toolResult
  case commandExec
  case fileEvent
  case networkEvent
  case memoryWrite
  case permissionState

  var graphOrder: Int {
    switch self {
    case .processObservation:
      0
    case .llmRequest:
      10
    case .llmResponse:
      20
    case .mcpToolList:
      30
    case .mcpToolCall, .toolCall:
      40
    case .commandExec:
      50
    case .fileEvent, .networkEvent, .memoryWrite:
      60
    case .mcpToolResult, .toolResult:
      70
    case .mcpError:
      80
    case .permissionState:
      90
    }
  }
}

struct RuntimeEventRecord: Identifiable, Codable, Hashable {
  var id: UUID
  var sessionId: String
  var agentId: UUID?
  var agentName: String?
  var kind: RuntimeEventKind
  var timestamp: Date
  var source: String
  var processId: Int32?
  var parentProcessId: Int32?
  var path: String?
  var url: String?
  var method: String?
  var toolName: String?
  var provider: String?
  var message: String?
  var riskSignal: String?
  var untrusted: Bool
  var correlationKey: String?
  var metadata: [String: String]

  init(
    id: UUID = UUID(),
    sessionId: String,
    agentId: UUID? = nil,
    agentName: String? = nil,
    kind: RuntimeEventKind,
    timestamp: Date = Date(),
    source: String,
    processId: Int32? = nil,
    parentProcessId: Int32? = nil,
    path: String? = nil,
    url: String? = nil,
    method: String? = nil,
    toolName: String? = nil,
    provider: String? = nil,
    message: String? = nil,
    riskSignal: String? = nil,
    untrusted: Bool = false,
    correlationKey: String? = nil,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.sessionId = sessionId
    self.agentId = agentId
    self.agentName = agentName
    self.kind = kind
    self.timestamp = timestamp
    self.source = source
    self.processId = processId
    self.parentProcessId = parentProcessId
    self.path = path
    self.url = url
    self.method = method
    self.toolName = toolName
    self.provider = provider
    self.message = message
    self.riskSignal = riskSignal
    self.untrusted = untrusted
    self.correlationKey = correlationKey
    self.metadata = metadata
  }

  static func localSessionId(prefix: String, timestamp: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd"
    return "\(prefix)-\(formatter.string(from: timestamp))"
  }
}

struct RuntimeSessionGraph: Identifiable, Codable, Hashable {
  var id: String { sessionId }
  var sessionId: String
  var agentNames: [String]
  var startedAt: Date
  var endedAt: Date
  var nodeCount: Int
  var edgeCount: Int
  var nodes: [RuntimeSessionNode]
  var edges: [RuntimeSessionEdge]
  var updatedAt: Date
}

struct RuntimeSessionNode: Identifiable, Codable, Hashable {
  var id: String
  var eventId: UUID
  var kind: RuntimeEventKind
  var title: String
  var timestamp: Date
  var source: String
  var path: String?
  var toolName: String?
  var message: String?
}

struct RuntimeSessionEdge: Identifiable, Codable, Hashable {
  var id: String
  var sourceNodeId: String
  var targetNodeId: String
  var relation: String
  var timestamp: Date
}
