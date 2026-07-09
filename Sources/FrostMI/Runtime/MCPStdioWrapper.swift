import Foundation

enum MCPStdioWrapper {
  static func run(arguments: [String] = CommandLine.arguments) -> Int32 {
    do {
      let options = try MCPWrapperOptions.parse(arguments: arguments)
      let database = try FrostDatabase(url: options.databaseURL ?? FrostDatabase.defaultURL())
      let appender = RuntimeEventAppender(store: RuntimeEventStore(database: database))
      let correlator = MCPJSONRPCCorrelator(
        sessionId: options.sessionId,
        agentName: options.agentName,
        source: "mcp-stdio-wrapper"
      ) { event in
        appender.append(event)
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = options.command

      let childInput = Pipe()
      let childOutput = Pipe()
      let childError = Pipe()
      process.standardInput = childInput
      process.standardOutput = childOutput
      process.standardError = childError

      let stdinCapture = JSONLineBuffer { line in
        correlator.observe(line: line, direction: .clientToServer)
      }
      let stdoutCapture = JSONLineBuffer { line in
        correlator.observe(line: line, direction: .serverToClient)
      }

      FileHandle.standardInput.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
          try? childInput.fileHandleForWriting.close()
          return
        }
        stdinCapture.consume(data)
        childInput.fileHandleForWriting.write(data)
      }
      childOutput.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
          return
        }
        stdoutCapture.consume(data)
        FileHandle.standardOutput.write(data)
      }
      childError.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
          return
        }
        FileHandle.standardError.write(data)
      }

      try process.run()
      process.waitUntilExit()

      FileHandle.standardInput.readabilityHandler = nil
      childOutput.fileHandleForReading.readabilityHandler = nil
      childError.fileHandleForReading.readabilityHandler = nil
      stdinCapture.finish()
      stdoutCapture.finish()
      appender.flush()
      return process.terminationStatus
    } catch {
      FileHandle.standardError.write(
        Data("MCP stdio wrapper failed: \(error.localizedDescription)\n".utf8))
      return 1
    }
  }

  static func runSelfTest() -> Int32 {
    do {
      let databaseURL = RuntimeEventSelfTests.temporaryDatabaseURL(label: "mcp-wrapper")
      let sessionId = "mcp-wrapper-self-test"
      let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
      let process = Process()
      process.executableURL = executable
      process.arguments = [
        "--mcp-stdio-wrapper",
        "--db",
        databaseURL.path,
        "--session",
        sessionId,
        "--agent",
        "codex-cli",
        "--",
        "/usr/bin/python3",
        "-c",
        mcpFixtureServerScript,
      ]
      let input = Pipe()
      let output = Pipe()
      let error = Pipe()
      process.standardInput = input
      process.standardOutput = output
      process.standardError = error
      try process.run()
      let requestLines =
        [
          #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#,
          #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"README.md"}}}"#,
        ].joined(separator: "\n") + "\n"
      input.fileHandleForWriting.write(Data(requestLines.utf8))
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
      let stdout =
        String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let stderr =
        String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      guard process.terminationStatus == 0 else {
        print(
          "MCP wrapper self-test failed: wrapper exited \(process.terminationStatus). \(stderr)")
        return 1
      }
      guard stdout.contains(#""tools""#), stdout.contains(#""read_file""#) else {
        print("MCP wrapper self-test failed: fixture server responses were not forwarded.")
        return 1
      }
      let store = try RuntimeEventStore(url: databaseURL)
      let events = try store.loadEvents(sessionId: sessionId)
      let graphs = try store.loadSessionGraphs()
      let kinds = Set(events.map(\.kind))
      guard kinds.contains(.mcpToolList),
        kinds.contains(.mcpToolCall),
        kinds.contains(.mcpToolResult),
        let graph = graphs.first(where: { $0.sessionId == sessionId }),
        graph.nodeCount >= 4,
        graph.edgeCount >= 3
      else {
        print(
          "MCP wrapper self-test failed: missing captured MCP events or graph edges. events=\(events.count) graphs=\(graphs.count)"
        )
        return 1
      }
      print(
        "MCP wrapper self-test passed: events=\(events.count) graphs=\(graphs.count) graphEdges=\(graph.edgeCount)"
      )
      return 0
    } catch {
      print("MCP wrapper self-test failed: \(error.localizedDescription)")
      return 1
    }
  }
}

private struct MCPWrapperOptions {
  var command: [String]
  var sessionId: String
  var agentName: String?
  var databaseURL: URL?

