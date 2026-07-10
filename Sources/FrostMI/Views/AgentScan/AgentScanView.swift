import AppKit
import SwiftUI

private enum AgentScanSection: Hashable {
  case agents
  case mcp
  case skills
  case context
  case memory
  case permissions
  case runtimeProcesses
  case runtimeEvents
  case runtimeSensors
  case analysisAgents
}

private enum AgentSensingTab: String, CaseIterable, Identifiable {
  case agentAnalysis
  case runtimeMonitor
  case staticScan

  var id: String { rawValue }

  var title: String {
    switch self {
    case .agentAnalysis:
      "Agent Analysis"
    case .runtimeMonitor:
      "Runtime Monitor"
    case .staticScan:
      "Static Scan"
    }
  }

  var subtitle: String {
    switch self {
    case .agentAnalysis:
      "首页先看每个 Agent 的总画像、运行状态和关联资产。"
    case .runtimeMonitor:
      "运行时进程、FSEvents、权限和传感器状态。"
    case .staticScan:
      "静态发现 Agent、MCP、Skill、Context 和 Memory。"
    }
  }
}

struct AgentScanView: View {
  @StateObject private var viewModel = AgentScanViewModel()
  @State private var selectedTab: AgentSensingTab = .agentAnalysis
  @State private var selectedAgentID: UUID?
  @State private var showsLowConfidenceCommonAgents = false
  @State private var commonAgentPage = 0
  @State private var customAgentPage = 0
  @State private var mcpPage = 0
  @State private var skillPage = 0
  @State private var contextPage = 0
  @State private var memoryPage = 0
  @State private var permissionPage = 0
  @State private var runtimeProcessPage = 0
  @State private var runtimeEventPage = 0
  @State private var runtimeSessionPage = 0
  @State private var runningAgentPage = 0
  @State private var inactiveAgentPage = 0
  @State private var selectedRuntimeSessionID: String?

  private let pageSize = 10

  var body: some View {
    ScrollViewReader { scrollProxy in
      FrostPage {
        PageHeader(
          title: "Agent Sensing",
          subtitle: "本机 AI Agent、MCP、Skill、上下文、Memory 和运行时候选的端上感知。",
          path: "FrostMI / Agent Sensing"
        )

        tabSelector

        switch selectedTab {
        case .agentAnalysis:
          agentCommandCenter
          analysisSummaryGrid(scrollProxy)
          analysisContent
        case .runtimeMonitor:
          runtimeMonitorDashboard
          runtimeContent
        case .staticScan:
          header
          staticSummaryGrid(scrollProxy)
          staticContent
        }
      }
    }
    .task {
      viewModel.startIfNeeded()
    }
  }

  private var tabSelector: some View {
    FrostCard("Sensing Mode", subtitle: "从 Agent 总画像开始，再下钻到运行时或静态扫描明细。") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Sensing Mode", selection: $selectedTab) {
          ForEach(AgentSensingTab.allCases) { tab in
            Text(tab.title).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 520)

        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "info.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FrostTheme.accent)
          Text(selectedTab.subtitle)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(FrostTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var runtimeMonitoringBinding: Binding<Bool> {
    Binding(
      get: { viewModel.isRuntimeMonitoring },
      set: { viewModel.setRuntimeMonitoringEnabled($0) }
    )
  }

  private var agentCommandCenter: some View {
    FrostCard("Agent Command Center", subtitle: "日常先看 Agent 总画像；需要刷新资产或观测运行态时，用这里的两个主开关。") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
        sensingActionCard(
          title: "静态画像重建",
          caption: "Static Profile Rebuild",
          description: "重新扫描本机 Agent、MCP、Skill、Context 和 Memory，完成后更新下方 Agent 画像。",
          systemImage: "arrow.triangle.2.circlepath",
          status: viewModel.isScanning || viewModel.isStaticProfileRebuilding ? "构建中" : "手动刷新",
          tone: viewModel.isScanning || viewModel.isStaticProfileRebuilding ? .warning : .info,
          actionTitle: viewModel.isScanning || viewModel.isStaticProfileRebuilding ? "刷新中" : "刷新",
          isBusy: viewModel.isScanning || viewModel.isStaticProfileRebuilding,
          action: viewModel.rebuildStaticProfile
        )

        sensingToggleCard(
          title: "运行时监控",
          caption: "Runtime Observation",
          description: "持续刷新运行中进程和已授权工作区 FSEvents，不主动请求额外系统级权限。",
          systemImage: "dot.radiowaves.left.and.right",
          status: viewModel.isRuntimeMonitoring ? "实时开启" : "已暂停",
          tone: viewModel.isRuntimeMonitoring ? .healthy : .neutral,
          isOn: runtimeMonitoringBinding,
          isDisabled: !viewModel.configuration.enableRuntimeObserver
        )
      }
    }
  }

