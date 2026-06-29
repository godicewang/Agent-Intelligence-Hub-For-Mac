import SwiftUI

enum FrostTheme {
  static let radius: CGFloat = 8
  static let compactRadius: CGFloat = 6
  static let accent = Color(red: 0.11, green: 0.62, blue: 0.68)
  static let accentStrong = Color(red: 0.02, green: 0.42, blue: 0.48)
  static let sidebarBackground = Color(red: 0.038, green: 0.044, blue: 0.050)
  static let sidebarSurface = Color(red: 0.064, green: 0.075, blue: 0.082)
  static let sidebarSelection = Color(red: 0.085, green: 0.135, blue: 0.142)
  static let sidebarHover = Color.white.opacity(0.052)
  static let sidebarDivider = Color.black.opacity(0.44)
  static let sidebarText = Color.white.opacity(0.86)
  static let sidebarMutedText = Color.white.opacity(0.58)

  static var pageBackground: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var cardBackground: Color {
    Color(nsColor: .controlBackgroundColor)
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

  static var moduleWellBackground: Color {
    Color(nsColor: .textBackgroundColor).opacity(0.54)
  }

  static var border: Color {
    Color.primary.opacity(0.105)
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
    Color.black.opacity(0.14)
  }
}
