import Foundation

/// What `ff` (or any other app) asks Folio to show, carried by a folio: URL:
/// `folio://open?path=<p>&cwd=<dir>&select=1&newWindow=1&newTab=1&search=<query>`.
/// `path` is as typed (it may be relative or start with ~); `cwd` is the folder `ff` ran in.
public struct FolioRequest: Equatable, Sendable {
    public static let scheme = "folio"
    public static let bundleID = "com.anshul.folio"

    public var path: String?
    public var cwd: String?
    /// Explorer's /select: show the item selected in its folder (a file always is).
    public var select: Bool
    public var newWindow: Bool
    public var newTab: Bool
    public var search: String?

    public init(path: String?, cwd: String? = nil, select: Bool = false, newWindow: Bool = false,
                newTab: Bool = false, search: String? = nil) {
        self.path = path
        self.cwd = cwd
        self.select = select
        self.newWindow = newWindow
        self.newTab = newTab
        self.search = search
    }

    // MARK: The URL

    /// Every value percent-encoded except letters, digits and `-._~/`, so `&`, `=`, `+`, `#`, `%` and
    /// spaces in a path or a query survive the trip.
    public var url: URL {
        var items: [(String, String)] = []
        if let path { items.append(("path", path)) }
        if let cwd { items.append(("cwd", cwd)) }
        if select { items.append(("select", "1")) }
        if newWindow { items.append(("newWindow", "1")) }
        if newTab { items.append(("newTab", "1")) }
        if let search { items.append(("search", search)) }
        let query = items.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(Self.scheme)://open" + (query.isEmpty ? "" : "?" + query))!
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Nil for anything but folio://open (or folio:open). Flags read 1, true or yes (or no value) as on.
    public static func parse(_ url: URL) -> FolioRequest? {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let command = (parts.host ?? parts.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard command == "open" else { return nil }
        var values: [String: String] = [:]
        // percentEncodedQueryItems, decoded here, so a + stays a plus.
        for item in parts.percentEncodedQueryItems ?? [] {
            values[item.name] = item.value.map { $0.removingPercentEncoding ?? $0 } ?? ""
        }
        func flag(_ name: String) -> Bool {
            guard let v = values[name]?.lowercased() else { return false }
            return v.isEmpty || v == "1" || v == "true" || v == "yes"
        }
        func text(_ name: String) -> String? {
            guard let v = values[name], !v.isEmpty else { return nil }
            return v
        }
        return FolioRequest(path: text("path"), cwd: text("cwd"), select: flag("select"), newWindow: flag("newWindow"),
                            newTab: flag("newTab"), search: text("search"))
    }

    // MARK: Paths

    /// The absolute path: ~ expanded, a relative path taken from `cwd` (or from / without one), . and ..
    /// worked out, no trailing slash. Nil when no path was given (Folio's start place).
    public var resolvedPath: String? { path.map { Self.resolve($0, cwd: cwd) } }

    public static func resolve(_ path: String, cwd: String?) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = (cwd ?? "/") + "/" + p }
        var out: [Substring] = []
        for part in p.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = out.popLast(); continue }
            out.append(part)
        }
        return "/" + out.joined(separator: "/")
    }

    // MARK: What the app shows

    public enum ItemKind: Sendable { case folder, file, missing }

    /// Where the result goes: the usual place (a tab already on that folder, else a new tab or a new
    /// window as Folder Options say), or the window or tab asked for.
    public enum Placement: Sendable, Equatable { case usual, newWindow, newTab }

    public struct Plan: Equatable, Sendable {
        /// The folder to show; nil is the start place (Home).
        public var folder: String?
        /// The item to select in it.
        public var select: String?
        public var search: String?
        public var placement: Placement

        public init(folder: String?, select: String?, search: String?, placement: Placement) {
            self.folder = folder
            self.select = select
            self.search = search
            self.placement = placement
        }
    }

    /// A folder shows itself; a file (or anything with `select`) shows its folder with it selected; a
    /// search runs in the folder (a file's folder). Nil when the path is not there.
    public func plan(kind: (String) -> ItemKind) -> Plan? {
        let placement: Placement = newWindow ? .newWindow : newTab ? .newTab : .usual
        guard let target = resolvedPath else {
            return Plan(folder: nil, select: nil, search: search, placement: placement)
        }
        let k = kind(target)
        guard k != .missing else { return nil }
        let parent = (target as NSString).deletingLastPathComponent
        if let search {
            return Plan(folder: k == .folder ? target : parent, select: nil, search: search, placement: placement)
        }
        if k == .folder && (!select || target == "/") {
            return Plan(folder: target, select: nil, search: nil, placement: placement)
        }
        return Plan(folder: parent, select: target, search: nil, placement: placement)
    }
}
