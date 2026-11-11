import Foundation
import Testing
@testable import FolioCore

@Suite struct FilePathsTests {
    @Test func tmpAndPrivateTmpAreOneItem() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/a.mov")
        let viaPrivate = URL(fileURLWithPath: t.root.path + "/dest/a.mov")
        let viaTmp = URL(fileURLWithPath: t.root.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/") + "/dest/a.mov")
        #expect(viaTmp.path.hasPrefix("/tmp/"))
        #expect(FilePaths.itemKey(viaTmp) == FilePaths.itemKey(viaPrivate))
        #expect(FilePaths.parentKey(ofItemKey: FilePaths.itemKey(viaTmp)) == FilePaths.folderKey(viaPrivate.deletingLastPathComponent()))
        // A window on /tmp/.../dest, standardized the way the address bar does it.
        let window = URL(fileURLWithPath: t.root.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/") + "/dest").standardizedFileURL
        #expect(FilePaths.folderKey(window) == FilePaths.parentKey(ofItemKey: FilePaths.itemKey(viaPrivate)))
    }

    @Test func aSymlinkKeepsItsOwnName() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/target.txt")
        let link = t.url("dest/link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target.txt")
        #expect(FilePaths.itemKey(link).hasSuffix("/dest/link"))
    }

    @Test func missingItemsAndTheRootStillHaveKeys() {
        #expect(FilePaths.itemKey(URL(fileURLWithPath: "/")) == "/")
        #expect(FilePaths.itemKey(URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())/x")).hasSuffix("/x"))
        #expect(FilePaths.parentKey(ofItemKey: "/a") == "/")
    }

    @Test func manyKeysAtOnceAreTheKeysOneByOne() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/a.txt")
        try t.file("dest/sub/b.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("linked").path, withDestinationPath: t.url("dest").path)
        let viaTmp = t.root.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        let urls = [t.url("dest/a.txt"), URL(fileURLWithPath: viaTmp + "/dest/a.txt"), t.url("dest/sub/b.txt"),
                    URL(fileURLWithPath: viaTmp + "/dest/./sub/../a.txt"), URL(fileURLWithPath: "/"), t.url("linked/a.txt"),
                    URL(fileURLWithPath: viaTmp + "/dest/..."), URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())/x")]
        #expect(FilePaths.itemKeys(urls) == urls.map(FilePaths.itemKey))
    }

    @Test func aFolderListingsKeysAreItsKeysOneByOne() throws {
        // What the list and each Columns column key: a real listing (names with a space and an accent, a
        // link to a folder kept as the link), the same folder listed through /tmp, an item from another
        // folder after them, and the root.
        let t = try TestTree()
        defer { t.close() }
        for name in ["a.txt", "b c.txt", "é.txt"] { try t.file("dest/\(name)") }
        try t.file("dest/sub/inner.txt")
        try FileManager.default.createSymbolicLink(at: t.url("dest/link"), withDestinationURL: t.url("dest/sub"))
        let viaTmp = URL(fileURLWithPath: t.root.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/") + "/dest")
        let urls = try FolderListing.list(t.url("dest")).map(\.url) + FolderListing.list(viaTmp).map(\.url)
            + [t.url("dest/sub/inner.txt"), URL(fileURLWithPath: "/")]
        #expect(urls.count == 12)
        let keys = FilePaths.itemKeys(urls)
        #expect(keys == urls.map(FilePaths.itemKey))
        // The link stays the link in both listings (never its target, dest/sub).
        #expect(keys.filter { $0.hasSuffix("/dest/link") }.count == 2)
    }

    @Test func aPlainPathHasNoDotPartsOrDoubleSlashes() {
        for p in ["/a", "/a/b.txt", "/a/.hidden", "/a/...", "/a/b..c", "/a/x."] { #expect(FilePaths.isPlain(p), "\(p)") }
        for p in ["/", "", "a/b", "/a/", "/a//b", "/a/./b", "/a/../b", "/a/.", "/a/.."] { #expect(!FilePaths.isPlain(p), "\(p)") }
    }
}
