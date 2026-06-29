import SwiftUI

struct ApprovalView: View {
  @State private var selectedTab: ApprovalTab = .pending

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Approval",
        subtitle: "高风险 Agent 行为的本地审批入口。",
        path: "FrostADR / Approval"
      )

      Picker("", selection: $selectedTab) {
        ForEach(ApprovalTab.allCases) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 300)

      FrostDetailLayout {
        FrostCard(selectedTab.title, subtitle: selectedTab.subtitle) {
          PlaceholderTable(
            columns: selectedTab.columns,
            emptyTitle: selectedTab.emptyTitle,
            emptyMessage: selectedTab.emptyMessage,
            minHeight: 460
          )
        }
      } detail: {
        DetailPlaceholder(
          title: "审批详情",
          message: "选择审批请求后将在此展示请求来源、风险说明和审计记录。",
          systemImage: "person.badge.shield.checkmark"
        )
      }
    }
  }
}

private enum ApprovalTab: String, CaseIterable, Identifiable {
  case pending
  case history

  var id: String { rawValue }

  var title: String {
    switch self {
    case .pending:
      "待审批"
    case .history:
      "历史审批"
    }
  }

  var subtitle: String {
    switch self {
    case .pending:
      "Pending requests"
    case .history:
      "Approval history"
    }
  }

  var columns: [String] {
    switch self {
    case .pending:
      ["请求", "风险", "Session", "时间"]
    case .history:
      ["请求", "结果", "操作人", "时间"]
    }
  }

  var emptyTitle: String {
    switch self {
    case .pending:
      "暂无待审批请求"
    case .history:
      "暂无历史审批"
    }
  }

  var emptyMessage: String {
    switch self {
    case .pending:
      "等待真实审批请求接入。"
    case .history:
      "等待审批审计记录接入。"
    }
  }
}

struct ApprovalView_Previews: PreviewProvider {
  static var previews: some View {
    ApprovalView()
      .frame(width: 1100, height: 720)
  }
}
