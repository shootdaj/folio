import AppKit
import FolioCore

/// The one-time offer of Full Disk Access at launch, and Folio > Full Disk Access... any time.
@MainActor
enum DiskAccessPrompt {
    /// At launch: checks the grant (the check also lists Folio under Full Disk Access) and, while it is
    /// off, asks once, unless the user picked Do Not Ask Again.
    static func offerIfNeeded(defaults: UserDefaults = .standard) {
        guard DiskAccess.shouldOffer(granted: DiskAccess.isGranted(), dismissed: DiskAccess.isDismissed(defaults)) else { return }
        let alert = NSAlert()
        alert.messageText = "Give Folio Full Disk Access"
        alert.informativeText = """
            macOS asks again for each protected folder (Desktop, Documents, Downloads, iCloud Drive, other \
            apps' data, external and network drives). With Full Disk Access, macOS stops asking.

            In System Settings, turn on Folio under Full Disk Access, then quit and open Folio again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Do Not Ask Again")
        switch alert.runModal() {
        case .alertFirstButtonReturn: openSettings()
        case .alertThirdButtonReturn: DiskAccess.setDismissed(defaults)
        default: break
        }
    }

    static func openSettings() {
        _ = DiskAccess.isGranted()  // the read puts Folio in the list
        NSWorkspace.shared.open(DiskAccess.settingsURL)
    }
}
