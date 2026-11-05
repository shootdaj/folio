import Darwin
import Foundation

public enum JobKind: String, Sendable { case copy, move }

public enum JobState: String, Sendable, Equatable {
    case preparing, running, paused, waitingOnConflict, waitingOnProblem, done, cancelled

    public var isFinished: Bool { self == .done || self == .cancelled }
}

/// Name, kind, size and date of one side of a conflict.
public struct ItemFacts: Sendable, Equatable {
    public let name: String
    public let isFolder: Bool
    public let size: Int64?
    public let modified: Date?

    public static func read(_ url: URL) -> ItemFacts {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            return ItemFacts(name: url.lastPathComponent, isFolder: false, size: nil, modified: nil)
        }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let t = st.st_mtimespec
        return ItemFacts(name: url.lastPathComponent, isFolder: isDir,
                         size: (st.st_mode & S_IFMT) == S_IFREG ? Int64(st.st_size) : nil,
                         modified: Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_nsec) / 1e9))
    }
}

/// An incoming item whose name is taken in the destination. The job waits for a decision.
public struct FileConflict: Sendable, Equatable, Identifiable {
    public let id: Int
    public let source: URL
    public let destination: URL
    public let existing: ItemFacts
    public let incoming: ItemFacts

    public var incomingIsNewer: Bool {
        (incoming.modified ?? .distantPast).timeIntervalSince(existing.modified ?? .distantPast) > 1
    }

    /// Positive when the incoming file is larger.
    public var sizeDelta: Int64 { (incoming.size ?? 0) - (existing.size ?? 0) }

    /// Two files with the same size and date (to within 2 s): Explorer's "skip identical files".
    public var isIdentical: Bool {
        guard !existing.isFolder, !incoming.isFolder, existing.size == incoming.size,
              let a = existing.modified, let b = incoming.modified else { return false }
        return abs(a.timeIntervalSince(b)) < 2
    }
}

public enum ConflictDecision: String, Sendable, Equatable { case replace, skip, keepBoth }

/// Something that stopped one item (access denied, the item vanished). Try again, Skip or Cancel.
public struct JobProblem: Sendable, Equatable, Identifiable {
    public let id: Int
    public let url: URL
    public let message: String
    public let canRetry: Bool
}

public enum ProblemDecision: Sendable, Equatable { case retry, skip, cancel }

public struct JobOptions: Sendable {
    public var trash: any Trasher = SystemTrash()
    /// Bytes per second; nil copies at full speed.
    public var throttle: Int64?
    /// Skip conflicts where both files have the same size and date.
    public var skipIdentical = false
    /// Answers every conflict without asking (tests, and "do this for all" set up front).
    public var conflictPolicy: ConflictDecision?
    /// Answers every problem without asking.
    public var problemPolicy: ProblemDecision?
    /// Same-volume moves rename in place. Off, a move copies and then deletes, as across volumes.
    public var allowRename = true
    /// APFS clones make same-volume copies instant. Off with a throttle.
    public var allowClone = true

    public init() {}

    /// `FOLIO_SLOW_COPY=1` copies at 40 MB/s with no clones, so the VM test can watch the progress
    /// window. Only the test scripts set it.
    public static func fromEnvironment(_ env: [String: String]) -> JobOptions {
        var o = JobOptions()
        if env["FOLIO_SLOW_COPY"] == "1" {
            o.throttle = 40_000_000
            o.allowClone = false
        }
        return o
    }
}

/// What the progress window shows for one job.
public struct JobSnapshot: Sendable, Equatable {
    public let id: Int
    public let kind: JobKind
    public let state: JobState
    public let sources: [URL]
    public let destination: URL
    public let bytesDone: Int64
    public let bytesTotal: Int64
    public let itemsDone: Int
    public let itemsTotal: Int
    public let currentName: String?
    /// Bytes per second over the last second; 0 while paused or waiting.
    public let speed: Double
    public let secondsLeft: Double?
    public let conflict: FileConflict?
    /// Conflicts still to decide, the shown one included.
    public let conflictsLeft: Int
    public let problem: JobProblem?
    public let skipped: Int
    public let skipIdentical: Bool

    public var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal))
            : itemsTotal > 0 ? min(1, Double(itemsDone) / Double(itemsTotal)) : (state == .done ? 1 : 0)
    }
}

