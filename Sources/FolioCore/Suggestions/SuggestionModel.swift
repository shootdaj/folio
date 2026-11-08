import Foundation

/// The kinds of clean-up suggestion, in the order the cards show.
public enum SuggestionKind: String, Sendable, Hashable, CaseIterable {
    case trash, largeUnused, duplicates, oldDownloads, installers, appCaches, derivedData, buildFolders, emptyFolders, brokenLinks

    /// The Trash card offers Empty Trash and Reveal only.
    public var canMoveToTrash: Bool { self != .trash }
    public var canIgnore: Bool { self != .trash }

    /// The place of this kind in card order.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

/// Where the date of a suggestion came from.
public enum DateSource: String, Sendable, Hashable {
    case lastUsed, accessed, modified, added
}

/// One file on one volume: the device and the file number. Hard links share it.
public struct FileID: Sendable, Hashable {
    public let device: Int32
    public let inode: UInt64

    public init(device: Int32, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// What the scan saw of an item. Move to Trash runs `SuggestionVerify.current` and drops an item whose stamp changed.
public struct ItemStamp: Sendable, Hashable {
    public let device: Int32
    public let inode: UInt64
    /// The size in bytes. A folder has none (0).
    public let logical: Int64
    public let modified: Date?

    public init(device: Int32, inode: UInt64, logical: Int64, modified: Date?) {
        self.device = device
        self.inode = inode
        self.logical = logical
        self.modified = modified
    }

    public var fileID: FileID { FileID(device: device, inode: inode) }
}

/// A file or folder in a suggestion.
public struct SuggestionItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let isFolder: Bool
    /// The bytes on disk. This is what a Trash frees, and totals and thresholds use it.
    public let bytes: Int64
    /// The size the Size column shows.
    public let logicalBytes: Int64
    public let date: Date?
    public let dateSource: DateSource?
    public let stamp: ItemStamp
    /// `FilePaths.itemKey` of the URL.
    public let id: String

    public init(url: URL, isFolder: Bool, bytes: Int64, logicalBytes: Int64, date: Date? = nil,
                dateSource: DateSource? = nil, stamp: ItemStamp) {
        self.url = url
        self.isFolder = isFolder
        self.bytes = bytes
        self.logicalBytes = logicalBytes
        self.date = date
        self.dateSource = dateSource
        self.stamp = stamp
        self.id = FilePaths.itemKey(url)
    }
}

/// Why an item is suggested.
public enum SuggestionReason: Sendable, Hashable {
    case notUsedSince(Date, DateSource)
    case inDownloadsSince(Date)
    case installer(ext: String, since: Date)
    case sameContent(copies: Int, sha256: String, mayShareBlocks: Bool)
    case trash(items: Int)
    case cache(appID: String)
    case derivedData(projects: Int)
    case buildFolder(name: String, projectIdleSince: Date)
    case emptyFolder
    case brokenLink(target: String)
}

/// One card row: one item, or for duplicates all copies of one file.
public struct Suggestion: Sendable, Hashable, Identifiable {
    public let kind: SuggestionKind
    /// `dup:<sha256>` for duplicates, else the item's id.
    public let id: String
    /// One item, except for duplicates: every copy.
    public let items: [SuggestionItem]
    /// Duplicates only: the copy that stays.
    public let keep: URL?
    /// The bytes that Move to Trash frees. For duplicates, the copies other than `keep`, or 0 when the copies may share blocks.
    public let bytes: Int64
    public let reason: SuggestionReason

    public init(kind: SuggestionKind, id: String, items: [SuggestionItem], keep: URL? = nil, bytes: Int64, reason: SuggestionReason) {
        self.kind = kind
        self.id = id
        self.items = items
        self.keep = keep
        self.bytes = bytes
        self.reason = reason
    }

    /// The items that Move to Trash may take: all of them, but not the kept copy.
    public var removable: [SuggestionItem] { items.filter { $0.url != keep } }

    /// The same group with another copy kept, and the bytes counted again. Any other URL changes nothing.
    public func keeping(_ url: URL) -> Suggestion {
        guard kind == .duplicates, items.contains(where: { $0.url == url }) else { return self }
        return Suggestion(kind: kind, id: id, items: items, keep: url, bytes: Self.saving(items, keep: url, reason: reason), reason: reason)
    }

    static func saving(_ items: [SuggestionItem], keep: URL?, reason: SuggestionReason) -> Int64 {
        if case .sameContent(_, _, true) = reason { return 0 }
        return items.filter { $0.url != keep }.reduce(0) { $0 + $1.bytes }
    }

    /// The group after some copies went away; nil when fewer than two copies are left.
    func withoutCopies(_ keys: Set<String>) -> Suggestion? {
        let left = items.filter { !keys.contains($0.id) }
        if left.count == items.count { return self }
        guard kind == .duplicates else { return left.isEmpty ? nil : Suggestion(kind: kind, id: id, items: left, keep: keep, bytes: bytes, reason: reason) }
        guard left.count >= 2 else { return nil }
        let kept = left.contains { $0.url == keep } ? keep : left[0].url
        guard case .sameContent(_, let sha, let share) = reason else { return nil }
        let reason = SuggestionReason.sameContent(copies: left.count, sha256: sha, mayShareBlocks: share)
        return Suggestion(kind: kind, id: id, items: left, keep: kept, bytes: Self.saving(left, keep: kept, reason: reason), reason: reason)
    }
}

/// The suggestions of one kind, as one card.
public struct SuggestionCard: Sendable, Hashable {
    public let kind: SuggestionKind
    public let suggestions: [Suggestion]
    public let bytes: Int64
}

/// Why the walk left something out.
public enum SkipReason: String, Sendable, Hashable, CaseIterable {
    case library, dotFolder, gitFolder, package, symlink, mountPoint, otherDevice, cloudOnly, denied, unreadable,
         managedMedia, activeBuildFolder, locked, hardlink, ignored, depthCap, entryCap, timeBudget, hashBudget, spotlightCap
}

/// How many things were left out for each reason, and the first few paths.
public struct ScanSkips: Sendable, Equatable {
    public static let sampleLimit = 5
    public var counts: [SkipReason: Int] = [:]
    public var samples: [SkipReason: [String]] = [:]

