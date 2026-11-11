import Testing
@testable import FolioCore

/// The navigation pane opens the tree down to a folder, and scrolls to its tree row only when no row
/// for that folder is in view already (a Quick access pin, say). Ctrl+Shift+E always scrolls.
@Suite struct SidebarFollowTests {
    /// Stands in for FilePaths.folderKey: /tmp is /private/tmp on the Mac.
    func key(_ path: String) -> String { path.hasPrefix("/tmp/") ? "/private" + path : path }

    func scrolls(to target: String, _ visible: [String?], forced: Bool = false) -> Bool {
        SidebarFollow.shouldScroll(to: target, visiblePaths: visible, forced: forced, key: key)
    }

    @Test func aVisiblePinForTheFolderKeepsThePaneWhereItIs() {
        // Home, the Documents pin and a heading are in view; the tree row for Documents is far below.
        #expect(!scrolls(to: "/Users/admin/Documents", [nil, "/Users/admin/Desktop", "/Users/admin/Documents", nil]))
    }

    @Test func aPinMatchesThroughTheResolvedPath() {
        #expect(!scrolls(to: "/private/tmp/work", ["/tmp/work"]))
    }

    @Test func noRowForTheFolderInViewScrolls() {
        #expect(scrolls(to: "/Users/admin/Documents", ["/Users/admin/Desktop", "/Users/admin/Downloads"]))
        #expect(scrolls(to: "/Users/admin/Documents", []), "no rows in view at all")
    }

    /// New folder from a node's menu reveals the new folder, not the window's folder. The window's
    /// folder in view must not keep the pane from scrolling to the new one.
    @Test func theWindowsFolderInViewDoesNotStandInForAnotherFolder() {
        #expect(scrolls(to: "/Users/admin/Documents/New folder", [nil, "/Users/admin/Documents"]))
    }

    @Test func expandToCurrentFolderAlwaysScrolls() {
        #expect(scrolls(to: "/Users/admin/Documents", ["/Users/admin/Documents"], forced: true))
    }
}
