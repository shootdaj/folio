import Foundation

/// One clickable segment of the address bar.
public struct Crumb: Sendable, Equatable {
    public let title: String
    /// The folder this crumb jumps to.
    public let path: String
    /// The last crumb, drawn in the accent.
    public let isCurrent: Bool

    public init(title: String, path: String, isCurrent: Bool) {
        self.title = title
        self.path = path
        self.isCurrent = isCurrent
    }
}

public enum Breadcrumbs {
    /// The startup disk, shown as the only crumb at `/`.
    public static let rootTitle = "Macintosh HD"

    /// `/Users/anshul/Code` gives Users, anshul, Code; each crumb holds the path up to itself.
    public static func crumbs(for url: URL) -> [Crumb] {
        let parts = components(of: url.path)
        guard !parts.isEmpty else { return [Crumb(title: rootTitle, path: "/", isCurrent: true)] }
        var prefix = ""
        return parts.enumerated().map { index, part in
            prefix += "/" + part
            return Crumb(title: part, path: prefix, isCurrent: index == parts.count - 1)
        }
    }

    /// The folder a row of crumbs stands for: the last crumb's path.
    public static func path(of crumbs: [Crumb]) -> String {
        crumbs.last?.path ?? "/"
    }

    /// What the editable path field means: `~` is home, a relative path starts at the current folder.
    /// Returns nil for an empty field. Whether the folder exists is checked by the caller.
    public static func resolve(typed text: String, current: URL, home: URL) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url: URL
        if trimmed == "~" {
            url = home
        } else if trimmed.hasPrefix("~/") {
            url = home.appendingPathComponent(String(trimmed.dropFirst(2)))
        } else if trimmed.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmed)
        } else {
            url = current.appendingPathComponent(trimmed)
        }
        return URL(fileURLWithPath: "/" + components(of: url.path).joined(separator: "/"), isDirectory: true)
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
}
