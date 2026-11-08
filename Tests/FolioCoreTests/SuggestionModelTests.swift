import Foundation
import Testing
@testable import FolioCore

/// The Suggestions model: cards, removing and restoring rows, keeping another copy, Verify and the words.
@Suite struct SuggestionModelTests {
    private let home = URL(fileURLWithPath: "/private/tmp/folio-tests/model-home", isDirectory: true)

    private func item(_ path: String, bytes: Int64 = 100, ino: UInt64 = 1, modified: Date? = nil) -> SuggestionItem {
        SuggestionItem(url: URL(fileURLWithPath: path), isFolder: false, bytes: bytes, logicalBytes: bytes,
                       stamp: ItemStamp(device: 1, inode: ino, logical: bytes, modified: modified))
    }

    private func single(_ kind: SuggestionKind, _ path: String, bytes: Int64) -> Suggestion {
        let i = item(path, bytes: bytes)
        return Suggestion(kind: kind, id: i.id, items: [i], bytes: bytes, reason: .emptyFolder)
    }

    private func group(_ paths: [String], bytes: Int64 = 100, share: Bool = false, sha: String = "abc") -> Suggestion {
        let items = paths.enumerated().map { item($1, bytes: bytes, ino: UInt64($0 + 1)) }
        let reason = SuggestionReason.sameContent(copies: items.count, sha256: sha, mayShareBlocks: share)
        let keep = items[0].url
        return Suggestion(kind: .duplicates, id: "dup:" + sha, items: items, keep: keep,
                          bytes: Suggestion.saving(items, keep: keep, reason: reason), reason: reason)
    }

    @Test func removingTrashedPathsUpdatesBytesAndDropsSingletonDuplicateGroups() {
        let big = single(.largeUnused, "/private/tmp/folio-tests/m/big.bin", bytes: 900)
        let trio = group(["/private/tmp/folio-tests/m/a", "/private/tmp/folio-tests/m/b", "/private/tmp/folio-tests/m/c"])
        let pair = group(["/private/tmp/folio-tests/m/p", "/private/tmp/folio-tests/m/q"], sha: "def")
        let report = SuggestionReport(suggestions: [big, trio, pair], home: home)
        #expect(report.totalBytes == 900 + 200 + 100)

        let one = report.removing(keys: [trio.items[2].id])
        #expect(one.suggestions.count == 3)
        let shrunk = try? #require(one.suggestions.first { $0.id == trio.id })
        #expect(shrunk?.items.count == 2)
        #expect(shrunk?.bytes == 100)
        #expect(one.totalBytes == 900 + 100 + 100)

        let two = one.removing(keys: [pair.items[1].id, big.items[0].id])
        #expect(two.suggestions.map(\.id) == [trio.id], "the pair has one copy left and goes away")
        #expect(two.totalBytes == 100)
        #expect(report.removing(keys: []).suggestions.count == 3)
    }

    @Test func removingTheKeptCopyKeepsAnotherOne() throws {
        let trio = group(["/private/tmp/folio-tests/m/a", "/private/tmp/folio-tests/m/b", "/private/tmp/folio-tests/m/c"])
        let report = SuggestionReport(suggestions: [trio], home: home).removing(keys: [trio.items[0].id])
        let left = try #require(report.suggestions.first)
        #expect(left.items.count == 2)
        #expect(left.keep == left.items[0].url, "a group never has every copy removable")
        #expect(left.removable.count == 1)
    }

