import Foundation
import Testing
@testable import FolioCore

/// The ignore list: paths (a folder covers its subtree) and duplicate hashes, kept in the defaults.
@Suite struct SuggestionIgnoresTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/ignores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    private func item(_ path: String) -> SuggestionItem {
        SuggestionItem(url: URL(fileURLWithPath: path), isFolder: false, bytes: 10, logicalBytes: 10,
                       stamp: ItemStamp(device: 1, inode: 1, logical: 10, modified: nil))
    }

    private func suggestion(_ path: String) -> Suggestion {
        let i = item(path)
        return Suggestion(kind: .largeUnused, id: i.id, items: [i], bytes: 10, reason: .emptyFolder)
    }

    @Test func ignoredPathIsKeptAcrossLaunches() throws {
        try withDefaults { d in
            let s = suggestion("/private/tmp/folio-tests/ig/big.bin")
            SuggestionIgnores(defaults: d).ignore(s)
            let again = SuggestionIgnores(defaults: d)
            #expect(again.paths == [s.id])
            #expect(again.snapshot.covers(s.id))
            #expect(again.count == 1)
        }
    }

    @Test func ignoringADuplicateGroupStoresItsHash() throws {
        try withDefaults { d in
            let a = item("/private/tmp/folio-tests/ig/a"), b = item("/private/tmp/folio-tests/ig/b")
            let group = Suggestion(kind: .duplicates, id: "dup:cafe", items: [a, b], keep: a.url, bytes: 10,
                                   reason: .sameContent(copies: 2, sha256: "cafe", mayShareBlocks: false))
            let ignores = SuggestionIgnores(defaults: d)
            ignores.ignore(group)
            #expect(ignores.hashes == ["cafe"] && ignores.paths.isEmpty)
            #expect(ignores.snapshot.coversHash("cafe") && !ignores.snapshot.coversHash("beef"))
            // One copy, by its path.
            ignores.ignore(group, item: b)
            #expect(ignores.paths == [b.id])
        }
    }

    @Test func ignoredFolderCoversItsSubtreeButNotASiblingWithTheSamePrefix() {
        let snap = SuggestionIgnores.Snapshot(paths: ["/private/tmp/folio-tests/ig/a/b"])
        #expect(snap.covers("/private/tmp/folio-tests/ig/a/b"))
        #expect(snap.covers("/private/tmp/folio-tests/ig/a/b/c/d.txt"))
        #expect(!snap.covers("/private/tmp/folio-tests/ig/a/bc"))
        #expect(!snap.covers("/private/tmp/folio-tests/ig/a"))
        #expect(!SuggestionIgnores.Snapshot().covers("/anything"))
    }

    @Test func unignoreBringsItBack() throws {
        try withDefaults { d in
            let ignores = SuggestionIgnores(defaults: d)
            ignores.ignore(path: "/p/a")
            ignores.ignore(path: "/p/b")
            ignores.ignore(hash: "h1")
            ignores.unignore(path: "/p/a")
            ignores.unignore(hash: "h1")
            #expect(ignores.paths == ["/p/b"] && ignores.hashes.isEmpty)
            #expect(!ignores.snapshot.covers("/p/a"))
            ignores.removeAll()
            #expect(ignores.count == 0)
        }
    }

    @Test func ignoringTwiceKeepsOneEntryAtTheTop() throws {
        try withDefaults { d in
            let ignores = SuggestionIgnores(defaults: d)
            ignores.ignore(path: "/p/a")
            ignores.ignore(path: "/p/b")
            ignores.ignore(path: "/p/a")
            #expect(ignores.paths == ["/p/a", "/p/b"])
        }
    }

    @Test func cappedAtFiveThousandOldestDropped() throws {
        try withDefaults { d in
            let ignores = SuggestionIgnores(defaults: d)
            d.set((1...5_000).reversed().map { "/p/\($0)" }, forKey: SuggestionIgnores.pathsKey)
            for i in 5_001...5_010 { ignores.ignore(path: "/p/\(i)") }
            #expect(ignores.paths.count == 5_000)
            #expect(ignores.paths.first == "/p/5010" && ignores.paths.last == "/p/11")
        }
    }
}
