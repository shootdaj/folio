import Foundation
import Testing
@testable import FolioCore

/// The VM script's tree, on a temp folder: three levels, files named for the matching rules, sizes
/// spread, a dot folder with a file, a phrase file.
private func searchTree() throws -> TestTree {
    let t = try TestTree()
    try t.file("work/Bert.txt", bytes: 120)
    try t.file("work/Albert.txt", bytes: 300)
    try t.file("work/level2/Bertie.md", bytes: 2000)
    try t.file("work/level2/my_bert.log", bytes: 900)
    try t.file("work/level2/level3/report-2024.txt", bytes: 40_000)
    let notes = try t.file("work/level2/level3/notes.txt", bytes: 0)
    try "needle in the text".write(to: notes, atomically: true, encoding: .utf8)
    try t.file("work/.stash/dotted-bert.txt", bytes: 10)
    try t.file("work/empty.txt", bytes: 0)
    return t
}

private func walk(_ t: TestTree, _ text: String, recursive: Bool = true, hidden: Bool = false, contents: Bool = false) throws -> [String] {
    var o = SearchWalk.Options()
    o.recursive = recursive
    o.includeHidden = hidden
    o.fileContents = contents
    let w = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(try parse(text)), options: o)
    return w.collect().map(\.entry.name).sorted()
}

@Suite(.serialized) struct SearchWalkTests {
    @Test func theWalkFindsWordStartsInEveryLevel() throws {
        let t = try searchTree(); defer { t.close() }
        #expect(try walk(t, "bert") == ["Bert.txt", "Bertie.md", "my_bert.log"])
        #expect(try walk(t, "*bert*") == ["Albert.txt", "Bert.txt", "Bertie.md", "my_bert.log"])
        #expect(try walk(t, "level2") == ["level2"])
    }

    @Test func aPlainWordFindsTagsAndNamesTheBulkListingGives() throws {
        let t = try searchTree(); defer { t.close() }
        try FileTags.setNames(["Projectx"], of: t.url("work/level2/level3/report-2024.txt"))
        try t.file("work/level2/IMG_0001.JPG", bytes: 5)
        #expect(try walk(t, "projectx") == ["report-2024.txt"], "tags hold the word")
        #expect(FileTags.hasTags(t.url("work/level2/level3/report-2024.txt")))
        #expect(!FileTags.hasTags(t.url("work/Bert.txt")))
        #expect(try walk(t, "img") == ["IMG_0001.JPG"])
        #expect(try walk(t, "kind:folder") == ["level2", "level3"])
    }

    @Test func currentFolderOnlyLooksOneLevel() throws {
        let t = try searchTree(); defer { t.close() }
        #expect(try walk(t, "bert", recursive: false) == ["Bert.txt"])
        #expect(try walk(t, "*bert*", recursive: false) == ["Albert.txt", "Bert.txt"])
    }

    @Test func dotFoldersAreWalkedOnlyWithHiddenItems() throws {
        let t = try searchTree(); defer { t.close() }
        #expect(try !walk(t, "dotted").contains("dotted-bert.txt"))
        #expect(try walk(t, "dotted", hidden: true) == ["dotted-bert.txt"])
        #expect(try walk(t, "bert", hidden: true) == ["Bert.txt", "Bertie.md", "dotted-bert.txt", "my_bert.log"])
    }

    @Test func contentsAreReadOnlyWithFileContentsOn() throws {
        let t = try searchTree(); defer { t.close() }
        #expect(try walk(t, "content:needle").isEmpty)
        #expect(try walk(t, "content:needle", contents: true) == ["notes.txt"])
        #expect(try walk(t, "needle", contents: true) == ["notes.txt"])
        #expect(try walk(t, "\"needle in the\"", contents: true) == ["notes.txt"])
        #expect(try walk(t, "\"in needle\"", contents: true).isEmpty)
    }

