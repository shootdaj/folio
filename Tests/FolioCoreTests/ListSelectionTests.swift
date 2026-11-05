import Foundation
import Testing
@testable import FolioCore

/// Explorer's selection rules on a Details list of 10 rows.
@Suite struct ListSelectionTests {
    private func rows(_ r: Int...) -> IndexSet { IndexSet(r) }

    @Test func clickSelectsOnlyThatRowAndSetsTheAnchor() {
        var s = ListSelection(count: 10)
        s.click(2)
        s.click(5)
        #expect(s.rows == rows(5))
        #expect(s.anchor == 5)
        #expect(s.focus == 5)
    }

    @Test func cmdClickTogglesRowsInAndOut() {
        var s = ListSelection(count: 10)
        s.click(1)
        s.toggle(4)
        s.toggle(7)
        #expect(s.rows == rows(1, 4, 7))
        s.toggle(4)
        #expect(s.rows == rows(1, 7))
        #expect(s.anchor == 4, "the toggled row becomes the anchor for the next Shift+click")
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchorAndDropsTheRest() {
        var s = ListSelection(count: 10)
        s.click(0)
        s.toggle(8)            // anchor 8, rows 0 and 8
        s.extend(to: 5)
        #expect(s.rows == IndexSet(5...8), "Explorer drops row 0: Shift+click replaces the selection")
        s.extend(to: 9)
        #expect(s.rows == IndexSet(8...9), "the anchor stays where it was")
        #expect(s.anchor == 8)
        #expect(s.focus == 9)
    }

    @Test func shiftClickWithNothingSelectedStartsAtTheClickedRow() {
        var s = ListSelection(count: 10)
        s.extend(to: 3)
        #expect(s.rows == rows(3))
        #expect(s.anchor == 3)
    }

    @Test func cmdShiftClickAddsASecondRangeWithoutDroppingTheFirst() {
        var s = ListSelection(count: 10)
        s.click(1)
        s.extend(to: 2)        // 1...2
        s.toggle(6)            // anchor 6
        s.addRange(to: 8)      // + 6...8
        #expect(s.rows == IndexSet([1, 2, 6, 7, 8]))
    }

    @Test func shiftArrowsExtendFromTheAnchorAndShrinkBack() {
        var s = ListSelection(count: 10)
        s.click(4)
        s.move(.down, extend: true)
        s.move(.down, extend: true)
        #expect(s.rows == IndexSet(4...6))
        s.move(.up, extend: true)
        #expect(s.rows == IndexSet(4...5))
        s.move(.up, extend: true)
        s.move(.up, extend: true)
        #expect(s.rows == IndexSet(3...4), "crossing the anchor extends the other way")
        #expect(s.anchor == 4)
    }

    @Test func shiftHomeAndShiftEndSelectToTheEnds() {
        var s = ListSelection(count: 10)
        s.click(6)
        s.move(.home, extend: true)
        #expect(s.rows == IndexSet(0...6))
        s.move(.end, extend: true)
        #expect(s.rows == IndexSet(6...9))
    }

    @Test func plainArrowsMoveASingleSelectionAndStopAtTheEdges() {
        var s = ListSelection(count: 3)
        s.move(.down, extend: false)
        #expect(s.rows == rows(0), "the first Down with nothing focused lands on the first row")
        s.move(.down, extend: false)
        s.move(.down, extend: false)
        s.move(.down, extend: false)
        #expect(s.rows == rows(2))
        s.move(.home, extend: false)
        #expect(s.rows == rows(0))
        s.move(.up, extend: false)
        #expect(s.rows == rows(0))
    }

    @Test func pageMovesJumpByAPage() {
        var s = ListSelection(count: 100)
        s.click(10)
        s.move(.pageDown(20), extend: false)
        #expect(s.rows == rows(30))
        s.move(.pageUp(50), extend: true)
        #expect(s.rows == IndexSet(0...30))
    }

    @Test func ctrlArrowsMoveTheFocusAndCtrlSpaceTogglesIt() {
        var s = ListSelection(count: 10)
        s.click(2)
        s.moveFocus(.down)
        s.moveFocus(.down)
        #expect(s.rows == rows(2), "moving the focus leaves the selection alone")
        #expect(s.focus == 4)
        s.toggleFocused()
        #expect(s.rows == rows(2, 4))
        s.toggleFocused()
        #expect(s.rows == rows(2))
    }

    @Test func selectAllNoneAndInvert() {
        var s = ListSelection(count: 6)
        s.click(1)
        s.toggle(3)
        s.invert()
        #expect(s.rows == rows(0, 2, 4, 5))
        s.selectAll()
        #expect(s.rows == IndexSet(0..<6))
        s.invert()
        #expect(s.rows.isEmpty)
        s.click(2)
        s.selectNone()
        #expect(s.rows.isEmpty)
    }

    @Test func aShorterListDropsRowsThatAreGone() {
        var s = ListSelection(count: 10)
        s.click(7)
        s.extend(to: 9)
        s.setCount(8)
        #expect(s.rows == rows(7))
        #expect(s.focus == 7)
        #expect(s.anchor == 7)
        s.setCount(0)
        #expect(s.rows.isEmpty)
        #expect(s.focus == nil)
    }

    @Test func adoptingAnOutsideSelectionKeepsItAsTheTruth() {
        var s = ListSelection(count: 10)
        s.adopt(rows(3, 4), focus: 4)
        #expect(s.rows == rows(3, 4))
        s.move(.down, extend: true)
        #expect(s.rows == IndexSet(4...5), "the adopted focus is the new anchor")
    }
}

/// The rubber band: which rows a drag rectangle touches, and how it combines with the selection.
@Suite struct RubberBandTests {
    @Test func rowsTouchedByABandFromBelowTheList() {
        // 24 pt rows. A band from y=100 (row 4) up to y=30 (row 1).
        let hit = RubberBand.rows(fromY: 100, toY: 30, rowHeight: 24, count: 10)
        #expect(hit == IndexSet(1...4))
    }

