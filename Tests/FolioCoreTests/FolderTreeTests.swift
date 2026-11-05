import Foundation
import Testing
@testable import FolioCore

/// The navigation pane's tree: children read only when a node opens, folders only in natural order,
/// hidden folders only when shown (or on the way to the current folder), Expand to current folder,
/// and Numpad * expanding everything under a node.
@Suite struct FolderTreeTests {
    /// root/alpha/beta/gamma (three levels), plus siblings, a file, a package, a hidden and a dot folder.
    private func makeTree() throws -> TestTree {
        let t = try TestTree()
        try t.folder("tree/alpha/beta/gamma")
        try t.folder("tree/alpha/beta2")
        try t.folder("tree/File10")
        try t.folder("tree/File2")
        try t.folder("tree/beta")
        try t.folder("tree/Zeta")
        try t.folder("tree/App.app/Contents")
        try t.folder("tree/.dotted/inner")
        try t.folder("tree/flagged/inside")
        try ItemFlags.setHidden(true, t.url("tree/flagged"))
        try t.file("tree/notes.txt")
        return t
    }

    private func path(_ t: TestTree, _ p: String) -> String { FilePaths.folderKey(t.url(p)) }

    @Test func childrenAreReadOnlyWhenANodeOpens() throws {
        let t = try makeTree()
        defer { t.close() }
        let tree = FolderTree()
        let top = path(t, "tree")
        #expect(!tree.isLoaded(top))
        #expect(tree.listCount == 0)
        _ = tree.children(of: top)
        #expect(tree.isLoaded(top))
        #expect(tree.listCount == 1)
        _ = tree.children(of: top)
        #expect(tree.listCount == 1, "a second ask comes from the cache")
        #expect(!tree.isLoaded(path(t, "tree/alpha")), "grandchildren wait until their node opens")
        tree.invalidate(top)
        #expect(!tree.isLoaded(top))
    }

    @Test func foldersOnlyInNaturalOrderWithoutHiddenOnes() throws {
        let t = try makeTree()
        defer { t.close() }
        let names = FolderTree().children(of: path(t, "tree")).map(\.name)
        // File2 before File10, case ignored; no file, no package, no dot or flagged folder.
        #expect(names == ["alpha", "beta", "File2", "File10", "Zeta"])
    }

    @Test func hiddenFoldersShowWhenHiddenItemsAreOn() throws {
        let t = try makeTree()
        defer { t.close() }
        let tree = FolderTree(showHidden: true)
        let kids = tree.children(of: path(t, "tree"))
        #expect(kids.map(\.name) == [".dotted", "alpha", "beta", "File2", "File10", "flagged", "Zeta"])
        #expect(kids.filter(\.isHidden).map(\.name) == [".dotted", "flagged"])
        tree.showHidden = false
        #expect(!tree.isLoaded(path(t, "tree")), "switching the toggle reads the folders again")
        #expect(tree.children(of: path(t, "tree")).count == 5)
    }

    @Test func chainRunsFromTheVolumeRootToTheFolder() {
        #expect(FolderTree.chain(from: "/", to: "/private/tmp/x") == ["/", "/private", "/private/tmp", "/private/tmp/x"])
        #expect(FolderTree.chain(from: "/Volumes/Scratch", to: "/Volumes/Scratch/a/b")
                == ["/Volumes/Scratch", "/Volumes/Scratch/a", "/Volumes/Scratch/a/b"])
        #expect(FolderTree.chain(from: "/Volumes/Scratch", to: "/Volumes/Scratch") == ["/Volumes/Scratch"])
        #expect(FolderTree.chain(from: "/Volumes/Scratch", to: "/Users/x") == nil)
        #expect(FolderTree.chain(from: "/Volumes/Scr", to: "/Volumes/Scratch/a") == nil, "a name prefix is not a parent")
    }

    @Test func theRootIsTheDeepestVolumeHoldingThePath() {
        let roots = ["/", "/Volumes/Scratch", "/Volumes/Scratch Two"]
        #expect(FolderTree.root(for: "/Volumes/Scratch/a", roots: roots) == "/Volumes/Scratch")
        #expect(FolderTree.root(for: "/Volumes/Scratch Two/b", roots: roots) == "/Volumes/Scratch Two")
        #expect(FolderTree.root(for: "/Users/someone", roots: roots) == "/")
        #expect(FolderTree.root(for: "/Volumes/Other/c", roots: roots) == "/")
    }

    @Test func expandToCurrentFolderRevealsHiddenFoldersOnTheWay() throws {
        let t = try makeTree()
        defer { t.close() }
        let tree = FolderTree()
        let top = path(t, "tree")
        let target = path(t, "tree/flagged/inside")
        #expect(!tree.children(of: top).map(\.name).contains("flagged"))
        let chain = try #require(FolderTree.chain(from: top, to: target))
        let changed = tree.reveal(chain)
        #expect(changed == [top], "the node that now shows one more child reloads")
        #expect(tree.children(of: top).map(\.name).contains("flagged"))
        #expect(tree.children(of: path(t, "tree/flagged")).map(\.name) == ["inside"])
        // Every node on the chain but the last is there to expand, in order.
        #expect(tree.reveal(chain).isEmpty, "a second reveal changes nothing")
    }

    @Test func expandAllListsEverythingBelowBreadthFirstUpToALimit() throws {
        let t = try makeTree()
        defer { t.close() }
        let tree = FolderTree()
        let top = path(t, "tree")
        let all = tree.descendants(of: top, limit: 100)
        #expect(all.first == top)
        #expect(Set(all) == Set([top, path(t, "tree/alpha"), path(t, "tree/beta"), path(t, "tree/File2"),
                                 path(t, "tree/File10"), path(t, "tree/Zeta"), path(t, "tree/alpha/beta"),
                                 path(t, "tree/alpha/beta2"), path(t, "tree/alpha/beta/gamma")]))
        #expect(all.firstIndex(of: path(t, "tree/Zeta"))! < all.firstIndex(of: path(t, "tree/alpha/beta"))!)
        #expect(tree.descendants(of: top, limit: 3).count == 3)
    }

    @Test func aSymlinkedFolderShowsButExpandAllDoesNotFollowIt() throws {
        let t = try makeTree()
        defer { t.close() }
        try FileManager.default.createSymbolicLink(at: t.url("tree/alpha/loop"), withDestinationURL: t.url("tree"))
        let tree = FolderTree()
        let alpha = path(t, "tree/alpha")
        let kids = tree.children(of: alpha)
        #expect(kids.map(\.name) == ["beta", "beta2", "loop"])
        #expect(kids.last?.isLink == true)
        let all = tree.descendants(of: path(t, "tree"), limit: 500)
        #expect(all.count == 9, "the loop is never walked into")
    }
}
