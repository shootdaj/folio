import Darwin
import Foundation

/// A file the duplicate finder may hash: at or above the size floor, in a place the walk offers.
struct DuplicateCandidate: Sendable {
    let item: SuggestionItem
    let linkCount: UInt32

    var fileID: FileID { item.stamp.fileID }
}

/// What one walk found. The duplicate finder (a later step) takes `duplicateCandidates` and removes the
/// items its groups claim with `excluding(keys:)`, because a duplicate wins over every loose-file kind.
struct WalkResult: Sendable {
    var suggestions: [Suggestion] = []
    var duplicateCandidates: [DuplicateCandidate] = []
    var stats = ScanStats()
    var skips = ScanSkips()
    /// Fixed places that could not be read for lack of a right.
    var denied: [URL] = []
    /// A cap or the time budget stopped the walk.
    var isPartial = false
    var needsFullDiskAccess = false
    var cancelled = false

    /// The result without the single-item suggestions whose item id is in `keys`.
    func excluding(keys: Set<String>) -> WalkResult {
        var out = self
        out.suggestions = suggestions.filter { s in s.items.count != 1 || !keys.contains(s.items[0].id) }
        return out
    }
}

/// The scan thread's I/O policy: cloud-only files are not downloaded by a read, and the disk work is
/// low priority. The old values come back at the end, because GCD reuses threads.
enum IOPolicy {
    // From <sys/resource.h>, in case the macros do not import.
    private static let typeDisk = IOPOL_TYPE_DISK
    private static let typeMaterialize = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
    private static let scope = IOPOL_SCOPE_THREAD

    static func scoped<T>(_ body: () -> T) -> T {
        let oldDisk = getiopolicy_np(typeDisk, scope)
        let oldMaterialize = getiopolicy_np(typeMaterialize, scope)
        _ = setiopolicy_np(typeMaterialize, scope, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        // The kernel refuses this on a thread that has a quality of service. The walk then goes on without it.
        _ = setiopolicy_np(typeDisk, scope, IOPOL_UTILITY)
        defer {
            if oldDisk >= 0 { _ = setiopolicy_np(typeDisk, scope, oldDisk) }
            if oldMaterialize >= 0 { _ = setiopolicy_np(typeMaterialize, scope, oldMaterialize) }
        }
        return body()
    }
}

/// The size of a folder tree. A hard link counts once. Nothing is followed: links are counted as links,
/// mount points and cloud-only folders are not entered.
enum SubtreeSizer {
    struct Measure {
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var files = 0
        /// The entries directly in the root, without the files the Mac keeps for itself.
        var topLevel = 0
        /// The budget or a cancel stopped the count.
        var partial = false
        /// Why the root could not be read.
        var rootError: ScanReadError?
    }

    /// `tick` is called for every entry with the folder it is in. It returns false to stop.
    static func measure(_ root: URL, fs: any ScanFileSystem, tick: (URL) -> Bool) -> Measure {
        var m = Measure()
        var seen: Set<FileID> = []
        var stack = [root]
        while let dir = stack.popLast() {
            let entries: [ScanEntry]
            do {
                entries = try fs.list(dir)
            } catch {
                if dir == root { m.rootError = error }
                continue
            }
            for e in entries {
                guard tick(dir) else {
                    m.partial = true
                    return m
                }
                if dir == root && !ProtectedFiles.isProtected(name: e.name) { m.topLevel += 1 }
                if e.type == .folder {
                    m.allocated += e.allocated
                    if !e.isMountPoint && !e.isDataless { stack.append(dir.appendingPathComponent(e.name, isDirectory: true)) }
                    continue
                }
                if e.linkCount > 1, !seen.insert(e.fileID).inserted { continue }
                m.allocated += e.allocated
                m.logical += e.logical
                m.files += 1
            }
        }
        return m
    }
}

/// The scan of the home folder: the fixed places first (pass 1), then one walk of home (pass 2) that
/// feeds every rule. It reads a file's attributes only, never its content. Run it on the scan thread.
final class SuggestionWalk {
    private enum Work {
        case open(URL, ScanEntry?, Int)
        case close
    }

    /// A folder being walked. Only the ancestors of the current folder have one.
    private struct Frame {
        let entry: ScanEntry?
        let url: URL
        /// `FilePaths.folderKey`, kept only when something is ignored.
        let key: String?
        let eligible: Bool
        var hasContent = false
        /// Empty folders below that may be reported if this folder has content.
        var emptyKids: [Suggestion] = []
    }

