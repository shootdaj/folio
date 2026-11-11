import Foundation

/// Full Disk Access: the one grant that covers every place macOS guards (Desktop, Documents, Downloads,
/// iCloud Drive, other apps' data, removable and network volumes). Without it macOS asks once for each.
/// No app can turn it on: Folio > Full Disk Access… opens the System Settings page where the user does.
/// Release builds are signed with the same certificate every time, so the grant survives updates.
public enum DiskAccess {
    /// Privacy & Security > Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    public static let blockedFolder = "macOS blocked this folder. Folio > Full Disk Access… fixes it for all folders."
    public static let blockedRecycleBin = "Folio needs Full Disk Access to show the Recycle Bin (Folio > Full Disk Access…)"

    /// Whether macOS's privacy protection refused the folder: EPERM ("Operation not permitted"). A folder
    /// closed by its own permissions fails with EACCES instead, which Full Disk Access does not change.
    public static func isPrivacyDenial(_ error: any Error) -> Bool {
        var next: NSError? = error as NSError
        while let e = next {
            if e.domain == NSPOSIXErrorDomain { return e.code == Int(EPERM) }
            next = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// The status bar's line for a folder that did not list.
    public static func loadErrorText(_ error: any Error, isRecycleBin: Bool) -> String {
        guard isPrivacyDenial(error) else { return error.localizedDescription }
        return isRecycleBin ? blockedRecycleBin : blockedFolder
    }
}
