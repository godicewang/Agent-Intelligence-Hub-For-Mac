import SwiftUI

enum FrostTheme {
  static let radius: CGFloat = 8
  static let compactRadius: CGFloat = 6
  static let accent = Color(red: 0.10, green: 0.55, blue: 0.68)
  static let accentStrong = Color(red: 0.04, green: 0.44, blue: 0.56)
  static let sidebarBackground = Color(red: 0.052, green: 0.061, blue: 0.070)
  static let sidebarSurface = Color(red: 0.078, green: 0.092, blue: 0.106)
  static let sidebarSelection = Color(red: 0.110, green: 0.145, blue: 0.160)
  static let sidebarHover = Color.white.opacity(0.060)
  static let sidebarDivider = Color.black.opacity(0.38)
  static let sidebarText = Color.white.opacity(0.86)
  static let sidebarMutedText = Color.white.opacity(0.58)

  static var pageBackground: Color {
    Color(nsColor: .underPageBackgroundColor)
  }

  static var cardBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var elevatedCardBackground: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  static var headerBackground: Color {
    Color(nsColor: .controlBackgroundColor).opacity(0.72)
  }

  static var secondaryCardBackground: Color {
    Color(nsColor: .textBackgroundColor).opacity(0.74)
  }

  static var border: Color {
    Color.primary.opacity(0.120)
  }

  static var subtleBorder: Color {
    Color.primary.opacity(0.075)
  }

  static var mutedText: Color {
    Color.secondary
  }

  static var tableHeaderBackground: Color {
    Color.primary.opacity(0.046)
  }

  static var tableRowBackground: Color {
    Color.primary.opacity(0.018)
  }

  static var shadow: Color {
    Color.black.opacity(0.10)
  }
}
