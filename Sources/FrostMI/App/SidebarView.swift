import SwiftUI

struct SidebarView: View {
  var body: some View {
    VStack(spacing: 0) {
      brandHeader

      VStack(alignment: .leading, spacing: 10) {
        Text("INTELLIGENCE")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(FrostTheme.sidebarMutedText)
          .tracking(1.1)
          .padding(.horizontal, 14)
          .padding(.top, 14)

        agentSensingItem
          .padding(.horizontal, 12)
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)

      Spacer(minLength: 24)
      endpointStatus
    }
    .background(FrostTheme.sidebarBackground)
  }

  private var brandHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FrostTheme.accent.opacity(0.20))
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FrostTheme.accent.opacity(0.45), lineWidth: 1)
            )

          Image(systemName: "snowflake")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(FrostTheme.accent)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text("FrostMI")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)

          Text("Frost Mac Intelligence")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(FrostTheme.sidebarMutedText)
        }
      }

      HStack(spacing: 6) {
        Capsule()
          .fill(FrostTheme.accent)
          .frame(width: 6, height: 6)

        Text("macOS Apple Silicon")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(FrostTheme.sidebarMutedText)

        Spacer()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 18)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .background(
      Rectangle()
        .fill(FrostTheme.sidebarSurface.opacity(0.48))
    )
  }

  private var agentSensingItem: some View {
    HStack(spacing: 10) {
      Image(systemName: "scope")
        .font(.system(size: 15, weight: .bold))
        .frame(width: 22)
        .foregroundStyle(FrostTheme.accent)

      Text("Agent Sensing")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)

      Spacer()
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(FrostTheme.sidebarSelection)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(FrostTheme.accent.opacity(0.44), lineWidth: 1)
    )
    .help("Agent Sensing")
  }

  private var endpointStatus: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Agent Sensing", systemImage: "scope")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(FrostTheme.sidebarMutedText)

        Spacer()

        StatusBadge(label: "本地", tone: .info)
      }

      Text("本机 Agent、MCP、Skill、Context 和 Memory 感知")
        .font(.system(size: 12))
        .foregroundStyle(FrostTheme.sidebarMutedText)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(FrostTheme.sidebarSurface)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    )
    .padding(12)
  }
}

struct SidebarView_Previews: PreviewProvider {
  static var previews: some View {
    SidebarView()
      .frame(width: 256, height: 760)
  }
}