    public init() {}

    public mutating func add(_ reason: SkipReason, path: String) {
        counts[reason, default: 0] += 1
        if samples[reason, default: []].count < Self.sampleLimit { samples[reason, default: []].append(path) }
    }

    public func count(_ reason: SkipReason) -> Int { counts[reason] ?? 0 }
}

/// What the scan did.
public struct ScanStats: Sendable, Equatable {
    public var entries = 0
    public var folders = 0
    public var elapsed: TimeInterval = 0
    public var hashedBytes: Int64 = 0
    public var spotlightLookups = 0

    public init() {}
}

/// The result of one scan. The app keeps it in memory only.
public struct SuggestionReport: Sendable {
    /// Kind order, then bytes (largest first), then path.
    public var suggestions: [Suggestion]
    public var scannedAt: Date
    public var home: URL
    public var stats: ScanStats
    public var skips: ScanSkips
    /// Places the scan could not read for lack of a right (the Trash, without Full Disk Access).
    public var denied: [URL]
    /// A cap or a budget stopped a part of the scan.
    public var isPartial: Bool
    public var needsFullDiskAccess: Bool
    public var totalBytes: Int64

    public init(suggestions: [Suggestion] = [], scannedAt: Date = Date(), home: URL, stats: ScanStats = ScanStats(),
                skips: ScanSkips = ScanSkips(), denied: [URL] = [], isPartial: Bool = false,
                needsFullDiskAccess: Bool = false, totalBytes: Int64? = nil) {
        let sorted = Self.sorted(suggestions)
        self.suggestions = sorted
        self.scannedAt = scannedAt
        self.home = home
        self.stats = stats
        self.skips = skips
        self.denied = denied
        self.isPartial = isPartial
        self.needsFullDiskAccess = needsFullDiskAccess
        self.totalBytes = totalBytes ?? sorted.reduce(0) { $0 + $1.bytes }
    }

    /// What Move to Trash and Empty Trash can free together.
    public var reclaimableBytes: Int64 { totalBytes }

    static func sorted(_ list: [Suggestion]) -> [Suggestion] {
        list.sorted { a, b in
            if a.kind != b.kind { return a.kind.order < b.kind.order }
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            return a.id < b.id
        }
    }

    /// The cards that have something to show, in kind order.
    public func cards() -> [SuggestionCard] {
        var byKind: [SuggestionKind: [Suggestion]] = [:]
        for s in suggestions { byKind[s.kind, default: []].append(s) }
        return SuggestionKind.allCases.compactMap { kind in
            guard let list = byKind[kind], !list.isEmpty else { return nil }
            return SuggestionCard(kind: kind, suggestions: list, bytes: list.reduce(0) { $0 + $1.bytes })
        }
    }

    /// The report after the items with these ids (`SuggestionItem.id`) went to the Trash. A duplicate group
    /// with fewer than two copies left goes away. `totalBytes` drops by what the changed rows freed.
    public func removing(keys: Set<String>) -> SuggestionReport {
        guard !keys.isEmpty else { return self }
        var out = self
        out.suggestions = suggestions.compactMap { $0.withoutCopies(keys) }
        out.totalBytes = totalBytes - (suggestions.reduce(0) { $0 + $1.bytes } - out.suggestions.reduce(0) { $0 + $1.bytes })
        return out
    }

    /// The report with these suggestions back in it (Undo). A group that is still in the report is replaced.
    public func restoring(_ list: [Suggestion]) -> SuggestionReport {
        guard !list.isEmpty else { return self }
        var out = self
        let back = Set(list.map(\.id))
        let kept = suggestions.filter { !back.contains($0.id) }
        out.suggestions = Self.sorted(kept + list)
        out.totalBytes = totalBytes + (out.suggestions.reduce(0) { $0 + $1.bytes } - suggestions.reduce(0) { $0 + $1.bytes })
        return out
    }

    /// The URLs without any that lie inside another URL of the list, and without repeats. Order stays.
    public static func outermost(_ urls: [URL]) -> [URL] {
        let keys = FilePaths.itemKeys(urls)
        let all = Set(keys)
        var seen: Set<String> = []
        var out: [URL] = []
        for (url, key) in zip(urls, keys) where seen.insert(key).inserted {
            var inside = false
            var path = Substring(key)
            while let slash = path.lastIndex(of: "/"), slash != path.startIndex {
                path = path[..<slash]
                if all.contains(String(path)) { inside = true; break }
            }
            if !inside { out.append(url) }
        }
        return out
    }
}

/// Run right before Move to Trash: a path may now hold another file than the scan saw.
public enum SuggestionVerify {
    /// The items whose device, inode, size and modified date are still the ones the scan saw.
    public static func current(_ items: [SuggestionItem], fs: any ScanFileSystem) -> [SuggestionItem] {
        items.filter { fs.stamp($0.url) == $0.stamp }
    }
}
