import Foundation

final class MemoryFileScanner {
  private let limits: ScanLimits

  init(limits: ScanLimits = ScanLimits()) {
    self.limits = limits
  }

  func scan(files: [URL], sourceAgentId: UUID? = nil) -> [MemoryAsset] {
    files.compactMap { asset(url: $0, sourceAgentId: sourceAgentId) }
  }

  func asset(url: URL, sourceAgentId: UUID? = nil) -> MemoryAsset? {
    guard DiscoveryUtilities.fileExists(url) else { return nil }
    let name = url.lastPathComponent.lowercased()
    let format: MemoryFormat
    if name.hasSuffix(".jsonl") {
      format = .jsonl
    } else if name.hasSuffix(".sqlite") || name.hasSuffix(".db") {
      format = .sqlite
    } else if name.hasSuffix(".json") {
      format = .json
    } else if name.contains("vector") || name.hasSuffix(".faiss") {
      format = .vectorDb
    } else {
      format = .unknown
    }

    let text =
      DiscoveryUtilities.readSmallTextFile(url, maxBytes: min(limits.maxFileBytes, 64 * 1024))?
      .lowercased() ?? ""
    let lineCount =
      format == .jsonl ? text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count : nil

    return MemoryAsset(
      id: UUID(),
      path: url.path,
      format: format,
      sourceAgentId: sourceAgentId,
      estimatedRecordCount: lineCount,
      containsToolHistory: text.contains("tool") || text.contains("function_call"),
      containsConversationHistory: text.contains("messages") || text.contains("conversation")
        || text.contains("prompt"),
      containsProceduralMemory: text.contains("procedure") || text.contains("memory")
        || text.contains("instruction"),
      lastModifiedAt: DiscoveryUtilities.modificationDate(url),
      privacySensitivity: text.range(
        of: DiscoveryUtilities.sensitiveKeyPattern, options: .regularExpression) != nil
        ? .high : .medium
    )
  }
}