    @Test func propertiesKindsSizesAndNot() throws {
        let t = try searchTree(); defer { t.close() }
        #expect(try walk(t, "kind:document size:tiny") == ["Albert.txt", "Bert.txt", "Bertie.md", "my_bert.log", "notes.txt"])
        #expect(try walk(t, "size:empty") == ["empty.txt"])
        #expect(try walk(t, "kind:folder") == ["level2", "level3"])
        #expect(try walk(t, "NOT report") == ["Albert.txt", "Bert.txt", "Bertie.md", "empty.txt", "level2", "level3", "my_bert.log", "notes.txt"])
        #expect(try walk(t, "folder:level3") == ["notes.txt", "report-2024.txt"])
        // Made just now: all nine visible items are from today (the real today, not the fixture's).
        var o = SearchWalk.Options()
        o.recursive = true
        let today = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(try SearchQuery.parse("datemodified:today")), options: o)
        #expect(today.collect().count == 9)
    }

    @Test func contentsAreSizeCappedAndBinaryIsSkipped() throws {
        let t = try TestTree(); defer { t.close() }
        let big = try t.file("work/big.txt", bytes: 0)
        try String(repeating: "needle ", count: 1000).write(to: big, atomically: true, encoding: .utf8)
        let bin = try t.file("work/data.bin", bytes: 0)
        try Data([0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65, 0x00, 0x01]).write(to: bin)
        #expect(FileSubject.text(at: big, cap: 100) == nil)
        #expect(FileSubject.text(at: big, cap: 1_000_000)?.hasPrefix("needle") == true)
        #expect(FileSubject.text(at: bin, cap: 1_000_000) == nil)
    }

    @Test func progressCrawlsToOne() throws {
        let t = try searchTree(); defer { t.close() }
        let w = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(try parse("txt")), options: SearchWalk.Options())
        var progress: [Double] = []
        w.run(isCancelled: { false }) { _, p in progress.append(p) }
        #expect(progress.last == 1)
        #expect(progress == progress.sorted() || progress.allSatisfy { $0 <= 1 })
    }

    @Test func cancellingStopsTheWalk() throws {
        let t = try searchTree(); defer { t.close() }
        let w = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(.all), options: SearchWalk.Options())
        var batches = 0
        w.run(isCancelled: { true }) { _, _ in batches += 1 }
        #expect(batches == 0)
    }
}

@Suite struct SearchMergeTests {
    private func hit(_ path: String, _ score: Int = 0) -> SearchHit {
        SearchHit(entry: FileEntry(url: URL(fileURLWithPath: path), name: (path as NSString).lastPathComponent, isFolder: false,
                                   modified: nil, size: 1, kind: "Plain Text"), score: score)
    }

    @Test func spotlightAndTheWalkMergeByPath() {
        var m = SearchMerger()
        let spotlight = [hit("/private/tmp/a/Bert.txt", 350), hit("/private/tmp/a/b/my_bert.log", 300)]
        let walk = [hit("/private/tmp/a/Bert.txt", 350), hit("/private/tmp/a/.stash/x.txt", 300), hit("/private/tmp/a/b/my_bert.log", 300)]
        #expect(m.merge(spotlight).count == 2)
        let fresh = m.merge(walk)
        #expect(fresh.map(\.entry.name) == ["x.txt"])
        #expect(m.count == 3)
        #expect(m.contains(URL(fileURLWithPath: "/private/tmp/a/.stash/x.txt")))
    }

    @Test func rankedPutsRelevanceFirstThenNames() {
        let ranked = SearchMerger.ranked([hit("/w/zeta.txt", 100), hit("/w/Bert.txt", 350), hit("/w/file10.txt", 300), hit("/w/file2.txt", 300)])
        #expect(ranked.map(\.entry.name) == ["Bert.txt", "file2.txt", "file10.txt", "zeta.txt"])
    }
}

