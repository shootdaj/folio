import Foundation

/// One clickable segment of the address bar.
public struct Crumb: Sendable, Equatable {
    public let title: String
    /// The folder this crumb jumps to.
    public let path: String
    /// The last crumb, drawn in the accent.
    public let isCurrent: Bool
    /// The first crumb: the volume the path is on, shown by its name.
    public let isVolume: Bool

    public init(title: String, path: String, isCurrent: Bool, isVolume: Bool = false) {
        self.title = title
        self.path = path
        self.isCurrent = isCurrent
        self.isVolume = isVolume
    }
}

public enum Breadcrumbs {
    /// The startup disk's name when the real one is not known yet.
    public static let rootTitle = "Macintosh HD"

    /// `/Users/anshul/Code` gives Macintosh HD, Users, anshul, Code: the volume first, then one crumb
    /// per folder, each holding the path up to itself. A path under a mounted volume starts at that
    /// volume (`/Volumes/FolioScratch/a` gives FolioScratch, a).
    public static func crumbs(for url: URL, volumes: [VolumeCapacity] = []) -> [Crumb] {
        let parts = components(of: url.path)
        let path = "/" + parts.joined(separator: "/")
        // The deepest mount point that holds the path; "/" when none does.
        let volume = volumes
            .filter { $0.path != "/" && (path == $0.path || path.hasPrefix($0.path + "/")) }
            .max { $0.path.count < $1.path.count }
        let rootPath = volume?.path ?? "/"
        let rootName = volume?.name ?? volumes.first { $0.path == "/" }?.name ?? rootTitle
        let rootDepth = components(of: rootPath).count
        var out = [Crumb(title: rootName, path: rootPath, isCurrent: parts.count == rootDepth, isVolume: true)]
        var prefix = rootPath == "/" ? "" : rootPath
        for (index, part) in parts.enumerated() where index >= rootDepth {
            prefix += "/" + part
            out.append(Crumb(title: part, path: prefix, isCurrent: index == parts.count - 1))
        }
        return out
    }

    /// The folder a row of crumbs stands for: the last crumb's path.
    public static func path(of crumbs: [Crumb]) -> String {
        crumbs.last?.path ?? "/"
    }

    /// What the editable path field means: `~` is home, a relative path starts at the current folder.
    /// Returns nil for an empty field. Whether the folder exists is checked by the caller.
    public static func resolve(typed text: String, current: URL, home: URL) -> URL? {
        var env = AddressEnvironment.current
        env.home = home
        return AddressInput.resolve(text, current: current, env: env)
    }

    /// The path's folder names with `.` and `..` worked out on the text alone. Unlike
    /// `standardizedFileURL` it keeps `/private/tmp` as typed instead of turning it into `/tmp`.
    public static func components(of path: String) -> [String] {
        var out: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !out.isEmpty { out.removeLast() }
            default: out.append(String(part))
            }
        }
        return out
    }

    /// The path as one clean string: `/private//tmp/./x/` is `/private/tmp/x`.
    public static func normalized(_ path: String) -> String {
        "/" + components(of: path).joined(separator: "/")
    }
}

/// Crumbs that do not fit collapse from the left behind a « button, as in Explorer.
public enum CrumbFit {
    /// The index of the first crumb still shown. `widths` are each crumb with its arrow, left to right.
    /// When they do not all fit in `available`, the « button (`overflowWidth`) takes its share and
    /// crumbs drop from the left until the rest fit; the current (last) crumb always stays.
    public static func firstVisible(widths: [Double], available: Double, overflowWidth: Double) -> Int {
        guard widths.count > 1, widths.reduce(0, +) > available else { return 0 }
        let room = available - overflowWidth
        var used = 0.0
        var first = widths.count
        for i in widths.indices.reversed() {
            if first < widths.count && used + widths[i] > room { break }
            used += widths[i]
            first = i
        }
        return max(1, first)
    }
}

/// One folder in a crumb's dropdown.
public struct FolderMenuItem: Sendable, Equatable {
    public let name: String
    public let path: String
    /// The folder the window is in, or on the way to it: drawn marked.
    public let isOnPath: Bool

    public init(name: String, path: String, isOnPath: Bool) {
        self.name = name
        self.path = path
        self.isOnPath = isOnPath
    }
}

public enum FolderMenu {
    /// The folders inside `folder` (the crumb whose arrow was clicked), in natural order, with the one
    /// that leads to `current` marked. Files, packages and hidden folders are left out, except a hidden
    /// folder on the current path.
    public static func items(in folder: URL, current: URL) -> [FolderMenuItem] {
        let base = Breadcrumbs.normalized(folder.path)
        let here = Breadcrumbs.components(of: current.path)
        let depth = Breadcrumbs.components(of: base).count
        let onPath: String? = here.count > depth && Breadcrumbs.normalized(here.prefix(depth).joined(separator: "/")) == base
            ? here[depth] : nil
        let parent = base == "/" ? "" : base
        return PathCompleter.subfolders(in: folder)
            .filter { !$0.isHidden || $0.name == onPath }
            .map { FolderMenuItem(name: $0.name, path: parent + "/" + $0.name, isOnPath: $0.name == onPath) }
    }
}
