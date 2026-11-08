import Testing
@testable import FolioCore

/// The navigation pane scrolls to the current folder's tree row only when no row for it is in view.
@Suite struct SidebarFollowTests {
    @Test func aVisiblePinKeepsThePaneWhereItIs() {
        // Documents pinned at row 3 (in view) and in the tree at row 40 (out of view).
        #expect(!SidebarFollow.shouldScroll(currentRows: [3, 40], visibleRows: 0..<25, forced: false))
    }

    @Test func noCurrentRowInViewScrolls() {
        #expect(SidebarFollow.shouldScroll(currentRows: [40], visibleRows: 0..<25, forced: false))
        #expect(SidebarFollow.shouldScroll(currentRows: [3], visibleRows: 10..<35, forced: false), "the pin is scrolled away")
    }

    @Test func aFolderWithNoRowScrolls() {
        #expect(SidebarFollow.shouldScroll(currentRows: [], visibleRows: 0..<25, forced: false))
    }

    @Test func expandToCurrentFolderAlwaysScrolls() {
        #expect(SidebarFollow.shouldScroll(currentRows: [3, 40], visibleRows: 0..<25, forced: true))
    }
}
