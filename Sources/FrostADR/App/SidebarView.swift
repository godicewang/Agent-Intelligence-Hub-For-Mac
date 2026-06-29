import SwiftUI

struct SidebarView: View {
  @Binding var selection: FrostRoute

  var body: some View {
    VStack(spacing: 0) {
      brandHeader

      VStack(alignment: .leading, spacing: 10) {
        Text("MODULE")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(FrostTheme.sidebarMutedText)
          .tracking(1.1)
          .padding(.horizontal, 14)
          .padding(.top, 14)

        VStack(spacing: 6) {
          ForEach(FrostRoute.allCases) { route in
            SidebarItem(
              route: route,
              isSelected: route == selection
            ) {
              selection = route
            }
          }
        }
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

          Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(FrostTheme.accent)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text("FrostADR")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)

          Text("Endpoint Agent-EDR")
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

  private var endpointStatus: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Endpoint", systemImage: "desktopcomputer")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(FrostTheme.sidebarMutedText)

        Spacer()

        StatusBadge(label: "待接入", tone: .neutral)
      }

      Text("等待端上数据接入")
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

private struct SidebarItem: View {
  let route: FrostRoute
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: route.systemImage)
          .font(.system(size: 15, weight: .bold))
          .frame(width: 22)
          .foregroundStyle(isSelected ? FrostTheme.accent : FrostTheme.sidebarMutedText)

        Text(route.title)
          .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
          .foregroundStyle(isSelected ? .white : FrostTheme.sidebarText)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer()
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(background)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(
            isSelected
              ? FrostTheme.accent.opacity(0.44) : Color.white.opacity(isHovered ? 0.10 : 0),
            lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help(route.title)
    .onHover { isHovered = $0 }
  }

  private var background: Color {
    if isSelected {
      FrostTheme.sidebarSelection
    } else if isHovered {
      FrostTheme.sidebarHover
    } else {
      Color.clear
    }
  }
}

struct SidebarView_Previews: PreviewProvider {
  static var previews: some View {
    SidebarView(selection: .constant(.agentScan))
      .frame(width: 256, height: 760)
  }
}
