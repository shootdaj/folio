import Darwin
import Foundation
import Testing
@testable import FolioCore

/// A fake home in a temp folder, with files dated by age. Nothing here reads the real home.
private struct ScanHome {
    let t: TestTree
    let home: URL
    let now = Date()

    init() throws {
        t = try TestTree()
        home = try t.folder("Home")
    }

    func close() { t.close() }

    func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    /// A file of `kb` thousand bytes, all its dates `days` days old unless one is given.
    @discardableResult
    func file(_ path: String, kb: Int = 200, fill: UInt8 = 0x41, days: Double = 400, added: Double? = nil) throws -> URL {
        let u = try t.file("Home/" + path, bytes: kb * 1000, fill: fill)
        age(u, days: days, added: added)
        return u
    }

    func age(_ u: URL, days: Double, added: Double? = nil) {
        func date(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        let d = date(days)
        var times = [timeval(tv_sec: Int(d.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(d.timeIntervalSince1970), tv_usec: 0)]
        #expect(utimes(u.path, &times) == 0)
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var stamp = timespec(tv_sec: Int(date(added ?? days).timeIntervalSince1970), tv_nsec: 0)
        #expect(setattrlist(u.path, &request, &stamp, MemoryLayout<timespec>.size, 0) == 0)
    }

    /// Dates every folder under home, the deepest first.
    func ageFolders(days: Double) {
        var folders: [URL] = []
        if let walker = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let u as URL in walker where (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                folders.append(u)
            }
        }
        for u in folders.sorted(by: { $0.path.count > $1.path.count }) { age(u, days: days) }
        age(home, days: days)
    }

    func config(_ edit: (inout SuggestionConfig) -> Void = { _ in }) -> SuggestionConfig {
        var c = SuggestionConfig(home: home, now: now)
        c.largeFileMin = 100_000
        c.duplicateMin = 100_000
        c.cacheMin = 100_000
        c.buildFolderMin = 100_000
        edit(&c)
        return c
    }

    func scanner(fs: any ScanFileSystem = LiveScanFileSystem(), ignores: SuggestionIgnores.Snapshot = .init(),
                 _ edit: (inout SuggestionConfig) -> Void = { _ in }) -> SuggestionScanner {
        SuggestionScanner(config: config(edit), ignores: ignores, fs: fs)
    }

    func collect(_ edit: (inout SuggestionConfig) -> Void = { _ in }) -> SuggestionReport {
        scanner(edit).collect()
    }

    func rels(_ r: SuggestionReport, _ kind: SuggestionKind) -> [String] {
        r.suggestions.filter { $0.kind == kind }.flatMap(\.items)
            .map { String($0.url.path.dropFirst(home.path.count + 1)) }.sorted()
    }
}

@Suite struct SuggestionScanTests {
    @Test func entryCapStopsTheWalkAndMarksThePartialReport() throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<10 { try h.file("f\(i).bin") }
        h.ageFolders(days: 30)
        let r = h.collect { $0.maxEntries = 3 }
        #expect(r.isPartial)
        #expect(r.skips.count(.entryCap) == 1)
    }