    @Test func aBandBelowTheLastRowTouchesNothing() {
        #expect(RubberBand.rows(fromY: 300, toY: 260, rowHeight: 24, count: 10).isEmpty)
    }

    @Test func aBandOnARowEdgeOnlyTouchesTheRowItEnters() {
        // y=48 is the top edge of row 2: a band from 48 to 70 is inside row 2 only.
        #expect(RubberBand.rows(fromY: 48, toY: 70, rowHeight: 24, count: 10) == IndexSet(integer: 2))
        // From 20 to 48 is rows 0 and 1, never row 2.
        #expect(RubberBand.rows(fromY: 20, toY: 48, rowHeight: 24, count: 10) == IndexSet(0...1))
    }

    @Test func aBandPastTheEndsIsClampedToTheList() {
        #expect(RubberBand.rows(fromY: -50, toY: 1000, rowHeight: 24, count: 5) == IndexSet(0..<5))
        #expect(RubberBand.rows(fromY: 10, toY: 10, rowHeight: 24, count: 0).isEmpty)
    }

    @Test func cmdDragAddsToTheSelectionAndPlainDragReplacesIt() {
        let base = IndexSet([0, 9])
        let hit = IndexSet(3...5)
        #expect(RubberBand.selection(base: base, hit: hit, adding: true) == IndexSet([0, 3, 4, 5, 9]))
        #expect(RubberBand.selection(base: base, hit: hit, adding: false) == hit)
    }

    @Test func theBandRectIsNormalisedWhicheverWayYouDrag() {
        let r = RubberBand.rect(from: (x: 300, y: 200), to: (x: 100, y: 50))
        #expect(r.x == 100 && r.y == 50 && r.width == 200 && r.height == 150)
    }
}
