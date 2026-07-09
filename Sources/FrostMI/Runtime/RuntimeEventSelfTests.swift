import Foundation

enum RuntimeEventSelfTests {
  static func runStoreSelfTest() -> Int32 {
    do {
      let url = temporaryDatabaseURL(label: "store")
      let store = try RuntimeEventStore(url: url)
      let sessionId = "self-test-session"
      let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
      let events = [
        RuntimeEventRecord(
          sessionId: sessionId,
          agentName: "codex-cli",
          kind: .llmRequest,
          timestamp: startedAt,
          source: "self-test",
          provider: "openai-compatible",
          message: "User asked agent to inspect a project."
        ),
        RuntimeEventRecord(
          sessionId: sessionId,
          agentName: "codex-cli",
          kind: .mcpToolCall,
          timestamp: startedAt.addingTimeInterval(1),
          source: "self-test",
          method: "tools/call",
          toolName: "read_file",
          message: "MCP tool call captured."
        ),
        RuntimeEventRecord(
          sessionId: sessionId,
          agentName: "codex-cli",
          kind: .mcpToolResult,
          timestamp: startedAt.addingTimeInterval(2),
          source: "self-test",
          method: "tools/call",
          toolName: "read_file",
          message: "MCP tool result captured."
        ),
        RuntimeEventRecord(
          sessionId: sessionId,
          agentName: "codex-cli",
          kind: .fileEvent,
          timestamp: startedAt.addingTimeInterval(3),
          source: "self-test",
          path: "/tmp/FrostMI/AGENTS.md",
          message: "File change captured."
        ),
      ]
      let graphs = try store.append(events)
      let reloadedEvents = try store.loadEvents(sessionId: sessionId)
      guard reloadedEvents.count == events.count else {
        print(
          "Runtime event store self-test failed: expected \(events.count) events, got \(reloadedEvents.count)."
        )
        return 1
      }
      guard let graph = graphs.first(where: { $0.sessionId == sessionId }),
        graph.nodeCount == events.count,
        graph.edgeCount == events.count - 1
      else {
        print("Runtime event store self-test failed: session graph did not preserve event order.")
        return 1
      }
      print(
        "Runtime event store self-test passed: events=\(reloadedEvents.count) graphs=\(graphs.count) graphEdges=\(graph.edgeCount)"
      )
      return 0
    } catch {
      print("Runtime event store self-test failed: \(error.localizedDescription)")
      return 1
    }
  }

  static func runFSEventsSelfTest() -> Int32 {
    let allowDegraded = CommandLine.arguments.contains("--allow-degraded")
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
      .appendingPathComponent(
        ".frostmi-fsevents-self-test-\(UUID().uuidString)",
        isDirectory: true
      )
    do {
      try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? fileManager.removeItem(at: root) }
      let store = try RuntimeEventStore(url: temporaryDatabaseURL(label: "fsevents"))
      let semaphore = DispatchSemaphore(value: 0)
      let watcher = FSEventsWatcher { changes in
        let relevant = changes.filter { $0.path.path.hasPrefix(root.path) }
        guard !relevant.isEmpty else { return }
        let events = relevant.map { change in
          RuntimeEventRecord(
            sessionId: RuntimeEventRecord.localSessionId(
              prefix: "fsevents-self-test",
              timestamp: change.observedAt
            ),
            kind: .fileEvent,
            timestamp: change.observedAt,
            source: "macos-fsevents",
            path: change.path.path,
            message: "FSEvents self-test observed \(change.flagSummary) change.",
            correlationKey: String(change.eventId),
            metadata: [
              "eventId": String(change.eventId),
              "flags": String(change.flags),
              "flagSummary": change.flagSummary,
            ]
          )
        }
        _ = try? store.append(events)
        semaphore.signal()
      }
      let state = watcher.start(paths: [root], latency: 0.15)
      guard state.status == .available else {
        print("FSEvents self-test failed: \(state.message)")
        watcher.stop()
        return 1
      }
      Thread.sleep(forTimeInterval: 0.35)
      let changedFile = root.appendingPathComponent("AGENTS.md")
      try "FrostMI FSEvents self-test\n".write(to: changedFile, atomically: true, encoding: .utf8)
      Thread.sleep(forTimeInterval: 0.2)
      try "FrostMI FSEvents self-test updated\n".write(
        to: changedFile,
        atomically: true,
        encoding: .utf8
      )
      let signal = waitForFSEvent(semaphore: semaphore, timeout: 10)
      watcher.stop()
      guard signal == .success else {
        if allowDegraded {
          print(
            "FSEvents self-test degraded: stream started but this execution environment did not deliver a file event within timeout."
          )
          return 0
        }
        print("FSEvents self-test failed: no event arrived within timeout.")
        return 1
      }
      let events = try store.loadEvents()
      let graphs = try store.loadSessionGraphs()
      guard events.contains(where: { $0.path == changedFile.path }),
        graphs.contains(where: { $0.nodeCount > 0 })
      else {
        print("FSEvents self-test failed: event did not persist to runtime store.")
        return 1
      }
      print(
        "FSEvents self-test passed: events=\(events.count) graphs=\(graphs.count) watched=\(root.path)"
      )
      return 0
    } catch {
      print("FSEvents self-test failed: \(error.localizedDescription)")
      return 1
    }
  }

  static func temporaryDatabaseURL(label: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("FrostMI-\(label)-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("runtime.sqlite")
  }

  private static func waitForFSEvent(
    semaphore: DispatchSemaphore,
    timeout: TimeInterval
  ) -> DispatchTimeoutResult {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
      let result = semaphore.wait(timeout: .now())
      if result == .success {
        return result
      }
    }
    return .timedOut
  }
}
