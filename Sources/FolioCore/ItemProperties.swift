import AVFoundation
import CoreServices
import Darwin
import Foundation
import ImageIO

/// POSIX permissions as the Permissions tab's nine check boxes.
public struct Permissions: Sendable, Equatable {
    public enum Who: Int, CaseIterable, Sendable { case owner, group, others }
    public enum Access: Int, CaseIterable, Sendable { case read, write, execute }

    /// The low 12 bits of st_mode.
    public var mode: UInt16

    public init(mode: UInt16) { self.mode = mode & 0o7777 }

    private static func bit(_ who: Who, _ access: Access) -> UInt16 {
        UInt16(0o400) >> UInt16(who.rawValue * 3 + access.rawValue)
    }

    public func allows(_ who: Who, _ access: Access) -> Bool { mode & Self.bit(who, access) != 0 }

    public func setting(_ who: Who, _ access: Access, _ on: Bool) -> Permissions {
        Permissions(mode: on ? mode | Self.bit(who, access) : mode & ~Self.bit(who, access))
    }

    /// "rw-r--r--".
    public var symbolic: String {
        Who.allCases.map { who in
            Access.allCases.map { a in allows(who, a) ? ["r", "w", "x"][a.rawValue] : "-" }.joined()
        }.joined()
    }

    /// "644".
    public var octal: String { String(mode & 0o777, radix: 8) }

    /// Nobody may write.
    public var isReadOnly: Bool { mode & 0o222 == 0 }

    /// Read-only on clears every write bit; off gives the owner write access back.
    public func readOnly(_ on: Bool) -> Permissions {
        Permissions(mode: on ? mode & ~0o222 : mode | 0o200)
    }
}

/// Everything the Properties window shows about one item.
public struct ItemInfo: Sendable, Equatable {
    public let url: URL
    public let name: String
    /// The folder it is in.
    public let location: String
    /// "Folder", "Plain Text Document".
    public let kind: String
    public let isFolder: Bool
    public let isPackage: Bool
    public let link: LinkKind?
    public let linkTarget: URL?
    /// Bytes for files and packages' own entry; folders are counted with `FolderCounter`.
    public let size: Int64?
    public let sizeOnDisk: Int64?
    public let created: Date?
    public let modified: Date?
    public let lastOpened: Date?
    /// The Mac's locked flag (uchg), Explorer's Read-only attribute.
    public let isLocked: Bool
    /// The hidden flag (or a dot name).
    public let isHidden: Bool
    /// com.apple.quarantine is set: Explorer's "This file came from another computer".
    public let isQuarantined: Bool
    public let owner: String
    public let group: String
    public let permissions: Permissions
    public let tags: [String]

    public static func read(_ url: URL) -> ItemInfo {
        let fresh = URL(fileURLWithPath: url.path)
        let keys: Set<URLResourceKey> = [.localizedTypeDescriptionKey, .isPackageKey, .creationDateKey,
                                         .contentModificationDateKey, .contentAccessDateKey, .isUserImmutableKey,
                                         .isHiddenKey, .tagNamesKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let v = try? fresh.resourceValues(forKeys: keys)
        var st = stat()
        let exists = lstat(url.path, &st) == 0
        let type = st.st_mode & S_IFMT
        let isDir = exists && type == S_IFDIR
        let isPackage = v?.isPackage ?? false
        let link = Aliases.kind(of: url)
        let allocated = v?.totalFileAllocatedSize ?? v?.fileAllocatedSize
        return ItemInfo(
            url: url,
            name: fresh.lastPathComponent,
            location: url.deletingLastPathComponent().path,
            kind: isDir && !isPackage ? "Folder" : (v?.localizedTypeDescription ?? (link == .symlink ? "Symbolic link" : "Document")),
            isFolder: isDir && !isPackage,
            isPackage: isPackage,
            link: link,
            linkTarget: link == nil ? nil : Aliases.resolve(url),
            size: isDir ? nil : exists ? Int64(st.st_size) : nil,
            sizeOnDisk: isDir ? nil : allocated.map(Int64.init) ?? (exists ? Int64(st.st_blocks) * 512 : nil),
            created: v?.creationDate,
            modified: v?.contentModificationDate,
            lastOpened: SpotlightDates.lastUsed(url) ?? v?.contentAccessDate,
            isLocked: v?.isUserImmutable ?? (st.st_flags & UInt32(UF_IMMUTABLE) != 0),
            isHidden: v?.isHidden ?? false,
            isQuarantined: ExtendedAttributes.has(url, "com.apple.quarantine"),
            owner: exists ? userName(st.st_uid) : "",
            group: exists ? groupName(st.st_gid) : "",
            permissions: Permissions(mode: UInt16(st.st_mode)),
            tags: v?.tagNames ?? [])
    }

    private static func userName(_ uid: uid_t) -> String {
        guard let pw = getpwuid(uid) else { return String(uid) }
        return String(cString: pw.pointee.pw_name)
    }

    private static func groupName(_ gid: gid_t) -> String {
        guard let gr = getgrgid(gid) else { return String(gid) }
        return String(cString: gr.pointee.gr_name)
    }
}

/// The General tab's Locked and Hidden boxes, the Permissions tab, Unblock and tags.
public enum ItemFlags {
    public static func setLocked(_ on: Bool, _ url: URL) throws {
        var values = URLResourceValues()
        values.isUserImmutable = on
        var u = URL(fileURLWithPath: url.path)
        try u.setResourceValues(values)
    }

