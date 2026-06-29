import SwiftUI

enum FrostRoute: String, CaseIterable, Identifiable, Hashable {
  case agentScan

  var id: String { rawValue }

  var title: String {
    switch self {
    case .agentScan:
      "Agent Scan"
    }
  }

  var shortTitle: String {
    switch self {
    case .agentScan:
      "Agent Scan"
    }
  }

  var systemImage: String {
    switch self {
    case .agentScan:
      "scope"
    }
  }

  @MainActor
  @ViewBuilder
  var destination: some View {
    switch self {
    case .agentScan:
      AgentScanView()
    }
  }
}
