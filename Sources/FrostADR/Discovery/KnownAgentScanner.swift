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

  func scan() -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    let now = Date()

    for fingerprint in registry.fingerprints {
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
        let url = expanded(path)
        if DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url) {
          installPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.installPath
          evidence.append(
            evidenceRecord(
              .knownPath, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.installPath, summary: "Known install path exists"
            ))
        }
      }

      for path in fingerprint.configPaths {
        let url = expanded(path)
        if DiscoveryUtilities.fileExists(url) {
          configPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.configPath
          evidence.append(
            evidenceRecord(
              .config, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.configPath, summary: "Known config path exists"))
        }
      }

      for path in fingerprint.mcpConfigPaths {
        let url = expanded(path)
        if DiscoveryUtilities.fileExists(url) {
          mcpConfigPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.mcpConfig
          evidence.append(
            evidenceRecord(
              .mcpConfig, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.mcpConfig,
              summary: "MCP-capable config path exists"))
        }
      }

      for path in fingerprint.skillPaths {
        for url in expandedCandidates(path) where DiscoveryUtilities.directoryExists(url) {
          skillPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.skill
          evidence.append(
            evidenceRecord(
              .skill, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.skill, summary: "Skill directory exists"))
        }
      }

      for path in fingerprint.cachePaths {
        let url = expanded(path)
        if DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url) {
          cachePaths.append(url.path)
          confidence += fingerprint.confidenceWeights.cache
          evidence.append(
            evidenceRecord(
              .knownPath, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.cache, summary: "Cache path exists"))
        }
      }

      for path in fingerprint.memoryPaths {
        let url = expanded(path)
        if DiscoveryUtilities.fileExists(url) || DiscoveryUtilities.directoryExists(url) {
          memoryPaths.append(url.path)
          confidence += fingerprint.confidenceWeights.memory
          evidence.append(
            evidenceRecord(
              .memoryFile, fingerprint: fingerprint, path: url.path,
              delta: fingerprint.confidenceWeights.memory, summary: "Memory/cache path exists"))
        }
      }

      for root in config.scanRoots where DiscoveryUtilities.directoryExists(root) {
        for marker in fingerprint.projectMarkers {
          let markerURL = root.appendingPathComponent(marker)
          if DiscoveryUtilities.fileExists(markerURL)
            || DiscoveryUtilities.directoryExists(markerURL)
          {
            workspacePaths.append(root.path)
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
        discoveryMethods: [.knownPath, .configSchema, .workspaceScan],
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
        contentsOf: skillScanner.scan(directories: skillURLs, sourceAgentId: asset.id))

      let memoryURLs = collectMemoryFiles(paths: memoryPaths)
      result.memories.append(
        contentsOf: memoryScanner.scan(files: memoryURLs, sourceAgentId: asset.id))
    }

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

  private func scopes(paths: [String]) -> [DiscoveryScope] {
    paths.map {
      DiscoveryUtilities.inferredScope(for: URL(fileURLWithPath: $0), home: config.homeDirectory)
    }.uniqueSorted()
  }

  private func workspaceFor(url: URL, workspaces: [String]) -> String? {
    workspaces.first { url.path.hasPrefix($0) }
  }

  private func collectMemoryFiles(paths: [String]) -> [URL] {
    var files: [URL] = []
    for path in paths {
      let url = URL(fileURLWithPath: path)
      if DiscoveryUtilities.fileExists(url) {
        files.append(url)
      } else if DiscoveryUtilities.directoryExists(url) {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
          let name = item.lastPathComponent.lowercased()
          if name.hasSuffix(".jsonl") || name.hasSuffix(".sqlite") || name.hasSuffix(".db")
            || name.contains("memory") || name.contains("conversation")
          {
            files.append(item)
          }
        }
      }
    }
    return files
  }
}
