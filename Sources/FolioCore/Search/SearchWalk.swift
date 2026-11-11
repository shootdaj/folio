import CoreServices
import Foundation

/// One result: the row the list shows and its relevance.
public struct SearchHit: Sendable, Equatable {
    public let entry: FileEntry
    public let score: Int

    public init(entry: FileEntry, score: Int) {
        self.entry = entry
        self.score = score
    }
}

/// A file on disk as the matcher sees it; everything past the listing's values is read on first use.
public final class FileSubject: SearchSubject {
    public let entry: FileEntry
    /// How contents are read: the walk reads them only with File contents on; a Spotlight result is
    /// read to check what Spotlight matched, when it is text and small enough.
    public enum ContentPolicy: Sendable { case read(cap: Int), off, spotlight(cap: Int) }
    let policy: ContentPolicy
    /// Authors and title come from Spotlight's store (MDItem); only read when the query names them.
    let readsProperties: Bool
    /// Values Spotlight already handed over (NSMetadataItem attributes).
    var given: [String: Any] = [:]

    public init(entry: FileEntry, policy: ContentPolicy, readsProperties: Bool = false) {
        self.entry = entry
        self.policy = policy
        self.readsProperties = readsProperties
    }

    public var name: String { entry.name }
    public var path: String { entry.url.path }
    public var isFolder: Bool { entry.isFolder }
    public var isLink: Bool { entry.isLink }
    public var size: Int64? { entry.size }
    public var modified: Date? { entry.modified }
    public var typeText: String { entry.kind }

    private lazy var values: URLResourceValues? = try? entry.url.resourceValues(forKeys: [.creationDateKey, .contentTypeKey, .tagNamesKey])
    public var created: Date? { (given["created"] as? Date) ?? values?.creationDate }
    public var contentType: String? { (given["type"] as? String) ?? values?.contentType?.identifier }
    /// A plain word is also looked for in the tags, so every item whose name does not match asks for
    /// them: one `getxattr` says first whether the item has any (most have none).
    public var tags: [String] {
        if let t = given["tags"] as? [String] { return t }
        // The listing usually knows the item has no extended attributes at all: then no disk call.
        guard entry.mayHaveTags, FileTags.hasTags(entry.url) else { return [] }
        return values?.tagNames ?? []
    }

    private lazy var mdItem: MDItem? = readsProperties ? MDItemCreateWithURL(kCFAllocatorDefault, entry.url as CFURL) : nil
    public var authors: [String] {
        if let a = given["authors"] as? [String] { return a }
        guard let item = mdItem else { return [] }
        return (MDItemCopyAttribute(item, kMDItemAuthors) as? [String]) ?? []
    }
    public var title: String? {
        if let t = given["title"] as? String { return t }
        guard let item = mdItem else { return nil }
        return MDItemCopyAttribute(item, kMDItemTitle) as? String
    }

    private lazy var body: SearchContent = readBody()
    public var content: SearchContent { body }

    private func readBody() -> SearchContent {
        switch policy {
        case .off: return .none
        case .read(let cap): return Self.text(at: entry.url, cap: cap).map(SearchContent.text) ?? .none
        case .spotlight(let cap): return Self.text(at: entry.url, cap: cap).map(SearchContent.text) ?? .unknown
        }
    }

