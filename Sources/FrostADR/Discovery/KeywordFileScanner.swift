import Foundation

final class KeywordFileScanner: @unchecked Sendable {
  static let skipDirectoryNames: Set<String> = [
    ".git", "node_modules", "build", "dist", "DerivedData", "Library/Caches", "Caches",
    ".build", ".swiftpm", "__pycache__",
  ]

  private let config: DiscoveryConfiguration
  private let parser = ConfigParser()
  private let mcpParser = MCPConfigParser()
  private let skillScanner: SkillScanner
  private let memoryScanner: MemoryFileScanner

  private let targetFileNames: Set<String> = [
    "AGENTS.md", "CLAUDE.md", "GEMINI.md", "CODEX.md", ".mcp.json", "mcp.json", "settings.json",
    "config.toml", "tools.json", "skills.json", "memory.json", "session.jsonl",
    "conversation.jsonl",
    "SKILL.md",
  ]

  private let agentKeywords = [
    "agent", "autonomous", "planner", "tool call", "function call", "subagent", "memory",
    "scratchpad", "reasoning", "workspace", "approval",
  ]
  private let llmKeywords = [
    "openai", "anthropic", "claude", "codex", "gemini", "deepseek", "ollama", "litellm",
    "base_url", "api_key", "model", "messages", "tools", "tool_choice", "function_call",
  ]
  private let mcpSkillKeywords = [
    "mcpServers", "model_context_protocol", "tools/list", "tools/call", "stdio", "sse",
    "streamable-http", "SKILL.md", "skill.yaml", "frontmatter",
  ]

  init(config: DiscoveryConfiguration, skillScanner: SkillScanner, memoryScanner: MemoryFileScanner)
  {
    self.config = config
    self.skillScanner = skillScanner
    self.memoryScanner = memoryScanner
  }

  func scan(additionalRoots: [URL] = [], deadline: Date? = nil) -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    var budget = ScanBudget(deadline: deadline)
    let roots = (config.scanRoots + additionalRoots).map { $0.standardizedFileURL }.uniqueSorted()

    for root in roots where DiscoveryUtilities.directoryExists(root) {
      guard budget.canVisitDirectory(config.limits) else { break }
      walk(root, workspaceRoot: root, depth: 0, budget: &budget, result: &result)
    }
    return result
  }

  private func walk(
    _ directory: URL, workspaceRoot: URL, depth: Int, budget: inout ScanBudget,
    result: inout DiscoveryScanResult
  ) {
    guard depth <= config.limits.maxDepth, budget.canVisitDirectory(config.limits) else { return }
    budget.visitedDirectories += 1
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } catch {
      result.evidence.append(
        DiscoveryEvidence(
          evidenceType: .permission,
          source: "keyword-scanner",
          path: directory.path,
          confidenceDelta: 0,
          summary: "Unable to list directory: \(error.localizedDescription)",
          rawKey: "permission-denied"
        ))
      return
    }

    for name in names.prefix(config.limits.maxDirectoryEntries) {
      if Self.skipDirectoryNames.contains(name) { continue }
      let url = directory.appendingPathComponent(name)
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      if isDirectory.boolValue {
        walk(url, workspaceRoot: workspaceRoot, depth: depth + 1, budget: &budget, result: &result)
      } else if shouldInspect(url), budget.canInspectFile(config.limits) {
        budget.inspectedFiles += 1
        inspect(url, workspace: workspaceRoot, deadline: budget.deadline, result: &result)
      }
    }
  }

  private func shouldInspect(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    if targetFileNames.contains(name) { return true }
    if name.hasSuffix(".jsonl")
      && (name.lowercased().contains("session") || name.lowercased().contains("conversation"))
    {
      return true
    }
    return false
  }

  private func inspect(
    _ url: URL, workspace: URL, deadline: Date?, result: inout DiscoveryScanResult
  ) {
    let name = url.lastPathComponent
    if name == "SKILL.md" {
      result.skills.append(
        contentsOf: skillScanner.scan(
          directory: url.deletingLastPathComponent(), deadline: deadline))
      return
    }

    if name == ".mcp.json" || name == "mcp.json" || name == "settings.json" || name == "config.toml"
    {
      result.mcpServers.append(contentsOf: mcpParser.parse(url: url, workspacePath: workspace.path))
    }

    if name.lowercased().contains("memory") || name.lowercased().contains("session")
      || name.lowercased().contains("conversation")
    {
      if let memory = memoryScanner.asset(url: url) {
        result.memories.append(memory)
      }
    }

    guard let text = parser.text(at: url, maxBytes: config.limits.maxFileBytes) else { return }
    let keywords = (agentKeywords + llmKeywords + mcpSkillKeywords).uniqueSorted()
    let hits = parser.keywordHits(in: text, keywords: keywords)
    guard !hits.isEmpty || ["AGENTS.md", "CLAUDE.md", "GEMINI.md", "CODEX.md"].contains(name) else {
      return
    }

    let riskHints = hits.filter {
      $0.range(of: DiscoveryUtilities.sensitiveKeyPattern, options: .regularExpression) != nil
        || ["api_key", "tool_choice", "function_call", "tools/call"].contains($0)
    }
    let context = ContextFileAsset(
      path: url.path,
      workspace: workspace.path,
      detectedAgent: detectedAgentName(from: name, hits: hits),
      keywordHits: hits,
      riskHints: riskHints,
      hash: DiscoveryUtilities.sha256ForFile(url, maxBytes: config.limits.maxFileBytes),
      lastModifiedAt: DiscoveryUtilities.modificationDate(url)
    )
    result.contextFiles.append(context)

    let agent = AgentAsset(
      displayName: context.detectedAgent ?? "Workspace Agent Context",
      normalizedName: context.detectedAgent?.normalizedAssetName ?? "workspace-agent-context",
      agentType: .unknownCandidate,
      confidence: min(75, 20 + hits.count * 5),
      discoveryMethods: [.keywordScan, .workspaceScan],
      scopes: [.workspace],
      configPaths: [url.path],
      workspacePaths: [workspace.path],
      managedStatus: .observableOnly,
      runtimeStatus: .unknown,
      riskLevel: riskHints.isEmpty ? .informational : .medium,
      metadataSummary: "Context file keyword hits: \(hits.prefix(8).joined(separator: ", "))"
    )
    result.agents.append(agent)
    result.evidence.append(
      DiscoveryEvidence(
        assetId: agent.id,
        evidenceType: .keyword,
        source: "keyword-scanner",
        path: url.path,
        confidenceDelta: agent.confidence,
        summary: "Keyword scan identified agent context file",
        rawKey: name
      ))
  }

  private func detectedAgentName(from fileName: String, hits: [String]) -> String? {
    if fileName == "CLAUDE.md" || hits.contains("claude") { return "Claude Context" }
    if fileName == "AGENTS.md" || hits.contains("codex") { return "Agent Context" }
    if fileName == "GEMINI.md" || hits.contains("gemini") { return "Gemini Context" }
    return nil
  }
}

private struct ScanBudget {
  var visitedDirectories = 0
  var inspectedFiles = 0
  var deadline: Date?

  func canVisitDirectory(_ limits: ScanLimits) -> Bool {
    visitedDirectories < limits.maxScannedDirectories && !isExpired
  }

  func canInspectFile(_ limits: ScanLimits) -> Bool {
    inspectedFiles < limits.maxInspectedFiles && !isExpired
  }

  private var isExpired: Bool {
    guard let deadline else { return false }
    return Date() >= deadline
  }
}