public struct JobResult: Sendable, Equatable {
    public let state: JobState
    /// nil when nothing changed (everything skipped).
    public let record: OperationRecord?
    /// The top-level items now in the destination, to select after a paste.
    public let placed: [URL]
    public let skipped: Int
}

/// One copy or move, run on its own thread: it measures the sources, moves everything that has no
/// clash, merges same-named folders, then asks about each clash (Explorer defers them to the end),
/// and can be paused, resumed and cancelled. A cancelled job leaves only whole files behind.
public final class FileJob: @unchecked Sendable {
    public let id: Int
    public let kind: JobKind
    public let sources: [URL]
    public let destination: URL
    private let options: JobOptions

    /// Called on the job's thread after a state change (not on every byte; poll `snapshot()` for that).
    public var onChange: (@Sendable (FileJob) -> Void)?

    private struct Cancelled: Error {}
    private struct Pending { let src: URL; let dst: URL; let top: Bool }

    private let cond = NSCondition()
    // Guarded by `cond`.
    private var state: JobState = .preparing
    private var pauseRequested = false
    private var cancelRequested = false
    private var bytesDone: Int64 = 0, bytesTotal: Int64 = 0
    private var itemsDone = 0, itemsTotal = 0
    private var currentName: String?
    private var meter = SpeedMeter()
    private var conflict: FileConflict?
    private var conflictsLeft = 0
    private var decision: (ConflictDecision, Bool)?
    private var problem: JobProblem?
    private var problemAnswer: ProblemDecision?
    private var applyToAll: ConflictDecision?
    private var skipIdentical: Bool
    private var skipped = 0
    private var finalResult: JobResult?
    private var waiters: [CheckedContinuation<JobResult, Never>] = []
    private var throttleStart = 0.0
    private var throttleBytes: Int64 = 0

    // Only touched on the job's thread.
    private var copied: [Pair] = [], moved: [Pair] = []
    private var createdFolders: [URL] = [], removedFolders: [URL] = []
    private var replaced: [TrashedItem] = []
    private var placed: [URL] = []
    private var mergedSources: [URL] = []
    private var queue: [Pending] = []
    private var nextID = 1

    private static let idLock = NSLock()
    nonisolated(unsafe) private static var lastID = 0

    public init(kind: JobKind, sources: [URL], into destination: URL, options: JobOptions = JobOptions()) {
        Self.idLock.lock()
        Self.lastID += 1
        id = Self.lastID
        Self.idLock.unlock()
        self.kind = kind
        self.sources = sources
        self.destination = destination
        self.options = options
        skipIdentical = options.skipIdentical
    }

    // MARK: Control

    public func start() {
        let thread = Thread { [self] in main() }
        thread.qualityOfService = .userInitiated
        thread.name = "Folio \(kind.rawValue) job \(id)"
        thread.start()
    }

    /// Starts the job and waits for it to finish.
    public func run() async -> JobResult {
        start()
        return await finished()
    }

    public func finished() async -> JobResult {
        await withCheckedContinuation { (c: CheckedContinuation<JobResult, Never>) in
            cond.lock()
            if let r = finalResult {
                cond.unlock()
                c.resume(returning: r)
            } else {
                waiters.append(c)
                cond.unlock()
            }
        }
    }

    public func pause() {
        locked {
            guard !state.isFinished else { return }
            pauseRequested = true
            if state == .running { state = .paused }
        }
        notify()
    }

    public func resume() {
        locked {
            pauseRequested = false
            if state == .paused { state = .running }
            restartClocks()
            cond.broadcast()
        }
        notify()
    }

    public func cancel() {
        locked {
            cancelRequested = true
            cond.broadcast()
        }
    }

    /// Answers the shown conflict; `applyToAll` is "Do this for the next N conflicts".
    public func resolve(_ d: ConflictDecision, applyToAll all: Bool = false) {
        locked {
            guard state == .waitingOnConflict else { return }
            decision = (d, all)
            cond.broadcast()
        }
    }

    /// "Skip N files with the same date and size"; skips the shown conflict too if it is one.
    public func setSkipIdentical(_ on: Bool) {
        locked {
            skipIdentical = on
            if on, state == .waitingOnConflict, conflict?.isIdentical == true {
                decision = (.skip, false)
                cond.broadcast()
            }
        }
        notify()
    }

    public func answer(_ d: ProblemDecision) {
        locked {
            guard state == .waitingOnProblem else { return }
            problemAnswer = d
            cond.broadcast()
        }
    }

