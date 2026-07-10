import Foundation
import NetworkExtension
import Security

struct NetworkFlowSnapshot: Hashable {
  var pid: Int32
  var processName: String
  var protocolName: String
  var localEndpoint: String
  var remoteEndpoint: String
  var remoteAddress: String
  var remotePort: Int?
  var state: String
  var observedAt: Date
  var source: String

  var urlString: String {
    if let remotePort {
      return "\(protocolName.lowercased())://\(remoteAddress):\(remotePort)"
    }
    return "\(protocolName.lowercased())://\(remoteAddress)"
  }
}

final class NetworkFlowMonitor {
  func permissionState() -> DiscoveryPermissionState {
    let entitlement = "com.apple.developer.networking.networkextension" as CFString
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap { SecTaskCopyValueForEntitlement($0, entitlement, nil) }
    let hasEntitlement =
      (value as? Bool) == true || ((value as? [String])?.isEmpty == false)
    return DiscoveryPermissionState(
      id: UUID(),
      capability: .networkExtension,
      status: hasEntitlement ? .available : .missingEntitlement,
      message: hasEntitlement
        ? "Network Extension entitlement is present; flow monitor can attach when configured."
        : "Network Extension entitlement is missing in this development build.",
      checkedAt: Date()
    )
  }

  func flowSnapshotState() -> DiscoveryPermissionState {
    let lsofPath = "/usr/sbin/lsof"
    let isExecutable = FileManager.default.isExecutableFile(atPath: lsofPath)
    return DiscoveryPermissionState(
      id: UUID(),
      capability: .networkFlowSnapshot,
      status: isExecutable ? .available : .failed,
      message: isExecutable
        ? "Lightweight local network flow snapshot is available through lsof; Network Extension entitlement is still required for full flow-detail enforcement."
        : "lsof is unavailable, so lightweight local network flow snapshots cannot run.",
      checkedAt: Date()
    )
  }

  func captureEstablishedTCPFlows(
    forProcessIds processIds: Set<Int32>? = nil,
    limit: Int = 128,
    timeout: TimeInterval = 1.5
  ) -> [NetworkFlowSnapshot] {
    guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof") else { return [] }
    let scopedProcessIds = processIds?
      .filter { $0 > 0 }
      .sorted()
    if let scopedProcessIds, scopedProcessIds.isEmpty {
      return []
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    var arguments = ["-nP", "-iTCP", "-sTCP:ESTABLISHED"]
    if let scopedProcessIds {
      arguments += ["-a", "-p", scopedProcessIds.map(String.init).joined(separator: ",")]
    }
    process.arguments = arguments
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      return []
    }

    let timeoutState = NetworkCommandTimeoutState()
    let timeoutWork = DispatchWorkItem { [weak process, timeoutState] in
      guard let process, process.isRunning else { return }
      timeoutState.markTimedOut()
      process.terminate()
    }
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + min(max(timeout, 0.1), 3), execute: timeoutWork)
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    timeoutWork.cancel()
    process.waitUntilExit()
    guard !timeoutState.didTimeOut, process.terminationStatus == 0 else { return [] }
    let output = String(decoding: data, as: UTF8.self)
    let observedAt = Date()
    return output.components(separatedBy: .newlines)
      .dropFirst()
      .compactMap { Self.parseLsofLine($0, observedAt: observedAt) }
      .filter { flow in
        guard let processIds else { return true }
        return processIds.contains(flow.pid)
      }
      .reduce(into: [String: NetworkFlowSnapshot]()) { partial, flow in
        let key = "\(flow.pid)|\(flow.protocolName)|\(flow.localEndpoint)|\(flow.remoteEndpoint)"
        partial[key] = flow
      }
      .values
      .sorted {
        if $0.pid == $1.pid { return $0.remoteEndpoint < $1.remoteEndpoint }
        return $0.pid < $1.pid
      }
      .prefix(max(0, limit))
      .map { $0 }
  }

  func knownProviderName(for host: String) -> String? {
    let lower = host.lowercased()
    if lower.contains("api.openai.com") { return "OpenAI" }
    if lower.contains("anthropic.com") { return "Anthropic" }
    if lower.contains("generativelanguage.googleapis.com") { return "Gemini" }
    if lower.contains("deepseek.com") { return "DeepSeek" }
    if lower.contains("ollama") || lower.contains("localhost") { return "Ollama" }
    if lower.contains("litellm") { return "LiteLLM" }
    return nil
  }

  private static func parseLsofLine(
    _ line: String,
    observedAt: Date
  ) -> NetworkFlowSnapshot? {
    let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard fields.count >= 9, let pid = Int32(fields[1]) else { return nil }
    let processName = fields[0].replacingOccurrences(of: "\\x20", with: " ")
    let protocolName = fields[7]
    let name = fields.dropFirst(8).joined(separator: " ")
    guard protocolName == "TCP", let arrowRange = name.range(of: "->") else { return nil }
    let state = stateValue(from: name)
    let localEndpoint = String(name[..<arrowRange.lowerBound])
    let remotePart = String(name[arrowRange.upperBound...])
    let remoteEndpoint = remotePart.components(separatedBy: " ").first ?? remotePart
    let parsedRemote = parseEndpoint(remoteEndpoint)
    return NetworkFlowSnapshot(
      pid: pid,
      processName: processName,
      protocolName: protocolName,
      localEndpoint: localEndpoint,
      remoteEndpoint: remoteEndpoint,
      remoteAddress: parsedRemote.address,
      remotePort: parsedRemote.port,
      state: state,
      observedAt: observedAt,
      source: "macos-lsof-network-flow"
    )
  }

  private static func stateValue(from name: String) -> String {
    guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close
    else {
      return "unknown"
    }
    return String(name[name.index(after: open)..<close])
  }

  private static func parseEndpoint(_ endpoint: String) -> (address: String, port: Int?) {
    let trimmed = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if endpoint.hasPrefix("["),
      let bracket = endpoint.lastIndex(of: "]"),
      endpoint.distance(from: bracket, to: endpoint.endIndex) > 2
    {
      let address = String(endpoint[endpoint.index(after: endpoint.startIndex)..<bracket])
      let portStart = endpoint.index(bracket, offsetBy: 2)
      return (address, Int(endpoint[portStart...]))
    }
    guard let colon = trimmed.lastIndex(of: ":") else {
      return (trimmed, nil)
    }
    let address = String(trimmed[..<colon])
    let port = Int(trimmed[trimmed.index(after: colon)...])
    return (address, port)
  }
}

private final class NetworkCommandTimeoutState: @unchecked Sendable {
  private let lock = NSLock()
  private var timedOut = false

  var didTimeOut: Bool {
    lock.lock()
    defer { lock.unlock() }
    return timedOut
  }

  func markTimedOut() {
    lock.lock()
    timedOut = true
    lock.unlock()
  }
}
