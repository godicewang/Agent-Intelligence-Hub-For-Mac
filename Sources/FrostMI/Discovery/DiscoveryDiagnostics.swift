import Foundation

enum DiscoveryDiagnostics {
  static func printColdScanSummary() -> Int32 {
    do {
      let config = DiscoveryConfiguration.default()
      let registry = try FingerprintRegistry.bundled()
      let skillScanner = SkillScanner(limits: config.limits)
      let memoryScanner = MemoryFileScanner(limits: config.limits)
      let scanner = ColdStartScanner(
        knownAgentScanner: KnownAgentScanner(
          registry: registry,
          skillScanner: skillScanner,
          memoryScanner: memoryScanner,
          config: config),
        keywordScanner: KeywordFileScanner(
          config: config,
          skillScanner: skillScanner,
          memoryScanner: memoryScanner),
        processInspector: ProcessInspector(
          behaviorEngine: BehaviorFingerprintEngine(), config: config, registry: registry),
        permissionInspector: FileSystemPermissionInspector(),
        endpointSecurityMonitor: EndpointSecurityMonitor(),
        networkFlowMonitor: NetworkFlowMonitor(),
        config: config)

      let startedAt = Date()
      let result = scanner.runFullScan()
      let elapsed = Date().timeIntervalSince(startedAt)
      print("elapsed=\(String(format: "%.2f", elapsed))s")
      print(
        "raw agents=\(result.agents.count) mcp=\(result.mcpServers.count) skills=\(result.skills.count) context=\(result.contextFiles.count) memory=\(result.memories.count) permissions=\(result.permissionStates.count)"
      )
      if let snapshot = try? mergedSnapshot(for: result) {
        print(
          "merged agents=\(snapshot.agents.count) mcp=\(snapshot.mcpServers.count) skills=\(snapshot.skills.count) context=\(snapshot.contextFiles.count) memory=\(snapshot.memories.count) permissions=\(snapshot.permissionStates.count)"
        )
      }
      print("events:")
      for event in result.events {
        print("- \(event.message)")
      }
      print("mcp:")
      for mcp in result.mcpServers.sorted(by: { $0.configPath < $1.configPath }) {
        print("- \(mcp.name) | \(mcp.configPath)")
      }
      print("context:")
      for context in result.contextFiles.sorted(by: { $0.path < $1.path }) {
        print("- \(context.path)")
      }
      print("memory:")
      for memory in result.memories.sorted(by: { $0.path < $1.path }) {
        print("- \(memory.path)")
      }
      return 0
    } catch {
      print("Discovery diagnostics failed: \(error.localizedDescription)")
      return 1
    }
  }

  private static func mergedSnapshot(for result: DiscoveryScanResult) throws -> DiscoverySnapshot {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FrostMIDiscoveryDiagnostics-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = AssetGraphStore(
      database: try FrostDatabase(url: directory.appendingPathComponent("diag.sqlite")))
    return try store.merge(result)
  }
}
