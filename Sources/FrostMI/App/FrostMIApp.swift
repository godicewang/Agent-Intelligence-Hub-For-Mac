import SwiftUI

@main
struct FrostMIApp: App {
  init() {
    if CommandLine.arguments.contains("--discovery-self-test") {
      Foundation.exit(DiscoverySelfTest.run())
    }
    if CommandLine.arguments.contains("--cold-start-agent-bench") {
      Foundation.exit(DiscoverySelfTest.runColdStartAgentBench())
    }
    if CommandLine.arguments.contains("--runtime-sensing-bench") {
      Foundation.exit(RuntimeSensingBench.run())
    }
    if CommandLine.arguments.contains("--runtime-event-store-self-test") {
      Foundation.exit(RuntimeEventSelfTests.runStoreSelfTest())
    }
    if CommandLine.arguments.contains("--fsevents-self-test") {
      Foundation.exit(RuntimeEventSelfTests.runFSEventsSelfTest())
    }
    if CommandLine.arguments.contains("--mcp-wrapper-self-test") {
      Foundation.exit(MCPStdioWrapper.runSelfTest())
    }
    if CommandLine.arguments.contains("--codex-runtime-capture-self-test") {
      Foundation.exit(CodexRuntimeCaptureSelfTest.run())
    }
    if CommandLine.arguments.contains("--mcp-stdio-wrapper") {
      Foundation.exit(MCPStdioWrapper.run())
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
