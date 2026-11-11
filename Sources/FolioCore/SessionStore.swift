import Foundation

/// A rectangle in AppKit screen coordinates: a window's frame, or a screen's.
public struct SessionFrame: Codable, Equatable, Sendable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func intersection(_ o: SessionFrame) -> Double {
        let w = min(maxX, o.maxX) - max(x, o.x), h = min(maxY, o.maxY) - max(y, o.y)
        return w > 0 && h > 0 ? w * h : 0
    }
}

/// The display a window was on: its name (NSScreen.localizedName) and frame when the window was saved.
public struct SessionDisplay: Codable, Equatable, Sendable {
    public var name: String
    public var frame: SessionFrame

    public init(name: String, frame: SessionFrame) {
        self.name = name
        self.frame = frame
    }
}

/// A search shown in a tab (its query, Current folder or All subfolders, This PC).
public struct SearchSession: Codable, Equatable, Sendable {
    public var text: String
    public var recursive: Bool
    public var everywhere: Bool

    public init(text: String, recursive: Bool, everywhere: Bool) {
        self.text = text
        self.recursive = recursive
        self.everywhere = everywhere
    }
}

/// One tab as saved: its folder (or Home), Back and Forward, sort and grouping, what was selected, the
/// first row in view, and a search it was showing. Fields after milestone 5 are optional so older
/// session files still read.
public struct TabSession: Codable, Equatable, Sendable {
    public var path: String
    public var back: [String]
    public var forward: [String]
    public var sortKey: String
    public var ascending: Bool
    /// Shift+click sort keys and Group by (milestone 6).
    public var thenKeys: [SortTerm]?
    public var group: GroupSpec?
    /// Milestone 9: the selected items (`FilePaths.itemKey`), the first row in view, the search shown.
    public var selection: [String]?
    public var scrollRow: Int?
    public var search: SearchSession?

    public init(_ tab: BrowserTab) {
        path = Self.text(tab.history.current)
        back = tab.history.backStackURLs.map(Self.text)
        forward = tab.history.forwardStackURLs.map(Self.text)
        sortKey = tab.sort.key.rawValue
        ascending = tab.sort.ascending
        thenKeys = tab.sort.then.isEmpty ? nil : tab.sort.then
        group = tab.group
        selection = tab.selection.isEmpty ? nil : tab.selection
        scrollRow = tab.scrollRow > 0 ? tab.scrollRow : nil
        search = tab.history.search.map { SearchSession(text: $0.text, recursive: $0.recursive, everywhere: $0.everywhere) }
    }

    private static func text(_ url: URL) -> String {
        NavigationHistory.isHome(url) ? NavigationHistory.homePath : url.path
    }

    private static func url(_ text: String) -> URL {
        text == NavigationHistory.homePath ? NavigationHistory.home : URL(fileURLWithPath: text, isDirectory: true)
    }

    /// The tab back. A folder that is gone opens its nearest parent that still exists (without its
    /// selection, scroll place, search or Forward list); Home is always there.
    public func tab(exists: (String) -> Bool) -> BrowserTab {
        var place = path
        if place != NavigationHistory.homePath {
            while place != "/" && !exists(place) { place = (place as NSString).deletingLastPathComponent }
            if place.isEmpty { place = "/" }
        }
        let same = place == path
        let sort = SortSpec(key: SortKey(rawValue: sortKey) ?? .name, ascending: ascending, then: thenKeys ?? [])
        var history = NavigationHistory(current: Self.url(place), back: back.map(Self.url),
                                        forward: same ? forward.map(Self.url) : [])
        if same, let s = search { history.updateSearch(HistorySearch(text: s.text, recursive: s.recursive, everywhere: s.everywhere)) }
        var tab = BrowserTab(history: history, sort: sort, selection: same ? selection ?? [] : [],
                             scrollRow: same ? scrollRow ?? 0 : 0)
        tab.group = group
        return tab
    }
}

public struct WindowSession: Codable, Equatable, Sendable {
    public var frame: SessionFrame
    /// The display the window was on (milestone 9).
    public var display: SessionDisplay?
    public var tabs: [TabSession]
    public var active: Int
    /// The navigation pane's open folders, top to bottom (milestone 9).
    public var expandedFolders: [String]?

    public init(frame: SessionFrame, display: SessionDisplay? = nil, tabs: [TabSession], active: Int,
                expandedFolders: [String]? = nil) {
        self.frame = frame
        self.display = display
        self.tabs = tabs
        self.active = active
        self.expandedFolders = expandedFolders
    }

    public var clampedActive: Int { tabs.isEmpty ? 0 : min(max(0, active), tabs.count - 1) }
}

