import Foundation
import Testing
@testable import FolioCore

private func dir(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

@Suite struct NavigationHistoryTests {
    @Test func startsAtTheStartFolderWithNothingToGoBackOrForwardTo() {
        let history = NavigationHistory(start: dir("/Users/anshul"))
        #expect(history.current.path == "/Users/anshul")
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func backAndForwardWalkThePushedFolders() {
        var history = NavigationHistory(start: dir("/a"))
        history.push(dir("/a/b"))
        history.push(dir("/a/b/c"))

        #expect(history.goBack()?.path == "/a/b")
        #expect(history.goBack()?.path == "/a")
        #expect(history.goBack() == nil)
        #expect(history.current.path == "/a")
        #expect(history.goForward()?.path == "/a/b")
        #expect(history.goForward()?.path == "/a/b/c")
        #expect(history.goForward() == nil)
        #expect(history.current.path == "/a/b/c")
    }

    @Test func pushAfterBackTruncatesTheForwardStack() {
        var history = NavigationHistory(start: dir("/a"))
        history.push(dir("/b"))
        history.push(dir("/c"))
        _ = history.goBack()
        #expect(history.canGoForward)

        history.push(dir("/d"))

        #expect(!history.canGoForward)
        #expect(history.goForward() == nil)
        #expect(history.goBack()?.path == "/b")
    }

    @Test func pushingTheCurrentFolderIsANoOp() {
        var history = NavigationHistory(start: dir("/a"))
        history.push(dir("/a/"))
        #expect(!history.canGoBack)
    }

    @Test func upGoesToTheParentAndBackReturns() {
        var history = NavigationHistory(start: dir("/Users/anshul/Code"))
        #expect(history.canGoUp)
        #expect(history.goUp()?.path == "/Users/anshul")
        #expect(history.goUp()?.path == "/Users")
        #expect(history.goUp()?.path == "/")
        #expect(history.goBack()?.path == "/Users")
        #expect(history.canGoForward)
    }

    @Test func upAtTheRootDoesNothing() {
        var history = NavigationHistory(start: dir("/"))
        #expect(!history.canGoUp)
        #expect(history.goUp() == nil)
        #expect(history.current.path == "/")
        #expect(!history.canGoBack)
    }

    @Test func backListIsNewestFirstAndForwardListIsNextFirst() {
        var history = NavigationHistory(start: dir("/a"))
        for path in ["/b", "/c", "/d"] { history.push(dir(path)) }
        #expect(history.backList.map(\.path) == ["/c", "/b", "/a"])
        #expect(history.forwardList.isEmpty)
        _ = history.goBack()
        #expect(history.backList.map(\.path) == ["/b", "/a"])
        #expect(history.forwardList.map(\.path) == ["/d"])
    }

    @Test func pickingFromTheBackListJumpsSeveralSteps() {
        var history = NavigationHistory(start: dir("/a"))
        for path in ["/b", "/c", "/d"] { history.push(dir(path)) }
        // The third entry of the right-click list on Back.
        #expect(history.goBack(steps: 3)?.path == "/a")
        #expect(history.backList.isEmpty)
        #expect(history.forwardList.map(\.path) == ["/b", "/c", "/d"])
        #expect(history.goForward(steps: 2)?.path == "/c")
        #expect(history.backList.map(\.path) == ["/b", "/a"])
        #expect(history.forwardList.map(\.path) == ["/d"])
    }

    @Test func stepsPastEitherEndDoNothing() {
        var history = NavigationHistory(start: dir("/a"))
        history.push(dir("/b"))
        #expect(history.goBack(steps: 2) == nil)
        #expect(history.goForward(steps: 1) == nil)
        #expect(history.goBack(steps: 0) == nil)
        #expect(history.current.path == "/b")
        #expect(history.backList.map(\.path) == ["/a"])
    }

    @Test func homeIsAPlaceInTheHistoryWithNoUp() {
        var h = NavigationHistory(start: URL(fileURLWithPath: "/tmp/a"))
        h.push(NavigationHistory.home)
        #expect(h.isHome)
        #expect(!h.canGoUp)
        #expect(h.goUp() == nil)
        h.push(NavigationHistory.home)
        #expect(h.backList.count == 1, "Home twice in a row is one step")
        #expect(h.goBack()?.path == "/tmp/a")
        #expect(!h.isHome)
        #expect(h.goForward().map(NavigationHistory.isHome) == true)
    }

    @Test func aSavedHistoryComesBackWithItsStacks() {
        let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b"), c = URL(fileURLWithPath: "/tmp/c")
        let h = NavigationHistory(current: b, back: [a], forward: [c])
        #expect(h.current.path == "/tmp/b")
        #expect(h.backStackURLs == [a])
        #expect(h.forwardStackURLs == [c])
        var moved = h
        #expect(moved.goForward()?.path == "/tmp/c")
    }
}
