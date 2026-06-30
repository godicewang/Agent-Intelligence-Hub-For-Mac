import Foundation

final class SkillScanner {
  private let limits: ScanLimits
  private let scriptExtensions: Set<String> = ["sh", "bash", "py", "js", "ts", "rb", "pl", "zsh"]
  private let textFileExtensions: Set<String> = [
    "bash", "env", "json", "js", "md", "py", "rb", "sh", "toml", "ts", "txt", "yaml", "yml", "zsh",
  ]
  private let textFileNames: Set<String> = [
    "Dockerfile", "Makefile", "package.json", "requirements.txt", "setup.py", "install.sh",
  ]

  init(limits: ScanLimits = ScanLimits()) {
    self.limits = limits
  }

  func scan(directories: [URL], sourceAgentId: UUID? = nil, deadline: Date? = nil)
    -> [SkillAsset]
  {
    directories.flatMap { scan(directory: $0, sourceAgentId: sourceAgentId, deadline: deadline) }
  }

  func scan(directory: URL, sourceAgentId: UUID? = nil, deadline: Date? = nil) -> [SkillAsset] {
    guard DiscoveryUtilities.directoryExists(directory) else { return [] }
    var results: [SkillAsset] = []
    var budget = SkillScanBudget(deadline: deadline)
    walk(directory, depth: 0, budget: &budget) { url in
      if url.lastPathComponent == "SKILL.md" {
        let skillDirectory = url.deletingLastPathComponent()
        results.append(
          asset(skillDirectory: skillDirectory, skillMarkdown: url, sourceAgentId: sourceAgentId))
      }
    }
    return results
  }

  private func asset(skillDirectory: URL, skillMarkdown: URL, sourceAgentId: UUID?) -> SkillAsset {
    let text =
      DiscoveryUtilities.readSmallTextFile(skillMarkdown, maxBytes: limits.maxFileBytes) ?? ""
    let lower = scanTextBundle(skillDirectory: skillDirectory, skillMarkdown: skillMarkdown)
      .lowercased()
    let hasScripts =
      containsScriptFile(in: skillDirectory) || lower.contains("```bash") || lower.contains("```sh")
    let hasExternalURLs = lower.range(of: #"https?://"#, options: .regularExpression) != nil
    let hasInstall = ["install", "setup", "npm install", "pip install", "curl", "brew install"]
      .contains { lower.contains($0) }
    let sensitive =
      lower.range(of: DiscoveryUtilities.sensitiveKeyPattern, options: .regularExpression) != nil
    let risk: RiskLevel =
      sensitive || (hasScripts && hasExternalURLs) ? .medium : hasScripts ? .low : .informational

    return SkillAsset(
      name: skillDirectory.lastPathComponent,
      sourceAgentId: sourceAgentId,
      path: skillDirectory.path,
      scope: DiscoveryUtilities.inferredScope(for: skillDirectory),
      description: description(from: text),
      hasSkillMarkdown: true,
      hasScripts: hasScripts,
      hasExternalURLs: hasExternalURLs,
      hasInstallInstructions: hasInstall,
      hasSensitivePermissionHints: sensitive,
      hash: directoryHash(skillDirectory),
      scanStatus: .preScanned,
      riskLevel: risk,
      lastModifiedAt: DiscoveryUtilities.modificationDate(skillMarkdown)
    )
  }

  private func walk(_ directory: URL, depth: Int, visit: (URL) -> Void) {
    var budget = SkillScanBudget()
    walk(directory, depth: depth, budget: &budget, visit: visit)
  }

  private func walk(
    _ directory: URL, depth: Int, budget: inout SkillScanBudget, visit: (URL) -> Void
  ) {
    guard depth <= limits.maxDepth, budget.canVisitDirectory(limits) else { return }
    budget.visitedDirectories += 1
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in names.prefix(limits.maxDirectoryEntries) {
      if KeywordFileScanner.skipDirectoryNames.contains(name) { continue }
      let url = directory.appendingPathComponent(name)
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      if isDirectory.boolValue {
        walk(url, depth: depth + 1, budget: &budget, visit: visit)
      } else {
        guard budget.canInspectFile(limits) else { continue }
        budget.inspectedFiles += 1
        visit(url)
      }
    }
  }

  private func containsScriptFile(in directory: URL) -> Bool {
    var found = false
    var budget = SkillScanBudget()
    walk(directory, depth: 0, budget: &budget) { url in
      if scriptExtensions.contains(url.pathExtension.lowercased()) {
        found = true
      }
    }
    return found
  }

  private func scanTextBundle(skillDirectory: URL, skillMarkdown: URL) -> String {
    var chunks: [String] = []
    var inspectedTextFiles = 0
    var collectedBytes = 0
    let maxTextFiles = min(limits.maxInspectedFiles, 64)
    let maxTotalBytes = min(limits.maxFileBytes * 4, 512 * 1024)
    var budget = SkillScanBudget()

    walk(skillDirectory, depth: 0, budget: &budget) { url in
      guard inspectedTextFiles < maxTextFiles, collectedBytes < maxTotalBytes else { return }
      guard shouldReadTextForSignals(url) else { return }
      let fileSize = Int(DiscoveryUtilities.fileSize(url))
      guard fileSize <= limits.maxFileBytes else { return }
      guard let text = DiscoveryUtilities.readSmallTextFile(url, maxBytes: limits.maxFileBytes)
      else {
        return
      }
      inspectedTextFiles += 1
      collectedBytes += min(fileSize, limits.maxFileBytes)
      let relativeName =
        url == skillMarkdown ? "SKILL.md" : url.lastPathComponent
      chunks.append("\n# \(relativeName)\n\(text)")
    }
    return chunks.joined(separator: "\n")
  }

  private func shouldReadTextForSignals(_ url: URL) -> Bool {
    if url.lastPathComponent == "SKILL.md" { return true }
    if textFileNames.contains(url.lastPathComponent) { return true }
    return textFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func description(from text: String) -> String? {
    for line in text.components(separatedBy: .newlines).prefix(30) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.lowercased().hasPrefix("description:") {
        return String(trimmed.dropFirst("description:".count)).trimmingCharacters(
          in: .whitespacesAndNewlines
        ).trimmedQuotes
      }
      if trimmed.hasPrefix("# ") {
        return String(trimmed.dropFirst(2))
      }
    }
    return nil
  }

  private func directoryHash(_ directory: URL) -> String {
    var seed = ""
    var budget = SkillScanBudget()
    walk(directory, depth: 0, budget: &budget) { url in
      if DiscoveryUtilities.fileSize(url) <= UInt64(limits.maxFileBytes) {
        seed +=
          "\(url.lastPathComponent):\(DiscoveryUtilities.sha256ForFile(url, maxBytes: limits.maxFileBytes));"
      }
    }
    return DiscoveryUtilities.sha256ForString(seed.isEmpty ? directory.path : seed)
  }
}

private struct SkillScanBudget {
  var visitedDirectories = 0
  var inspectedFiles = 0
  var deadline: Date?

  func canVisitDirectory(_ limits: ScanLimits) -> Bool {
    visitedDirectories < limits.maxScannedDirectories && !isExpired
  }

  func canInspectFile(_ limits: ScanLimits) -> Bool {
    inspectedFiles < limits.maxInspectedFiles && !isExpired
  }

  private var isExpired: Bool {
    guard let deadline else { return false }
    return Date() >= deadline
  }
}
