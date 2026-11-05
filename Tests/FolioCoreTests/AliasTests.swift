import Foundation
import Testing
@testable import FolioCore

/// Create alias (a Finder alias, the default) and Create symbolic link, their names, resolving them,
/// and undo and redo of the step.
@Suite(.serialized) struct AliasTests {
    @Test func anAliasIsNamedTheFinderWayAndNumberedWhenTaken() throws {
        let t = try TestTree()
        defer { t.close() }
        let notes = try t.file("work/notes.txt")
        let work = notes.deletingLastPathComponent()
        let first = try Aliases.make(.alias, to: notes, in: work)
        let second = try Aliases.make(.alias, to: notes, in: work)
        #expect(first.lastPathComponent == "notes.txt alias")
        #expect(second.lastPathComponent == "notes.txt alias 2")
        let link = try Aliases.make(.symlink, to: notes, in: work)
        #expect(link.lastPathComponent == "notes.txt symlink")
        #expect(Aliases.name(for: "Docs", kind: .alias, taken: { _ in false }) == "Docs alias")
    }

    @Test func aFinderAliasFollowsItsTargetAfterARename() throws {
        let t = try TestTree()
        defer { t.close() }
        let report = try t.file("work/report.txt", bytes: 3)
        let alias = try Aliases.make(.alias, to: report, in: try t.folder("elsewhere"))
        #expect(Aliases.kind(of: alias) == .alias)
        #expect(Aliases.resolve(alias).map(FilePaths.itemKey) == FilePaths.itemKey(report))
        // Renaming the target does not break a Finder alias (it is a bookmark, not a path).
        let renamed = try FileOps.rename(report, to: "final.txt")
        #expect(Aliases.resolve(alias).map(FilePaths.itemKey) == FilePaths.itemKey(renamed))
    }

    @Test func aSymlinkPointsAtThePathAndAPlainFileIsNoLink() throws {
        let t = try TestTree()
        defer { t.close() }
        let docs = try t.folder("work/Docs")
        let link = try Aliases.make(.symlink, to: docs, in: try t.folder("elsewhere"))
        #expect(Aliases.kind(of: link) == .symlink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == docs.path)
        #expect(Aliases.resolve(link).map(FilePaths.folderKey) == FilePaths.folderKey(docs))
        let plain = try t.file("work/plain.txt")
        #expect(Aliases.kind(of: plain) == nil)
        #expect(Aliases.kind(of: docs) == nil)
        #expect(Aliases.resolve(plain) == nil)
    }

    @Test func aLinkToAMissingTargetResolvesToNothing() throws {
        let t = try TestTree()
        defer { t.close() }
        let gone = try t.file("work/gone.txt")
        let link = try Aliases.make(.symlink, to: gone, in: gone.deletingLastPathComponent())
        try FileOps.deletePermanently([gone])
        #expect(Aliases.resolve(link) == nil)
    }

    @Test func undoTrashesTheNewLinksAndRedoMakesThemAgain() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt"), b = try t.folder("work/B")
        let dest = t.url("dest")
        let items = try [a, b].map { try Aliases.makeItem(.alias, to: $0, in: dest) }
        #expect(t.names("dest") == ["B alias", "a.txt alias"])
        let record = OperationRecord.links(items)
        #expect(record.title == "Create Alias")
        try FileOps.undo(record, trash: t.trash)
        #expect(t.names("dest").isEmpty)
        let redone = try FileOps.redo(record, trash: t.trash)
        #expect(t.names("dest") == ["B alias", "a.txt alias"])
        #expect(redone.items.map(\.lastPathComponent).sorted() == ["B alias", "a.txt alias"])
        #expect(Aliases.resolve(t.url("dest/B alias")).map(FilePaths.folderKey) == FilePaths.folderKey(b))
        #expect(OperationRecord.links([LinkItem(url: dest, target: a, kind: .symlink)]).title == "Create Symbolic Link")
    }
}
