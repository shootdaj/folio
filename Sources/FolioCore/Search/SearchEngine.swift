import Foundation

/// Where a search looks.
public enum SearchLocation: Sendable, Equatable {
    /// A folder and, unless Current folder is picked, its subfolders.
    case folder(URL)
    /// Home: the home folder and the indexed places (Spotlight only, fast, like Explorer's Home).
    case home
    /// This PC: every volume, Spotlight for the indexed ones and the walk for the rest.
    case thisPC
}

public struct SearchRequest: Sendable {
    public var query: QueryNode
    public var location: SearchLocation
    /// All subfolders (true) or Current folder.
    public var recursive = true
    /// View > Hidden items: dot files and hidden items take part (and need the walk).
    public var includeHidden = false
    /// Search options > File contents: the walk reads files (Spotlight reads contents where it indexes).
    public var fileContents = false
    /// Search options > System files: the walk goes into system folders.
    public var systemFiles = false

    public init(query: QueryNode, location: SearchLocation) {
        self.query = query
        self.location = location
    }
}

/// What a running search reports: hits not reported before, progress, and whether it is finished.
public struct SearchUpdate: Sendable {
    public var hits: [SearchHit]
    public var progress: Double
    public var done: Bool
    public var total: Int
    /// Seconds from start to the first hit, and to the end (when done).
    public var firstHitAfter: Double?
    public var elapsed: Double
    public var walked: Bool
}

/// Whether Spotlight indexes a volume: `mdutil -s` once per volume, network volumes never.
public enum VolumeIndexing {
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    public static func isIndexed(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeIsLocalKey])
        if values?.volumeIsLocal == false { return false }
        let volume = values?.volume?.path ?? "/"
        lock.lock()
        if let known = cache[volume] { lock.unlock(); return known }
        lock.unlock()
        let indexed = mdutilSaysEnabled(volume)
        lock.lock()
        cache[volume] = indexed
        lock.unlock()
        return indexed
    }

    static func mdutilSaysEnabled(_ volume: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        p.arguments = ["-s", volume]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return true }
        p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parse(text)
    }

    /// "Indexing enabled." means indexed; disabled or an unknown state means the walk covers it.
    public static func parse(_ mdutilOutput: String) -> Bool {
        mdutilOutput.lowercased().contains("indexing enabled")
    }
}

/// Runs one search: Spotlight (NSMetadataQuery scoped to the place) and, in parallel, the live walk for
/// what Spotlight skips; merges both by path and reports in batches until both are done. Cancel stops
/// both (a new keystroke cancels the query before).
public final class SearchEngine: @unchecked Sendable {
    public let request: SearchRequest
    private let onUpdate: @Sendable (SearchUpdate) -> Void
    private let queue = DispatchQueue(label: "folio.search.merge")
    private var merger = SearchMerger()
    private var pending: [SearchHit] = []
    private var flushScheduled = false
    private var spotlightDone = false
    private var walkDone = false
    private var walkProgress = 0.0
    private var walks = false
    private var started = Date()
    private var firstHit: Double?
    private var finished = false
    private let cancelLock = NSLock()
    private var cancelledFlag = false
    private var spotlight: SpotlightRunner?

    public init(_ request: SearchRequest, onUpdate: @escaping @Sendable (SearchUpdate) -> Void) {
        self.request = request
        self.onUpdate = onUpdate
    }

