import Foundation

struct AgentSensingProfile: Identifiable, Hashable {
  var id: UUID { agent.id }
  var agent: AgentAsset
  var mcpCount: Int
  var skillCount: Int
  var contextCount: Int
  var memoryCount: Int
  var runtimeProcessCount: Int
  var evidenceCount: Int
  var highestRisk: RiskLevel

  var staticAssetCount: Int {
    mcpCount + skillCount + contextCount + memoryCount
  }

  var isRuntimeActive: Bool {
    runtimeProcessCount > 0 || agent.runtimeStatus == .running
  }

  var coverageLabel: String {
    switch (staticAssetCount > 0, runtimeProcessCount > 0) {
    case (true, true):
      "static + runtime"
    case (true, false):
      "static only"
    case (false, true):
      "runtime only"
    case (false, false):
      "agent shell"
    }
  }

  var analysisSummary: String {
    if isRuntimeActive && staticAssetCount > 0 {
      return "该 Agent 同时具备静态资产和运行时进程证据，可用于后续 Session 归因。"
    }
    if isRuntimeActive {
      return "该 Agent 当前存在运行时证据，但静态资产较少，建议后续补充配置或缓存解析。"
    }
    if staticAssetCount > 0 {
      return "该 Agent 当前主要来自静态发现，尚未观察到运行中进程。"
    }
    return "该 Agent 只有基础发现证据，后续需要更多配置、进程或文件变化佐证。"
  }
}

enum AgentSensingAnalyzer {
  static func profiles(from snapshot: DiscoverySnapshot) -> [AgentSensingProfile] {
    snapshot.agents.map { agent in
      let mcpServers = mcpServers(for: agent, snapshot: snapshot)
      let skills = skills(for: agent, snapshot: snapshot)
      let contexts = contextFiles(for: agent, snapshot: snapshot)
      let memories = memories(for: agent, snapshot: snapshot)
      let runtimeProcesses = runtimeProcesses(for: agent, snapshot: snapshot)
      let evidence = snapshot.evidence.filter { $0.assetId == agent.id }
      return AgentSensingProfile(
        agent: agent,
        mcpCount: mcpServers.count,
        skillCount: skills.count,
        contextCount: contexts.count,
        memoryCount: memories.count,
        runtimeProcessCount: runtimeProcesses.count,
        evidenceCount: evidence.count,
        highestRisk: highestRisk(
          agent: agent,
          mcpServers: mcpServers,
          skills: skills
        )
      )
    }
    .sorted {
      if $0.isRuntimeActive != $1.isRuntimeActive {
        return $0.isRuntimeActive && !$1.isRuntimeActive
      }
      if $0.agent.confidence == $1.agent.confidence {
        return $0.agent.displayName < $1.agent.displayName
      }
      return $0.agent.confidence > $1.agent.confidence
    }
  }

  static func mcpServers(for agent: AgentAsset, snapshot: DiscoverySnapshot) -> [MCPServerAsset] {
    let pathSet = Set(agent.mcpConfigPaths + agent.configPaths)
    return snapshot.mcpServers.filter {
      $0.sourceAgentId == agent.id || pathSet.contains($0.configPath)
    }
  }

  static func skills(for agent: AgentAsset, snapshot: DiscoverySnapshot) -> [SkillAsset] {
    snapshot.skills.filter {
      $0.sourceAgentId == agent.id || agent.skillPaths.contains($0.path)
    }
  }

  static func contextFiles(for agent: AgentAsset, snapshot: DiscoverySnapshot) -> [ContextFileAsset]
  {
    snapshot.contextFiles.filter { context in
      if let detectedAgent = context.detectedAgent?.normalizedAssetName,
        detectedAgent == agent.normalizedName
      {
        return true
      }
      if let workspace = context.workspace,
        agent.workspacePaths.contains(where: { workspace == $0 || workspace.hasPrefix($0 + "/") })
      {
        return true
      }
      return agent.workspacePaths.contains { context.path.hasPrefix($0 + "/") }
    }
  }

  static func memories(for agent: AgentAsset, snapshot: DiscoverySnapshot) -> [MemoryAsset] {
    snapshot.memories.filter {
      $0.sourceAgentId == agent.id || agent.memoryPaths.contains($0.path)
    }
  }

  static func runtimeProcesses(for agent: AgentAsset, snapshot: DiscoverySnapshot)
    -> [RuntimeProcessAsset]
  {
    snapshot.runtimeProcesses.filter { process in
      if process.sourceAgentId == agent.id { return true }
      if agent.processIds.contains(process.pid) { return true }
      if let executablePath = process.executablePath,
        agent.executablePaths.contains(executablePath)
      {
        return true
      }
      if let bundleIdentifier = process.bundleIdentifier,
        agent.bundleIdentifiers.contains(bundleIdentifier)
      {
        return true
      }
      return false
    }
  }

  private static func highestRisk(
    agent: AgentAsset,
    mcpServers: [MCPServerAsset],
    skills: [SkillAsset]
  ) -> RiskLevel {
    ([agent.riskLevel] + mcpServers.map(\.riskLevel) + skills.map(\.riskLevel))
      .max(by: { riskRank($0) < riskRank($1) }) ?? .informational
  }

  private static func riskRank(_ risk: RiskLevel) -> Int {
    switch risk {
    case .informational:
      0
    case .low:
      1
    case .medium:
      2
    case .high:
      3
    case .critical:
      4
    }
  }
}
