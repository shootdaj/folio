import Darwin
import Foundation
import UniformTypeIdentifiers

/// One folder read with `getattrlistbulk`: the kernel returns the name, type, date, size and flags of many
/// entries in one call. `contentsOfDirectory` uses the same call, but then each entry's values go through
/// URL resource values, which cost more than the read. FolderListing uses this and falls back to the
/// URL way for a folder (or an entry) that this cannot read.
/// Why an extended bulk read gave nothing.
enum ScanReadError: Error, Equatable {
    /// The caller has no right to read the folder.
    case denied
    /// The folder is gone, or it is not a folder.
    case missing
    /// The kernel cannot give these values here: the sealed system volume.
    case unsupported
    /// Any other failure, with its `errno`.
    case failed(Int32)

    init(errno code: Int32) {
        switch code {
        case EACCES, EPERM: self = .denied
        case ENOENT, ENOTDIR: self = .missing
        default: self = .failed(code)
        }
    }
}

enum BulkListing {
    /// What the kernel gives for one entry.
    struct Raw {
        var name: String
        var type: UInt32
        var modified: Date?
        var size: Int64?
        /// Finder flags (FinderInfo bytes 8 and 9): the alias and bundle bits.
        var finderFlags: UInt16
        var mode: UInt32
        /// BSD flags (`UF_HIDDEN`).
        var flags: UInt32
        var isMountPoint: Bool
        /// The kernel could not read this entry's attributes.
        var failed: Bool
        // The next fields come only from `readExtended`; `read` leaves them at these defaults.
        /// The volume the entry is on (`st_dev`, as the kernel's 32-bit `dev_t`).
        var device: UInt32 = 0
        /// The file number on that volume (`st_ino`). Hard links share it.
        var inode: UInt64 = 0
        /// The number of hard links (`st_nlink`). Files only; 0 for a folder.
        var linkCount: UInt32 = 0
        /// The bytes the file takes on disk, as `st_blocks * 512` (`ATTR_FILE_ALLOCSIZE`). Files only.
        var allocated: Int64?
        /// The last access date (`st_atime`).
        var accessed: Date?
        /// The date the item came into its folder (Finder's "Date Added").
        var added: Date?
    }

    private static let kIsAlias: UInt16 = 0x8000
    private static let kHasBundle: UInt16 = 0x2000

    /// Every entry of `path`, or nil when the folder cannot be opened or read this way.
    static func read(_ path: String) -> [Raw]? {
        try? scan(path, extended: false)
    }

    /// Every entry of `path` with the extended fields (device, inode, links, allocated size, access and
    /// added dates), or the reason the folder could not be read. The sealed system volume is `.unsupported`.
    static func readExtended(_ path: String) throws(ScanReadError) -> [Raw] {
        try scan(path, extended: true)
    }

