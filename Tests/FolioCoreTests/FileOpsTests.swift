import Foundation
import Testing
@testable import FolioCore

/// Rename, Trash, delete, new items, and undo and redo of every operation, on temp trees.
@Suite(.serialized) struct FileOpsTests {
    @Test func renameAndItsUndoAndRedo() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/draft.txt", bytes: 5)
        let renamed = try FileOps.rename(a, to: "final.txt")
        #expect(t.names("work") == ["final.txt"])
        let record = OperationRecord.rename([Pair(from: a, to: renamed)])

        let back = try FileOps.undo(record, trash: t.trash)
        #expect(t.names("work") == ["draft.txt"])
        #expect(back == [a])
        _ = try FileOps.redo(record, trash: t.trash)
        #expect(t.names("work") == ["final.txt"])
    }

    @Test func renameNeverReplacesAnotherItem() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt", fill: 0x01)
        try t.file("work/b.txt", fill: 0x02)
        #expect(throws: FileOpError.exists("b.txt")) { try FileOps.rename(a, to: "b.txt") }
        #expect(t.data("work/b.txt")?.first == 0x02)
        #expect(throws: FileOpError.invalidName(.forbiddenCharacter("/"))) { try FileOps.rename(a, to: "x/y") }
    }

    @Test func aCaseOnlyRenameWorks() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/notes.txt")
        try FileOps.rename(a, to: "Notes.txt")
        #expect(t.names("work") == ["Notes.txt"])
    }

    @Test func batchRenameNumbersTheItemsInViewOrderAndUndoPutsEveryNameBack() throws {
        let t = try TestTree()
        defer { t.close() }
        let items = [try t.file("work/IMG_9.jpg"), try t.file("work/IMG_1.jpg"), try t.file("work/clip.mov"),
                     try t.folder("work/Extras")]
        let pairs = try FileOps.batchRename(items, base: "Trip")
        #expect(pairs.map(\.to.lastPathComponent) == ["Trip (1).jpg", "Trip (2).jpg", "Trip (3).mov", "Trip (4)"])
        #expect(t.names("work") == ["Trip (1).jpg", "Trip (2).jpg", "Trip (3).mov", "Trip (4)"])
        try FileOps.undo(.rename(pairs), trash: t.trash)
        #expect(t.names("work") == ["Extras", "IMG_1.jpg", "IMG_9.jpg", "clip.mov"])
    }

    @Test func trashUndoPutsItemsBackAndRedoTrashesThemAgain() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt", bytes: 7)
        let docs = try t.folder("work/Docs")
        try t.file("work/Docs/inner.txt")
        let trashed = try FileOps.trash([a, docs], using: t.trash)
        #expect(t.names("work").isEmpty)
        #expect(trashed.allSatisfy { FileManager.default.fileExists(atPath: $0.inTrash.path) })

        let back = try FileOps.undo(.trash(trashed), trash: t.trash)
        #expect(t.names("work") == ["Docs", "a.txt"])
        #expect(t.names("work/Docs") == ["inner.txt"])
        #expect(Set(back) == [a, docs])

        let redo = try FileOps.redo(.trash(trashed), trash: t.trash)
        #expect(t.names("work").isEmpty)
        guard case .trash(let again) = redo.record else { Issue.record("no trash record"); return }
        #expect(again.map(\.original) == [a, docs])
        #expect(again.map(\.inTrash) != trashed.map(\.inTrash), "a redo records the new Trash places")
    }

    @Test func undoingATrashRecreatesAMissingParentFolder() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/deep/a.txt")
        let trashed = try FileOps.trash([a], using: t.trash)
        try FileManager.default.trashItem(at: t.url("work/deep"), resultingItemURL: nil)
        try FileOps.undo(.trash(trashed), trash: t.trash)
        #expect(t.exists("work/deep/a.txt"))
    }

    @Test func undoingATrashNeverOverwritesANewItemWithTheSameName() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt", fill: 0x01)
        let trashed = try FileOps.trash([a], using: t.trash)
        try t.file("work/a.txt", fill: 0x02)
        #expect(throws: FileOpError.exists("a.txt")) { try FileOps.undo(.trash(trashed), trash: t.trash) }
        #expect(t.data("work/a.txt")?.first == 0x02)
    }

    @Test func permanentDeleteRemovesTheItems() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let docs = try t.folder("work/Docs")
        try t.file("work/Docs/x.txt")
        try FileOps.deletePermanently([a, docs])
        #expect(t.names("work").isEmpty)
    }

    @Test func newFolderAndNewTextDocumentWithUndoAndRedo() throws {
        let t = try TestTree()
        defer { t.close() }
        let work = try t.folder("work")
        let f1 = try FileOps.newFolder(in: work)
        let f2 = try FileOps.newFolder(in: work)
        #expect([f1, f2].map(\.lastPathComponent) == ["New folder", "New folder (2)"])
        let doc = try FileOps.newTextDocument(in: work)
        #expect(doc.lastPathComponent == "New Text Document.txt")
        #expect(t.data("work/New Text Document.txt")?.isEmpty == true)

        try FileOps.undo(.newFolder(f2), trash: t.trash)
        try FileOps.undo(.newFile(doc), trash: t.trash)
        #expect(t.names("work") == ["New folder"])
        _ = try FileOps.redo(.newFolder(f2), trash: t.trash)
        _ = try FileOps.redo(.newFile(doc), trash: t.trash)
        #expect(t.names("work") == ["New Text Document.txt", "New folder", "New folder (2)"])
    }

    @Test func undoAMoveBringsEverythingBackIncludingMergedFoldersAndRedoMovesItAgain() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.txt")
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/new.jpg")
        try t.file("dest/Photos/old.jpg")
        let r = await FileJob(kind: .move, sources: [a, photos], into: t.url("dest"), options: t.options()).run()
        let record = try #require(r.record)

        let back = try FileOps.undo(record, trash: t.trash)
        #expect(t.names("src") == ["Photos", "a.txt"])
        #expect(t.names("src/Photos") == ["new.jpg"])
        #expect(t.names("dest/Photos") == ["old.jpg"])
        #expect(Set(back.map(\.lastPathComponent)) == ["a.txt", "new.jpg"])

        let redo = try FileOps.redo(record, trash: t.trash)
        #expect(t.names("src").isEmpty)
        #expect(t.names("dest/Photos") == ["new.jpg", "old.jpg"])
        #expect(redo.record == record)
    }

    @Test func undoACrossVolumeMoveRemovesTheFoldersItMade() async throws {
        let t = try TestTree()
        defer { t.close() }
        let docs = try t.folder("src/Docs")
        try t.file("src/Docs/sub/two.txt")
        let r = await FileJob(kind: .move, sources: [docs], into: t.url("dest"),
                              options: t.options { $0.allowRename = false }).run()
        try FileOps.undo(try #require(r.record), trash: t.trash)
        #expect(t.exists("src/Docs/sub/two.txt"))
        #expect(t.names("dest").isEmpty)
    }

    @Test func undoACopyRemovesTheCopiesAndBringsBackWhatReplaceTrashed() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.txt", bytes: 50)
        let b = try t.file("src/b.txt", bytes: 5)
        try t.file("dest/a.txt", bytes: 10)
        let r = await FileJob(kind: .copy, sources: [a, b], into: t.url("dest"),
                              options: t.options { $0.conflictPolicy = .replace }).run()
        let record = try #require(r.record)
        #expect(t.data("dest/a.txt")?.count == 50)

        try FileOps.undo(record, trash: t.trash)
        #expect(t.names("dest") == ["a.txt"])
        #expect(t.data("dest/a.txt")?.count == 10, "the replaced file is back")

        let redo = try FileOps.redo(record, trash: t.trash)
        #expect(t.names("dest") == ["a.txt", "b.txt"])
        #expect(t.data("dest/a.txt")?.count == 50)
        guard case .copy(_, let replaced) = redo.record else { Issue.record("no copy record"); return }
        #expect(replaced.count == 1)
    }

    @Test func undoHistoryNamesTheStepsAndANewStepClearsRedo() {
        var h = UndoHistory()
        #expect(h.undoTitle == nil)
        let u = URL(fileURLWithPath: "/private/tmp/folio-tests/x")
        h.record(.rename([Pair(from: u, to: u)]))
        h.record(.newFolder(u))
        #expect(h.undoTitle == "Undo New Folder")
        let step = h.takeUndo()!
        h.didUndo(step)
        #expect(h.undoTitle == "Undo Rename")
        #expect(h.redoTitle == "Redo New Folder")
        h.record(.trash([]))
        #expect(h.redoTitle == nil)
        #expect(h.undoTitle == "Undo Delete")
    }

    /// The real macOS Trash, only on the scratch volume (docs/plan/RULES.md, rule 1).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Volumes/FolioScratch")))
    func theSystemTrashRoundTripsOnTheScratchVolume() throws {
        let root = URL(fileURLWithPath: "/Volumes/FolioScratch/unit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: root, resultingItemURL: nil) }
        let a = root.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: a)
        let trashed = try FileOps.trash([a], using: SystemTrash())
        #expect(!FileManager.default.fileExists(atPath: a.path))
        try FileOps.undo(.trash(trashed), trash: SystemTrash())
        #expect(FileManager.default.fileExists(atPath: a.path))
    }
}

