import SwiftUI

struct StaticScanView: View {
  @State private var selectedScope: StaticScanScope = .all

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Static Scan",
        subtitle: "MCP、Skill、Memory 与上下文文件的静态风险扫描入口。",
        path: "FrostADR / Static Scan"
      )

      FrostCard("扫描状态", subtitle: "Scanner state") {
        HStack(spacing: 12) {
          StatusBadge(label: "待接入", tone: .neutral)
          Text("等待扫描器状态接入")
            .font(.system(size: 13))
            .foregroundStyle(FrostTheme.mutedText)
          Spacer()
        }
        .frame(minHeight: 34)
      }

      FrostDetailLayout {
        VStack(alignment: .leading, spacing: 14) {
          FrostCard("扫描类型", subtitle: "Scope filter") {
            Picker("", selection: $selectedScope) {
              ForEach(StaticScanScope.allCases) { scope in
                Text(scope.title).tag(scope)
              }
            }
            .pickerStyle(.segmented)
          }

          FrostCard("Findings", subtitle: "Static scan findings") {
            PlaceholderTable(
              columns: ["严重级别", "类型", "资产", "规则", "状态"],
              emptyTitle: "暂无 Finding",
              emptyMessage: "等待静态扫描器接入真实发现。",
              minHeight: 360
            )
          }
        }
      } detail: {
        DetailPlaceholder(
          title: "Finding 详情",
          message: "选择扫描发现后将在此展示上下文、规则和处置建议。",
          systemImage: "doc.text.magnifyingglass"
        )
      }
    }
  }
}

private enum StaticScanScope: String, CaseIterable, Identifiable {
  case all = "All"
  case mcp = "MCP"
  case skill = "Skill"
  case memory = "Memory"
  case context = "Context"

  var id: String { rawValue }
  var title: String { rawValue }
}

struct StaticScanView_Previews: PreviewProvider {
  static var previews: some View {
    StaticScanView()
      .frame(width: 1100, height: 720)
  }
}