    private static func scan(_ path: String, extended: Bool) throws(ScanReadError) -> [Raw] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ScanReadError(errno: errno) }
        defer { close(fd) }
        // The sealed system volume (/, /usr, /System): its firmlinks (/Applications, /Users, /usr/local)
        // read here as the system's stubs, not the data volume's folders. Foundation follows them.
        var fs = statfs()
        guard fstatfs(fd, &fs) == 0 else { throw .failed(errno) }
        let mountedOn = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if mountedOn == "/" { throw .unsupported }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FNDRINFO) | attrgroup_t(ATTR_CMN_ACCESSMASK) | attrgroup_t(ATTR_CMN_FLAGS)
        request.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)
        if extended {
            // Bits are added to the same request; the kernel returns them in bit order (see `parse`).
            request.commonattr |= attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_ACCTIME)
                | attrgroup_t(ATTR_CMN_FILEID) | attrgroup_t(ATTR_CMN_ADDEDTIME)
            request.fileattr |= attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        }
        let size = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        var out: [Raw] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, size, 0)
            if count < 0 { throw ScanReadError(errno: errno) }
            if count == 0 { break }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                out.append(parse(entry + 4))
                entry += length
            }
        }
        return out
    }

    /// One entry, after its length: the returned set first, then each attribute in the order of its bit
    /// (ATTR_CMN_ERROR comes first), common ones, then folder ones, then file ones.
    ///
    /// Order and sizes, from getattrlist(2) and getattrlistbulk(2) and the bit values in <sys/attr.h>:
    /// common NAME 0x1 (attrreference, 8 bytes), DEVID 0x2 (dev_t, 4), OBJTYPE 0x8 (4), MODTIME 0x400
    /// (timespec, 16), ACCTIME 0x1000 (timespec), FNDRINFO 0x4000 (32), ACCESSMASK 0x20000 (4), FLAGS
    /// 0x40000 (4), FILEID 0x2000000 (u_int64_t, 8), ADDEDTIME 0x10000000 (timespec); folder
    /// MOUNTSTATUS 0x4 (4); file LINKCOUNT 0x1 (u_int32_t, 4), ALLOCSIZE 0x4 (off_t, 8) and DATALENGTH
    /// 0x200 (off_t, 8). A group's values keep the order of their bits, lowest first.
    private static func parse(_ start: UnsafeRawPointer) -> Raw {
        var p = start
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        let common = returned.commonattr
        func has(_ bit: Int32) -> Bool { common & attrgroup_t(bit) != 0 }
        var raw = Raw(name: "", type: 0, modified: nil, size: nil, finderFlags: 0, mode: 0, flags: 0,
                      isMountPoint: false, failed: false)
        func date(_ t: timespec) -> Date {
            // Foundation's own sum, so a date compares equal to the one URL resource values give.
            Date(timeIntervalSinceReferenceDate: Double(t.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate
                 + 1.0e-9 * Double(t.tv_nsec))
        }
        if has(ATTR_CMN_ERROR) {
            raw.failed = p.loadUnaligned(as: UInt32.self) != 0
            p += 4
        }
        if has(ATTR_CMN_NAME) {
            let ref = p.loadUnaligned(as: attrreference_t.self)
            let bytes = UnsafeRawBufferPointer(start: p + Int(ref.attr_dataoffset), count: max(0, Int(ref.attr_length) - 1))
            raw.name = String(decoding: bytes, as: UTF8.self)
            p += MemoryLayout<attrreference_t>.size
        } else {
            raw.failed = true
        }
        if has(ATTR_CMN_DEVID) {
            raw.device = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if has(ATTR_CMN_OBJTYPE) {
            raw.type = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if has(ATTR_CMN_MODTIME) {
            raw.modified = date(p.loadUnaligned(as: timespec.self))
            p += MemoryLayout<timespec>.size
        }
        if has(ATTR_CMN_ACCTIME) {
            raw.accessed = date(p.loadUnaligned(as: timespec.self))
            p += MemoryLayout<timespec>.size
        }
        if has(ATTR_CMN_FNDRINFO) {
            raw.finderFlags = UInt16(p.load(fromByteOffset: 8, as: UInt8.self)) << 8 | UInt16(p.load(fromByteOffset: 9, as: UInt8.self))
            p += 32
        }
        if has(ATTR_CMN_ACCESSMASK) {
            raw.mode = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if has(ATTR_CMN_FLAGS) {
            raw.flags = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if has(ATTR_CMN_FILEID) {
            raw.inode = p.loadUnaligned(as: UInt64.self)
            p += 8
        }
        if has(ATTR_CMN_ADDEDTIME) {
            raw.added = date(p.loadUnaligned(as: timespec.self))
            p += MemoryLayout<timespec>.size
        }
        if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
            raw.isMountPoint = p.loadUnaligned(as: UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
            p += 4
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            raw.linkCount = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            raw.allocated = p.loadUnaligned(as: Int64.self)
            p += 8
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            raw.size = p.loadUnaligned(as: Int64.self)
            p += 8
        }
        return raw
    }

    /// The listing of `folder` as FileEntry values, with the same values the URL way gives; nil to fall back.
    static func entries(_ folder: URL, includeHidden: Bool, hideProtected: Bool, kinds: inout [String: String]) -> [FileEntry]? {
        guard let raws = read(folder.path) else { return nil }
        var out: [FileEntry] = []
        out.reserveCapacity(raws.count)
        for raw in raws {
            let hidden = raw.name.hasPrefix(".") || raw.flags & UInt32(UF_HIDDEN) != 0
            if !includeHidden && hidden { continue }
            if hideProtected && ProtectedFiles.isProtected(name: raw.name) { continue }
            let isDir = raw.type == VDIR.rawValue
            let url = folder.appendingPathComponent(raw.name, isDirectory: isDir)
            // An entry the kernel could not read, and links (their target decides), go the URL way.
            if raw.failed || raw.name.isEmpty || raw.type == VLNK.rawValue {
                out.append(FolderListing.entry(for: url, kinds: &kinds))
                continue
            }
            let ext = FolderListing.pathExtension(raw.name)
            let isPackage = isDir && !raw.isMountPoint && (raw.finderFlags & kHasBundle != 0 || PackageExtensions.isPackage(ext))
            let isAlias = !isDir && raw.finderFlags & kIsAlias != 0
            let kindKey: String
            if raw.isMountPoint {
                kindKey = "bulk:volume"
            } else if isPackage {
                kindKey = "bulk:package:" + ext.lowercased()
            } else if isDir {
                kindKey = "bulk:folder"
            } else if isAlias {
                kindKey = "bulk:alias"
            } else if raw.type != VREG.rawValue {
                kindKey = "bulk:special:\(raw.type)"
            } else if ext.isEmpty {
                // No extension: macOS types some by name (README is plain text) and some by the
                // executable bit, so the content type is asked, as the URL way did for every file.
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
                kindKey = type ?? "bulk:data"
            } else {
                kindKey = "bulk:ext:" + ext.lowercased()
            }
            out.append(FileEntry(
                url: url,
                name: raw.name,
                isFolder: isDir && !isPackage,
                modified: raw.modified,
                // Only regular files have a size (a socket or a pipe has none, as with URL values).
                size: raw.type == VREG.rawValue ? raw.size : nil,
                kind: FolderListing.kind(of: url, key: kindKey, cache: &kinds),
                isHidden: hidden,
                isLink: isAlias,
                finderFlags: raw.finderFlags,
                bsdFlags: raw.flags))
        }
        return out
    }
}

/// Whether a folder's extension makes it a package (an app, a bundle, a library), as Launch Services
/// decides; each extension is asked once. Any thread.
enum PackageExtensions {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: Bool] = [:]

    static func isPackage(_ ext: String) -> Bool {
        guard !ext.isEmpty else { return false }
        let key = ext.lowercased()
        if let hit = lock.withLock({ known[key] }) { return hit }
        let answer = UTType(filenameExtension: key, conformingTo: .directory)?.conforms(to: .package) ?? false
        lock.withLock { known[key] = answer }
        return answer
    }
}
