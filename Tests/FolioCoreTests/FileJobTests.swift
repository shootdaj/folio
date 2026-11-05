import Foundation
import Testing
@testable import FolioCore

/// Copy and move jobs on temp trees: merging, deferred conflicts and each decision, pause, cancel.
@Suite(.serialized) struct FileJobTests {
    @Test func copyCopiesFilesAndFoldersWithTheirContentsAndDates() async throws {
        let t = try TestTree()
        defer { t.close() }
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try t.file("src/a.txt", bytes: 100, modified: old)
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/one.jpg", bytes: 2000)
        try t.file("src/Photos/.hidden", bytes: 3)
        let dest = try t.folder("dest")

        let r = await FileJob(kind: .copy, sources: [a, photos], into: dest, options: t.options()).run()

        #expect(r.state == .done)
        #expect(t.names("dest") == ["Photos", "a.txt"])
        #expect(t.names("dest/Photos") == [".hidden", "one.jpg"])
        #expect(t.data("dest/Photos/one.jpg")?.count == 2000)
        #expect(ItemFacts.read(t.url("dest/a.txt")).modified == old, "the copy keeps the date")
        #expect(t.names("src") == ["Photos", "a.txt"], "the sources stay")
        #expect(r.placed.map(\.lastPathComponent) == ["a.txt", "Photos"])
        guard case .copy(let copied, let replaced) = r.record else { Issue.record("no copy record"); return }
        #expect(copied.map { [$0.from.path, $0.to.path] } == [[a.path, t.url("dest/a.txt").path],
                                                              [photos.path, t.url("dest/Photos").path]])
        #expect(replaced.isEmpty)
    }

    @Test func throttledCopiesAreRealByteCopiesWithTheSameContent() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/big.bin", bytes: 300_000, fill: 0x5A)
        let dest = try t.folder("dest")
        let r = await FileJob(kind: .copy, sources: [a], into: dest, options: t.options { $0.throttle = 3_000_000 }).run()
        #expect(r.state == .done)
        #expect(t.data("dest/big.bin") == t.data("src/big.bin"))
    }

    @Test func pastingIntoTheSameFolderMakesNameDashCopyThenNumbers() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/report.txt")
        let work = t.url("work")
        _ = await FileJob(kind: .copy, sources: [a], into: work, options: t.options()).run()
        let r = await FileJob(kind: .copy, sources: [a], into: work, options: t.options()).run()
        #expect(t.names("work") == ["report - Copy (2).txt", "report - Copy.txt", "report.txt"])
        #expect(r.placed.map(\.lastPathComponent) == ["report - Copy (2).txt"])
    }

    @Test func copyMergesSameNamedFoldersInsteadOfReplacingThem() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/Photos/old.jpg", fill: 0x01)
        try t.file("dest/Photos/Trip/day1.jpg", fill: 0x02)
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/new.jpg")
        try t.file("src/Photos/Trip/day2.jpg")

        let r = await FileJob(kind: .copy, sources: [photos], into: t.url("dest"), options: t.options()).run()

        #expect(r.state == .done)
        #expect(t.names("dest/Photos") == ["Trip", "new.jpg", "old.jpg"], "Finder would have wiped old.jpg")
        #expect(t.names("dest/Photos/Trip") == ["day1.jpg", "day2.jpg"])
        #expect(r.placed.map(\.path) == [t.url("dest/Photos").path])
    }

    @Test func conflictsWaitUntilEverythingElseIsCopied() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try ["a.txt", "b.txt", "c.txt"].map { try t.file("src/\($0)", bytes: 50, fill: 0x42) }
        try t.file("dest/b.txt", bytes: 10, fill: 0x01)
        let job = FileJob(kind: .copy, sources: files, into: t.url("dest"), options: t.options())
        job.start()

        #expect(await waitUntil { job.snapshot().state == .waitingOnConflict })
        let s = job.snapshot()
        #expect(s.conflict?.incoming.name == "b.txt")
        #expect(s.conflict?.existing.size == 10 && s.conflict?.incoming.size == 50)
        #expect(s.conflictsLeft == 1)
        #expect(t.exists("dest/a.txt") && t.exists("dest/c.txt"), "a and c were copied before the question")

        job.resolve(.skip)
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(r.skipped == 1)
        #expect(t.data("dest/b.txt")?.count == 10, "Skip leaves the file that was there")
    }

    @Test func replaceTakesTheIncomingFileAndSendsTheOldOneToTheTrash() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.txt", bytes: 50)
        try t.file("dest/a.txt", bytes: 10)
        let r = await FileJob(kind: .copy, sources: [a], into: t.url("dest"),
                              options: t.options { $0.conflictPolicy = .replace }).run()
        #expect(t.data("dest/a.txt")?.count == 50)
        guard case .copy(_, let replaced) = r.record else { Issue.record("no copy record"); return }
        #expect(replaced.count == 1)
        #expect(FileManager.default.fileExists(atPath: replaced[0].inTrash.path), "the replaced file is in the Trash")
    }

    @Test func keepBothCopiesTheIncomingFileAsNameOne() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a-video.mov", bytes: 50)
        try t.file("dest/a-video.mov", bytes: 10)
        let job = FileJob(kind: .copy, sources: [a], into: t.url("dest"), options: t.options())
        job.start()
        #expect(await waitUntil { job.snapshot().state == .waitingOnConflict })
        job.resolve(.keepBoth)
        let r = await job.finished()
        #expect(t.names("dest") == ["a-video (1).mov", "a-video.mov"])
        #expect(t.data("dest/a-video (1).mov")?.count == 50)
        #expect(t.data("dest/a-video.mov")?.count == 10)
        #expect(r.placed.map(\.path) == [t.url("dest/a-video (1).mov").path])
    }

    @Test func doThisForAllAnswersEveryRemainingConflict() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try ["a", "b", "c"].map { try t.file("src/\($0).txt") }
        for n in ["a", "b", "c"] { try t.file("dest/\(n).txt", bytes: 3) }
        let job = FileJob(kind: .copy, sources: files, into: t.url("dest"), options: t.options())
        job.start()
        #expect(await waitUntil { job.snapshot().state == .waitingOnConflict })
        #expect(job.snapshot().conflictsLeft == 3)
        job.resolve(.keepBoth, applyToAll: true)
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(t.names("dest") == ["a (1).txt", "a.txt", "b (1).txt", "b.txt", "c (1).txt", "c.txt"])
    }

    @Test func eachConflictCanGetItsOwnDecision() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try ["a", "b", "c"].map { try t.file("src/\($0).txt", bytes: 20) }
        for n in ["a", "b", "c"] { try t.file("dest/\(n).txt", bytes: 3) }
        let job = FileJob(kind: .copy, sources: files, into: t.url("dest"), options: t.options())
        job.start()
        for (expected, decision) in [("a.txt", ConflictDecision.replace), ("b.txt", .skip), ("c.txt", .keepBoth)] {
            #expect(await waitUntil { job.snapshot().conflict?.incoming.name == expected })
            job.resolve(decision)
        }
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(t.data("dest/a.txt")?.count == 20)
        #expect(t.data("dest/b.txt")?.count == 3)
        #expect(t.names("dest") == ["a.txt", "b.txt", "c (1).txt", "c.txt"])
    }

    @Test func skipIdenticalSkipsFilesWithTheSameSizeAndDate() async throws {
        let t = try TestTree()
        defer { t.close() }
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let same = try t.file("src/same.txt", bytes: 9, modified: when)
        let differs = try t.file("src/differs.txt", bytes: 9, modified: when)
        try t.file("dest/same.txt", bytes: 9, modified: when)
        try t.file("dest/differs.txt", bytes: 9, modified: when.addingTimeInterval(-3600))
        let job = FileJob(kind: .copy, sources: [same, differs], into: t.url("dest"),
                          options: t.options { $0.skipIdentical = true })
        job.start()
        #expect(await waitUntil { job.snapshot().state == .waitingOnConflict })
        #expect(job.snapshot().conflict?.incoming.name == "differs.txt", "same.txt never asked")
        #expect(job.snapshot().conflict?.incomingIsNewer == true)
        job.resolve(.skip)
        let r = await job.finished()
        #expect(r.skipped == 2)
    }

    @Test func aFileAgainstAFolderOfTheSameNameIsAConflictNotAMerge() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/thing")
        try t.folder("dest/thing")
        try t.file("dest/thing/inside.txt")
        let r = await FileJob(kind: .copy, sources: [a], into: t.url("dest"),
                              options: t.options { $0.conflictPolicy = .keepBoth }).run()
        #expect(t.names("dest") == ["thing", "thing (1)"])
        #expect(t.names("dest/thing") == ["inside.txt"])
        #expect(r.state == .done)
    }

    @Test func copyingAFolderIntoItselfIsRefusedAndSkipped() async throws {
        let t = try TestTree()
        defer { t.close() }
        let src = try t.folder("src")
        try t.file("src/a.txt")
        let inner = try t.folder("src/inner")
        let r = await FileJob(kind: .copy, sources: [src], into: inner, options: t.options()).run()
        #expect(r.state == .done)
        #expect(r.skipped == 1)
        #expect(t.names("src/inner").isEmpty)
    }

    @Test func moveRenamesOnTheSameVolumeAndMergesFolders() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.txt")
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/new.jpg")
        try t.file("dest/Photos/old.jpg")

        let r = await FileJob(kind: .move, sources: [a, photos], into: t.url("dest"), options: t.options()).run()

        #expect(r.state == .done)
        #expect(t.names("src").isEmpty, "the merged Photos folder left the source once empty")
        #expect(t.names("dest") == ["Photos", "a.txt"])
        #expect(t.names("dest/Photos") == ["new.jpg", "old.jpg"])
        guard case .move(let moved, _, let removed, _) = r.record else { Issue.record("no move record"); return }
        #expect(moved == [Pair(from: a, to: t.url("dest/a.txt")),
                          Pair(from: t.url("src/Photos/new.jpg"), to: t.url("dest/Photos/new.jpg"))])
        #expect(removed == [photos])
    }

    @Test func moveIntoTheFolderItIsInChangesNothing() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let r = await FileJob(kind: .move, sources: [a], into: t.url("work"), options: t.options()).run()
        #expect(r.state == .done)
        #expect(r.record == nil)
        #expect(t.names("work") == ["a.txt"])
    }

    @Test func aMoveAcrossVolumesCopiesThenDeletesEachFile() async throws {
        let t = try TestTree()
        defer { t.close() }
        let docs = try t.folder("src/Docs")
        try t.file("src/Docs/one.txt", bytes: 40)
        try t.file("src/Docs/sub/two.txt", bytes: 60)
        let r = await FileJob(kind: .move, sources: [docs], into: t.url("dest"),
                              options: t.options { $0.allowRename = false }).run()
        #expect(r.state == .done)
        #expect(!t.exists("src/Docs"))
        #expect(t.data("dest/Docs/sub/two.txt")?.count == 60)
        guard case .move(let moved, let created, let removed, _) = r.record else { Issue.record("no move record"); return }
        #expect(moved.count == 2)
        #expect(created.map(\.lastPathComponent) == ["Docs", "sub"])
        #expect(Set(removed.map(\.lastPathComponent)) == ["Docs", "sub"])
    }

    @Test func cancellingACopyMidwayLeavesOnlyWholeFiles() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try (1...4).map { try t.file("src/f\($0).bin", bytes: 200_000, fill: UInt8($0)) }
        let job = FileJob(kind: .copy, sources: files, into: t.url("dest"),
                          options: t.options { $0.throttle = 1_000_000 })
        job.start()
        #expect(await waitUntil { job.snapshot().itemsDone >= 1 && job.snapshot().bytesDone > 220_000 })
        job.cancel()
        let r = await job.finished()

        #expect(r.state == .cancelled)
        let copied = t.names("dest")
        #expect(!copied.isEmpty && copied.count < 4, "stopped part way: \(copied)")
        for name in copied {
            #expect(t.data("dest/\(name)") == t.data("src/\(name)"), "\(name) is whole, never a partial file")
        }
        #expect(t.names("src").count == 4, "a copy never touches its sources")
        guard case .copy(let pairs, _) = r.record else { Issue.record("no record"); return }
        #expect(pairs.count == copied.count, "undo knows exactly what the cancelled copy left")
    }

    @Test func cancellingAMoveMidwayLeavesEveryFileInExactlyOnePlace() async throws {
        let t = try TestTree()
        defer { t.close() }
        let docs = try t.folder("src/Docs")
        for i in 1...4 { try t.file("src/Docs/f\(i).bin", bytes: 150_000, fill: UInt8(i)) }
        let job = FileJob(kind: .move, sources: [docs], into: t.url("dest"),
                          options: t.options { $0.allowRename = false; $0.throttle = 1_000_000 })
        job.start()
        #expect(await waitUntil { job.snapshot().bytesDone > 200_000 })
        job.cancel()
        let r = await job.finished()

        #expect(r.state == .cancelled)
        let there = Set(t.names("dest/Docs")), here = Set(t.names("src/Docs"))
        #expect(there.isDisjoint(with: here))
        #expect(there.union(here) == ["f1.bin", "f2.bin", "f3.bin", "f4.bin"])
        for name in there { #expect(t.data("dest/Docs/\(name)")?.count == 150_000) }
    }

    @Test func pauseStopsTheBytesAndResumeFinishesTheCopy() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.bin", bytes: 600_000)
        let job = FileJob(kind: .copy, sources: [a], into: t.url("dest"),
                          options: t.options { $0.throttle = 1_500_000 })
        job.start()
        #expect(await waitUntil { job.snapshot().bytesDone > 100_000 })
        job.pause()
        #expect(await waitUntil { job.snapshot().state == .paused })
        try await Task.sleep(for: .milliseconds(150))
        let held = job.snapshot().bytesDone
        try await Task.sleep(for: .milliseconds(300))
        let paused = job.snapshot()
        #expect(paused.bytesDone == held, "no bytes move while paused")
        #expect(paused.speed == 0)
        #expect(paused.bytesDone < 600_000)

        job.resume()
        #expect(await waitUntil { job.snapshot().state == .running || job.snapshot().state == .done })
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(t.data("dest/a.bin")?.count == 600_000)
    }

    @Test func progressReportsBytesItemsSpeedAndTimeLeft() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try (1...3).map { try t.file("src/f\($0).bin", bytes: 400_000) }
        let job = FileJob(kind: .copy, sources: files, into: t.url("dest"),
                          options: t.options { $0.throttle = 1_000_000 })
        job.start()
        #expect(await waitUntil { job.snapshot().bytesDone > 300_000 })
        try await Task.sleep(for: .milliseconds(400))
        let s = job.snapshot()
        #expect(s.bytesTotal == 1_200_000)
        #expect(s.itemsTotal == 3)
        #expect(s.speed > 600_000 && s.speed < 1_500_000, "about the 1 MB/s throttle: \(s.speed)")
        #expect((s.secondsLeft ?? 0) > 0.1)
        #expect(s.currentName?.hasPrefix("f") == true)
        let r = await job.finished()
        let end = job.snapshot()
        #expect(r.state == .done)
        #expect(end.bytesDone == end.bytesTotal && end.itemsDone == end.itemsTotal)
        #expect(end.fraction == 1)
    }

    @Test func symbolicLinksAreCopiedAsLinks() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("src/target.txt")
        let link = t.url("src/link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target.txt")
        _ = await FileJob(kind: .copy, sources: [link], into: t.url("dest"), options: t.options()).run()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: t.url("dest/link").path) == "target.txt")
    }
}
