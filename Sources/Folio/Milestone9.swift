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

/// The version `make app` wrote into Info.plist from the git tags (`Folio --version`): the whole version
/// (1.2.3, 1.2.3-4-gabc1234, 0.0.0-abc1234) and the short commit.
enum BuildInfo {
    static var version: String { info("FolioVersion") ?? info("CFBundleShortVersionString") ?? "unknown" }
    static var commit: String { info("FolioGitCommit") ?? "unknown" }
    static var line: String { "Folio \(version) (\(commit))" }
    private static func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }
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

    /// The global domain (`defaults write -g`), as FolioCore's FileViewerSetting sees it.
    struct GlobalPreferences: GlobalDefaults {
        func string(for key: String) -> String? {
            CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                   kCFPreferencesAnyHost) as? String
        }

        func set(_ value: String?, for key: String) {
            CFPreferencesSetValue(key as CFString, value as CFString?, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
    }

    /// Reveal in Folio instead of Finder: NSFileViewer names Folio.
    static var revealsInFolio: Bool { FileViewerSetting.isFolio(bundleID: bundleID, defaults: GlobalPreferences()) }

    static func setRevealsInFolio(_ on: Bool) -> FileViewerReport {
        FileViewerSetting.apply(on: on, bundleID: bundleID, defaults: GlobalPreferences())
    }

    /// Whether a folder in the open-documents event AppKit is handling now is a reveal from another app.
    static func isReveal(_ folder: URL) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let pid = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let sender = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        // /Volumes/Macintosh HD is a symlink to /, and isVolume is false for the link itself.
        let isVolumeRoot = (try? folder.resolvingSymlinksInPath().resourceValues(forKeys: [.isVolumeKey]))?.isVolume ?? false
        return FileViewerSetting.isReveal(sender: sender, ownBundleID: bundleID,
                                          fileViewer: GlobalPreferences().string(for: FileViewerSetting.key),
                                          isVolumeRoot: isVolumeRoot)
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

/// The Dock icon. In the bundle macOS draws Folio.icns itself (its shape, glass rim and shadow), so nothing
/// is set. A build run outside the bundle gets the same picture cut to the icon shape, since the Dock does
/// not mask an image set here.
@MainActor
enum DockIcon {
    static func start() {
        guard Bundle.main.bundleURL.pathExtension != "app", let image = AppIcon.masked(pixels: 512) else { return }
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
