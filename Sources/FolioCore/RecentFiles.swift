import Foundation

/// Home's Recent files: the last 30 files opened through Folio, newest first, kept in the defaults.
/// The app also tells NSDocumentController, and `merged` adds the system's recent documents after
/// Folio's own.
public struct RecentFiles {
    public static let key = "recentFiles"
    public static let limit = 30
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var paths: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    /// Puts the file at the top; one opened before moves up instead of showing twice.
    public func record(_ path: String) {
        var list = paths.filter { $0 != path }
        list.insert(path, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }

    public func remove(_ path: String) {
        defaults.set(paths.filter { $0 != path }, forKey: Self.key)
    }

    /// Folio's log first, then the system's recent documents it does not have, at most `limit`.
    public static func merged(own: [String], system: [String], limit: Int = RecentFiles.limit) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for path in own + system where seen.insert(path).inserted {
            out.append(path)
            if out.count == limit { break }
        }
        return out
    }
}

/// Home's Favorites: files and folders starred with Add to Favorites, newest first.
public struct FavoritesStore {
    public static let key = "favorites"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var paths: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func contains(_ path: String) -> Bool { paths.contains(path) }

    /// Adds at the top; a favourite already there stays where it is.
    public mutating func add(_ path: String) {
        guard !contains(path) else { return }
        defaults.set([path] + paths, forKey: Self.key)
    }

    public mutating func remove(_ path: String) {
        defaults.set(paths.filter { $0 != path }, forKey: Self.key)
    }

    public mutating func toggle(_ path: String) {
        if contains(path) { remove(path) } else { add(path) }
    }
}
