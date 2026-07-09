import Foundation

enum CodexRuntimeCaptureSelfTest {
  static func run() -> Int32 {
    do {
      let rows = processRows()
      let expectedRows = expectedCodexRows(from: rows)
      guard !expectedRows.isEmpty else {
        print("Codex runtime capture self-test failed: no running Codex.app process found.")
        return 1
      }

      let config = DiscoveryConfiguration.default()
      let inspector = try ProcessInspector(
        behaviorEngine: BehaviorFingerprintEngine(),
        config: config,
        registry: .bundled()
      )
      let result = inspector.inspect(observations: rows)
      let codexAgentIds = Set(
        result.agents.filter { $0.normalizedName == "codex-app" }.map(\.id)
      )
      let capturedPids = Set(
        result.runtimeProcesses.filter { runtime in
          guard let sourceAgentId = runtime.sourceAgentId else { return false }
          return codexAgentIds.contains(sourceAgentId)
        }.map(\.pid)
      )
      let expectedPids = Set(expectedRows.map(\.pid))
      let missingPids = expectedPids.subtracting(capturedPids)
      let components = componentSummary(rows: expectedRows)
      if missingPids.isEmpty {
        print(
          "Codex runtime capture self-test passed: expected=\(expectedPids.count) captured=\(capturedPids.intersection(expectedPids).count) components=\(components)"
        )
        return 0
      }

      let missing = expectedRows.filter { missingPids.contains($0.pid) }
        .map { "\($0.pid):\(componentName(for: $0))" }
        .joined(separator: ", ")
      print(
        "Codex runtime capture self-test failed: expected=\(expectedPids.count) captured=\(capturedPids.intersection(expectedPids).count) missing=[\(missing)] components=\(components)"
      )
      return 1
    } catch {
      print("Codex runtime capture self-test failed: \(error.localizedDescription)")
      return 1
    }
  }

  private static func processRows() -> [ProcessObservation] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid=,comm=,args="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    return output.components(separatedBy: .newlines).compactMap(ProcessObservation.init(line:))
  }

  private static func expectedCodexRows(from rows: [ProcessObservation]) -> [ProcessObservation] {
    let rowsByParent = Dictionary(grouping: rows, by: \.ppid)
    let rootPids = rows.filter { row in
      row.arguments.contains("/Applications/Codex.app/Contents/MacOS/Codex")
        || row.arguments == "/Applications/Codex.app/Contents/MacOS/Codex"
    }.map(\.pid)
    var descendants: Set<Int32> = Set(rootPids)
    var queue = rootPids
    while let pid = queue.first {
      queue.removeFirst()
      for child in rowsByParent[pid] ?? [] where !descendants.contains(child.pid) {
        descendants.insert(child.pid)
        queue.append(child.pid)
      }
    }

    return rows.filter { row in
      let text = "\(row.command) \(row.arguments)"
      let isCodexBundleProcess = text.contains("/Applications/Codex.app/")
      let isCodexComputerUse =
        text.contains("/.codex/computer-use/")
        || text.contains("Codex Computer Use.app")
      return isCodexBundleProcess || (isCodexComputerUse && descendants.contains(row.ppid))
    }.sorted { $0.pid < $1.pid }
  }

  private static func componentSummary(rows: [ProcessObservation]) -> String {
    let counts = Dictionary(grouping: rows.map(componentName), by: { $0 })
      .mapValues(\.count)
    return counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: ",")
  }

  private static func componentName(for row: ProcessObservation) -> String {
    let text = "\(row.command) \(row.arguments)"
    if text.contains("app-server") { return "app-server" }
    if text.contains("node_repl") { return "node_repl" }
    if text.contains("Codex (Renderer)") { return "renderer" }
    if text.contains("Codex (Service)") { return "service" }
    if text.contains("crashpad") { return "crashpad" }
    if text.contains("bare-modifier-monitor") { return "modifier-monitor" }
    if text.contains("Computer Use") || text.contains("SkyComputerUse") {
      return "computer-use"
    }
    if text.contains("/Applications/Codex.app/Contents/MacOS/Codex") { return "main" }
    if text.contains("/Applications/Codex.app/") { return "bundle-helper" }
    return URL(fileURLWithPath: row.command).lastPathComponent
  }
}
