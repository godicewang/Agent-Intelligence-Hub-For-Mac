import SwiftUI

struct SessionGraphView: View {
  var body: some View {
    FrostPage {
      PageHeader(
        title: "Session Graph",
        subtitle: "Observable decision and execution chain reconstruction.",
        path: "FrostADR / Session Graph"
      )

      FrostCard("Session 选择", subtitle: "Session selector") {
        HStack(spacing: 12) {
          Menu("选择 Session") {
            Text("等待 Session 数据接入")
          }
          .menuStyle(.borderlessButton)

          StatusBadge(label: "待接入", tone: .neutral)
          Spacer()
        }
        .frame(minHeight: 36)
      }

      FrostDetailLayout {
        VStack(alignment: .leading, spacing: 14) {
          FrostCard("决策链图", subtitle: "Observable execution chain") {
            ZStack {
              RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
                .fill(FrostTheme.secondaryCardBackground)
                .overlay(
                  RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
                    .stroke(FrostTheme.subtleBorder, lineWidth: 1)
                )

              EmptyStateView(
                title: "暂无 Session Graph",
                message: "等待真实 Session 事件接入后绘制节点与边。",
                systemImage: "point.3.connected.trianglepath.dotted"
              )
            }
            .frame(minHeight: 380)
          }

          FrostCard("风险解释", subtitle: "Risk explanation") {
            EmptyStateView(
              title: "暂无风险解释",
              message: "选择 Session 或节点后展示可观察证据与风险理由。",
              systemImage: "text.magnifyingglass"
            )
            .frame(minHeight: 150)
          }
        }
      } detail: {
        DetailPlaceholder(
          title: "节点详情",
          message: "选择图节点后将在此展示事件类型、时间、路径和关联证据。",
          systemImage: "smallcircle.filled.circle"
        )
      }
    }
  }
}

struct SessionGraphView_Previews: PreviewProvider {
  static var previews: some View {
    SessionGraphView()
      .frame(width: 1100, height: 720)
  }
}
