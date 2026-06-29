import SwiftUI

struct AlertsView: View {
  @State private var selectedSeverity: AlertSeverityFilter = .all

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Alerts",
        subtitle: "运行时检测、策略命中与阻断审计的告警入口。",
        path: "FrostADR / Alerts"
      )

      FrostCard("严重级别筛选", subtitle: "Severity filter") {
        Picker("", selection: $selectedSeverity) {
          ForEach(AlertSeverityFilter.allCases) { severity in
            Text(severity.title).tag(severity)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
      }

      FrostDetailLayout {
        VStack(alignment: .leading, spacing: 14) {
          FrostCard("告警列表", subtitle: "Runtime alerts") {
            PlaceholderTable(
              columns: ["严重级别", "时间", "阶段", "对象", "动作"],
              emptyTitle: "暂无告警",
              emptyMessage: "等待运行时检测事件接入。",
              minHeight: 320
            )
          }

          FrostCard("时间线", subtitle: "Alert timeline") {
            EmptyStateView(
              title: "暂无时间线",
              message: "选择告警后将在此展示关联事件序列。",
              systemImage: "timeline.selection"
            )
            .frame(minHeight: 170)
          }
        }
      } detail: {
        DetailPlaceholder(
          title: "告警详情",
          message: "选择告警后将在此展示检测阶段、证据与处置记录。",
          systemImage: "exclamationmark.triangle"
        )
      }
    }
  }
}

private enum AlertSeverityFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case critical = "Critical"
  case high = "High"
  case medium = "Medium"
  case low = "Low"
  case info = "Info"

  var id: String { rawValue }
  var title: String { rawValue }
}

struct AlertsView_Previews: PreviewProvider {
  static var previews: some View {
    AlertsView()
      .frame(width: 1100, height: 720)
  }
}
