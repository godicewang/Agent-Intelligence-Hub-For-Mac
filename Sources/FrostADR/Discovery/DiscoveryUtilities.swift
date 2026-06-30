import CryptoKit
import Foundation

enum DiscoveryUtilities {
  static let sensitiveKeyPattern =
    "(?i)(api[_-]?key|token|password|passwd|secret|private[_-]?key|credential|cookie)"
  static let sensitiveValuePattern =
    #"(?i)(sk-[a-z0-9_-]{16,}|xox[baprs]-[a-z0-9-]{16,}|akia[0-9a-z]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)"#

  static func expandedPath(
    _ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    if path == "~" {
      return home
    }
    if path.hasPrefix("~/") {
      return home.appendingPathComponent(String(path.dropFirst(2)))
    }
    return URL(fileURLWithPath: path)
  }

  static func fileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  static func directoryExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  static func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
  }

  static func fileSize(_ url: URL) -> UInt64 {
    ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value
      ?? 0
  }

  static func sha256ForFile(_ url: URL, maxBytes: Int = 1_048_576) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return "unreadable:\(url.path)"
    }
    defer { try? handle.close() }
    let data = handle.readData(ofLength: maxBytes)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func sha256ForString(_ value: String) -> String {
    let data = Data(value.utf8)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func readSmallTextFile(_ url: URL, maxBytes: Int) -> String? {
    guard fileSize(url) <= UInt64(maxBytes), let data = try? Data(contentsOf: url) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func sanitizeArgument(_ value: String) -> String {
    if value.range(of: sensitiveKeyPattern, options: .regularExpression) != nil
      || value.range(of: sensitiveValuePattern, options: .regularExpression) != nil
    {
      return "<redacted-sensitive-argument>"
    }
    if value.count > 180 {
      return String(value.prefix(180)) + "..."
    }
    return value
  }

  static func envKeyNames(from object: Any?) -> [String] {
    if let dict = object as? [String: Any] {
      return dict.keys.sorted()
    }
    if let array = object as? [String] {
      return array.map { $0.components(separatedBy: "=").first ?? $0 }.sorted()
    }
    return []
  }

  static func riskLevel(for score: Int) -> RiskLevel {
    switch score {
    case 80...:
      .critical
    case 60..<80:
      .high
    case 35..<60:
      .medium
    case 1..<35:
      .low
    default:
      .informational
    }
  }

  static func inferredScope(
    for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> DiscoveryScope {
    let path = url.standardizedFileURL.path
    if path.hasPrefix("/etc/") || path.hasPrefix("/Library/") {
      return .system
    }
    if path.hasPrefix(home.path) {
      let relative = String(path.dropFirst(home.path.count))
      if relative.contains("/.vscode/") || relative.contains("/Cursor/") {
        return .extensionScope
      }
      if relative.contains("/Projects/") || relative.contains("/Developer/")
        || relative.contains("/Code/") || relative.contains("/Workspace/")
        || relative.contains("/Coding/")
      {
        return .project
      }
      return .user
    }
    return .unknown
  }

  static func isUserApplicationSupportPath(
    _ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> Bool {
    let path = url.standardizedFileURL.path
    let applicationSupport = home.standardizedFileURL
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .path
    return path == applicationSupport || path.hasPrefix(applicationSupport + "/")
  }
}

struct ScanLimits: Codable, Hashable {
  var maxDepth: Int = 5
  var maxFileBytes: Int = 256 * 1024
  var maxDirectoryEntries: Int = 1_500
  var maxScannedDirectories: Int = 700
  var maxInspectedFiles: Int = 1_200
  var maxCollectedMemoryFiles: Int = 120
  var maxScanSeconds: TimeInterval = 12

  static let lightweightDefault = ScanLimits(
    maxDepth: 3,
    maxFileBytes: 128 * 1024,
    maxDirectoryEntries: 800,
    maxScannedDirectories: 350,
    maxInspectedFiles: 700,
    maxCollectedMemoryFiles: 80,
    maxScanSeconds: 8
  )
}

extension StringProtocol {
  var trimmedQuotes: String {
    var value = String(self)
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
      value.removeFirst()
      value.removeLast()
    }
    return value
  }
}