    public var isCancelled: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }
        return cancelledFlag
    }

    public func cancel() {
        cancelLock.lock()
        cancelledFlag = true
        cancelLock.unlock()
        spotlight?.stop()
    }

    /// Plans and starts both halves off the calling thread (`mdutil` may take a moment the first time).
    public func start() {
        started = Date()
        queue.async { [self] in begin() }
    }

    private func begin() {
        guard !isCancelled else { return }
        let request = self.request
        let matcher = SearchMatcher(request.query)
        // Plan: what Spotlight covers and what the walk covers.
        var scopes: [Any] = []
        var roots: [URL] = []
        var scopeKey: String?
        switch request.location {
        case .folder(let url):
            scopes = [url]
            scopeKey = FilePaths.folderKey(url)
            if SearchPlan.needsWalk(url.path, volumeIndexed: VolumeIndexing.isIndexed(url), includeHidden: request.includeHidden) {
                roots = [url]
            }
        case .home:
            scopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
            // The home folder is walked only where Spotlight has no index of it.
            let home = FileManager.default.homeDirectoryForCurrentUser
            if !VolumeIndexing.isIndexed(home) || request.includeHidden { roots = [home] }
        case .thisPC:
            scopes = [NSMetadataQueryLocalComputerScope]
            let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey],
                                                                options: [.skipHiddenVolumes]) ?? []
            roots = volumes.filter { v in
                (try? v.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal != false && !VolumeIndexing.isIndexed(v)
            }
        }
        walks = !roots.isEmpty
        if !walks { walkDone = true }

        if let predicate = SpotlightPredicate.compile(request.query) {
            let runner = SpotlightRunner(predicate: predicate, scopes: scopes, matcher: matcher,
                                         currentFolder: request.recursive ? nil : scopeKey,
                                         includeHidden: request.includeHidden,
                                         isCancelled: { [weak self] in self?.isCancelled ?? true },
                                         onHits: { [weak self] hits in self?.ingest(hits, progress: nil) },
                                         onDone: { [weak self] in self?.queue.async { self?.spotlightDone = true; self?.flush() } })
            spotlight = runner
            runner.start()
        } else {
            spotlightDone = true
        }

        if walks {
            var options = SearchWalk.Options()
            options.recursive = request.recursive
            options.includeHidden = request.includeHidden
            options.fileContents = request.fileContents
            options.systemFiles = request.systemFiles
            let walk = SearchWalk(roots: roots, matcher: matcher, options: options)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                walk.run(isCancelled: { self?.isCancelled ?? true }) { hits, progress in
                    self?.ingest(hits, progress: progress)
                }
                self?.queue.async { self?.walkDone = true; self?.flush() }
            }
        }
        if !walks && spotlight == nil { flush() }
    }

    private func ingest(_ hits: [SearchHit], progress: Double?) {
        queue.async { [self] in
            guard !isCancelled else { return }
            if let progress { walkProgress = progress }
            let fresh = merger.merge(hits)
            if !fresh.isEmpty, firstHit == nil { firstHit = Date().timeIntervalSince(started) }
            pending += fresh
            if !flushScheduled {
                flushScheduled = true
                queue.asyncAfter(deadline: .now() + 0.08) { [self] in flush() }
            }
        }
    }

    /// On `queue`: sends what is pending, and the end once both halves are done.
    private func flush() {
        flushScheduled = false
        guard !isCancelled, !finished else { return }
        let done = spotlightDone && walkDone
        if done { finished = true }
        let progress = done ? 1 : (walks ? walkProgress * (spotlightDone ? 1 : 0.9) : 0)
        let update = SearchUpdate(hits: pending, progress: progress, done: done, total: merger.count, firstHitAfter: firstHit,
                                  elapsed: Date().timeIntervalSince(started), walked: walks)
        pending = []
        onUpdate(update)
    }
}

/// NSMetadataQuery on its own operation queue (results read off the main thread), checked again with
/// the matcher as they arrive; stopped after the first gathering (no live updates).
final class SpotlightRunner: @unchecked Sendable {
    private let predicate: String
    private let scopes: [Any]
    private let matcher: SearchMatcher
    private let currentFolder: String?
    private let includeHidden: Bool
    private let isCancelled: () -> Bool
    private let onHits: ([SearchHit]) -> Void
    private let onDone: () -> Void
    private let opQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var processed = 0
    private var kinds: [String: String] = [:]
    private var ended = false

    init(predicate: String, scopes: [Any], matcher: SearchMatcher, currentFolder: String?, includeHidden: Bool,
         isCancelled: @escaping () -> Bool, onHits: @escaping ([SearchHit]) -> Void, onDone: @escaping () -> Void) {
        self.predicate = predicate
        self.scopes = scopes
        self.matcher = matcher
        self.currentFolder = currentFolder
        self.includeHidden = includeHidden
        self.isCancelled = isCancelled
        self.onHits = onHits
        self.onDone = onDone
    }

    func start() {
        opQueue.addOperation { [self] in
            guard let p = NSPredicate(fromMetadataQueryString: predicate) else { finish(); return }
            let q = NSMetadataQuery()
            q.predicate = p
            q.searchScopes = scopes
            q.notificationBatchingInterval = 0.1
            q.operationQueue = opQueue
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: q, queue: opQueue) { [weak self] _ in
                self?.read()
            })
            observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: opQueue) { [weak self] _ in
                self?.read()
                self?.finish()
            })
            query = q
            if !q.start() { finish() }
        }
    }

    func stop() {
        opQueue.addOperation { [self] in
            query?.stop()
            finish()
        }
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        query = nil
        onDone()
    }

    private func read() {
        guard let q = query, !isCancelled() else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        let n = q.resultCount
        guard processed < n else { return }
        var hits: [SearchHit] = []
        for i in processed..<n {
            if isCancelled() { break }
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            if let currentFolder, FilePaths.parentKey(ofItemKey: FilePaths.itemKey(url)) != currentFolder { continue }
            guard (try? url.checkResourceIsReachable()) == true else { continue }
            let entry = FolderListing.entry(for: url, kinds: &kinds)
            if !includeHidden && entry.isHidden { continue }
            let subject = FileSubject(entry: entry, policy: .spotlight(cap: 2 * 1024 * 1024))
            subject.given["tags"] = item.value(forAttribute: "kMDItemUserTags") as? [String] ?? []
            subject.given["authors"] = item.value(forAttribute: "kMDItemAuthors") as? [String] ?? []
            if let t = item.value(forAttribute: "kMDItemTitle") as? String { subject.given["title"] = t }
            if let t = item.value(forAttribute: "kMDItemContentType") as? String { subject.given["type"] = t }
            if matcher.matches(subject, trustUnknown: true) {
                hits.append(SearchHit(entry: entry, score: matcher.score(subject)))
            }
        }
        processed = n
        if !hits.isEmpty { onHits(hits) }
    }
}
