import Foundation
import Testing
@testable import FolioCore

private func entry(_ name: String, folder: Bool = false, size: Int64? = nil) -> FileEntry {
    FileEntry(url: URL(fileURLWithPath: "/tmp/x/\(name)"), name: name, isFolder: folder,
              modified: nil, size: folder ? nil : size, kind: folder ? "Folder" : "File")
}

@Suite struct StatusTextTests {
    @Test func countReadsItemsAndSelected() {
        #expect(StatusText.count(items: 28, selection: SelectionSummary([])) == "28 items, 0 selected")
        #expect(StatusText.count(items: 1, selection: SelectionSummary([])) == "1 item, 0 selected")
        let folder = SelectionSummary([entry("ai-harness", folder: true)])
        #expect(StatusText.count(items: 28, selection: folder) == "28 items, 1 selected")
        let files = SelectionSummary([entry("a.md", size: 3917), entry("b.txt", size: 15)])
        #expect(StatusText.count(items: 50_000, selection: files) == "50,000 items, 2 selected, 4 KB")
    }

    @Test func sizesShowInKilobytesRoundedUp() {
        #expect(ByteText.kilobytes(0) == "0 KB")
        #expect(ByteText.kilobytes(15) == "1 KB")
        #expect(ByteText.kilobytes(1024) == "1 KB")
        #expect(ByteText.kilobytes(1025) == "2 KB")
        #expect(ByteText.kilobytes(4_000_000) == "3,907 KB")
    }

    @Test func sortLabelsMatchTheDesign() {
        #expect(SortLabel.label(SortSpec(key: .name, ascending: true)) == "Name, A to Z")
        #expect(SortLabel.label(SortSpec(key: .name, ascending: false)) == "Name, Z to A")
        #expect(SortLabel.label(SortSpec(key: .modified, ascending: false)) == "Date modified, newest first")
        #expect(SortLabel.label(SortSpec(key: .kind, ascending: true)) == "Type, A to Z")
        #expect(SortLabel.label(SortSpec(key: .size, ascending: false)) == "Size, largest first")
        #expect(SortLabel.sentence(SortSpec(key: .kind, ascending: true)) == "Sorted by Type, A to Z")
    }
}

/// The status bar's readouts: what the Control room's HUD and ticker showed, in D4's status bar.
@Suite struct StatusReadoutTests {
    private let volume = VolumeCapacity(name: "Macintosh HD", path: "/", total: 926_000_000_000, free: 81_000_000_000)

    @Test func browsingReadsCountSelectionSortVolumeAndView() {
        let rows = (0..<28).map { entry("f\($0)", folder: true) }
        let r = StatusReadout.make(items: rows.count, selection: SelectionSummary([entry("ai-harness", folder: true)]),
                                   sort: .standard, volume: volume, view: "Details")
        #expect(r.count == "28 items, 1 selected")
        #expect(r.selected == "ai-harness")
        #expect(r.sort == "Sorted by Name, A to Z")
        #expect(r.volumeName == "Macintosh HD" && r.volumeFree == "81.0 GB")
        #expect(r.volumeText == "Macintosh HD, 81.0 GB free")
        #expect(r.view == "Details")
        #expect(!r.busy)
    }

    @Test func nothingSelectedLeavesTheCountAlone() {
        let r = StatusReadout.make(items: 1, selection: SelectionSummary([]), sort: .standard, volume: nil, view: "Large icons")
        #expect(r.count == "1 item")
        #expect(r.selected == nil)
        #expect(r.volumeText == nil, "no volume, no free space")
        #expect(r.view == "Large icons")
    }

    @Test func theSelectionCarriesTheNameOrTheSizeOfTheSelectedFiles() {
        let rows = [entry("a.mov", size: 70_000_000), entry("b.mov", size: 2048), entry("Docs", folder: true)]
        func selected(_ s: [FileEntry]) -> String? {
            StatusReadout.make(items: 3, selection: SelectionSummary(s), sort: .standard, volume: nil, view: "Details").selected
        }
        #expect(selected([rows[0]]) == "a.mov, 68,360 KB")
        #expect(selected(rows) == "68,362 KB")
        #expect(selected([rows[2]]) == "Docs", "a folder has no size to show")
        #expect(selected([rows[2], entry("More", folder: true)]) == nil)
    }

