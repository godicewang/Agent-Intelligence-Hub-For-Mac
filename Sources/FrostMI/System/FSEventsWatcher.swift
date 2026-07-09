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
  private var targetPaths: [String] = []

  init(callback: @escaping ([FSEventsChange]) -> Void) {
    self.callback = callback
  }

  func start(
    paths: [URL],
    latency: TimeInterval = 1.5,
    useRootFallback: Bool = false
  ) -> DiscoveryPermissionState {
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
    targetPaths = existingPaths.flatMap { path in
      let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
      return [standardized, normalizedDataVolumePath(standardized)]
    }
      .uniqueSorted()
    let streamPaths = useRootFallback ? ["/"] : existingPaths

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
        let relevantChanges = watcher.relevantChanges(changes)
        if ProcessInfo.processInfo.environment["FROSTMI_FSEVENTS_DEBUG"] == "1" {
          let rawPaths = changes.map(\.path.path).joined(separator: ", ")
          let relevantPaths = relevantChanges.map(\.path.path).joined(separator: ", ")
          print("FSEvents debug raw=[\(rawPaths)] relevant=[\(relevantPaths)]")
        }
        watcher.callback(relevantChanges)
      },
      &context,
      streamPaths as CFArray,
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
      message:
        useRootFallback
        ? "FSEvents watcher started in root-filter mode for \(existingPaths.count) target paths."
        : "FSEvents watcher started for \(existingPaths.count) paths.",
      checkedAt: Date()
    )
  }

  func stop() {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    self.stream = nil
    targetPaths = []
  }

  func flushSync() {
    guard let stream else { return }
    FSEventStreamFlushSync(stream)
  }

  deinit {
    stop()
  }

  private func relevantChanges(_ changes: [FSEventsChange]) -> [FSEventsChange] {
    changes.filter { change in
      guard change.flags & UInt32(kFSEventStreamEventFlagHistoryDone) == 0 else {
        return false
      }
      guard !targetPaths.isEmpty else { return true }
      let path = normalizedDataVolumePath(change.path.standardizedFileURL.path)
      return targetPaths.contains { target in
        path == target
          || path.hasPrefix(target + "/")
          || (target.hasPrefix(path.hasSuffix("/") ? path : path + "/") && path != "/")
      }
    }
  }

  private func normalizedDataVolumePath(_ path: String) -> String {
    let dataPrefix = "/System/Volumes/Data"
    guard path.hasPrefix(dataPrefix + "/") else { return path }
    return String(path.dropFirst(dataPrefix.count))
  }
}
