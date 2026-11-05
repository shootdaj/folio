import Foundation

/// The sidebar's Quick access pins, in order, saved under `quickAccessPins`. Until anything is pinned
/// or unpinned it holds D1's favourites. Drop a folder on the group to pin it at that place, drag a pin
/// to reorder, Unpin from its menu.
public struct PinStore {
    public static let key = "quickAccessPins"
    private let defaults: UserDefaults
    private let home: URL

    public init(defaults: UserDefaults, home: URL) {
        self.defaults = defaults
        self.home = home
    }

    public var paths: [String] {
        if let saved = defaults.array(forKey: Self.key) as? [String] { return saved }
        return QuickAccess.places(home: home).map(\.path)
    }

    public func isPinned(_ path: String) -> Bool { paths.contains(Self.clean(path)) }

    /// Pins at `index` (an insertion place, 0 is the top), or at the end. A pinned folder moves there.
    public mutating func pin(_ path: String, at index: Int? = nil) {
        let p = Self.clean(path)
        var list = paths
        var place = min(max(0, index ?? list.count), list.count)
        if let old = list.firstIndex(of: p) {
            list.remove(at: old)
            if old < place { place -= 1 }
        }
        list.insert(p, at: min(place, list.count))
        save(list)
    }

    public mutating func unpin(_ path: String) {
        let p = Self.clean(path)
        save(paths.filter { $0 != p })
    }

    /// Drag to reorder: the pin at `from` goes to the insertion place `to` (0...count, before removal).
    public mutating func move(from: Int, to: Int) {
        var list = paths
        guard list.indices.contains(from) else { return }
        let item = list.remove(at: from)
        let place = to > from ? to - 1 : to
        list.insert(item, at: min(max(0, place), list.count))
        save(list)
    }

    public mutating func replace(with list: [String]) { save(list.map(Self.clean)) }

    /// What the sidebar draws: the folder name bright and, inside home, its parent dim ("Anshul/");
    /// outside home the parent folder's name.
    public var places: [QuickAccessPlace] {
        let base = Self.clean(home.path)
        return paths.map { path in
            if path == "/" { return QuickAccessPlace(title: "/", prefix: "", path: path) }
            let url = URL(fileURLWithPath: path)
            let title = url.lastPathComponent
            let parent = url.deletingLastPathComponent().path
            let prefix: String
            if path.hasPrefix(base + "/") {
                let relative = String(path.dropFirst(base.count + 1))
                prefix = relative.contains("/") ? (relative as NSString).deletingLastPathComponent + "/" : ""
            } else {
                prefix = parent == "/" ? "" : (parent as NSString).lastPathComponent + "/"
            }
            return QuickAccessPlace(title: title, prefix: prefix, path: path)
        }
    }

    private func save(_ list: [String]) { defaults.set(list, forKey: Self.key) }

    static func clean(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
