import Foundation

/// One mounted volume for the This PC list: name, size and free space, the 24-segment bar, and what
/// kind of volume it is (the startup disk, removable, a disk image, a network share).
public struct VolumeCapacity: Sendable, Equatable {
    public let name: String
    public let path: String
    public let total: Int64
    public let free: Int64
    public let isRoot: Bool
    public let isRemovable: Bool
    /// Disk images, USB sticks and discs: macOS can eject them.
    public let isEjectable: Bool
    /// False for network shares (SMB, AFP, NFS, WebDAV, FTP).
    public let isLocal: Bool
    public let isInternal: Bool

    public init(name: String, path: String, total: Int64, free: Int64, isRoot: Bool = false,
                isRemovable: Bool = false, isEjectable: Bool = false, isLocal: Bool = true, isInternal: Bool = false) {
        self.name = name
        self.path = path
        self.total = total
        self.free = free
        self.isRoot = isRoot
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isLocal = isLocal
        self.isInternal = isInternal
    }

    public var isNetwork: Bool { !isLocal }

    /// The Eject button (Disconnect for a share): never on the startup disk.
    public var canEject: Bool { !isRoot && (isEjectable || isRemovable || isNetwork) }

    /// Explorer turns the bar red from 90% used.
    public var isNearlyFull: Bool { total > 0 && usedFraction >= 0.9 }

    public var used: Int64 { max(0, total - free) }

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public var percentText: String { "\(Int((usedFraction * 100).rounded()))%" }

    /// D1's segmented bar: `max(1, round(pct / 100 * 24))` lit segments, none when the size is unknown.
    public func litSegments(of count: Int = 24) -> Int {
        guard total > 0 else { return 0 }
        return min(count, max(1, Int((usedFraction * Double(count)).rounded())))
    }

    public var freeText: String { ByteText.storage(free) + " free" }
    public var totalText: String { "of " + ByteText.storage(total) }

    public static let resourceKeys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeURLKey,
        .volumeIsRootFileSystemKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey,
        .volumeIsInternalKey,
    ]

    /// The volume that holds `url`. Reads only volume attributes, never the folder's contents.
    public static func read(_ url: URL) -> VolumeCapacity? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
        let root = values.volume ?? url
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        let name = values.volumeLocalizedName ?? values.volumeName ?? root.lastPathComponent
        let path = root.standardizedFileURL.path
        return VolumeCapacity(name: name, path: path, total: total, free: free,
                              isRoot: values.volumeIsRootFileSystem ?? (path == "/"),
                              isRemovable: values.volumeIsRemovable ?? false,
                              isEjectable: values.volumeIsEjectable ?? false,
                              isLocal: values.volumeIsLocal ?? true,
                              isInternal: values.volumeIsInternal ?? false)
    }

    /// Every mounted, visible volume: the startup disk first, then /Volumes.
    public static func mounted() -> [VolumeCapacity] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(resourceKeys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(read)
    }
}

/// This PC and Network: the local volumes (the startup disk first, then internal ones, then the rest
/// by name) and the mounted network shares by name.
public enum VolumeList {
    public static func arrange(_ volumes: [VolumeCapacity]) -> (drives: [VolumeCapacity], network: [VolumeCapacity]) {
        func rank(_ v: VolumeCapacity) -> Int { v.isRoot ? 0 : v.isInternal ? 1 : 2 }
        let drives = volumes.filter(\.isLocal).sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let network = volumes.filter(\.isNetwork).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (drives, network)
    }
}

/// Byte counts as text, without locale surprises.
public enum ByteText {
    /// Explorer's Size column and status bar: kilobytes, rounded up, 1 KB minimum for a non-empty file.
    public static func kilobytes(_ bytes: Int64) -> String {
        let kb = bytes <= 0 ? 0 : (bytes + 1023) / 1024
        return grouped(kb) + " KB"
    }

    /// Disk sizes in decimal units as Finder shows them: 81.4 GB, 926 GB, 2.0 TB, 512 MB.
    public static func storage(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1e12 { return String(format: "%.1f TB", b / 1e12) }
        if b >= 100e9 { return String(format: "%.0f GB", b / 1e9) }
        if b >= 1e9 { return String(format: "%.1f GB", b / 1e9) }
        return String(format: "%.0f MB", b / 1e6)
    }

    /// 50000 as "50,000".
    public static func grouped(_ n: Int64) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    public static func grouped(_ n: Int) -> String { grouped(Int64(n)) }
}

/// One pinned folder in the sidebar's Quick access group.
public struct QuickAccessPlace: Sendable, Equatable {
    /// The last folder name, drawn bright.
    public let title: String
    /// The part before it, drawn dim ("Anshul/").
    public let prefix: String
    public let path: String
}

public enum QuickAccess {
    /// D1's favourites, Anshul/Code first. Pinning and reordering arrive in milestone 5.
    public static let defaults = ["Anshul/Code", "Downloads", "Desktop", "Documents", "Pictures", "Movies"]

    public static func places(home: URL) -> [QuickAccessPlace] {
        defaults.map { relative in
            let slash = relative.lastIndex(of: "/")
            let title = slash.map { String(relative[relative.index(after: $0)...]) } ?? relative
            let prefix = slash.map { String(relative[...$0]) } ?? ""
            let base = home.path.hasSuffix("/") ? String(home.path.dropLast()) : home.path
            return QuickAccessPlace(title: title, prefix: prefix, path: base + "/" + relative)
        }
    }
}
