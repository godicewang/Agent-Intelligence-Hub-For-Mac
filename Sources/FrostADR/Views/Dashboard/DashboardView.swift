import SwiftUI

struct DashboardView: View {
  var body: some View {
    FrostPage {
      PageHeader(
        title: "Dashboard",
        subtitle: "端上 Agent 风险态势、保护模块状态与最近安全事件入口。",
        path: "FrostADR / Dashboard"
      )

      FrostCard("产品状态", subtitle: "Endpoint-native Agent-EDR") {
        HStack(alignment: .center, spacing: 14) {
          StatusBadge(label: "待接入", tone: .neutral)

          Text("等待端上数据接入")
            .font(.system(size: 13))
            .foregroundStyle(FrostTheme.mutedText)

          Spacer()
        }
        .frame(minHeight: 34)
      }

      metricGrid

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], spacing: 16) {
        FrostCard("风险趋势", subtitle: "Risk trend") {
          EmptyStateView(
            title: "等待端上数据接入",
            message: "风险趋势区域已预留。",
            systemImage: "chart.xyaxis.line"
          )
          .frame(minHeight: 220)
        }

        FrostCard("最近事件", subtitle: "Recent activity") {
          PlaceholderTable(
            columns: ["时间", "阶段", "对象", "动作"],
            emptyTitle: "暂无事件",
            emptyMessage: "等待真实端上事件写入。",
            minHeight: 186
          )
        }
      }

      FrostCard("保护模块状态", subtitle: "Module state") {
        PlaceholderTable(
          columns: ["模块", "状态", "策略", "最近活动"],
          emptyTitle: "等待模块状态",
          emptyMessage: "Endpoint Security、Local Proxy、MCP Wrapper 等模块将在真实接入后展示。",
          minHeight: 210
        )
      }
    }
  }

  private var metricGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
      metricCard(title: "Agent 资产", icon: "laptopcomputer")
      metricCard(title: "活动告警", icon: "exclamationmark.triangle")
      metricCard(title: "策略命中", icon: "checklist.checked")
      metricCard(title: "扫描发现", icon: "doc.text.magnifyingglass")
    }
  }

  private func metricCard(title: String, icon: String) -> some View {
    FrostCard(title) {
      EmptyStateView(
        title: "等待端上数据接入",
        message: "指标结构已就绪。",
        systemImage: icon,
        compact: true
      )
      .frame(minHeight: 112)
    }
  }
}

struct DashboardView_Previews: PreviewProvider {
  static var previews: some View {
    DashboardView()
      .environmentObject(AppViewModel())
  }
}
