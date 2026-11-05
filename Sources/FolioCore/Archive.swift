import Darwin
import Foundation

/// Compress to: Windows 11's ZIP, 7z and TAR, all written by bsdtar (libarchive, as in Windows 11).
public enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip, sevenZip = "7z", tar

    public var fileExtension: String { rawValue }

    /// The Compress to submenu's wording.
    public var title: String {
        switch self {
        case .zip: "ZIP file"
        case .sevenZip: "7z file"
        case .tar: "TAR file"
        }
    }

    var bsdtarFormat: String {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7zip"
        case .tar: "pax"
        }
    }
}

/// Explorer's names for a new archive and for Extract all's folder, and which files take part.
public enum ArchiveNaming {
    /// Extensions libarchive reads that Extract all is offered for (longest first, for the double ones).
    public static let extractable = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz4", "zip", "7z", "tgz", "tbz",
                                     "tbz2", "txz", "tar", "rar", "cab", "iso", "xar", "cpio", "lha", "lzh"]

    /// One item: its name (a file's without its extension) plus the format's extension; several: the
    /// first one's. A taken name gets " (1)", then " (2)".
    public static func archiveName(for items: [URL], format: ArchiveFormat,
                                   isFolder: ((URL) -> Bool)? = nil,
                                   exists: (String) -> Bool) -> String {
        guard let first = items.first else { return "Archive." + format.fileExtension }
        let folder = isFolder?(first) ?? (FileJob.kind(first) == .folder)
        let base = FileNaming.split(first.lastPathComponent, isFolder: folder).base
        let ext = "." + format.fileExtension
        if !exists(base + ext) { return base + ext }
        var n = 1
        while exists(base + " (\(n))" + ext) { n += 1 }
        return base + " (\(n))" + ext
    }

    /// The archive's name without its archive extension: photos.zip and src.tar.gz give photos and src.
    public static func extractFolderName(for archive: URL) -> String {
        let name = archive.lastPathComponent
        let lower = name.lowercased()
        for ext in extractable where lower.hasSuffix("." + ext) && name.count > ext.count + 1 {
            return String(name.dropLast(ext.count + 1))
        }
        return (name as NSString).deletingPathExtension
    }

    public static func isExtractable(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        return extractable.contains { lower.hasSuffix("." + $0) && lower.count > $0.count + 1 }
    }

    /// Zips open like folders (Explorer's Compressed folders); the other kinds are extracted.
    public static func isBrowsable(_ url: URL) -> Bool { url.pathExtension.lowercased() == "zip" }
}

/// What the progress window shows and drives: copy and move jobs (FileJob) and archive jobs.
public protocol ProgressJob: AnyObject, Sendable {
    var id: Int { get }
    var kind: JobKind { get }
    var sources: [URL] { get }
    var destination: URL { get }
    /// Why a job stopped by itself (an archive bsdtar could not read), for a dialog.
    var errorMessage: String? { get }
    func observe(_ handler: @escaping @Sendable () -> Void)
    func start()
    func finished() async -> JobResult
    func snapshot() -> JobSnapshot
    func pause()
    func resume()
    func cancel()
    func resolve(_ d: ConflictDecision, applyToAll: Bool)
    func setSkipIdentical(_ on: Bool)
    func answer(_ d: ProblemDecision)
}

/// Job numbers shared by every kind of job, so the progress window can key them all alike.
enum JobIDs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last = 0

    static func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        last += 1
        return last
    }
}

/// Compress to ZIP, 7z or TAR, or Extract all, as one bsdtar run: progress from bsdtar's verbose lines
/// (one per entry), Pause and Resume by stopping and continuing the process, Cancel removes what it made.
public final class ArchiveJob: ProgressJob, @unchecked Sendable {
    public enum Operation: Sendable, Equatable { case compress(ArchiveFormat), extract }

    public let id: Int
    public let operation: Operation
    public let sources: [URL]
    public let destination: URL
    public var kind: JobKind { operation == .extract ? .extract : .compress }

    static let tool = "/usr/bin/bsdtar"

    private let cond = NSCondition()
    // Guarded by `cond`.
    private var state: JobState = .preparing
    private var cancelRequested = false
    private var pauseRequested = false
    private var bytesDone: Int64 = 0, bytesTotal: Int64 = 0
    private var itemsDone = 0, itemsTotal = 0
    private var currentName: String?
    private var meter = SpeedMeter()
    private var pid: pid_t = 0
    private var error: String?
    private var finalResult: JobResult?
    private var waiters: [CheckedContinuation<JobResult, Never>] = []
    private var handler: (@Sendable () -> Void)?
    /// Extract: entry path to size, for the bytes done.
    private var sizes: [String: Int64] = [:]
    /// The entry bsdtar is on (its "a name" line has no newline until the entry is written), its size,
    /// and how big the archive was when it began: a big file's progress shows while it is written.
    private var inFlight: (path: String, size: Int64, archiveAt: Int64)?

