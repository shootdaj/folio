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
}
