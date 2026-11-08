import Foundation

/// Full Disk Access: the one grant that covers every place macOS guards (Desktop, Documents, Downloads,
/// iCloud Drive, other apps' data, removable and network volumes). Without it macOS asks once for each.
/// No app can turn it on; Folio checks it and opens the System Settings page where the user turns it on.
public enum DiskAccess {
    public static let dismissedKey = "diskAccessDismissed"

    /// Privacy & Security > Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// The user's privacy database: readable only with Full Disk Access. A read without it fails (EPERM)
    /// and shows no prompt, and the try puts the app in the Full Disk Access list.
    public static func probePath(home: URL) -> String {
        home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
    }

    /// Whether this process can read the probe file.
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: probePath(home: home)) else { return false }
        try? handle.close()
        return true
    }

    /// The launch alert comes while the grant is off, until the user picks Do Not Ask Again.
    public static func shouldOffer(granted: Bool, dismissed: Bool) -> Bool { !granted && !dismissed }

    public static func isDismissed(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: dismissedKey) }
    public static func setDismissed(_ defaults: UserDefaults) { defaults.set(true, forKey: dismissedKey) }
}
