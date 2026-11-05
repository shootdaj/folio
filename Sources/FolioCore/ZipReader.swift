import Darwin
import Foundation
import UniformTypeIdentifiers

/// One entry of a zip's central directory.
public struct ZipEntry: Sendable, Equatable {
    /// The path inside the zip, "/" separated; folders end in "/".
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let compressedSize: Int64
    public let modified: Date?

    /// The last part of the path.
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

/// A zip read the way Explorer's Compressed folders read one: the central directory at its end (ZIP64
/// too), no extraction. Mac metadata (__MACOSX and ._ files) is left out, as Finder leaves it out.
public struct ZipArchive: Sendable {
    public enum Failure: Error, LocalizedError {
        case notAZip(String)
        public var errorDescription: String? {
            switch self { case .notAZip(let name): "\(name) is not a zip file, or it is damaged." }
        }
    }

    public let url: URL
    public let entries: [ZipEntry]

    public init(url: URL, includeMetadata: Bool = false) throws {
        self.url = url
        let all = try Self.read(url)
        entries = includeMetadata ? all : all.filter { e in
            !e.path.hasPrefix("__MACOSX/") && !e.name.hasPrefix("._") && e.name != ".DS_Store"
        }
    }

    /// What a folder inside the zip holds (the root is ""), folders that only appear in paths included,
    /// folders first then names as Finder sorts them.
    public func children(of folder: String) -> [ZipEntry] {
        let prefix = folder.isEmpty ? "" : (folder.hasSuffix("/") ? folder : folder + "/")
        var files: [String: ZipEntry] = [:]
        var dirs: [String: ZipEntry] = [:]
        for e in entries where e.path.hasPrefix(prefix) && e.path.count > prefix.count {
            let rest = e.path.dropFirst(prefix.count)
            let parts = rest.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }
            let name = String(first)
            if parts.count == 1 && !e.isDirectory {
                files[name] = e
            } else if dirs[name] == nil || (parts.count == 1 && e.isDirectory) {
                let real = parts.count == 1 && e.isDirectory
                dirs[name] = ZipEntry(path: prefix + name + "/", isDirectory: true, size: 0, compressedSize: 0,
                                      modified: real ? e.modified : dirs[name]?.modified)
            }
        }
        let order: (ZipEntry, ZipEntry) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return dirs.values.sorted(by: order) + files.values.sorted(by: order)
    }

    /// True when `folder` exists in the zip (as an entry or in a path).
    public func hasFolder(_ folder: String) -> Bool {
        if folder.isEmpty { return true }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return entries.contains { $0.path.hasPrefix(prefix) }
    }

    // MARK: Reading the central directory

    private static func read(_ url: URL) throws -> [ZipEntry] {
        let name = url.lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.notAZip(name) }
        defer { try? handle.close() }
        let size = Int64((try? handle.seekToEnd()) ?? 0)
        guard size >= 22 else { throw Failure.notAZip(name) }
        let tailLength = min(size, 65_557)
        try handle.seek(toOffset: UInt64(size - tailLength))
        let tail = handle.readData(ofLength: Int(tailLength))
        guard let eocd = lastIndex(of: 0x06054b50, in: tail) else { throw Failure.notAZip(name) }
        var count = Int64(tail.le16(eocd + 10))
        var cdSize = Int64(tail.le32(eocd + 12))
        var cdOffset = Int64(tail.le32(eocd + 16))
        // ZIP64: the real numbers sit in the ZIP64 end record, found through its locator.
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF, eocd >= 20,
           tail.le32(eocd - 20) == 0x07064b50 {
            let at = Int64(tail.le64(eocd - 20 + 8))
            try handle.seek(toOffset: UInt64(at))
            let rec = handle.readData(ofLength: 56)
            guard rec.count == 56, rec.le32(0) == 0x06064b50 else { throw Failure.notAZip(name) }
            count = Int64(rec.le64(32))
            cdSize = Int64(rec.le64(40))
            cdOffset = Int64(rec.le64(48))
        }
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= size else { throw Failure.notAZip(name) }
        try handle.seek(toOffset: UInt64(cdOffset))
        let cd = handle.readData(ofLength: Int(cdSize))
        var out: [ZipEntry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, cd.le32(p) == 0x02014b50 else { throw Failure.notAZip(name) }
            let flags = cd.le16(p + 8)
            let time = cd.le16(p + 12), date = cd.le16(p + 14)
            var compressed = Int64(cd.le32(p + 20)), uncompressed = Int64(cd.le32(p + 24))
            let nameLength = Int(cd.le16(p + 28)), extraLength = Int(cd.le16(p + 30)), commentLength = Int(cd.le16(p + 32))
            guard p + 46 + nameLength + extraLength + commentLength <= cd.count else { throw Failure.notAZip(name) }
            let raw = cd.subdata(in: (p + 46)..<(p + 46 + nameLength))
            let path = flags & 0x0800 != 0 ? String(decoding: raw, as: UTF8.self)
                : (String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? "")
            var modified = dosDate(date: date, time: time)
            // Extra fields: ZIP64 sizes (0x0001) and the Unix modification time (0x5455).
            var e = p + 46 + nameLength
            let end = e + extraLength
            while e + 4 <= end {
                let id = cd.le16(e), length = Int(cd.le16(e + 2))
                let body = e + 4
                guard body + length <= end else { break }
                if id == 0x0001 {
                    var q = body
                    if uncompressed == 0xFFFF_FFFF, q + 8 <= body + length { uncompressed = Int64(cd.le64(q)); q += 8 }
                    if compressed == 0xFFFF_FFFF, q + 8 <= body + length { compressed = Int64(cd.le64(q)) }
                } else if id == 0x5455, length >= 5, cd[cd.startIndex + body] & 1 != 0 {
                    modified = Date(timeIntervalSince1970: Double(Int32(bitPattern: cd.le32(body + 1))))
                }
                e = body + length
            }
            if !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") {
                out.append(ZipEntry(path: path, isDirectory: path.hasSuffix("/"), size: uncompressed,
                                    compressedSize: compressed, modified: modified))
            }
            p += 46 + nameLength + extraLength + commentLength
        }
        return out
    }

    private static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        var i = data.count - 22
        while i >= 0 {
            if data.le32(i) == signature { return i }
            i -= 1
        }
        return nil
    }

    /// MS-DOS date and time (local time, 2 s steps).
    private static func dosDate(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var c = DateComponents()
        c.year = 1980 + Int(date >> 9)
        c.month = Int((date >> 5) & 0x0F)
        c.day = Int(date & 0x1F)
        c.hour = Int(time >> 11)
        c.minute = Int((time >> 5) & 0x3F)
        c.second = Int(time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: c)
    }
}