    public static func setHidden(_ on: Bool, _ url: URL) throws {
        var values = URLResourceValues()
        values.isHidden = on
        var u = URL(fileURLWithPath: url.path)
        try u.setResourceValues(values)
    }

    public static func setPermissions(_ p: Permissions, _ url: URL) throws {
        var st = stat()
        let special = lstat(url.path, &st) == 0 ? UInt16(st.st_mode) & 0o7000 : 0
        if chmod(url.path, mode_t(special | (p.mode & 0o777))) != 0 { throw FileOpError.posix(errno, url) }
    }

    /// Explorer's Unblock: removes the quarantine flag macOS puts on downloads.
    public static func unblock(_ url: URL) throws {
        guard ExtendedAttributes.has(url, "com.apple.quarantine") else { return }
        if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 { throw FileOpError.posix(errno, url) }
    }

    public static func setTags(_ tags: [String], _ url: URL) throws {
        try FileTags.setNames(tags, of: url)
    }
}

public struct XAttr: Sendable, Equatable {
    public let name: String
    public let size: Int
}

public enum ExtendedAttributes {
    public static func list(_ url: URL) -> [XAttr] {
        let n = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard n > 0 else { return [] }
        var buf = [CChar](repeating: 0, count: n)
        guard listxattr(url.path, &buf, n, XATTR_NOFOLLOW) == n else { return [] }
        return buf.split(separator: 0).map { chars in
            let name = String(decoding: chars.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return XAttr(name: name, size: max(0, getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)))
        }.sorted { $0.name < $1.name }
    }

    static func has(_ url: URL, _ name: String) -> Bool {
        getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}

/// Files, folders and bytes under a selection, for "Contains N files, M folders" and the sizes.
public struct FolderTally: Sendable, Equatable {
    public var files: Int
    public var folders: Int
    public var bytes: Int64
    public var allocated: Int64

    public init(files: Int, folders: Int, bytes: Int64, allocated: Int64) {
        self.files = files
        self.folders = folders
        self.bytes = bytes
        self.allocated = allocated
    }
}

public enum FolderCounter {
    /// Walks every item (hidden ones and package contents too, links not followed). `report` gets the
    /// running tally every `every` items, so the window's counter ticks; `isCancelled` stops the walk.
    /// `includeRoots` counts the given items themselves (a multi-selection); off counts what is inside.
    public static func count(_ roots: [URL], includeRoots: Bool, every: Int = 128,
                             isCancelled: () -> Bool = { false },
                             report: (FolderTally) -> Void = { _ in }) -> FolderTally {
        var tally = FolderTally(files: 0, folders: 0, bytes: 0, allocated: 0)
        var seen = 0
        func add(_ url: URL, isRoot: Bool) -> Bool {
            if isCancelled() { return false }
            var st = stat()
            guard lstat(url.path, &st) == 0 else { return true }
            let isDir = st.st_mode & S_IFMT == S_IFDIR
            if !isRoot || includeRoots {
                if isDir { tally.folders += 1 } else {
                    tally.files += 1
                    tally.bytes += Int64(st.st_size)
                    tally.allocated += Int64(st.st_blocks) * 512
                }
                seen += 1
                if seen % max(1, every) == 0 { report(tally) }
            }
            if isDir {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                for name in names.sorted() where !add(url.appendingPathComponent(name), isRoot: false) { return false }
            }
            return true
        }
        for root in roots where !add(root, isRoot: true) { break }
        report(tally)
        return tally
    }
}

/// On, off or mixed across a selection (the Locked and Hidden boxes of multi-selection Properties).
public enum Tri: Sendable, Equatable {
    case on, off, mixed