    /// The file as text when it looks like text (no NUL bytes in its first 4 KB, like grep) and is no
    /// bigger than `cap`; nil otherwise.
    public static func text(at url: URL, cap: Int) -> String? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= cap,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if data.prefix(4096).contains(0) { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Which places the live walk covers, because Spotlight skips them (tested on this Mac): dot folders
/// (so the Trash too), /private/tmp and /private/var, volumes with indexing off and network shares.
public enum SearchPlan {
    public static let unindexedRoots = ["/private/tmp", "/private/var", "/tmp", "/var", "/cores", "/dev"]

    /// True for a path Spotlight does not index whatever the volume says.
    public static func isSkippedBySpotlight(_ path: String) -> Bool {
        if unindexedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Does a search of `folder` need the walk: always where Spotlight has nothing; on an indexed volume
    /// only with hidden items shown (dot files are never indexed, and hidden items show only then).
    public static func needsWalk(_ folder: String, volumeIndexed: Bool, includeHidden: Bool) -> Bool {
        if !volumeIndexed || isSkippedBySpotlight(folder) { return true }
        return includeHidden
    }

    /// System folders the walk skips unless System files is on (never the folder being searched or
    /// one it is inside).
    public static func isSystemFolder(_ path: String, home: String) -> Bool {
        let system = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/cores", "/dev", "/opt", home + "/Library"]
        return system.contains(path)
    }
}

/// Merges hits from Spotlight and the walk by path: the first one in wins, later copies are dropped.
public struct SearchMerger: Sendable {
    private var seen: Set<String> = []
    public private(set) var hits: [SearchHit] = []

    public init() {}

    public var count: Int { hits.count }

    /// The hits not seen before, in the order given.
    @discardableResult
    public mutating func merge(_ batch: [SearchHit]) -> [SearchHit] {
        var fresh: [SearchHit] = []
        for h in batch where seen.insert(FilePaths.itemKey(h.entry.url)).inserted {
            fresh.append(h)
        }
        hits += fresh
        return fresh
    }

    public func contains(_ url: URL) -> Bool { seen.contains(FilePaths.itemKey(url)) }

    /// Relevance first, then names as Finder sorts them (StandardOrder: each name made a Core
    /// Foundation string once, not on every comparison).
    public static func ranked(_ hits: [SearchHit]) -> [SearchHit] {
        let names = hits.map { StandardOrder.key($0.entry.name) }
        let order = StandardOrder()
        return hits.indices.sorted { i, j in
            let (a, b) = (hits[i], hits[j])
            if a.score != b.score { return a.score > b.score }
            switch order.compare(names[i], names[j]) {
            case -1: return true
            case 1: return false
            default: return a.entry.url.path < b.entry.url.path
            }
        }.map { hits[$0] }
    }
}

/// The live walk: lists the folder (and its subfolders), checks every item against the query, and
/// hands over hits in batches. Reads contents (grep-like, size-capped) when File contents is on.
public struct SearchWalk: Sendable {
    public struct Options: Sendable {
        public var recursive = true
        public var includeHidden = false
        public var systemFiles = false
        public var fileContents = false
        /// Search options > Zipped (compressed) folders: the walk also lists what each zip holds.
        public var zippedFolders = false
        public var contentCap = 4 * 1024 * 1024
        public var home = FileManager.default.homeDirectoryForCurrentUser.path
        /// Folders not to go into (already covered by Spotlight, or another volume).
        public var skip: Set<String> = []

        public init() {}
    }

    public let roots: [URL]
    public let matcher: SearchMatcher
    public let options: Options

    public init(roots: [URL], matcher: SearchMatcher, options: Options) {
        self.roots = roots
        self.matcher = matcher
        self.options = options
    }

    /// Progress is folders listed over folders found so far: it crawls as the tree unfolds.
    public func run(isCancelled: () -> Bool, onBatch: ([SearchHit], Double) -> Void) {
        var pending = roots
        var listed = 0
        var batch: [SearchHit] = []
        var lastSend = Date()
        let readsProperties = matcher.query.terms.contains { $0.property == .author || $0.property == .title }
        let policy: FileSubject.ContentPolicy = options.fileContents ? .read(cap: options.contentCap) : .off
        while let dir = pending.popLast() {
            if isCancelled() { return }
            // The window's own listing: one bulk read per folder, kinds shared with every window.
            let entries = (try? FolderListing.list(dir, includeHidden: options.includeHidden)) ?? []
            listed += 1
            for entry in entries {
                if isCancelled() { return }
                let url = entry.url
                if !options.includeHidden && entry.isHidden { continue }
                let subject = FileSubject(entry: entry, policy: policy, readsProperties: readsProperties)
                if matcher.matches(subject, trustUnknown: false) {
                    batch.append(SearchHit(entry: entry, score: matcher.score(subject)))
                }
                if options.zippedFolders, options.recursive, !entry.isFolder, ArchiveNaming.isBrowsable(url) {
                    batch += zipHits(url)
                }
                if options.recursive, entry.isFolder, !entry.isLink, !options.skip.contains(url.path),
                   options.systemFiles || !SearchPlan.isSystemFolder(url.path, home: options.home) {
                    pending.append(url)
                }
            }
            if batch.count >= 250 || (!batch.isEmpty && Date().timeIntervalSince(lastSend) > 0.08) {
                onBatch(batch, Double(listed) / Double(listed + pending.count))
                batch = []
                lastSend = Date()
            }
        }
        onBatch(batch, 1)
    }

    /// Every entry of a zip, checked like a file (names, sizes, dates, kinds; contents are not read).
    private func zipHits(_ archive: URL) -> [SearchHit] {
        guard let zip = try? ZipArchive(url: archive) else { return [] }
        var hits: [SearchHit] = []
        var pending = [""]
        while let folder = pending.popLast() {
            for entry in ZipFolder.rows(zip, folder) {
                if !options.includeHidden && entry.isHidden { continue }
                let subject = FileSubject(entry: entry, policy: .off, readsProperties: false)
                if matcher.matches(subject, trustUnknown: false) {
                    hits.append(SearchHit(entry: entry, score: matcher.score(subject)))
                }
                if entry.isFolder {
                    pending.append(String(entry.url.path.dropFirst(archive.path.count + 1)))
                }
            }
        }
        return hits
    }

    /// Every hit at once (tests and small trees).
    public func collect() -> [SearchHit] {
        var out: [SearchHit] = []
        run(isCancelled: { false }) { hits, _ in out += hits }
        return out
    }
}
