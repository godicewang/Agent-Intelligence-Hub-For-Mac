import SwiftUI

struct AgentScanView: View {
  var body: some View {
    FrostPage {
      PageHeader(
        title: "Agent Scan",
        subtitle: "本机 AI Agent 与相关执行入口的端上扫描模块。",
        path: "FrostADR / Agent Scan"
      )

      AgentScanModuleShell()
    }
  }
}

private struct AgentScanModuleShell: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(FrostTheme.accent.opacity(0.13))
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FrostTheme.accent.opacity(0.28), lineWidth: 1)
            )

          Image(systemName: "scope")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(FrostTheme.accent)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 4) {
          Text("Agent Scan")
            .font(.system(size: 18, weight: .bold))

          Text("模块框架已预留，等待后续接入真实扫描流程。")
            .font(.system(size: 13))
            .foregroundStyle(FrostTheme.mutedText)
        }

        Spacer()

        StatusBadge(label: "待实现", tone: .neutral)
      }
      .padding(18)

      Divider()

      ZStack {
        RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
          .fill(FrostTheme.moduleWellBackground)
          .overlay(
            RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
              .stroke(FrostTheme.subtleBorder, lineWidth: 1)
          )

        VStack(spacing: 12) {
          Image(systemName: "square.dashed")
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(FrostTheme.mutedText.opacity(0.72))

          Text("Agent Scan 模块区域")
            .font(.system(size: 15, weight: .semibold))

          Text("当前阶段仅保留模块容器，不展示内部扫描内容。")
            .font(.system(size: 12))
            .foregroundStyle(FrostTheme.mutedText)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 500)
      .padding(18)
    }
    .background(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .fill(FrostTheme.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: FrostTheme.radius, style: .continuous)
        .stroke(FrostTheme.border, lineWidth: 1)
    )
    .shadow(color: FrostTheme.shadow, radius: 12, x: 0, y: 4)
  }
}

struct AgentScanView_Previews: PreviewProvider {
  static var previews: some View {
    AgentScanView()
      .frame(width: 1100, height: 720)
  }
}
