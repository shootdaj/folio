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
    }
}

@Suite struct TickerTests {
    private let volume = VolumeCapacity(name: "Macintosh HD", path: "/", total: 926_000_000_000, free: 81_000_000_000)

    @Test func tickerListsFreeSpaceSelectionSortAndPath() {
        let items = Ticker.items(volume: volume, selection: SelectionSummary([entry("ai-harness", folder: true)]),
                                 sort: .standard, path: "/Users/anshul/Anshul/Code")
        #expect(items.map(\.plain) == [
            "Macintosh HD 81.0 GB free of 926 GB",
            "Selected ai-harness, folder",
            "Sorted by name, A to Z",
            "Path /Users/anshul/Anshul/Code",
            "91% of Macintosh HD used, 845 GB",
        ])
        // The free space, the selected name and the path are the bright parts.
        #expect(items[0].segments.filter(\.strong).map(\.text) == ["81.0 GB free"])
        #expect(items[1].segments.filter(\.strong).map(\.text) == ["ai-harness"])
        #expect(items[3].segments.filter(\.strong).map(\.text) == ["/Users/anshul/Anshul/Code"])
    }

    @Test func selectionReadsNothingOneFileOrACount() {
        func selText(_ selected: [FileEntry]) -> String {
            Ticker.items(volume: nil, selection: SelectionSummary(selected), sort: .standard, path: "/")[0].plain
        }
        #expect(selText([]) == "Nothing selected")
        #expect(selText([entry("notes.md", size: 3917)]) == "Selected notes.md, 4 KB")
        #expect(selText([entry("a", size: 2048), entry("b", folder: true)]) == "Selected 2 items, 2 KB")
        #expect(selText([entry("a", folder: true), entry("b", folder: true)]) == "Selected 2 items")
    }

    @Test func withoutAVolumeTheTickerSkipsDiskItems() {
        let items = Ticker.items(volume: nil, selection: SelectionSummary([]),
                                 sort: SortSpec(key: .modified, ascending: false), path: "/private/tmp")
        #expect(items.map(\.plain) == ["Nothing selected", "Sorted by date modified, newest first", "Path /private/tmp"])
    }
}

@Suite struct HudTests {
    @Test func hudReadsDepthCountsSortViewAndSelection() {
        let rows = [entry("a", folder: true), entry("b", folder: true), entry("c.md", size: 1)]
        let segs = Hud.segments(path: "/Users/anshul/Anshul/Code", entries: rows, sort: .standard,
                                selection: SelectionSummary([rows[0]]))
        #expect(segs.map(\.key) == ["Path depth", "Items", "Folders", "Files", "Sort", "View", "Selected"])
        #expect(segs.map(\.value) == ["4", "3", "2", "1", "Name, A to Z", "Details", "a"])
        #expect(segs.map(\.hasLight) == [true, false, false, false, false, false, false])
        #expect(segs.last?.trailing == true)
    }

    @Test func selectedSaysNothingOrACount() {
        let rows = [entry("a"), entry("b")]
        #expect(Hud.segments(path: "/", entries: rows, sort: .standard, selection: SelectionSummary([])).last?.value == "Nothing")
        #expect(Hud.segments(path: "/", entries: rows, sort: .standard, selection: SelectionSummary(rows)).last?.value == "2 items")
        #expect(Hud.segments(path: "/", entries: [], sort: .standard, selection: SelectionSummary([])).first?.value == "0")
    }
}

@Suite struct FileTypeTests {
    @Test func badgeColourFollowsTheDesignsTypeGroups() {
        #expect(FileTypeCategory(name: "README.md") == .doc)
        #expect(FileTypeCategory(name: "notes.TXT") == .doc)
        #expect(FileTypeCategory(name: "main.go") == .code)
        #expect(FileTypeCategory(name: "build.py") == .code)
        #expect(FileTypeCategory(name: "index.html") == .web)
        #expect(FileTypeCategory(name: "site.css") == .web)
        #expect(FileTypeCategory(name: "data.json") == .data)
        #expect(FileTypeCategory(name: "Makefile") == .data)
    }
}
