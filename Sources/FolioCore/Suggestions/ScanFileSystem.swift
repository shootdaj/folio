import Darwin
import Foundation

/// What a listing says of one entry.
public enum ScanEntryType: Sendable, Equatable {
    case file, folder, symlink, other
}

/// One entry of a folder, with the values the scan needs.
public struct ScanEntry: Sendable, Equatable {
    public var name: String
    public var type: ScanEntryType
    public var isPackage = false
    public var isMountPoint = false
    public var isHidden = false
    /// A cloud-only file or folder. Reading it would download it.
    public var isDataless = false
    public var isAlias = false
    public var isLocked = false
    public var device: Int32 = 0
    public var inode: UInt64 = 0
    public var linkCount: UInt32 = 0
    /// The size in bytes. A folder has none (0).
    public var logical: Int64 = 0
    /// The bytes on disk.
    public var allocated: Int64 = 0
    public var modified: Date?
    public var accessed: Date?
    public var added: Date?
    public var finderFlags: UInt16 = 0

    public init(name: String, type: ScanEntryType) {
        self.name = name
        self.type = type
    }

    public var fileID: FileID { FileID(device: device, inode: inode) }
}

/// Where a link points.
public enum LinkTarget: Sendable, Equatable {
    case exists
    /// The target is gone. The text is its path.
    case missing(String)
    /// The target is on a volume that is not mounted. This is not broken.
    case offline(String)
}

/// Everything the scan asks of the disk. Tests wrap the live one and fake what a temp folder cannot make.
public protocol ScanFileSystem: Sendable {
    func list(_ dir: URL) throws(ScanReadError) -> [ScanEntry]
    /// Spotlight's last-used date.
    func lastUsed(_ url: URL) -> Date?
    func linkTarget(_ url: URL, alias: Bool) -> LinkTarget
    /// Whether the file may share blocks with another (an APFS clone).
    func mayShareBlocks(_ url: URL) -> Bool
    /// `lstat`, for Verify. Nil when the item is gone.
    func stamp(_ url: URL) -> ItemStamp?
}

/// The real disk.
public struct LiveScanFileSystem: ScanFileSystem {
    private static let kIsAlias: UInt16 = 0x8000
    private static let kHasBundle: UInt16 = 0x2000
    private static let dataless: UInt32 = 0x4000_0000  // SF_DATALESS

    public init() {}

    public func list(_ dir: URL) throws(ScanReadError) -> [ScanEntry] {
        let raws: [BulkListing.Raw]
        do {
            raws = try BulkListing.readExtended(dir.path)
        } catch {
            guard error == .unsupported else { throw error }
            return try fallback(dir)
        }
        var out: [ScanEntry] = []
        out.reserveCapacity(raws.count)
        for raw in raws where !raw.name.isEmpty {
            let type: ScanEntryType = raw.type == VREG.rawValue ? .file : raw.type == VDIR.rawValue ? .folder
                : raw.type == VLNK.rawValue ? .symlink : .other
            var e = ScanEntry(name: raw.name, type: raw.failed ? .other : type)
            let ext = FolderListing.pathExtension(raw.name)
            e.isMountPoint = raw.isMountPoint
            e.isPackage = type == .folder && !raw.isMountPoint
                && (raw.finderFlags & Self.kHasBundle != 0 || PackageExtensions.isPackage(ext))
            e.isHidden = raw.name.hasPrefix(".") || raw.flags & UInt32(UF_HIDDEN) != 0
            e.isDataless = raw.flags & Self.dataless != 0
            e.isAlias = type == .file && raw.finderFlags & Self.kIsAlias != 0
            e.isLocked = raw.flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0
            e.device = Int32(bitPattern: raw.device)
            e.inode = raw.inode
            e.linkCount = raw.linkCount
            e.logical = type == .file ? raw.size ?? 0 : 0
            e.allocated = raw.allocated ?? 0
            e.modified = raw.modified
            e.accessed = raw.accessed
            e.added = raw.added
            e.finderFlags = raw.finderFlags
            out.append(e)
        }
        return out
    }

