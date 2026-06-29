import SwiftUI

struct FrostPage<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      FrostTheme.pageBackground

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 28)
      }
      .scrollIndicators(.visible)
    }
  }
}

struct FrostDetailLayout<Primary: View, Detail: View>: View {
  var detailWidth: CGFloat = 322
  let primary: Primary
  let detail: Detail

  init(
    detailWidth: CGFloat = 322,
    @ViewBuilder primary: () -> Primary,
    @ViewBuilder detail: () -> Detail
  ) {
    self.detailWidth = detailWidth
    self.primary = primary()
    self.detail = detail()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      primary
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

      detail
        .frame(width: detailWidth, alignment: .topLeading)
    }
  }
}

struct FrostPage_Previews: PreviewProvider {
  static var previews: some View {
    FrostPage {
      PageHeader(title: "Preview", subtitle: "Stable page container.", path: "FrostADR / Preview")
      FrostCard("Card") {
        EmptyStateView(title: "Empty", message: "No data.", compact: true)
      }
    }
    .frame(width: 900, height: 640)
  }
}
