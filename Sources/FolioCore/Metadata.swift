import AVFoundation
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads the columns past Name, Date modified, Type and Size: file attributes and resource values,
/// Spotlight's attributes (MDItem), and where Spotlight has nothing (unindexed places such as /tmp)
/// ImageIO for images and AVFoundation for audio and video. Slow per item; call it off the main thread.
public enum MetadataReader {
    public static func read(_ url: URL) -> ItemMetadata {
        var m = ItemMetadata()
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey, .tagNamesKey,
                                         .isUserImmutableKey, .isHiddenKey, .contentTypeKey, .isSymbolicLinkKey, .isAliasFileKey]
        let v = try? url.resourceValues(forKeys: keys)
        m.created = v?.creationDate
        m.accessed = v?.contentAccessDate
        m.added = v?.addedToDirectoryDate
        m.tags = v?.tagNames ?? []
        m.isLocked = v?.isUserImmutable ?? false
        m.isHidden = v?.isHidden ?? false
        let type = v?.contentType
        m.uti = type?.identifier
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            m.owner = attrs[.ownerAccountName] as? String
            if let p = attrs[.posixPermissions] as? NSNumber { m.permissions = permissionText(p.uint16Value) }
        }
        if v?.isSymbolicLink == true {
            m.linkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        } else if v?.isAliasFile == true {
            m.linkTarget = (try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]))?.path
        }
        readSpotlight(url, isImage: type?.conforms(to: .image) ?? false, into: &m)
        if m.comments == nil { m.comments = finderComment(url) }
        if let type, type.conforms(to: .image), m.pixelWidth == nil || m.dateTaken == nil || m.cameraModel == nil {
            readImage(url, into: &m)
        }
        if let type, type.conforms(to: .audiovisualContent), m.duration == nil { readMedia(url, into: &m) }
        return m
    }

    /// "rwxr-xr-x".
    public static func permissionText(_ mode: UInt16) -> String {
        let letters: [Character] = ["r", "w", "x"]
        var out = ""
        for i in 0..<9 {
            let bit = UInt16(1) << UInt16(8 - i)
            out.append(mode & bit != 0 ? letters[i % 3] : "-")
        }
        return out
    }

    private static func readSpotlight(_ url: URL, isImage: Bool, into m: inout ItemMetadata) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return }
        func get(_ key: CFString) -> Any? { MDItemCopyAttribute(item, key) }
        func number(_ key: CFString) -> Double? { (get(key) as? NSNumber)?.doubleValue }
        func text(_ key: CFString) -> String? { (get(key) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        m.pixelWidth = number(kMDItemPixelWidth).map { Int($0) }
        m.pixelHeight = number(kMDItemPixelHeight).map { Int($0) }
        m.duration = number(kMDItemDurationSeconds)
        m.bitRate = number(kMDItemTotalBitRate) ?? number(kMDItemAudioBitRate)
        m.cameraModel = text(kMDItemAcquisitionModel)
        m.album = text(kMDItemAlbum)
        m.artist = (get(kMDItemAuthors) as? [String])?.joined(separator: "; ")
        m.title = text(kMDItemTitle)
        m.comments = text(kMDItemFinderComment)
        if isImage { m.dateTaken = get(kMDItemContentCreationDate) as? Date }
    }

    private static func readImage(_ url: URL, into m: inout ItemMetadata) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }
        if m.pixelWidth == nil { m.pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue }
        if m.pixelHeight == nil { m.pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue }
        if m.dateTaken == nil, let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            // EXIF carries no zone: the camera's wall clock, read as local time (as Explorer does).
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            m.dateTaken = f.date(from: raw)
        }
        if m.cameraModel == nil, let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraModel = (tiff[kCGImagePropertyTIFFModel] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private static func readMedia(_ url: URL, into m: inout ItemMetadata) {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite, seconds > 0 { m.duration = seconds }
        let tracks = asset.tracks
        if m.bitRate == nil {
            let rate = tracks.reduce(0.0) { $0 + Double($1.estimatedDataRate) }
            if rate > 0 { m.bitRate = rate }
        }
        if let video = tracks.first(where: { $0.mediaType == .video }) {
            if video.nominalFrameRate > 0 { m.frameRate = Double(video.nominalFrameRate) }
            let size = video.naturalSize.applying(video.preferredTransform)
            if m.pixelWidth == nil, size.width != 0 {
                m.pixelWidth = Int(abs(size.width))
                m.pixelHeight = Int(abs(size.height))
            }
        }
    }

    static let commentAttribute = "com.apple.metadata:kMDItemFinderComment"

    /// Finder's comment, from the attribute Finder and Spotlight keep it in.
    public static func finderComment(_ url: URL) -> String? {
        let size = getxattr(url.path, commentAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, commentAttribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read > 0 else { return nil }
        let text = try? PropertyListSerialization.propertyList(from: data, format: nil) as? String
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// The Details pane's edits: Tags and Comments.
public enum MetadataWriter {
    public static func setTags(_ tags: [String], of url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// An empty comment removes it.
    public static func setComment(_ text: String, of url: URL) throws {
        let name = MetadataReader.commentAttribute
        if text.isEmpty {
            if removexattr(url.path, name, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: text, format: .binary, options: 0)
        let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    /// "work, urgent" as typed in the pane: split on commas and semicolons, trimmed, no empties or repeats.
    public static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Metadata per item, read once and kept until the item's modification date changes (or it is
/// invalidated after an edit). Safe from any thread; reads run outside the lock.
public final class MetadataCache: @unchecked Sendable {
    public typealias Reader = @Sendable (URL) -> ItemMetadata

    public static let shared = MetadataCache()

    private struct Entry {
        let stamp: Date?
        let meta: ItemMetadata
    }

    private let lock = NSLock()
    private var store: [String: Entry] = [:]
    private var readCount = 0
    private let reader: Reader
    private let limit: Int

    public init(limit: Int = 60_000, reader: @escaping Reader = MetadataReader.read) {
        self.limit = limit
        self.reader = reader
    }

    /// How many times the reader ran (for tests and the perf log).
    public var reads: Int { lock.withLock { readCount } }

    /// What is cached and still current, without reading.
    public func cached(_ entry: FileEntry) -> ItemMetadata? {
        lock.withLock {
            guard let hit = store[entry.url.path], hit.stamp == entry.modified else { return nil }
            return hit.meta
        }
    }

    /// The cached value, or a fresh read.
    public func metadata(_ entry: FileEntry) -> ItemMetadata {
        if let hit = cached(entry) { return hit }
        let meta = reader(entry.url)
        lock.withLock {
            readCount += 1
            if store.count >= limit { store.removeAll(keepingCapacity: true) }
            store[entry.url.path] = Entry(stamp: entry.modified, meta: meta)
        }
        return meta
    }

    /// Reads every item not cached yet; returns how many were read.
    @discardableResult
    public func fill(_ entries: [FileEntry]) -> Int {
        var n = 0
        for e in entries where cached(e) == nil {
            _ = metadata(e)
            n += 1
        }
        return n
    }

    public func hasAll(_ entries: [FileEntry]) -> Bool { entries.allSatisfy { cached($0) != nil } }

    /// After Tags or Comments change (the modification date does not).
    public func invalidate(_ url: URL) {
        _ = lock.withLock { store.removeValue(forKey: url.path) }
    }
}
