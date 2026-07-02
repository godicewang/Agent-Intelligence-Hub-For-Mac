import Foundation

final class ColdStartScanner: @unchecked Sendable {
  private let knownAgentScanner: KnownAgentScanner
  private let keywordScanner: KeywordFileScanner
  private let processInspector: ProcessInspector
  private let permissionInspector: FileSystemPermissionInspector
  private let endpointSecurityMonitor: EndpointSecurityMonitor
  private let networkFlowMonitor: NetworkFlowMonitor
  private let config: DiscoveryConfiguration

  var isColdStartEnabled: Bool {
    config.enableColdStartScan
  }

  init(
    knownAgentScanner: KnownAgentScanner,
    keywordScanner: KeywordFileScanner,
    processInspector: ProcessInspector,
    permissionInspector: FileSystemPermissionInspector,
    endpointSecurityMonitor: EndpointSecurityMonitor,
    networkFlowMonitor: NetworkFlowMonitor,
    config: DiscoveryConfiguration
  ) {
    self.knownAgentScanner = knownAgentScanner
    self.keywordScanner = keywordScanner
    self.processInspector = processInspector
    self.permissionInspector = permissionInspector
    self.endpointSecurityMonitor = endpointSecurityMonitor
    self.networkFlowMonitor = networkFlowMonitor
    self.config = config
  }

  func runFullScan() -> DiscoveryScanResult {
    var result = DiscoveryScanResult()
    let deadline = Date().addingTimeInterval(config.limits.maxScanSeconds)
    result.events.append(
      DiscoveryEvent(
        id: UUID(), kind: .coldStartScan, path: nil, message: "Cold start discovery scan started.",
        createdAt: result.scannedAt)
    )

    result.merge(knownAgentScanner.scan(deadline: deadline))
    if !isExpired(deadline) {
      let keywordInputs = keywordScanInputs(for: result.agents)
      result.merge(
        keywordScanner.scan(
          additionalRoots: keywordInputs.roots,
          additionalFiles: keywordInputs.files,
          deadline: deadline
        ))
    }
    if config.enableRuntimeObserver, !isExpired(deadline) {
      result.merge(processInspector.inspectRunningProcesses(deadline: deadline))
    }
    if !config.scanRoots.isEmpty {
      result.permissionStates.append(
        contentsOf: permissionInspector.inspect(paths: config.scanRoots))
    }
    if config.enableEndpointSecurityMonitor {
      result.permissionStates.append(endpointSecurityMonitor.permissionState())
    }
    if config.enableNetworkMonitor {
      result.permissionStates.append(networkFlowMonitor.permissionState())
    }
    let timedOut = isExpired(deadline)
    result.events.append(
      DiscoveryEvent(
        id: UUID(),
        kind: .coldStartScan,
        path: nil,
        message: timedOut
          ? "Cold start discovery scan stopped after the lightweight time budget with \(result.agents.count) agent candidates."
          : "Cold start discovery scan completed with \(result.agents.count) agent candidates.",
        createdAt: Date()
      ))
    return result
  }

  private func isExpired(_ deadline: Date) -> Bool {
    Date() >= deadline
  }

