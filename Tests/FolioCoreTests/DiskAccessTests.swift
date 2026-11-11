import Foundation
import Testing
@testable import FolioCore

/// Full Disk Access: Folio > Full Disk Access… opens its System Settings page, and a folder macOS refuses
/// says so in the status bar, pointing at that menu item. Folders closed by their own permissions keep
/// macOS's message, since Full Disk Access does not open them.
@Suite struct DiskAccessTests {
    /// What FileManager throws when macOS's privacy protection refuses a folder (`ls` prints "Operation not
    /// permitted" for the same folder).
    private func privacyDenial() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [
            NSFilePathErrorKey: "/Users/someone/Library/Mail",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
        ])
    }

    private func listingError(_ folder: URL) throws -> any Error {
        do {
            _ = try FolderListing.list(folder)
        } catch {
            return error
        }
        Issue.record("\(folder.path) listed")
        throw CancellationError()
    }

    @Test func theMenuItemOpensFullDiskAccessInSystemSettings() {
        #expect(DiskAccess.settingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    @Test func aFolderMacOSBlocksPointsAtTheMenuItem() {
        #expect(DiskAccess.isPrivacyDenial(privacyDenial()))
        #expect(DiskAccess.loadErrorText(privacyDenial(), isRecycleBin: false)
                == "macOS blocked this folder. Folio > Full Disk Access… fixes it for all folders.")
        // The bare POSIX error counts too.
        #expect(DiskAccess.isPrivacyDenial(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
    }

    @Test func theRecycleBinKeepsItsOwnLine() {
        #expect(DiskAccess.loadErrorText(privacyDenial(), isRecycleBin: true)
                == "Folio needs Full Disk Access to show the Recycle Bin (Folio > Full Disk Access…)")
    }

    @Test func aFolderClosedByItsPermissionsKeepsMacOSMessage() throws {
        let root = URL(fileURLWithPath: "/private/tmp/folio-tests/disk-access-\(UUID().uuidString)", isDirectory: true)
        let closed = root.appendingPathComponent("closed", isDirectory: true)
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: closed.path)
            try? FileManager.default.trashItem(at: root, resultingItemURL: nil)
        }
        let error = try listingError(closed)
        #expect(!DiskAccess.isPrivacyDenial(error))
        #expect(DiskAccess.loadErrorText(error, isRecycleBin: false) == error.localizedDescription)
    }

    @Test func otherFailuresKeepMacOSMessage() throws {
        let missing = URL(fileURLWithPath: "/private/tmp/folio-tests/disk-access-missing-\(UUID().uuidString)")
        let error = try listingError(missing)
        #expect(!DiskAccess.isPrivacyDenial(error))
        #expect(DiskAccess.loadErrorText(error, isRecycleBin: false) == error.localizedDescription)
        #expect(DiskAccess.loadErrorText(error, isRecycleBin: true) == error.localizedDescription)
    }

    @Test func infoPlistExplainsEachProtectedPlace() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for key in ["NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
                    "NSDownloadsFolderUsageDescription", "NSRemovableVolumesUsageDescription",
                    "NSNetworkVolumesUsageDescription"] {
            let text = plist[key] as? String ?? ""
            #expect(text.hasPrefix("Folio is a file manager"), "\(key): [\(text)]")
        }
    }
}
