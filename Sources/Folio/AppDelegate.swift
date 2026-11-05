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

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = processStartDate
        Fonts.registerBundled()
        ThemeController.shared.start(defaults: .standard)
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Folders passed with `open -a` or dropped on the Dock icon arrive in application(_:open:) first.
        if windows.isEmpty { openWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
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
        default: break
        }
        return true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            openWindow(at: isDirectory.boolValue ? url : url.deletingLastPathComponent())
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
        return true
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow(at: FileManager.default.homeDirectoryForCurrentUser)
    }

    func openWindow(at folder: URL) {
        let controller = BrowserWindowController(folder: folder)
        guard let window = controller.window else { return }
        if windows.isEmpty { window.center() }
        cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        windows.append(controller)
        controller.showWindow(nil)
    }

    func windowClosed(_ controller: BrowserWindowController) {
        windows.removeAll { $0 === controller }
    }
}