/// Every open window, front to back, and the one view every folder shows.
public struct Session: Codable, Equatable, Sendable {
    public var windows: [WindowSession]
    /// `ViewMode.rawValue` (milestone 9): the view comes back with the windows.
    public var viewMode: String?

    public init(windows: [WindowSession], viewMode: String? = nil) {
        self.windows = windows
        self.viewMode = viewMode
    }
}

/// Explorer's "Restore previous folder windows at logon", always on unless Folder Options say no: the
/// windows and their tabs in ~/Library/Application Support/Folio/session.json, written (atomically) half
/// a second after each change and on quit, read at the next launch. A file that does not read is moved
/// aside as session.corrupt-<time>.json and the app starts fresh.
public struct SessionStore: Sendable {
    /// Changes within this long are written once.
    public static let coalesce: TimeInterval = 0.5

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Folio/session.json")
    }

    public enum Loaded: Equatable, Sendable {
        case none
        case session(Session)
        /// The file did not read; it is now at `movedTo` (nil if it could not be moved).
        case corrupt(movedTo: URL?)
    }

    public let url: URL

    public init(url: URL = SessionStore.defaultURL()) {
        self.url = url
    }

    /// Writes happen one at a time, in order, off the main thread (`saveInBackground`).
    private static let writer = DispatchQueue(label: "folio.session.write", qos: .utility)

    /// Encodes and writes the session off the main thread; a failure goes to `failed`.
    public func saveInBackground(_ session: Session, failed: @escaping @Sendable (Error) -> Void) {
        let store = self
        Self.writer.async {
            do { try store.save(session) } catch { failed(error) }
        }
    }

    /// Writes the session now, after any background write still in flight (quitting).
    public func saveNow(_ session: Session) throws {
        try Self.writer.sync { try save(session) }
    }

    public func save(_ session: Session) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(session)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func load(now: Date = Date()) -> Loaded {
        guard let data = FileManager.default.contents(atPath: url.path) else { return .none }
        if let session = try? JSONDecoder().decode(Session.self, from: data) { return .session(session) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        var aside = url.deletingLastPathComponent().appendingPathComponent("session.corrupt-\(f.string(from: now)).json")
        var n = 2
        while FileManager.default.fileExists(atPath: aside.path) {
            aside = url.deletingLastPathComponent().appendingPathComponent("session.corrupt-\(f.string(from: now))-\(n).json")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return .corrupt(movedTo: aside)
        } catch {
            return .corrupt(movedTo: nil)
        }
    }

    /// Removes the file (to the Trash when it can).
    public func clear() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Window frames per display

/// A screen as AppKit gives it: name, frame and the part windows may use (no menu bar or Dock).
public struct ScreenInfo: Equatable, Sendable {
    public var name: String
    public var frame: SessionFrame
    public var visible: SessionFrame

    public init(name: String, frame: SessionFrame, visible: SessionFrame) {
        self.name = name
        self.frame = frame
        self.visible = visible
    }
}

public enum WindowPlacement {
    /// Where a saved window goes. On the display it was on when that display is still there (found by
    /// name, then by frame), moved along if the arrangement moved it; otherwise on the screen it overlaps
    /// most, or centred on the main screen (the first) when it overlaps none. Never bigger than the
    /// screen's usable part.
    public static func place(_ frame: SessionFrame, display: SessionDisplay?, screens: [ScreenInfo]) -> SessionFrame {
        guard let main = screens.first else { return frame }
        var f = frame
        var target: ScreenInfo?
        if let display {
            target = screens.first { $0.name == display.name && $0.frame.width == display.frame.width && $0.frame.height == display.frame.height }
                ?? screens.first { $0.name == display.name }
                ?? screens.first { $0.frame == display.frame }
            if let t = target {
                f.x += t.frame.x - display.frame.x
                f.y += t.frame.y - display.frame.y
            }
        }
        if target == nil {
            target = screens.map { ($0, $0.visible.intersection(f)) }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
        }
        let screen = target ?? main
        let v = screen.visible
        if v.intersection(f) == 0 {
            f.width = min(f.width, v.width)
            f.height = min(f.height, v.height)
            return SessionFrame(x: v.x + (v.width - f.width) / 2, y: v.y + (v.height - f.height) / 2, width: f.width, height: f.height)
        }
        if f.width > v.width || f.height > v.height {
            f.width = min(f.width, v.width)
            f.height = min(f.height, v.height)
            f.x = max(v.x, min(f.x, v.maxX - f.width))
            f.y = max(v.y, min(f.y, v.maxY - f.height))
        }
        return f
    }
}
