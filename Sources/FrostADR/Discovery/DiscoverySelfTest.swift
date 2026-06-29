import Foundation

enum DiscoverySelfTest {
  static func run() -> Int32 {
    var failures: [String] = []

    check("FingerprintRegistry loads Claude and Codex", failures: &failures) {
      let registry = try FingerprintRegistry.bundled()
      return registry.fingerprints.contains { $0.normalizedName == "claude-code" }
        && registry.fingerprints.contains { $0.normalizedName == "codex-cli" }
    }

    check("Default discovery avoids protected broad scan roots", failures: &failures) {
      let home = fixture("Home")
      let config = DiscoveryConfiguration.default(homeDirectory: home, projectRoot: home)
      let protectedNames = ["Documents", "Desktop", "Downloads", "Library"]
      return config.scanRoots.isEmpty
        && protectedNames.allSatisfy { protectedName in
          !config.scanRoots.contains {
            $0.standardizedFileURL.path.hasPrefix(
              home.appendingPathComponent(protectedName).standardizedFileURL.path)
          }
        }
        && !config.enableFSEventsWatcher
        && !config.enableEndpointSecurityMonitor
        && !config.enableNetworkMonitor
        && !config.enableUserApplicationSupportScan
        && !config.allowsAutomaticAccess(
          to: home.appendingPathComponent("Library/Application Support/Cursor/User/settings.json"))
    }

    check("MCP JSON parser finds servers and risk", failures: &failures) {
      let servers = MCPConfigParser().parse(url: fixture("MCP/mcp.json"))
      return servers.count == 2
        && servers.contains { $0.name == "safe-local" && $0.envKeyNames.contains("OPENAI_API_KEY") }
        && servers.contains { $0.name == "risky-remote" && $0.riskPreScore >= 30 }
    }

    check("MCP TOML parser finds servers", failures: &failures) {
      let servers = MCPConfigParser().parse(url: fixture("MCP/config.toml"))
      return servers.count == 2
        && servers.contains { $0.name == "local" && $0.command == "uvx" }
        && servers.contains { $0.name == "http" && $0.transport == .http }
    }

    check("Skill scanner finds Layer 1 signals", failures: &failures) {
      let skills = SkillScanner().scan(directory: fixture("Skill"))
      return skills.count == 1 && skills[0].hasScripts && skills[0].hasExternalURLs
    }

    check("Keyword scanner finds context and MCP config", failures: &failures) {
      let root = try preparedCodexProject()
      let config = DiscoveryConfiguration.default(homeDirectory: fixture("Home"), projectRoot: root)
      let result = KeywordFileScanner(
        config: config, skillScanner: SkillScanner(), memoryScanner: MemoryFileScanner()
      ).scan(additionalRoots: [root])
      return result.contextFiles.contains { $0.path.hasSuffix("AGENTS.md") }
        && result.mcpServers.contains { $0.name == "fixture" }
    }

    check("Behavior fingerprint scores agent candidate", failures: &failures) {
      let result = BehaviorFingerprintEngine().evaluate(
        BehaviorFingerprintInput(
          processName: "custom-agent",
          executablePath: "/usr/local/bin/custom-agent",
          argv: [
            "custom-agent --base_url https://api.openai.com/v1/chat/completions --tool_choice auto"
          ],
          cwd: nil,
          parentChain: ["zsh", "node"],
          connectedLLMProviders: ["OpenAI"],
          spawnedCommandCount: 1,
          workspaceTouched: "/tmp/workspace",
          hasWorkspaceAgentContext: true,
          hasMCPOrToolSchema: true,
          wroteSessionLikeFile: true,
          observedLLMCommandLoop: false
        ))
      return result.score >= 60
        && (result.state == .agentCandidate || result.state == .confirmedAgent)
    }

    check("AssetGraphStore persists and merges", failures: &failures) {
      let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("FrostADR.sqlite")
      let store = try AssetGraphStore(database: FrostDatabase(url: dbURL))
      var first = DiscoveryScanResult()
      first.agents = [
        AgentAsset(
          displayName: "Fixture Agent",
          agentType: .known,
          confidence: 50,
          discoveryMethods: [.knownPath],
          configPaths: ["/tmp/fixture-agent/config.json"]
        )
      ]
      _ = try store.merge(first)

      var second = DiscoveryScanResult()
      second.agents = [
        AgentAsset(
          displayName: "Fixture Agent",
          agentType: .known,
          confidence: 80,
          discoveryMethods: [.configSchema],
          configPaths: ["/tmp/fixture-agent/config.json"]
        )
      ]
      let snapshot = try store.merge(second)
      return snapshot.agents.count == 1 && snapshot.agents[0].confidence == 80
    }

    if failures.isEmpty {
      print("Discovery self-test passed.")
      return 0
    }
    print("Discovery self-test failed:")
    for failure in failures {
      print("- \(failure)")
    }
    return 1
  }

  private static func check(_ name: String, failures: inout [String], body: () throws -> Bool) {
    do {
      if try !body() {
        failures.append(name)
      }
    } catch {
      failures.append("\(name): \(error.localizedDescription)")
    }
  }

  private static func fixture(_ relativePath: String) -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Tests/FrostADRTests/Fixtures", isDirectory: true)
      .appendingPathComponent(relativePath)
  }

  private static func preparedCodexProject() throws -> URL {
    let source = fixture("CodexProject")
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("FrostADRDiscoverySelfTest-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("CodexProject", isDirectory: true)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: destination)

    let ignoredAgentFile = destination.appendingPathComponent("AGENTS.md")
    if FileManager.default.fileExists(atPath: ignoredAgentFile.path) {
      try FileManager.default.removeItem(at: ignoredAgentFile)
    }

    try FileManager.default.copyItem(
      at: source.appendingPathComponent("AGENTS.fixture.md"),
      to: ignoredAgentFile
    )
    return destination
  }
}
