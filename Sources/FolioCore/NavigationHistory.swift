import Foundation

/// Back/Forward/Up history for one tab, like Windows Explorer: Up is a normal step you can go Back from.
/// Home (`NavigationHistory.home`) is a place in the history like any folder, with no Up.
public struct NavigationHistory: Sendable, Equatable {
    /// Home, Explorer's start page: Quick access, Favorites and Recent instead of a folder.
    public static let home = URL(string: "folio:home")!
    public static let homePath = "folio:home"

    public private(set) var current: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    public init(start: URL) {
        current = Self.clean(start)
    }

    /// A history as it was saved: `back` oldest first, `forward` nearest last (as the stacks hold them).
    public init(current: URL, back: [URL], forward: [URL]) {
        self.current = Self.clean(current)
        backStack = back.map(Self.clean)
        forwardStack = forward.map(Self.clean)
    }

    /// The stacks as saved (see `init(current:back:forward:)`).
    public var backStackURLs: [URL] { backStack }
    public var forwardStackURLs: [URL] { forwardStack }

    public var isHome: Bool { Self.isHome(current) }
    public static func isHome(_ url: URL) -> Bool { url.scheme == "folio" }

    private static func clean(_ url: URL) -> URL { isHome(url) ? home : url.standardizedFileURL }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        isHome(a) || isHome(b) ? isHome(a) && isHome(b) : a.path == b.path
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var canGoUp: Bool { Self.parent(of: current) != nil }

    /// Goes to a new folder and drops the forward stack. Pushing the current folder does nothing.
    public mutating func push(_ url: URL) {
        let url = Self.clean(url)
        guard !Self.same(url, current) else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = url
    }

    public mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    public mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }

    /// What right-clicking Back lists: the previous folders, the most recent first.
    public var backList: [URL] { backStack.reversed() }

    /// What right-clicking Forward lists: the next folders, the nearest first.
    public var forwardList: [URL] { forwardStack.reversed() }

    /// Jumps to entry `steps - 1` of `backList`. Nil (and no change) past the end.
    public mutating func goBack(steps: Int) -> URL? {
        guard steps > 0, steps <= backStack.count else { return nil }
        for _ in 0..<steps { _ = goBack() }
        return current
    }

    /// Jumps to entry `steps - 1` of `forwardList`. Nil (and no change) past the end.
    public mutating func goForward(steps: Int) -> URL? {
        guard steps > 0, steps <= forwardStack.count else { return nil }
        for _ in 0..<steps { _ = goForward() }
        return current
    }

    public mutating func goUp() -> URL? {
        guard let parent = Self.parent(of: current) else { return nil }
        push(parent)
        return current
    }

    public static func parent(of url: URL) -> URL? {
        guard !isHome(url) else { return nil }
        let url = url.standardizedFileURL
        guard url.path != "/" else { return nil }
        return url.deletingLastPathComponent().standardizedFileURL
    }
}
