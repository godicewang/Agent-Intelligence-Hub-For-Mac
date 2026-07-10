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
    let candidates =
      ([normalizedProjectRoot] + automaticWorkspaceRoots(homeDirectory: homeDirectory))
      .map { $0.standardizedFileURL }

    for candidate in candidates {
      if isSafeAutomaticWorkspaceRoot(candidate, homeDirectory: homeDirectory) {
        roots.append(candidate)
      }
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
      enableNetworkMonitor: true,
      enableUserApplicationSupportScan: false
    )
  }

  func allowsAutomaticAccess(to url: URL) -> Bool {
    if usesIsolatedHomeDirectory,
      Self.isSystemLevelAbsolutePath(url)
    {
      return false
    }
    if !enableUserApplicationSupportScan,
      DiscoveryUtilities.isUserApplicationSupportPath(url, home: homeDirectory),
      !Self.isKnownAgentApplicationSupportPath(url, homeDirectory: homeDirectory)
    {
      return false
    }
    return true
  }

  private var usesIsolatedHomeDirectory: Bool {
    homeDirectory.standardizedFileURL.path
      != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
  }

  private static func isSystemLevelAbsolutePath(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    return path.hasPrefix("/Applications/")
      || path.hasPrefix("/Library/")
      || path.hasPrefix("/System/")
      || path.hasPrefix("/etc/")
      || path.hasPrefix("/opt/")
      || path == "/Applications"
      || path == "/Library"
      || path == "/System"
      || path == "/etc"
      || path == "/opt"
  }

  private static let knownAgentApplicationSupportDirectories: Set<String> = [
    "Claude",
    "Codex",
    "Cursor",
    "Code",
    "Code - Insiders",
    "Trae",
    "Windsurf",
  ]

  private static func isKnownAgentApplicationSupportPath(
    _ url: URL, homeDirectory: URL
  ) -> Bool {
    let applicationSupport = homeDirectory.standardizedFileURL
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .standardizedFileURL
      .path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(applicationSupport + "/") else {
      return false
    }

    let relativePath = String(path.dropFirst(applicationSupport.count + 1))
    guard let directoryName = relativePath.split(separator: "/").first else {
      return false
    }
    return knownAgentApplicationSupportDirectories.contains(String(directoryName))
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

  private static func automaticWorkspaceRoots(homeDirectory: URL) -> [URL] {
    [
      "Coding",
      "Code",
      "Developer",
      "Projects",
      "Workspace",
      "Workspaces",
      "src",
    ].map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
  }
}
