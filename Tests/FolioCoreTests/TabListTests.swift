import Foundation
import Testing
@testable import FolioCore

/// Tabs in one window: Cmd+T, Cmd+W (the last closes the window), Cmd+Shift+T, Ctrl+Tab cycling,
/// Cmd+1..9, middle-click background tabs, Duplicate, Close others, Close to the right, drag to
/// reorder, and moving a tab to another window (tear out, merge). Each tab keeps its own history.
@Suite struct TabListTests {
    private func folder(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/tabs/" + name, isDirectory: true) }
    private func tab(_ name: String) -> BrowserTab { BrowserTab(folder: folder(name)) }
    private func names(_ list: TabList) -> [String] { list.tabs.map { $0.current.lastPathComponent } }
    private func list(_ names: String..., active: Int = 0) -> TabList { TabList(names.map(tab), active: active) }

    @Test func newTabGoesToTheEndAndBecomesActive() {
        var tabs = list("a", "b")
        let i = tabs.append(tab("c"))
        #expect(i == 2)
        #expect(names(tabs) == ["a", "b", "c"])
        #expect(tabs.activeIndex == 2)
        #expect(tabs.active.current.lastPathComponent == "c")
    }

    @Test func middleClickOpensBackgroundTabsNextToTheActiveOneInOrder() {
        var tabs = list("a", "b", "c")
        tabs.select(0)
        tabs.openNext(tab("x"), activate: false)
        tabs.openNext(tab("y"), activate: false)
        #expect(names(tabs) == ["a", "x", "y", "b", "c"], "the second background tab goes after the first")
        #expect(tabs.activeIndex == 0, "background tabs leave the active one alone")
        tabs.select(3)
        tabs.openNext(tab("z"), activate: true)
        #expect(names(tabs) == ["a", "x", "y", "b", "z", "c"])
        #expect(tabs.active.current.lastPathComponent == "z")
    }

    @Test func closingTheActiveTabActivatesItsRightNeighbourOrTheLeftWhenLast() {
        var tabs = list("a", "b", "c", active: 1)
        let closedB = tabs.close(at: 1)
        #expect(closedB?.current.lastPathComponent == "b")
        #expect(names(tabs) == ["a", "c"])
        #expect(tabs.active.current.lastPathComponent == "c")
        _ = tabs.close(at: 1)
        #expect(tabs.active.current.lastPathComponent == "a")
        let refused = tabs.close(at: 0)
        #expect(refused == nil, "the last tab is not closed here: the window closes instead")
        #expect(tabs.count == 1)
    }

    @Test func closingAnotherTabKeepsTheActiveOne() {
        var tabs = list("a", "b", "c", active: 2)
        _ = tabs.close(at: 0)
        #expect(names(tabs) == ["b", "c"])
        #expect(tabs.active.current.lastPathComponent == "c")
        #expect(tabs.activeIndex == 1)
    }

    @Test func reopenBringsTheLastClosedTabBackWithItsHistory() {
        var tabs = list("a", "b")
        tabs.select(1)
        tabs.active.history.push(folder("b2"))
        var closed = ClosedTabs()
        let index = tabs.activeIndex
        closed.push(tabs.close(at: index)!, index: index)
        #expect(names(tabs) == ["a"])
        let popped = closed.pop()
        let back = try! #require(popped)
        tabs.insert(back.tab, at: back.index, activate: true)
        #expect(names(tabs) == ["a", "b2"])
        #expect(tabs.active.history.canGoBack)
        #expect(tabs.active.history.backList.first?.lastPathComponent == "b")
        let none = closed.pop()
        #expect(none == nil)
    }

    @Test func closedTabsKeepTheLatestTwentyFive() {
        var closed = ClosedTabs()
        for i in 0..<30 { closed.push(tab("t\(i)"), index: 0) }
        #expect(closed.count == ClosedTabs.limit)
        let last = closed.pop()
        #expect(last?.tab.current.lastPathComponent == "t29")
    }

    @Test func controlTabCyclesBothWaysAndWraps() {
        var tabs = list("a", "b", "c")
        tabs.cycle(forward: true)
        #expect(tabs.activeIndex == 1)
        tabs.cycle(forward: true)
        tabs.cycle(forward: true)
        #expect(tabs.activeIndex == 0, "past the last it wraps to the first")
        tabs.cycle(forward: false)
        #expect(tabs.activeIndex == 2, "before the first it wraps to the last")
    }

    @Test func commandNumberSelectsThatTabAndNineTheLast() {
        var tabs = list("a", "b", "c", "d")
        let two = tabs.selectNumber(2)
        #expect(two)
        #expect(tabs.activeIndex == 1)
        let nine = tabs.selectNumber(9)
        #expect(nine)
        #expect(tabs.activeIndex == 3, "Cmd+9 is always the last tab")
        let six = tabs.selectNumber(6)
        #expect(!six, "no sixth tab")
        #expect(tabs.activeIndex == 3)
    }

    @Test func duplicateOpensACopyNextToItWithItsOwnHistory() {
        var tabs = list("a", "b")
        tabs.select(0)
        tabs.active.history.push(folder("a2"))
        let i = tabs.duplicate(at: 0)
        #expect(i == 1)
        #expect(names(tabs) == ["a2", "a2", "b"])
        #expect(tabs.activeIndex == 1)
        #expect(tabs.tabs[0].id != tabs.tabs[1].id)
        tabs.active.history.push(folder("elsewhere"))
        #expect(tabs.tabs[0].current.lastPathComponent == "a2", "the original keeps its own folder")
    }

    @Test func closeOthersAndCloseToTheRight() {
        var tabs = list("a", "b", "c", "d", active: 3)
        let right = tabs.closeToTheRight(of: 1)
        #expect(right.map { $0.current.lastPathComponent } == ["c", "d"])
        #expect(names(tabs) == ["a", "b"])
        #expect(tabs.active.current.lastPathComponent == "b", "the active tab was closed, so the clicked one takes over")
        var more = list("a", "b", "c", active: 0)
        let others = more.closeOthers(keeping: 1)
        #expect(others.count == 2)
        #expect(names(more) == ["b"])
        #expect(more.activeIndex == 0)
    }

    @Test func dragToReorderMovesTheTabToItsNewPlaceAndActiveFollows() {
        var tabs = list("a", "b", "c", "d", active: 1)
        tabs.move(from: 0, to: 2)
        #expect(names(tabs) == ["b", "c", "a", "d"])
        #expect(tabs.active.current.lastPathComponent == "b")
        tabs.move(from: 3, to: 0)
        #expect(names(tabs) == ["d", "b", "c", "a"])
        #expect(tabs.activeIndex == 1)
        tabs.move(from: 1, to: 99)
        #expect(names(tabs) == ["d", "c", "a", "b"], "past the end means the end")
    }

    @Test func moveBetweenWindowsTakesTheTabWithItsHistory() {
        var left = list("a", "b", "c", active: 1)
        var right = list("x")
        left.active.history.push(folder("b2"))
        let id = left.active.id
        let removed = left.remove(id: id)
        let moved = try! #require(removed)
        right.insert(moved, at: 1, activate: true)
        #expect(names(left) == ["a", "c"])
        #expect(left.active.current.lastPathComponent == "c")
        #expect(names(right) == ["x", "b2"])
        #expect(right.active.id == id)
        #expect(right.active.history.canGoBack)
        // The last tab of a window can be merged away too; the window then closes.
        var single = list("solo")
        let gone = single.remove(id: single.active.id)
        let last = try! #require(gone)
        #expect(single.isEmpty)
        right.insert(last, at: 0, activate: false)
        #expect(names(right) == ["solo", "x", "b2"])
        #expect(right.active.id == id, "a tab put in the background leaves the active one active")
        let unknown = single.remove(id: UUID())
        #expect(unknown == nil)
    }

    @Test func eachTabHasItsOwnSortAndSelection() {
        var tabs = list("a", "b")
        tabs.active.sort = SortSpec(key: .size, ascending: false)
        tabs.active.selection = ["/tmp/tabs/a/one"]
        tabs.select(1)
        #expect(tabs.active.sort == .standard)
        #expect(tabs.active.selection.isEmpty)
        tabs.select(0)
        #expect(tabs.active.sort.key == .size)
        #expect(tabs.active.selection == ["/tmp/tabs/a/one"])
    }
}
