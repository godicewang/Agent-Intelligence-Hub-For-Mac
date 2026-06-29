import Foundation

final class MCPConfigParser {
  func parse(url: URL, sourceAgentId: UUID? = nil, workspacePath: String? = nil) -> [MCPServerAsset]
  {
    let ext = url.pathExtension.lowercased()
    if ext == "toml" {
      return parseTOML(url: url, sourceAgentId: sourceAgentId, workspacePath: workspacePath)
    }
    return parseJSON(url: url, sourceAgentId: sourceAgentId, workspacePath: workspacePath)
  }

  func parseJSON(url: URL, sourceAgentId: UUID? = nil, workspacePath: String? = nil)
    -> [MCPServerAsset]
  {
    guard
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return []
    }

    var servers: [MCPServerAsset] = []
    for serverMap in recursiveMCPServerMaps(in: object) {
      for (name, rawConfig) in serverMap {
        guard let config = rawConfig as? [String: Any] else { continue }
        servers.append(
          asset(
            name: name, config: config, configURL: url, sourceAgentId: sourceAgentId,
            workspacePath: workspacePath))
      }
    }
    return servers
  }

  func parseTOML(url: URL, sourceAgentId: UUID? = nil, workspacePath: String? = nil)
    -> [MCPServerAsset]
  {
    guard let text = DiscoveryUtilities.readSmallTextFile(url, maxBytes: 512 * 1024) else {
      return []
    }

    var currentName: String?
    var configs: [String: [String: Any]] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        let section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if section.hasPrefix("mcp_servers.") || section.hasPrefix("mcpServers.") {
          currentName = section.components(separatedBy: ".").dropFirst().joined(separator: ".")
          configs[currentName ?? ""] = configs[currentName ?? ""] ?? [:]
        } else {
          currentName = nil
        }
        continue
      }

      guard let currentName, let separator = line.firstIndex(of: "=") else { continue }
      let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = line[line.index(after: separator)...].trimmingCharacters(
        in: .whitespacesAndNewlines)
      configs[currentName, default: [:]][key] = parseTOMLValue(value)
    }

    return configs.map { name, config in
      asset(
        name: name, config: config, configURL: url, sourceAgentId: sourceAgentId,
        workspacePath: workspacePath)
    }
  }

  private func recursiveMCPServerMaps(in object: Any) -> [[String: Any]] {
    if let dict = object as? [String: Any] {
      var matches: [[String: Any]] = []
      for (key, value) in dict {
        if ["mcpServers", "mcp_servers", "servers"].contains(key),
          let servers = value as? [String: Any]
        {
          matches.append(servers)
        } else {
          matches.append(contentsOf: recursiveMCPServerMaps(in: value))
        }
      }
      return matches
    }
    if let array = object as? [Any] {
      return array.flatMap { recursiveMCPServerMaps(in: $0) }
    }
    return []
  }

  private func asset(
    name: String,
    config: [String: Any],
    configURL: URL,
    sourceAgentId: UUID?,
    workspacePath: String?
  ) -> MCPServerAsset {
    let command = config["command"] as? String
    let args = (config["args"] as? [String] ?? []).map(DiscoveryUtilities.sanitizeArgument)
    let envKeys = DiscoveryUtilities.envKeyNames(from: config["env"])
    let transport = transport(from: config)
    let risk = risk(command: command, args: args, envKeyNames: envKeys)
    let hashSeed =
      "\(name)|\(command ?? "")|\(args.joined(separator: " "))|\(envKeys.joined(separator: ","))|\(DiscoveryUtilities.sha256ForFile(configURL))"

    return MCPServerAsset(
      name: name,
      sourceAgentId: sourceAgentId,
      transport: transport,
      configPath: configURL.path,
      command: command,
      args: args,
      envKeyNames: envKeys,
      scope: DiscoveryUtilities.inferredScope(for: configURL),
      workspacePath: workspacePath,
      manifestHash: DiscoveryUtilities.sha256ForString(hashSeed),
      inspectionStatus: inspectionStatus(for: risk),
      riskPreScore: risk,
      riskLevel: DiscoveryUtilities.riskLevel(for: risk),
      lastModifiedAt: DiscoveryUtilities.modificationDate(configURL)
    )
  }

  private func transport(from config: [String: Any]) -> MCPTransport {
    let raw = ((config["transport"] ?? config["type"]) as? String)?.lowercased()
    if raw == "sse" { return .sse }
    if raw == "http" { return .http }
    if raw == "streamable-http" || raw == "streamable_http" { return .streamableHttp }
    if config["url"] != nil { return .http }
    if config["command"] != nil { return .stdio }
    return .unknown
  }

  private func risk(command: String?, args: [String], envKeyNames: [String]) -> Int {
    let joined = ([command ?? ""] + args).joined(separator: " ").lowercased()
    var score = 0
    if command == "npx", !args.contains(where: { $0.contains("@") }) { score += 30 }
    if command == "uvx" { score += 25 }
    if joined.contains("curl") && joined.contains("bash") { score += 45 }
    if joined.contains("python -c") || joined.contains("node -e") { score += 30 }
    if joined.contains("osascript") { score += 35 }
    if joined.contains("chmod +x") { score += 20 }
    if joined.contains("base64") && (joined.contains("-d") || joined.contains("--decode")) {
      score += 30
    }
    if joined.contains("~/.ssh") || joined.contains("/.ssh") || joined.contains(" .env") {
      score += 35
    }
    if args.contains(where: { ["/", "~", "~/Library", "~/.ssh"].contains($0) }) { score += 15 }
    if envKeyNames.contains(where: {
      $0.range(of: DiscoveryUtilities.sensitiveKeyPattern, options: .regularExpression) != nil
    }) {
      score += 20
    }
    if let command, command.contains("/"), !command.hasPrefix("/usr/bin/"),
      !command.hasPrefix("/bin/"), !command.hasPrefix("/opt/homebrew/")
    {
      score += 10
    }
    return min(score, 100)
  }

  private func inspectionStatus(for risk: Int) -> MCPInspectionStatus {
    if risk >= 60 { return .blockedUntilApproved }
    if risk > 0 { return .preScanned }
    return .noExecDiscovered
  }

  private func parseTOMLValue(_ value: String) -> Any {
    if value.hasPrefix("[") && value.hasSuffix("]") {
      return value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmedQuotes }
    }
    if value.hasPrefix("{") && value.hasSuffix("}") {
      var dict: [String: String] = [:]
      let body = value.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
      for pair in body.split(separator: ",") {
        let parts = pair.split(separator: "=", maxSplits: 1).map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if parts.count == 2 {
          dict[parts[0].trimmedQuotes] = parts[1].trimmedQuotes
        }
      }
      return dict
    }
    return value.trimmedQuotes
  }
}
