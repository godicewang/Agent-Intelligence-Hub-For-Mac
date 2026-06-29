import Foundation

final class FileSystemPermissionInspector {
  func inspect(paths: [URL]) -> [DiscoveryPermissionState] {
    var states: [DiscoveryPermissionState] = []
    let protectedProbe = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("Messages")

    let fullDiskStatus: PermissionStatus
    if FileManager.default.isReadableFile(atPath: protectedProbe.path) {
      fullDiskStatus = .available
    } else {
      fullDiskStatus = .restricted
    }
    states.append(
      DiscoveryPermissionState(
        id: UUID(),
        capability: .fullDiskAccess,
        status: fullDiskStatus,
        message: fullDiskStatus == .available
          ? "Protected user data directories appear readable."
          : "Full Disk Access may be required for complete cache/session discovery.",
        checkedAt: Date()
      ))

    for path in paths
    where DiscoveryUtilities.directoryExists(path)
      && !FileManager.default.isReadableFile(atPath: path.path)
    {
      states.append(
        DiscoveryPermissionState(
          id: UUID(),
          capability: .fullDiskAccess,
          status: .restricted,
          message: "Directory is not readable: \(path.path)",
          checkedAt: Date()
        ))
    }
    return states
  }
}