    public func snapshot() -> JobSnapshot {
        cond.lock()
        defer { cond.unlock() }
        let now = Self.now()
        let speed = state == .running ? meter.bytesPerSecond(at: now) : 0
        let left: Double? = speed > 0 ? Double(max(0, bytesTotal - bytesDone)) / speed : nil
        return JobSnapshot(id: id, kind: kind, state: state, sources: sources, destination: destination,
                           bytesDone: bytesDone, bytesTotal: bytesTotal, itemsDone: itemsDone, itemsTotal: itemsTotal,
                           currentName: currentName, speed: speed, secondsLeft: left, conflict: conflict,
                           conflictsLeft: conflictsLeft, problem: problem, skipped: skipped, skipIdentical: skipIdentical)
    }

    // MARK: The run

    private func main() {
        var end = JobState.done
        do {
            prepare()
            locked {
                if state == .preparing { state = pauseRequested ? .paused : .running }
                restartClocks()
            }
            notify()
            for src in sources {
                try checkpoint()
                try handleTop(src)
            }
            try resolveQueue()
        } catch {
            end = .cancelled
        }
        if kind == .move { removeEmptiedSources() }
        finish(end)
    }

    private func prepare() {
        var n = 0
        var b: Int64 = 0
        for src in sources {
            let m = Self.measure(src)
            n += m.items
            b += m.bytes
        }
        locked {
            itemsTotal = n
            bytesTotal = b
        }
    }

    private func handleTop(_ src: URL) throws {
        let name = src.lastPathComponent
        guard Self.kind(src) != .missing else {
            _ = try ask(JobProblem(id: takeID(), url: src, message: "\(name) is no longer there.", canRetry: false))
            countSkip(items: 0, bytes: 0)
            return
        }
        if Self.same(src.deletingLastPathComponent(), destination) {
            if kind == .move {
                // Moving an item into the folder it is in changes nothing.
                let m = Self.measure(src)
                add(items: m.items, bytes: m.bytes)
                return
            }
            let copyName = FileNaming.copyName(for: name, isFolder: Self.kind(src) == .folder) {
                Self.kind(self.destination.appendingPathComponent($0)) != .missing
            }
            try transfer(src, to: destination.appendingPathComponent(copyName), top: true)
            return
        }
        if Self.kind(src) == .folder || Self.kind(src) == .package, Self.inside(destination, src) {
            let d = try ask(JobProblem(id: takeID(), url: src,
                                       message: "The destination folder is inside \(name).", canRetry: false))
            if d == .cancel { throw Cancelled() }
            skip(src)
            return
        }
        try place(src, at: destination.appendingPathComponent(name), top: true)
    }

    /// Puts `src` at `dst`: straight there when the name is free, merged when both are folders,
    /// queued for a decision otherwise.
    private func place(_ src: URL, at dst: URL, top: Bool) throws {
        let dk = Self.kind(dst)
        if dk == .missing {
            try transfer(src, to: dst, top: top)
            return
        }
        if Self.kind(src) == .folder, dk == .folder {
            add(items: 1, bytes: 0)
            if top { placed.append(dst) }
            if kind == .move { mergedSources.append(src) }
            for child in Self.children(src) {
                try checkpoint()
                try place(child, at: dst.appendingPathComponent(child.lastPathComponent), top: false)
            }
            return
        }
        queue.append(Pending(src: src, dst: dst, top: top))
    }

    /// Copies or moves `src` to `dst`, which must not exist yet.
    private func transfer(_ src: URL, to dst: URL, top: Bool) throws {
        let done: Bool
        switch kind {
        case .copy:
            copied.append(Pair(from: src, to: dst))
            do {
                done = try attempt(src) {
                    do { try self.copyTree(src, dst) } catch {
                        if !(error is Cancelled) { try? FileManager.default.removeItem(at: dst) }
                        throw error
                    }
                }
            } catch {
                // Cancelled in the middle of a file: its partial copy is gone, so is the record of it.
                if Self.kind(dst) == .missing { copied.removeLast() }
                throw error
            }
            if !done { copied.removeLast(); skip(src) }
        case .move:
            done = try attempt(src) { try self.moveTree(src, dst) }
            if !done { skip(src) }
        }
        if done && top { placed.append(dst) }
    }

