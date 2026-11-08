import Foundation
import Testing
@testable import FolioCore

/// The bulk read (`getattrlistbulk`) gives each item the same values as the URL way it replaced.
@Suite struct BulkListingTests {
    /// A folder with one of each awkward thing: packages by extension and by bundle bit, a dot file, a
    /// flagged file, links to a folder and to a file, an alias, executables with and without an
    /// extension, odd and wide names, upper-case extensions and an empty extension.
    private func makeFixture() throws -> TestTree {
        let t = try TestTree()
        for f in ["notes.txt", "README", "Photo.JPG", "data.json", "archive.tar.gz", "name.", "café ünïcode.md",
                  "日本語.txt", ".zshrc", ".hidden.txt", "flagged.txt", "script.sh", "tool", "x.unknownext"] {
            _ = try t.file("fx/" + f)
        }
        try Data(repeating: 1, count: 4321).write(to: t.url("fx/sized.bin"))
        _ = try t.folder("fx/Plain Folder")
        _ = try t.folder("fx/Tool.app/Contents")
        _ = try t.folder("fx/Library.bundle")
        _ = try t.folder("fx/folder.with.dots")
        _ = try t.folder("fx/.dotfolder")
        try ItemFlags.setHidden(true, t.url("fx/flagged.txt"))
        for exe in ["fx/tool", "fx/script.sh"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.url(exe).path)
        }
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link-to-folder").path, withDestinationPath: "Plain Folder")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link-to-file").path, withDestinationPath: "notes.txt")
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/broken-link").path, withDestinationPath: "nowhere")
        let bookmark = try t.url("fx/notes.txt").bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: t.url("fx/notes alias"))
        return t
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
        func sameExceptDate(_ o: Row) -> Bool {
            path == o.path && name == o.name && kind == o.kind && isFolder == o.isFolder && isHidden == o.isHidden
                && isLink == o.isLink && size == o.size
        }
        var description: String { "\(name) kind=\(kind) folder=\(isFolder) hidden=\(isHidden) link=\(isLink) size=\(size.map(String.init) ?? "nil") modified=\(modified.map { "\($0.timeIntervalSince1970)" } ?? "nil")" }
    }

    private func compare(_ folder: URL, hidden: Bool, protected: Bool = false) throws {
        var bulkKinds: [String: String] = [:], urlKinds: [String: String] = [:]
        guard let bulk = BulkListing.entries(folder, includeHidden: hidden, hideProtected: protected, kinds: &bulkKinds) else {
            #expect(onSystemVolume(folder), "only the sealed system volume goes the URL way: \(folder.path)")
            return
        }
        let byURL = try FolderListing.listByURL(folder, includeHidden: hidden, hideProtected: protected, kinds: &urlKinds)
        let a = Dictionary(bulk.map { (Row($0).path, Row($0)) }, uniquingKeysWith: { x, _ in x })
        let b = Dictionary(byURL.map { (Row($0).path, Row($0)) }, uniquingKeysWith: { x, _ in x })
        #expect(Set(a.keys) == Set(b.keys), "\(folder.path) hidden=\(hidden): the same items")
        for (path, row) in b {
            guard let mine = a[path] else { continue }
            // A live folder (home, its Trash) can change between the two reads: a new date on an item
            // touched in the last two minutes is that change, not a difference in the reads.
            let recent = [mine.modified, row.modified].compactMap { $0 }.contains { Date().timeIntervalSince($0) < 120 }
            if recent, mine.sameExceptDate(row) { continue }
            #expect(mine == row, "\(path)\n bulk: \(mine)\n  url: \(row)")
        }
    }

    private func onSystemVolume(_ folder: URL) -> Bool {
        var fs = statfs()
        guard statfs(folder.path, &fs) == 0 else { return false }
        return withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } == "/"
    }

    @Test func theSystemVolumeGoesTheURLWay() {
        var kinds: [String: String] = [:]
        #expect(BulkListing.entries(URL(fileURLWithPath: "/"), includeHidden: true, hideProtected: false, kinds: &kinds) == nil,
                "/Applications and /Users are firmlinks there")
    }

    @Test func theFixtureReadsTheSameEitherWay() throws {
        let t = try makeFixture()
        defer { t.close() }
        try compare(t.url("fx"), hidden: false)
        try compare(t.url("fx"), hidden: true)
        try compare(t.url("fx"), hidden: true, protected: true)
    }

    @Test func realFoldersReadTheSameEitherWay() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["/", "/Applications", "/Volumes", "/usr/bin", "/System/Library/CoreServices", "/private/etc"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [home, home.appendingPathComponent("Downloads"), home.appendingPathComponent("Library"),
               URL(fileURLWithPath: "/Library"), URL(fileURLWithPath: "/Users"),
               URL(fileURLWithPath: "/Applications/Utilities"),
               // This repository: a git object folder holds thousands of files with no extension.
               URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
               URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                   .appendingPathComponent(".git")]
        for folder in folders where FileManager.default.isReadableFile(atPath: folder.path) {
            try compare(folder, hidden: true)
        }
    }

    @Test func aFolderThatCannotBeOpenedFallsBack() {
        var kinds: [String: String] = [:]
        #expect(BulkListing.entries(URL(fileURLWithPath: "/private/tmp/folio-tests/nope-\(UUID())"), includeHidden: false,
                                    hideProtected: false, kinds: &kinds) == nil)
    }
}