    @Test func timeBudgetUsesTheInjectedClock() throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<10 { try h.file("f\(i).bin") }
        h.ageFolders(days: 30)
        let ticks = LockedCounter()
        let r = h.collect {
            $0.timeBudget = 5
            $0.elapsed = { ticks.increment(); return Double(ticks.value) }
        }
        #expect(r.isPartial)
        #expect(r.skips.count(.timeBudget) == 1)
    }

    @Test func depthCapSkipsDeeperFoldersAndLogsThem() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file("a/b/c/d/big.bin")
        try h.file("a/ok.bin")
        h.ageFolders(days: 30)
        let r = h.collect { $0.maxDepth = 2 }
        #expect(h.rels(r, .largeUnused) == ["a/ok.bin"])
        #expect(r.skips.count(.depthCap) == 1)
    }

    @Test func cancelReturnsAnEmptyReportFast() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file("big.bin")
        h.ageFolders(days: 30)
        let r = h.scanner().run(isCancelled: { true }, onProgress: { _ in }, onCards: { _ in })
        #expect(r.suggestions.isEmpty)
        #expect(r.isPartial)
        #expect(r.totalBytes == 0)
    }

    @Test func progressRisesAndEndsAtOne() throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<5 { try h.file("d\(i)/big.bin", fill: UInt8(i)) }
        try h.file("x/same1.bin", fill: 0x77)
        try h.file("y/same2.bin", fill: 0x77)
        h.ageFolders(days: 30)
        let log = LockedLog()
        _ = h.scanner().run(isCancelled: { false }, onProgress: { p in log.add("\(p.phase):\(p.fraction)") }, onCards: { _ in })
        let values = log.values
        #expect(values.first != nil)
        #expect(values.last == "done:1.0")
        let fractions = values.compactMap { Double($0.split(separator: ":").last ?? "") }
        #expect(fractions == fractions.sorted())
    }

    @Test func fixedPlaceCardsArriveBeforeTheWalkEnds() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file(".Trash/old.bin")
        try h.file("keep/big.bin")
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.denied = []
        let seenHome = LockedCounter()
        let cardKinds = LockedLog()
        let report = h.scanner(fs: fs).run(isCancelled: { false }, onProgress: { _ in }, onCards: { cards in
            if fs.listed.count(of: h.home.path) > 0 { seenHome.increment() }
            for c in cards { cardKinds.add(c.kind.rawValue) }
        })
        #expect(cardKinds.values.first == "trash")
        #expect(seenHome.value == 0)
        #expect(report.suggestions.contains { $0.kind == .trash })
    }

    @Test func skipsKeepFiveSamplePathsPerReason() throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<8 {
            try FileManager.default.createSymbolicLink(atPath: h.url("link\(i)").path, withDestinationPath: "/private/tmp")
        }
        let r = h.collect()
        #expect(r.skips.count(.symlink) == 8)
        #expect(r.skips.samples[.symlink]?.count == 5)
    }

    @Test func eachKindIsCappedButTheTotalCountsEverything() throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<5 { try h.file("big\(i).bin", kb: 200 + i * 100, fill: UInt8(i + 1)) }
        h.ageFolders(days: 30)
        let r = h.collect { $0.maxPerKind = 2 }
        #expect(h.rels(r, .largeUnused).count == 2)
        // The two largest stay on the card.
        #expect(h.rels(r, .largeUnused) == ["big3.bin", "big4.bin"])
        #expect(r.totalBytes > r.suggestions.reduce(0) { $0 + $1.bytes })
    }

    @Test func nothingIsSentAfterACancel() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file(".Trash/old.bin")
        for i in 0..<5 { try h.file("d\(i)/big.bin", fill: UInt8(i)) }
        h.ageFolders(days: 30)
        let cancelled = LockedCounter()
        let after = LockedCounter()
        let r = h.scanner().run(isCancelled: { cancelled.value > 0 }, onProgress: { _ in
            if cancelled.value > 0 { after.increment() }
        }, onCards: { _ in
            cancelled.increment()
        })
        #expect(after.value == 0)
        #expect(r.suggestions.isEmpty)
        #expect(r.isPartial)
    }

    @Test func theRunnerSendsCardsThenTheReport() async throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file(".Trash/old.bin")
        h.ageFolders(days: 30)
        let log = LockedLog()
        let scan = SuggestionScan(h.scanner()) { u in
            if u.report != nil { log.add("report") } else if u.cards != nil { log.add("cards") } else { log.add("progress") }
        }
        scan.start()
        #expect(await waitUntil { log.values.last == "report" })
        let values = log.values
        #expect(values.filter { $0 == "report" }.count == 1)
        #expect(values.firstIndex(of: "cards")! < values.firstIndex(of: "report")!)
    }

    @Test func aCancelledRunnerSendsNothingMore() async throws {
        let h = try ScanHome()
        defer { h.close() }
        for i in 0..<5 { try h.file("d\(i)/big.bin", fill: UInt8(i)) }
        h.ageFolders(days: 30)
        let count = LockedCounter()
        let scan = SuggestionScan(h.scanner()) { _ in count.increment() }
        scan.cancel()
        scan.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(scan.isCancelled)
        #expect(count.value == 0)
    }

    @Test func measureTrashSizesTheTrashAlone() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file(".Trash/a.bin")
        try h.file(".Trash/b.bin", fill: 0x42)
        let s = SuggestionScanner.measureTrash(config: h.config(), fs: LiveScanFileSystem())
        #expect(s?.kind == .trash)
        #expect((s?.bytes ?? 0) >= 400_000)
        #expect(SuggestionScanner.measureTrash(config: SuggestionConfig(home: try h.t.folder("Empty"), now: h.now), fs: LiveScanFileSystem()) == nil)
    }

    @Test func hashedFilesAreReportedForTheCenter() throws {
        let h = try ScanHome()
        defer { h.close() }
        try h.file("a/one.bin", fill: 0x55)
        try h.file("b/two.bin", fill: 0x55)
        h.ageFolders(days: 30)
        let r = h.collect()
        #expect(r.hashedFiles.count == 2)
    }

    @Test func eachFileAppearsInOneSuggestionOnly() throws {
        let h = try ScanHome()
        defer { h.close() }
        // An old installer that also has a copy: the duplicate wins, the installer does not repeat.
        try h.file("Downloads/app.dmg", fill: 0x10, days: 30)
        try h.file("Documents/app copy.dmg", fill: 0x10, days: 30)
        // An old, large file in Downloads: old downloads wins over large unused.
        try h.file("Downloads/movie.bin", fill: 0x20, days: 300)
        // Large unused alone.
        try h.file("Documents/film.bin", fill: 0x30, days: 300)
        // Two plain copies.
        try h.file("Documents/x1.bin", fill: 0x40, days: 300)
        try h.file("Pictures2/x2.bin", fill: 0x40, days: 300)
        h.ageFolders(days: 300)
        let r = h.collect()
        let ids = r.suggestions.flatMap(\.items).map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(h.rels(r, .duplicates).contains("Downloads/app.dmg"))
        #expect(h.rels(r, .installers).isEmpty)
        #expect(h.rels(r, .oldDownloads) == ["Downloads/movie.bin"])
        #expect(h.rels(r, .largeUnused) == ["Documents/film.bin"])
        #expect(Set(h.rels(r, .duplicates)) == ["Downloads/app.dmg", "Documents/app copy.dmg", "Documents/x1.bin", "Pictures2/x2.bin"])
        #expect(r.suggestions.filter { $0.kind == .duplicates }.count == 2)
    }

    @Test func nothingInsideAClaimedFolderIsSuggestedAgain() throws {
        let h = try ScanHome()
        defer { h.close() }
        // An old Downloads folder is one item. Its files are not offered again, and not as duplicates.
        try h.file("Downloads/Old Stuff/big.bin", fill: 0x61, days: 300)
        try h.file("Downloads/Old Stuff/setup.dmg", fill: 0x62, days: 300)
        try h.file("Documents/copy-of-big.bin", fill: 0x61, days: 300)
        // An idle build folder is one item.
        try h.file("proj/package.json", kb: 1, days: 90)
        try h.file("proj/node_modules/pkg/lib.bin", fill: 0x63, days: 300)
        try h.file("Documents/copy-of-lib.bin", fill: 0x63, days: 300)
        // The Trash and a cache are one item each.
        try h.file(".Trash/t1.bin", fill: 0x64)
        try h.file("Library/Caches/org.x/blob.bin", fill: 0x65)
        h.ageFolders(days: 120)
        let r = h.collect()
        #expect(h.rels(r, .oldDownloads) == ["Downloads/Old Stuff"])
        #expect(h.rels(r, .buildFolders) == ["proj/node_modules"])
        #expect(h.rels(r, .trash).count == 1)
        #expect(h.rels(r, .appCaches) == ["Library/Caches/org.x"])
        #expect(h.rels(r, .duplicates).isEmpty)
        let paths = r.suggestions.flatMap(\.items).map(\.url.path)
        for p in paths {
            let inside = paths.contains { $0 != p && p.hasPrefix($0 + "/") }
            #expect(!inside, "\(p) lies inside another suggestion")
        }
    }
}
