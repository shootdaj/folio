import Foundation
import Testing
@testable import FolioCore

private func suite() -> UserDefaults {
    let name = "folio-column-width-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

/// Columns view: which folders stand side by side, what Left and Right do, how Back and Forward land.
@Suite struct ColumnPathTests {
    let home = "/Users/anshul"
    var anchors: [String] { [home, "/Users/anshul/Documents", "/Users/anshul/Downloads", "/", "/Volumes/Backup"] }

    @Test func theColumnsStartAtTheDeepestQuickAccessOrHomeFolderThatHoldsTheFolder() {
        #expect(ColumnPath.root(for: "/Users/anshul/Documents/Projects/folio", previous: nil, anchors: anchors) == "/Users/anshul/Documents")
        #expect(ColumnPath.root(for: "/Users/anshul/Music/Live", previous: nil, anchors: anchors) == home)
        #expect(ColumnPath.root(for: home, previous: nil, anchors: anchors) == home)
        // Outside home and Quick access: the volume's root, an external drive's own root.
        #expect(ColumnPath.root(for: "/Applications/Utilities", previous: nil, anchors: anchors) == "/")
        #expect(ColumnPath.root(for: "/Volumes/Backup/2026/photos", previous: nil, anchors: anchors) == "/Volumes/Backup")
        // No anchors at all: the startup disk's root.
        #expect(ColumnPath.root(for: "/tmp/folio-tests/a", previous: nil, anchors: []) == "/")
        // A pin saved with a trailing slash still counts; a folder that only shares a name prefix does not.
        #expect(ColumnPath.root(for: "/Users/anshul/Documents2/x", previous: nil, anchors: ["/Users/anshul/Documents/", home]) == home)
        #expect(ColumnPath.root(for: "/Users/anshul/Documents/x", previous: nil, anchors: ["/Users/anshul/Documents/"]) == "/Users/anshul/Documents")
    }

    @Test func movesInsideTheColumnsKeepTheirFirstColumnAndLeavingItStartsAgain() {
        let docs = "/Users/anshul/Documents"
        // From Home's column into Documents: Home's column stays first (Right adds a column, it never re-roots).
        #expect(ColumnPath.root(for: docs, previous: home, shown: [home], anchors: anchors) == home)
        #expect(ColumnPath.root(for: "/Users/anshul/Documents/a/b", previous: home, shown: [home, docs, "/Users/anshul/Documents/a"],
                                anchors: anchors) == home)
        // Back or Left to a folder on screen: the same first column.
        #expect(ColumnPath.root(for: docs, previous: home, shown: [home, docs, "/Users/anshul/Documents/a"], anchors: anchors) == home)
        // Left out of the first column: its parent becomes the first column (the deepest anchor that holds it).
        #expect(ColumnPath.root(for: home, previous: docs, shown: [docs], anchors: anchors) == home)
        #expect(ColumnPath.root(for: "/Users", previous: home, shown: [home], anchors: anchors) == "/")
        // The sidebar or the address bar to a folder deeper down, not on screen: a fresh start, kept short.
        #expect(ColumnPath.root(for: "/Users/anshul/Documents/a/b", previous: home, shown: [home], anchors: anchors) == docs)
        #expect(ColumnPath.root(for: "/Users/anshul/Documents/a/b", previous: "/", shown: ["/", "/tmp"], anchors: anchors) == docs)
        // Somewhere else entirely: a fresh start there.
        #expect(ColumnPath.root(for: "/Volumes/Backup/x", previous: home, shown: [home], anchors: anchors) == "/Volumes/Backup")
    }

    @Test func theFoldersRunFromTheFirstColumnToTheCurrentFolder() {
        #expect(ColumnPath.folders(from: home, to: "/Users/anshul/Documents/a") ==
                [home, "/Users/anshul/Documents", "/Users/anshul/Documents/a"])
        #expect(ColumnPath.folders(from: home, to: home) == [home])
        #expect(ColumnPath.folders(from: "/", to: "/tmp/folio-tests") == ["/", "/tmp", "/tmp/folio-tests"])
        #expect(ColumnPath.folders(from: "/", to: "/") == ["/"])
        // Inside a zip, the zip is a column like any folder.
        #expect(ColumnPath.folders(from: home, to: "/Users/anshul/x.zip/in") == [home, "/Users/anshul/x.zip", "/Users/anshul/x.zip/in"])
        // A first column that does not hold the folder: the folder alone.
        #expect(ColumnPath.folders(from: "/Volumes/Backup", to: "/Users/anshul") == ["/Users/anshul"])
    }

    @Test func eachColumnHighlightsTheItemThatLeadsOn() {
        #expect(ColumnPath.child(of: home, toward: "/Users/anshul/Documents/a") == "/Users/anshul/Documents")
        #expect(ColumnPath.child(of: "/", toward: "/tmp/x") == "/tmp")
        #expect(ColumnPath.child(of: home, toward: home) == nil)
        #expect(ColumnPath.child(of: "/Users/anshul/Documents", toward: "/Users/anshul/Downloads/a") == nil)
        #expect(ColumnPath.child(of: "/Users/an", toward: "/Users/anshul/a") == nil)
    }

    @Test func selectingAFolderOpensItsColumnAndSelectingAFileShowsThePreview() {
        let root = home, current = "/Users/anshul/Documents"
        let folder = ColumnPlan.make(root: root, current: current, selected: [("/Users/anshul/Documents/a", true)])
        #expect(folder.folders == [home, "/Users/anshul/Documents"])
        #expect(folder.highlighted == ["Documents"])
        #expect(folder.tail == .folder("/Users/anshul/Documents/a"))
        let file = ColumnPlan.make(root: root, current: current, selected: [("/Users/anshul/Documents/notes.txt", false)])
        #expect(file.tail == .preview("/Users/anshul/Documents/notes.txt"))
        // Several items, or none: nothing after the current folder's column.
        #expect(ColumnPlan.make(root: root, current: current, selected: [("/Users/anshul/Documents/a", true),
                                                                          ("/Users/anshul/Documents/b", true)]).tail == .none)
        #expect(ColumnPlan.make(root: root, current: current, selected: []).tail == .none)
        // The first column is the root itself: nothing highlighted before the current folder.
        #expect(ColumnPlan.make(root: home, current: home, selected: []).highlighted == [])
    }

    @Test func rightGoesIntoTheSelectedFolderAndNowhereForAFileOrSeveralItems() {
        #expect(ColumnKeys.right(selected: [("/r/a", true)]) == .enter("/r/a"))
        #expect(ColumnKeys.right(selected: [("/r/notes.txt", false)]) == .none)
        #expect(ColumnKeys.right(selected: [("/r/a", true), ("/r/b", true)]) == .none)
        #expect(ColumnKeys.right(selected: []) == .none)
    }

    @Test func leftGoesToTheColumnBeforeWithThisFolderSelected() {
        #expect(ColumnKeys.left(current: "/r/a/b") == .leave(to: "/r/a", select: "/r/a/b"))
        // In the first column it goes up a folder anyway (the columns then start there).
        #expect(ColumnKeys.left(current: "/r") == .leave(to: "/", select: "/r"))
        #expect(ColumnKeys.left(current: "/") == .none)
    }

    @Test func backAndForwardLandOnTheFolderWithTheFolderTheyCameFromSelected() {
        // Right, Right then Back: the column before, with the folder just left selected (its column stays open).
        #expect(ColumnPath.selection(arriving: "/r/a/b", from: "/r/a/b/c") == "/r/a/b/c")
        // Back past several columns at once (Left was a step of its own): the child on the way.
        #expect(ColumnPath.selection(arriving: "/r", from: "/r/a/b") == "/r/a")
        // Forward into a deeper folder, or across to a sibling: nothing to select.
        #expect(ColumnPath.selection(arriving: "/r/a/b/c", from: "/r/a/b") == nil)
        #expect(ColumnPath.selection(arriving: "/r/x", from: "/r/a/b") == nil)
    }
}

