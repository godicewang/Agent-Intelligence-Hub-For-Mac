import SwiftUI

struct RootView: View {
  var body: some View {
    HStack(spacing: 0) {
      SidebarView()
        .frame(width: 272)

      Rectangle()
        .fill(FrostTheme.sidebarDivider)
        .frame(width: 1)

      AgentScanView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FrostTheme.pageBackground)
    }
    .tint(FrostTheme.accent)
    .background(FrostTheme.pageBackground)
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}