  private func keywordScanInputs(for agents: [AgentAsset]) -> (roots: [URL], files: [URL]) {
    var roots: [URL] = []
    var files: [URL] = []
    let normalizedNames = Set(agents.map(\.normalizedName))

    for agent in agents {
      roots.append(contentsOf: agent.workspacePaths.map(URL.init(fileURLWithPath:)))
      files.append(
        contentsOf: (agent.configPaths + agent.mcpConfigPaths).map(URL.init(fileURLWithPath:)))
    }

    if normalizedNames.contains("codex-cli") || normalizedNames.contains("codex-app") {
      let codexHome = config.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
      files.append(contentsOf: codexSupportFiles(in: codexHome))
      files.append(contentsOf: codexPluginMCPFiles(in: codexHome))
    }

    if normalizedNames.contains("claude-code") {
      let claudeHome = config.homeDirectory.appendingPathComponent(".claude", isDirectory: true)
      files.append(claudeHome.appendingPathComponent("settings.json"))
      files.append(claudeHome.appendingPathComponent("history.jsonl"))
      files.append(contentsOf: claudePluginMCPFiles(in: claudeHome))
    }

    if normalizedNames.contains("gemini-cli") {
      let geminiHome = config.homeDirectory.appendingPathComponent(".gemini", isDirectory: true)
      files.append(geminiHome.appendingPathComponent("GEMINI.md"))
      files.append(geminiHome.appendingPathComponent("settings.json"))
    }

    if normalizedNames.contains("cursor") || normalizedNames.contains("cline-roocode") {
      files.append(contentsOf: cursorSupportFiles())
      files.append(contentsOf: cursorPluginMCPFiles())
    }

    let lingmaRoot = config.homeDirectory.appendingPathComponent(
      ".lingma/extension/local", isDirectory: true)
    files.append(lingmaRoot.appendingPathComponent("mcp.json"))

    return (
      roots: roots.map { $0.standardizedFileURL }.uniqueSorted(),
      files: files.map { $0.standardizedFileURL }.uniqueSorted()
    )
  }

  private func codexSupportFiles(in codexHome: URL) -> [URL] {
    var files = [
      codexHome.appendingPathComponent("AGENTS.md"),
      codexHome.appendingPathComponent("config.toml"),
      codexHome.appendingPathComponent("session_index.jsonl"),
      codexHome.appendingPathComponent("memories_1.sqlite"),
      codexHome.appendingPathComponent("state_5.sqlite"),
      codexHome.appendingPathComponent("goals_1.sqlite"),
    ]
    files.append(
      contentsOf: shallowMatchingFiles(
        in: codexHome.appendingPathComponent("archived_sessions", isDirectory: true)))
    files.append(
      contentsOf: shallowMatchingFiles(
        in: codexHome.appendingPathComponent("sqlite", isDirectory: true)))
    return files
  }

  private func codexPluginMCPFiles(in codexHome: URL) -> [URL] {
    let roots = [
      codexHome.appendingPathComponent(".tmp/plugins/plugins", isDirectory: true),
      codexHome.appendingPathComponent(
        ".tmp/bundled-marketplaces/openai-bundled/plugins", isDirectory: true),
      codexHome.appendingPathComponent("plugins/cache", isDirectory: true),
      codexHome.appendingPathComponent("plugins/local", isDirectory: true),
    ]
    return roots.flatMap { collectSupportConfigFiles(in: $0, maxDepth: 4) }
  }

  private func claudePluginMCPFiles(in claudeHome: URL) -> [URL] {
    let roots = [
      claudeHome.appendingPathComponent("plugins/cache", isDirectory: true),
      claudeHome.appendingPathComponent("plugins/repos", isDirectory: true),
    ]
    return roots.flatMap { collectSupportConfigFiles(in: $0, maxDepth: 6) }
  }

  private func cursorSupportFiles() -> [URL] {
    let cursorHome = config.homeDirectory.appendingPathComponent(".cursor", isDirectory: true)
    let cursorSupport = config.homeDirectory
      .appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
    var files = [
      cursorHome.appendingPathComponent("mcp.json"),
      cursorSupport.appendingPathComponent("User/mcp.json"),
      cursorSupport.appendingPathComponent("User/settings.json"),
    ]

    for workspace in cursorWorkspaceRoots(cursorSupport: cursorSupport) {
      files.append(contentsOf: workspaceSupportFiles(for: workspace, flavor: .cursor))
    }
    return files
  }

  private func cursorPluginMCPFiles() -> [URL] {
    let cursorHome = config.homeDirectory.appendingPathComponent(".cursor", isDirectory: true)
    let roots = [
      cursorHome.appendingPathComponent("plugins/cache", isDirectory: true),
      cursorHome.appendingPathComponent("plugins/local", isDirectory: true),
    ]
    return roots.flatMap { collectSupportConfigFiles(in: $0, maxDepth: 6) }
  }

  private func cursorWorkspaceRoots(cursorSupport: URL) -> [URL] {
    let storage = cursorSupport.appendingPathComponent("User/workspaceStorage", isDirectory: true)
    guard
      let hashes = try? FileManager.default.contentsOfDirectory(
        at: storage, includingPropertiesForKeys: nil)
    else {
      return []
    }
    return hashes.compactMap { hashDirectory in
      workspaceFolder(from: hashDirectory.appendingPathComponent("workspace.json"))
    }.uniqueSorted()
  }

