import CoreServices
import Foundation

final class FSEventsWatcher {
  private var stream: FSEventStreamRef?
  private let queue = DispatchQueue(label: "frostadr.fsevents")
  private let callback: ([URL]) -> Void

  init(callback: @escaping ([URL]) -> Void) {
    self.callback = callback
  }

  func start(paths: [URL]) -> DiscoveryPermissionState {
    stop()
    let existingPaths = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
    guard !existingPaths.isEmpty else {
      return DiscoveryPermissionState(
        id: UUID(),
        capability: .fileSystemEvents,
        status: .notConfigured,
        message: "No existing discovery paths are available for FSEvents.",
        checkedAt: Date()
      )
    }

    let retainedSelf = Unmanaged.passUnretained(self).toOpaque()
    var context = FSEventStreamContext(
      version: 0,
      info: retainedSelf,
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      { _, info, numberOfEvents, eventPaths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        watcher.callback(paths.prefix(numberOfEvents).map(URL.init(fileURLWithPath:)))
      },
      &context,
      existingPaths as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.5,
      FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
    )

    guard let stream else {
      return DiscoveryPermissionState(
        id: UUID(),
        capability: .fileSystemEvents,
        status: .failed,
        message: "FSEvents stream creation failed.",
        checkedAt: Date()
      )
    }

    FSEventStreamSetDispatchQueue(stream, queue)
    FSEventStreamStart(stream)
    return DiscoveryPermissionState(
      id: UUID(),
      capability: .fileSystemEvents,
      status: .available,
      message: "FSEvents watcher started for \(existingPaths.count) paths.",
      checkedAt: Date()
    )
  }

  func stop() {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
  }

  deinit {
    stop()
  }
}
