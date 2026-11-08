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
        let viaTmp = t.root.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        let urls = [t.url("dest/a.txt"), URL(fileURLWithPath: viaTmp + "/dest/a.txt"), t.url("dest/sub/b.txt"),
                    URL(fileURLWithPath: viaTmp + "/dest/./sub/../a.txt"), URL(fileURLWithPath: "/"),
                    URL(fileURLWithPath: viaTmp + "/dest/..."), URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())/x")]
        #expect(FilePaths.itemKeys(urls) == urls.map(FilePaths.itemKey))
    }

    @Test func aPlainPathHasNoDotPartsOrDoubleSlashes() {
        for p in ["/a", "/a/b.txt", "/a/.hidden", "/a/...", "/a/b..c", "/a/x."] { #expect(FilePaths.isPlain(p), "\(p)") }
        for p in ["/", "", "a/b", "/a/", "/a//b", "/a/./b", "/a/../b", "/a/.", "/a/.."] { #expect(!FilePaths.isPlain(p), "\(p)") }
    }
}
