import SwiftUI

struct MCPSkillView: View {
  @State private var selectedTab: MCPSkillTab = .mcpServers

  var body: some View {
    FrostPage {
      PageHeader(
        title: "MCP / Skill",
        subtitle: "MCP Server 与 Skill 资产的静态信任入口。",
        path: "FrostADR / MCP / Skill"
      )

      Picker("", selection: $selectedTab) {
        ForEach(MCPSkillTab.allCases) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 360)

      FrostCard(selectedTab.title, subtitle: selectedTab.subtitle) {
        PlaceholderTable(
          columns: selectedTab.columns,
          emptyTitle: selectedTab.emptyTitle,
          emptyMessage: selectedTab.emptyMessage,
          minHeight: 460
        )
      }
    }
  }
}

private enum MCPSkillTab: String, CaseIterable, Identifiable {
  case mcpServers
  case skills

  var id: String { rawValue }

  var title: String {
    switch self {
    case .mcpServers:
      "MCP Servers"
    case .skills:
      "Skills"
    }
  }

  var subtitle: String {
    switch self {
    case .mcpServers:
      "已发现 MCP 配置与 Server 清单"
    case .skills:
      "已发现 Skill 包与资源清单"
    }
  }

  var columns: [String] {
    switch self {
    case .mcpServers:
      ["名称", "Transport", "配置路径", "命令", "信任状态"]
    case .skills:
      ["名称", "来源", "路径", "权限", "信任状态"]
    }
  }

  var emptyTitle: String {
    switch self {
    case .mcpServers:
      "暂无 MCP Server"
    case .skills:
      "暂无 Skill"
    }
  }

  var emptyMessage: String {
    switch self {
    case .mcpServers:
      "等待 MCP 发现与扫描结果接入。"
    case .skills:
      "等待 Skill 发现与扫描结果接入。"
    }
  }
}

struct MCPSkillView_Previews: PreviewProvider {
  static var previews: some View {
    MCPSkillView()
      .frame(width: 1100, height: 720)
  }
}