    private static let customIcon: UInt16 = 0x0400

    private let config: SuggestionConfig
    private let fs: any ScanFileSystem
    private let ignores: SuggestionIgnores.Snapshot
    private let isCancelled: () -> Bool

    private var result = WalkResult()
    private var start: TimeInterval = 0
    private var stopped = false
    private var lookups = 0
    private var pendingOpens = 0
    private var aliasResolves = 0
    private var homeDevice: Int32?
    private let homePath: String
    private let downloadsPath: String
    private let desktopPath: String
    private let managedPrefixes: [String]
    private let standardPaths: Set<String>
    private let cutoffUnused: Date

    init(config: SuggestionConfig, fs: any ScanFileSystem, ignores: SuggestionIgnores.Snapshot, isCancelled: @escaping () -> Bool) {
        self.config = config
        self.fs = fs
        self.ignores = ignores
        self.isCancelled = isCancelled
        var home = config.home.path
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        homePath = home
        downloadsPath = home + "/Downloads"
        desktopPath = home + "/Desktop"
        managedPrefixes = config.managedMedia.map { home + "/" + $0 }
        standardPaths = Set(config.standardFolders.map { home + "/" + $0 })
        cutoffUnused = config.now.addingTimeInterval(-config.unusedFor)
    }

    /// The size of the Trash alone, as the card of pass 1 would show it.
    func trashOnly() -> WalkResult {
        IOPolicy.scoped {
            start = config.elapsed()
            trash()
            result.stats.elapsed = config.elapsed() - start
            result.cancelled = result.cancelled || isCancelled()
            return result
        }
    }

    /// Runs both passes. `onFixedPlaces` gets the cards of pass 1 before the walk starts. `onWalk` gets the
    /// folders listed so far, the folders still waiting, the entries seen and the folder being listed.
    func run(onFixedPlaces: ([Suggestion]) -> Void = { _ in },
             onWalk: (_ listed: Int, _ pending: Int, _ entries: Int, _ current: String) -> Void = { _, _, _, _ in }) -> WalkResult {
        IOPolicy.scoped {
            start = config.elapsed()
            homeDevice = fs.stamp(config.home)?.device
            fixedPlaces()
            onFixedPlaces(result.suggestions)
            if !stopped { walkHome(onWalk) }
            result.stats.elapsed = config.elapsed() - start
            result.cancelled = result.cancelled || isCancelled()
            return result
        }
    }

    private func wants(_ kind: SuggestionKind) -> Bool { config.kinds.contains(kind) }

    /// Counts one entry against the caps. False means stop.
    private func tick(_ at: URL) -> Bool {
        if stopped { return false }
        if isCancelled() {
            result.cancelled = true
            stopped = true
            return false
        }
        result.stats.entries += 1
        if result.stats.entries > config.maxEntries { return stop(.entryCap, at) }
        if config.elapsed() - start > config.timeBudget { return stop(.timeBudget, at) }
        return true
    }

    private func stop(_ reason: SkipReason, _ at: URL) -> Bool {
        stopped = true
        result.isPartial = true
        result.skips.add(reason, path: at.path)
        return false
    }

    // MARK: Pass 1, the fixed places

    private func measure(_ url: URL) -> SubtreeSizer.Measure {
        let m = SubtreeSizer.measure(url, fs: fs, tick: tick)
        if m.partial && !result.cancelled { result.isPartial = true }
        return m
    }

    private func isIgnored(_ url: URL) -> Bool {
        !ignores.paths.isEmpty && ignores.covers(FilePaths.itemKey(url))
    }

    private func folderItem(_ url: URL, _ m: SubtreeSizer.Measure, date: Date? = nil, source: DateSource? = nil) -> SuggestionItem? {
        guard let stamp = fs.stamp(url) else { return nil }
        return SuggestionItem(url: url, isFolder: true, bytes: m.allocated, logicalBytes: m.logical, date: date ?? stamp.modified,
                              dateSource: source ?? .modified, stamp: stamp)
    }

    private func fixedPlaces() {
        if wants(.trash) { trash() }
        if wants(.appCaches) {
            for place in config.cachePlaces {
                if place.hasSuffix("/*") {
                    cacheChildren(config.home.appendingPathComponent(String(place.dropLast(2)), isDirectory: true))
                } else {
                    cache(config.home.appendingPathComponent(place, isDirectory: true), app: (place as NSString).lastPathComponent)
                }
            }
        }
        if wants(.derivedData) { derivedData() }
    }

