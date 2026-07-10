import Foundation

enum RuntimePlatformSelfTests {
  static func runNetworkFlowSelfTest() -> Int32 {
    let monitor = NetworkFlowMonitor()
    let state = monitor.flowSnapshotState()
    guard state.status == .available else {
      print("Network flow self-test failed: \(state.message)")
      return 1
    }
    let flows = monitor.captureEstablishedTCPFlows(limit: 16)
    guard !flows.isEmpty else {
      print("Network flow self-test failed: no established TCP flows were visible to lsof.")
      return 1
    }
    let sample = flows.prefix(3).map {
      "\($0.processName)[\($0.pid)]->\($0.remoteEndpoint)"
    }.joined(separator: ",")
    print(
      "Network flow self-test passed: flows=\(flows.count) source=macos-lsof-network-flow sample=\(sample)"
    )
    return 0
  }

  static func runEndpointSecuritySelfTest() -> Int32 {
    let state = EndpointSecurityMonitor().start()
    switch state.status {
    case .available:
      print("Endpoint Security self-test passed: \(state.message)")
      return 0
    case .missingEntitlement:
      print("Endpoint Security self-test passed: \(state.message)")
      return 0
    default:
      print("Endpoint Security self-test failed: \(state.message)")
      return 1
    }
  }
}
