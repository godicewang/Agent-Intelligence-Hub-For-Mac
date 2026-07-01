import AppKit
import SwiftUI

private enum AgentScanSection: Hashable {
  case agents
  case mcp
  case skills
  case context
  case memory
  case permissions
}

struct AgentScanView: View {
  @StateObject private var viewModel = AgentScanViewModel()
  @State private var selectedAgentID: UUID?
  @State private var showsLowConfidenceCommonAgents = false
  @State private var commonAgentPage = 0
  @State private var customAgentPage = 0
  @State private var mcpPage = 0
  @State private var skillPage = 0
  @State private var contextPage = 0
  @State private var memoryPage = 0
  @State private var permissionPage = 0

  private let pageSize = 10

  var body: some View {
    ScrollViewReader { scrollProxy in
      FrostPage {
        PageHeader(
          title: "Agent Scan",
          subtitle: "本机 AI Agent、MCP、Skill、上下文文件和运行时候选的真实端上发现。",
          path: "FrostADR / Agent Scan"
        )

        header
        summaryGrid(scrollProxy)
        content
      }
    }
    .task {
      viewModel.startIfNeeded()
    }
  }

  private var header: some View {
    FrostCard("Agent Discovery", subtitle: "Cold start scan + runtime observation") {
      HStack(alignment: .top, spacing: 16) {
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

        VStack(alignment: .leading, spacing: 8) {
          Text(viewModel.isScanning ? "正在构建本机Agent画像" : headerTitle)
            .font(.system(size: 17, weight: .bold))

          Text(statusLine)
            .font(.system(size: 12))
            .foregroundStyle(FrostTheme.mutedText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 7) {
            StatusBadge(label: "Local Endpoint", tone: .info)
            StatusBadge(label: "No-Exec Scan", tone: .healthy)
            StatusBadge(label: "Page Size 10", tone: .neutral)
          }
        }

        Spacer()

        HStack(spacing: 10) {
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
            Label("重新构建画像", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.borderedProminent)
          .tint(FrostTheme.accent)
          .disabled(viewModel.isScanning)
        }
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
    if let lastScannedAt = viewModel.snapshot.lastColdStartScannedAt {
      return
        "最近构建：\(lastScannedAt.formatted(date: .abbreviated, time: .standard))。启动时直接加载本地画像，需要刷新时手动重新构建。"
    }
    return "等待首次构建。默认只扫描无需额外授权的 Agent 配置和已授权工作区，不读取受保护应用数据。"
  }

  private var headerTitle: String {
    viewModel.snapshot.lastColdStartScannedAt == nil ? "等待构建本机Agent画像" : "本机Agent画像已加载"
  }

  private func summaryGrid(_ scrollProxy: ScrollViewProxy) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
      metric(
        "Agents",
        value: viewModel.snapshot.agents.count,
        icon: "scope",
        section: .agents,
        scrollProxy: scrollProxy
      )
      metric(
        "MCP",
        value: viewModel.snapshot.mcpServers.count,
        icon: "puzzlepiece.extension",
        section: .mcp,
        scrollProxy: scrollProxy
      )
      metric(
        "Skills",
        value: viewModel.snapshot.skills.count,
        icon: "terminal",
        section: .skills,
        scrollProxy: scrollProxy
      )
      metric(
        "Context",
        value: viewModel.snapshot.contextFiles.count,
        icon: "doc.text.magnifyingglass",
        section: .context,
        scrollProxy: scrollProxy
      )
      metric(
        "Memory",
        value: viewModel.snapshot.memories.count,
        icon: "externaldrive",
        section: .memory,
        scrollProxy: scrollProxy
      )
      metric(
        "Permissions",
        value: restrictedPermissionCount,
        icon: "lock.shield",
        section: .permissions,
        scrollProxy: scrollProxy
      )
    }
  }

