import Foundation

final class FileSystemPermissionInspector {
  func inspect(paths: [URL]) -> [DiscoveryPermissionState] {
    var states: [DiscoveryPermissionState] = []
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