    private func resolveQueue() throws {
        var i = 0
        while i < queue.count {
            try checkpoint()
            let p = queue[i]
            i += 1
            guard Self.kind(p.src) != .missing else { countSkip(items: 0, bytes: 0); continue }
            let c = FileConflict(id: takeID(), source: p.src, destination: p.dst,
                                 existing: ItemFacts.read(p.dst), incoming: ItemFacts.read(p.src))
            switch try decide(c, left: queue.count - i + 1) {
            case .skip:
                skip(p.src)
            case .replace:
                let trashed = try attempt(p.dst) {
                    let t = try self.options.trash.trash(p.dst)
                    self.replaced.append(TrashedItem(original: p.dst, inTrash: t))
                }
                if trashed { try transfer(p.src, to: p.dst, top: p.top) } else { skip(p.src) }
            case .keepBoth:
                let parent = p.dst.deletingLastPathComponent()
                let name = FileNaming.keepBothName(for: p.dst.lastPathComponent, isFolder: Self.kind(p.src) == .folder) {
                    Self.kind(parent.appendingPathComponent($0)) != .missing
                }
                try transfer(p.src, to: parent.appendingPathComponent(name), top: p.top)
            }
        }
    }

    private func decide(_ c: FileConflict, left: Int) throws -> ConflictDecision {
        cond.lock()
        if skipIdentical && c.isIdentical { cond.unlock(); return .skip }
        if let p = options.conflictPolicy ?? applyToAll { cond.unlock(); return p }
        state = .waitingOnConflict
        conflict = c
        conflictsLeft = left
        decision = nil
        cond.unlock()
        notify()
        cond.lock()
        while decision == nil && !cancelRequested { cond.wait() }
        let answer = decision
        conflict = nil
        conflictsLeft = max(0, left - 1)
        state = pauseRequested ? .paused : .running
        restartClocks()
        cond.unlock()
        notify()
        guard let answer, !isCancelled else { throw Cancelled() }
        if answer.1 { locked { applyToAll = answer.0 } }
        return answer.0
    }

    private func ask(_ p: JobProblem) throws -> ProblemDecision {
        if let policy = options.problemPolicy {
            if policy == .cancel { throw Cancelled() }
            return p.canRetry || policy != .retry ? policy : .skip
        }
        locked {
            state = .waitingOnProblem
            problem = p
            problemAnswer = nil
        }
        notify()
        cond.lock()
        while problemAnswer == nil && !cancelRequested { cond.wait() }
        let answer = problemAnswer
        problem = nil
        state = pauseRequested ? .paused : .running
        restartClocks()
        cond.unlock()
        notify()
        guard let answer, answer != .cancel, !isCancelled else { throw Cancelled() }
        return answer
    }

    /// Runs `body`; on an error asks Try again, Skip or Cancel. False when the item was skipped.
    private func attempt(_ url: URL, _ body: () throws -> Void) throws -> Bool {
        while true {
            do {
                try body()
                return true
            } catch let c as Cancelled {
                throw c
            } catch {
                let d = try ask(JobProblem(id: takeID(), url: url, message: Self.describe(error, url), canRetry: true))
                if d == .skip { return false }
            }
        }
    }

    // MARK: Copying

