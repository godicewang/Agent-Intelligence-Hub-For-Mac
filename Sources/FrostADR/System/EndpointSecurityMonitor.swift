import EndpointSecurity
import Foundation
import Security

final class EndpointSecurityMonitor {
  func permissionState() -> DiscoveryPermissionState {
    let entitlement = "com.apple.developer.endpoint-security.client" as CFString
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap { SecTaskCopyValueForEntitlement($0, entitlement, nil) }
    let hasEntitlement = (value as? Bool) == true
    return DiscoveryPermissionState(
      id: UUID(),
      capability: .endpointSecurity,
      status: hasEntitlement ? .available : .missingEntitlement,
      message: hasEntitlement
        ? "Endpoint Security entitlement is present; monitor can be initialized by the privileged helper."
        : "Endpoint Security entitlement is missing in this development build.",
      checkedAt: Date()
    )
  }

  func start() -> DiscoveryPermissionState {
    permissionState()
  }
}
