import CoreServices
import Darwin
import Foundation

/// Gathers change reports and hands them on once per `latency` window (200 ms), so a burst of writes
/// is one refresh.
final class ChangeCoalescer: @unchecked Sendable {
    private let latency: TimeInterval
    private let queue: DispatchQueue
    private let deliver: @Sendable (Set<String>) -> Void
    private let lock = NSLock()
    private var pending: Set<String> = []
    private var scheduled = false
    private var generation = 0

    init(latency: TimeInterval, queue: DispatchQueue, deliver: @escaping @Sendable (Set<String>) -> Void) {
        self.latency = latency
        self.queue = queue
        self.deliver = deliver
    }

    func note(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        lock.lock()
        pending.formUnion(paths)
        let start = !scheduled
        scheduled = true
        let gen = generation
        lock.unlock()
        guard start else { return }
        queue.asyncAfter(deadline: .now() + latency) { [weak self] in self?.flush(gen) }
    }

    /// Drops what is pending (the watched set changed).
    func reset() {
        lock.lock()
        pending = []
        scheduled = false
        generation += 1
        lock.unlock()
    }

    private func flush(_ gen: Int) {
        lock.lock()
        guard gen == generation else { lock.unlock(); return }
        let out = pending
        pending = []
        scheduled = false
        lock.unlock()
        if !out.isEmpty { deliver(out) }
    }
}

/// Auto-refresh for the folders tabs show: a kqueue source on each folder (items added, removed or
/// renamed) and an FSEvents stream of folder events (a file in it written), coalesced. Reports the
/// folders (resolved, as `FilePaths.folderKey`) that changed.
public final class FolderWatcher: @unchecked Sendable {
    private let coalescer: ChangeCoalescer
    private let source = DispatchQueue(label: "folio.watch.events")
    private let lock = NSLock()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var stream: FSEventStreamRef?
    private var watched: Set<String> = []

    public init(latency: TimeInterval = 0.2, queue: DispatchQueue = .main, onChange: @escaping @Sendable (Set<String>) -> Void) {
        coalescer = ChangeCoalescer(latency: latency, queue: queue, deliver: onChange)
    }

    deinit { stop() }

    /// Watches exactly these folders (paths as shown; they are resolved here).
    public func watch(_ folders: Set<String>) {
        let keys = Set(folders.map { FilePaths.folderKey(URL(fileURLWithPath: $0)) })
        lock.lock()
        let same = keys == watched
        lock.unlock()
        if same { return }
        stop()
        coalescer.reset()
        lock.lock()
        watched = keys
        for key in keys { sources[key] = makeSource(key) }
        lock.unlock()
        startStream(Array(keys))
    }

    public func stop() {
        // A change noted just before stopping is not delivered after it.
        coalescer.reset()
        lock.lock()
        let old = sources
        sources = [:]
        watched = []
        let s = stream
        stream = nil
        lock.unlock()
        for (_, src) in old { src.cancel() }
        if let s {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }

    private func makeSource(_ path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link, .attrib],
                                                           queue: source)
        src.setEventHandler { [weak self] in self?.coalescer.note([path]) }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }

    private func startStream(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            me.fileEvents(Array(paths.prefix(count)))
        }
        // Folder-level events: FSEvents names the folder a file changed in (a write into a file names its
        // folder too), not each file, so a tab on a big tree is not sent every write anywhere below it.
        let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          0.05, flags) else { return }
        FSEventStreamSetDispatchQueue(s, source)
        FSEventStreamStart(s)
        lock.lock()
        stream = s
        lock.unlock()
    }

    /// Folders something changed in: the ones that are ours (their subfolders are not listed here; the
    /// folder's own creation or date is the kqueue source's business).
    private func fileEvents(_ paths: [String]) {
        lock.lock()
        let keys = watched
        lock.unlock()
        var hit: Set<String> = []
        for p in paths {
            let folder = p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
            if keys.contains(folder) { hit.insert(folder) }
        }
        if !hit.isEmpty { coalescer.note(hit) }
    }
}

/// The navigation pane's tree: FSEvents over its roots, reporting every folder whose items changed.
public final class TreeWatcher: @unchecked Sendable {
    private let coalescer: ChangeCoalescer
    private let source = DispatchQueue(label: "folio.watch.tree")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var roots: Set<String> = []

    public init(latency: TimeInterval = 0.2, queue: DispatchQueue = .main, onChange: @escaping @Sendable (Set<String>) -> Void) {
        coalescer = ChangeCoalescer(latency: latency, queue: queue, deliver: onChange)
    }

    deinit { stop() }

    public func watch(roots paths: Set<String>) {
        let keys = Set(paths.map { FilePaths.folderKey(URL(fileURLWithPath: $0)) })
        lock.lock()
        let same = keys == roots
        lock.unlock()
        if same { return }
        stop()
        lock.lock()
        roots = keys
        lock.unlock()
        guard !keys.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let me = Unmanaged<TreeWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            me.coalescer.note(Set(paths.prefix(count).map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, Array(keys) as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags) else { return }
        FSEventStreamSetDispatchQueue(s, source)
        FSEventStreamStart(s)
        lock.lock()
        stream = s
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let s = stream
        stream = nil
        roots = []
        lock.unlock()
        coalescer.reset()
        if let s {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
