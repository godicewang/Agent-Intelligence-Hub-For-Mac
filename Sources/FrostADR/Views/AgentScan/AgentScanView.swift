import SwiftUI

struct AgentScanView: View {
  @StateObject private var viewModel = AgentScanViewModel()
  @State private var selectedAgentID: UUID?

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Agent Scan",
        subtitle: "本机 AI Agent、MCP、Skill、上下文文件和运行时候选的真实端上发现。",
        path: "FrostADR / Agent Scan"
      )

      header
      summaryGrid
      content
    }
    .task {
      viewModel.startIfNeeded()
    }
  }

  private var header: some View {
    FrostCard("Agent Discovery", subtitle: "Cold start scan + runtime observation") {
      HStack(alignment: .center, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FrostTheme.accent.opacity(0.13))
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FrostTheme.accent.opacity(0.28), lineWidth: 1)
            )

          Image(systemName: viewModel.isScanning ? "arrow.triangle.2.circlepath" : "scope")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(FrostTheme.accent)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 5) {
          Text(viewModel.isScanning ? "正在轻量扫描本机 Agent 资产" : "Agent 发现引擎已连接本机数据")
            .font(.system(size: 16, weight: .bold))

          Text(statusLine)
            .font(.system(size: 12))
            .foregroundStyle(FrostTheme.mutedText)
        }

        Spacer()

        if viewModel.isScanning {
          ProgressView()
            .controlSize(.small)
        }

        Button {
          viewModel.exportJSONL()
        } label: {
          Label("导出 JSONL", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.isScanning)

        Button {
          viewModel.rescan()
        } label: {
          Label("重新扫描", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isScanning)
      }

      if let exportMessage = viewModel.exportMessage {
        Divider()
          .padding(.vertical, 10)

        Label(exportMessage, systemImage: "square.and.arrow.down")
          .font(.system(size: 12))
          .foregroundStyle(FrostTheme.mutedText)
      }

      if let error = viewModel.errorMessage {
        Divider()
          .padding(.vertical, 10)

        Label(error, systemImage: "exclamationmark.triangle")
          .font(.system(size: 12))
          .foregroundStyle(.orange)
      }
    }
  }

  private var statusLine: String {
    if let lastScannedAt = viewModel.snapshot.lastScannedAt {
      return
        "最近扫描：\(lastScannedAt.formatted(date: .abbreviated, time: .standard))。所有结果来自本机扫描与本地持久化。"
    }
    return "等待首次扫描完成。默认只扫描无需额外授权的 Agent 配置和已授权工作区，不读取受保护应用数据。"
  }

  private var summaryGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
      metric(
        "Agents", value: viewModel.snapshot.agents.count, icon: "laptopcomputer.and.magnifyingglass"
      )
      metric("MCP", value: viewModel.snapshot.mcpServers.count, icon: "puzzlepiece.extension")
      metric("Skills", value: viewModel.snapshot.skills.count, icon: "terminal")
      metric(
        "Context", value: viewModel.snapshot.contextFiles.count, icon: "doc.text.magnifyingglass")
      metric("Memory", value: viewModel.snapshot.memories.count, icon: "externaldrive")
      metric("Permissions", value: restrictedPermissionCount, icon: "lock.shield")
    }
  }

  private func metric(_ title: String, value: Int, icon: String) -> some View {
    FrostCard(title) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(FrostTheme.accent)
          .frame(width: 26)

        Text("\(value)")
          .font(.system(size: 26, weight: .bold))

        Spacer()
      }
      .frame(minHeight: 48)
    }
  }

  private var restrictedPermissionCount: Int {
    viewModel.snapshot.permissionStates.filter { $0.status != .available }.count
  }

  @ViewBuilder
  private var content: some View {
    FrostDetailLayout(detailWidth: 360) {
      VStack(alignment: .leading, spacing: 16) {
        if isDiscoveryEmpty && !viewModel.isScanning {
          emptyOverview
        } else {
          agentsSection
          mcpSkillGrid
          contextSection
        }
      }
    } detail: {
      VStack(alignment: .leading, spacing: 16) {
        scanScopeSection
        selectedAgentSection
        runtimeSection
        permissionSection
      }
    }
  }

  private var isDiscoveryEmpty: Bool {
    viewModel.snapshot.agents.isEmpty && viewModel.snapshot.mcpServers.isEmpty
      && viewModel.snapshot.skills.isEmpty && viewModel.snapshot.contextFiles.isEmpty
      && viewModel.snapshot.memories.isEmpty
  }

  private var sortedAgents: [AgentAsset] {
    viewModel.snapshot.agents.sorted {
      if $0.confidence == $1.confidence {
        return $0.displayName < $1.displayName
      }
      return $0.confidence > $1.confidence
    }
  }

  private var selectedAgent: AgentAsset? {
    sortedAgents.first { $0.id == selectedAgentID } ?? sortedAgents.first
  }

  private var emptyOverview: some View {
    FrostCard("真实空状态", subtitle: "No local agent assets discovered") {
      EmptyStateView(
        title: "未发现 Agent 资产",
        message:
          "当前轻量扫描范围内没有发现 Agent、MCP、Skill 或上下文资产。创建 AGENTS.md、.mcp.json、SKILL.md 或安装本地 Agent 后可重新扫描。",
        systemImage: "checkmark.shield"
      )
      .frame(minHeight: 260)
    }
  }

  private var agentsSection: some View {
    FrostCard("Agent Assets", subtitle: "真实发现结果") {
      if viewModel.snapshot.agents.isEmpty {
        EmptyStateView(
          title: "暂无 Agent", message: "扫描完成后未发现 Agent 资产。", systemImage: "tray", compact: true)
      } else {
        VStack(spacing: 0) {
          tableHeader(["名称", "类型", "状态", "MCP", "Skill", "置信度", "风险"])
          ForEach(sortedAgents) { agent in
            agentRow(agent)
          }
        }
      }
    }
  }

  private func agentRow(_ agent: AgentAsset) -> some View {
    Button {
      selectedAgentID = agent.id
    } label: {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          rowText(agent.displayName)
          rowText(agent.agentType.rawValue)
          rowText(agent.runtimeStatus.rawValue)
          rowText("\(mcpCount(for: agent))")
          rowText("\(skillCount(for: agent))")
          rowText("\(agent.confidence)")
          HStack {
            StatusBadge(label: agent.riskLevel.rawValue, tone: tone(for: agent.riskLevel))
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
        }
        Divider()
      }
      .background(
        (selectedAgent?.id == agent.id ? FrostTheme.accent.opacity(0.09) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var mcpSkillGrid: some View {
    HStack(alignment: .top, spacing: 16) {
      mcpSection
      skillSection
    }
  }

  private var mcpSection: some View {
    FrostCard("MCP Servers", subtitle: "no-exec config discovery") {
      if viewModel.snapshot.mcpServers.isEmpty {
        EmptyStateView(
          title: "暂无 MCP Server", message: "未发现真实 MCP 配置。", systemImage: "puzzlepiece.extension",
          compact: true)
      } else {
        VStack(spacing: 0) {
          tableHeader(["名称", "Transport", "Command", "Risk", "Inspection"])
          ForEach(viewModel.snapshot.mcpServers) { server in
            row([
              server.name,
              server.transport.rawValue,
              server.command ?? "-",
              "\(server.riskPreScore)",
              server.inspectionStatus.rawValue,
            ])
          }
        }
      }
    }
  }

  private var skillSection: some View {
    FrostCard("Skills", subtitle: "Layer 1 pre-scan") {
      if viewModel.snapshot.skills.isEmpty {
        EmptyStateView(
          title: "暂无 Skill", message: "未发现真实 Skill 目录。", systemImage: "terminal", compact: true)
      } else {
        VStack(spacing: 0) {
          tableHeader(["名称", "脚本", "外部 URL", "安装指令", "风险"])
          ForEach(viewModel.snapshot.skills) { skill in
            row([
              skill.name,
              skill.hasScripts ? "yes" : "no",
              skill.hasExternalURLs ? "yes" : "no",
              skill.hasInstallInstructions ? "yes" : "no",
              skill.riskLevel.rawValue,
            ])
          }
        }
      }
    }
  }

  private var contextSection: some View {
    FrostCard("Context / Memory", subtitle: "上下文与记忆文件元数据") {
      if viewModel.snapshot.contextFiles.isEmpty && viewModel.snapshot.memories.isEmpty {
        EmptyStateView(
          title: "暂无上下文或记忆文件", message: "未发现 AGENTS.md、CLAUDE.md、session.jsonl 等文件。",
          systemImage: "doc.text", compact: true)
      } else {
        VStack(spacing: 0) {
          tableHeader(["类型", "路径", "摘要"])
          ForEach(viewModel.snapshot.contextFiles) { item in
            row(["Context", item.path, item.keywordHits.prefix(4).joined(separator: ", ")])
          }
          ForEach(viewModel.snapshot.memories) { item in
            row(["Memory", item.path, item.format.rawValue])
          }
        }
      }
    }
  }

  private var permissionSection: some View {
    FrostCard("Permission / Runtime Status", subtitle: "真实权限和运行时观察状态") {
      VStack(spacing: 0) {
        tableHeader(["能力", "状态", "说明"])
        ForEach(viewModel.snapshot.permissionStates) { state in
          row([state.capability.rawValue, state.status.rawValue, state.message])
        }
        if viewModel.snapshot.permissionStates.isEmpty {
          EmptyStateView(
            title: "暂无额外权限请求",
            message:
              "默认轻量发现不会主动请求 Full Disk Access、App Data、Endpoint Security 或 Network Extension 权限。",
            systemImage: "lock.shield", compact: true)
        }
      }
    }
  }

  private var scanScopeSection: some View {
    FrostCard("Scan Scope", subtitle: "启动权限与扫描边界") {
      VStack(alignment: .leading, spacing: 12) {
        WrapBadges {
          StatusBadge(
            label: viewModel.configuration.enableColdStartScan ? "Cold Start On" : "Cold Start Off",
            tone: viewModel.configuration.enableColdStartScan ? .healthy : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableRuntimeObserver ? "Runtime On" : "Runtime Off",
            tone: viewModel.configuration.enableRuntimeObserver ? .healthy : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableFSEventsWatcher ? "FSEvents On" : "FSEvents Off",
            tone: viewModel.configuration.enableFSEventsWatcher ? .info : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableUserApplicationSupportScan
              ? "App Data On" : "App Data Off",
            tone: viewModel.configuration.enableUserApplicationSupportScan ? .warning : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableEndpointSecurityMonitor ? "ES On" : "ES Off",
            tone: viewModel.configuration.enableEndpointSecurityMonitor ? .warning : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableNetworkMonitor ? "Network On" : "Network Off",
            tone: viewModel.configuration.enableNetworkMonitor ? .warning : .neutral)
        }

        Divider()

        if viewModel.configuration.scanRoots.isEmpty {
          EmptyStateView(
            title: "轻量启动模式",
            message: "当前没有自动工作区扫描根；仅检查无需额外授权的已知 Agent 路径和运行进程指纹。",
            systemImage: "scope", compact: true)
        } else {
          VStack(alignment: .leading, spacing: 7) {
            Text("Active Roots")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(FrostTheme.mutedText)
            ForEach(viewModel.configuration.scanRoots.map(\.path), id: \.self) { path in
              compactPath(path)
            }
          }
        }
      }
    }
  }

  private var selectedAgentSection: some View {
    FrostCard("Agent Detail", subtitle: "选中资产详情") {
      if let agent = selectedAgent {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text(agent.displayName)
              .font(.system(size: 15, weight: .bold))
              .lineLimit(2)
            HStack(spacing: 6) {
              StatusBadge(label: agent.agentType.rawValue, tone: .info)
              StatusBadge(label: agent.managedStatus.rawValue, tone: .neutral)
              StatusBadge(label: agent.riskLevel.rawValue, tone: tone(for: agent.riskLevel))
            }
          }

          Divider()

          detailRow("Confidence", "\(agent.confidence)")
          detailRow("Runtime", agent.runtimeStatus.rawValue)
          detailRow("Scopes", agent.scopes.map(\.rawValue).joined(separator: ", "))
          detailRow("Methods", agent.discoveryMethods.map(\.rawValue).joined(separator: ", "))

          pathGroup("Config", agent.configPaths)
          pathGroup("Workspace", agent.workspacePaths)
          pathGroup("MCP", agent.mcpConfigPaths)
          pathGroup("Skills", agent.skillPaths)
          pathGroup("Memory", agent.memoryPaths)

          if let summary = agent.metadataSummary, !summary.isEmpty {
            Text(summary)
              .font(.system(size: 11))
              .foregroundStyle(FrostTheme.mutedText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        EmptyStateView(
          title: "未选择 Agent",
          message: "发现真实 Agent 后，点击左侧资产行查看路径、方法和风险摘要。",
          systemImage: "sidebar.right", compact: true)
      }
    }
  }

  private var runtimeSection: some View {
    FrostCard("Runtime Evidence", subtitle: "进程、证据与事件") {
      VStack(alignment: .leading, spacing: 10) {
        detailRow("Runtime Processes", "\(viewModel.snapshot.runtimeProcesses.count)")
        detailRow("Evidence", "\(viewModel.snapshot.evidence.count)")
        detailRow("Events", "\(viewModel.snapshot.events.count)")
        if let latest = viewModel.snapshot.events.sorted(by: { $0.createdAt > $1.createdAt }).first
        {
          Divider()
          Text(latest.message)
            .font(.system(size: 11))
            .foregroundStyle(FrostTheme.mutedText)
            .lineLimit(3)
        }
      }
    }
  }

  private func tableHeader(_ columns: [String]) -> some View {
    HStack(spacing: 0) {
      ForEach(columns, id: \.self) { column in
        Text(column)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(FrostTheme.mutedText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
      }
    }
    .background(FrostTheme.tableHeaderBackground)
  }

  private func row(_ columns: [String]) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, value in
          rowText(value)
        }
      }
      Divider()
    }
  }

  private func rowText(_ value: String) -> some View {
    Text(value.isEmpty ? "-" : value)
      .font(.system(size: 12))
      .lineLimit(2)
      .truncationMode(.middle)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(FrostTheme.mutedText)
        .frame(width: 112, alignment: .leading)

      Text(value.isEmpty ? "-" : value)
        .font(.system(size: 11))
        .lineLimit(3)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func pathGroup(_ title: String, _ paths: [String]) -> some View {
    Group {
      if !paths.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(FrostTheme.mutedText)
          ForEach(paths.prefix(4), id: \.self) { path in
            compactPath(path)
          }
        }
      }
    }
  }

  private func compactPath(_ path: String) -> some View {
    Text(path)
      .font(.system(size: 10.5, design: .monospaced))
      .lineLimit(1)
      .truncationMode(.middle)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(FrostTheme.tableRowBackground)
      )
  }

  private func mcpCount(for agent: AgentAsset) -> Int {
    let pathSet = Set(agent.mcpConfigPaths + agent.configPaths)
    return viewModel.snapshot.mcpServers.filter {
      $0.sourceAgentId == agent.id || pathSet.contains($0.configPath)
    }.count
  }

  private func skillCount(for agent: AgentAsset) -> Int {
    viewModel.snapshot.skills.filter {
      $0.sourceAgentId == agent.id || agent.skillPaths.contains($0.path)
    }.count
  }

  private func tone(for risk: RiskLevel) -> StatusBadgeTone {
    switch risk {
    case .informational:
      .info
    case .low:
      .healthy
    case .medium:
      .warning
    case .high, .critical:
      .critical
    }
  }
}

private struct WrapBadges<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AgentScanView_Previews: PreviewProvider {
  static var previews: some View {
    AgentScanView()
      .frame(width: 1100, height: 720)
  }
}
