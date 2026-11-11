import Darwin
import Foundation
import UniformTypeIdentifiers

/// One folder read with `getattrlistbulk`: the kernel returns the name, type, date, size and flags of many
/// entries in one call. `contentsOfDirectory` uses the same call, but then each entry's values go through
/// URL resource values, which cost more than the read. FolderListing uses this and falls back to the
/// URL way for a folder (or an entry) that this cannot read.
enum BulkListing {
    /// What the kernel gives for one entry.
    struct Raw {
        var name: String
        var type: UInt32
        var modified: Date?
        var size: Int64?
        /// Finder flags (FinderInfo bytes 8 and 9): the alias, bundle, invisible and custom icon bits.
        var finderFlags: UInt16
        var mode: UInt32
        /// BSD flags (`UF_HIDDEN`, `UF_IMMUTABLE`, `UF_COMPRESSED`).
        var flags: UInt32
        var isMountPoint: Bool
        /// The file system's extended flags (EF_NO_XATTRS), when it gives them.
        var extFlags: UInt64?
        /// The kernel could not read this entry's attributes.
        var failed: Bool
    }

    static let kIsAlias: UInt16 = 0x8000
    static let kIsInvisible: UInt16 = 0x4000 // the tests set it
    static let kHasBundle: UInt16 = 0x2000

    /// The first call's buffer (a folder of a few thousand items), then the one for the rest.
    static let smallBuffer = 256 * 1024
    static let bigBuffer = 4 * 1024 * 1024

    /// The sealed system volume (/, /usr, /System) is read the URL way: its firmlinks (/Applications,
    /// /Users, /usr/local) read here as the system's stubs, not the data volume's folders.
    static func readsTheURLWay(mountedOn: String) -> Bool { mountedOn == "/" }

    /// Every entry of `path`, or nil when the folder cannot be opened or read this way.
    static func read(_ path: String) -> [Raw]? {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var fs = statfs()
        guard fstatfs(fd, &fs) == 0 else { return nil }
        let mountedOn = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        if readsTheURLWay(mountedOn: mountedOn) { return nil }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FNDRINFO) | attrgroup_t(ATTR_CMN_ACCESSMASK) | attrgroup_t(ATTR_CMN_FLAGS)
        request.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)
        // Extended common attributes ride in forkattr: the extended flags say "no extended attributes".
        request.forkattr = attrgroup_t(ATTR_CMNEXT_EXT_FLAGS)
        // A folder that fills the first buffer gets a bigger one: fewer calls for a huge folder.
        var size = smallBuffer
        var buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        var out: [Raw] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, size, UInt64(FSOPT_ATTR_CMN_EXTENDED))
            if count < 0 { return nil }
            if count == 0 { break }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                out.append(parse(entry + 4))
                entry += length
            }
            if size == smallBuffer {
                buffer.deallocate()
                size = bigBuffer
                buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
            }
        }
        return out
    }

    /// One entry, after its length: the returned set first, then each attribute in the order of its bit
    /// (ATTR_CMN_ERROR comes first), common ones, then folder ones, then file ones (getattrlistbulk(2)).
    private static func parse(_ start: UnsafeRawPointer) -> Raw {
        var p = start
        let returned = p.loadUnaligned(as: attribute_set_t.self)
        p += MemoryLayout<attribute_set_t>.size
        let common = returned.commonattr
        func has(_ bit: Int32) -> Bool { common & attrgroup_t(bit) != 0 }
        var raw = Raw(name: "", type: 0, modified: nil, size: nil, finderFlags: 0, mode: 0, flags: 0,
                      isMountPoint: false, extFlags: nil, failed: false)
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
        if has(ATTR_CMN_OBJTYPE) {
            raw.type = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if has(ATTR_CMN_MODTIME) {
            let t = p.loadUnaligned(as: timespec.self)
            // Foundation's own sum, so a date compares equal to the one URL resource values give.
            raw.modified = Date(timeIntervalSinceReferenceDate: Double(t.tv_sec) - Date.timeIntervalBetween1970AndReferenceDate
                                + 1.0e-9 * Double(t.tv_nsec))
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
        if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
            raw.isMountPoint = p.loadUnaligned(as: UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
            p += 4
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            raw.size = p.loadUnaligned(as: Int64.self)
            p += 8
        }
        if returned.forkattr & attrgroup_t(ATTR_CMNEXT_EXT_FLAGS) != 0 {
            raw.extFlags = p.loadUnaligned(as: UInt64.self)
            p += 8
        }
        return raw
    }

    /// Hidden as the URL values decide it: a dot name or the hidden flag (setting Finder's invisible bit
    /// sets the hidden flag too).
    static func isHidden(_ raw: Raw) -> Bool {
        raw.name.hasPrefix(".") || raw.flags & UInt32(UF_HIDDEN) != 0
    }

    /// The listing of `folder` as FileEntry values, with the same values the URL way gives; nil to fall back.
    static func entries(_ folder: URL, includeHidden: Bool, hideProtected: Bool, kinds: inout [String: String]) -> [FileEntry]? {
        guard let raws = read(folder.path) else { return nil }
        var out: [FileEntry] = []
        out.reserveCapacity(raws.count)
        for raw in raws {
            let hidden = isHidden(raw)
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
                bsdFlags: raw.flags,
                hasExtendedAttributes: raw.extFlags.map { $0 & UInt64(EF_NO_XATTRS) == 0 }))
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
