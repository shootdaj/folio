import Foundation

/// How far a scan has come.
public struct ScanProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case fixedPlaces, walking, lastUsed, hashing, done }

    public var phase: Phase
    /// 0 to 1. Fixed places take 0 to 0.1, the walk 0.1 to 0.75, the last-used lookups 0.75 to 0.8, hashing the rest.
    public var fraction: Double
    public var entries: Int
    /// The bytes of content read for hashing so far.
    public var hashed: Int64
    /// The folder being listed.
    public var current: String

    public init(phase: Phase, fraction: Double, entries: Int = 0, hashed: Int64 = 0, current: String = "") {
        self.phase = phase
        self.fraction = fraction
        self.entries = entries
        self.hashed = hashed
        self.current = current
    }
}

/// The whole scan in one call: the fixed places, the walk of home and the duplicate finder, with the
/// precedence applied across all of them. Run it off the main thread.
public struct SuggestionScanner: Sendable {
    private static let progressInterval: TimeInterval = 0.1

    public let config: SuggestionConfig
    public let ignores: SuggestionIgnores.Snapshot
    private let fs: any ScanFileSystem

    public init(config: SuggestionConfig, ignores: SuggestionIgnores.Snapshot, fs: any ScanFileSystem = LiveScanFileSystem()) {
        self.config = config
        self.ignores = ignores
        self.fs = fs
    }

    /// The scan with no progress and no cancel, for tests.
    public func collect() -> SuggestionReport {
        run(isCancelled: { false }, onProgress: { _ in }, onCards: { _ in })
    }

    /// The Trash alone as one suggestion, or nil when it is empty or cannot be read. The app uses this to
    /// refresh the Trash card after a Trash change, with no new scan.
    public static func measureTrash(config: SuggestionConfig, fs: any ScanFileSystem) -> Suggestion? {
        var only = config
        only.kinds = [.trash]
        return SuggestionWalk(config: only, fs: fs, ignores: .init(), isCancelled: { false }).trashOnly().suggestions.first
    }

    /// Runs the scan. `onCards` gets the cards of the fixed places as soon as they are measured. `onProgress`
    /// is called at most every 0.1 s, and for the last step. Nothing is called after `isCancelled` says yes,
    /// and a cancelled scan returns an empty partial report.
    public func run(isCancelled: () -> Bool, onProgress: (ScanProgress) -> Void, onCards: ([Suggestion]) -> Void) -> SuggestionReport {
        // The policy holds for the whole scan, the hashing too: a read must not download a cloud file.
        IOPolicy.scoped { runScoped(isCancelled: isCancelled, onProgress: onProgress, onCards: onCards) }
    }

