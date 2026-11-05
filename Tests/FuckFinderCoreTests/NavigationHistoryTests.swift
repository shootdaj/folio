import Foundation
import Testing
@testable import FuckFinderCore

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
}
