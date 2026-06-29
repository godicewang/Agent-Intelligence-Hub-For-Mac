import SwiftUI

struct PageHeader: View {
  let title: String
  let subtitle: String
  let path: String

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(path)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FrostTheme.mutedText)

          StatusBadge(label: "Local Endpoint", tone: .info)
        }

        Text(title)
          .font(.system(size: 25, weight: .bold))

        Text(subtitle)
          .font(.system(size: 13))
          .foregroundStyle(FrostTheme.mutedText)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Text("FrostADR")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(FrostTheme.mutedText)

        Text("端上轻量发现")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(FrostTheme.accent)
      }
    }
    .padding(.horizontal, 2)
    .padding(.bottom, 2)
  }
}

struct PageHeader_Previews: PreviewProvider {
  static var previews: some View {
    PageHeader(title: "Dashboard", subtitle: "端上 Agent 风险态势与保护模块状态。", path: "FrostADR / Dashboard")
      .padding()
  }
}
