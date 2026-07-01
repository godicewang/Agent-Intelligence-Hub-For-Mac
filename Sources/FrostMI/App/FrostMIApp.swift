import SwiftUI

@main
struct FrostMIApp: App {
  init() {
    if CommandLine.arguments.contains("--discovery-self-test") {
      Foundation.exit(DiscoverySelfTest.run())
    }
    if CommandLine.arguments.contains("--discovery-print-summary") {
      Foundation.exit(DiscoveryDiagnostics.printColdScanSummary())
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .frame(minWidth: 1240, minHeight: 780)
    }
    .defaultSize(width: 1360, height: 860)
    .windowToolbarStyle(.unified)
  }
}
