import AppKit
import FolioCore
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
            ThemeController.shared.start(defaults: uitest.defaults)
            ThemeController.shared.theme = uitest.theme
            ThemeController.shared.accent = uitest.accent
        } else {
            ThemeController.shared.start(defaults: .standard)
        }
        NSApp.mainMenu = MainMenu.build()
        // Other apps' Services take the selected files' URLs or paths (the menus' Services submenu).
        NSApp.registerServicesMenuSendTypes([.fileURL, .string], returnTypes: [])
        VolumeCenter.shared.start()
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
        // Folders passed with `open -a` or dropped on the Dock icon arrive in application(_:open:) first;
        // then those windows open and the saved session does not. Otherwise the last session comes back.
        if windows.isEmpty && !restoreSession() { openWindow(at: NavigationHistory.home) }
        VolumeCenter.shared.remountMappedShares()
        NSApp.activate()
    }

    // MARK: View > Theme, View > Accent

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ThemeChoice(rawValue: raw) else { return }
        ThemeController.shared.theme = choice
    }

    @objc func selectAccent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = AccentChoice(rawValue: raw) else { return }
        ThemeController.shared.accent = choice
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let raw = item.representedObject as? String
        switch item.action {
        case #selector(selectTheme(_:)): item.state = raw == ThemeController.shared.theme.rawValue ? .on : .off
        case #selector(selectAccent(_:)): item.state = raw == ThemeController.shared.accent.rawValue ? .on : .off
        case #selector(closeTab(_:)): return NSApp.keyWindow != nil
        case #selector(reopenClosedTab(_:)): return closedTabs.count > 0
        case #selector(tileWindows(_:)): return !windows.isEmpty
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

    func application(_ sender: NSApplication, open urls: [URL]) {
        guard uitest == nil else { return }
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            openWindow(at: isDirectory.boolValue ? url : url.deletingLastPathComponent())
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && uitest == nil { openWindow(at: NavigationHistory.home) }
        return true
    }

    // MARK: Windows

    private var keyController: BrowserWindowController? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)
            ?? (NSApp.mainWindow?.windowController as? BrowserWindowController)
    }

    /// Cmd+N: another window on the folder this one shows (Home when none is open).
    @objc func newWindow(_ sender: Any?) {
        openWindow(at: keyController?.history.current ?? NavigationHistory.home)
    }

    /// Cmd+T with no window open.
    @objc func newTab(_ sender: Any?) { openWindow(at: NavigationHistory.home) }

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

    /// Saves the windows and their tabs a moment after a change (Explorer's restore at logon).
    func scheduleSessionSave() {
        guard uitest == nil, !terminating else { return }
        sessionTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
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
        SessionStore(defaults: .standard).save(Session(windows: all.compactMap { $0.windowSession() }))
    }

    /// Opens the saved windows, back to front so the front one ends up in front. False when none.
    private func restoreSession() -> Bool {
        guard let session = SessionStore(defaults: .standard).load(), !session.windows.isEmpty else { return false }
        let fm = FileManager.default
        func exists(_ path: String) -> Bool {
            var dir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
        }
        for saved in session.windows.reversed() where !saved.tabs.isEmpty {
            let tabs = saved.tabs.map { $0.tab(exists: exists) }
            let f = saved.frame
            openWindow(with: tabs, active: saved.clampedActive, near: nil, size: nil,
                       frame: NSRect(x: f.x, y: f.y, width: f.width, height: f.height))
        }
        return !windows.isEmpty
    }
}
