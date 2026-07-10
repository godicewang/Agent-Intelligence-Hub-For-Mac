import Darwin
import Foundation
import Security

final class EndpointSecurityMonitor {
  func permissionState() -> DiscoveryPermissionState {
    let entitlement = "com.apple.developer.endpoint-security.client" as CFString
    let task = SecTaskCreateFromSelf(nil)
    let value = task.flatMap { SecTaskCopyValueForEntitlement($0, entitlement, nil) }
    let hasEntitlement = (value as? Bool) == true
    guard hasEntitlement else {
      return DiscoveryPermissionState(
        id: UUID(),
        capability: .endpointSecurity,
        status: .missingEntitlement,
        message: "Endpoint Security entitlement is missing in this development build.",
        checkedAt: Date()
      )
    }

    let frameworkPath = "/System/Library/Frameworks/EndpointSecurity.framework/EndpointSecurity"
    let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL)
    if let handle {
      dlclose(handle)
    }
    let status: PermissionStatus = handle == nil ? .failed : .available
    let message = handle == nil
      ? "Endpoint Security entitlement is present, but the EndpointSecurity framework could not be loaded by this build environment."
      : "Endpoint Security entitlement and framework are present; auth-event subscription must be started by the privileged helper."

    return DiscoveryPermissionState(
      id: UUID(),
      capability: .endpointSecurity,
      status: status,
      message: message,
      checkedAt: Date()
    )
  }

  func start() -> DiscoveryPermissionState {
    permissionState()
  }
}
