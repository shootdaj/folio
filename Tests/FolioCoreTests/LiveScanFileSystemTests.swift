import Darwin
import Foundation
import Testing
@testable import FolioCore

/// The real disk behind the scan: listing, link targets, stamps and clones.
@Suite struct LiveScanFileSystemTests {
    private let fs = LiveScanFileSystem()

    @Test func aBrokenSymlinkIsMissingAndAWorkingOneExists() throws {
        let t = try TestTree()
        defer { t.close() }
        _ = try t.file("fx/real.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/good").path, withDestinationPath: "real.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/bad").path, withDestinationPath: "nothing.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/abs").path, withDestinationPath: t.url("fx/real.txt").path)
        #expect(fs.linkTarget(t.url("fx/good"), alias: false) == .exists)
        #expect(fs.linkTarget(t.url("fx/abs"), alias: false) == .exists)
        #expect(fs.linkTarget(t.url("fx/bad"), alias: false) == .missing(t.url("fx/nothing.txt").path))
    }

    @Test func aLinkToAnUnmountedVolumeIsOfflineNotBroken() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.folder("fx")
        let target = "/Volumes/folio-no-such-volume-\(UUID().uuidString)/x.txt"
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/far").path, withDestinationPath: target)
        #expect(fs.linkTarget(t.url("fx/far"), alias: false) == .offline(target))
    }

    @Test func aBrokenAliasIsMissingAndAWorkingOneExists() throws {
        let t = try TestTree()
        defer { t.close() }
        let target = try t.file("fx/notes.txt")
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: t.url("fx/notes alias"))
        #expect(fs.linkTarget(t.url("fx/notes alias"), alias: true) == .exists)
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
        let result = fs.linkTarget(t.url("fx/notes alias"), alias: true)
        guard case .missing(let path) = result else {
            Issue.record("expected a missing target, got \(result)")
            return
        }
        #expect(path.hasSuffix("/fx/notes.txt"))
    }

    @Test func anAliasToAMovedFileStillExists() throws {
        let t = try TestTree()
        defer { t.close() }
        let target = try t.file("fx/before.txt")
        try URL.writeBookmarkData(try target.bookmarkData(options: .suitableForBookmarkFile), to: t.url("fx/alias"))
        try FileManager.default.moveItem(at: target, to: t.url("fx/after.txt"))
        #expect(fs.linkTarget(t.url("fx/alias"), alias: true) == .exists)
    }

    @Test func listGivesTheValuesTheScanNeeds() throws {
        let t = try TestTree()
        defer { t.close() }
        _ = try t.file("fx/a.bin", bytes: 5_000)
        try FileManager.default.linkItem(at: t.url("fx/a.bin"), to: t.url("fx/b.bin"))
        _ = try t.folder("fx/sub")
        _ = try t.folder("fx/Thing.app")
        _ = try t.file("fx/.hidden")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link").path, withDestinationPath: "a.bin")
        let list = try fs.list(t.url("fx"))
        func entry(_ name: String) throws -> ScanEntry { try #require(list.first { $0.name == name }) }
        let a = try entry("a.bin")
        #expect(a.type == .file && a.logical == 5_000 && a.allocated >= 5_000 && a.linkCount == 2)
        #expect(a.fileID == (try entry("b.bin")).fileID)
        #expect(a.modified != nil && a.accessed != nil && a.added != nil)
        #expect(try entry("sub").type == .folder && entry("sub").logical == 0)
        #expect(try entry("Thing.app").isPackage)
        #expect(try entry(".hidden").isHidden)
        #expect(try entry("link").type == .symlink)
        #expect(!a.isDataless && !a.isLocked && !a.isAlias && !a.isMountPoint)
        #expect(throws: ScanReadError.missing) { try fs.list(t.url("nope")) }
    }

    @Test func listFallsBackOnTheSealedVolume() throws {
        let list = try fs.list(URL(fileURLWithPath: "/usr", isDirectory: true))
        #expect(list.contains { $0.name == "bin" && $0.type == .folder })
    }

    @Test func stampMatchesLstatAndAListing() throws {
        let t = try TestTree()
        defer { t.close() }
        let file = try t.file("fx/s.bin", bytes: 321)
        let stamp = try #require(fs.stamp(file))
        var st = stat()
        #expect(lstat(file.path, &st) == 0)
        #expect(stamp.device == st.st_dev && stamp.inode == UInt64(st.st_ino) && stamp.logical == 321)
        let listed = try #require(try fs.list(t.url("fx")).first)
        #expect(listed.modified == stamp.modified, "a listing and a stamp give the same date")
        #expect(listed.fileID == stamp.fileID)
        let folder = try #require(fs.stamp(t.url("fx")))
        #expect(folder.logical == 0)
        #expect(fs.stamp(t.url("fx/none")) == nil)
    }

    @Test func aCloneMayShareBlocksAndAPlainFileDoesNot() throws {
        let t = try TestTree()
        defer { t.close() }
        let original = try t.file("fx/orig.bin", bytes: 200_000)
        _ = try t.file("fx/plain.bin", bytes: 200_000, fill: 0x42)
        #expect(clonefile(original.path, t.url("fx/clone.bin").path, 0) == 0, "the temp folder is on APFS")
        #expect(fs.mayShareBlocks(t.url("fx/clone.bin")))
        #expect(!fs.mayShareBlocks(t.url("fx/plain.bin")))
        #expect(!fs.mayShareBlocks(t.url("fx/none.bin")))
    }

    @Test func patchedFSFakesOnlyWhatYouAskAndCounts() throws {
        let t = try TestTree()
        defer { t.close() }
        _ = try t.file("fx/a.bin")
        _ = try t.folder("fx/cloud")
        var p = PatchedFS()
        p.patch[t.url("fx/cloud").path] = { $0.isDataless = true }
        p.denied = [t.url("fx/cloud").path]
        p.lastUsedDates[t.url("fx/a.bin").path] = Date(timeIntervalSince1970: 5)
        let list = try p.list(t.url("fx"))
        #expect(list.first { $0.name == "cloud" }?.isDataless == true && list.first { $0.name == "a.bin" }?.isDataless == false)
        #expect(throws: ScanReadError.denied) { try p.list(t.url("fx/cloud")) }
        #expect(p.listed.count(of: t.url("fx").path) == 1)
        #expect(p.lastUsed(t.url("fx/a.bin")) == Date(timeIntervalSince1970: 5) && p.lastUsed(t.url("fx/b")) == nil)
        #expect(p.lookups.value == 2)
    }
}