@Suite struct ProgressTextTests {
    @Test func speedIsTheBytesOverTheLastSecond() {
        var m = SpeedMeter()
        m.record(bytes: 0, at: 10.0)
        m.record(bytes: 50, at: 10.5)
        m.record(bytes: 100, at: 11.0)
        m.record(bytes: 150, at: 11.5)
        #expect(m.bytesPerSecond(at: 11.5) == 100)
        #expect(m.bytesPerSecond(at: 12.5) == 0, "a second with no bytes reads as stopped")
    }

    @Test func aRestartForgetsThePause() {
        var m = SpeedMeter()
        m.record(bytes: 0, at: 0)
        m.record(bytes: 1000, at: 1)
        m.restart(bytes: 1000, at: 60)
        #expect(m.bytesPerSecond(at: 60.05) == 0, "too little history yet")
        m.record(bytes: 1500, at: 60.5)
        #expect(m.bytesPerSecond(at: 60.5) == 1000)
    }

    @Test func readoutsReadLikeD1() {
        #expect(ProgressText.speed(412_000_000) == "412 MB/s")
        #expect(ProgressText.speed(4_200_000) == "4.2 MB/s")
        #expect(ProgressText.speed(850_000) == "850 KB/s")
        #expect(ProgressText.timeLeft(5.2) == "6 s")
        #expect(ProgressText.timeLeft(65) == "1 min 5 s")
        #expect(ProgressText.timeLeft(7380) == "2 h 3 min")
        #expect(ProgressText.bytesOf(2_210_000_000, 4_830_000_000) == "2.21 GB of 4.83 GB")
        #expect(ProgressText.bytesOf(120_000_000, 200_000_000) == "120.0 MB of 200.0 MB")
    }
}