    public static func of(_ values: [Bool]) -> Tri {
        if values.allSatisfy({ $0 }) && !values.isEmpty { return .on }
        return values.contains(true) ? .mixed : .off
    }
}

public enum SelectionText {
    /// "3 files, 1 folder".
    public static func contains(_ t: FolderTally) -> String {
        ByteText.grouped(t.files) + (t.files == 1 ? " file, " : " files, ")
            + ByteText.grouped(t.folders) + (t.folders == 1 ? " folder" : " folders")
    }

    /// "12.4 MB (12,996,224 bytes)", Explorer's size line.
    public static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes) + " (" + ByteText.grouped(bytes) + (bytes == 1 ? " byte)" : " bytes)")
    }
}

public struct PixelSize: Sendable, Equatable {
    public let width: Int
    public let height: Int
}

/// The Details tab's dimensions (ImageIO) and length (AVFoundation).
public enum MediaInfo {
    public static func pixelSize(_ url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(o) ? PixelSize(width: h, height: w) : PixelSize(width: w, height: h)
    }

    /// The camera, lens and taken date an image carries, when it has them.
    public static func exif(_ url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var out: [(String, String)] = []
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let camera = [tiff[kCGImagePropertyTIFFMake] as? String, tiff[kCGImagePropertyTIFFModel] as? String]
                .compactMap { $0 }.joined(separator: " ")
            if !camera.isEmpty { out.append(("Camera", camera)) }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String { out.append(("Date taken", taken)) }
            if let lens = exif[kCGImagePropertyExifLensModel] as? String { out.append(("Lens", lens)) }
        }
        return out
    }

    public static func duration(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration), time.isNumeric, time.seconds > 0 else { return nil }
        return time.seconds
    }

    /// "0:01", "1:05", "1:02:03".
    public static func durationText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(sec))" : "\(m):\(two(sec))"
    }
}

/// Spotlight's title, authors and comments, for the Details tab.
public enum Spotlight {
    public static func details(_ url: URL) -> [(String, String)] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        var out: [(String, String)] = []
        func text(_ key: CFString) -> String? {
            let v = MDItemCopyAttribute(item, key)
            if let s = v as? String, !s.isEmpty { return s }
            if let list = v as? [String], !list.isEmpty { return list.joined(separator: ", ") }
            return nil
        }
        if let t = text(kMDItemTitle) { out.append(("Title", t)) }
        if let a = text(kMDItemAuthors) { out.append(("Authors", a)) }
        if let c = text(kMDItemFinderComment) { out.append(("Comments", c)) }
        if let w = text(kMDItemWhereFroms) { out.append(("Where from", w)) }
        return out
    }
}

/// One app that can open a file.
public struct AppChoice: Sendable, Equatable {
    public let url: URL
    public let name: String
}

/// Launch Services: the apps that open a file, its default first, then by name.
public enum OpenWith {
    public static func apps(for url: URL) -> [AppChoice] {
        let all = (LSCopyApplicationURLsForURL(url as CFURL, .all)?.takeRetainedValue() as? [URL]) ?? []
        let first = defaultApp(for: url)
        var seen = Set<String>()
        var out: [AppChoice] = []
        if let first { out.append(first); seen.insert(first.url.standardizedFileURL.path) }
        let rest = all.map(choice).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // The same app installed twice keeps only its first copy.
        var names = Set(out.map(\.name))
        return out + rest.filter { names.insert($0.name).inserted }
    }

    public static func defaultApp(for url: URL) -> AppChoice? {
        (LSCopyDefaultApplicationURLForURL(url as CFURL, .all, nil)?.takeRetainedValue() as URL?).map(choice)
    }

    static func choice(_ app: URL) -> AppChoice {
        AppChoice(url: app, name: FileManager.default.displayName(atPath: app.path)
            .replacingOccurrences(of: ".app", with: ""))
    }
}

/// Dates that only Spotlight knows.
enum SpotlightDates {
    /// Finder's "Last opened": Spotlight's last-used date when it has one.
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
