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

/// Folder Options > General > Folio and macOS: Open "Show in Finder" from other apps in Folio.
///
/// AppKit reads the NSFileViewer default when an app asks NSWorkspace to reveal items
/// (activateFileViewerSelectingURLs:, selectFile:inFileViewerRootedAtPath:), which is what most apps'
/// "Show in Finder" and "Reveal in Finder" call. With NSFileViewer naming Folio, the reveal reaches Folio
/// as an open-documents event: a file then shows selected in its folder. Apps that send Finder an Apple
/// event or a script by name still go to Finder. Off by default: the key is not there on a new install.
public enum FileViewerSetting {
    public static let key = "NSFileViewer"

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
        let isFolio = isFolio(bundleID: bundleID, defaults: defaults)
        let problem: String? = on == isFolio ? nil
            : "macOS did not keep the setting. \u{201C}Show in Finder\u{201D} in other apps still goes to \(isFolio ? "Folio" : "Finder")."
        return FileViewerReport(replaced: on && !wasFolio ? before : nil, problem: problem)
    }
}