    private func copyTree(_ src: URL, _ dst: URL) throws {
        switch Self.kind(src) {
        case .folder, .package:
            try Self.makeFolder(dst, like: src)
            add(items: 1, bytes: 0)
            for child in Self.children(src) {
                try checkpoint()
                try copyTree(child, dst.appendingPathComponent(child.lastPathComponent))
            }
            Self.copyFolderDates(src, dst)
        case .file:
            locked { currentName = src.lastPathComponent }
            try copyFile(src, dst)
            add(items: 1, bytes: 0)
        case .link:
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: src.path)
            try FileManager.default.createSymbolicLink(atPath: dst.path, withDestinationPath: target)
            add(items: 1, bytes: 0)
        case .missing:
            throw FileOpError.missing(src.lastPathComponent)
        }
    }

    /// Clones when it can; otherwise copies in chunks (pause, cancel and the throttle act between
    /// chunks), then the metadata. A copy that stops removes its partial file.
    private func copyFile(_ src: URL, _ dst: URL) throws {
        if options.allowClone && options.throttle == nil {
            if clonefile(src.path, dst.path, 0) == 0 {
                add(items: 0, bytes: Self.measure(src).bytes)
                return
            }
            if errno != EXDEV && errno != ENOTSUP && errno != EPERM { throw FileOpError.posix(errno, dst) }
        }
        let input = open(src.path, O_RDONLY)
        guard input >= 0 else { throw FileOpError.posix(errno, src) }
        defer { close(input) }
        var st = stat()
        fstat(input, &st)
        let output = open(dst.path, O_WRONLY | O_CREAT | O_EXCL, st.st_mode & 0o7777)
        guard output >= 0 else { throw FileOpError.posix(errno, dst) }
        let chunk = options.throttle.map { Int(max(64 * 1024, min(1 << 20, $0 / 20))) } ?? (1 << 20)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var written: Int64 = 0
        do {
            while true {
                try checkpoint()
                let n = read(input, buffer, chunk)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw FileOpError.posix(errno, src)
                }
                if n == 0 { break }
                var off = 0
                while off < n {
                    let w = write(output, buffer + off, n - off)
                    if w < 0 {
                        if errno == EINTR { continue }
                        throw FileOpError.posix(errno, dst)
                    }
                    off += w
                }
                written += Int64(n)
                add(items: 0, bytes: Int64(n))
                try throttle(Int64(n))
            }
        } catch {
            close(output)
            unlink(dst.path)
            add(items: 0, bytes: -written)
            throw error
        }
        close(output)
        copyfile(src.path, dst.path, nil, copyfile_flags_t(COPYFILE_METADATA))
    }

    // MARK: Moving

    private func moveTree(_ src: URL, _ dst: URL) throws {
        if options.allowRename {
            let m = Self.measure(src)
            if renamex_np(src.path, dst.path, UInt32(RENAME_EXCL)) == 0 {
                moved.append(Pair(from: src, to: dst))
                add(items: m.items, bytes: m.bytes)
                return
            }
            if errno != EXDEV { throw FileOpError.posix(errno, src) }
        }
        try crossMove(src, dst)
    }

    /// Across volumes: file by file, each copied and then deleted, so a cancel leaves every file in
    /// exactly one place.
    private func crossMove(_ src: URL, _ dst: URL) throws {
        switch Self.kind(src) {
        case .folder, .package:
            if Self.kind(dst) == .missing {
                try Self.makeFolder(dst, like: src)
                createdFolders.append(dst)
            }
            add(items: 1, bytes: 0)
            for child in Self.children(src) {
                try checkpoint()
                try crossMove(child, dst.appendingPathComponent(child.lastPathComponent))
            }
            Self.copyFolderDates(src, dst)
            if rmdir(src.path) == 0 { removedFolders.append(src) }
        case .file:
            locked { currentName = src.lastPathComponent }
            try copyFile(src, dst)
            if unlink(src.path) != 0 { throw FileOpError.posix(errno, src) }
            moved.append(Pair(from: src, to: dst))
            add(items: 1, bytes: 0)
        case .link:
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: src.path)
            try FileManager.default.createSymbolicLink(atPath: dst.path, withDestinationPath: target)
            unlink(src.path)
            moved.append(Pair(from: src, to: dst))
            add(items: 1, bytes: 0)
        case .missing:
            throw FileOpError.missing(src.lastPathComponent)
        }
    }

    /// Source folders a merge emptied go away, deepest first.
    private func removeEmptiedSources() {
        for folder in mergedSources.reversed() where rmdir(folder.path) == 0 {
            removedFolders.append(folder)
        }
    }

    // MARK: Bookkeeping

    private func finish(_ end: JobState) {
        let record: OperationRecord?
        switch kind {
        case .copy:
            record = copied.isEmpty && replaced.isEmpty ? nil : .copy(copied: copied, replaced: replaced)
        case .move:
            record = moved.isEmpty && replaced.isEmpty && createdFolders.isEmpty ? nil
                : .move(moved: moved, createdFolders: createdFolders, removedFolders: removedFolders, replaced: replaced)
        }
        cond.lock()
        let result = JobResult(state: end, record: record, placed: placed, skipped: skipped)
        state = end
        currentName = nil
        conflict = nil
        problem = nil
        finalResult = result
        let pending = waiters
        waiters = []
        cond.unlock()
        for w in pending { w.resume(returning: result) }
        notify()
    }

    private func checkpoint() throws {
        cond.lock()
        defer { cond.unlock() }
        if cancelRequested { throw Cancelled() }
        guard pauseRequested else { return }
        state = .paused
        cond.unlock()
        notify()
        cond.lock()
        while pauseRequested && !cancelRequested { cond.wait() }
        if cancelRequested { throw Cancelled() }
        state = .running
    }

    private func throttle(_ n: Int64) throws {
        guard let rate = options.throttle, rate > 0 else { return }
        locked { throttleBytes += n }
        while true {
            // A resume restarts the clock, which ends the wait at once.
            let wait: Double = locked { throttleStart + Double(throttleBytes) / Double(rate) - Self.now() }
            if wait <= 0 { return }
            try checkpoint()
            usleep(useconds_t(min(0.05, wait) * 1_000_000))
        }
    }

    /// After a pause or a wait: the speed and the throttle count from now. Call with the lock held.
    private func restartClocks() {
        let now = Self.now()
        meter.restart(bytes: bytesDone, at: now)
        throttleStart = now
        throttleBytes = 0
    }

    private func add(items: Int, bytes: Int64) {
        locked {
            itemsDone += items
            bytesDone += bytes
            meter.record(bytes: bytesDone, at: Self.now())
        }
    }

    private func skip(_ src: URL) {
        let m = Self.measure(src)
        countSkip(items: m.items, bytes: m.bytes)
    }

    private func countSkip(items: Int, bytes: Int64) {
        locked {
            itemsTotal -= items
            bytesTotal -= bytes
            skipped += 1
        }
    }

    private var isCancelled: Bool { locked { cancelRequested } }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func notify() { onChange?(self) }

    @discardableResult
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        cond.lock()
        defer { cond.unlock() }
        return try body()
    }

    // MARK: File system helpers

    enum Kind { case folder, package, file, link, missing }

    static func kind(_ url: URL) -> Kind {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return .missing }
        switch st.st_mode & S_IFMT {
        case S_IFLNK: return .link
        case S_IFDIR:
            return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true ? .package : .folder
        default: return .file
        }
    }

    static func measure(_ url: URL) -> (items: Int, bytes: Int64) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return (0, 0) }
        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            var n = 1
            var b: Int64 = 0
            for child in children(url) {
                let m = measure(child)
                n += m.items
                b += m.bytes
            }
            return (n, b)
        case S_IFREG: return (1, Int64(st.st_size))
        default: return (1, 0)
        }
    }

    /// Everything in a folder, hidden files too, in name order.
    static func children(_ url: URL) -> [URL] {
        let list = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        return list.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func makeFolder(_ dst: URL, like src: URL) throws {
        var st = stat()
        let mode = lstat(src.path, &st) == 0 ? st.st_mode & 0o7777 : 0o755
        if mkdir(dst.path, mode | 0o700) != 0 { throw FileOpError.posix(errno, dst) }
    }

    static func copyFolderDates(_ src: URL, _ dst: URL) {
        if let date = ItemFacts.read(src).modified {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dst.path)
        }
    }

    /// The canonical path (symlinks such as /tmp resolved) for comparing folders.
    static func canonical(_ url: URL) -> String {
        if let p = realpath(url.path, nil) {
            defer { free(p) }
            return String(cString: p)
        }
        return url.standardizedFileURL.path
    }

    static func same(_ a: URL, _ b: URL) -> Bool { canonical(a) == canonical(b) }

    /// True when `folder` is `item` or anywhere inside it.
    static func inside(_ folder: URL, _ item: URL) -> Bool {
        let f = canonical(folder), i = canonical(item)
        return f == i || f.hasPrefix(i + "/")
    }

    static func describe(_ error: Error, _ url: URL) -> String {
        if let e = error as? FileOpError { return e.message }
        return (error as NSError).localizedDescription
    }

    static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Why a file operation failed, in words for a dialog.
public enum FileOpError: Error, Equatable, LocalizedError {
    case exists(String)
    case missing(String)
    case invalidName(FileNaming.Problem)
    case system(String)

    static func posix(_ code: Int32, _ url: URL) -> FileOpError {
        if code == EEXIST { return .exists(url.lastPathComponent) }
        if code == ENOENT { return .missing(url.lastPathComponent) }
        return .system(url.lastPathComponent + ": " + String(cString: strerror(code)))
    }

    public var message: String {
        switch self {
        case .exists(let name): "There is already an item named \(name) here."
        case .missing(let name): "\(name) is no longer there."
        case .invalidName(let p): p.message
        case .system(let text): text
        }
    }

    public var errorDescription: String? { message }
}