  static func parse(arguments: [String]) throws -> MCPWrapperOptions {
    guard let wrapperIndex = arguments.firstIndex(of: "--mcp-stdio-wrapper") else {
      throw MCPWrapperError.invalidArguments("missing --mcp-stdio-wrapper")
    }
    var index = arguments.index(after: wrapperIndex)
    var sessionId = "mcp-\(UUID().uuidString)"
    var agentName: String?
    var databaseURL: URL?
    var command: [String] = []

    while index < arguments.count {
      let value = arguments[index]
      if value == "--" {
        command = Array(arguments[arguments.index(after: index)...])
        break
      }
      switch value {
      case "--session":
        index += 1
        guard index < arguments.count else {
          throw MCPWrapperError.invalidArguments("missing value for --session")
        }
        sessionId = arguments[index]
      case "--agent":
        index += 1
        guard index < arguments.count else {
          throw MCPWrapperError.invalidArguments("missing value for --agent")
        }
        agentName = arguments[index]
      case "--db":
        index += 1
        guard index < arguments.count else {
          throw MCPWrapperError.invalidArguments("missing value for --db")
        }
        databaseURL = URL(fileURLWithPath: arguments[index])
      default:
        throw MCPWrapperError.invalidArguments("unknown option \(value)")
      }
      index += 1
    }

    guard !command.isEmpty else {
      throw MCPWrapperError.invalidArguments(
        "usage: FrostMI --mcp-stdio-wrapper [--db path] [--session id] [--agent name] -- command args..."
      )
    }
    return MCPWrapperOptions(
      command: command,
      sessionId: sessionId,
      agentName: agentName,
      databaseURL: databaseURL
    )
  }
}

private enum MCPWrapperError: Error, LocalizedError {
  case invalidArguments(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      message
    }
  }
}

private enum MCPDirection {
  case clientToServer
  case serverToClient
}

private final class MCPJSONRPCCorrelator: @unchecked Sendable {
  private struct RequestContext {
    var method: String
    var toolName: String?
  }

  private let lock = NSLock()
  private let sessionId: String
  private let agentName: String?
  private let source: String
  private let emit: (RuntimeEventRecord) -> Void
  private var requests: [String: RequestContext] = [:]

  init(
    sessionId: String,
    agentName: String?,
    source: String,
    emit: @escaping (RuntimeEventRecord) -> Void
  ) {
    self.sessionId = sessionId
    self.agentName = agentName
    self.source = source
    self.emit = emit
  }

  func observe(line: String, direction: MCPDirection) {
    guard let object = parseJSONObject(line) else { return }
    switch direction {
    case .clientToServer:
      observeClientMessage(object)
    case .serverToClient:
      observeServerMessage(object)
    }
  }

  private func observeClientMessage(_ object: [String: Any]) {
    guard let method = object["method"] as? String else { return }
    let requestId = jsonRPCId(object["id"])
    let params = object["params"] as? [String: Any]
    let toolName = params?["name"] as? String
    if let requestId {
      lock.lock()
      requests[requestId] = RequestContext(method: method, toolName: toolName)
      lock.unlock()
    }

    switch method {
    case "tools/list":
      emit(
        event(
          kind: .mcpToolList,
          method: method,
          toolName: nil,
          message: "MCP tools/list requested.",
          correlationKey: requestId
        ))
    case "tools/call":
      emit(
        event(
          kind: .mcpToolCall,
          method: method,
          toolName: toolName,
          message: "MCP tools/call requested for \(toolName ?? "unknown tool").",
          correlationKey: requestId,
          metadata: paramsSummary(params)
        ))
    default:
      break
    }
  }

  private func observeServerMessage(_ object: [String: Any]) {
    guard let requestId = jsonRPCId(object["id"]) else { return }
    lock.lock()
    let context = requests.removeValue(forKey: requestId)
    lock.unlock()
    guard let context else { return }

    if let error = object["error"] as? [String: Any] {
      emit(
        event(
          kind: .mcpError,
          method: context.method,
          toolName: context.toolName,
          message: "MCP \(context.method) returned error.",
          correlationKey: requestId,
          metadata: paramsSummary(error)
        ))
      return
    }

    switch context.method {
    case "tools/list":
      emit(
        event(
          kind: .mcpToolResult,
          method: context.method,
          toolName: nil,
          message: "MCP tools/list response captured.",
          correlationKey: requestId,
          metadata: resultSummary(object["result"])
        ))
    case "tools/call":
      emit(
        event(
          kind: .mcpToolResult,
          method: context.method,
          toolName: context.toolName,
          message: "MCP tools/call response captured for \(context.toolName ?? "unknown tool").",
          correlationKey: requestId,
          metadata: resultSummary(object["result"])
        ))
    default:
      break
    }
  }

