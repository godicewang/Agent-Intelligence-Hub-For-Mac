import Foundation

final class ConfigParser {
  func jsonObject(at url: URL, maxBytes: Int = 512 * 1024) -> [String: Any]? {
    guard DiscoveryUtilities.fileSize(url) <= UInt64(maxBytes),
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return object
  }

  func text(at url: URL, maxBytes: Int = 256 * 1024) -> String? {
    DiscoveryUtilities.readSmallTextFile(url, maxBytes: maxBytes)
  }

  func keywordHits(in text: String, keywords: [String]) -> [String] {
    let lower = text.lowercased()
    return keywords.filter { lower.contains($0.lowercased()) }.uniqueSorted()
  }
}
