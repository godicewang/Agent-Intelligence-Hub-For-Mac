import SwiftUI

struct AgentScanView: View {
  @StateObject private var viewModel = AgentScanViewModel()

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

        Button("导出 JSONL") {
          viewModel.exportJSONL()
        }
        .disabled(viewModel.isScanning)

        Button("重新扫描") {
          viewModel.rescan()
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
    if viewModel.snapshot.agents.isEmpty && !viewModel.isScanning {
      FrostCard("真实空状态", subtitle: "No local agent assets discovered") {
        EmptyStateView(
          title: "未发现 Agent 资产",
          message:
            "当前扫描范围内没有发现 Agent、MCP、Skill 或上下文资产。你可以创建 AGENTS.md、.mcp.json 或安装本地 Agent 后重新扫描。",
          systemImage: "checkmark.shield"
        )
        .frame(minHeight: 260)
      }
    } else {
      VStack(alignment: .leading, spacing: 16) {
        agentsSection
        mcpSection
        skillSection
        contextSection
        permissionSection
      }
    }
  }

  private var agentsSection: some View {
    FrostCard("Agent Assets", subtitle: "真实发现结果") {
      if viewModel.snapshot.agents.isEmpty {
        EmptyStateView(
          title: "暂无 Agent", message: "扫描完成后未发现 Agent 资产。", systemImage: "tray", compact: true)
      } else {
        VStack(spacing: 0) {
          tableHeader(["名称", "类型", "状态", "置信度", "风险", "最近扫描"])
          ForEach(viewModel.snapshot.agents.sorted(by: { $0.confidence > $1.confidence })) {
            agent in
            row([
              agent.displayName,
              agent.agentType.rawValue,
              agent.runtimeStatus.rawValue,
              "\(agent.confidence)",
              agent.riskLevel.rawValue,
              agent.lastScannedAt.formatted(date: .numeric, time: .shortened),
            ])
          }
        }
      }
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
          Text(value.isEmpty ? "-" : value)
            .font(.system(size: 12))
            .lineLimit(2)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
      }
      Divider()
    }
  }
}

struct AgentScanView_Previews: PreviewProvider {
  static var previews: some View {
    AgentScanView()
      .frame(width: 1100, height: 720)
  }
}
