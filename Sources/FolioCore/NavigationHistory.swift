import Foundation

/// A search shown at a place in the history: Back from a result's folder returns to the results with the
/// query restored, as Explorer keeps a search-ms location in the tab's history.
public struct HistorySearch: Sendable, Equatable {
    public var text: String
    /// All subfolders, or Current folder only.
    public var recursive: Bool
    /// Search again in This PC: the whole Mac, from the startup disk.
    public var everywhere: Bool

    public init(text: String, recursive: Bool = true, everywhere: Bool = false) {
        self.text = text
        self.recursive = recursive
        self.everywhere = everywhere
    }
}

/// A place that is not a folder: Home or Suggestions. Each has a `folio:` address.
public enum SpecialPlace: String, Sendable, CaseIterable {
    case home, suggestions

    public var path: String { "folio:" + rawValue }
    public var url: URL { URL(string: path)! }

    /// An exact match gives its place. Other `folio:` text (from a newer build) gives Home. Anything else is nil.
    public init?(path: String) {
        if let exact = Self.allCases.first(where: { $0.path == path }) {
            self = exact
        } else if path.hasPrefix("folio:") {
            self = .home
        } else {
            return nil
        }
    }
}

/// Back/Forward/Up history for one tab, like Windows Explorer: Up is a normal step you can go Back from.
/// Home (`NavigationHistory.home`) is a place in the history like any folder, with no Up.
public struct NavigationHistory: Sendable, Equatable {
    /// Home, Explorer's start page: Quick access, Favorites and Recent instead of a folder.
    public static let home = URL(string: "folio:home")!
    public static let homePath = "folio:home"
    /// Suggestions, the page of things to clean up.
    public static let suggestions = SpecialPlace.suggestions.url
    public static let suggestionsPath = SpecialPlace.suggestions.path

    public private(set) var current: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    /// The search shown at `current`, nil for the plain folder.
    public private(set) var search: HistorySearch?
    private var backSearches: [HistorySearch?] = []
    private var forwardSearches: [HistorySearch?] = []

    public init(start: URL) {
        current = Self.clean(start)
    }

    /// A history as it was saved: `back` oldest first, `forward` nearest last (as the stacks hold them).
    public init(current: URL, back: [URL], forward: [URL]) {
        self.current = Self.clean(current)
        backStack = back.map(Self.clean)
        forwardStack = forward.map(Self.clean)
        backSearches = back.map { _ in nil }
        forwardSearches = forward.map { _ in nil }
    }

    /// The stacks as saved (see `init(current:back:forward:)`).
    public var backStackURLs: [URL] { backStack }
    public var forwardStackURLs: [URL] { forwardStack }

    /// The special place shown, or nil for a folder.
    public static func special(_ url: URL) -> SpecialPlace? {
        url.scheme == "folio" ? SpecialPlace(path: url.absoluteString) ?? .home : nil
    }

    public var special: SpecialPlace? { Self.special(current) }
    public var isSpecial: Bool { special != nil }
    public var isHome: Bool { special == .home }
    public var isSuggestions: Bool { special == .suggestions }

    /// Exactly Home.
    public static func isHome(_ url: URL) -> Bool { special(url) == .home }
    /// Any special place (Home or Suggestions).
    public static func isSpecial(_ url: URL) -> Bool { special(url) != nil }
    public static func isSuggestions(_ url: URL) -> Bool { special(url) == .suggestions }

    private static func clean(_ url: URL) -> URL { special(url)?.url ?? url.standardizedFileURL }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        let (x, y) = (special(a), special(b))
        return x != nil || y != nil ? x == y : a.path == b.path
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var canGoUp: Bool { Self.parent(of: current) != nil }

    /// Goes to a new folder (or a search in one) and drops the forward stack. Pushing the place shown
    /// does nothing.
    public mutating func push(_ url: URL, search: HistorySearch? = nil) {
        let url = Self.clean(url)
        guard !Self.same(url, current) || search != self.search else { return }
        backStack.append(current)
        backSearches.append(self.search)
        forwardStack.removeAll()
        forwardSearches.removeAll()
        current = url
        self.search = search
    }

    /// Typing on in the box: the search shown here changes in place (no new step per keystroke).
    public mutating func updateSearch(_ search: HistorySearch) {
        self.search = search
    }

    /// Esc or an empty box: back to the plain folder. When the step before is that folder, the search
    /// step goes away; otherwise the search is dropped from this step.
    public mutating func closeSearch() {
        guard search != nil else { return }
        if let previous = backStack.last, Self.same(previous, current), backSearches.last == .some(nil) {
            backStack.removeLast()
            backSearches.removeLast()
        }
        search = nil
    }

    public mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        forwardSearches.append(search)
        current = previous
        search = backSearches.popLast() ?? nil
        return current
    }

    public mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        backSearches.append(search)
        current = next
        search = forwardSearches.popLast() ?? nil
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
        guard !isSpecial(url) else { return nil }
        let url = url.standardizedFileURL
        guard url.path != "/" else { return nil }
        return url.deletingLastPathComponent().standardizedFileURL
    }
}