    @Test func restoringPutsRowsBackInOrderAndReplacesAGroup() {
        let big = single(.largeUnused, "/private/tmp/folio-tests/m/big.bin", bytes: 900)
        let trio = group(["/private/tmp/folio-tests/m/a", "/private/tmp/folio-tests/m/b", "/private/tmp/folio-tests/m/c"])
        let full = SuggestionReport(suggestions: [big, trio], home: home)
        let after = full.removing(keys: [big.items[0].id, trio.items[1].id, trio.items[2].id])
        #expect(after.suggestions.isEmpty && after.totalBytes == 0)
        let back = after.restoring([trio, big])
        #expect(back.suggestions.map(\.id) == [big.id, trio.id], "largeUnused comes before duplicates")
        #expect(back.totalBytes == full.totalBytes)
        let partly = full.removing(keys: [trio.items[2].id]).restoring([trio])
        #expect(partly.suggestions.count == 2 && partly.totalBytes == full.totalBytes, "the group is replaced, not doubled")
    }

    @Test func keepingAnotherCopyMovesItOutOfRemovable() {
        let g = group(["/private/tmp/folio-tests/m/a", "/private/tmp/folio-tests/m/b", "/private/tmp/folio-tests/m/c"], bytes: 50)
        #expect(g.removable.map(\.url.lastPathComponent) == ["b", "c"])
        #expect(g.bytes == 100)
        let other = g.keeping(g.items[2].url)
        #expect(other.keep == g.items[2].url)
        #expect(other.removable.map(\.url.lastPathComponent) == ["a", "b"])
        #expect(other.bytes == 100)
        #expect(g.keeping(URL(fileURLWithPath: "/private/tmp/folio-tests/m/zzz")) == g, "a URL outside the group changes nothing")
        let clones = group(["/private/tmp/folio-tests/m/a", "/private/tmp/folio-tests/m/b"], share: true)
        #expect(clones.bytes == 0 && clones.keeping(clones.items[1].url).bytes == 0, "copies that may share blocks free nothing")
    }

    @Test func cardsFollowKindOrderAndSortByBytes() throws {
        let list = [
            single(.emptyFolders, "/private/tmp/folio-tests/m/e", bytes: 0),
            single(.largeUnused, "/private/tmp/folio-tests/m/small.bin", bytes: 600),
            single(.trash, "/private/tmp/folio-tests/m/.Trash", bytes: 10),
            single(.largeUnused, "/private/tmp/folio-tests/m/huge.bin", bytes: 900),
            single(.largeUnused, "/private/tmp/folio-tests/m/also.bin", bytes: 600),
        ]
        let cards = SuggestionReport(suggestions: list, home: home).cards()
        #expect(cards.map(\.kind) == [.trash, .largeUnused, .emptyFolders], "kinds with nothing have no card")
        let large = try #require(cards.first { $0.kind == .largeUnused })
        #expect(large.suggestions.map { $0.items[0].url.lastPathComponent } == ["huge.bin", "also.bin", "small.bin"])
        #expect(large.bytes == 2100)
        #expect(SuggestionKind.allCases.map(\.rawValue).first == "trash")
        #expect(!SuggestionKind.trash.canMoveToTrash && !SuggestionKind.trash.canIgnore && SuggestionKind.brokenLinks.canMoveToTrash)
    }

    @Test func outermostDropsPathsInsideOthersAndRepeats() {
        let urls = ["/private/tmp/folio-tests/o/a/b/c.txt", "/private/tmp/folio-tests/o/a", "/private/tmp/folio-tests/o/ab",
                    "/private/tmp/folio-tests/o/a", "/private/tmp/folio-tests/o/z/y"].map { URL(fileURLWithPath: $0) }
        let out = SuggestionReport.outermost(urls).map(\.path)
        #expect(out == ["/private/tmp/folio-tests/o/a", "/private/tmp/folio-tests/o/ab", "/private/tmp/folio-tests/o/z/y"])
        #expect(SuggestionReport.outermost([]).isEmpty)
    }

