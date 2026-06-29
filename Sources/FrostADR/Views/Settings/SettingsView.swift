import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settings: SettingsViewModel

  var body: some View {
    FrostPage {
      PageHeader(
        title: "Settings",
        subtitle: "端上保护、隐私、本地代理与扫描入口的本地 UI 设置。",
        path: "FrostADR / Settings"
      )

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16)], spacing: 16) {
        controlPlaneSection
        protectionSection
        privacySection
        proxySection
        mcpWrapperSection
        staticScanSection
        systemSensorSection
        aboutSection
      }
    }
  }

  private var controlPlaneSection: some View {
    FrostCard("控制平面地址", subtitle: "Control plane") {
      TextField("https://", text: $settings.controlPlaneAddress)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 520)
    }
  }

  private var protectionSection: some View {
    FrostCard("本地保护模式", subtitle: "Local protection") {
      Picker("模式", selection: $settings.protectionMode) {
        ForEach(LocalProtectionMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 420)
    }
  }

  private var privacySection: some View {
    FrostCard("隐私与数据上传", subtitle: "Privacy") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("持久化前本地脱敏", isOn: $settings.redactSecretsBeforeStorage)
        Toggle("允许上传到控制平面", isOn: $settings.allowControlPlaneUpload)
      }
      .toggleStyle(.switch)
    }
  }

  private var proxySection: some View {
    FrostCard("Local LLM Proxy", subtitle: "Local proxy") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("启用 Local LLM Proxy", isOn: $settings.localLLMProxyEnabled)
          .toggleStyle(.switch)

        TextField("端口", text: $settings.localLLMProxyPort)
          .textFieldStyle(.roundedBorder)
          .frame(width: 180)
      }
    }
  }

  private var mcpWrapperSection: some View {
    FrostCard("MCP Wrapper", subtitle: "Tool wrapper") {
      Toggle("启用 MCP Wrapper", isOn: $settings.mcpWrapperEnabled)
        .toggleStyle(.switch)
    }
  }

  private var staticScanSection: some View {
    FrostCard("静态扫描", subtitle: "Static scan") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("启用静态扫描", isOn: $settings.staticScanEnabled)
        Toggle("扫描工作区上下文文件", isOn: $settings.scanWorkspaceContextFiles)
      }
      .toggleStyle(.switch)
    }
  }

  private var systemSensorSection: some View {
    FrostCard("系统事件感知", subtitle: "System sensor") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("启用系统事件感知", isOn: $settings.systemSensorEnabled)
        Toggle("被动进程观察", isOn: $settings.passiveProcessObservation)
      }
      .toggleStyle(.switch)
    }
  }

  private var aboutSection: some View {
    FrostCard("关于 FrostADR", subtitle: "Endpoint-native Agent Detection & Response") {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("产品")
            .foregroundStyle(FrostTheme.mutedText)
          Spacer()
          Text("FrostADR")
            .fontWeight(.semibold)
        }

        Divider()

        HStack {
          Text("阶段")
            .foregroundStyle(FrostTheme.mutedText)
          Spacer()
          Text("UI Shell")
            .fontWeight(.semibold)
        }
      }
      .font(.system(size: 13))
    }
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
      .environmentObject(SettingsViewModel())
      .frame(width: 1100, height: 900)
  }
}