@Suite struct ColumnWidthTests {
    @Test func oneWidthForEveryColumnRememberedAcrossFoldersAndLaunches() {
        let d = suite()
        #expect(ColumnWidth.load(d) == ColumnWidth.standard)
        ColumnWidth.save(312, d)
        #expect(ColumnWidth.load(d) == 312)
        // A width from an older build or a typo in the defaults comes back inside the limits.
        d.set(5, forKey: ColumnWidth.key)
        #expect(ColumnWidth.load(d) == ColumnWidth.minimum)
        d.set(9000, forKey: ColumnWidth.key)
        #expect(ColumnWidth.load(d) == ColumnWidth.maximum)
    }

    @Test func doubleClickingADividerFitsTheWidestNameWithinTheLimits() {
        #expect(ColumnWidth.fit(widest: 200, chrome: 64) == 264)
        #expect(ColumnWidth.fit(widest: 10, chrome: 64) == ColumnWidth.minimum)
        #expect(ColumnWidth.fit(widest: 2000, chrome: 64) == ColumnWidth.maximum)
    }
}

@Suite struct ColumnPreviewTests {
    @Test func aFileShowsKindSizeCreatedModifiedAndTags() {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let created = Date(timeIntervalSince1970: 1_600_000_000)
        let e = FileEntry(url: URL(fileURLWithPath: "/r/notes.txt"), name: "notes.txt", isFolder: false, modified: modified,
                          size: 5000, kind: "Plain Text")
        var meta = ItemMetadata()
        meta.created = created
        meta.tags = ["Red", "Work"]
        let fields = ColumnPreview.fields(e, meta)
        #expect(fields.map(\.key) == ["Kind", "Size", "Created", "Modified", "Tags"])
        #expect(fields[0].value == "Plain Text")
        #expect(fields[1].value == ColumnValues.text(e, .size, meta))
        #expect(fields[2].value == ColumnValues.dateText(created))
        #expect(fields[3].value == ColumnValues.dateText(modified))
        #expect(fields[4].value == "Red, Work")
    }

