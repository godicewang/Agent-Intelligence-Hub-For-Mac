import SwiftUI

struct FrostCard<Content: View>: View {
  private let title: String?
  private let subtitle: String?
  private let content: Content

  init(
    _ title: String? = nil,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if title != nil || subtitle != nil {
        HStack(alignment: .top, spacing: 10) {
          Rectangle()
            .fill(FrostTheme.accent.opacity(0.82))
            .frame(width: 3, height: 28)
            .clipShape(Capsule(style: .continuous))

          VStack(alignment: .leading, spacing: 3) {
            if let title {
              Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            }

            if let subtitle {
              Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrostTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }

          Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(FrostTheme.headerBackground)

        Divider()
      }

      content
        .padding(15)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .fill(FrostTheme.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .stroke(FrostTheme.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous))
    .shadow(color: FrostTheme.shadow, radius: 10, x: 0, y: 3)
  }
}

struct FrostCard_Previews: PreviewProvider {
  static var previews: some View {
    FrostCard("区域标题", subtitle: "结构占位") {
      EmptyStateView(title: "等待端上数据接入", message: "该区域将在真实数据源接入后呈现内容。", compact: true)
    }
    .padding()
  }
}