  private func sensingActionCard(
    title: String,
    caption: String,
    description: String,
    systemImage: String,
    status: String,
    tone: StatusBadgeTone,
    actionTitle: String,
    isBusy: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .top, spacing: 14) {
      commandIcon(systemImage, isActive: isBusy)

      commandText(
        title: title, caption: caption, description: description, status: status, tone: tone)

      Button(action: action) {
        if isBusy {
          ProgressView()
            .controlSize(.small)
            .frame(width: 30, height: 30)
        } else {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 15, weight: .bold))
            .frame(width: 30, height: 30)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(FrostTheme.accent)
      .disabled(isBusy)
      .help(actionTitle)
    }
    .commandCard(isActive: isBusy)
  }

  private func sensingToggleCard(
    title: String,
    caption: String,
    description: String,
    systemImage: String,
    status: String,
    tone: StatusBadgeTone,
    isOn: Binding<Bool>,
    isDisabled: Bool = false
  ) -> some View {
    HStack(alignment: .top, spacing: 14) {
      commandIcon(systemImage, isActive: isOn.wrappedValue)

      commandText(
        title: title, caption: caption, description: description, status: status, tone: tone)

      Toggle("", isOn: isOn)
        .toggleStyle(.switch)
        .labelsHidden()
        .tint(FrostTheme.accent)
        .disabled(isDisabled)
        .help(title)
    }
    .commandCard(isActive: isOn.wrappedValue)
  }

  private func commandIcon(_ systemImage: String, isActive: Bool) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(FrostTheme.accent.opacity(isActive ? 0.18 : 0.13))
      Image(systemName: systemImage)
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(FrostTheme.accent)
    }
    .frame(width: 46, height: 46)
  }

  private func commandText(
    title: String,
    caption: String,
    description: String,
    status: String,
    tone: StatusBadgeTone
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 15, weight: .bold))
          Text(caption)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(FrostTheme.mutedText)
        }

        Spacer(minLength: 8)

        StatusBadge(label: status, tone: tone)
      }

      Text(description)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(FrostTheme.mutedText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var header: some View {
    FrostCard("Agent Discovery", subtitle: "FrostADR Runtime foundation") {
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
            StatusBadge(label: "Evidence Bound", tone: .info)
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

  private func staticSummaryGrid(_ scrollProxy: ScrollViewProxy) -> some View {
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
  private var staticContent: some View {
    FrostDetailLayout(detailWidth: 380) {
      VStack(alignment: .leading, spacing: 18) {
        if isDiscoveryEmpty && !viewModel.isScanning {
          emptySensingState
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

  @ViewBuilder
  private var runtimeContent: some View {
    FrostDetailLayout(detailWidth: 380) {
      VStack(alignment: .leading, spacing: 18) {
        runtimeProcessesSection
          .id(AgentScanSection.runtimeProcesses)
        runtimeEventsSection
          .id(AgentScanSection.runtimeEvents)
        runtimeSessionGraphsSection
      }
    } detail: {
      VStack(alignment: .leading, spacing: 18) {
        runtimeSensorStatusSection
          .id(AgentScanSection.runtimeSensors)
        runtimeAttributionSection
        runtimeSessionDetailSection
      }
    }
  }

  private var runtimeStatusLine: String {
    if let refreshedAt = viewModel.lastRuntimeRefreshedAt {
      return
        "最近刷新：\(refreshedAt.formatted(date: .abbreviated, time: .standard))。当前使用无额外授权的进程快照和已授权工作区 FSEvents，不伪造 Endpoint Security / Network Extension 遥测。"
    }
    return "启动后会自动刷新运行时快照；也可以手动刷新。需要系统级遥测时只显示真实 entitlement 状态。"
  }

  private var runtimeMonitorDashboard: some View {
    FrostCard("Runtime Monitor", subtitle: "实时运行态仪表盘") {
      HStack(alignment: .center, spacing: 18) {
        RuntimePulseMeter(
          activeProcessCount: runtimeProcesses.count,
          activeAgentCount: agentProfiles.filter(\.isRuntimeActive).count,
          isRefreshing: viewModel.isRuntimeRefreshing
        )
        .frame(width: 190, height: 150)

        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
              Text(viewModel.isRuntimeMonitoring ? "运行时监控中" : "运行时监控未启用")
                .font(.system(size: 18, weight: .bold))
              Text(runtimeStatusLine)
                .font(.system(size: 12))
                .foregroundStyle(FrostTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
              viewModel.refreshRuntimeNow()
            } label: {
              Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(FrostTheme.accent)
            .disabled(viewModel.isRuntimeRefreshing)
          }

          HStack(spacing: 10) {
            runtimeSignalTile(
              title: "运行 Agent",
              value: "\(agentProfiles.filter(\.isRuntimeActive).count)",
              detail: "当前有进程证据",
              tone: .healthy
            )
            runtimeSignalTile(
              title: "运行进程",
              value: "\(runtimeProcesses.count)",
              detail: "来自 ps + App 视图",
              tone: .info
            )
            runtimeSignalTile(
              title: "最近事件",
              value: "\(runtimeEvents.count)",
              detail: "本地降噪保留",
              tone: .neutral
            )
          }
        }
      }
    }
  }

  private func runtimeSignalTile(
    title: String,
    value: String,
    detail: String,
    tone: StatusBadgeTone
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(FrostTheme.mutedText)
        Spacer()
        StatusBadge(label: detail, tone: tone)
      }
      Text(value)
        .font(.system(size: 28, weight: .bold))
        .monospacedDigit()
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: FrostTheme.compactRadius, style: .continuous)
        .fill(FrostTheme.moduleWellBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: FrostTheme.compactRadius, style: .continuous)
        .stroke(FrostTheme.subtleBorder, lineWidth: 1)
    )
  }

  private var runtimeProcessesSection: some View {
    let visibleProcesses = pageItems(runtimeProcesses, page: runtimeProcessPage)

    return FrostCard("Runtime Processes", subtitle: "known process + behavior fingerprints") {
      if runtimeProcesses.isEmpty {
        EmptyStateView(
          title: "暂无运行时 Agent 进程",
          message: "当前进程快照中没有匹配到已知 Agent 或高置信行为候选。",
          systemImage: "play.slash", compact: true)
      } else {
        tableSurface {
          tableHeader(["PID", "Owner", "Process", "Score", "Provider", "Workspace"])
          ForEach(visibleProcesses) { process in
            clickableRow(
              [
                "\(process.pid)",
                runtimeOwnerName(for: process),
                process.processName,
                "\(process.agentCandidateScore)",
                process.connectedLLMProviders.joined(separator: ", "),
                process.workspaceTouched ?? "-",
              ],
              help: "打开进程可执行文件位置"
            ) {
              if let path = process.executablePath ?? process.bundlePath {
                viewModel.openPath(path)
              }
            }
          }
          paginationFooter(
            total: runtimeProcesses.count, page: $runtimeProcessPage, label: "Runtime")
        }
      }
    }
  }

  private var runtimeEventsSection: some View {
    let visibleEvents = pageItems(runtimeEvents, page: runtimeEventPage)

    return FrostCard("Runtime Events", subtitle: "local observation trail") {
      if runtimeEvents.isEmpty {
        EmptyStateView(
          title: "暂无运行时事件",
          message: "尚未记录进程快照、文件变化、网络快照或 MCP Runtime 事件。",
          systemImage: "list.bullet.rectangle", compact: true)
      } else {
        tableSurface {
          tableHeader(["时间", "类型", "说明"])
          ForEach(visibleEvents) { event in
            runtimeEventRow(event)
          }
          paginationFooter(total: runtimeEvents.count, page: $runtimeEventPage, label: "Event")
        }
      }
    }
  }

  private func runtimeEventRow(_ event: RuntimeEventRecord) -> some View {
    let columns = [
      event.timestamp.formatted(date: .omitted, time: .standard),
      runtimeEventTitle(event.kind),
      event.message ?? event.path ?? event.url ?? "已记录本机运行时观察。",
    ]
    if let path = event.path, !path.isEmpty {
      return AnyView(
        clickableRow(columns, help: "打开事件关联路径") {
          viewModel.openPath(path)
        })
    }
    return AnyView(row(columns))
  }

  private var runtimeSessionGraphsSection: some View {
    let visibleGraphs = pageItems(viewModel.runtimeSessionGraphs, page: runtimeSessionPage)

    return FrostCard("Session Graphs", subtitle: "由真实 runtime event store 重建的可审计会话链") {
      if viewModel.runtimeSessionGraphs.isEmpty {
        EmptyStateView(
          title: "暂无可重建会话",
          message: "运行时事件写入后，这里会显示按会话整理的观察节点和顺序边。",
          systemImage: "point.3.connected.trianglepath.dotted", compact: true)
      } else {
        tableSurface {
          tableHeader(["会话", "Agent", "节点", "更新时间"])
          ForEach(visibleGraphs) { graph in
            clickableRow(
              [
                graph.sessionId,
                graph.agentNames.isEmpty ? "本机观察" : graph.agentNames.joined(separator: ", "),
                "\(graph.nodeCount) / \(graph.edgeCount)",
                graph.updatedAt.formatted(date: .omitted, time: .standard),
              ], help: "查看会话观察链"
            ) {
              selectedRuntimeSessionID = graph.sessionId
            }
          }
          paginationFooter(
            total: viewModel.runtimeSessionGraphs.count, page: $runtimeSessionPage, label: "Session")
        }
      }
    }
  }

  private var runtimeSensorStatusSection: some View {
    FrostCard("Runtime Sensors", subtitle: "真实权限与传感器状态") {
      VStack(alignment: .leading, spacing: 12) {
        WrapBadges {
          StatusBadge(
            label: viewModel.configuration.enableRuntimeObserver ? "Runtime On" : "Runtime Off",
            tone: viewModel.configuration.enableRuntimeObserver ? .healthy : .neutral)
          StatusBadge(
            label: viewModel.configuration.enableFSEventsWatcher ? "FSEvents On" : "FSEvents Off",
            tone: viewModel.configuration.enableFSEventsWatcher ? .info : .neutral)
          StatusBadge(
            label: endpointSecurityBadgeLabel,
            tone: endpointSecurityBadgeTone)
          StatusBadge(
            label: viewModel.configuration.enableNetworkMonitor ? "网络快照 On" : "网络快照 Off",
            tone: viewModel.configuration.enableNetworkMonitor ? .info : .neutral)
        }

        Divider()

        if viewModel.snapshot.permissionStates.isEmpty {
          EmptyStateView(
            title: "暂无额外权限状态",
            message: "当前运行时监控未请求额外系统权限；只展示真实可用的轻量观测。",
            systemImage: "lock.shield", compact: true)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.snapshot.permissionStates) { state in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(state.capability.rawValue)
                    .font(.system(size: 11, weight: .bold))
                  Spacer()
                  StatusBadge(label: state.status.rawValue, tone: tone(for: state.status))
                }
                Text(state.message)
                  .font(.system(size: 10.5))
                  .foregroundStyle(FrostTheme.mutedText)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(FrostTheme.tableRowBackground)
              )
            }
          }
        }
      }
    }
  }

  private var runtimeAttributionSection: some View {
    FrostCard("Runtime Attribution", subtitle: "进程到 Agent 的归因") {
      if let agent = selectedAgent {
        let processes = AgentSensingAnalyzer.runtimeProcesses(
          for: agent, snapshot: viewModel.snapshot)
        VStack(alignment: .leading, spacing: 10) {
          detailRow("Selected Agent", agent.displayName)
          detailRow("Runtime Processes", "\(processes.count)")
          detailRow("Process IDs", processes.map { String($0.pid) }.joined(separator: ", "))
          detailRow(
            "Evidence", "\(viewModel.snapshot.evidence.filter { $0.assetId == agent.id }.count)")
          if processes.isEmpty {
            Divider()
            EmptyStateView(
              title: "未观察到运行中进程",
              message: "该 Agent 当前只有静态证据或历史运行状态。",
              systemImage: "pause.circle", compact: true)
          }
        }
      } else {
        EmptyStateView(
          title: "未选择 Agent",
          message: "在 Static Scan 或 Agent Analysis 中选择 Agent 后，可查看运行时归因。",
          systemImage: "scope", compact: true)
      }
    }
  }

  private var runtimeSessionDetailSection: some View {
    FrostCard("Session Detail", subtitle: "选中会话的最近可观察节点") {
      if let graph = selectedRuntimeSessionGraph {
        VStack(alignment: .leading, spacing: 10) {
          detailRow("Session", graph.sessionId)
          detailRow("Agents", graph.agentNames.isEmpty ? "本机观察" : graph.agentNames.joined(separator: ", "))
          detailRow("Observed", "\(graph.nodeCount) nodes · \(graph.edgeCount) edges")
          detailRow(
            "Window",
            "\(graph.startedAt.formatted(date: .abbreviated, time: .shortened)) - \(graph.endedAt.formatted(date: .omitted, time: .shortened))")

          Divider()

          ForEach(graph.nodes.suffix(6)) { node in
            VStack(alignment: .leading, spacing: 3) {
              Text(runtimeEventTitle(node.kind))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(FrostTheme.accent)
              Text(node.message ?? node.title)
                .font(.system(size: 10.5))
                .foregroundStyle(FrostTheme.mutedText)
                .lineLimit(2)
              Text(node.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(FrostTheme.mutedText)
            }
            .padding(8)
            .background(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FrostTheme.tableRowBackground)
            )
          }
        }
      } else {
        EmptyStateView(
          title: "未选择运行时会话",
          message: "在左侧 Session Graphs 中选择一条会话，查看已记录的节点与顺序关系。",
          systemImage: "point.3.connected.trianglepath.dotted", compact: true)
      }
    }
  }

  private func analysisSummaryGrid(_ scrollProxy: ScrollViewProxy) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
      metric(
        "Agents",
        value: agentProfiles.count,
        icon: "scope",
        section: .analysisAgents,
        scrollProxy: scrollProxy
      )
      metric(
        "Active",
        value: agentProfiles.filter(\.isRuntimeActive).count,
        icon: "play.circle",
        section: .analysisAgents,
        scrollProxy: scrollProxy
      )
      metric(
        "Static Linked",
        value: agentProfiles.filter { $0.staticAssetCount > 0 }.count,
        icon: "link",
        section: .analysisAgents,
        scrollProxy: scrollProxy
      )
      metric(
        "Review",
        value: agentProfiles.filter { [.high, .critical].contains($0.highestRisk) }.count,
        icon: "exclamationmark.shield",
        section: .analysisAgents,
        scrollProxy: scrollProxy
      )
    }
  }

  @ViewBuilder
  private var analysisContent: some View {
    FrostDetailLayout(detailWidth: 400) {
      VStack(alignment: .leading, spacing: 18) {
        runningAgentsSection
          .id(AgentScanSection.analysisAgents)
        inactiveAgentsSection
      }
    } detail: {
      agentAnalysisDetail
    }
  }

  private var runningAgentsSection: some View {
    agentProfileSection(
      title: "正在运行的 Agent",
      subtitle: "按最近观察和使用信号排序",
      emptyTitle: "暂无运行中的 Agent",
      emptyMessage: "当前运行时快照中没有观察到正在运行的 Agent。",
      profiles: runningAgentProfiles,
      page: $runningAgentPage
    )
  }

  private var inactiveAgentsSection: some View {
    agentProfileSection(
      title: "未运行的 Agent",
      subtitle: "按最近观察和资产信号排序",
      emptyTitle: "暂无未运行的 Agent",
      emptyMessage: "当前所有 Agent 都处于运行或最近观察状态。",
      profiles: inactiveAgentProfiles,
      page: $inactiveAgentPage
    )
  }

  private func agentProfileSection(
    title: String,
    subtitle: String,
    emptyTitle: String,
    emptyMessage: String,
    profiles: [AgentSensingProfile],
    page: Binding<Int>
  ) -> some View {
    let visibleProfiles = pageItems(profiles, page: page.wrappedValue)

    return FrostCard(title, subtitle: subtitle) {
      if agentProfiles.isEmpty {
        EmptyStateView(
          title: "暂无 Agent 画像",
          message: "完成静态发现或观察到运行中 Agent 后，这里会展示聚合画像。",
          systemImage: "person.crop.rectangle.stack", compact: true)
      } else if profiles.isEmpty {
        EmptyStateView(
          title: emptyTitle,
          message: emptyMessage,
          systemImage: "tray", compact: true)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text("点击任意 Agent 卡片，在右侧查看 MCP、Skill、Context、Memory 和活跃情况。排序优先使用最近观察时间，其次参考运行进程、证据和资产信号。")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(FrostTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)

          LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            ForEach(visibleProfiles) { profile in
              agentProfileCard(profile)
            }
          }

          paginationFooter(total: profiles.count, page: page, label: "Agent")
        }
      }
    }
  }

  private func agentProfileCard(_ profile: AgentSensingProfile) -> some View {
    Button {
      selectedAgentID = profile.agent.id
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(
                profile.isRuntimeActive
                  ? FrostTheme.accent.opacity(0.16) : Color.primary.opacity(0.06)
              )
            Image(systemName: profile.isRuntimeActive ? "play.circle.fill" : "pause.circle")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(profile.isRuntimeActive ? FrostTheme.accent : FrostTheme.mutedText)
          }
          .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 5) {
            Text(profile.agent.displayName)
              .font(.system(size: 14, weight: .bold))
              .lineLimit(2)
            HStack(spacing: 6) {
              StatusBadge(
                label: profile.isRuntimeActive ? "running" : "not running",
                tone: profile.isRuntimeActive ? .healthy : .neutral)
              StatusBadge(label: profile.highestRisk.rawValue, tone: tone(for: profile.highestRisk))
            }
          }

          Spacer(minLength: 0)
        }

        HStack(spacing: 8) {
          miniCount("MCP", profile.mcpCount)
          miniCount("Skill", profile.skillCount)
          miniCount("Ctx", profile.contextCount)
          miniCount("Mem", profile.memoryCount)
          miniCount("Run", profile.runtimeProcessCount)
        }

        Text(profile.usageSummary)
          .font(.system(size: 10.2, weight: .semibold))
          .foregroundStyle(FrostTheme.accent.opacity(0.9))
          .lineLimit(1)

        Text(profile.analysisSummary)
          .font(.system(size: 10.5))
          .foregroundStyle(FrostTheme.mutedText)
          .lineLimit(2)
      }
      .padding(13)
      .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .fill(
            selectedAgentID == profile.agent.id
              ? FrostTheme.accent.opacity(0.10) : FrostTheme.moduleWellBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .stroke(
            selectedAgentID == profile.agent.id
              ? FrostTheme.accent.opacity(0.52) : FrostTheme.subtleBorder,
            lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("查看 \(profile.agent.displayName) 的资产和活跃情况")
  }

  private func miniCount(_ title: String, _ value: Int) -> some View {
    VStack(spacing: 2) {
      Text("\(value)")
        .font(.system(size: 14, weight: .bold))
        .monospacedDigit()
      Text(title)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(FrostTheme.mutedText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(FrostTheme.tableRowBackground)
    )
  }

  private var agentAnalysisDetail: some View {
    FrostCard("Agent Intelligence", subtitle: "证据覆盖与运行态摘要") {
      if let profile = selectedProfile {
        let mcpServers = AgentSensingAnalyzer.mcpServers(
          for: profile.agent, snapshot: viewModel.snapshot)
        let skills = AgentSensingAnalyzer.skills(for: profile.agent, snapshot: viewModel.snapshot)
        let contextFiles = AgentSensingAnalyzer.contextFiles(
          for: profile.agent, snapshot: viewModel.snapshot)
        let memories = AgentSensingAnalyzer.memories(
          for: profile.agent, snapshot: viewModel.snapshot)
        let processes = AgentSensingAnalyzer.runtimeProcesses(
          for: profile.agent, snapshot: viewModel.snapshot)

        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text(profile.agent.displayName)
              .font(.system(size: 15, weight: .bold))
              .lineLimit(2)
            HStack(spacing: 6) {
              StatusBadge(
                label: profile.coverageLabel, tone: profile.isRuntimeActive ? .healthy : .neutral)
              StatusBadge(label: profile.agent.agentType.rawValue, tone: .info)
              StatusBadge(label: profile.highestRisk.rawValue, tone: tone(for: profile.highestRisk))
            }
          }

          Divider()

          detailRow("Confidence", "\(profile.agent.confidence)")
          detailRow("MCP", "\(profile.mcpCount)")
          detailRow("Skills", "\(profile.skillCount)")
          detailRow("Context", "\(profile.contextCount)")
          detailRow("Memory", "\(profile.memoryCount)")
          detailRow("Runtime", "\(profile.runtimeProcessCount)")
          detailRow("Evidence", "\(profile.evidenceCount)")

          Divider()

          Text(profile.analysisSummary)
            .font(.system(size: 11))
            .foregroundStyle(FrostTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)

          pathGroup("Config", profile.agent.configPaths)
          pathGroup("Workspace", profile.agent.workspacePaths)
          pathGroup("Executable", profile.agent.executablePaths)

          linkedAssetList(
            "Active Processes",
            emptyMessage: "当前没有运行中进程。",
            items: processes.map {
              LinkedAssetLabel(
                title: "\($0.processName) · pid \($0.pid)",
                subtitle: $0.executablePath ?? $0.bundlePath ?? "-",
                systemImage: "play.circle")
            })
          linkedAssetList(
            "MCP",
            emptyMessage: "未关联 MCP Server。",
            items: mcpServers.map {
              LinkedAssetLabel(
                title: $0.name, subtitle: $0.configPath, systemImage: "puzzlepiece.extension")
            })
          linkedAssetList(
            "Skills",
            emptyMessage: "未关联 Skill。",
            items: skills.map {
              LinkedAssetLabel(title: $0.name, subtitle: $0.path, systemImage: "terminal")
            })
          linkedAssetList(
            "Context",
            emptyMessage: "未关联上下文文件。",
            items: contextFiles.map {
              LinkedAssetLabel(
                title: URL(fileURLWithPath: $0.path).lastPathComponent, subtitle: $0.path,
                systemImage: "doc.text")
            })
          linkedAssetList(
            "Memory",
            emptyMessage: "未关联 Memory。",
            items: memories.map {
              LinkedAssetLabel(
                title: $0.format.rawValue, subtitle: $0.path, systemImage: "externaldrive")
            })
        }
      } else {
        EmptyStateView(
          title: "未选择 Agent",
          message: "点击左侧 Agent 画像行查看静态资产、动态进程和证据覆盖。",
          systemImage: "sidebar.right", compact: true)
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

  private var runtimeProcesses: [RuntimeProcessAsset] {
    viewModel.runtimeProcesses
  }

  private var runtimeEvents: [RuntimeEventRecord] {
    viewModel.runtimeEvents
  }

  private var agentProfiles: [AgentSensingProfile] {
    viewModel.agentProfiles
  }

  private var runningAgentProfiles: [AgentSensingProfile] {
    agentProfiles.filter(\.isRuntimeActive).sorted(by: AgentSensingAnalyzer.usageSort)
  }

  private var inactiveAgentProfiles: [AgentSensingProfile] {
    agentProfiles.filter { !$0.isRuntimeActive }.sorted(by: AgentSensingAnalyzer.usageSort)
  }

  private var selectedProfile: AgentSensingProfile? {
    agentProfiles.first { $0.agent.id == selectedAgentID }
      ?? agentProfiles.first
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

  private var emptySensingState: some View {
    FrostCard("真实空状态", subtitle: "No local intelligence assets discovered") {
      EmptyStateView(
        title: "未发现本机 Agent 资产",
        message:
          "当前轻量感知范围内没有发现 Agent、MCP、Skill 或上下文资产。创建 AGENTS.md、.mcp.json、SKILL.md 或安装本地 Agent 后可重新构建画像。",
        systemImage: "checkmark.shield"
      )
      .frame(minHeight: 260)
    }
  }

  private var commonAgentsSection: some View {
    let visibleAgents = pageItems(displayedCommonAgents, page: commonAgentPage)

    return FrostCard("Known Agents", subtitle: "Codex / Gemini / Cursor / Trae 等已知 Agent") {
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

    return FrostCard("Custom Agents", subtitle: "未知 / 自定义终端 Agent 候选") {
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
      columns: [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top),
      ],
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
            label: endpointSecurityBadgeLabel,
            tone: endpointSecurityBadgeTone)
          StatusBadge(
            label: viewModel.configuration.enableNetworkMonitor ? "网络快照 On" : "网络快照 Off",
            tone: viewModel.configuration.enableNetworkMonitor ? .info : .neutral)
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

  private var selectedRuntimeSessionGraph: RuntimeSessionGraph? {
    if let selectedRuntimeSessionID,
      let graph = viewModel.runtimeSessionGraphs.first(where: { $0.sessionId == selectedRuntimeSessionID })
    {
      return graph
    }
    return viewModel.runtimeSessionGraphs.first
  }

  private var endpointSecurityBadgeLabel: String {
    guard viewModel.configuration.enableEndpointSecurityMonitor else {
      return "ES 未配置"
    }
    return "ES 检测中"
  }

  private var endpointSecurityBadgeTone: StatusBadgeTone {
    viewModel.configuration.enableEndpointSecurityMonitor ? .warning : .neutral
  }

  private func runtimeEventTitle(_ kind: RuntimeEventKind) -> String {
    switch kind {
    case .processObservation:
      "进程快照"
    case .llmRequest:
      "LLM 请求"
    case .llmResponse:
      "LLM 响应"
    case .mcpToolList:
      "MCP 工具列表"
    case .mcpToolCall:
      "MCP 工具调用"
    case .mcpToolResult:
      "MCP 调用结果"
    case .mcpError:
      "MCP 错误"
    case .toolCall:
      "工具调用"
    case .toolResult:
      "工具结果"
    case .commandExec:
      "命令执行"
    case .fileEvent:
      "文件变化"
    case .networkEvent:
      "网络快照"
    case .memoryWrite:
      "Memory 写入"
    case .permissionState:
      "权限状态"
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

  private func linkedAssetList(
    _ title: String,
    emptyMessage: String,
    items: [LinkedAssetLabel]
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(FrostTheme.mutedText)

      if items.isEmpty {
        Text(emptyMessage)
          .font(.system(size: 10.5))
          .foregroundStyle(FrostTheme.mutedText)
          .padding(.vertical, 2)
      } else {
        ForEach(items.prefix(6)) { item in
          Button {
            if item.subtitle != "-" {
              viewModel.openPath(item.subtitle)
            }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: item.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FrostTheme.accent)
                .frame(width: 16)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.system(size: 11, weight: .semibold))
                  .lineLimit(1)
                Text(item.subtitle)
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(FrostTheme.mutedText)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              Spacer(minLength: 0)
            }
            .padding(8)
            .background(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FrostTheme.tableRowBackground)
            )
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
          .help("打开 \(item.subtitle)")
        }

        if items.count > 6 {
          Text("还有 \(items.count - 6) 项，可在 Static Scan 对应列表中分页查看。")
            .font(.system(size: 10.5))
            .foregroundStyle(FrostTheme.mutedText)
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

  private func tone(for status: PermissionStatus) -> StatusBadgeTone {
    switch status {
    case .available:
      .healthy
    case .restricted, .missingEntitlement:
      .warning
    case .notConfigured:
      .neutral
    case .failed:
      .critical
    }
  }

  private func runtimeOwnerName(for process: RuntimeProcessAsset) -> String {
    if let sourceAgentId = process.sourceAgentId,
      let agent = viewModel.snapshot.agents.first(where: { $0.id == sourceAgentId })
    {
      return agent.displayName
    }
    if let agent = viewModel.snapshot.agents.first(where: { $0.processIds.contains(process.pid) }) {
      return agent.displayName
    }
    return process.bundleIdentifier ?? process.processName
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

private struct LinkedAssetLabel: Identifiable {
  let id = UUID()
  let title: String
  let subtitle: String
  let systemImage: String
}

private struct RuntimePulseMeter: View {
  let activeProcessCount: Int
  let activeAgentCount: Int
  let isRefreshing: Bool

  var body: some View {
    TimelineView(.periodic(from: Date(), by: 1)) { timeline in
      let phase =
        timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3

      ZStack {
        Circle()
          .fill(FrostTheme.moduleWellBackground)
          .overlay(Circle().stroke(FrostTheme.subtleBorder, lineWidth: 1))

        Circle()
          .stroke(FrostTheme.accent.opacity(0.22), lineWidth: 10)
          .scaleEffect(0.80 + phase * 0.16)
          .opacity(isRefreshing ? 0.72 : 0.36)

        Circle()
          .stroke(FrostTheme.accent.opacity(0.58), lineWidth: 2)
          .scaleEffect(0.68)

        VStack(spacing: 6) {
          Image(
            systemName: isRefreshing
              ? "arrow.triangle.2.circlepath" : "dot.radiowaves.left.and.right"
          )
          .font(.system(size: 21, weight: .bold))
          .foregroundStyle(FrostTheme.accent)
          Text("\(activeProcessCount)")
            .font(.system(size: 34, weight: .bold))
            .monospacedDigit()
          Text("runtime processes")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FrostTheme.mutedText)
          StatusBadge(
            label: "\(activeAgentCount) active agents",
            tone: activeAgentCount > 0 ? .healthy : .neutral)
        }
      }
    }
  }
}

extension View {
  fileprivate func pointingHandCursor() -> some View {
    modifier(PointingHandCursorModifier())
  }

  fileprivate func commandCard(isActive: Bool) -> some View {
    padding(15)
      .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .fill(isActive ? FrostTheme.accent.opacity(0.08) : FrostTheme.moduleWellBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .stroke(isActive ? FrostTheme.accent.opacity(0.38) : FrostTheme.subtleBorder)
      )
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
