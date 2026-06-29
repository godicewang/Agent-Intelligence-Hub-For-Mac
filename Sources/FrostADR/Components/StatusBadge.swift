import SwiftUI

enum StatusBadgeTone {
  case neutral
  case info
  case healthy
  case warning
  case critical

  var foreground: Color {
    switch self {
    case .neutral:
      Color.secondary
    case .info:
      FrostTheme.accent
    case .healthy:
      Color(red: 0.20, green: 0.58, blue: 0.38)
    case .warning:
      Color(red: 0.72, green: 0.48, blue: 0.14)
    case .critical:
      Color(red: 0.78, green: 0.24, blue: 0.26)
    }
  }

  var background: Color {
    foreground.opacity(0.13)
  }
}

struct StatusBadge: View {
  let label: String
  var tone: StatusBadgeTone = .neutral

  var body: some View {
    Text(label)
      .font(.system(size: 10.5, weight: .bold))
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .foregroundStyle(tone.foreground)
      .background(
        Capsule(style: .continuous)
          .fill(tone.background)
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(tone.foreground.opacity(0.20), lineWidth: 1)
      )
  }
}

struct StatusBadge_Previews: PreviewProvider {
  static var previews: some View {
    HStack {
      StatusBadge(label: "待接入")
      StatusBadge(label: "状态", tone: .info)
      StatusBadge(label: "注意", tone: .warning)
    }
    .padding()
  }
}
