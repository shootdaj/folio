import AppKit
import FolioCore
import FolioLink
import os

let perfLog = Logger(subsystem: "com.anshul.folio", category: "perf")

/// Wall-clock time this process was started, read from the kernel, for launch-to-rows timing.
let processStartDate: Date = {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
    let start = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
}()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var windows: [BrowserWindowController] = []
    private var cascadePoint = NSPoint.zero
    private let uitest: UITestConfig?
    /// Cmd+Shift+T: tabs closed in any window, and the tabs of closed windows.
    var closedTabs = ClosedTabs()
    private var sessionTimer: Timer?
    private var terminating = false

    init(uitest: UITestConfig?) {
        self.uitest = uitest
        super.init()
    }

    var browserControllers: [BrowserWindowController] { windows }

    func controller(windowNumber: Int) -> BrowserWindowController? {
        windows.first { $0.window?.windowNumber == windowNumber }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = processStartDate
        Fonts.registerBundled()
        // Folio draws its own tabs; macOS's window tabs would add a second kind.
        NSWindow.allowsAutomaticWindowTabbing = false
        if let uitest {
            ThemeController.shared.start(defaults: uitest.defaults, forcedAppearance: uitest.appearance)
            ThemeController.shared.hue = uitest.hue
        } else {
            ThemeController.shared.start(defaults: .standard)
        }
        // One view and one column set for every window and folder (milestone 6).
        ViewCenter.shared.start(defaults: uitest?.defaults ?? .standard)
        ColumnCenter.shared.start(defaults: uitest?.defaults ?? .standard)
        NSApp.mainMenu = MainMenu.build()
        // Other apps' Services take the selected files' URLs or paths (the menus' Services submenu).
        NSApp.registerServicesMenuSendTypes([.fileURL, .string], returnTypes: [])
        VolumeCenter.shared.start()
        if uitest == nil { DeviceCenter.shared.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let uitest {
            let controller = BrowserWindowController(
                folder: uitest.folder,
                options: .init(size: UITestRunner.windowSize, uitest: true, historyDefaults: uitest.defaults))
            windows.append(controller)
            Task { @MainActor in
                let code = await UITestRunner.run(uitest, controller: controller)
                exit(code)
            }
            return
        }
        // Folders passed with `open -a`, `ff` or dropped on the Dock icon arrive in application(_:open:)
        // first; then those windows open and the saved session does not. Otherwise the last session comes back.
        if windows.isEmpty && !restoreSession() { openWindow(at: Self.startPlace) }
        VolumeCenter.shared.remountMappedShares()
        NotificationCenter.default.addObserver(self, selector: #selector(viewChanged(_:)), name: ViewCenter.didChange, object: nil)
        DockIcon.start()
        NSApp.activate()
    }

    /// Folio > Settings... (Cmd+,, the Mac's key for an app's settings): Folder Options, also with no
    /// window open.
    @objc func showSettings(_ sender: Any?) {
        FolderOptionsWindowController.show(near: NSApp.mainWindow ?? NSApp.keyWindow)
    }

    @objc private func viewChanged(_ note: Notification) { scheduleSessionSave() }

    /// Folder Options > Keep running when the last window closes (on: Explorer stays alive; Cmd+Q quits).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        uitest == nil && !ListOptions.folder.keepRunning
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closeTab(_:)): return NSApp.keyWindow != nil
        case #selector(reopenClosedTab(_:)): return closedTabs.count > 0
        case #selector(tileWindows(_:)): return !windows.isEmpty
        case #selector(toggleFolderHandler(_:)): item.state = SystemSettings.foldersOpenInFolio ? .on : .off
        case #selector(toggleLaunchAtLogin(_:)): item.state = SystemSettings.launchesAtLogin ? .on : .off
        case #selector(toggleKeepRunning(_:)): item.state = ListOptions.folder.keepRunning ? .on : .off
        default: break
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveSession()
        terminating = true
        // File promises from Folio's last drag would hold up quitting (AppKit resolves them all).
        DragState.releasePasteboard()
        return .terminateNow
    }

    /// folio: URLs from `ff`, and folders or files sent by other apps (Launch Services, `open -a`, the Dock).
    func application(_ sender: NSApplication, open urls: [URL]) {
        guard uitest == nil else { return }
        for url in urls {
            if let request = FolioRequest.parse(url) {
                open(request)
                continue
            }
            guard url.isFileURL else { continue }
            // A saved search runs again, live.
            if url.pathExtension.lowercased() == SavedSearch.fileExtension, let saved = try? SavedSearch.read(from: url) {
                openSavedSearch(saved)
                continue
            }
            open(FolioRequest(path: url.path))
        }
        NSApp.activate()
    }

    /// A folder (or a file, selected in its folder, or a search) in the window and tab the request asks
    /// for. Usually: a tab already on that folder comes to the front; otherwise a new tab in the front
    /// window (Folder Options > Open external folder links in a new tab) or a new window.
    func open(_ request: FolioRequest) {
        guard let plan = request.plan(kind: Self.kind) else {
            let alert = NSAlert()
            alert.messageText = "Folio can't find \u{201C}\(request.resolvedPath ?? "")\u{201D}"
            alert.informativeText = "Check the spelling and try again."
            alert.runModal()
            return
        }
        let folder = plan.folder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.startPlace
        let select = plan.select.map { FilePaths.itemKey(URL(fileURLWithPath: $0)) }
        let front = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            .first { c in windows.contains { $0 === c } }
        var tab = BrowserTab(folder: folder)
        if let search = plan.search { tab.history.push(folder, search: HistorySearch(text: search)) }
        if let select { tab.selection = [select] }
        var placement = plan.placement
        if placement == .usual {
            if let (controller, index) = existingTab(on: folder) {
                controller.showExisting(tab: index, selecting: select, search: plan.search)
                return
            }
            placement = ListOptions.folder.externalFoldersInNewTab ? .newTab : .newWindow
        }
        if placement == .newTab, let front {
            front.openRequestedTab(tab)
            return
        }
        openWindow(with: [tab], active: 0, near: nil, size: nil).window?.makeKeyAndOrderFront(nil)
    }

    /// The first tab (front window first) showing this folder, not a search.
    private func existingTab(on folder: URL) -> (BrowserWindowController, Int)? {
        let key = FilePaths.folderKey(folder)
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            .filter { c in windows.contains { $0 === c } }
        for c in ordered + windows.filter({ c in !ordered.contains { $0 === c } }) {
            if let i = c.tabs.tabs.firstIndex(where: { t in
                t.history.search == nil && (NavigationHistory.isHome(folder) ? t.history.isHome
                    : !t.history.isHome && FilePaths.folderKey(t.current) == key)
            }) { return (c, i) }
        }
        return nil
    }

    /// A package (an app, a bundle) is an item to select, not a folder to open.
    nonisolated private static func kind(_ path: String) -> FolioRequest.ItemKind {
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &dir) else { return .missing }
        return dir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: path) ? .folder : .file
    }

    /// A window on the saved search's place with the search shown (Back goes to the plain folder).
    @discardableResult
    func openSavedSearch(_ saved: SavedSearch) -> BrowserWindowController {
        let place: URL
        switch saved.location {
        case .folder(let url): place = url
        case .home: place = NavigationHistory.home
        case .thisPC: place = URL(fileURLWithPath: "/", isDirectory: true)
        }
        var history = NavigationHistory(start: place)
        history.push(place, search: HistorySearch(text: saved.text, recursive: saved.recursive, everywhere: saved.location == .thisPC))
        let controller = openWindow(with: [BrowserTab(history: history)], active: 0, near: nil, size: nil)
        // The results' own grouping and sort, as saved (the tab's grouping outside the search stays).
        controller.group = saved.group
        if let first = saved.sort.first {
            controller.searchSort = SortSpec(key: first.key, ascending: first.ascending, then: Array(saved.sort.dropFirst()))
        }
        if saved.group != nil || !saved.sort.isEmpty { controller.rearrange() }
        if let raw = saved.view, let mode = ViewMode(rawValue: raw), mode != .details { controller.chooseView(mode) }
        return controller
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && uitest == nil { openWindow(at: Self.startPlace) }
        return true
    }

    // MARK: Windows

    private var keyController: BrowserWindowController? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)
            ?? (NSApp.mainWindow?.windowController as? BrowserWindowController)
    }

    /// Cmd+N: another window on the folder this one shows (Home when none is open).
    @objc func newWindow(_ sender: Any?) {
        openWindow(at: keyController?.history.current ?? Self.startPlace)
    }

    /// Cmd+T with no window open.
    @objc func newTab(_ sender: Any?) { openWindow(at: Self.startPlace) }

    /// Folder Options > Open Folio to: Home, or This PC (the startup disk, as the This PC search does).
    static var startPlace: URL {
        ListOptions.folder.openTo == .thisPC ? URL(fileURLWithPath: "/", isDirectory: true) : NavigationHistory.home
    }

    /// Cmd+W in a window that has no tabs (Properties): it closes.
    @objc func closeTab(_ sender: Any?) { NSApp.keyWindow?.performClose(nil) }

    /// Cmd+Shift+T with no Folio window open: the tab comes back in a window of its own.
    @objc func reopenClosedTab(_ sender: Any?) {
        guard let entry = closedTabs.pop() else { NSSound.beep(); return }
        openWindow(with: [entry.tab], active: 0, near: nil, size: nil)
    }

    @discardableResult
    func openWindow(at folder: URL) -> BrowserWindowController {
        openWindow(with: [BrowserTab(folder: folder)], active: 0, near: nil, size: nil)
    }

    /// A window with these tabs. `near` (a screen point) puts its tab strip under the pointer, for a
    /// tab torn out of another window.
    @discardableResult
    func openWindow(with tabs: [BrowserTab], active: Int, near point: NSPoint?, size: NSSize?,
                    frame: NSRect? = nil) -> BrowserWindowController {
        let controller = BrowserWindowController(tabs: tabs, active: active)
        if let window = controller.window {
            if let frame {
                window.setFrame(Self.onScreen(frame), display: false)
            } else {
                if let size { window.setContentSize(size) }
                if let point {
                    window.setFrameTopLeftPoint(NSPoint(x: point.x - 120, y: point.y + ChassisView.titleH + 18))
                } else if windows.isEmpty {
                    window.center()
                } else {
                    cascadePoint = window.cascadeTopLeft(from: cascadePoint)
                }
            }
        }
        windows.append(controller)
        controller.showWindow(nil)
        scheduleSessionSave()
        return controller
    }

    /// A saved frame, moved back onto a screen if the screen it was on is gone.
    private static func onScreen(_ frame: NSRect) -> NSRect {
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return frame }
        guard let screen = NSScreen.main?.visibleFrame else { return frame }
        return NSRect(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2, width: frame.width, height: frame.height)
    }

    func windowClosed(_ controller: BrowserWindowController) {
        windows.removeAll { $0 === controller }
        scheduleSessionSave()
    }

    /// Window > Tile left and right: this window on the left half of the screen, the other Folio
    /// window (a new one on the same folder when there is none) on the right.
    @objc func tileWindows(_ sender: Any?) {
        guard let key = keyController ?? windows.last else { return }
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
        let other = ordered.first { $0 !== key } ?? openWindow(at: key.history.current)
        guard let screen = key.window?.screen ?? NSScreen.main else { return }
        let f = screen.visibleFrame
        let half = floor(f.width / 2)
        key.window?.setFrame(NSRect(x: f.minX, y: f.minY, width: half, height: f.height), display: true)
        other.window?.setFrame(NSRect(x: f.minX + half, y: f.minY, width: f.width - half, height: f.height), display: true)
        other.window?.orderFront(nil)
        key.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Session

    /// Saves the windows and their tabs half a second after the last change (Explorer's restore at logon).
    func scheduleSessionSave() {
        guard uitest == nil, !terminating else { return }
        sessionTimer?.invalidate()
        let timer = Timer(timeInterval: SessionStore.coalesce, repeats: false) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.saveSession() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
    }

    func saveSession() {
        guard uitest == nil, !terminating else { return }
        sessionTimer?.invalidate()
        sessionTimer = nil
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
        let all = ordered.filter { c in windows.contains { $0 === c } } + windows.filter { c in !ordered.contains { $0 === c } }
        let session = Session(windows: all.compactMap { $0.windowSession() }, viewMode: ViewCenter.shared.mode.rawValue)
        do {
            try SessionStore().save(session)
        } catch {
            perfLog.error("session not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the saved windows, back to front so the front one ends up in front, each on the display it
    /// was on. False when there is nothing to restore (no file, Reopen windows off, or a damaged file,
    /// which is moved aside so the app starts on its start place).
    private func restoreSession() -> Bool {
        switch SessionStore().load() {
        case .none:
            return false
        case .corrupt(let aside):
            perfLog.error("session file did not read; moved to \(aside?.path ?? "nowhere", privacy: .public)")
            return false
        case .session(let session):
            guard ListOptions.folder.reopenWindows, !session.windows.isEmpty else { return false }
            if let raw = session.viewMode, let mode = ViewMode(rawValue: raw) { ViewCenter.shared.set(mode) }
            let fm = FileManager.default
            func exists(_ path: String) -> Bool {
                var dir: ObjCBool = false
                return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
            }
            let screens = NSScreen.screens.map { s in
                ScreenInfo(name: s.localizedName, frame: SessionFrame(s.frame), visible: SessionFrame(s.visibleFrame))
            }
            for saved in session.windows.reversed() where !saved.tabs.isEmpty {
                let tabs = saved.tabs.map { $0.tab(exists: exists) }
                let f = WindowPlacement.place(saved.frame, display: saved.display, screens: screens)
                let controller = openWindow(with: tabs, active: saved.clampedActive, near: nil, size: nil,
                                            frame: NSRect(x: f.x, y: f.y, width: f.width, height: f.height))
                controller.restoreTree(saved.expandedFolders ?? [])
            }
            return !windows.isEmpty
        }
    }

    // MARK: Folio and macOS (the Folio menu, Folder Options > General)

    /// Open folders in Folio instead of Finder: asks Launch Services, reads back what it kept, and says so.
    @objc func toggleFolderHandler(_ sender: Any?) {
        setFolderHandler(on: !SystemSettings.foldersOpenInFolio, sheetOn: nil)
    }

    func setFolderHandler(on: Bool, sheetOn window: NSWindow?, done: (() -> Void)? = nil) {
        let report = SystemSettings.setFoldersOpenInFolio(on)
        let alert = NSAlert()
        alert.messageText = report.headline
        alert.informativeText = report.details + "\n\n" + report.note
        alert.alertStyle = report.allAccepted ? .informational : .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window) { _ in MainActor.assumeIsolated { done?() } }
        } else {
            alert.runModal()
            done?()
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        setLaunchAtLogin(!SystemSettings.launchesAtLogin, sheetOn: nil)
    }

    func setLaunchAtLogin(_ on: Bool, sheetOn window: NSWindow?, done: (() -> Void)? = nil) {
        guard let problem = SystemSettings.setLaunchAtLogin(on) else { done?(); return }
        let alert = NSAlert()
        alert.messageText = on ? "Folio was not added to your login items" : "Folio was not taken out of your login items"
        alert.informativeText = problem
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window) { _ in MainActor.assumeIsolated { done?() } }
        } else {
            alert.runModal()
            done?()
        }
    }

    @objc func toggleKeepRunning(_ sender: Any?) {
        var options = ListOptions.folder
        options.keepRunning.toggle()
        ListOptions.apply(options)
    }
}
