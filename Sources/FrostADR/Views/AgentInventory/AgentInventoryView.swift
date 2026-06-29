import SwiftUI

struct AgentInventoryView: View {
  @State private var searchText = ""

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Agent Inventory",
        subtitle: "发现并审计本机 AI Agent、上下文文件与相关资产。",
        path: "FrostADR / Agent Inventory"
      )

      FrostCard("工具栏", subtitle: "Search and filters") {
        HStack(spacing: 12) {
          TextField("搜索 Agent、路径或工作区", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 360)

          Menu("筛选器") {
            Text("等待端上数据接入")
          }
          .menuStyle(.borderlessButton)

          Spacer()
        }
      }

      FrostDetailLayout {
        FrostCard("Agent 列表", subtitle: "Discovered assets") {
          PlaceholderTable(
            columns: ["Agent", "类型", "工作区", "风险", "管理状态", "最后观察"],
            emptyTitle: "暂无 Agent 资产",
            emptyMessage: "等待发现器接入真实端上数据。",
            minHeight: 420
          )
        }
      } detail: {
        DetailPlaceholder(
          title: "资产详情",
          message: "选择 Agent 资产后将在此展示路径、指纹、风险和管理状态。",
          systemImage: "laptopcomputer.and.magnifyingglass"
        )
      }
    }
  }
}

struct AgentInventoryView_Previews: PreviewProvider {
  static var previews: some View {
    AgentInventoryView()
      .frame(width: 1100, height: 720)
  }
}