    public init(compress items: [URL], format: ArchiveFormat, to archive: URL) {
        id = JobIDs.next()
        operation = .compress(format)
        sources = items
        destination = archive
    }

    public init(extract archive: URL, into folder: URL) {
        id = JobIDs.next()
        operation = .extract
        sources = [archive]
        destination = folder
    }

    public var errorMessage: String? { locked { error } }

    public func observe(_ handler: @escaping @Sendable () -> Void) { locked { self.handler = handler } }

    // MARK: Control

    public func start() {
        let thread = Thread { [self] in main() }
        thread.qualityOfService = .userInitiated
        thread.name = "Folio archive job \(id)"
        thread.start()
    }

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
            if pid > 0 { kill(pid, SIGSTOP) }
            if state == .running { state = .paused }
        }
        notify()
    }

    public func resume() {
        locked {
            pauseRequested = false
            if pid > 0 { kill(pid, SIGCONT) }
            if state == .paused { state = .running }
            meter.restart(bytes: bytesDone, at: Self.now())
        }
        notify()
    }

    public func cancel() {
        locked {
            cancelRequested = true
            if pid > 0 {
                kill(pid, SIGCONT)
                kill(pid, SIGTERM)
            }
            cond.broadcast()
        }
    }

    public func resolve(_ d: ConflictDecision, applyToAll: Bool) {}
    public func setSkipIdentical(_ on: Bool) {}
    public func answer(_ d: ProblemDecision) {}

    public func snapshot() -> JobSnapshot {
        cond.lock()
        defer { cond.unlock() }
        let now = Self.now()
        let shown = bytesDone + inFlightBytes()
        if state == .running { meter.record(bytes: shown, at: now) }
        let speed = state == .running ? meter.bytesPerSecond(at: now) : 0
        let left: Double? = speed > 0 && bytesTotal > 0 ? Double(max(0, bytesTotal - shown)) / speed : nil
        return JobSnapshot(id: id, kind: kind, state: state, sources: sources, destination: destination,
                           bytesDone: shown, bytesTotal: bytesTotal, itemsDone: itemsDone, itemsTotal: itemsTotal,
                           currentName: currentName, speed: speed, secondsLeft: left, conflict: nil, conflictsLeft: 0,
                           problem: nil, skipped: 0, skipIdentical: false)
    }

    // MARK: The run

    private func main() {
        let fm = FileManager.default
        var made = false
        var ok = false
        switch operation {
        case .compress(let format):
            prepareCompress()
            ok = runTool(compressArguments(format), input: fileList())
            if !ok { try? fm.removeItem(at: destination) }
        case .extract:
            prepareExtract()
            made = FileJob.kind(destination) == .missing
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                ok = runTool(["-x", "-v", "-k", "-f", sources[0].path, "-C", destination.path], input: nil)
            } catch {
                locked { self.error = error.localizedDescription }
            }
            if !ok && made { try? fm.removeItem(at: destination) }
        }
        let record: OperationRecord?
        switch operation {
        case .compress: record = ok ? .created([destination], title: "Compress") : nil
        case .extract: record = ok && made ? .created([destination], title: "Extract") : nil
        }
        finish(ok ? .done : .cancelled, record: record, placed: ok ? [destination] : [])
    }

    private func prepareCompress() {
        var n = 0
        var b: Int64 = 0
        for src in sources {
            let m = FileJob.measure(src)
            n += m.items
            b += m.bytes
        }
        locked {
            itemsTotal = n
            bytesTotal = b
        }
    }

    /// The entries and their sizes: zips from their central directory, the rest from bsdtar's listing.
    private func prepareExtract() {
        var table: [String: Int64] = [:]
        if ArchiveNaming.isBrowsable(sources[0]), let zip = try? ZipArchive(url: sources[0], includeMetadata: true) {
            for e in zip.entries { table[e.path.hasSuffix("/") ? String(e.path.dropLast()) : e.path] = e.size }
        } else {
            let out = Self.capture([Self.tool, "-t", "-v", "-f", sources[0].path])
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                guard parts.count == 9, let size = Int64(parts[4]) else { continue }
                var path = String(parts[8])
                if path.hasPrefix("./") { path.removeFirst(2) }
                if path.hasSuffix("/") { path.removeLast() }
                if !path.isEmpty, path != "." { table[path] = size }
            }
        }
        locked {
            sizes = table
            itemsTotal = table.count
            bytesTotal = table.values.reduce(0, +)
        }
    }

    private func compressArguments(_ format: ArchiveFormat) -> [String] {
        ["-c", "-v", "-f", destination.path, "--format", format.bsdtarFormat, "-T", "-"]
    }

    /// bsdtar's -T list: "-C" and the folder on lines of their own, then the item's name.
    private func fileList() -> String {
        var out = ""
        for src in sources {
            out += "-C\n" + src.deletingLastPathComponent().path + "\n" + src.lastPathComponent + "\n"
        }
        return out
    }

    /// Runs bsdtar; true when it ends with 0 and was not cancelled. Each "a name" or "x name" line is an entry done.
    private func runTool(_ args: [String], input: String?) -> Bool {
        if sources.contains(where: { $0.lastPathComponent.contains("\n") }) {
            locked { error = "A name with a line break can't go into an archive." }
            return false
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        // No ._ AppleDouble entries in the archive, as Windows and Finder's Compress leave out.
        env["COPYFILE_DISABLE"] = "1"
        p.environment = env
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        let stdin = Pipe()
        p.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do {
            if locked({ cancelRequested }) { return false }
            try p.run()
        } catch {
            locked { self.error = error.localizedDescription }
            return false
        }
        locked {
            pid = p.processIdentifier
            if pauseRequested {
                kill(pid, SIGSTOP)
                state = .paused
            } else {
                state = .running
            }
            meter.restart(bytes: 0, at: Self.now())
        }
        notify()
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        var messages: [String] = []
        var buffer = Data()
        let reader = err.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if !entryDone(line) { messages.append(line) }
            }
            if !buffer.isEmpty { entryStarted(String(decoding: buffer, as: UTF8.self)) }
        }
        p.waitUntilExit()
        locked { pid = 0 }
        let cancelled = locked { cancelRequested }
        if cancelled { return false }
        if p.terminationStatus != 0 {
            let text = messages.map { $0.hasPrefix("bsdtar: ") ? String($0.dropFirst(8)) : $0 }.joined(separator: "\n")
            locked { error = text.isEmpty ? "bsdtar stopped with code \(p.terminationStatus)." : text }
            return false
        }
        return true
    }

    /// How far into the entry in flight: the archive's growth (compressing; random data grows it one to
    /// one, compressible data less, so this never runs ahead) or the extracted file's size. Lock held.
    private func inFlightBytes() -> Int64 {
        guard let f = inFlight, state == .running || state == .paused else { return 0 }
        var st = stat()
        switch operation {
        case .compress:
            guard stat(destination.path, &st) == 0 else { return 0 }
            return max(0, min(f.size, Int64(st.st_size) - f.archiveAt))
        case .extract:
            guard lstat(destination.appendingPathComponent(f.path).path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return 0 }
            return max(0, min(f.size, Int64(st.st_size)))
        }
    }

    /// The start of a verbose line with no newline yet: the entry being written now.
    private func entryStarted(_ partial: String) {
        guard partial.count > 2, partial.hasPrefix("a ") || partial.hasPrefix("x ") else { return }
        var path = String(partial.dropFirst(2))
        if path.hasPrefix("./") { path.removeFirst(2) }
        if path.hasSuffix("/") { path.removeLast() }
        let size: Int64
        switch operation {
        case .compress: size = sizeOfSource(path)
        case .extract: size = locked { sizes[path] ?? 0 }
        }
        var st = stat()
        let archiveAt = stat(destination.path, &st) == 0 ? Int64(st.st_size) : 0
        locked {
            guard inFlight?.path != path else { return }
            inFlight = (path, size, archiveAt)
            currentName = (path as NSString).lastPathComponent
        }
    }

    private func sizeOfSource(_ path: String) -> Int64 {
        let top = path.split(separator: "/").first.map(String.init) ?? path
        guard let parent = sources.first(where: { $0.lastPathComponent == top })?.deletingLastPathComponent() else { return 0 }
        var st = stat()
        guard lstat(parent.appendingPathComponent(path).path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return 0 }
        return Int64(st.st_size)
    }

    /// "a Photos/one.jpg" (compress) or "x Photos/one.jpg" (extract): one more entry, and its bytes.
    private func entryDone(_ line: String) -> Bool {
        guard line.count > 2, line.hasPrefix("a ") || line.hasPrefix("x ") else { return false }
        var path = String(line.dropFirst(2))
        if path.hasPrefix("./") { path.removeFirst(2) }
        if path.hasSuffix("/") { path.removeLast() }
        let bytes: Int64
        switch operation {
        case .compress: bytes = sizeOfSource(path)
        case .extract: bytes = locked { sizes[path] ?? 0 }
        }
        locked {
            inFlight = nil
            itemsDone += 1
            bytesDone += bytes
            currentName = (path as NSString).lastPathComponent
            meter.record(bytes: bytesDone, at: Self.now())
        }
        return true
    }

    private func finish(_ end: JobState, record: OperationRecord?, placed: [URL]) {
        cond.lock()
        inFlight = nil
        if end == .done {
            itemsTotal = max(itemsTotal, itemsDone)
            itemsDone = itemsTotal
            bytesDone = bytesTotal
        }
        let result = JobResult(state: end, record: record, placed: placed, skipped: 0)
        state = end
        currentName = nil
        finalResult = result
        let pending = waiters
        waiters = []
        cond.unlock()
        for w in pending { w.resume(returning: result) }
        notify()
    }

    private func notify() { locked { handler }?() }

    @discardableResult
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        cond.lock()
        defer { cond.unlock() }
        return try body()
    }

    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// A tool's standard output (listing an archive, `sharing -l`).
    public static func capture(_ command: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command[0])
        p.arguments = Array(command.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
