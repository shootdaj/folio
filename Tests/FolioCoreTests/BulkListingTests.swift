import Darwin
import Foundation
import Testing
@testable import FolioCore

/// The bulk read (`getattrlistbulk`) gives each item the same values as the URL way it replaced. Every
/// folder here is a temp tree under /private/tmp/folio-tests (RULES.md, rule 1): no home folders, no
/// system folders, nothing machine-dependent.
@Suite struct BulkListingTests {
    /// A folder with one of each awkward thing: packages by extension and by bundle bit (with and without
    /// an extension), a dot file, flagged and Finder-invisible files, links to a folder and to a file, a
    /// broken link, an alias, executables with and without an extension, odd and wide names, upper-case
    /// and empty extensions, a locked file and an empty one.
    private func makeFixture() throws -> TestTree {
        let t = try TestTree()
        for f in ["notes.txt", "README", "Photo.JPG", "data.json", "archive.tar.gz", "name.", "café ünïcode.md",
                  "日本語.txt", ".zshrc", ".hidden.txt", "flagged.txt", "invisible.txt", "script.sh", "tool", "x.unknownext",
                  "locked.txt", "Makefile"] {
            try t.file("fx/" + f)
        }
        try Data().write(to: t.url("fx/empty.txt"))
        try Data(repeating: 1, count: 4321).write(to: t.url("fx/sized.bin"))
        try t.folder("fx/Plain Folder")
        try t.folder("fx/Tool.app/Contents")
        try t.folder("fx/Library.bundle")
        try t.folder("fx/folder.with.dots")
        try t.folder("fx/.dotfolder")
        try t.folder("fx/BundleBit")
        try ItemFlags.setHidden(true, t.url("fx/flagged.txt"))
        try setFinderFlags(BulkListing.kIsInvisible, t.url("fx/invisible.txt"))
        try setFinderFlags(BulkListing.kHasBundle, t.url("fx/BundleBit"))
        for exe in ["fx/tool", "fx/script.sh"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.url(exe).path)
        }
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link-to-folder").path, withDestinationPath: "Plain Folder")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link-to-file").path, withDestinationPath: "notes.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/broken-link").path, withDestinationPath: "nowhere")
        let bookmark = try t.url("fx/notes.txt").bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: t.url("fx/notes alias"))
        try ItemFlags.setLocked(true, t.url("fx/locked.txt"))
        return t
    }

    private func setFinderFlags(_ flags: UInt16, _ url: URL) throws {
        var info = [UInt8](repeating: 0, count: 32)
        info[8] = UInt8(flags >> 8)
        info[9] = UInt8(flags & 0xFF)
        guard setxattr(url.path, "com.apple.FinderInfo", info, 32, 0, XATTR_NOFOLLOW) == 0 else { throw FileOpError.posix(errno, url) }
    }

    /// The locked file is unlocked so the tree can go to the Trash.
    private func close(_ t: TestTree) {
        try? ItemFlags.setLocked(false, t.url("fx/locked.txt"))
        t.close()
    }

    private struct Row: Equatable, CustomStringConvertible {
        let path, name, kind: String
        let isFolder, isHidden, isLink: Bool
        let size: Int64?
        let modified: Date?
        init(_ e: FileEntry) {
            path = e.url.standardizedFileURL.path
            name = e.name; kind = e.kind; isFolder = e.isFolder; isHidden = e.isHidden; isLink = e.isLink
            size = e.size; modified = e.modified
        }
        var description: String { "\(name) kind=\(kind) folder=\(isFolder) hidden=\(isHidden) link=\(isLink) size=\(size.map(String.init) ?? "nil") modified=\(modified.map { "\($0.timeIntervalSince1970)" } ?? "nil")" }
    }

    private func compare(_ folder: URL, hidden: Bool, protected: Bool = false) throws {
        var bulkKinds: [String: String] = [:], urlKinds: [String: String] = [:]
        let bulk = try #require(BulkListing.entries(folder, includeHidden: hidden, hideProtected: protected, kinds: &bulkKinds))
        let byURL = try FolderListing.listByURL(folder, includeHidden: hidden, hideProtected: protected, kinds: &urlKinds)
        let a = Dictionary(bulk.map { (Row($0).path, Row($0)) }, uniquingKeysWith: { x, _ in x })
        let b = Dictionary(byURL.map { (Row($0).path, Row($0)) }, uniquingKeysWith: { x, _ in x })
        #expect(Set(a.keys) == Set(b.keys), "hidden=\(hidden) protected=\(protected): the same items")
        for (path, row) in b {
            guard let mine = a[path] else { continue }
            #expect(mine == row, "\(path)\n bulk: \(mine)\n  url: \(row)")
        }
    }

    @Test func theFixtureReadsTheSameEitherWay() throws {
        let t = try makeFixture()
        defer { close(t) }
        try compare(t.url("fx"), hidden: false)
        try compare(t.url("fx"), hidden: true)
        try compare(t.url("fx"), hidden: true, protected: true)
        var kinds: [String: String] = [:]
        let shown = try #require(BulkListing.entries(t.url("fx"), includeHidden: false, hideProtected: false, kinds: &kinds))
        // Setting Finder's invisible bit sets the hidden flag too (the file system keeps them in step).
        #expect(!shown.contains { $0.name == "invisible.txt" || $0.name == "flagged.txt" || $0.name == ".zshrc" })
        #expect(shown.first { $0.name == "BundleBit" }?.isFolder == false, "the bundle bit makes a package")
    }

    @Test func rowsKnowLockedAndCustomIconFromTheListing() throws {
        let t = try makeFixture()
        defer { close(t) }
        try t.folder("fx/Iconned")
        try setFinderFlags(FolderIcon.hasCustomIconFlag, t.url("fx/Iconned"))
        var kinds: [String: String] = [:]
        let rows = try #require(BulkListing.entries(t.url("fx"), includeHidden: true, hideProtected: false, kinds: &kinds))
        func row(_ name: String) -> FileEntry? { rows.first { $0.name == name } }
        #expect(row("locked.txt")?.isLockedOrCompressed == true)
        #expect(row("notes.txt")?.isLockedOrCompressed == false)
        #expect(row("Iconned")?.mayHaveCustomIcon == true)
        #expect(row("Plain Folder")?.mayHaveCustomIcon == false, "no disk read for a folder without the flag")
        let unknown = try FolderListing.listByURL(t.url("fx"), includeHidden: true, hideProtected: false, kinds: &kinds)
        #expect(unknown.first { $0.name == "locked.txt" }?.isLockedOrCompressed == nil, "the URL way leaves it to the disk")
        #expect(unknown.first { $0.name == "Plain Folder" }?.mayHaveCustomIcon == true)
    }

    @Test func theListingKnowsWhichItemsHaveNoExtendedAttributes() throws {
        let t = try makeFixture()
        defer { close(t) }
        try FileTags.setNames(["Work"], of: t.url("fx/data.json"))
        var kinds: [String: String] = [:]
        let rows = try #require(BulkListing.entries(t.url("fx"), includeHidden: true, hideProtected: false, kinds: &kinds))
        var seen = 0
        for row in rows where !row.isLink {
            let real = listxattr(row.url.path, nil, 0, XATTR_NOFOLLOW) > 0
            if let known = row.hasExtendedAttributes {
                #expect(known == real, "\(row.name): listing says \(known), the disk \(real)")
                seen += 1
            }
        }
        #expect(seen > 10, "APFS gives the flag for every item")
        #expect(rows.first { $0.name == "data.json" }?.mayHaveTags == true)
        // And every other value still reads as the URL way gives it.
        try compare(t.url("fx"), hidden: true)
    }

    @Test func aFolderNeedingSeveralKernelCallsReadsEveryItem() throws {
        // 3,000 entries with long names fill the 256 KB buffer more than once.
        let t = try TestTree()
        defer { t.close() }
        let long = String(repeating: "n", count: 120)
        var kinds: [String: String] = [:]
        try FileManager.default.createDirectory(at: t.url("many"), withIntermediateDirectories: true)
        for i in 0..<3_000 { FileManager.default.createFile(atPath: t.url("many/\(long)-\(i).txt").path, contents: Data([1])) }
        let bulk = try #require(BulkListing.entries(t.url("many"), includeHidden: true, hideProtected: false, kinds: &kinds))
        #expect(bulk.count == 3_000)
        #expect(Set(bulk.map(\.name)).count == 3_000)
        try compare(t.url("many"), hidden: true)
    }

    @Test func theListingUsesTheBulkReadAndKeepsKindsBetweenFolders() throws {
        let t = try makeFixture()
        defer { close(t) }
        let listed = try FolderListing.list(t.url("fx"), includeHidden: false)
        var kinds: [String: String] = [:]
        let byURL = try FolderListing.listByURL(t.url("fx"), includeHidden: false, hideProtected: false, kinds: &kinds)
        #expect(Set(listed.map(Row.init).map(\.description)) == Set(byURL.map(Row.init).map(\.description)))
        #expect(KindCache.shared.snapshot()["bulk:ext:txt"] == byURL.first { $0.name == "notes.txt" }?.kind)
    }

    @Test func onlyTheSealedSystemVolumeGoesTheURLWay() {
        #expect(BulkListing.readsTheURLWay(mountedOn: "/"), "/Applications and /Users are firmlinks there")
        #expect(!BulkListing.readsTheURLWay(mountedOn: "/System/Volumes/Data"))
        #expect(!BulkListing.readsTheURLWay(mountedOn: "/Volumes/FolioScratch"))
    }

    @Test func aFolderThatCannotBeOpenedFallsBack() {
        var kinds: [String: String] = [:]
        #expect(BulkListing.entries(URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())"), includeHidden: false,
                                    hideProtected: false, kinds: &kinds) == nil)
        #expect(throws: (any Error).self) { try FolderListing.list(URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())")) }
    }
}
