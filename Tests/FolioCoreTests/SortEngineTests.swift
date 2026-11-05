import Foundation
import Testing
@testable import FolioCore

/// Fixture: two folders and four files with known dates, sizes and kinds.
private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSince1970: 1_700_000_000)

private func entry(_ name: String, folder: Bool = false, age days: Double,
                   size: Int64? = nil, kind: String) -> FileEntry {
    FileEntry(url: URL(fileURLWithPath: "/fixture/\(name)"), name: name, isFolder: folder,
              modified: base.addingTimeInterval(-days * day), size: folder ? nil : size, kind: kind)
}

private let fixture: [FileEntry] = [
    entry("file10.txt", age: 3, size: 10, kind: "Plain Text"),
    entry("Zeta", folder: true, age: 0, kind: "Folder"),
    entry("file2.txt", age: 1, size: 3000, kind: "Plain Text"),
    entry("alpha", folder: true, age: 9, kind: "Folder"),
    entry("Movie.mov", age: 0.5, size: 900, kind: "QuickTime movie"),
    entry("File1.png", age: 7, size: 50, kind: "PNG image"),
]

private func names(_ entries: [FileEntry]) -> [String] { entries.map(\.name) }

@Suite struct SortEngineTests {
    @Test func defaultIsNameAscendingWithFoldersFirstAndNaturalNumbers() {
        #expect(SortSpec.standard == SortSpec(key: .name, ascending: true))
        let sorted = SortEngine.sort(fixture, by: .standard)
        #expect(names(sorted) == ["alpha", "Zeta", "File1.png", "file2.txt", "file10.txt", "Movie.mov"])
    }

    @Test func nameDescendingPutsFoldersAtTheBottom() {
        let sorted = SortEngine.sort(fixture, by: SortSpec(key: .name, ascending: false))
        #expect(names(sorted) == ["Movie.mov", "file10.txt", "file2.txt", "File1.png", "Zeta", "alpha"])
    }

    @Test func dateModifiedFirstClickIsNewestFirst() {
        let firstClick = SortSpec.standard.clicking(.modified)
        #expect(firstClick == SortSpec(key: .modified, ascending: false))
        let sorted = SortEngine.sort(fixture, by: firstClick)
        // Files newest first, then folders (descending puts folders last), newest first too.
        #expect(names(sorted) == ["Movie.mov", "file2.txt", "file10.txt", "File1.png", "Zeta", "alpha"])
    }

    @Test func dateModifiedSecondClickIsOldestFirstWithFoldersOnTop() {
        let secondClick = SortSpec.standard.clicking(.modified).clicking(.modified)
        #expect(secondClick == SortSpec(key: .modified, ascending: true))
        let sorted = SortEngine.sort(fixture, by: secondClick)
        #expect(names(sorted) == ["alpha", "Zeta", "File1.png", "file10.txt", "file2.txt", "Movie.mov"])
    }

    @Test func nameAndTypeFirstClickAscendingSecondClickReverses() {
        let fromDate = SortSpec(key: .modified, ascending: false)
        #expect(fromDate.clicking(.name) == SortSpec(key: .name, ascending: true))
        #expect(fromDate.clicking(.kind) == SortSpec(key: .kind, ascending: true))
        #expect(SortSpec.standard.clicking(.name) == SortSpec(key: .name, ascending: false))
        #expect(fromDate.clicking(.kind).clicking(.kind) == SortSpec(key: .kind, ascending: false))
    }

    @Test func typeSortsByKindThenName() {
        let sorted = SortEngine.sort(fixture, by: SortSpec(key: .kind, ascending: true))
        #expect(names(sorted) == ["alpha", "Zeta", "file2.txt", "file10.txt", "File1.png", "Movie.mov"])
    }

    @Test func sizeSortsFilesBySizeWithFoldersFirst() {
        let sorted = SortEngine.sort(fixture, by: SortSpec(key: .size, ascending: true))
        #expect(names(sorted) == ["alpha", "Zeta", "file10.txt", "File1.png", "Movie.mov", "file2.txt"])
        let reversed = SortEngine.sort(fixture, by: SortSpec(key: .size, ascending: false))
        #expect(names(reversed) == ["file2.txt", "Movie.mov", "File1.png", "file10.txt", "Zeta", "alpha"])
    }

    @Test func emptyListStaysEmpty() {
        #expect(SortEngine.sort([], by: .standard).isEmpty)
    }
}

