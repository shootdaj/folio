import Foundation

/// A window's place on screen, in AppKit screen coordinates.
public struct SessionFrame: Codable, Equatable, Sendable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One tab as saved: its folder (or Home), its Back and Forward stacks and its sort.
public struct TabSession: Codable, Equatable, Sendable {
    public var path: String
    public var back: [String]
    public var forward: [String]
    public var sortKey: String
    public var ascending: Bool

    public init(_ tab: BrowserTab) {
        path = Self.text(tab.history.current)
        back = tab.history.backStackURLs.map(Self.text)
        forward = tab.history.forwardStackURLs.map(Self.text)
        sortKey = tab.sort.key.rawValue
        ascending = tab.sort.ascending
    }

    private static func text(_ url: URL) -> String {
        NavigationHistory.isHome(url) ? NavigationHistory.homePath : url.path
    }

    private static func url(_ text: String) -> URL {
        text == NavigationHistory.homePath ? NavigationHistory.home : URL(fileURLWithPath: text, isDirectory: true)
    }

    /// The tab back. A folder that is gone opens its nearest parent that still exists; Home is always there.
    public func tab(exists: (String) -> Bool) -> BrowserTab {
        var place = path
        if place != NavigationHistory.homePath {
            while place != "/" && !exists(place) { place = (place as NSString).deletingLastPathComponent }
            if place.isEmpty { place = "/" }
        }
        let sort = SortSpec(key: SortKey(rawValue: sortKey) ?? .name, ascending: ascending)
        let history = NavigationHistory(current: Self.url(place), back: back.map(Self.url),
                                        forward: place == path ? forward.map(Self.url) : [])
        return BrowserTab(history: history, sort: sort)
    }
}

public struct WindowSession: Codable, Equatable, Sendable {
    public var frame: SessionFrame
    public var tabs: [TabSession]
    public var active: Int

    public init(frame: SessionFrame, tabs: [TabSession], active: Int) {
        self.frame = frame
        self.tabs = tabs
        self.active = active
    }

    public var clampedActive: Int { tabs.isEmpty ? 0 : min(max(0, active), tabs.count - 1) }
}

/// Every open window, front to back.
public struct Session: Codable, Equatable, Sendable {
    public var windows: [WindowSession]

    public init(windows: [WindowSession]) {
        self.windows = windows
    }
}

/// Explorer's "Restore previous folder windows at logon": the windows and their tabs, saved as they
/// change and opened again at the next launch.
public struct SessionStore {
    public static let key = "session"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Nil when nothing was saved or the saved data cannot be read.
    public func load() -> Session? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