  private enum WorkspaceFlavor {
    case cursor
  }

  private func workspaceSupportFiles(for workspace: URL, flavor: WorkspaceFlavor) -> [URL] {
    var files: [URL] = []
    let ancestors = workspaceAncestors(from: workspace)
    for root in ancestors {
      files.append(root.appendingPathComponent(".mcp.json"))
      files.append(root.appendingPathComponent("mcp.json"))
      files.append(root.appendingPathComponent("AGENTS.md"))
      files.append(root.appendingPathComponent("CLAUDE.md"))
      files.append(root.appendingPathComponent("GEMINI.md"))
      switch flavor {
      case .cursor:
        files.append(root.appendingPathComponent(".cursor/mcp.json"))
        files.append(root.appendingPathComponent(".cursor/rules"))
      }
    }
    return files
  }

  private func workspaceAncestors(from workspace: URL) -> [URL] {
    let homePath = config.homeDirectory.standardizedFileURL.path
    var current = workspace.standardizedFileURL
    var result: [URL] = []
    while current.path.hasPrefix(homePath + "/") && current.path != homePath {
      result.append(current)
      current.deleteLastPathComponent()
    }
    return result
  }

  private func workspaceFolder(from workspaceJSON: URL) -> URL? {
    guard
      let data = try? Data(contentsOf: workspaceJSON),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let folder = object["folder"] as? String
    else {
      return nil
    }
    if folder.hasPrefix("file://"), let url = URL(string: folder), url.isFileURL {
      return url.standardizedFileURL
    }
    return nil
  }

  private func shallowMatchingFiles(in directory: URL) -> [URL] {
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else {
      return []
    }
    return
      urls
      .filter { isSupportMemoryFile($0) }
      .prefix(config.limits.maxCollectedMemoryFiles)
      .map { $0 }
  }

  private func isSupportMemoryFile(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name.hasSuffix(".jsonl") || name.hasSuffix(".sqlite") || name.hasSuffix(".db")
      || name.contains("memory") || name.contains("session") || name.contains("conversation")
      || name.contains("history")
  }

  private func collectSupportConfigFiles(in directory: URL, maxDepth: Int) -> [URL] {
    var files: [URL] = []
    collectSupportConfigFiles(in: directory, depth: 0, maxDepth: maxDepth, files: &files)
    return files
  }

  private func collectSupportConfigFiles(
    in directory: URL, depth: Int, maxDepth: Int, files: inout [URL]
  ) {
    guard depth <= maxDepth, files.count < config.limits.maxInspectedFiles else {
      return
    }
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey])
    else {
      return
    }

    for url in urls {
      let name = url.lastPathComponent
      if name == ".git" || name == "node_modules" || name == "marketplaces" {
        continue
      }
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      if isDirectory.boolValue {
        collectSupportConfigFiles(in: url, depth: depth + 1, maxDepth: maxDepth, files: &files)
      } else if isSupportConfigFileName(name) {
        files.append(url)
      }
    }
  }

  private func isSupportConfigFileName(_ name: String) -> Bool {
    name == ".mcp.json" || name == "mcp.json" || name == "AGENTS.md" || name == "CLAUDE.md"
      || name == "GEMINI.md" || name == "CODEX.md"
  }
}

extension DiscoveryScanResult {
  mutating func merge(_ other: DiscoveryScanResult) {
    agents.append(contentsOf: other.agents)
    mcpServers.append(contentsOf: other.mcpServers)
    skills.append(contentsOf: other.skills)
    contextFiles.append(contentsOf: other.contextFiles)
    memories.append(contentsOf: other.memories)
    runtimeProcesses.append(contentsOf: other.runtimeProcesses)
    evidence.append(contentsOf: other.evidence)
    permissionStates.append(contentsOf: other.permissionStates)
    events.append(contentsOf: other.events)
    scannedAt = max(scannedAt, other.scannedAt)
  }
}
