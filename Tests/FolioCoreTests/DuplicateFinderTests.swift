import Darwin
import Foundation
import Testing
@testable import FolioCore

/// Files in a temp home. Candidates are built from a real listing, as the walk does.
private struct DupHome {
    let t: TestTree
    let home: URL

    init() throws {
        t = try TestTree()
        home = try t.folder("Home")
    }

    func close() { t.close() }

    @discardableResult
    func file(_ path: String, bytes: Int = 200_000, fill: UInt8 = 0x41, modified: Date? = nil) throws -> URL {
        try t.file("Home/" + path, bytes: bytes, fill: fill, modified: modified)
    }

    func config(_ edit: (inout SuggestionConfig) -> Void = { _ in }) -> SuggestionConfig {
        var c = SuggestionConfig(home: home, now: Date())
        c.duplicateMin = 100_000
        edit(&c)
        return c
    }

    /// Every regular file under home, as the walk would hand it out.
    func candidates(fs: any ScanFileSystem = LiveScanFileSystem()) throws -> [DuplicateCandidate] {
        var out: [DuplicateCandidate] = []
        var stack = [home]
        while let dir = stack.popLast() {
            for e in try fs.list(dir) {
                let u = dir.appendingPathComponent(e.name)
                if e.type == .folder { stack.append(u); continue }
                guard e.type == .file else { continue }
                let stamp = ItemStamp(device: e.device, inode: e.inode, logical: e.logical, modified: e.modified)
                let item = SuggestionItem(url: u, isFolder: false, bytes: e.allocated, logicalBytes: e.logical,
                                          date: e.modified, dateSource: .modified, stamp: stamp)
                out.append(DuplicateCandidate(item: item, linkCount: e.linkCount))
            }
        }
        return out
    }

    func run(fs: any ScanFileSystem = LiveScanFileSystem(), ignores: SuggestionIgnores.Snapshot = .init(),
             isCancelled: @escaping () -> Bool = { false }, edit: (inout SuggestionConfig) -> Void = { _ in })
        throws -> DuplicateResult {
        DuplicateFinder.groups(try candidates(fs: fs), fs: fs, config: config(edit), ignores: ignores,
                               isCancelled: isCancelled, progress: { _, _ in })
    }

    func rel(_ u: URL?) -> String? { u.map { String($0.path.dropFirst(home.path.count + 1)) } }
}

