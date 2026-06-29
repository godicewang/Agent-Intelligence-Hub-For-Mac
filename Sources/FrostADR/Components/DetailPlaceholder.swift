import SwiftUI

struct DetailPlaceholder: View {
  let title: String
  let message: String
  var systemImage: String = "sidebar.right"

  var body: some View {
    FrostCard(title) {
      EmptyStateView(
        title: "未选择对象",
        message: message,
        systemImage: systemImage,
        compact: false
      )
      .frame(minHeight: 260)
    }
  }
}

struct DetailPlaceholder_Previews: PreviewProvider {
  static var previews: some View {
    DetailPlaceholder(title: "详情", message: "选择记录后将在此展示详情。")
      .padding()
  }
}