@Suite struct SearchPlanTests {
    @Test func placesSpotlightSkipsAreWalked() {
        #expect(SearchPlan.isSkippedBySpotlight("/private/tmp/folio-tests/x"))
        #expect(SearchPlan.isSkippedBySpotlight("/tmp"))
        #expect(SearchPlan.isSkippedBySpotlight("/Users/a/.Trash"))
        #expect(SearchPlan.isSkippedBySpotlight("/Users/a/code/.git/objects"))
        #expect(!SearchPlan.isSkippedBySpotlight("/Users/a/Documents"))
        #expect(!SearchPlan.isSkippedBySpotlight("/private/tmpfiles"))
        #expect(SearchPlan.needsWalk("/private/tmp/x", volumeIndexed: true, includeHidden: false))
        #expect(SearchPlan.needsWalk("/Volumes/USB", volumeIndexed: false, includeHidden: false))
        #expect(!SearchPlan.needsWalk("/Users/a/Documents", volumeIndexed: true, includeHidden: false))
        #expect(SearchPlan.needsWalk("/Users/a/Documents", volumeIndexed: true, includeHidden: true))
        #expect(SearchPlan.isSystemFolder("/System", home: "/Users/a"))
        #expect(SearchPlan.isSystemFolder("/Users/a/Library", home: "/Users/a"))
        #expect(!SearchPlan.isSystemFolder("/Applications", home: "/Users/a"))
    }

    @Test func mdutilOutput() {
        #expect(VolumeIndexing.parse("/:\n\tIndexing enabled. \n"))
        #expect(!VolumeIndexing.parse("/Volumes/USB:\n\tIndexing disabled.\n"))
        #expect(!VolumeIndexing.parse("/Volumes/X:\n\tError: unknown indexing state.\n"))
    }
}

/// The whole engine on a temp tree under /private/tmp, which Spotlight does not index (tested): the
/// Spotlight half finishes with nothing and the walk finds the files; both merge and the run ends.
@Suite(.serialized) struct SearchEngineTests {
    final class Box: @unchecked Sendable {
        var hits: [SearchHit] = []
        var done = false
        var progress: [Double] = []
        var updates = 0
        let lock = NSLock()
        func with<T>(_ body: (Box) -> T) -> T { lock.withLock { body(self) } }
    }

    private func run(_ t: TestTree, _ text: String, contents: Bool = false) async throws -> Box {
        var r = SearchRequest(query: try parse(text), location: .folder(t.url("work")))
        r.fileContents = contents
        let box = Box()
        let engine = SearchEngine(r) { u in
            box.with { b in
                b.hits += u.hits
                b.progress.append(u.progress)
                b.updates += 1
                if u.done { b.done = true }
            }
        }
        engine.start()
        let finished = await waitUntil(20) { box.with(\.done) }
        #expect(finished)
        return box
    }

    @Test func aSearchFinishesWithTheWalksHits() async throws {
        let t = try searchTree(); defer { t.close() }
        let box = try await run(t, "bert")
        #expect(box.hits.map(\.entry.name).sorted() == ["Bert.txt", "Bertie.md", "my_bert.log"])
        #expect(box.progress.last == 1)
    }

    @Test func fileContentsInAPlaceSpotlightSkips() async throws {
        let t = try searchTree(); defer { t.close() }
        let off = try await run(t, "content:needle")
        #expect(off.hits.isEmpty)
        let on = try await run(t, "content:needle", contents: true)
        #expect(on.hits.map(\.entry.name) == ["notes.txt"])
    }

    @Test func cancelledSearchesReportNothingMore() async throws {
        let t = try searchTree(); defer { t.close() }
        let box = Box()
        let engine = SearchEngine(SearchRequest(query: try parse("bert"), location: .folder(t.url("work")))) { _ in
            box.with { $0.updates += 1 }
        }
        engine.start()
        engine.cancel()
        try await Task.sleep(for: .milliseconds(600))
        #expect(box.with(\.updates) == 0)
    }
}