    private func denied(_ url: URL) {
        result.denied.append(url)
        result.needsFullDiskAccess = true
    }

    private func trash() {
        let url = RecycleBin.trashFolder(home: config.home)
        let m = measure(url)
        if m.rootError == .denied { denied(url) }
        guard m.rootError == nil, m.allocated > 0 || m.topLevel > 0, let item = folderItem(url, m) else { return }
        result.suggestions.append(Suggestion(kind: .trash, id: item.id, items: [item], bytes: m.allocated, reason: .trash(items: m.topLevel)))
    }

    private func cache(_ url: URL, app: String) {
        guard !isIgnored(url) else {
            result.skips.add(.ignored, path: url.path)
            return
        }
        let m = measure(url)
        if m.rootError == .denied { denied(url) }
        guard m.rootError == nil, m.allocated >= config.cacheMin, let item = folderItem(url, m) else { return }
        result.suggestions.append(Suggestion(kind: .appCaches, id: item.id, items: [item], bytes: m.allocated, reason: .cache(appID: app)))
    }

    private func cacheChildren(_ base: URL) {
        let entries: [ScanEntry]
        do {
            entries = try fs.list(base)
        } catch {
            if error == .denied { denied(base) }
            return
        }
        for e in entries where e.type == .folder && !e.isDataless && !e.isMountPoint && !stopped {
            if config.cacheExcludedPrefixes.contains(where: { e.name.hasPrefix($0) }) { continue }
            cache(base.appendingPathComponent(e.name, isDirectory: true), app: e.name)
        }
    }

    private func derivedData() {
        let url = config.home.appendingPathComponent(config.derivedData, isDirectory: true)
        guard !isIgnored(url) else {
            result.skips.add(.ignored, path: url.path)
            return
        }
        let m = measure(url)
        if m.rootError == .denied { denied(url) }
        guard m.rootError == nil, m.allocated >= config.cacheMin, let item = folderItem(url, m) else { return }
        // Xcode names a project's folder Name-hash. The other folders in it are shared caches.
        let projects = ((try? fs.list(url)) ?? []).filter { $0.type == .folder && $0.name.contains("-") }.count
        result.suggestions.append(Suggestion(kind: .derivedData, id: item.id, items: [item], bytes: m.allocated,
                                             reason: .derivedData(projects: projects)))
    }

    // MARK: Pass 2, the walk of home