@Suite struct DuplicateFinderTests {
    @Test func sameContentGroupsKeepOneCopyOutsideDownloads() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("Downloads/report.mov", fill: 0x5A)
        try h.file("Documents/report-final.mov", fill: 0x5A)
        try h.file("Desktop/report copy.mov", fill: 0x5A)
        try h.file("Documents/other.mov", fill: 0x5B)
        let r = try h.run()
        #expect(r.groups.count == 1)
        let g = try #require(r.groups.first)
        #expect(g.kind == .duplicates)
        #expect(g.id.hasPrefix("dup:") && g.id.count == 4 + 64)
        #expect(g.items.count == 3)
        #expect(h.rel(g.keep) == "Documents/report-final.mov")
        guard case .sameContent(let copies, let sha, let share) = g.reason else { Issue.record("reason"); return }
        #expect(copies == 3 && !share && g.id == "dup:" + sha)
        #expect(!r.partial)
    }

    @Test func theKeptCopyIsTheNewestThenTheShortestPath() throws {
        let h = try DupHome()
        defer { h.close() }
        let old = Date().addingTimeInterval(-9 * 86_400)
        let new = Date().addingTimeInterval(-86_400)
        try h.file("a/old.bin", modified: old)
        try h.file("b/newer.bin", modified: new)
        try h.file("c/new.bin", modified: new)
        let g = try #require(try h.run().groups.first)
        #expect(h.rel(g.keep) == "c/new.bin")
        // Ties on date: the shortest path wins.
        let t2 = try DupHome()
        defer { t2.close() }
        try t2.file("dir/long-name.bin", fill: 0x43, modified: new)
        try t2.file("x.bin", fill: 0x43, modified: new)
        let g2 = try #require(try t2.run().groups.first)
        #expect(t2.rel(g2.keep) == "x.bin")
    }

    @Test func differentMiddleByteIsNotADuplicate() throws {
        let h = try DupHome()
        defer { h.close() }
        let size = 600_000
        let a = try h.file("a.bin", bytes: size)
        let b = try h.file("b.bin", bytes: size)
        var data = try Data(contentsOf: b)
        data[size / 2] = 0x42
        try data.write(to: b)
        _ = a
        let r = try h.run()
        #expect(r.groups.isEmpty)
        // Both passed the partial hash, so both were read in full.
        #expect(r.hashed > Int64(2 * size))
    }

    @Test func hardlinksAreNotDuplicates() throws {
        let h = try DupHome()
        defer { h.close() }
        let a = try h.file("a.bin")
        try FileManager.default.createDirectory(at: h.home.appendingPathComponent("b"), withIntermediateDirectories: true)
        #expect(link(a.path, h.home.appendingPathComponent("b/link.bin").path) == 0)
        let r = try h.run()
        #expect(r.groups.isEmpty)
        #expect(r.hashed == 0)
    }

    @Test func filesUnderTheFloorAreNotHashed() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("a.bin", bytes: 20_000)
        try h.file("b.bin", bytes: 20_000)
        let r = try h.run(edit: { $0.duplicateMin = 1_000_000 })
        #expect(r.groups.isEmpty)
        #expect(r.hashed == 0)
    }

    @Test func differentSizesAreNeverHashed() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("a.bin", bytes: 200_000)
        try h.file("b.bin", bytes: 200_001)
        let r = try h.run()
        #expect(r.groups.isEmpty)
        #expect(r.hashed == 0)
    }

    @Test func reclaimableBytesCountAllButTheKeptCopy() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("a/one.bin")
        try h.file("b/two.bin")
        try h.file("c/three.bin")
        let g = try #require(try h.run().groups.first)
        let each = try #require(g.items.first?.bytes)
        #expect(each >= 200_000)
        #expect(g.bytes == each * 2)
        #expect(g.removable.count == 2 && !g.removable.contains { $0.url == g.keep })
    }

    @Test func ignoredCopyIsKeptNeverOffered() throws {
        let h = try DupHome()
        defer { h.close() }
        let ignored = try h.file("Downloads/ignored.bin")
        try h.file("Documents/plain.bin")
        let snap = SuggestionIgnores.Snapshot(paths: [FilePaths.itemKey(ignored)])
        let g = try #require(try h.run(ignores: snap).groups.first)
        #expect(h.rel(g.keep) == "Downloads/ignored.bin")
        #expect(g.removable.map { h.rel($0.url) } == ["Documents/plain.bin"])
    }

    @Test func twoIgnoredCopiesLeaveOnlyOneInTheGroup() throws {
        let h = try DupHome()
        defer { h.close() }
        let a = try h.file("a.bin"), b = try h.file("b.bin")
        try h.file("c.bin")
        let snap = SuggestionIgnores.Snapshot(paths: [FilePaths.itemKey(a), FilePaths.itemKey(b)])
        let g = try #require(try h.run(ignores: snap).groups.first)
        #expect(g.items.count == 2)
        #expect(g.removable.map { h.rel($0.url) } == ["c.bin"])
        #expect(["a.bin", "b.bin"].contains(h.rel(g.keep)))
    }

    @Test func ignoredHashDropsTheGroup() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("a.bin")
        try h.file("b.bin")
        let first = try #require(try h.run().groups.first)
        guard case .sameContent(_, let sha, _) = first.reason else { Issue.record("reason"); return }
        let r = try h.run(ignores: SuggestionIgnores.Snapshot(hashes: [sha]))
        #expect(r.groups.isEmpty)
    }

    @Test func clonedCopiesReportNoSavings() throws {
        let h = try DupHome()
        defer { h.close() }
        let a = try h.file("a.bin", bytes: 300_000)
        try FileManager.default.createDirectory(at: h.home.appendingPathComponent("b"), withIntermediateDirectories: true)
        let b = h.home.appendingPathComponent("b/clone.bin")
        guard clonefile(a.path, b.path, 0) == 0 else {
            Issue.record("clonefile failed: \(errno)")
            return
        }
        #expect(LiveScanFileSystem().mayShareBlocks(b))
        let g = try #require(try h.run().groups.first)
        guard case .sameContent(_, _, let share) = g.reason else { Issue.record("reason"); return }
        #expect(share)
        #expect(g.bytes == 0)
    }

    @Test func hashBudgetStopsLargestGroupsFirstAndLogsTheRest() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("big/a.bin", bytes: 400_000, fill: 0x01)
        try h.file("big/b.bin", bytes: 400_000, fill: 0x01)
        try h.file("small/a.bin", bytes: 150_000, fill: 0x02)
        try h.file("small/b.bin", bytes: 150_000, fill: 0x02)
        let r = try h.run(edit: { $0.hashBudgetBytes = 1_000_000 })
        // The budget counts full reads: the big pair (800k) fits, the small pair (300k more) does not.
        #expect(r.groups.count == 1)
        #expect(r.groups[0].items.allSatisfy { $0.url.path.contains("/big/") })
        #expect(r.partial)
        #expect(r.skips.count(.hashBudget) == 2)
        #expect(r.skips.samples[.hashBudget]?.allSatisfy { $0.contains("/small/") } == true)
    }

    @Test func timeBudgetStopsAndLogsTheRest() throws {
        let h = try DupHome()
        defer { h.close() }
        try h.file("a.bin")
        try h.file("b.bin")
        let ticks = LockedCounter()
        let r = try h.run(edit: { c in
            c.hashTimeBudget = 10
            // Every read of the clock moves it 100 seconds on.
            c.elapsed = { ticks.increment(); return TimeInterval(ticks.value) * 100 }
        })
        #expect(r.groups.isEmpty)
        #expect(r.partial)
        #expect(r.skips.count(.hashBudget) == 2)
    }

    @Test func cancelStopsMidFile() throws {
        let h = try DupHome()
        defer { h.close() }
        let size = 5 * 1_048_576
        let a = try h.file("a.bin", bytes: size)
        try h.file("b.bin", bytes: size)
        // The helper checks at each chunk and reads no more once it says stop.
        let calls = LockedCounter()
        let seen = LockedCounter()
        let sha = DuplicateFinder.sha256(a, range: nil, isCancelled: { calls.increment(); return calls.value > 2 },
                                         onChunk: { _ in seen.increment() })
        #expect(sha == nil)
        #expect(seen.value == 2)
        // The finder returns nothing after a cancel.
        let polls = LockedCounter()
        let r = try h.run(isCancelled: { polls.increment(); return polls.value > 6 })
        #expect(r.groups.isEmpty)
        #expect(r.partial)
        #expect(r.hashed < Int64(2 * size))
    }

    @Test func shaOfARangeMatchesTheBytes() throws {
        let h = try DupHome()
        defer { h.close() }
        let u = try h.file("a.bin", bytes: 1000, fill: 0x00)
        let whole = try #require(DuplicateFinder.sha256(u, range: nil, isCancelled: { false }))
        // SHA-256 of 1000 zero bytes.
        #expect(whole == "541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53")
        let part = try #require(DuplicateFinder.sha256(u, range: 0..<10, isCancelled: { false }))
        #expect(part == "01d448afd928065458cf670b60f5a594d735af0172c8d67f22a81680132681ca")
    }
}