    private func runScoped(isCancelled: () -> Bool, onProgress: (ScanProgress) -> Void, onCards: ([Suggestion]) -> Void) -> SuggestionReport {
        withoutActuallyEscaping(isCancelled) { cancelled in
            let begun = config.elapsed()
            var progress = ScanProgress(phase: .fixedPlaces, fraction: 0)
            var lastSent: TimeInterval?

            func send(force: Bool = false) {
                guard !cancelled() else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if !force, let lastSent, now - lastSent < Self.progressInterval { return }
                lastSent = now
                onProgress(progress)
            }
            func stopped() -> SuggestionReport {
                SuggestionReport(scannedAt: config.now, home: config.home, isPartial: true)
            }

            send(force: true)
            let walk = SuggestionWalk(config: config, fs: fs, ignores: ignores, isCancelled: cancelled)
            let walked = walk.run(onFixedPlaces: { cards in
                guard !cancelled() else { return }
                progress.phase = .walking
                progress.fraction = 0.1
                send(force: true)
                if !cards.isEmpty { onCards(self.capped(cards)) }
            }, onWalk: { listed, pending, entries, current in
                progress.phase = .walking
                progress.fraction = 0.1 + 0.65 * Double(listed) / Double(max(1, listed + pending))
                progress.entries = entries
                progress.current = current
                send()
            })
            if walked.cancelled || cancelled() { return stopped() }

            progress.phase = .lastUsed
            progress.fraction = 0.75
            progress.entries = walked.stats.entries
            send()

            var dups = DuplicateResult()
            if config.kinds.contains(.duplicates), !walked.duplicateCandidates.isEmpty {
                progress.phase = .hashing
                progress.fraction = 0.8
                send()
                dups = DuplicateFinder.groups(walked.duplicateCandidates, fs: fs, config: config, ignores: ignores,
                                              isCancelled: cancelled, progress: { done, planned in
                    progress.fraction = 0.8 + 0.2 * Double(done) / Double(max(1, planned))
                    progress.hashed = done
                    send()
                })
                if cancelled() { return stopped() }
            }

            // A copy in a duplicate group is in no other suggestion, the kept copy too.
            let claimed = Set(dups.groups.flatMap { $0.items.map(\.id) })
            let loose = walked.excluding(keys: claimed)
            let all = loose.suggestions + dups.groups

            var skips = walked.skips
            for (reason, count) in dups.skips.counts { skips.counts[reason, default: 0] += count }
            for (reason, paths) in dups.skips.samples {
                for path in paths where skips.samples[reason, default: []].count < ScanSkips.sampleLimit {
                    skips.samples[reason, default: []].append(path)
                }
            }
            var stats = walked.stats
            stats.hashedBytes = dups.hashed
            stats.elapsed = config.elapsed() - begun

            var seen = Set<FileID>()
            let shown = capped(all)
            var report = SuggestionReport(suggestions: shown, scannedAt: config.now, home: config.home, stats: stats,
                                          skips: skips, denied: walked.denied, isPartial: walked.isPartial || dups.partial,
                                          needsFullDiskAccess: walked.needsFullDiskAccess,
                                          totalBytes: shown.reduce(0) { $0 + $1.bytes })
            report.hashedFiles = dups.hashedFiles.filter { seen.insert($0).inserted }

            progress = ScanProgress(phase: .done, fraction: 1, entries: stats.entries, hashed: stats.hashedBytes)
            send(force: true)
            return report
        }
    }

    /// At most `maxPerKind` suggestions of each kind, the largest first.
    private func capped(_ list: [Suggestion]) -> [Suggestion] {
        var byKind: [SuggestionKind: [Suggestion]] = [:]
        for s in list { byKind[s.kind, default: []].append(s) }
        return byKind.values.flatMap { group in
            Array(group.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }.prefix(config.maxPerKind))
        }
    }
}

/// What a running scan sends: progress, then the fixed-place cards, then the report.
public struct SuggestionUpdate: Sendable {
    public let progress: ScanProgress
    /// The cards of the fixed places, sent once before the walk ends.
    public let cards: [Suggestion]?
    /// The finished report, sent once, last.
    public let report: SuggestionReport?

    public init(progress: ScanProgress, cards: [Suggestion]? = nil, report: SuggestionReport? = nil) {
        self.progress = progress
        self.cards = cards
        self.report = report
    }
}

/// One scan on its own utility-priority thread. `cancel()` stops it, and after `cancel()` returns nothing more is sent.
/// `cancel()` waits for an `onUpdate` call that is running. `onUpdate` must not wait for the thread that calls `cancel()`.
public final class SuggestionScan: @unchecked Sendable {
    private let scanner: SuggestionScanner
    private let onUpdate: @Sendable (SuggestionUpdate) -> Void
    private let cancelLock = NSRecursiveLock()
    private var cancelledFlag = false
    private var latest = ScanProgress(phase: .fixedPlaces, fraction: 0)

    public init(_ scanner: SuggestionScanner, onUpdate: @escaping @Sendable (SuggestionUpdate) -> Void) {
        self.scanner = scanner
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
    }

    public func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            guard !isCancelled else { return }
            let report = scanner.run(isCancelled: { self.isCancelled }, onProgress: { progress in
                self.latest = progress
                self.send(SuggestionUpdate(progress: progress))
            }, onCards: { cards in
                self.send(SuggestionUpdate(progress: self.latest, cards: cards))
            })
            send(SuggestionUpdate(progress: ScanProgress(phase: .done, fraction: 1, entries: report.stats.entries,
                                                         hashed: report.stats.hashedBytes), report: report))
        }
    }

    private func send(_ update: SuggestionUpdate) {
        cancelLock.lock(); defer { cancelLock.unlock() }
        guard !cancelledFlag else { return }
        onUpdate(update)
    }
}
