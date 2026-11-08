import Testing
@testable import FolioCore

/// The right-hand pane is dragged wider or narrower at its left edge, within bounds, and leaves the list room.
@Suite struct SidePaneSizeTests {
    @Test func aDragSetsTheWidthFromTheRightEdgeWithinBounds() {
        #expect(SidePaneSize.dragged(toX: 1000, rightEdge: 1440) == 440)
        #expect(SidePaneSize.dragged(toX: 1400, rightEdge: 1440) == SidePaneSize.minimum)
        #expect(SidePaneSize.dragged(toX: 0, rightEdge: 1440) == SidePaneSize.maximum)
    }

    @Test func theListKeepsItsRoomInANarrowWindow() {
        #expect(SidePaneSize.shown(chosen: 340, room: 1192) == 340, "a normal window shows the chosen width")
        #expect(SidePaneSize.shown(chosen: 600, room: 800) == 440, "the list keeps 360 pt")
        #expect(SidePaneSize.shown(chosen: 340, room: 300) == 0, "no room: no pane")
    }
}
