import Foundation

/// One tab of a window: its own Back and Forward history, sort, grouping, selection and scroll place.
/// The sort and grouping stay as the tab moves between folders (no folder keeps a view of its own).
public struct BrowserTab: Sendable, Equatable {
    public let id: UUID
    public var history: NavigationHistory
    public var sort: SortSpec
    /// Group by; nil is (None).
    public var group: GroupSpec?
    /// The selected items (`FilePaths.itemKey`), put back when the tab is shown again.
    public var selection: [String]
    /// The first row in view when the tab was left.
    public var scrollRow: Int

    public init(folder: URL, sort: SortSpec = .standard, id: UUID = UUID()) {
        self.init(history: NavigationHistory(start: folder), sort: sort, id: id)
    }

    public init(history: NavigationHistory, sort: SortSpec = .standard, selection: [String] = [],
                scrollRow: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.history = history
        self.sort = sort
        self.selection = selection
        self.scrollRow = scrollRow
    }

    public var current: URL { history.current }

    /// Duplicate tab: the same place, history, sort and grouping under a new identity.
    public func duplicated() -> BrowserTab {
        var copy = BrowserTab(history: history, sort: sort, selection: selection, scrollRow: scrollRow)
        copy.group = group
        return copy
    }
}

/// The tabs of one window, left to right, and which one is shown. Closing the last tab is the
/// window's job (`close(at:)` refuses it); moving a tab to another window may empty the list, and
/// the window then closes.
public struct TabList: Sendable {
    public private(set) var tabs: [BrowserTab]
    public private(set) var activeIndex: Int
    /// Background tabs opened from the active tab since it became active: the next one goes after them.
    private var backgroundRun = 0

    public init(_ tabs: [BrowserTab], active: Int = 0) {
        precondition(!tabs.isEmpty, "a window has at least one tab")
        self.tabs = tabs
        activeIndex = min(max(0, active), tabs.count - 1)
    }

    public var count: Int { tabs.count }
    public var isEmpty: Bool { tabs.isEmpty }

    public var active: BrowserTab {
        get { tabs[activeIndex] }
        set { tabs[activeIndex] = newValue }
    }

    public func index(of id: UUID) -> Int? { tabs.firstIndex { $0.id == id } }

    /// Changes a tab in place without showing it (a background tab whose drive went away).
    public mutating func modify(at index: Int, _ body: (inout BrowserTab) -> Void) {
        guard tabs.indices.contains(index) else { return }
        body(&tabs[index])
    }

    public mutating func select(_ index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        activeIndex = index
        backgroundRun = 0
    }

    /// Cmd+T: a new tab at the end, shown.
    @discardableResult
    public mutating func append(_ tab: BrowserTab) -> Int {
        tabs.append(tab)
        select(tabs.count - 1)
        return tabs.count - 1
    }

    /// Open in new tab and middle-click: right of the active tab, after the background tabs already
    /// opened from it, so several open in the order they were clicked.
    @discardableResult
    public mutating func openNext(_ tab: BrowserTab, activate: Bool) -> Int {
        let at = min(tabs.count, activeIndex + 1 + backgroundRun)
        tabs.insert(tab, at: at)
        if activate {
            activeIndex = at
            backgroundRun = 0
        } else {
            backgroundRun += 1
        }
        return at
    }

    /// Cmd+1 to Cmd+8: that tab. Cmd+9: the last one. False when there is no such tab.
    @discardableResult
    public mutating func selectNumber(_ n: Int) -> Bool {
        let index = n == 9 ? tabs.count - 1 : n - 1
        guard tabs.indices.contains(index) else { return false }
        select(index)
        return true
    }

    /// Ctrl+Tab and Ctrl+Shift+Tab, wrapping at either end.
    public mutating func cycle(forward: Bool) {
        guard tabs.count > 1 else { return }
        select((activeIndex + (forward ? 1 : tabs.count - 1)) % tabs.count)
    }

    /// Closes one tab. Nil (and nothing closed) when it is the only tab: the window closes instead.
    /// The active tab hands over to its right neighbour, or the left one when it was last.
    public mutating func close(at index: Int) -> BrowserTab? {
        guard tabs.count > 1, tabs.indices.contains(index) else { return nil }
        return take(at: index)
    }

    /// Close other tabs: everything but `index`, which becomes active. Returns the closed tabs.
    public mutating func closeOthers(keeping index: Int) -> [BrowserTab] {
        guard tabs.indices.contains(index) else { return [] }
        let keep = tabs[index]
        let closed = tabs.enumerated().filter { $0.offset != index }.map(\.element)
        tabs = [keep]
        activeIndex = 0
        backgroundRun = 0
        return closed
    }

    /// Close tabs to the right of `index`. When the active tab was among them, `index` takes over.
    public mutating func closeToTheRight(of index: Int) -> [BrowserTab] {
        guard tabs.indices.contains(index), index < tabs.count - 1 else { return [] }
        let closed = Array(tabs[(index + 1)...])
        tabs.removeSubrange((index + 1)...)
        if activeIndex > index { activeIndex = index; backgroundRun = 0 }
        return closed
    }

    /// Duplicate tab: a copy right after it, shown. Returns its index.
    @discardableResult
    public mutating func duplicate(at index: Int) -> Int {
        guard tabs.indices.contains(index) else { return activeIndex }
        tabs.insert(tabs[index].duplicated(), at: index + 1)
        activeIndex = index + 1
        backgroundRun = 0
        return index + 1
    }

    /// Drag to reorder: the tab at `from` ends up at index `to` (clamped to the strip).
    public mutating func move(from: Int, to: Int) {
        guard tabs.indices.contains(from) else { return }
        let id = tabs[activeIndex].id
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: min(max(0, to), tabs.count))
        activeIndex = index(of: id) ?? 0
    }

    /// Tear out, merge, Move to new window: takes the tab out, even the last one (the list is then
    /// empty and its window closes).
    public mutating func remove(id: UUID) -> BrowserTab? {
        guard let i = index(of: id) else { return nil }
        return take(at: i)
    }

    /// A tab arriving from another window (or reopened): at `index`, shown when `activate`.
    public mutating func insert(_ tab: BrowserTab, at index: Int, activate: Bool) {
        let at = min(max(0, index), tabs.count)
        let activeID = tabs.isEmpty ? nil : tabs[activeIndex].id
        tabs.insert(tab, at: at)
        if activate || activeID == nil {
            activeIndex = at
        } else if let activeID {
            activeIndex = self.index(of: activeID) ?? at
        }
        backgroundRun = 0
    }

    private mutating func take(at index: Int) -> BrowserTab {
        let wasActive = index == activeIndex
        let tab = tabs.remove(at: index)
        if tabs.isEmpty {
            activeIndex = 0
        } else if wasActive {
            activeIndex = min(index, tabs.count - 1)
            backgroundRun = 0
        } else if index < activeIndex {
            activeIndex -= 1
        }
        return tab
    }
}

/// Cmd+Shift+T: the tabs closed most recently, with where they were.
public struct ClosedTabs: Sendable {
    public struct Entry: Sendable, Equatable {
        public let tab: BrowserTab
        public let index: Int
    }

    public static let limit = 25
    private var entries: [Entry] = []

    public init() {}

    public var count: Int { entries.count }

    public mutating func push(_ tab: BrowserTab, index: Int) {
        entries.append(Entry(tab: tab, index: index))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    public mutating func pop() -> Entry? { entries.popLast() }
}
