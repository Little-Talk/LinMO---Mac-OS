import CoreServices
import Foundation

final class SharedFolderWatcher {
    private let root: String
    private let queue = DispatchQueue(label: "linmo.shared-folder-watcher")
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    static let batchLimit = 2000

    init?(path: String, onChange: @escaping ([String]) -> Void) {
        guard let real = realpath(path, nil) else { return nil }
        let resolved = String(cString: real)
        free(real)
        self.root = resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<SharedFolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            watcher.receive((0..<count).compactMap { list[$0] as? String })
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    private func receive(_ paths: [String]) {
        let prefix = root + "/"
        var seen = Set<String>()
        var relative: [String] = []
        for path in paths where path.hasPrefix(prefix) {
            let rel = String(path.dropFirst(prefix.count))
            if !rel.isEmpty, seen.insert(rel).inserted {
                relative.append(rel)
            }
        }
        guard !relative.isEmpty else { return }
        if relative.count > Self.batchLimit {
            relative = Array(relative.sorted {
                let a = $0.split(separator: "/").count, b = $1.split(separator: "/").count
                return a == b ? $0 < $1 : a < b
            }.prefix(Self.batchLimit))
        }
        onChange(relative)
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        queue.sync {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    deinit { stop() }
}
