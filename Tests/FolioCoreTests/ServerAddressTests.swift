import Foundation
import Testing
@testable import FolioCore

/// Network: \\server\share and smb:// typed in the address bar or Connect to server, WebDAV and FTP
/// locations, and mapped shares remembered to mount again at the next launch.
@Suite struct ServerAddressTests {
    @Test func uncPathsBecomeSMBWithTheRestAsFolders() throws {
        let t = try #require(ServerAddress.parse(#"\\nas\media\films\2026"#))
        #expect(t.share.absoluteString == "smb://nas/media")
        #expect(t.rest == ["films", "2026"])
        let spaced = try #require(ServerAddress.parse(#"\\nas\My Share"#))
        #expect(spaced.share.absoluteString == "smb://nas/My%20Share")
        #expect(spaced.rest.isEmpty)
        let server = try #require(ServerAddress.parse(#"\\nas"#))
        #expect(server.share.absoluteString == "smb://nas", "just the server: macOS asks which share")
    }

    @Test func urlsKeepTheirSchemeAndUser() throws {
        #expect(ServerAddress.parse("smb://nas/media/films")?.share.absoluteString == "smb://nas/media")
        #expect(ServerAddress.parse("smb://nas/media/films")?.rest == ["films"])
        #expect(ServerAddress.parse("smb://anshul@nas.local/home")?.share.absoluteString == "smb://anshul@nas.local/home")
        #expect(ServerAddress.parse("afp://old-mac/Public")?.share.absoluteString == "afp://old-mac/Public")
        #expect(ServerAddress.parse("nfs://box/export/data")?.share.absoluteString == "nfs://box/export/data")
        #expect(ServerAddress.parse("nfs://box/export/data")?.rest.isEmpty == true, "NFS exports are whole paths")
        // WebDAV mounts read and write; FTP mounts read-only, as Finder does.
        #expect(ServerAddress.parse("https://dav.example.com/remote.php/dav")?.kind == .webDAV)
        #expect(ServerAddress.parse("ftp://ftp.example.com/pub")?.kind == .ftp)
        #expect(ServerAddress.parse("smb://nas/x")?.kind == .smb)
    }

    @Test func folderPathsAndCommandsAreNotServerAddresses() {
        #expect(ServerAddress.parse("/Users/someone") == nil)
        #expect(ServerAddress.parse("~/Downloads") == nil)
        #expect(ServerAddress.parse("terminal") == nil)
        #expect(ServerAddress.parse(#"\\"#) == nil)
        #expect(ServerAddress.parse("smb://") == nil)
        #expect(ServerAddress.parse("mailto:x@y.z") == nil)
    }

    @Test func mappedSharesAreRememberedOnceAndForgotten() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/shares-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let d = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        var shares = MappedShares(defaults: d)
        shares.add("smb://nas/media")
        shares.add("smb://nas/media")
        shares.add("afp://old-mac/Public")
        #expect(MappedShares(defaults: d).urls == ["smb://nas/media", "afp://old-mac/Public"])
        #expect(shares.contains("smb://nas/media"))
        shares.remove("smb://nas/media")
        #expect(MappedShares(defaults: d).urls == ["afp://old-mac/Public"])
    }
}
