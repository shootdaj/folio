import Foundation
import Testing
@testable import FolioCore

/// Details view's folders that open in place: the flattened rows, their depths and the parent of a row.
@Suite struct ListTreeTests {
    private let root = "/private/tmp/folio-tests/list-tree-fixture"

    private func entry(_ path: String, folder: Bool = false, link: Bool = false) -> FileEntry {
        let url = URL(fileURLWithPath: root + "/" + path)
        return FileEntry(url: url, name: url.lastPathComponent, isFolder: folder, modified: nil, size: folder ? nil : 1,
                         kind: folder ? "Folder" : "Plain Text", isLink: link)
    }

    private func key(_ path: String) -> String { FilePaths.itemKey(URL(fileURLWithPath: root + "/" + path)) }

    /// Folders first, then by name: a stand-in for the list's filter and sort.
    private func sorted(_ e: [FileEntry]) -> [FileEntry] {
        e.sorted { ($0.isFolder ? 0 : 1, $0.name) < ($1.isFolder ? 0 : 1, $1.name) }
    }

    private var top: [FileEntry] { [entry("b.txt"), entry("Alpha", folder: true), entry("Beta", folder: true)] }
    private var children: [String: [FileEntry]] {
        [
            key("Alpha"): [entry("Alpha/z.txt"), entry("Alpha/Inner", folder: true), entry("Alpha/a.txt")],
            key("Alpha/Inner"): [entry("Alpha/Inner/deep.txt")],
            key("Beta"): [entry("Beta/one.txt")],
        ]
    }

    private func names(_ r: (items: [FileEntry], depths: [Int])) -> [String] {
        zip(r.items, r.depths).map { String(repeating: "-", count: $1) + $0.name }
    }

    @Test func closedFoldersGiveTheTopLevelOnly() {
        let r = ListTree.flatten(top, children: children, expanded: [], arrange: sorted)
        #expect(names(r) == ["b.txt", "Alpha", "Beta"], "the top level keeps the order it came in")
        #expect(r.depths == [0, 0, 0])
    }

    @Test func anOpenFolderPutsItsArrangedChildrenAfterIt() {
        let r = ListTree.flatten(top, children: children, expanded: [key("Alpha")], arrange: sorted)
        #expect(names(r) == ["b.txt", "Alpha", "-Inner", "-a.txt", "-z.txt", "Beta"])
    }

    @Test func nestedOpenFoldersGoOneLevelDeeper() {
        let r = ListTree.flatten(top, children: children, expanded: [key("Alpha"), key("Alpha/Inner"), key("Beta")], arrange: sorted)
        #expect(names(r) == ["b.txt", "Alpha", "-Inner", "--deep.txt", "-a.txt", "-z.txt", "Beta", "-one.txt"])
    }

    @Test func anOpenFolderUnderAClosedParentDoesNotShow() {
        let r = ListTree.flatten(top, children: children, expanded: [key("Alpha/Inner")], arrange: sorted)
        #expect(names(r) == ["b.txt", "Alpha", "Beta"])
    }

    @Test func aFolderWithNoListingYetShowsNoChildren() {
        let r = ListTree.flatten(top, children: [:], expanded: [key("Alpha")], arrange: sorted)
        #expect(names(r) == ["b.txt", "Alpha", "Beta"])
    }

    @Test func theArrangeStepFiltersEachLevel() {
        // A filter that drops ".txt" files drops them at every level; a dropped folder takes its children.
        let noText: ([FileEntry]) -> [FileEntry] = { sorted($0.filter { !$0.name.hasSuffix(".txt") }) }
        let r = ListTree.flatten(top, children: children, expanded: [key("Alpha"), key("Alpha/Inner")], arrange: noText)
        #expect(names(r) == ["b.txt", "Alpha", "-Inner", "Beta"], "the top level is arranged by the caller, not here")
        let noAlpha: ([FileEntry]) -> [FileEntry] = { $0.filter { $0.name != "Inner" } }
        let r2 = ListTree.flatten(top, children: children, expanded: [key("Alpha"), key("Alpha/Inner")], arrange: noAlpha)
        #expect(!names(r2).contains("--deep.txt"), "a folder the filter hides hides its children")
    }

