import Foundation

/// One folder inside another, as the typeahead and the crumb dropdowns list them.
public struct Subfolder: Sendable, Equatable {
    public let name: String
    /// A dot name or the hidden flag (`/private`, `~/Library`).
    public let isHidden: Bool
}

/// One row of the typeahead: the full path, with its first `boldLength` characters typed so far.
public struct CompletionRow: Sendable, Equatable {
    public let path: String
    public let boldLength: Int
}

/// What the address bar's typeahead shows for the text typed so far.
public struct Completion: Sendable, Equatable {
    /// The folder whose subfolders are matched (the path typed up to its last slash).
    public let directory: URL
    /// The last segment, which names must start with.
    public let prefix: String
    /// The matches shown, at most `PathCompleter.limit`.
    public let names: [String]
    /// Every match, for the "8 of 23" count.
    public let total: Int

    public init(directory: URL, prefix: String, names: [String], total: Int) {
        self.directory = directory
        self.prefix = prefix
        self.names = names
        self.total = total
    }

    private var base: String { directory.path == "/" ? "" : directory.path }

    public var rows: [CompletionRow] {
        names.map { CompletionRow(path: base + "/" + $0, boldLength: base.count + 1 + min(prefix.count, $0.count)) }
    }

    /// Tab: the chosen match (the first when none is highlighted) as a full path ending in a slash.
    public func filled(_ index: Int?) -> String? {
        let i = index ?? 0
        guard names.indices.contains(i) else { return nil }
        return base + "/" + names[i] + "/"
    }
}

/// The typeahead matcher: folders inside the path typed so far whose names start with the last
/// segment, case-insensitive, in natural order, at most 8.
public enum PathCompleter {
    public static let limit = 8

    /// Splits the text at its last slash: the folder to list and the start of the name.
    /// `~`, variables and quotes are expanded first; relative text starts at `current`.
    public static func query(_ text: String, current: URL, env: AddressEnvironment) -> (directory: URL, prefix: String)? {
        guard let expanded = AddressInput.expand(text, env: env) else { return nil }
        let slash = expanded.lastIndex(of: "/")
        let head = slash.map { String(expanded[...$0]) } ?? ""
        let prefix = slash.map { String(expanded[expanded.index(after: $0)...]) } ?? expanded
        let dirText = head.isEmpty ? "." : head
        guard let directory = AddressInput.resolve(dirText, current: current, env: env) else { return nil }
        return (directory, prefix)
    }

    /// Every folder inside `directory` in natural order: real folders and symlinks to folders, never
    /// files or packages. Hidden ones are included and marked.
    public static func subfolders(in directory: URL) -> [Subfolder] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []) else { return [] }
        var out: [Subfolder] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            var isDirectory = values.isDirectory ?? false
            var isPackage = values.isPackage ?? false
            if values.isSymbolicLink == true {
                let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                isDirectory = target?.isDirectory ?? false
                isPackage = target?.isPackage ?? false
            }
            guard isDirectory && !isPackage else { continue }
            let name = url.lastPathComponent
            out.append(Subfolder(name: name, isHidden: (values.isHidden ?? false) || name.hasPrefix(".")))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The names that start with `prefix`, ignoring case. Dot folders only show for a dot prefix;
    /// folders hidden by flag (`/private`, `~/Library`) show, since people type them.
    public static func matches(_ folders: [Subfolder], prefix: String, limit: Int = PathCompleter.limit) -> (shown: [String], total: Int) {
        let dot = prefix.hasPrefix(".")
        let all = folders.filter { folder in
            guard dot || !folder.name.hasPrefix(".") else { return false }
            return prefix.isEmpty || folder.name.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
        }.map(\.name)
        return (Array(all.prefix(limit)), all.count)
    }

    /// Lists the folder from disk and matches in one go.
    public static func complete(_ text: String, current: URL, env: AddressEnvironment) -> Completion {
        guard let (directory, prefix) = query(text, current: current, env: env) else {
            return Completion(directory: current, prefix: "", names: [], total: 0)
        }
        let (shown, total) = matches(subfolders(in: directory), prefix: prefix)
        return Completion(directory: directory, prefix: prefix, names: shown, total: total)
    }
}
