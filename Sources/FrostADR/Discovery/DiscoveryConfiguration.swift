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
  var enableUserApplicationSupportScan: Bool

  static func `default`(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) -> DiscoveryConfiguration {
    let normalizedProjectRoot = projectRoot.standardizedFileURL
    var roots: [URL] = []
    if isSafeAutomaticWorkspaceRoot(normalizedProjectRoot, homeDirectory: homeDirectory) {
      roots.append(normalizedProjectRoot)
    }
    roots = roots.map { $0.standardizedFileURL }.uniqueSorted()
    return DiscoveryConfiguration(
      homeDirectory: homeDirectory,
      projectRoot: normalizedProjectRoot,
      scanRoots: roots,
      limits: .lightweightDefault,
      enableColdStartScan: true,
      enableRuntimeObserver: true,
      enableFSEventsWatcher: !roots.isEmpty,
      enableEndpointSecurityMonitor: false,
      enableNetworkMonitor: false,
      enableUserApplicationSupportScan: false
    )
  }

  func allowsAutomaticAccess(to url: URL) -> Bool {
    if !enableUserApplicationSupportScan,
      DiscoveryUtilities.isUserApplicationSupportPath(url, home: homeDirectory)
    {
      return false
    }
    return true
  }

  private static func isSafeAutomaticWorkspaceRoot(_ root: URL, homeDirectory: URL) -> Bool {
    let path = root.standardizedFileURL.path
    let homePath = homeDirectory.standardizedFileURL.path
    guard DiscoveryUtilities.directoryExists(root), path != "/", path != homePath else {
      return false
    }

    let protectedRoots = [
      homeDirectory.appendingPathComponent("Desktop"),
      homeDirectory.appendingPathComponent("Documents"),
      homeDirectory.appendingPathComponent("Downloads"),
      homeDirectory.appendingPathComponent("Library"),
      homeDirectory.appendingPathComponent("Pictures"),
      homeDirectory.appendingPathComponent("Movies"),
      homeDirectory.appendingPathComponent("Music"),
    ].map { $0.standardizedFileURL.path }
    guard !protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
      return false
    }

    let appBundleMarkers = [".app/Contents/MacOS", ".app/Contents/Resources"]
    guard !appBundleMarkers.contains(where: { path.contains($0) }) else {
      return false
    }

    return path.hasPrefix(homePath + "/") || path.hasPrefix("/tmp/")
      || path.hasPrefix("/private/tmp/")
  }
}
