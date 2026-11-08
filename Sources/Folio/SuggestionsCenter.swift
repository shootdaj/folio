import AppKit
import FolioCore

/// The one owner of the Suggestions scan for the whole app. It holds the last report (in memory only), the
/// ignores, the access gate and the pruning. Windows only show its state and listen for `didChange`.
@MainActor
final class SuggestionsCenter: NSObject {
    static let shared = SuggestionsCenter()
    static let didChange = Notification.Name("FolioSuggestionsChanged")

    // MARK: State the page shows

    private(set) var state: SuggestionState = .idle
    private(set) var report: SuggestionReport?
    /// Progress of the running scan.
    private(set) var progress: ScanProgress?
    /// The cards of the fixed places, sent before the walk ends.
    private(set) var earlyCards: [Suggestion] = []
    /// Why the last scan failed.
    private(set) var failure: String?
    /// When the last scan ended. Freshness counts from here.
    private(set) var lastScan: Date?
    /// The item ids that a Move to Trash is working on. The page hides them and does not send them again.
    private(set) var pending: Set<String> = []
    /// True from the yes in the Empty Trash alert until the Trash was measured again.
    private(set) var emptyingTrash = false

    /// False until the app has finished launching and restoring its session. Nothing scans by itself before.
    var autoScanAllowed = false {
        didSet {
            autoScanAllowedSince = autoScanAllowed ? (autoScanAllowedSince ?? Date()) : nil
            if autoScanAllowed { evaluate() }
        }
    }
    /// When launch ended. A page that was shown before this (a restored tab) does not start a scan by itself.
    private var autoScanAllowedSince: Date?

    // MARK: Where it scans

    private var defaults: UserDefaults = .standard
    /// Nil: the real home. A path is set only by `configure`, for a test run.
    private var fixtureHome: URL?
    private var fixtureConfig: SuggestionConfig?
    /// In a test run no scan starts until `configure` gives a fixture home, so the real home is never read.
    private var refusesScans = false
    private var accessOverride = false
    private let fs: any ScanFileSystem = LiveScanFileSystem()

    /// The folder the scan looks through: the real home, or a fixture home in a test run.
    var home: URL { fixtureHome ?? FileManager.default.homeDirectoryForCurrentUser }
    var isRealHome: Bool { fixtureHome == nil }
    var ignores: SuggestionIgnores { SuggestionIgnores(defaults: defaults) }
    var ignoredCount: Int { ignores.count }

    // MARK: The running scan

