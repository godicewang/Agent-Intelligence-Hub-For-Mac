import Foundation

struct DiscoveryConfiguration: Codable, Hashable {
  var homeDirectory: URL
  var projectRoot: URL
  var scanRoots: [URL]
  var limits: ScanLimits
  var enableColdStartScan: Bool
  var enableRuntimeObserver: Bool
  var enableFSEventsWatcher: Bool
  var enableEndpointSecurityMonitor: Bool
  var enableNetworkMonitor: Bool

  static func `default`(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) -> DiscoveryConfiguration {
    var roots = [
      homeDirectory.appendingPathComponent("Projects"),
      homeDirectory.appendingPathComponent("Developer"),
      homeDirectory.appendingPathComponent("Code"),
      homeDirectory.appendingPathComponent("Workspace"),
      homeDirectory.appendingPathComponent("Documents"),
      homeDirectory.appendingPathComponent("Coding"),
      projectRoot,
    ]
    roots = roots.map { $0.standardizedFileURL }.uniqueSorted()
    return DiscoveryConfiguration(
      homeDirectory: homeDirectory,
      projectRoot: projectRoot.standardizedFileURL,
      scanRoots: roots,
      limits: ScanLimits(),
      enableColdStartScan: true,
      enableRuntimeObserver: true,
      enableFSEventsWatcher: true,
      enableEndpointSecurityMonitor: true,
      enableNetworkMonitor: true
    )
  }
}
