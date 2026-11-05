import AppKit
import FolioCore
import FolioLink
import ServiceManagement

/// Milestone 9 in the app: Folio and macOS (default folder handler, login item), the Dock icon, the
/// build's version, and the window side of requests from `ff`.

extension SessionFrame {
    init(_ r: NSRect) {
        self.init(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
}

/// The version `make app` wrote into Info.plist (`Folio --version`).
enum BuildInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown" }
    static var commit: String { Bundle.main.object(forInfoDictionaryKey: "FolioGitCommit") as? String ?? "unknown" }
    static var line: String { "Folio \(version) (\(commit))" }
}

/// What Folio asks of macOS itself: the default app for folders and drives (Launch Services), and the
/// login item (SMAppService). Both read back the Mac's real state; nothing is kept in Folio's defaults.
@MainActor
enum SystemSettings {
    /// Launch Services, as FolioCore's DefaultFolderHandler sees it.
    struct LaunchServices: HandlerRegistry {
        func defaultHandler(for contentType: String) -> String? {
            LSCopyDefaultRoleHandlerForContentType(contentType as CFString, .all)?.takeRetainedValue() as String?
        }

        func setDefaultHandler(_ bundleID: String, for contentType: String) -> Int32 {
            LSSetDefaultRoleHandlerForContentType(contentType as CFString, .all, bundleID as CFString)
        }
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? FolioRequest.bundleID }

    static var foldersOpenInFolio: Bool { DefaultFolderHandler.isFolio(bundleID: bundleID, registry: LaunchServices()) }

    static func setFoldersOpenInFolio(_ on: Bool) -> FolderHandlerReport {
        DefaultFolderHandler.apply(on: on, bundleID: bundleID, registry: LaunchServices())
    }

    static var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Nil when macOS did it; otherwise what went wrong, in words.
    static func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return error.localizedDescription
        }
        if on, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "macOS asks you to allow it: System Settings > General > Login Items, turn Folio on."
        }
        return nil
    }
}

/// The Dock icon follows the Mac's light or dark setting (Folio.icns in the bundle is the dark one).
@MainActor
enum DockIcon {
    static var systemIsDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    static func start() {
        update()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { update() } }
        }
    }

    static func update() {
        guard let image = AppIcon.render(pixels: 512, appearance: systemIsDark ? .dark : .light) else { return }
        NSApp.applicationIconImage = NSImage(cgImage: image, size: NSSize(width: 512, height: 512))
    }
}

// MARK: - Requests from ff and other apps, in a window

extension BrowserWindowController {
    /// A tab of this window already shows the folder: it comes to the front, with the item selected or
    /// the search run in it.
    func showExisting(tab index: Int, selecting key: String?, search: String?) {
        guard tabs.tabs.indices.contains(index) else { return }
        if index != tabs.activeIndex {
            if let key { tabs.modify(at: index) { $0.selection = [key]; $0.scrollRow = 0 } }
            activateTab(index)
        } else if let key, search == nil {
            reloadContents(select: [key])
        }
        if let search {
            history.push(history.current, search: HistorySearch(text: search))
            load()
            sessionChanged()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Explorer's "Open external folder links in a new tab": a tab at the end of the strip, shown.
    func openRequestedTab(_ tab: BrowserTab) {
        stashActiveTab()
        _ = tabs.append(tab)
        showActiveTab()
        window?.makeKeyAndOrderFront(nil)
    }
}