    @Test func aFilteredListSaysWhatItWasFilteredFrom() {
        let r = StatusReadout.make(items: 3, total: 12, selection: SelectionSummary([]), sort: .standard, volume: nil, view: "Details")
        #expect(r.count == "3 items (filtered from 12)")
    }

    @Test func aSearchReadsSearchingUntilResultsThenRelevance() {
        let none = SelectionSummary([])
        let running = StatusReadout.make(items: 0, selection: none, sort: nil, volume: nil, view: "Details", searchingIn: "work")
        #expect(running.count == "Searching work")
        #expect(running.busy)
        #expect(running.sort == "Sorted by relevance")
        let growing = StatusReadout.make(items: 1234, selection: none, sort: nil, volume: nil, view: "Details", searchingIn: "work")
        #expect(growing.count == "1,234 items" && growing.busy)
        let done = StatusReadout.make(items: 1234, selection: none, sort: SortSpec(key: .modified, ascending: false),
                                      volume: nil, view: "Details")
        #expect(!done.busy)
        #expect(done.sort == "Sorted by Date modified, newest first")
    }
}

/// The sidebar's Details card, as D4 fills it.
@Suite struct DetailsCardTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test func oneFolderShowsNameKindModifiedAndWhere() {
        let folder = FileEntry(url: URL(fileURLWithPath: "/Users/anshul/Anshul/Code/ai-harness"), name: "ai-harness", isFolder: true,
                               modified: Date(timeIntervalSince1970: 1_788_908_340), size: nil, kind: "Folder")
        let card = DetailsCard.make([folder], timeZone: utc)
        #expect(card.icon == .item(name: "ai-harness", isFolder: true))
        #expect(card.title == "ai-harness" && card.subtitle == "Folder")
        #expect(card.fields.map(\.key) == ["Modified", "Where"], "a folder has no size")
        #expect(card.fields[0].value == "2026-09-08 22:59")
        #expect(card.fields[1].value == "/Users/anshul/Anshul/Code")
    }

    @Test func aFileAddsItsSize() {
        let file = entry("airbnb-bangkok-search.md", size: 3917)
        let card = DetailsCard.make([file])
        #expect(card.fields.map(\.key) == ["Size", "Where"], "no date known, so no Modified")
        #expect(card.fields[0].value == "4 KB")
    }

    @Test func severalItemsShowAStackTheMixAndTheSize() {
        let card = DetailsCard.make([entry("a", folder: true), entry("b", folder: true), entry("c.md", size: 2048)])
        #expect(card.icon == .stack)
        #expect(card.title == "3 items selected")
        #expect(card.subtitle == "2 folders, 1 file")
        #expect(card.fields == [DetailsCard.Field(key: "Size", value: "2 KB")])
        #expect(DetailsCard.make([entry("a", folder: true), entry("b", folder: true)]).fields.isEmpty)
    }

    @Test func nothingSelectedSaysSo() {
        let card = DetailsCard.make([])
        #expect(card.isEmpty)
        #expect(card.title == "Select an item to see its details here.")
    }
}

/// A selection counted in place gives what the copied selection gave (Cmd+A in a big folder copies nothing).
@Suite struct SelectionInPlaceTests {
    private static func entry(_ i: Int) -> FileEntry {
        let folder = i % 5 == 0
        let size: Int64? = folder ? nil : Int64(i * 1000)
        let url = URL(fileURLWithPath: "/private/tmp/folio-tests/sel/\(i)")
        return FileEntry(url: url, name: "item \(i)", isFolder: folder, modified: Date(timeIntervalSince1970: Double(i) * 3600),
                         size: size, kind: "Plain Text")
    }
    private let entries: [FileEntry] = (0..<40).map(SelectionInPlaceTests.entry)

    @Test func summariesAndCardsMatchForAnySelection() {
        let selections: [IndexSet] = [[], [3], [0], IndexSet(0..<40), IndexSet([1, 2, 7, 8, 9, 30]), IndexSet(5..<15), [0, 5, 10], [4, 39]]
        for rows in selections {
            let copied = rows.map { entries[$0] }
            #expect(SelectionSummary(entries, rows: rows) == SelectionSummary(copied), "\(Array(rows))")
            let tz = TimeZone(identifier: "UTC")!
            #expect(DetailsCard.make(entries, rows: rows, timeZone: tz) == DetailsCard.make(copied, timeZone: tz), "\(Array(rows))")
        }
    }
}
