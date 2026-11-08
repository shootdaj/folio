import Foundation

/// The global user defaults (`defaults write -g`), behind a protocol so the setting can be tested
/// without changing the Mac. The app's store uses CFPreferences in kCFPreferencesAnyApplication.
public protocol GlobalDefaults {
    func string(for key: String) -> String?
    /// Nil removes the key.
    func set(_ value: String?, for key: String)
}

/// What happened when Folio changed the setting.
public struct FileViewerReport: Equatable, Sendable {
    /// The other app that had the setting before Folio took it.
    public let replaced: String?
    /// Nil when macOS kept what Folio asked for.
    public let problem: String?
}

/// Folder Options > General: "Reveal in Folio instead of Finder".
///
/// AppKit reads the NSFileViewer default for "Reveal in Finder" and "Show in Finder" in other apps
/// (NSWorkspace activateFileViewerSelectingURLs: and selectFile:inFileViewerRootedAtPath:). Measured
/// on macOS 26.4.1: with NSFileViewer set to Folio, a reveal opens Folio, as an open-documents event.
/// Plain folder opens do not follow it: they go to the default app for folders. If the app it names
/// is missing, AppKit logs "Finder replacement ... not found" and does not use it. Scripts that address
/// Finder by name probably do not follow it (not measured).
public enum FileViewerSetting {
    public static let key = "NSFileViewer"

    /// A folder from these apps is opened, not revealed: a drop on Folio's Dock icon, and Finder's
    /// Open With > Folio.
    public static let openingApps: Set<String> = ["com.apple.dock", "com.apple.finder"]

    public static func isFolio(bundleID: String, defaults: GlobalDefaults) -> Bool {
        defaults.string(for: key)?.lowercased() == bundleID.lowercased()
    }

    /// On: NSFileViewer names Folio. Off: the key goes, so AppKit uses Finder again. Off removes the key
    /// only when it names Folio, so another app's choice stays. The value is read back after the write.
    public static func apply(on: Bool, bundleID: String, defaults: GlobalDefaults) -> FileViewerReport {
        let before = defaults.string(for: key)
        let wasFolio = before?.lowercased() == bundleID.lowercased()
        if on {
            if !wasFolio { defaults.set(bundleID, for: key) }
        } else if wasFolio {
            defaults.set(nil, for: key)
        }
        let kept = on ? isFolio(bundleID: bundleID, defaults: defaults) : !isFolio(bundleID: bundleID, defaults: defaults)
        let problem: String? = kept ? nil : on
            ? "macOS did not keep the setting. Reveals from other apps still go to Finder."
            : "macOS did not keep the setting. Reveals from other apps still go to Folio."
        return FileViewerReport(replaced: on && !wasFolio ? before : nil, problem: problem)
    }

    /// Whether a folder that came in an open-documents event is a reveal. A reveal shows the folder
    /// selected in its parent. An open shows the folder itself.
    ///
    /// Measured on macOS 26.4.1: a reveal, `NSWorkspace.open(_:withApplicationAt:)` and `open -a` send
    /// byte-identical events. Only the sender differs. A reveal comes from the app that asks for it.
    /// A command-line tool (`open -a`) is no app. So a folder is a reveal when Folio is the file viewer,
    /// the sender is an app, and the sender is not one of `openingApps` or Folio itself. A drive's root
    /// always opens, because Folio can be the default app for drives. Where Folio is also the default
    /// app for folders (macOS 15), another app's plain open of a folder looks the same as a reveal, so
    /// it shows the folder selected in its parent too.
    public static func isReveal(sender: String?, ownBundleID: String, fileViewer: String?, isVolumeRoot: Bool) -> Bool {
        guard !isVolumeRoot, let sender = sender?.lowercased(),
              fileViewer?.lowercased() == ownBundleID.lowercased() else { return false }
        return sender != ownBundleID.lowercased() && !openingApps.contains(sender)
    }
}
