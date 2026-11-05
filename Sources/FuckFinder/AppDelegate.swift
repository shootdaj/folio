import AppKit
import os

let perfLog = Logger(subsystem: "com.anshul.fuckfinder", category: "perf")

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    private var cascadePoint = NSPoint.zero

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = processStartDate
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Folders passed with `open -a` or dropped on the Dock icon arrive in application(_:open:) first.
        if windows.isEmpty { openWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
        NSApp.activate()
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
