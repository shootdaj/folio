import Foundation
import Testing
@testable import FuckFinderCore

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
