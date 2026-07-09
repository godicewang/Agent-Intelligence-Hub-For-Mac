import CoreServices
import Foundation

struct FSEventsChange: Hashable {
  var path: URL
  var eventId: UInt64
  var flags: UInt32
  var observedAt: Date

  var flagSummary: String {
    var values: [String] = []
    if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
      values.append("created")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
      values.append("modified")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
      values.append("removed")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
      values.append("renamed")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
      values.append("directory")
    }
    if flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 {
      values.append("file")
    }
    return values.isEmpty ? "changed" : values.joined(separator: ",")
  }
}

final class FSEventsWatcher {
  private var stream: FSEventStreamRef?
  private let queue = DispatchQueue(label: "frostadr.fsevents")
  private let callback: ([FSEventsChange]) -> Void

  init(callback: @escaping ([FSEventsChange]) -> Void) {
    self.callback = callback
  }

  func start(paths: [URL], latency: TimeInterval = 1.5) -> DiscoveryPermissionState {
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
      { _, info, numberOfEvents, eventPaths, eventFlags, eventIds in
        guard let info else { return }
        let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = eventPaths.bindMemory(to: UnsafePointer<CChar>.self, capacity: numberOfEvents)
        let now = Date()
        let changes = (0..<numberOfEvents).compactMap { index -> FSEventsChange? in
          return FSEventsChange(
            path: URL(fileURLWithPath: String(cString: paths[index])).standardizedFileURL,
            eventId: UInt64(eventIds[index]),
            flags: UInt32(eventFlags[index]),
            observedAt: now
          )
        }
        watcher.callback(changes)
      },
      &context,
      existingPaths as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      latency,
      FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
      )
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
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      return DiscoveryPermissionState(
        id: UUID(),
        capability: .fileSystemEvents,
        status: .failed,
        message: "FSEvents stream failed to start.",
        checkedAt: Date()
      )
    }
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