    private var scan: SuggestionScan?
    private var generation = 0
    private var ledger = SuggestionLedger()
    /// When Folio hashed a file. The next scan does not count that read as use.
    private var hashedAt: [FileID: Date] = [:]
    private var viewers: [ObjectIdentifier: Date] = [:]
    private var graceWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: OperationCenter.filesChanged, object: nil, queue: .main) { [weak self] note in
            let folders = note.userInfo?["folders"] as? Set<String>
            MainActor.assumeIsolated { self?.filesChanged(folders: folders) }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
    }

    // MARK: Setup

    /// The defaults of a test run, and no scan until `configure`. Called from the uitest branch of the app delegate.
    func useUITestDefaults(_ defaults: UserDefaults) {
        self.defaults = defaults
        refusesScans = true
    }

    /// A test run scans this fake home with this config. A home outside the test roots is refused (false).
    @discardableResult
    func configure(home: URL, config: SuggestionConfig, defaults: UserDefaults) -> Bool {
        guard UITestFixture.isAllowed(home), UITestFixture.isAllowed(config.home) else { return false }
        fixtureHome = home
        fixtureConfig = config
        self.defaults = defaults
        refusesScans = false
        return true
    }

    /// A test run shows the Full Disk Access page without the real check. Off puts the earlier state back.
    private var stateBeforeGate: SuggestionState?
    func uitestForceAccessGate(_ on: Bool) {
        guard !isRealHome else { return }
        if on {
            guard state != .needsAccess else { return }
            stateBeforeGate = state
            state = .needsAccess
        } else if state == .needsAccess, let earlier = stateBeforeGate {
            state = earlier
            stateBeforeGate = nil
        }
        post()
    }

    // MARK: Viewing

    /// A window shows the page (or stops). The scan starts after the page has been shown for a moment.
    /// When the last window leaves during a scan, the scan stops after a grace time.
    func setViewing(_ window: AnyObject, _ viewing: Bool) {
        let id = ObjectIdentifier(window)
        if viewing {
            guard viewers[id] == nil else { return }
            viewers[id] = Date()
            graceWork?.cancel()
            graceWork = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + SuggestionSchedule.shownDelay + 0.02) { [weak self] in
                self?.evaluate()
            }
        } else {
            guard viewers.removeValue(forKey: id) != nil else { return }
            if viewers.isEmpty, state == .scanning { startGrace() }
        }
    }

    private func startGrace() {
        graceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, viewers.isEmpty, state == .scanning else { return }
            stop()
        }
        graceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SuggestionSchedule.viewGrace, execute: work)
    }

    // MARK: Starting and stopping

    private func evaluate() {
        guard !refusesScans else { return }
        updateAccess()
        // The real home is never scanned by itself while Folio is in the background (a login item, a hidden launch).
        let visible = !isRealHome || NSApp.isActive
        let now = Date()
        let shownFor = visible ? SuggestionSchedule.shownFor(since: Array(viewers.values), allowedSince: autoScanAllowedSince, now: now) : 0
        if SuggestionSchedule.shouldStartAutomatically(allowed: autoScanAllowed, viewing: !viewers.isEmpty, shownFor: shownFor,
                                                       state: state, lastScan: lastScan, now: Date()) {
            startScan()
        }
    }

    /// The access gate for the real home. The check reads one file and shows no prompt.
    private func updateAccess() {
        guard isRealHome, !accessOverride else { return }
        let granted = DiskAccess.isGranted()
        if state == .needsAccess, granted { state = .idle; post() }
        else if state == .idle, !granted { state = .needsAccess; post() }
    }

    private func becameActive() {
        guard state == .needsAccess || state == .idle, !viewers.isEmpty else { return }
        evaluate()
    }

    /// The Rescan and Scan buttons, and F5. It does nothing while the gate is closed or a scan runs.
    func rescan() {
        guard !refusesScans else { return }
        updateAccess()
        guard state != .scanning, state != .needsAccess else { return }
        startScan()
    }

    /// "Scan anyway" on the needs-access page: the user chose to scan without Full Disk Access.
    func scanAnyway() {
        guard !refusesScans, state != .scanning else { return }
        accessOverride = true
        startScan()
    }

    /// The Stop button, and the end of the grace time. The old report stays.
    func stop() {
        guard state == .scanning else { return }
        scan?.cancel()
        scan = nil
        generation += 1
        progress = nil
        earlyCards = []
        state = report == nil ? .idle : .done
        post()
    }

    private func startScan() {
        scan?.cancel()
        generation += 1
        let mine = generation
        guard FileManager.default.isReadableFile(atPath: home.path) else {
            failure = "Folio cannot read " + home.path + "."
            state = .failed
            progress = nil
            post()
            return
        }
        failure = nil
        ledger.reset()
        earlyCards = []
        progress = ScanProgress(phase: .fixedPlaces, fraction: 0)
        state = .scanning
        let scanner = SuggestionScanner(config: scanConfig(), ignores: ignores.snapshot, fs: fs)
        let running = SuggestionScan(scanner) { update in
            Task { @MainActor in SuggestionsCenter.shared.receive(update, generation: mine) }
        }
        scan = running
        post()
        running.start()
    }

    private func scanConfig() -> SuggestionConfig {
        var config = fixtureConfig ?? SuggestionConfig(home: home, now: Date())
        config.hashedAt = hashedAt
        return config
    }

    private func receive(_ update: SuggestionUpdate, generation id: Int) {
        guard id == generation, state == .scanning else { return }
        progress = update.progress
        if let cards = update.cards { earlyCards = cards }
        if let done = update.report {
            let now = Date()
            for file in done.hashedFiles { hashedAt[file] = now }
            report = done
            lastScan = now
            scan = nil
            progress = nil
            earlyCards = []
            state = .done
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: "Suggestions ready",
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ])
        }
        post()
    }

    // MARK: Changes the page makes

    /// The rows a Move to Trash may take, before the disk is asked. The sheet shows their count and size.
    func selection(of suggestions: [Suggestion], item: SuggestionItem? = nil) -> SuggestionSelection {
        SuggestionActions.selection(of: suggestions, item: item, pending: pending, ignores: ignores.snapshot)
    }

    /// The plan for a Move to Trash, checked against the disk now (device, inode, size and date; for a
    /// duplicate group also the kept copy).
    /// `allowing` holds ids that a Move to Trash already marked as pending, for the check after its sheet.
    func trashPlan(of suggestions: [Suggestion], item: SuggestionItem? = nil, allowing: [String] = []) -> SuggestionTrashPlan {
        SuggestionActions.trashPlan(of: suggestions, item: item, pending: pending.subtracting(allowing),
                                    ignores: ignores.snapshot, fs: fs)
    }

    /// The Trash that Empty Trash may clear: the real Trash, or in a test run the Trash of the fixture home.
    /// Nil when the folder is not the Trash of the home, or a test run has no fixture home.
    var trashFolder: URL? {
        let trash = RecycleBin.trashFolder(home: home)
        guard RecycleBin.isTrash(trash, home: home) else { return nil }
        if isRealHome { return refusesScans ? nil : trash }
        return UITestFixture.isAllowed(trash) ? trash : nil
    }

    /// A Move to Trash has these items. The page hides them until the files change.
    func markTrashing(_ keys: [String]) {
        pending.formUnion(keys)
        post()
    }

    /// The Move to Trash failed or was cancelled, so the rows show again.
    func unmarkTrashing(_ keys: [String]) {
        pending.subtract(keys)
        post()
    }

    /// Empty Trash starts. The Trash row shows a spinner until `finishEmptying` measured the Trash again.
    func markEmptying() {
        emptyingTrash = true
        post()
    }

    /// The delete ended. The Trash is measured again off the main thread, then the spinner stops.
    func finishEmptying() {
        guard emptyingTrash else { return }
        let trashKey = FilePaths.folderKey(RecycleBin.trashFolder(home: home))
        guard state == .done, let current = report, !current.denied.contains(where: { FilePaths.folderKey($0) == trashKey }) else {
            emptyingTrash = false
            post()
            return
        }
        var trashConfig = scanConfig()
        trashConfig.kinds = [.trash]
        let config = trashConfig
        let fs = self.fs
        let mine = generation
        Task.detached(priority: .utility) {
            let trash = SuggestionScanner.measureTrash(config: config, fs: fs)
            await SuggestionsCenter.shared.applyEmptied(trash: trash, generation: mine)
        }
    }

    private func applyEmptied(trash: Suggestion?, generation id: Int) {
        emptyingTrash = false
        if id == generation, state == .done, let current = report { report = current.replacingTrash(with: trash) }
        post()
    }

    /// Ignore one item of a suggestion, or the whole suggestion (a group by its hash).
    func ignore(_ suggestion: Suggestion, item: SuggestionItem? = nil) {
        ignores.ignore(suggestion, item: item)
        if let current = report { report = current.excluding(ignores.snapshot) }
        post()
    }

    /// Forget every ignore and scan again.
    func showIgnoredAgain() {
        ignores.removeAll()
        post()
        rescan()
    }

    /// "Keep this copy instead" on a duplicate group.
    func keep(_ suggestion: Suggestion, copy: URL) {
        report = report?.restoring([suggestion.keeping(copy)])
        post()
    }

    // MARK: Files changed

    /// Rows whose file is gone leave the report, rows whose file is back (Undo) return, and the Trash is
    /// measured again when it changed. The look at the disk runs off the main thread.
    private func filesChanged(folders: Set<String>?) {
        guard state == .done, let current = report else { return }
        let items = ledger.itemsToCheck(in: current, folders: folders)
        let trashKey = FilePaths.folderKey(RecycleBin.trashFolder(home: home))
        let trashChanged = (folders?.contains(trashKey) ?? true) && !current.denied.contains { FilePaths.folderKey($0) == trashKey }
        guard !items.isEmpty || trashChanged else { return }
        let urls = items.map { ($0.id, $0.url) }
        var trashConfig = scanConfig()
        trashConfig.kinds = [.trash]
        let config = trashConfig
        let fs = self.fs
        let mine = generation
        Task.detached(priority: .utility) {
            var exists: [String: Bool] = [:]
            for (key, url) in urls { exists[key] = fs.stamp(url) != nil }
            let trash = trashChanged ? SuggestionScanner.measureTrash(config: config, fs: fs) : nil
            await SuggestionsCenter.shared.applyCheck(exists: exists, trash: trash, trashMeasured: trashChanged, generation: mine)
        }
    }

    private func applyCheck(exists: [String: Bool], trash: Suggestion?, trashMeasured: Bool, generation id: Int) {
        guard id == generation, state == .done, let current = report else { return }
        let result = ledger.reconciled(current, exists: exists)
        var next = result.report
        if trashMeasured { next = next.replacingTrash(with: trash) }
        ledger = result.ledger
        pending.subtract(exists.keys)
        report = next
        post()
    }

    private func post() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
