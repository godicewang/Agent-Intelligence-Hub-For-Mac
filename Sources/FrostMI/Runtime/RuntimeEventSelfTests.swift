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

      let boundedStore = try RuntimeEventStore(
        url: temporaryDatabaseURL(label: "bounded"),
        retention: .init(maxStoredEvents: 3, maxGraphNodesPerSession: 2))
      let boundedEvents = (0..<5).map { index in
        RuntimeEventRecord(
          sessionId: "bounded-session",
          kind: .fileEvent,
          timestamp: startedAt.addingTimeInterval(TimeInterval(index)),
          source: "self-test",
          path: "/tmp/FrostMI/\(index).txt",
          message: "Bounded event \(index).")
      }
      let boundedGraphs = try boundedStore.append(boundedEvents)
      let retainedEvents = try boundedStore.loadEvents(sessionId: "bounded-session")
      guard retainedEvents.count == 3,
        boundedGraphs.first?.nodeCount == 2,
        boundedGraphs.first?.edgeCount == 1
      else {
        print("Runtime event store self-test failed: retention or graph node limit was not enforced.")
        return 1
      }

      let prioritizedStore = try RuntimeEventStore(
        url: temporaryDatabaseURL(label: "prioritized"),
        retention: .init(
          maxStoredEvents: 20,
          maxGraphNodesPerSession: 20,
          maxFileEvents: 2,
          maxNetworkEvents: 2,
          maxProcessObservations: 1))
      let noisyEvents = (0..<4).map { index in
        RuntimeEventRecord(
          sessionId: "noisy-session",
          kind: .fileEvent,
          timestamp: startedAt.addingTimeInterval(TimeInterval(index)),
          source: "self-test",
          path: "/tmp/FrostMI/noisy-\(index).txt",
          message: "Noisy file event \(index).")
      }
      _ = try prioritizedStore.append(noisyEvents)
      let prioritizedEvents = try prioritizedStore.loadEvents(sessionId: "noisy-session")
      guard prioritizedEvents.count == 2 else {
        print("Runtime event store self-test failed: noisy file-event quota was not enforced.")
        return 1
      }

      let legacyDatabase = try FrostDatabase(url: temporaryDatabaseURL(label: "legacy-file-events"))
      let legacyStore = RuntimeEventStore(
        database: legacyDatabase,
        retention: .init(
          maxStoredEvents: 20,
          maxGraphNodesPerSession: 20,
          maxFileEvents: 2,
          maxNetworkEvents: 2,
          maxProcessObservations: 1))
      let legacyEvents = (0..<4).map { index in
        RuntimeEventRecord(
          sessionId: "legacy-fsevents-20250701",
          kind: .fileEvent,
          timestamp: startedAt.addingTimeInterval(TimeInterval(index)),
          source: "macos-fsevents",
          path: "/tmp/FrostMI/legacy-\(index).txt",
          message: "Legacy file event \(index).")
      }
      for event in legacyEvents {
        try legacyDatabase.upsert(
          event, kind: .runtimeEvent, key: event.id.uuidString, updatedAt: event.timestamp)
      }
      _ = try legacyStore.append(
        RuntimeEventRecord(
          sessionId: "legacy-maintenance",
          kind: .processObservation,
          timestamp: startedAt.addingTimeInterval(10),
          source: "self-test",
          message: "Trigger legacy retention cleanup."))
      let retainedLegacyEvents = try legacyStore.loadEvents()
      guard retainedLegacyEvents.filter({ $0.kind == .fileEvent }).count == 2 else {
        print("Runtime event store self-test failed: legacy UUID-keyed file events were not pruned.")
        return 1
      }

      let snapshotStore = try RuntimeEventStore(url: temporaryDatabaseURL(label: "snapshots"))
      let firstSnapshot = RuntimeEventRecord(
        sessionId: "network-snapshot-20250701",
        kind: .networkEvent,
        timestamp: startedAt,
        source: "macos-lsof-network-flow",
        processId: 9001,
        url: "tcp://127.0.0.1:11434",
        message: "First real network snapshot.",
        correlationKey: "9001|ollama|127.0.0.1:11434")
      let latestSnapshot = RuntimeEventRecord(
        sessionId: firstSnapshot.sessionId,
        kind: .networkEvent,
        timestamp: startedAt.addingTimeInterval(30),
        source: firstSnapshot.source,
        processId: firstSnapshot.processId,
        url: firstSnapshot.url,
        message: "Latest real network snapshot.",
        correlationKey: firstSnapshot.correlationKey)
      _ = try snapshotStore.append(firstSnapshot)
      _ = try snapshotStore.append(latestSnapshot)
      let coalescedSnapshots = try snapshotStore.loadEvents(sessionId: firstSnapshot.sessionId)
      guard coalescedSnapshots.count == 1,
        coalescedSnapshots.first?.message == latestSnapshot.message
      else {
        print("Runtime event store self-test failed: network snapshots were not coalesced.")
        return 1
      }

      let fileEventStore = try RuntimeEventStore(url: temporaryDatabaseURL(label: "file-events"))
      let firstFileEvent = RuntimeEventRecord(
        sessionId: "fsevents-20250701",
        kind: .fileEvent,
        timestamp: startedAt,
        source: "macos-fsevents",
        path: "/tmp/FrostMI/AGENTS.md",
        message: "First file observation.",
        correlationKey: "1")
      let latestFileEvent = RuntimeEventRecord(
        sessionId: firstFileEvent.sessionId,
        kind: .fileEvent,
        timestamp: startedAt.addingTimeInterval(45),
        source: firstFileEvent.source,
        path: firstFileEvent.path,
        message: "Latest file observation.",
        correlationKey: "2")
      _ = try fileEventStore.append(firstFileEvent)
      _ = try fileEventStore.append(latestFileEvent)
      let coalescedFileEvents = try fileEventStore.loadEvents(sessionId: firstFileEvent.sessionId)
      guard coalescedFileEvents.count == 1,
        coalescedFileEvents.first?.message == latestFileEvent.message
      else {
        print("Runtime event store self-test failed: repeated FSEvents paths were not coalesced.")
        return 1
      }
      print(
        "Runtime event store self-test passed: events=\(reloadedEvents.count) graphs=\(graphs.count) graphEdges=\(graph.edgeCount) retained=\(retainedEvents.count) fileQuota=\(prioritizedEvents.count) legacyFileQuota=\(retainedLegacyEvents.filter { $0.kind == .fileEvent }.count) coalescedNetwork=\(coalescedSnapshots.count) coalescedFiles=\(coalescedFileEvents.count)"
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
