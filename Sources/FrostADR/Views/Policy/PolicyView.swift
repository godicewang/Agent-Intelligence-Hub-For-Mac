import SwiftUI

struct PolicyView: View {
  var body: some View {
    FrostPage {
      PageHeader(
        title: "Rules / Policy",
        subtitle: "本地策略、规则包与检测动作的管理入口。",
        path: "FrostADR / Rules / Policy"
      )

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
        FrostCard("本地保护模式", subtitle: "Local protection mode") {
          EmptyStateView(
            title: "等待策略引擎接入",
            message: "保护模式状态区域已预留。",
            systemImage: "shield"
          )
          .frame(minHeight: 130)
        }

        FrostCard("规则包信息", subtitle: "Rule pack") {
          EmptyStateView(
            title: "暂无规则包信息",
            message: "等待控制平面或本地规则包接入。",
            systemImage: "shippingbox"
          )
          .frame(minHeight: 130)
        }
      }

      FrostDetailLayout {
        FrostCard("规则列表", subtitle: "Policy rules") {
          PlaceholderTable(
            columns: ["规则", "阶段", "动作", "状态", "规则包"],
            emptyTitle: "暂无规则",
            emptyMessage: "等待规则源接入。",
            minHeight: 420
          )
        }
      } detail: {
        DetailPlaceholder(
          title: "规则详情",
          message: "选择规则后将在此展示匹配条件、动作和版本信息。",
          systemImage: "checklist.checked"
        )
      }
    }
  }
}

struct PolicyView_Previews: PreviewProvider {
  static var previews: some View {
    PolicyView()
      .frame(width: 1100, height: 720)
  }
}
