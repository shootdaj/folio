import Darwin
import Foundation

/// Explorer's shortcuts on a Mac: a Finder alias (the default, it follows its target through renames
/// and moves) or a symbolic link (a plain path, what Terminal tools understand).
public enum LinkKind: String, Sendable, Equatable {
    case alias, symlink

    var suffix: String { self == .alias ? "alias" : "symlink" }
}

/// One link Folio made, enough to undo (trash it) and redo (make it again at the same place).
public struct LinkItem: Sendable, Equatable {
    public let url: URL
    public let target: URL
    public let kind: LinkKind

    public init(url: URL, target: URL, kind: LinkKind) {
        self.url = url
        self.target = target
        self.kind = kind
    }
}

public enum Aliases {
    /// Finder's names: "notes.txt alias", then "notes.txt alias 2"; symlinks end in "symlink".
    public static func name(for targetName: String, kind: LinkKind, taken: (String) -> Bool) -> String {
        let base = targetName + " " + kind.suffix
        if !taken(base) { return base }
        var n = 2
        while taken(base + " \(n)") { n += 1 }
        return base + " \(n)"
    }

    /// Makes a link to `target` in `folder` under the next free name.
    @discardableResult
    public static func make(_ kind: LinkKind, to target: URL, in folder: URL) throws -> URL {
        try makeItem(kind, to: target, in: folder).url
    }

    public static func makeItem(_ kind: LinkKind, to target: URL, in folder: URL) throws -> LinkItem {
        let name = name(for: target.lastPathComponent, kind: kind) { FileJob.kind(folder.appendingPathComponent($0)) != .missing }
        let url = folder.appendingPathComponent(name)
        try write(kind, to: target, at: url)
        return LinkItem(url: url, target: target, kind: kind)
    }

    /// Writes the link at exactly `url` (redo puts it back where it was).
    public static func write(_ kind: LinkKind, to target: URL, at url: URL) throws {
        guard FileJob.kind(url) == .missing else { throw FileOpError.exists(url.lastPathComponent) }
        switch kind {
        case .alias:
            let data = try target.bookmarkData(options: .suitableForBookmarkFile,
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(data, to: url)
        case .symlink:
            if symlink(target.path, url.path) != 0 { throw FileOpError.posix(errno, url) }
        }
    }

    /// `.alias` for a Finder alias file, `.symlink` for a symbolic link, nil for anything else.
    public static func kind(of url: URL) -> LinkKind? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true ? .alias : nil
    }

    /// Where the link points, if that still exists.
    public static func resolve(_ url: URL) -> URL? {
        switch kind(of: url) {
        case .alias:
            guard let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) else { return nil }
            return FileJob.kind(target) == .missing ? nil : target
        case .symlink:
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return nil }
            let target = dest.hasPrefix("/") ? URL(fileURLWithPath: dest)
                : url.deletingLastPathComponent().appendingPathComponent(dest)
            var st = stat()
            return stat(target.path, &st) == 0 ? target.standardizedFileURL : nil
        case nil:
            return nil
        }
    }
}