    private func isManaged(_ path: String) -> Bool {
        managedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func isEligibleEmpty(_ entry: ScanEntry?, _ url: URL) -> Bool {
        guard wants(.emptyFolders), let entry, !entry.isLocked, !entry.isPackage,
              entry.finderFlags & Self.customIcon == 0, !standardPaths.contains(url.path), !isManaged(url.path),
              let modified = entry.modified else { return false }
        return modified < config.now.addingTimeInterval(-config.emptyFolderMinAge)
    }

    private func walkHome(_ onWalk: (Int, Int, Int, String) -> Void) {
        var stack: [Work] = [.open(config.home, nil, 0)]
        pendingOpens = 1
        var frames: [Frame] = []
        while let work = stack.popLast(), !stopped {
            switch work {
            case .close:
                close(&frames)
            case .open(let url, let entry, let depth):
                pendingOpens -= 1
                let entries: [ScanEntry]
                do {
                    entries = try fs.list(url)
                } catch {
                    result.skips.add(error == .denied ? .denied : .unreadable, path: url.path)
                    markContent(&frames)
                    continue
                }
                result.stats.folders += 1
                let key = ignores.paths.isEmpty ? nil : FilePaths.folderKey(url)
                frames.append(Frame(entry: entry, url: url, key: key, eligible: isEligibleEmpty(entry, url)))
                stack.append(.close)
                var opens: [Work] = []
                for e in entries {
                    guard tick(url) else { break }
                    process(e, in: url, listing: entries, depth: depth, frame: &frames[frames.count - 1], opens: &opens)
                }
                stack.append(contentsOf: opens)
                pendingOpens += opens.count
                onWalk(result.stats.folders, pendingOpens, result.stats.entries, url.path)
            }
        }
    }

    private func markContent(_ frames: inout [Frame]) {
        if !frames.isEmpty { frames[frames.count - 1].hasContent = true }
    }

    /// A folder is done. An empty folder goes up to its parent as a candidate. Any other folder reports
    /// the empty folders below it, and counts as content for its parent.
    private func close(_ frames: inout [Frame]) {
        guard let f = frames.popLast() else { return }
        if !f.hasContent, f.eligible, let entry = f.entry, let kid = emptySuggestion(entry, f.url) {
            if frames.isEmpty { return }
            frames[frames.count - 1].emptyKids.append(kid)
            return
        }
        result.suggestions.append(contentsOf: f.emptyKids)
        markContent(&frames)
    }

    private func emptySuggestion(_ e: ScanEntry, _ url: URL) -> Suggestion? {
        let stamp = ItemStamp(device: e.device, inode: e.inode, logical: 0, modified: e.modified)
        let item = SuggestionItem(url: url, isFolder: true, bytes: 0, logicalBytes: 0, date: e.modified, dateSource: .modified, stamp: stamp)
        return Suggestion(kind: .emptyFolders, id: item.id, items: [item], bytes: 0, reason: .emptyFolder)
    }

    private func process(_ e: ScanEntry, in dir: URL, listing: [ScanEntry], depth: Int, frame: inout Frame, opens: inout [Work]) {
        if ProtectedFiles.isProtected(name: e.name) { return }
        let url = dir.appendingPathComponent(e.name, isDirectory: e.type == .folder)
        if let key = frame.key, ignores.covers((key == "/" ? "" : key) + "/" + e.name) {
            result.skips.add(.ignored, path: url.path)
            frame.hasContent = true
            return
        }
        switch e.type {
        case .folder:
            folder(e, url, in: dir, listing: listing, depth: depth, frame: &frame, opens: &opens)
        case .file:
            frame.hasContent = true
            file(e, url, in: dir)
        case .symlink:
            frame.hasContent = true
            result.skips.add(.symlink, path: url.path)
            checkLink(e, url, alias: false)
        case .other:
            frame.hasContent = true
        }
    }

    private func folder(_ e: ScanEntry, _ url: URL, in dir: URL, listing: [ScanEntry], depth: Int, frame: inout Frame, opens: inout [Work]) {
        func skip(_ reason: SkipReason) {
            result.skips.add(reason, path: url.path)
            frame.hasContent = true
        }
        if e.isMountPoint { return skip(.mountPoint) }
        if let homeDevice, e.device != homeDevice { return skip(.otherDevice) }
        if e.isDataless { return skip(.cloudOnly) }
        if dir.path == homePath && e.name == "Library" { return skip(.library) }
        if e.name == ".git" { return skip(.gitFolder) }
        let rule = wants(.buildFolders) ? config.buildFolders.first { $0.name == e.name } : nil
        if let rule, rule.marker.map({ m in listing.contains { $0.name == m } }) ?? true {
            frame.hasContent = true
            return buildFolder(e, url, rule: rule, listing: listing)
        }
        if e.isHidden { return skip(.dotFolder) }
        if dir.path == downloadsPath, wants(.oldDownloads), let date = e.added ?? e.modified,
           date < config.now.addingTimeInterval(-config.downloadsOldAfter) {
            frame.hasContent = true
            if e.isLocked { return result.skips.add(.locked, path: url.path) }
            let m = measure(url)
            if let item = folderItem(url, m, date: date, source: e.added != nil ? .added : .modified) {
                result.suggestions.append(Suggestion(kind: .oldDownloads, id: item.id, items: [item], bytes: m.allocated,
                                                     reason: .inDownloadsSince(date)))
            }
            return
        }
        if e.isPackage { return skip(.package) }
        if depth + 1 > config.maxDepth { return skip(.depthCap) }
        opens.append(.open(url, e, depth + 1))
    }

    private func buildFolder(_ e: ScanEntry, _ url: URL, rule: BuildFolderRule, listing: [ScanEntry]) {
        let newest = listing.filter { $0.name != e.name && !ProtectedFiles.isProtected(name: $0.name) }.compactMap(\.modified).max()
        guard let idleSince = newest ?? e.modified, idleSince < config.now.addingTimeInterval(-config.projectIdleFor) else {
            result.skips.add(.activeBuildFolder, path: url.path)
            return
        }
        if e.isLocked {
            result.skips.add(.locked, path: url.path)
            return
        }
        let m = measure(url)
        guard m.allocated >= config.buildFolderMin, let item = folderItem(url, m, date: idleSince, source: .modified) else { return }
        result.suggestions.append(Suggestion(kind: .buildFolders, id: item.id, items: [item], bytes: m.allocated,
                                             reason: .buildFolder(name: rule.name, projectIdleSince: idleSince)))
    }

    private func file(_ e: ScanEntry, _ url: URL, in dir: URL) {
        if e.isDataless { return result.skips.add(.cloudOnly, path: url.path) }
        if e.isAlias { return checkLink(e, url, alias: true) }
        let big = e.allocated >= min(config.duplicateMin, config.largeFileMin)
        if isManaged(url.path) {
            if big { result.skips.add(.managedMedia, path: url.path) }
            return
        }
        let inDropFolder = dir.path == downloadsPath || dir.path == desktopPath
        let ext = FolderListing.pathExtension(e.name).lowercased()
        let dated = e.added ?? e.modified
        let source: DateSource = e.added != nil ? .added : .modified

        var found: (SuggestionKind, SuggestionReason, Date, DateSource)?
        if let dated {
            if wants(.installers), config.installerExts.contains(ext) || (inDropFolder && config.archiveExtsInDropFolders.contains(ext)),
               dated < config.now.addingTimeInterval(-config.installerOldAfter) {
                found = (.installers, .installer(ext: ext, since: dated), dated, source)
            } else if wants(.oldDownloads), dir.path == downloadsPath, dated < config.now.addingTimeInterval(-config.downloadsOldAfter) {
                found = (.oldDownloads, .inDownloadsSince(dated), dated, source)
            }
        }
        if e.isLocked {
            if found != nil || big { result.skips.add(.locked, path: url.path) }
            return
        }
        let stamp = ItemStamp(device: e.device, inode: e.inode, logical: e.logical, modified: e.modified)
        func item(_ date: Date?, _ source: DateSource?) -> SuggestionItem {
            SuggestionItem(url: url, isFolder: false, bytes: e.allocated, logicalBytes: e.logical, date: date, dateSource: source, stamp: stamp)
        }
        if wants(.duplicates), e.allocated >= config.duplicateMin {
            result.duplicateCandidates.append(DuplicateCandidate(item: item(dated, dated == nil ? nil : source), linkCount: e.linkCount))
        }
        if let (kind, reason, date, source) = found {
            let it = item(date, source)
            result.suggestions.append(Suggestion(kind: kind, id: it.id, items: [it], bytes: e.allocated, reason: reason))
            return
        }
        largeUnused(e, url, item: item)
    }

    /// Large and unused. The dates on the entry decide first, and Spotlight is asked only for what is left.
    private func largeUnused(_ e: ScanEntry, _ url: URL, item: (Date?, DateSource?) -> SuggestionItem) {
        guard wants(.largeUnused), e.allocated >= config.largeFileMin else { return }
        guard e.linkCount == 1 else { return result.skips.add(.hardlink, path: url.path) }
        // A read by Folio (hashing) bumps the access date. It is not a use of the file.
        var accessed = e.accessed
        if let hashed = config.hashedAt[e.fileID], let a = accessed, a >= hashed { accessed = nil }
        var newest: (Date, DateSource)?
        for (date, source) in [(accessed, DateSource.accessed), (e.modified, .modified), (e.added, .added)] {
            guard let date else { continue }
            if newest == nil || date > newest!.0 { newest = (date, source) }
        }
        guard let newest, newest.0 < cutoffUnused else { return }
        guard lookups < config.maxSpotlightLookups else { return result.skips.add(.spotlightCap, path: url.path) }
        lookups += 1
        result.stats.spotlightLookups += 1
        let used = fs.lastUsed(url)
        if let used, used >= cutoffUnused { return }
        let (date, source) = used.map { ($0, DateSource.lastUsed) } ?? newest
        let it = item(date, source)
        result.suggestions.append(Suggestion(kind: .largeUnused, id: it.id, items: [it], bytes: e.allocated,
                                             reason: .notUsedSince(date, source)))
    }

    private func checkLink(_ e: ScanEntry, _ url: URL, alias: Bool) {
        guard wants(.brokenLinks) else { return }
        if alias {
            guard aliasResolves < config.maxAliasResolves else {
                result.isPartial = true
                return
            }
            aliasResolves += 1
        }
        guard case .missing(let target) = fs.linkTarget(url, alias: alias), let stamp = fs.stamp(url) else { return }
        let item = SuggestionItem(url: url, isFolder: false, bytes: e.allocated, logicalBytes: stamp.logical, date: e.modified,
                                  dateSource: e.modified == nil ? nil : .modified, stamp: stamp)
        result.suggestions.append(Suggestion(kind: .brokenLinks, id: item.id, items: [item], bytes: e.allocated,
                                             reason: .brokenLink(target: target)))
    }
}
