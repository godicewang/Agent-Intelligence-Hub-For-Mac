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
        Text("FrostMI")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(FrostTheme.mutedText)

        Text("Mac端智能")
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
    PageHeader(
      title: "Agent Sensing",
      subtitle: "Local AI agent, MCP, Skill, Context, and Memory sensing.",
      path: "FrostMI / Agent Sensing"
    )
    .padding()
  }
}