  private func metric(
    _ title: String,
    value: Int,
    icon: String,
    section: AgentScanSection,
    scrollProxy: ScrollViewProxy
  ) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.22)) {
        scrollProxy.scrollTo(section, anchor: .top)
      }
    } label: {
      VStack(alignment: .leading, spacing: 13) {
        HStack(alignment: .center, spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(FrostTheme.accent.opacity(0.12))
            Image(systemName: icon)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(FrostTheme.accent)
          }
          .frame(width: 32, height: 32)

          Spacer(minLength: 0)

          Image(systemName: "arrow.down.right.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FrostTheme.mutedText.opacity(0.72))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(FrostTheme.mutedText)
            .textCase(.uppercase)

          Text("\(value)")
            .font(.system(size: 30, weight: .bold))
            .monospacedDigit()

          Text("点击定位模块")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(FrostTheme.mutedText.opacity(0.84))
        }
      }
      .padding(15)
      .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .fill(FrostTheme.elevatedCardBackground)
      )
      .overlay(alignment: .top) {
        Rectangle()
          .fill(FrostTheme.accent.opacity(0.52))
          .frame(height: 2)
      }
      .overlay(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .stroke(FrostTheme.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous))
      .shadow(color: FrostTheme.shadow.opacity(0.76), radius: 12, x: 0, y: 4)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("跳转到 \(title) 模块")
  }

  private var restrictedPermissionCount: Int {
    viewModel.snapshot.permissionStates.filter { $0.status != .available }.count
  }

  @ViewBuilder
  private var content: some View {
    FrostDetailLayout(detailWidth: 380) {
      VStack(alignment: .leading, spacing: 18) {
        if isDiscoveryEmpty && !viewModel.isScanning {
          emptyOverview
        } else {
          commonAgentsSection
            .id(AgentScanSection.agents)
          customAgentsSection
          mcpSkillGrid
          contextFilesSection
            .id(AgentScanSection.context)
          memorySection
            .id(AgentScanSection.memory)
        }
      }
    } detail: {
      VStack(alignment: .leading, spacing: 18) {
        scanScopeSection
        selectedAgentSection
        runtimeSection
        permissionSection
          .id(AgentScanSection.permissions)
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
    sortedAgents.first { $0.id == selectedAgentID }
      ?? displayedCommonAgents.first
      ?? customAgents.first
      ?? sortedAgents.first
  }

  private var commonAgents: [AgentAsset] {
    sortedAgents.filter(isCommonAgent)
  }

  private var customAgents: [AgentAsset] {
    sortedAgents.filter { !isCommonAgent($0) }
  }

  private var highConfidenceCommonAgents: [AgentAsset] {
    commonAgents.filter { $0.confidence >= 90 }
  }

  private var lowConfidenceCommonAgents: [AgentAsset] {
    commonAgents.filter { $0.confidence < 90 }
  }

  private var displayedCommonAgents: [AgentAsset] {
    showsLowConfidenceCommonAgents ? commonAgents : highConfidenceCommonAgents
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

  private var commonAgentsSection: some View {
    let visibleAgents = pageItems(displayedCommonAgents, page: commonAgentPage)

    return FrostCard("常见 Agent", subtitle: "Codex / Gemini / Cursor / Trae 等已知 Agent") {
      HStack {
        Text("默认仅展示置信度 >= 90 的常见 Agent")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(FrostTheme.mutedText)

        Spacer()

        if !lowConfidenceCommonAgents.isEmpty {
          Button(showsLowConfidenceCommonAgents ? "隐藏低置信度" : "显示低置信度") {
            showsLowConfidenceCommonAgents.toggle()
          }
          .font(.system(size: 11, weight: .semibold))
        }
      }
      .padding(.bottom, 8)

      if commonAgents.isEmpty {
        EmptyStateView(
          title: "暂无常见 Agent", message: "当前本机画像中没有发现常见 Agent。", systemImage: "tray",
          compact: true)
      } else if displayedCommonAgents.isEmpty {
        EmptyStateView(
          title: "暂无高置信度常见 Agent",
          message: "已发现低置信度常见 Agent，可点击右上角显示。",
          systemImage: "line.3.horizontal.decrease.circle", compact: true)
      } else {
        tableSurface {
          tableHeader(["名称", "类型", "状态", "MCP", "Skill", "置信度", "风险"])
          ForEach(visibleAgents) { agent in
            agentRow(agent)
          }
          paginationFooter(
            total: displayedCommonAgents.count, page: $commonAgentPage, label: "Agent")
        }
      }
    }
  }

  private var customAgentsSection: some View {
    let visibleAgents = pageItems(customAgents, page: customAgentPage)

    return FrostCard("本机自研 Agent", subtitle: "未知 / 自定义终端 Agent 候选") {
      if customAgents.isEmpty {
        EmptyStateView(
          title: "暂无自研 Agent 候选",
          message: "没有发现通过行为指纹或上下文文件识别出的本机自研 Agent。",
          systemImage: "terminal", compact: true)
      } else {
        tableSurface {
          tableHeader(["名称", "类型", "状态", "MCP", "Skill", "置信度", "风险"])
          ForEach(visibleAgents) { agent in
            agentRow(agent)
          }
          paginationFooter(total: customAgents.count, page: $customAgentPage, label: "Agent")
        }
      }
    }
  }

  private func agentRow(_ agent: AgentAsset) -> some View {
    Button {
      selectedAgentID = agent.id
      viewModel.openRootDirectory(for: agent)
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
    .pointingHandCursor()
    .help("打开 Agent 根目录")
  }

  private var mcpSkillGrid: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
      alignment: .leading,
      spacing: 16
    ) {
      mcpSection
        .id(AgentScanSection.mcp)
      skillSection
        .id(AgentScanSection.skills)
    }
  }

  private var mcpSection: some View {
    let visibleServers = pageItems(viewModel.snapshot.mcpServers, page: mcpPage)

    return FrostCard("MCP Servers", subtitle: "no-exec config discovery") {
      if viewModel.snapshot.mcpServers.isEmpty {
        EmptyStateView(
          title: "暂无 MCP Server", message: "未发现真实 MCP 配置。", systemImage: "puzzlepiece.extension",
          compact: true)
      } else {
        tableSurface {
          tableHeader(["名称", "Transport", "Command", "Risk", "Inspection"])
          ForEach(visibleServers) { server in
            clickableRow(
              [
                server.name,
                server.transport.rawValue,
                server.command ?? "-",
                "\(server.riskPreScore)",
                server.inspectionStatus.rawValue,
              ], help: "打开 MCP 配置位置"
            ) {
              viewModel.openPath(server.configPath)
            }
          }
          paginationFooter(total: viewModel.snapshot.mcpServers.count, page: $mcpPage, label: "MCP")
        }
      }
    }
  }

  private var skillSection: some View {
    let visibleSkills = pageItems(viewModel.snapshot.skills, page: skillPage)

    return FrostCard("Skills", subtitle: "Layer 1 pre-scan") {
      if viewModel.snapshot.skills.isEmpty {
        EmptyStateView(
          title: "暂无 Skill", message: "未发现真实 Skill 目录。", systemImage: "terminal", compact: true)
      } else {
        tableSurface {
          tableHeader(["名称", "脚本", "外部 URL", "安装指令", "风险"])
          ForEach(visibleSkills) { skill in
            clickableRow(
              [
                skill.name,
                skill.hasScripts ? "yes" : "no",
                skill.hasExternalURLs ? "yes" : "no",
                skill.hasInstallInstructions ? "yes" : "no",
                skill.riskLevel.rawValue,
              ], help: "打开 Skill 目录"
            ) {
              viewModel.openDirectoryPath(skill.path)
            }
          }
          paginationFooter(total: viewModel.snapshot.skills.count, page: $skillPage, label: "Skill")
        }
      }
    }
  }

  private var contextFilesSection: some View {
    let visibleFiles = pageItems(viewModel.snapshot.contextFiles, page: contextPage)

    return FrostCard("Context Files", subtitle: "AGENTS.md / CLAUDE.md / rules / settings") {
      if viewModel.snapshot.contextFiles.isEmpty {
        EmptyStateView(
          title: "暂无上下文文件", message: "未发现 AGENTS.md、CLAUDE.md、rules 或 settings 文件。",
          systemImage: "doc.text", compact: true)
      } else {
        tableSurface {
          tableHeader(["类型", "路径", "摘要"])
          ForEach(visibleFiles) { item in
            clickableRow(
              [
                "Context", item.path, item.keywordHits.prefix(4).joined(separator: ", "),
              ], help: "打开上下文文件位置"
            ) {
              viewModel.openPath(item.path)
            }
          }
          paginationFooter(
            total: viewModel.snapshot.contextFiles.count, page: $contextPage, label: "Context"
          )
        }
      }
    }
  }

  private var memorySection: some View {
    let visibleMemories = pageItems(viewModel.snapshot.memories, page: memoryPage)

    return FrostCard("Memory", subtitle: "Session / cache / long-term memory metadata") {
      if viewModel.snapshot.memories.isEmpty {
        EmptyStateView(
          title: "暂无 Memory 文件", message: "未发现 session、cache 或 memory 文件。",
          systemImage: "externaldrive", compact: true)
      } else {
        tableSurface {
          tableHeader(["类型", "路径", "格式"])
          ForEach(visibleMemories) { item in
            clickableRow(["Memory", item.path, item.format.rawValue], help: "打开 Memory 文件位置") {
              viewModel.openPath(item.path)
            }
          }
          paginationFooter(
            total: viewModel.snapshot.memories.count, page: $memoryPage, label: "Memory")
        }
      }
    }
  }

  private var permissionSection: some View {
    let visiblePermissionStates = pageItems(
      viewModel.snapshot.permissionStates, page: permissionPage)

    return FrostCard("Permission / Runtime Status", subtitle: "真实权限和运行时观察状态") {
      if viewModel.snapshot.permissionStates.isEmpty {
        EmptyStateView(
          title: "暂无额外权限请求",
          message:
            "默认轻量发现不会主动请求 Full Disk Access、App Data、Endpoint Security 或 Network Extension 权限。",
          systemImage: "lock.shield", compact: true)
      } else {
        tableSurface {
          tableHeader(["能力", "状态", "说明"])
          ForEach(visiblePermissionStates) { state in
            row([state.capability.rawValue, state.status.rawValue, state.message])
          }
          paginationFooter(
            total: viewModel.snapshot.permissionStates.count, page: $permissionPage,
            label: "Permission")
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

  private func pageItems<T>(_ items: [T], page: Int) -> [T] {
    guard !items.isEmpty else { return [] }
    let currentPage = safePage(page, total: items.count)
    let startIndex = currentPage * pageSize
    return Array(items.dropFirst(startIndex).prefix(pageSize))
  }

  private func pageCount(total: Int) -> Int {
    max(1, Int(ceil(Double(total) / Double(pageSize))))
  }

  private func safePage(_ page: Int, total: Int) -> Int {
    min(max(page, 0), pageCount(total: total) - 1)
  }

  @ViewBuilder
  private func paginationFooter(total: Int, page: Binding<Int>, label: String) -> some View {
    if total > 0 {
      let currentPage = safePage(page.wrappedValue, total: total)
      let pages = pageCount(total: total)

      HStack(spacing: 10) {
        Text("每页 \(pageSize) 条 · 第 \(currentPage + 1) / \(pages) 页 · 共 \(total) \(label)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(FrostTheme.mutedText)

        Spacer()

        Button {
          page.wrappedValue = max(0, currentPage - 1)
        } label: {
          Image(systemName: "chevron.left")
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(currentPage == 0)
        .help("上一页")

        Button {
          page.wrappedValue = min(pages - 1, currentPage + 1)
        } label: {
          Image(systemName: "chevron.right")
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(currentPage >= pages - 1)
        .help("下一页")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(FrostTheme.tableHeaderBackground.opacity(0.68))
    }
  }

  private func tableSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      content()
    }
    .background(
      RoundedRectangle(cornerRadius: FrostTheme.compactRadius, style: .continuous)
        .fill(FrostTheme.moduleWellBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: FrostTheme.compactRadius, style: .continuous)
        .stroke(FrostTheme.subtleBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: FrostTheme.compactRadius, style: .continuous))
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
    rowContent(columns)
  }

  private func clickableRow(
    _ columns: [String], help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      rowContent(columns)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help(help)
  }

  private func rowContent(_ columns: [String]) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, value in
          rowText(value)
        }
      }
      .background(FrostTheme.tableRowBackground.opacity(0.42))
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
    Button {
      viewModel.openPath(path)
    } label: {
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
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("打开路径位置")
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

  private func isCommonAgent(_ agent: AgentAsset) -> Bool {
    let commonNames: Set<String> = [
      "claude-code",
      "claude-desktop",
      "codex-cli",
      "cursor",
      "gemini-cli",
      "cline-roocode",
      "continue",
      "openclaw",
      "aider",
      "trae",
      "unknown-vscode-agent-extension",
    ]
    return commonNames.contains(agent.normalizedName)
      || [.known, .cli, .desktop, .ideExtension].contains(agent.agentType)
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

private struct PointingHandCursorModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .onHover { hovering in
        if hovering {
          NSCursor.pointingHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }
}

extension View {
  fileprivate func pointingHandCursor() -> some View {
    modifier(PointingHandCursorModifier())
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
