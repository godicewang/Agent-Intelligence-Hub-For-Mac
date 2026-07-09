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
    let frostSupportRoot =
      (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support"))
      .appendingPathComponent("FrostADR", isDirectory: true)
    let codexProcessRoot = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/process_manager", isDirectory: true)
    let watchRoots = ([codexProcessRoot, frostSupportRoot].filter {
      fileManager.fileExists(atPath: $0.path)
    } + [frostSupportRoot])
      .map { $0.standardizedFileURL }
      .uniqueSorted()
    let root = frostSupportRoot
    let testDirectory = root.appendingPathComponent(
      "FrostMI-FSEvents-SelfTest-\(UUID().uuidString)",
      isDirectory: true
    )
    let changedFile = testDirectory.appendingPathComponent("fsevents-check.txt")
    do {
      try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
      defer { try? fileManager.removeItem(at: testDirectory) }
      let store = try RuntimeEventStore(url: temporaryDatabaseURL(label: "fsevents"))
      let semaphore = DispatchSemaphore(value: 0)
      let watcher = FSEventsWatcher { changes in
        let relevant = changes.filter { change in
          watchRoots.contains { root in
            change.path.standardizedFileURL.path.hasPrefix(root.path + "/")
          }
        }
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
      let state = watcher.start(paths: watchRoots, latency: 0.15, useRootFallback: true)
      guard state.status == .available else {
        print("FSEvents self-test failed: \(state.message)")
        watcher.stop()
        return 1
      }
      Thread.sleep(forTimeInterval: 0.35)
      try writeFSEventsSelfTestFile(changedFile)
      watcher.flushSync()
      let signal = waitForFSEvent(semaphore: semaphore, timeout: 15)
      watcher.stop()
      guard signal == .success else {
        if allowDegraded {
          print(
            "FSEvents self-test degraded: stream started but no real FrostMI application-support event arrived within timeout."
          )
          return 0
        }
        print(
          "FSEvents self-test failed: no real FrostMI application-support event arrived within timeout."
        )
        return 1
      }
      let events = try store.loadEvents()
      let graphs = try store.loadSessionGraphs()
      guard events.contains(where: { event in
        guard let path = event.path else { return false }
        return watchRoots.contains { root in path.hasPrefix(root.path + "/") }
      }),
        graphs.contains(where: { $0.nodeCount > 0 })
      else {
        print("FSEvents self-test failed: event did not persist to runtime store.")
        return 1
      }
      let observedRoots = watchRoots.filter { root in
        events.contains { event in
          guard let path = event.path else { return false }
          return path.hasPrefix(root.path + "/")
        }
      }.map(\.path).joined(separator: ",")
      let watchedRoots = watchRoots.map(\.path).joined(separator: ",")
      print(
        "FSEvents self-test passed: events=\(events.count) graphs=\(graphs.count) mode=root-filter watched=\(watchedRoots) observed=\(observedRoots)"
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

  private static func writeFSEventsSelfTestFile(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c",
      """
      printf '%s\\n' 'FrostMI FSEvents self-test' > "$1"
      sleep 0.2
      printf '%s\\n' 'FrostMI FSEvents self-test updated' > "$1"
      """,
      "frostmi-fsevents-writer",
      url.path,
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
  }
}