    /// The sealed system volume: Foundation and `lstat` follow the firmlinks. No mount point, alias or added date here.
    private func fallback(_ dir: URL) throws(ScanReadError) -> [ScanEntry] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        } catch {
            let code = (error as NSError).code
            if code == NSFileReadNoPermissionError { throw .denied }
            if code == NSFileReadNoSuchFileError || code == NSFileNoSuchFileError { throw .missing }
            throw .failed(EIO)
        }
        var out: [ScanEntry] = []
        for name in names {
            var st = stat()
            guard lstat(dir.appendingPathComponent(name).path, &st) == 0 else { continue }
            let kind = st.st_mode & S_IFMT
            var e = ScanEntry(name: name, type: kind == S_IFREG ? .file : kind == S_IFDIR ? .folder : kind == S_IFLNK ? .symlink : .other)
            e.isPackage = e.type == .folder && PackageExtensions.isPackage(FolderListing.pathExtension(name))
            e.isHidden = name.hasPrefix(".") || st.st_flags & UInt32(UF_HIDDEN) != 0
            e.isDataless = st.st_flags & Self.dataless != 0
            e.isLocked = st.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0
            e.device = st.st_dev
            e.inode = UInt64(st.st_ino)
            e.linkCount = UInt32(st.st_nlink)
            e.logical = e.type == .file ? Int64(st.st_size) : 0
            e.allocated = Int64(st.st_blocks) * 512
            e.modified = Self.date(st.st_mtimespec)
            e.accessed = Self.date(st.st_atimespec)
            out.append(e)
        }
        return out
    }

    public func lastUsed(_ url: URL) -> Date? { SpotlightDates.lastUsed(url) }

    public func linkTarget(_ url: URL, alias: Bool) -> LinkTarget {
        alias ? aliasTarget(url) : symlinkTarget(url)
    }

    private func symlinkTarget(_ url: URL) -> LinkTarget {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return .exists }
        let target = dest.hasPrefix("/") ? dest : url.deletingLastPathComponent().appendingPathComponent(dest).path
        return Self.check(target)
    }

    /// Reads the target from the bookmark data and does not resolve the alias, so nothing mounts and nothing waits.
    /// An alias whose stored path is gone may still resolve (the file moved), so that is tried once, without mounting.
    private func aliasTarget(_ url: URL) -> LinkTarget {
        guard let data = try? URL.bookmarkData(withContentsOf: url),
              let path = (try? URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data))?.path else { return .exists }
        let first = Self.check(path)
        guard case .missing = first else { return first }
        var stale = false
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        if let moved = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale),
           Self.exists(moved.path), !Self.isInTrash(moved.path) {
            return .exists
        }
        return first
    }

    private static func exists(_ path: String) -> Bool {
        var st = stat()
        return stat(path, &st) == 0
    }

    private static func isInTrash(_ path: String) -> Bool { path.contains("/.Trash/") || path.contains("/.Trashes/") }

    private static func check(_ path: String) -> LinkTarget {
        if exists(path) { return .exists }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 2, parts[0] == "Volumes", !exists("/Volumes/" + parts[1]) { return .offline(path) }
        return .missing(path)
    }

    public func mayShareBlocks(_ url: URL) -> Bool {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_EXT_FLAGS)
        var buffer = [UInt8](repeating: 0, count: 16)
        let ok = buffer.withUnsafeMutableBytes { raw in
            getattrlist(url.path, &request, raw.baseAddress, raw.count, UInt32(FSOPT_ATTR_CMN_EXTENDED) | UInt32(FSOPT_NOFOLLOW)) == 0
        }
        guard ok else { return false }
        let flags = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt64.self) }
        return flags & UInt64(EF_MAY_SHARE_BLOCKS) != 0
    }

    public func stamp(_ url: URL) -> ItemStamp? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let isFolder = st.st_mode & S_IFMT == S_IFDIR
        return ItemStamp(device: st.st_dev, inode: UInt64(st.st_ino), logical: isFolder ? 0 : Int64(st.st_size),
                         modified: Self.date(st.st_mtimespec))
    }

    /// Foundation's own sum, so a date compares equal to the one the bulk listing gives.
    private static func date(_ t: timespec) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(t.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate
             + 1.0e-9 * Double(t.tv_nsec))
    }
}
