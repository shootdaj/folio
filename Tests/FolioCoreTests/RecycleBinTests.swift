import Foundation
import Testing
@testable import FolioCore

/// The Recycle Bin view (Original location, Date deleted, Restore) and the cloud folders (iCloud Drive
/// and ~/Library/CloudStorage) with their online-only badge.
@Suite struct RecycleBinTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/bin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    @Test func folioRemembersWhereTrashedItemsCameFrom() throws {
        try withDefaults { d in
            let origins = TrashOrigins(defaults: d)
            origins.record([TrashedItem(original: URL(fileURLWithPath: "/tmp/w/a.txt"),
                                        inTrash: URL(fileURLWithPath: "/tmp/trash/a.txt"))])
            #expect(origins.original(of: "/tmp/trash/a.txt") == "/tmp/w/a.txt")
            #expect(origins.original(of: "/tmp/trash/b.txt") == nil)
            origins.forget("/tmp/trash/a.txt")
            #expect(TrashOrigins(defaults: d).original(of: "/tmp/trash/a.txt") == nil)
        }
    }

    @Test func theBinShowsOriginalLocationAndDateDeleted() {
        let deleted = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = FileEntry(url: URL(fileURLWithPath: "/tmp/trash/a.txt"), name: "a.txt", isFolder: false,
                              modified: Date(timeIntervalSince1970: 1), size: 10, kind: "Plain Text")
        let other = FileEntry(url: URL(fileURLWithPath: "/tmp/trash/b"), name: "b", isFolder: true,
                              modified: nil, size: nil, kind: "Folder")
        let rows = RecycleBin.rows([entry, other], original: { $0 == "/tmp/trash/a.txt" ? "/tmp/w/a.txt" : nil },
                                   deleted: { $0.lastPathComponent == "a.txt" ? deleted : nil })
        #expect(rows[0].kind == "/tmp/w")
        #expect(rows[0].modified == deleted)
        #expect(rows[0].size == 10)
        #expect(rows[1].kind == RecycleBin.unknownLocation)
        #expect(rows[1].modified == nil)
    }

    @Test func restoreGoesBackToTheFolderItCameFrom() {
        #expect(RecycleBin.restoreFolder(original: "/tmp/w/a.txt") == URL(fileURLWithPath: "/tmp/w", isDirectory: true))
        #expect(RecycleBin.restoreFolder(original: nil) == nil)
    }

    @Test func theTrashFolderIsRecognisedWhateverItsSpelling() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(RecycleBin.isTrash(URL(fileURLWithPath: "/Users/someone/.Trash"), home: home))
        #expect(RecycleBin.isTrash(URL(fileURLWithPath: "/Users/someone/.Trash/"), home: home))
        #expect(!RecycleBin.isTrash(URL(fileURLWithPath: "/Users/someone/.Trash/sub"), home: home))
        #expect(!RecycleBin.isTrash(URL(fileURLWithPath: "/Users/someone"), home: home))
    }

    @Test func cloudFoldersAreFoundUnderTheHomeFolder() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.folder("home/Library/CloudStorage/Dropbox")
        try t.folder("home/Library/CloudStorage/GoogleDrive-anshul@example.com")
        try t.folder("home/Library/CloudStorage/OneDrive-Personal")
        try t.folder("home/Library/Mobile Documents/com~apple~CloudDocs")
        try t.file("home/Library/CloudStorage/.DS_Store")
        let places = CloudFolders.locations(home: t.url("home"))
        #expect(places.map(\.name) == ["iCloud Drive", "Dropbox", "Google Drive (anshul@example.com)", "OneDrive - Personal"])
        #expect(places.first?.path.hasSuffix("Mobile Documents/com~apple~CloudDocs") == true)
        #expect(CloudFolders.locations(home: t.url("nobody")).isEmpty)
        #expect(CloudFolders.isCloud(t.url("home/Library/CloudStorage/Dropbox/x"), home: t.url("home")))
        #expect(!CloudFolders.isCloud(t.url("home/Documents"), home: t.url("home")))
    }

    @Test func aPlainFileIsNotOnlineOnly() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("plain.txt")
        let entries = try FolderListing.list(t.root, includeHidden: false, cloud: true)
        #expect(entries.first { $0.name == "plain.txt" }?.isCloudOnly == false)
    }

    @Test func hiddenItemsListOnlyWhenAskedFor() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("seen.txt")
        try t.file(".unseen")
        #expect(!(try FolderListing.list(t.root)).map(\.name).contains(".unseen"))
        #expect((try FolderListing.list(t.root, includeHidden: true)).map(\.name).contains(".unseen"))
    }
}