    @Test func aLinkOrAFileCannotOpen() {
        #expect(ListTree.canExpand(entry("Alpha", folder: true)))
        #expect(!ListTree.canExpand(entry("b.txt")))
        #expect(!ListTree.canExpand(entry("Link", folder: true, link: true)), "a link could loop back up the tree")
        // Even with a listing and a key in the set, a link stays closed.
        let link = entry("Link", folder: true, link: true)
        let r = ListTree.flatten([link], children: [key("Link"): [entry("Link/x.txt")]], expanded: [key("Link")], arrange: sorted)
        #expect(names(r) == ["Link"])
    }

    @Test func aFolderAlreadyOnThePathDoesNotOpenAgain() {
        // A listing that names its own folder (a loop) stops after one level.
        let loop = [key("Alpha"): [entry("Alpha", folder: true)]]
        let r = ListTree.flatten([entry("Alpha", folder: true)], children: loop, expanded: [key("Alpha")], arrange: sorted)
        #expect(r.items.count == 2)
    }

    @Test func theParentOfARowIsTheNearestRowOneLevelUp() {
        let depths = [0, 0, 1, 2, 1, 1, 0, 1]
        #expect(ListTree.parent(of: 0, depths: depths) == nil)
        #expect(ListTree.parent(of: 2, depths: depths) == 1)
        #expect(ListTree.parent(of: 3, depths: depths) == 2)
        #expect(ListTree.parent(of: 5, depths: depths) == 1)
        #expect(ListTree.parent(of: 7, depths: depths) == 6)
        #expect(ListTree.parent(of: 9, depths: depths) == nil, "out of range")
    }

    @Test func descendantsListEveryLevelWithinTheLimits() {
        let tree: [String: [FileEntry]] = [
            root + "/A": [entry("A/B", folder: true), entry("A/f.txt")],
            root + "/A/B": [entry("A/B/C", folder: true)],
            root + "/A/B/C": [entry("A/B/C/D", folder: true)],
            root + "/A/B/C/D": [],
        ]
        let list: (URL) throws -> [FileEntry] = { url in
            guard let rows = tree[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
            return rows
        }
        let all = ListTree.descendants(of: URL(fileURLWithPath: root + "/A"), list: list)
        #expect(Set(all.keys) == [key("A"), key("A/B"), key("A/B/C"), key("A/B/C/D")])
        let two = ListTree.descendants(of: URL(fileURLWithPath: root + "/A"), list: list, maxDepth: 2)
        #expect(Set(two.keys) == [key("A"), key("A/B")], "two levels: the folder and its subfolders")
        let few = ListTree.descendants(of: URL(fileURLWithPath: root + "/A"), list: list, maxFolders: 3)
        #expect(few.count == 3)
        let missing = ListTree.descendants(of: URL(fileURLWithPath: root + "/none"), list: list)
        #expect(missing.isEmpty, "a folder that cannot be listed is left out")
    }

    @Test func outermostDropsItemsInsideAnotherSelectedFolder() {
        // An open folder and its own item both selected: Trash, Copy and drag take the folder alone.
        let urls = ["Alpha", "Alpha/z.txt", "Alpha/Inner/deep.txt", "AlphaBeta/x.txt", "b.txt", "Alpha"]
            .map { URL(fileURLWithPath: root + "/" + $0) }
        #expect(ListTree.outermost(urls).map(\.lastPathComponent) == ["Alpha", "x.txt", "b.txt"],
                "a name that only starts the same (AlphaBeta) is not inside; a repeat goes; the order stays")
        #expect(ListTree.outermost([]).isEmpty)
    }

    @Test func theLayoutKeepsDepthsAndCountsTheTopLevel() {
        let r = ListTree.flatten(top, children: children, expanded: [key("Alpha")], arrange: sorted)
        let layout = ListLayout(items: r.items, depths: r.depths)
        #expect(layout.depths == [0, 0, 1, 1, 1, 0])
        #expect(layout.topLevelCount == 3)
        #expect(layout.rows.count == 6)
        #expect(layout.depth(ofItem: 2) == 1)
        #expect(layout.depth(ofItem: 99) == 0)
        let flat = ListLayout(items: top)
        #expect(flat.depths == [0, 0, 0] && flat.topLevelCount == 3)
    }
}
