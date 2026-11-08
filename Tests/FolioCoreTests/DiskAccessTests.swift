import Foundation
import Testing
@testable import FolioCore

/// Folio asks once for Full Disk Access, so macOS stops asking for each guarded folder.
@Suite struct DiskAccessTests {
    @Test func theProbeIsTheUsersPrivacyDatabase() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(DiskAccess.probePath(home: home) == "/Users/someone/Library/Application Support/com.apple.TCC/TCC.db")
    }

    @Test func aMissingProbeReadsAsNotGranted() {
        let home = URL(fileURLWithPath: "/private/tmp/folio-tests/no-such-home-\(UUID().uuidString)")
        #expect(!DiskAccess.isGranted(home: home))
    }

    @Test func theSettingsLinkOpensFullDiskAccess() {
        #expect(DiskAccess.settingsURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    @Test func theAlertComesOnlyWhileTheGrantIsOffAndNotDismissed() {
        #expect(DiskAccess.shouldOffer(granted: false, dismissed: false))
        #expect(!DiskAccess.shouldOffer(granted: true, dismissed: false))
        #expect(!DiskAccess.shouldOffer(granted: false, dismissed: true))
        #expect(!DiskAccess.shouldOffer(granted: true, dismissed: true))
    }

    @Test func doNotAskAgainIsKept() throws {
        let name = "folio-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!DiskAccess.isDismissed(defaults))
        DiskAccess.setDismissed(defaults)
        #expect(DiskAccess.isDismissed(defaults))
    }
}
