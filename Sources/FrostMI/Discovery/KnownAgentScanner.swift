import Foundation

final class KnownAgentScanner {
  private let registry: FingerprintRegistry
  private let mcpParser: MCPConfigParser
  private let skillScanner: SkillScanner
  private let memoryScanner: MemoryFileScanner
  private let config: DiscoveryConfiguration

  init(
    registry: FingerprintRegistry,
    mcpParser: MCPConfigParser = MCPConfigParser(),
    skillScanner: SkillScanner,
    memoryScanner: MemoryFileScanner,
    config: DiscoveryConfiguration
  ) {
    self.registry = registry
    self.mcpParser = mcpParser
    self.skillScanner = skillScanner
    self.memoryScanner = memoryScanner
    self.config = config
  }

  func scan(deadline: Date? = nil) -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    let now = Date()

    for fingerprint in registry.fingerprints {
      guard !isExpired(deadline) else { break }
      var evidence: [DiscoveryEvidence] = []
      var installPaths: [String] = []
      var configPaths: [String] = []
      var mcpConfigPaths: [String] = []
      var skillPaths: [String] = []
      var cachePaths: [String] = []
      var memoryPaths: [String] = []
      var workspacePaths: [String] = []
      var confidence = 0

      for path in fingerprint.installPaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path) where shouldAccess(url) {
          if DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url) {
            installPaths.append(url.path)
            confidence += fingerprint.confidenceWeights.installPath
            evidence.append(
              evidenceRecord(
                .knownPath, fingerprint: fingerprint, path: url.path,
                delta: fingerprint.confidenceWeights.installPath,
                summary: "Known install path exists"
              ))
          }
        }
      }

      for path in fingerprint.configPaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path) where shouldAccess(url) {
          if DiscoveryUtilities.fileExists(url)
            && configPathShouldCount(url, fingerprint: fingerprint)
          {
            configPaths.append(url.path)
            confidence += fingerprint.confidenceWeights.configPath
            evidence.append(
              evidenceRecord(
                .config, fingerprint: fingerprint, path: url.path,
                delta: fingerprint.confidenceWeights.configPath,
                summary: "Known config path exists"))
          }
        }
      }

      for path in fingerprint.mcpConfigPaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path) where shouldAccess(url) {
          if DiscoveryUtilities.fileExists(url)
            && configPathShouldCount(url, fingerprint: fingerprint)
          {
            mcpConfigPaths.append(url.path)
            confidence += fingerprint.confidenceWeights.mcpConfig
            evidence.append(
              evidenceRecord(
                .mcpConfig, fingerprint: fingerprint, path: url.path,
                delta: fingerprint.confidenceWeights.mcpConfig,
                summary: "MCP-capable config path exists"))
          }
        }
      }

      for path in fingerprint.skillPaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path)
        where shouldAccess(url) && DiscoveryUtilities.directoryExists(url)
          && skillPathShouldCount(path, fingerprint: fingerprint, confidence: confidence) {
          skillPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.skill
          evidence.append(
            evidenceRecord(
              .skill, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.skill, summary: "Skill directory exists"))
        }
      }

      for path in fingerprint.cachePaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path) where shouldAccess(url) {
          if (DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url))
            && supportPathShouldCount(url, fingerprint: fingerprint)
          {
            cachePaths.append(url.path)
            confidence += fingerprint.confidenceWeights.cache
            evidence.append(
              evidenceRecord(
                .knownPath, fingerprint: fingerprint, path: url.path,
                delta: fingerprint.confidenceWeights.cache, summary: "Cache path exists"))
          }
        }
      }

      for path in fingerprint.memoryPaths {
        guard !isExpired(deadline) else { break }
        for url in expandedCandidates(path) where shouldAccess(url) {
          if (DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url))
            && supportPathShouldCount(url, fingerprint: fingerprint)
          {
            memoryPaths.append(url.path)
            confidence += fingerprint.confidenceWeights.memory
            evidence.append(
              evidenceRecord(
                .memoryFile, fingerprint: fingerprint, path: url.path,
                delta: fingerprint.confidenceWeights.memory, summary: "Memory/cache path exists"))
          }
        }
      }

      let directConfidence = confidence
      for root in config.scanRoots where DiscoveryUtilities.directoryExists(root) {
        guard !isExpired(deadline) else { break }
        for marker in fingerprint.projectMarkers {
          guard !isExpired(deadline) else { break }
          for markerURL in matchingMarkerURLs(marker, in: root) {
            guard
              projectMarkerShouldCount(
                marker, markerURL: markerURL, fingerprint: fingerprint,
                directConfidence: directConfidence)
            else { continue }
            workspacePaths.append(root.path)
            if isMCPConfigMarker(markerURL) {
              mcpConfigPaths.append(markerURL.path)
            }
            confidence += fingerprint.confidenceWeights.projectMarker
            evidence.append(
              evidenceRecord(
                .contextFile, fingerprint: fingerprint, path: markerURL.path,
                delta: fingerprint.confidenceWeights.projectMarker, summary: "Project marker exists"
              ))
          }
        }
      }

      guard confidence > 0 else { continue }

      let asset = AgentAsset(
        displayName: fingerprint.displayName,
        normalizedName: fingerprint.normalizedName,
        agentType: fingerprint.agentType,
        vendor: fingerprint.vendor,
        confidence: confidence,
        discoveryMethods: discoveryMethods(for: evidence),
        discoveryEvidenceIds: evidence.map(\.id),
        scopes: scopes(paths: installPaths + configPaths + workspacePaths),
        installPaths: installPaths,
        configPaths: configPaths,
        workspacePaths: workspacePaths,
        cachePaths: cachePaths,
        mcpConfigPaths: mcpConfigPaths,
        skillPaths: skillPaths,
        memoryPaths: memoryPaths,
        managedStatus: confidence >= 60 ? .manageable : .observableOnly,
        runtimeStatus: .unknown,
        riskLevel: .informational,
        firstSeenAt: now,
        lastSeenAt: now,
        lastScannedAt: now
      )

      let linkedEvidence = evidence.map { item in
        var copy = item
        copy.assetId = asset.id
        return copy
      }
      result.evidence.append(contentsOf: linkedEvidence)
      result.agents.append(asset)

      let mcpURLs =
        mcpConfigPaths.map(URL.init(fileURLWithPath:))
        + workspacePaths.flatMap { workspace in
          [".mcp.json", "mcp.json", ".codex/config.toml"].map {
            URL(fileURLWithPath: workspace).appendingPathComponent($0)
          }
        }
      result.mcpServers.append(
        contentsOf: mcpURLs.flatMap {
          mcpParser.parse(
            url: $0, sourceAgentId: asset.id,
            workspacePath: workspaceFor(url: $0, workspaces: workspacePaths))
        })

      let skillURLs =
        skillPaths.map(URL.init(fileURLWithPath:))
        + workspacePaths.flatMap { workspace in
          [".claude/skills", ".agents/skills", "skills"].map {
            URL(fileURLWithPath: workspace).appendingPathComponent($0)
          }
        }
      result.skills.append(
        contentsOf: skillScanner.scan(
          directories: skillURLs, sourceAgentId: asset.id, deadline: deadline))

      let memoryURLs = collectMemoryFiles(paths: memoryPaths, deadline: deadline)
      result.memories.append(
        contentsOf: memoryScanner.scan(files: memoryURLs, sourceAgentId: asset.id))
    }

    suppressTerminalFallbackIfStrongerCandidateExists(result: &result)
    return result
  }

  private func expanded(_ path: String) -> URL {
    DiscoveryUtilities.expandedPath(path, home: config.homeDirectory)
  }

  private func expandedCandidates(_ path: String) -> [URL] {
    if path.hasPrefix("~") || path.hasPrefix("/") {
      return [expanded(path)]
    }
    return config.scanRoots.map { $0.appendingPathComponent(path) }
  }

  private func matchingMarkerURLs(_ marker: String, in root: URL) -> [URL] {
    if marker.contains("*") {
      return wildcardMarkerURLs(marker, in: root)
    }

    let url = root.appendingPathComponent(marker)
    if DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url) {
      return [url]
    }
    return []
  }

  private func wildcardMarkerURLs(_ marker: String, in root: URL) -> [URL] {
    let directoryPart: String
    let pattern: String
    if let slash = marker.lastIndex(of: "/") {
      directoryPart = String(marker[..<slash])
      pattern = String(marker[marker.index(after: slash)...])
    } else {
      directoryPart = ""
      pattern = marker
    }
    let baseDirectory =
      directoryPart.isEmpty ? root : root.appendingPathComponent(directoryPart, isDirectory: true)
    guard DiscoveryUtilities.directoryExists(baseDirectory),
      let names = try? FileManager.default.contentsOfDirectory(atPath: baseDirectory.path)
    else {
      return []
    }

    return names.prefix(config.limits.maxDirectoryEntries)
      .filter { wildcardMatches(pattern: pattern, value: $0) }
      .map { baseDirectory.appendingPathComponent($0) }
      .filter { DiscoveryUtilities.fileExists($0) || DiscoveryUtilities.directoryExists($0) }
  }

  private func wildcardMatches(pattern: String, value: String) -> Bool {
    let regex =
      "^"
      + NSRegularExpression.escapedPattern(for: pattern)
      .replacingOccurrences(of: "\\*", with: ".*") + "$"
    return value.range(of: regex, options: .regularExpression) != nil
  }

  private func configPathShouldCount(_ url: URL, fingerprint: AgentFingerprint) -> Bool {
    let path = url.path.lowercased()
    let isSharedIDEUserSettings =
      path.contains("/library/application support/code/user/settings.json")
      || path.contains("/library/application support/cursor/user/settings.json")
    guard isSharedIDEUserSettings else { return true }

    if fingerprint.normalizedName == "cursor",
      path.contains("/library/application support/cursor/user/settings.json")
    {
      return true
    }

    guard
      let text = DiscoveryUtilities.readSmallTextFile(
        url, maxBytes: min(config.limits.maxFileBytes, 128 * 1024))?.lowercased()
    else {
      return false
    }
    return contentMatchesSharedIDEFingerprint(
      text, fingerprint: fingerprint, path: path)
  }

  private func supportPathShouldCount(_ url: URL, fingerprint: AgentFingerprint) -> Bool {
    let path = url.path.lowercased()
    let isSharedIDESupport =
      path.contains("/library/application support/code/user/globalstorage")
      || path.contains("/library/application support/cursor/user/globalstorage")
    guard isSharedIDESupport else { return true }

    if fingerprint.normalizedName == "cursor",
      path.contains("/library/application support/cursor/")
    {
      return true
    }
    if fingerprint.normalizedName == "unknown-vscode-agent-extension",
      path.contains("/library/application support/code/")
    {
      return true
    }
    return path.contains(fingerprint.normalizedName)
      || path.contains(fingerprint.displayName.normalizedAssetName)
  }

  private func projectMarkerShouldCount(
    _ marker: String,
    markerURL: URL,
    fingerprint: AgentFingerprint,
    directConfidence: Int
  ) -> Bool {
    if fingerprint.normalizedName == "unknown-vscode-agent-extension",
      directConfidence == 0,
      !markerURL.path.lowercased().contains("/.vscode/")
    {
      return false
    }

    if fingerprint.agentType == .desktop, directConfidence == 0 {
      return false
    }

    if isSharedProjectMarker(marker), directConfidence == 0,
      fingerprint.agentType != .unknownCandidate
    {
      return false
    }

    if marker.contains(".vscode/settings.json") || marker.contains(".cursor/settings.json") {
      guard
        let text = DiscoveryUtilities.readSmallTextFile(
          markerURL, maxBytes: min(config.limits.maxFileBytes, 128 * 1024))?.lowercased()
      else {
        return false
      }
      return contentMatchesSharedIDEFingerprint(
        text, fingerprint: fingerprint, path: markerURL.path.lowercased())
    }
    return true
  }

  private func skillPathShouldCount(
    _ path: String, fingerprint: AgentFingerprint, confidence: Int
  ) -> Bool {
    let lower = path.lowercased()
    if lower == "skills" || lower == ".agents/skills" {
      return confidence > 0
    }
    if lower == "~/.claude/skills" || lower.hasSuffix("/.claude/skills") {
      return confidence > 0 || fingerprint.normalizedName == "claude-code"
    }
    if lower == "~/.agents/skills" || lower.hasSuffix("/.agents/skills") {
      return confidence > 0 || fingerprint.normalizedName == "codex-cli"
    }
    return true
  }

  private func isSharedProjectMarker(_ marker: String) -> Bool {
    [
      "AGENTS.md",
      ".mcp.json",
      "mcp.json",
      "SKILL.md",
      "skills",
      ".agents/skills",
    ].contains(marker)
  }

  private func isMCPConfigMarker(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    if name == ".mcp.json" || name == "mcp.json" {
      return true
    }
    let path = url.path.lowercased()
    return path.hasSuffix("/.codex/config.toml")
      || path.hasSuffix("/.cursor/mcp.json")
      || path.hasSuffix("/.windsurf/mcp.json")
  }

  private func contentMatchesSharedIDEFingerprint(
    _ text: String, fingerprint: AgentFingerprint, path: String
  ) -> Bool {
    switch fingerprint.normalizedName {
    case "cline-roocode":
      return text.contains("cline") || text.contains("roocode") || text.contains("roo-code")
        || text.contains("roo code")
    case "continue":
      return text.contains("continue")
    case "unknown-vscode-agent-extension":
      return path.contains("/library/application support/code/user/settings.json")
        && (text.contains("mcpservers") || text.contains("chat.agent") || text.contains("tool"))
    default:
      return true
    }
  }

  private func suppressTerminalFallbackIfStrongerCandidateExists(result: inout DiscoveryScanResult)
  {
    let hasStrongerCandidate = result.agents.contains {
      $0.normalizedName != "unknown-terminal-agent-candidate"
    }
    guard hasStrongerCandidate else { return }
    let removedIds = Set(
      result.agents
        .filter { $0.normalizedName == "unknown-terminal-agent-candidate" }
        .map(\.id))
    guard !removedIds.isEmpty else { return }
    result.agents.removeAll { removedIds.contains($0.id) }
    result.evidence.removeAll { evidence in
      evidence.assetId.map { removedIds.contains($0) } ?? false
    }
  }

  private func shouldAccess(_ url: URL) -> Bool {
    config.allowsAutomaticAccess(to: url)
  }

  private func evidenceRecord(
    _ type: DiscoveryEvidenceType,
    fingerprint: AgentFingerprint,
    path: String,
    delta: Int,
    summary: String
  ) -> DiscoveryEvidence {
    DiscoveryEvidence(
      evidenceType: type,
      source: fingerprint.normalizedName,
      path: path,
      confidenceDelta: delta,
      summary: summary,
      rawKey: URL(fileURLWithPath: path).lastPathComponent
    )
  }

  private func discoveryMethods(for evidence: [DiscoveryEvidence]) -> [DiscoveryMethod] {
    evidence.flatMap { item -> [DiscoveryMethod] in
      switch item.evidenceType {
      case .knownPath:
        [.knownPath]
      case .config:
        [.configSchema]
      case .mcpConfig:
        [.mcpConfigParse]
      case .skill:
        [.skillScan]
      case .contextFile:
        [.workspaceScan]
      case .memoryFile:
        [.memoryScan]
      case .process:
        [.processFingerprint]
      case .keyword:
        [.keywordScan]
      case .behavior:
        [.behaviorFingerprint]
      case .permission:
        []
      }
    }.uniqueSorted()
  }

  private func scopes(paths: [String]) -> [DiscoveryScope] {
    paths.map {
      DiscoveryUtilities.inferredScope(for: URL(fileURLWithPath: $0), home: config.homeDirectory)
    }.uniqueSorted()
  }

  private func workspaceFor(url: URL, workspaces: [String]) -> String? {
    workspaces.first { url.path.hasPrefix($0) }
  }

  private func collectMemoryFiles(paths: [String], deadline: Date?) -> [URL] {
    var files: [URL] = []
    var budget = MemoryCollectionBudget()
    for path in paths {
      guard !isExpired(deadline) else { break }
      guard files.count < config.limits.maxCollectedMemoryFiles else { break }
      let url = URL(fileURLWithPath: path)
      guard shouldAccess(url) else { continue }
      if DiscoveryUtilities.directoryExists(url) {
        collectMemoryFiles(
          in: url, depth: 0, files: &files, budget: &budget, deadline: deadline)
      } else if DiscoveryUtilities.fileExists(url), isMemoryLikeFile(url) {
        files.append(url)
      }
    }
    return files
  }

  private func collectMemoryFiles(
    in directory: URL, depth: Int, files: inout [URL], budget: inout MemoryCollectionBudget,
    deadline: Date?
  ) {
    guard depth <= config.limits.maxDepth,
      budget.visitedDirectories < config.limits.maxScannedDirectories,
      files.count < config.limits.maxCollectedMemoryFiles,
      !isExpired(deadline)
    else {
      return
    }
    budget.visitedDirectories += 1

    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in names.prefix(config.limits.maxDirectoryEntries) {
      guard !isExpired(deadline) else { break }
      guard files.count < config.limits.maxCollectedMemoryFiles else { break }
      if KeywordFileScanner.skipDirectoryNames.contains(name) { continue }
      let url = directory.appendingPathComponent(name)
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      if isDirectory.boolValue {
        collectMemoryFiles(
          in: url, depth: depth + 1, files: &files, budget: &budget, deadline: deadline)
      } else if isMemoryLikeFile(url) {
        files.append(url)
      }
    }
  }

  private func isMemoryLikeFile(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name.hasSuffix(".jsonl") || name.hasSuffix(".sqlite") || name.hasSuffix(".db")
      || name.contains("memory") || name.contains("conversation") || name.contains("session")
      || name.contains("history")
  }

  private func isExpired(_ deadline: Date?) -> Bool {
    guard let deadline else { return false }
    return Date() >= deadline
  }
}

private struct MemoryCollectionBudget {
  var visitedDirectories = 0
}
