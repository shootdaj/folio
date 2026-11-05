import Foundation
import Testing
@testable import FolioCore

/// Finder tags and colour labels, read and written in the attribute Finder and Spotlight use, so both
/// apps agree on them.
@Suite(.serialized) struct FileTagsTests {
    @Test func aColourTagIsWrittenTheWayFinderStoresIt() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/a.txt")
        try FileTags.write([FileTag(name: "Red", color: .red), FileTag(name: "Work", color: .none)], to: f)
        #expect(FileTags.read(f) == [FileTag(name: "Red", color: .red), FileTag(name: "Work", color: .none)])
        // The system's own reading of the same attribute: the names Spotlight and Finder show.
        #expect((try f.resourceValues(forKeys: [.tagNamesKey])).tagNames == ["Red", "Work"])
        #expect(FileTags.rawValues(f) == ["Red\n6", "Work\n0"])
    }

    @Test func namesWrittenWithoutAColourTakeTheStandardOne() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/b.txt")
        try (f as NSURL).setResourceValue(["Blue", "Project"], forKey: .tagNamesKey)
        let tags = FileTags.read(f)
        #expect(tags.map(\.name) == ["Blue", "Project"])
        #expect(tags.first?.color == .blue)
        #expect(tags.last?.color == TagColor.none)
    }

    @Test func noTagsReadsEmptyAndWritingNoneRemovesTheAttribute() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/c.txt")
        #expect(FileTags.read(f).isEmpty)
        try FileTags.write([FileTag(name: "Green", color: .green)], to: f)
        try FileTags.write([], to: f)
        #expect(FileTags.read(f).isEmpty)
        #expect(FileTags.rawValues(f).isEmpty)
    }

    @Test func togglingATagAddsItToAllThenTakesItOffAll() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt"), b = try t.file("work/b.txt")
        try FileTags.write([FileTag(name: "Red", color: .red)], to: a)
        let red = FileTag(name: "Red", color: .red)
        #expect(FileTags.state(of: red, on: [a, b]) == .mixed)
        try FileTags.toggle(red, on: [a, b])
        #expect(FileTags.read(b) == [red] && FileTags.read(a) == [red], "mixed becomes on for all")
        try FileTags.toggle(red, on: [a, b])
        #expect(FileTags.read(a).isEmpty && FileTags.read(b).isEmpty)
    }

    @Test func theSevenFinderColoursInMenuOrder() {
        #expect(TagColor.menuOrder.map(\.name) == ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"])
        #expect(TagColor.menuOrder.map(\.rawValue) == [6, 7, 5, 2, 4, 3, 1])
        #expect(FileTags.parse("Orange\n7") == FileTag(name: "Orange", color: .orange))
        #expect(FileTags.parse("Purple") == FileTag(name: "Purple", color: .purple))
        #expect(FileTags.parse("Mine\n9").color == TagColor.none)
    }

    @Test func tagsEditedAsNamesKeepTheColoursTheyHad() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/d.txt")
        try FileTags.write([FileTag(name: "Urgent", color: .orange)], to: f)
        try FileTags.setNames(["Urgent", "Later"], of: f)
        #expect(FileTags.read(f) == [FileTag(name: "Urgent", color: .orange), FileTag(name: "Later", color: .none)])
    }
}