    @Test func untaggedSaysSoAndWhatIsNotReadYetWaits() {
        let e = FileEntry(url: URL(fileURLWithPath: "/r/a.png"), name: "a.png", isFolder: false, modified: nil, size: 0, kind: "PNG image")
        #expect(ColumnPreview.fields(e, ItemMetadata()).first { $0.key == "Tags" }?.value == "None")
        // Before the metadata is read: no Created and no Tags line yet (they appear when it lands).
        #expect(ColumnPreview.fields(e, nil).map(\.key) == ["Kind", "Size"])
    }
}

@Suite struct ColumnsViewModeTests {
    @Test func columnsIsTheNinthLayoutAfterExplorersEight() {
        #expect(ViewMode.forShortcut(9) == .columns)
        #expect(ViewMode.columns.shortcut == 9)
        #expect(ViewMode.columns.title == "Columns")
        #expect(ViewMode.forShortcut(10) == nil)
        // In the View menu it follows Content, before Gallery.
        let all = ViewMode.allCases
        #expect(all.firstIndex(of: .columns) == all.firstIndex(of: .content)! + 1)
        #expect(all.last == .gallery)
    }

    @Test func columnsIsNeitherTheTableNorTheIconGrid() {
        #expect(!ViewMode.columns.usesTable)
        #expect(!ViewMode.columns.usesGrid)
        #expect(ViewMode.details.usesTable && !ViewMode.details.usesGrid)
        for mode in ViewMode.allCases where mode != .details && mode != .columns { #expect(mode.usesGrid) }
    }

    @Test func cmdScrollStepsOutOfColumnsAndNeverIntoIt() {
        // Columns sits beside Details and List: scrolling up goes to List, down to Details.
        #expect(ViewMode.columns.zoomed(by: 1) == .list)
        #expect(ViewMode.columns.zoomed(by: -1) == .details)
        // The other views step exactly as before.
        #expect(!ViewMode.zoomOrder.contains(.columns))
        #expect(ViewMode.details.zoomed(by: 1) == .list)
        #expect(ViewMode.list.zoomed(by: -1) == .details)
    }
}
