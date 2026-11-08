import Foundation

/// The suggestions the user chose to ignore: paths (a folder covers what is inside it) and duplicate
/// hashes. Newest first, at most `limit` of each, kept in the defaults.
public struct SuggestionIgnores {
    public static let pathsKey = "suggestionIgnoredPaths"
    public static let hashesKey = "suggestionIgnoredHashes"
    public static let limit = 5_000
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var paths: [String] { defaults.stringArray(forKey: Self.pathsKey) ?? [] }
    public var hashes: [String] { defaults.stringArray(forKey: Self.hashesKey) ?? [] }
    public var count: Int { paths.count + hashes.count }

    /// With an `item`, that item's path. Without one, a duplicate group by its hash and any other suggestion by its first item.
    public func ignore(_ suggestion: Suggestion, item: SuggestionItem? = nil) {
        if let item {
            ignore(path: item.id)
        } else if case .sameContent(_, let sha, _) = suggestion.reason {
            ignore(hash: sha)
        } else if let first = suggestion.items.first {
            ignore(path: first.id)
        }
    }

    public func ignore(path: String) { put(path, key: Self.pathsKey) }
    public func ignore(hash: String) { put(hash, key: Self.hashesKey) }
    public func unignore(path: String) { defaults.set(paths.filter { $0 != path }, forKey: Self.pathsKey) }
    public func unignore(hash: String) { defaults.set(hashes.filter { $0 != hash }, forKey: Self.hashesKey) }

    public func removeAll() {
        defaults.removeObject(forKey: Self.pathsKey)
        defaults.removeObject(forKey: Self.hashesKey)
    }

    private func put(_ value: String, key: String) {
        var list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != value }
        list.insert(value, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: key)
    }

    /// A copy for the scan, which runs off the main thread.
    public var snapshot: Snapshot { Snapshot(paths: Set(paths), hashes: Set(hashes)) }

    public struct Snapshot: Sendable, Equatable {
        public let paths: Set<String>
        public let hashes: Set<String>

        public init(paths: Set<String> = [], hashes: Set<String> = []) {
            self.paths = paths
            self.hashes = hashes
        }

        /// True for an ignored path and for anything inside an ignored folder. `a/b` does not cover `a/bc`.
        public func covers(_ key: String) -> Bool {
            guard !paths.isEmpty else { return false }
            if paths.contains(key) { return true }
            var rest = Substring(key)
            while let slash = rest.lastIndex(of: "/"), slash != rest.startIndex {
                rest = rest[..<slash]
                if paths.contains(String(rest)) { return true }
            }
            return false
        }

        public func coversHash(_ sha256: String) -> Bool { hashes.contains(sha256) }
    }
}
