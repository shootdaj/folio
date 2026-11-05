import AppKit
import FolioCore

/// Files on the general pasteboard: file URLs (so Finder and other apps can paste them) plus a Folio
/// marker when they were cut, so Folio's paste moves them. Cut items stay dimmed while the marker
/// is ours and still on the pasteboard.
@MainActor
enum FileClipboard {
    static let cutMarker = NSPasteboard.PasteboardType("com.anshul.folio.cut")
    static let didChange = Notification.Name("FolioClipboardDidChange")
    private static var cutChangeCount = -1
    private static var cutPaths: Set<String> = []

    static func write(_ urls: [URL], cut: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        if cut {
            pb.addTypes([cutMarker], owner: nil)
            pb.setString("1", forType: cutMarker)
        }
        cutChangeCount = cut ? pb.changeCount : -1
        cutPaths = cut ? Set(urls.map(FilePaths.itemKey)) : []
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The files on the pasteboard, and whether Folio cut them.
    static func read() -> (urls: [URL], isCut: Bool) {
        let pb = NSPasteboard.general
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return (urls, pb.types?.contains(cutMarker) == true)
    }

    static var hasFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// Item keys drawn dimmed: the pending cut, unless something else was copied since.
    static var dimmedPaths: Set<String> {
        NSPasteboard.general.changeCount == cutChangeCount ? cutPaths : []
    }

    /// Esc, or a paste that moved the files: the cut is over and the pasteboard is cleared.
    static func endCut() {
        guard NSPasteboard.general.changeCount == cutChangeCount else { return }
        NSPasteboard.general.clearContents()
        cutChangeCount = -1
        cutPaths = []
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static var hasPendingCut: Bool { !dimmedPaths.isEmpty }
}

/// Every file operation in the app goes through here: one undo history for all windows (like
/// Explorer), the running copy and move jobs, the progress window, the status chips and the Dock.
@MainActor
final class OperationCenter {
    static let shared = OperationCenter()
    /// Folders changed; `userInfo["select"]` holds paths to select in the windows that show them.
    static let filesChanged = Notification.Name("FolioFilesChanged")
    /// A job started, moved on or ended: windows refresh their status chip.
    static let jobsChanged = Notification.Name("FolioJobsChanged")

    private(set) var history = UndoHistory()
    let trash: any Trasher = SystemTrash()
    private let jobOptions = JobOptions.fromEnvironment(ProcessInfo.processInfo.environment)
    private(set) var jobs: [FileJob] = []
    private(set) var snapshots: [Int: JobSnapshot] = [:]
    private var started: [Int: Double] = [:]
    private var finishedAt: [Int: Double] = [:]
    private var timer: Timer?
    private var lastRefresh = 0.0
    private var busy = false
    private let progress = ProgressWindowController()
    private weak var anchorWindow: NSWindow?
    private let dock = DockProgress()

    private init() {}

    // MARK: Copy and move

    func start(_ kind: JobKind, sources: [URL], into folder: URL, near window: NSWindow?) {
        guard !sources.isEmpty else { return }
        let job = FileJob(kind: kind, sources: sources, into: folder, options: jobOptions)
        job.onChange = { _ in Task { @MainActor in OperationCenter.shared.tick() } }
        jobs.append(job)
        started[job.id] = now
        anchorWindow = window ?? anchorWindow
        progress.add(job)
        job.start()
        startTimer()
        Task { @MainActor in
            let result = await job.finished()
            self.jobFinished(job, result)
        }
        tick()
    }

    private func jobFinished(_ job: FileJob, _ result: JobResult) {
        if let record = result.record { history.record(record) }
        finishedAt[job.id] = now
        if result.state == .cancelled { progress.reveal(near: anchorWindow) }
        postChanged(select: result.placed)
        tick()
    }

    /// Close on a finished job, or a done job's moment of 100% has passed.
    func dismiss(_ job: FileJob) {
        jobs.removeAll { $0 === job }
        snapshots[job.id] = nil
        started[job.id] = nil
        finishedAt[job.id] = nil
        progress.remove(job)
        tick()
    }

    func showProgress() { progress.reveal(near: anchorWindow, force: true) }

    var hasJobs: Bool { !jobs.isEmpty }

    /// The status bar chip: "Copying 3 items, 42%", or nil when nothing runs.
    var chipText: String? {
        let live = jobs.compactMap { snapshots[$0.id] }.filter { !$0.state.isFinished }
        guard let first = live.first else { return nil }
        let pct = Int((live.map(\.fraction).reduce(0, +) / Double(live.count) * 100).rounded(.down))
        if live.count > 1 { return "\(live.count) jobs, \(pct)%" }
        let verb = first.kind == .copy ? "Copy" : "Move"
        switch first.state {
        case .paused: return "\(verb) paused, \(pct)%"
        case .waitingOnConflict, .waitingOnProblem: return "\(verb) waiting on you"
        default:
            let n = ByteText.grouped(first.itemsTotal)
            return (first.kind == .copy ? "Copying " : "Moving ") + n + (first.itemsTotal == 1 ? " item" : " items") + ", \(pct)%"
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { OperationCenter.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 30 times a second while jobs exist: snapshots to the progress window, chips and the Dock.
    func tick() {
        for job in jobs { snapshots[job.id] = job.snapshot() }
        let t = now
        // Explorer only shows the window for work that takes a moment, or that needs an answer.
        let needsWindow = jobs.contains { job in
            guard let s = snapshots[job.id] else { return false }
            return s.conflict != nil || s.problem != nil
                || (!s.state.isFinished && t - (started[job.id] ?? t) > 0.4)
        }
        if needsWindow { progress.reveal(near: anchorWindow) }
        progress.update(snapshots)
        // A done job shows 100% for a moment, then its panel goes, as Explorer's dialog closes itself.
        for job in jobs where snapshots[job.id]?.state == .done {
            if let end = finishedAt[job.id], t - end > 1.2 { dismiss(job) ; return }
        }
        // Files appear in the destination window as they land.
        if t - lastRefresh > 1, jobs.contains(where: { snapshots[$0.id]?.state == .running }) {
            lastRefresh = t
            let folders = Set(jobs.map { FilePaths.folderKey($0.destination) })
            NotificationCenter.default.post(name: Self.filesChanged, object: nil, userInfo: ["folders": folders])
        }
        let live = jobs.compactMap { snapshots[$0.id] }.filter { !$0.state.isFinished }
        dock.show(live.isEmpty ? nil : live.map(\.fraction).reduce(0, +) / Double(live.count),
                  paused: live.contains { $0.state != .running && $0.state != .preparing })
        NotificationCenter.default.post(name: Self.jobsChanged, object: nil)
        if jobs.isEmpty {
            timer?.invalidate()
            timer = nil
            progress.closeIfEmpty()
        }
    }

    // MARK: Quick operations

    func record(_ step: OperationRecord) { history.record(step) }

    func trash(_ urls: [URL], window: NSWindow?) {
        guard !urls.isEmpty else { return }
        let trasher = trash
        Task.detached {
            let result = Result { try FileOps.trash(urls, using: trasher) }
            await MainActor.run {
                switch result {
                case .success(let items):
                    self.history.record(.trash(items))
                case .failure(let error):
                    if let partial = error as? FileOps.TrashError {
                        if !partial.done.isEmpty { self.history.record(.trash(partial.done)) }
                        self.present(partial.underlying, window: window)
                    } else {
                        self.present(error, window: window)
                    }
                }
                self.postChanged(select: [])
            }
        }
    }

    func deletePermanently(_ urls: [URL], window: NSWindow?) {
        Task.detached {
            let result = Result { try FileOps.deletePermanently(urls) }
            await MainActor.run {
                if case .failure(let error) = result { self.present(error, window: window) }
                self.postChanged(select: [])
            }
        }
    }

    // MARK: Undo and redo

    var undoTitle: String? { history.undoTitle }
    var redoTitle: String? { history.redoTitle }

    func undo(window: NSWindow?) {
        guard !busy, let step = history.takeUndo() else { NSSound.beep(); return }
        busy = true
        let trasher = trash
        Task.detached {
            let result = Result { try FileOps.undo(step, trash: trasher) }
            await MainActor.run {
                self.busy = false
                switch result {
                case .success(let items):
                    self.history.didUndo(step)
                    self.postChanged(select: items)
                case .failure(let error):
                    self.present(error, window: window)
                    self.postChanged(select: [])
                }
            }
        }
    }

    func redo(window: NSWindow?) {
        guard !busy, let step = history.takeRedo() else { NSSound.beep(); return }
        busy = true
        let trasher = trash
        Task.detached {
            let result = Result { try FileOps.redo(step, trash: trasher) }
            await MainActor.run {
                self.busy = false
                switch result {
                case .success(let done):
                    self.history.didRedo(done.record)
                    self.postChanged(select: done.items)
                case .failure(let error):
                    self.present(error, window: window)
                    self.postChanged(select: [])
                }
            }
        }
    }

    func postChanged(select: [URL]) {
        NotificationCenter.default.post(name: Self.filesChanged, object: nil,
                                        userInfo: ["select": select.map(\.path)])
    }

    func present(_ error: Error, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Folio couldn't finish that"
        alert.informativeText = (error as? FileOpError)?.message ?? error.localizedDescription
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }
}

/// The Dock icon shows the progress of the running jobs, amber while paused or waiting.
@MainActor
final class DockProgress {
    private var view: DockTileView?

    func show(_ fraction: Double?, paused: Bool) {
        let tile = NSApp.dockTile
        guard let fraction else {
            if view != nil {
                tile.contentView = nil
                view = nil
                tile.display()
            }
            return
        }
        if view == nil {
            let v = DockTileView(frame: NSRect(origin: .zero, size: tile.size))
            tile.contentView = v
            view = v
        }
        guard let view else { return }
        let step = (fraction * 50).rounded() / 50
        if view.fraction != step || view.paused != paused {
            view.fraction = step
            view.paused = paused
            tile.display()
        }
    }
}

final class DockTileView: NSView {
    var fraction = 0.0
    var paused = false

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let p = Theme.palette(.dark, accent: ThemeController.shared.accent)
        let bar = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.08, width: bounds.width * 0.8, height: bounds.height * 0.11)
        fillRounded(bar, radius: bar.height / 2, p.hudBg)
        let inner = bar.insetBy(dx: 3, dy: 3)
        fillRounded(NSRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * fraction), height: inner.height),
                    radius: inner.height / 2, paused ? p.part : p.accent)
    }
}