    @Test func verifyDropsItemsReplacedOrChangedSinceTheScan() throws {
        let t = try TestTree()
        defer { t.close() }
        let fs = LiveScanFileSystem()
        let kept = try t.file("v/kept.bin", bytes: 100)
        let replaced = try t.file("v/replaced.bin", bytes: 100)
        let grown = try t.file("v/grown.bin", bytes: 100)
        let gone = try t.file("v/gone.bin", bytes: 100)
        func make(_ url: URL) throws -> SuggestionItem {
            SuggestionItem(url: url, isFolder: false, bytes: 4096, logicalBytes: 100, stamp: try #require(fs.stamp(url)))
        }
        let items = try [kept, replaced, grown, gone].map(make)
        // Same name, other file: the inode differs.
        try FileManager.default.removeItem(at: replaced)
        try Data(repeating: 0x42, count: 100).write(to: replaced)
        try Data(repeating: 0x42, count: 200).write(to: grown)
        try FileManager.default.removeItem(at: gone)
        let current = SuggestionVerify.current(items, fs: fs)
        #expect(current.map(\.url.lastPathComponent) == ["kept.bin"])
        // A touched modified date counts too.
        let touched = try t.file("v/touched.bin", bytes: 10)
        let before = try make(touched)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: touched.path)
        #expect(SuggestionVerify.current([before], fs: fs).isEmpty)
    }

    @Test func reasonTextReadsPlainly() throws {
        let locale = Locale(identifier: "en_US")
        let utc = try #require(TimeZone(identifier: "UTC"))
        let mar3 = Date(timeIntervalSince1970: 1_772_539_200)  // 3 Mar 2026, noon UTC
        func text(_ r: SuggestionReason) -> String { SuggestionText.reason(r, locale: locale, timeZone: utc) }
        #expect(text(.notUsedSince(mar3, .lastUsed)) == "Not opened since 3 Mar 2026")
        #expect(text(.notUsedSince(mar3, .modified)) == "Not changed since 3 Mar 2026")
        #expect(text(.sameContent(copies: 2, sha256: "x", mayShareBlocks: false)) == "2 copies, keep 1")
        #expect(text(.inDownloadsSince(mar3)) == "In Downloads since 3 Mar 2026")
        #expect(text(.installer(ext: "dmg", since: mar3)) == "DMG installer, added 3 Mar 2026")
        #expect(text(.installer(ext: "zip", since: mar3)) == "ZIP archive, added 3 Mar 2026")
        #expect(text(.trash(items: 1)) == "1 item in the Trash")
        #expect(text(.trash(items: 1234)) == "1,234 items in the Trash")
        #expect(text(.derivedData(projects: 3)) == "3 Xcode projects")
        #expect(text(.brokenLink(target: "/x/y")) == "Points to /x/y, which is missing")
        #expect(SuggestionText.title(.derivedData) == "Xcode build data")
        #expect(SuggestionText.size(512_000_000) == "512 MB")
        // The time zone decides the day.
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let lateNight = Date(timeIntervalSince1970: 1_772_539_200 + 13 * 3600)
        #expect(SuggestionText.reason(.inDownloadsSince(lateNight), locale: locale, timeZone: tokyo) == "In Downloads since 4 Mar 2026")
    }

    @Test func skipsKeepFiveSamplesForEachReason() {
        var skips = ScanSkips()
        for i in 1...8 { skips.add(.symlink, path: "/p/\(i)") }
        skips.add(.library, path: "/p/lib")
        #expect(skips.count(.symlink) == 8 && skips.samples[.symlink]?.count == 5)
        #expect(skips.samples[.symlink]?.first == "/p/1")
        #expect(skips.count(.library) == 1 && skips.count(.package) == 0)
    }

    @Test func theUITestConfigHasFloorsAFixtureCanMeet() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let c = SuggestionConfig.uitest(home: home, now: now, unit: 1024)
        #expect(c.largeFileMin == 48 * 1024 && c.duplicateMin == 1024 && c.cacheMin == 1024 && c.buildFolderMin == 1024)
        #expect(c.home == home && c.now == now && c.hashedAt.isEmpty)
        let d = SuggestionConfig(home: home, now: now)
        #expect(d.largeFileMin == 500_000_000 && d.kinds.count == SuggestionKind.allCases.count)
    }
}