extension Data {
    func le16(_ at: Int) -> UInt16 {
        let i = startIndex + at
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func le32(_ at: Int) -> UInt32 {
        let i = startIndex + at
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    func le64(_ at: Int) -> UInt64 { UInt64(le32(at)) | UInt64(le32(at + 4)) << 32 }
}

/// A place inside a zip: the zip file on disk and the folder path within it ("" for its top).
public enum ZipPath {
    public static func split(_ url: URL) -> (archive: URL, inner: String)? {
        let parts = url.standardizedFileURL.pathComponents
        var path = ""
        for (i, part) in parts.enumerated() {
            path = i == 0 ? part : (path == "/" ? "/" : path + "/") + part
            guard part.lowercased().hasSuffix(".zip") else { continue }
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            return (URL(fileURLWithPath: path), parts.dropFirst(i + 1).joined(separator: "/"))
        }
        return nil
    }

    /// True for a folder path inside a zip (not the zip file in its own folder).
    public static func isInside(_ url: URL) -> Bool { split(url) != nil }
}

/// A zip browsed like a folder: its rows for the list, and entries copied out of it with bsdtar.
public enum ZipFolder {
    /// The rows of a folder inside a zip; their URLs continue the zip's path (photos.zip/Trip/day.jpg).
    public static func list(_ url: URL) throws -> [FileEntry] {
        guard let (archive, inner) = ZipPath.split(url) else { throw ZipArchive.Failure.notAZip(url.lastPathComponent) }
        let zip = try ZipArchive(url: archive)
        return rows(zip, inner)
    }

    public static func rows(_ zip: ZipArchive, _ inner: String) -> [FileEntry] {
        var kinds: [String: String] = [:]
        return zip.children(of: inner).map { e in
            let name = e.name
            let url = zip.url.appendingPathComponent(String(e.path.dropLast(e.isDirectory ? 1 : 0)), isDirectory: e.isDirectory)
            return FileEntry(url: url, name: name, isFolder: e.isDirectory, modified: e.modified,
                             size: e.isDirectory ? nil : e.size, kind: kind(name, folder: e.isDirectory, cache: &kinds),
                             isHidden: name.hasPrefix("."))
        }
    }

    /// The type text Finder gives the extension ("Plain Text Document"), or Folder.
    static func kind(_ name: String, folder: Bool, cache: inout [String: String]) -> String {
        if folder { return "Folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        if let known = cache[ext] { return known }
        let text = KindNames.name(forExtension: ext)
        cache[ext] = text
        return text
    }

    /// Copies entries out of their zip into `folder` (a staging folder for Copy or a drag, or the place
    /// they are dropped): each lands as a top-level item, folders with everything in them.
    @discardableResult
    public static func extract(_ items: [URL], to folder: URL) throws -> [URL] {
        guard let first = items.first, let (archive, _) = ZipPath.split(first) else { return [] }
        var byDepth: [Int: [String]] = [:]
        for url in items {
            guard let (a, inner) = ZipPath.split(url), a.path == archive.path, !inner.isEmpty else { continue }
            byDepth[inner.split(separator: "/").count - 1, default: []].append(inner)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var out: [URL] = []
        for (depth, inners) in byDepth {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ArchiveJob.tool)
            p.arguments = ["-x", "-f", archive.path, "-C", folder.path, "--strip-components", "\(depth)", "--"] + inners
            p.standardOutput = FileHandle.nullDevice
            let err = Pipe()
            p.standardError = err
            try p.run()
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            if p.terminationStatus != 0 { throw FileOpError.system(message.isEmpty ? "Could not copy from \(archive.lastPathComponent)." : message) }
            out += inners.map { folder.appendingPathComponent(($0 as NSString).lastPathComponent) }
        }
        return out
    }
}

/// Finder's kind for an extension, as the listing shows it for a real file: read once per extension
/// from an empty sample file in a temp folder of Folio's own.
enum KindNames {
    nonisolated(unsafe) private static var known: [String: String] = [:]
    private static let lock = NSLock()

    static func name(forExtension ext: String) -> String {
        lock.lock()
        if let hit = known[ext] { lock.unlock(); return hit }
        lock.unlock()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-kinds", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sample = folder.appendingPathComponent(ext.isEmpty ? "sample" : "sample." + ext)
        if !FileManager.default.fileExists(atPath: sample.path) { FileManager.default.createFile(atPath: sample.path, contents: Data()) }
        let text = (try? sample.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? UTType(filenameExtension: ext)?.localizedDescription ?? "Document"
        lock.lock()
        known[ext] = text
        lock.unlock()
        return text
    }
}