@Suite struct MultiKeySortTests {
    @Test func shiftClickAddsKeysUpToFourAndReversesOnesAlreadyThere() {
        var s = SortSpec(key: .modified, ascending: false)
        s = s.shiftClicking(.kind)
        #expect(s.terms == [SortTerm(key: .modified, ascending: false), SortTerm(key: .kind, ascending: true)])
        s = s.shiftClicking(.name)
        #expect(s.rank(of: .modified) == 1)
        #expect(s.rank(of: .kind) == 2)
        #expect(s.rank(of: .name) == 3)
        #expect(s.rank(of: .size) == nil)
        s = s.shiftClicking(.kind)
        #expect(s.isAscending(.kind) == false)
        s = s.shiftClicking(.size).shiftClicking(.created)
        #expect(s.terms.count == SortSpec.maxKeys)
        #expect(s.terms.map(\.key) == [.modified, .kind, .name, .created])
        #expect(s.isAscending(.created) == false)
        s = s.shiftClicking(.modified)
        #expect(s.ascending)
        #expect(s.then.count == 3)
    }

    @Test func plainClickOnThePrimaryReversesItAndKeepsTheOthersAnotherColumnStartsOver() {
        let s = SortSpec(key: .modified, ascending: false).shiftClicking(.name)
        let flipped = s.clicking(.modified)
        #expect(flipped == SortSpec(key: .modified, ascending: true, then: [SortTerm(key: .name, ascending: true)]))
        #expect(s.clicking(.size) == SortSpec(key: .size, ascending: true))
    }

    @Test func secondaryKeysBreakTiesInTheirOwnDirection() {
        let sameDay = base.addingTimeInterval(-day)
        let items = [
            FileEntry(url: URL(fileURLWithPath: "/f/b.txt"), name: "b.txt", isFolder: false, modified: sameDay, size: 5, kind: "Plain Text"),
            FileEntry(url: URL(fileURLWithPath: "/f/a.png"), name: "a.png", isFolder: false, modified: sameDay, size: 7, kind: "PNG image"),
            FileEntry(url: URL(fileURLWithPath: "/f/c.txt"), name: "c.txt", isFolder: false, modified: sameDay, size: 9, kind: "Plain Text"),
            FileEntry(url: URL(fileURLWithPath: "/f/d.png"), name: "d.png", isFolder: false, modified: base, size: 1, kind: "PNG image"),
            FileEntry(url: URL(fileURLWithPath: "/f/F"), name: "F", isFolder: true, modified: base, size: nil, kind: "Folder"),
        ]
        let byDateThenType = SortSpec(key: .modified, ascending: false).shiftClicking(.kind)
        // Newest first; folders go last because the first key is descending; same day: Plain Text before
        // PNG, and the two text files break their tie on Name in the first key's direction (descending).
        #expect(names(SortEngine.sort(items, by: byDateThenType)) == ["d.png", "c.txt", "b.txt", "a.png", "F"])
        let thenSizeUp = byDateThenType.shiftClicking(.size)
        #expect(thenSizeUp.isAscending(.size) == true)
        #expect(names(SortEngine.sort(items, by: thenSizeUp)) == ["d.png", "b.txt", "c.txt", "a.png", "F"])
    }

    @Test func typeTiesBreakByNameReversingWithTheSort() {
        let items = ["file1.txt", "file2.txt", "file10.txt"].map {
            FileEntry(url: URL(fileURLWithPath: "/f/" + $0), name: $0, isFolder: false, modified: base, size: 1, kind: "Plain Text")
        }
        #expect(names(SortEngine.sort(items, by: SortSpec(key: .kind, ascending: true))) == ["file1.txt", "file2.txt", "file10.txt"])
        #expect(names(SortEngine.sort(items, by: SortSpec(key: .kind, ascending: false))) == ["file10.txt", "file2.txt", "file1.txt"])
    }

    @Test func metadataColumnsSortThroughTheProvider() {
        let a = FileEntry(url: URL(fileURLWithPath: "/f/a.png"), name: "a.png", isFolder: false, modified: base, size: 1, kind: "PNG image")
        let b = FileEntry(url: URL(fileURLWithPath: "/f/b.png"), name: "b.png", isFolder: false, modified: base, size: 1, kind: "PNG image")
        var big = ItemMetadata(); big.pixelWidth = 4000; big.pixelHeight = 3000
        var small = ItemMetadata(); small.pixelWidth = 64; small.pixelHeight = 64
        let meta = [a.url.path: big, b.url.path: small]
        let sorted = SortEngine.sort([a, b], by: SortSpec(key: .dimensions, ascending: true)) { meta[$0.url.path] }
        #expect(names(sorted) == ["b.png", "a.png"])
    }

    @Test func labelsNameEveryKey() {
        #expect(SortLabel.label(SortSpec(key: .size, ascending: false)) == "Size, largest first")
        #expect(SortLabel.label(SortSpec(key: .modified, ascending: false).shiftClicking(.kind).shiftClicking(.name))
            == "Date modified, newest first, then Type, Name")
        #expect(SortLabel.label(SortSpec(key: .created, ascending: true)) == "Date created, oldest first")
    }
}