  private func event(
    kind: RuntimeEventKind,
    method: String,
    toolName: String?,
    message: String,
    correlationKey: String?,
    metadata: [String: String] = [:]
  ) -> RuntimeEventRecord {
    RuntimeEventRecord(
      sessionId: sessionId,
      agentName: agentName,
      kind: kind,
      timestamp: Date(),
      source: source,
      method: method,
      toolName: toolName,
      message: message,
      correlationKey: correlationKey,
      metadata: metadata
    )
  }

  private func parseJSONObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object
  }

  private func jsonRPCId(_ value: Any?) -> String? {
    switch value {
    case let string as String:
      string
    case let number as NSNumber:
      number.stringValue
    default:
      nil
    }
  }

  private func paramsSummary(_ object: [String: Any]?) -> [String: String] {
    guard let object else { return [:] }
    var summary: [String: String] = [:]
    if let arguments = object["arguments"] as? [String: Any] {
      summary["argumentKeys"] = arguments.keys.sorted().joined(separator: ",")
    }
    if let code = object["code"] {
      summary["errorCode"] = "\(code)"
    }
    if let message = object["message"] {
      summary["errorMessage"] = "\(message)"
    }
    return summary
  }

  private func resultSummary(_ result: Any?) -> [String: String] {
    guard let result = result as? [String: Any] else { return [:] }
    var summary: [String: String] = [:]
    if let tools = result["tools"] as? [[String: Any]] {
      summary["toolCount"] = String(tools.count)
      summary["toolNames"] = tools.compactMap { $0["name"] as? String }.sorted().joined(
        separator: ",")
    }
    if let content = result["content"] as? [Any] {
      summary["contentItems"] = String(content.count)
    }
    if let isError = result["isError"] as? Bool {
      summary["isError"] = String(isError)
    }
    return summary
  }
}

private final class JSONLineBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = Data()
  private let onLine: (String) -> Void

  init(onLine: @escaping (String) -> Void) {
    self.onLine = onLine
  }

  func consume(_ data: Data) {
    lock.lock()
    buffer.append(data)
    let lines = drainCompleteLines()
    lock.unlock()
    for line in lines where !line.isEmpty {
      onLine(line)
    }
  }

  func finish() {
    lock.lock()
    let remaining = String(data: buffer, encoding: .utf8)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    buffer.removeAll()
    lock.unlock()
    if let remaining, !remaining.isEmpty {
      onLine(remaining)
    }
  }

  private func drainCompleteLines() -> [String] {
    var lines: [String] = []
    while let newline = buffer.firstIndex(of: 10) {
      let lineData = buffer[..<newline]
      buffer.removeSubrange(...newline)
      if let line = String(data: lineData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      {
        lines.append(line)
      }
    }
    return lines
  }
}

private final class RuntimeEventAppender: @unchecked Sendable {
  private let store: RuntimeEventStore
  private let queue = DispatchQueue(label: "frostmi.runtime.event.appender")
  private let group = DispatchGroup()

  init(store: RuntimeEventStore) {
    self.store = store
  }

  func append(_ event: RuntimeEventRecord) {
    group.enter()
    queue.async {
      defer { self.group.leave() }
      do {
        try self.store.append(event)
      } catch {
        FileHandle.standardError.write(
          Data("FrostMI runtime event append failed: \(error.localizedDescription)\n".utf8))
      }
    }
  }

  func flush() {
    _ = group.wait(timeout: .now() + 5)
  }
}

private let mcpFixtureServerScript = """
  import json
  import sys

  for line in sys.stdin:
      if not line.strip():
          continue
      request = json.loads(line)
      method = request.get("method")
      if method == "tools/list":
          response = {
              "jsonrpc": "2.0",
              "id": request.get("id"),
              "result": {
                  "tools": [
                      {
                          "name": "read_file",
                          "description": "Read a file",
                          "inputSchema": {
                              "type": "object",
                              "properties": {"path": {"type": "string"}},
                          },
                      }
                  ]
              },
          }
      elif method == "tools/call":
          response = {
              "jsonrpc": "2.0",
              "id": request.get("id"),
              "result": {
                  "content": [{"type": "text", "text": "ok"}],
                  "isError": False,
              },
          }
      else:
          response = {
              "jsonrpc": "2.0",
              "id": request.get("id"),
              "error": {"code": -32601, "message": "method not found"},
          }
      sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\\n")
      sys.stdout.flush()
  """
