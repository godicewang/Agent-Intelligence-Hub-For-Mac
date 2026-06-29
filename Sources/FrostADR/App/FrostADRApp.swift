import SwiftUI

@main
struct FrostADRApp: App {
  @StateObject private var appViewModel = AppViewModel()
  @StateObject private var settingsViewModel = SettingsViewModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(appViewModel)
        .environmentObject(settingsViewModel)
        .frame(minWidth: 1240, minHeight: 780)
    }
    .defaultSize(width: 1360, height: 860)
    .windowToolbarStyle(.unified)
  }
}
