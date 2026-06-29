import SwiftUI

@main
struct FrostADRApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .frame(minWidth: 1240, minHeight: 780)
    }
    .defaultSize(width: 1360, height: 860)
    .windowToolbarStyle(.unified)
  }
}
