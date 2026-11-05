import Darwin
import Foundation

/// What a drop does to the dragged items.
public enum DropAction: String, Sendable, Equatable {
    case move, copy, alias
    /// Onto an app: open the files with it.
    case open
    /// Control held or the right button: the Move here / Copy here / Create alias here menu.
    case ask
    /// Refused: into itself, into its own subfolder, or a move to where the items already are.
    case none
}

/// Modifier keys held at the drop, as macOS reports them.
public struct DropKeys: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let option = DropKeys(rawValue: 1)
    public static let command = DropKeys(rawValue: 2)
    public static let control = DropKeys(rawValue: 4)
}

/// What the drag source allows (a browser or Mail usually offers copies only).
public struct DropAllowed: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let move = DropAllowed(rawValue: 1)
    public static let copy = DropAllowed(rawValue: 2)
    public static let link = DropAllowed(rawValue: 4)
    public static let all: DropAllowed = [.move, .copy, .link]
}

public enum Volumes {
    /// True when both items are on one volume. The destination is followed if it is a link to a folder;
    /// the source is not (a dragged link moves as the link).
    public static func same(_ source: URL, _ destination: URL) -> Bool {
        var s = stat(), d = stat()
        guard lstat(source.path, &s) == 0, stat(destination.path, &d) == 0 else { return false }
        return s.st_dev == d.st_dev
    }
}

/// Explorer's drop rules with the Mac's keys (docs/plan/MILESTONES.md, milestone 4): the same volume
/// moves and another volume copies; Option copies, Cmd moves, Cmd+Option makes an alias; Control or
/// the right button asks with a menu; dropping on an app opens the files with it.
public enum DropRules {
    public static func action(dropping sources: [URL], onto destination: URL, keys: DropKeys = [],
                              rightButton: Bool = false, allowed: DropAllowed = .all,
                              sameVolume: (URL, URL) -> Bool = Volumes.same) -> DropAction {
        guard !sources.isEmpty else { return .none }
        let destKey = FilePaths.folderKey(destination)
        if sources.contains(where: { FilePaths.folderKey($0) == destKey }) { return .none }
        if isApp(destination) { return .open }
        if keys.contains(.control) || rightButton { return .ask }
        var action: DropAction
        if keys.contains(.command) && keys.contains(.option) {
            action = .alias
        } else if keys.contains(.option) {
            action = .copy
        } else if keys.contains(.command) {
            action = .move
        } else {
            action = plainAction(dropping: sources, onto: destination, sameVolume: sameVolume)
        }
        // What the source forbids falls back to what it allows.
        switch action {
        case .move where !allowed.contains(.move): action = allowed.contains(.copy) ? .copy : .none
        case .copy where !allowed.contains(.copy): action = allowed.contains(.move) ? .move : .none
        case .alias where !allowed.contains(.link): action = .none
        default: break
        }
        switch action {
        case .move, .copy:
            if sources.contains(where: { inside($0, destKey) }) { return .none }
            if action == .move && !canMove(sources, into: destination) { return .none }
        default: break
        }
        return action
    }

    /// What a drop with no keys does; the ask menu shows it as its default item.
    public static func plainAction(dropping sources: [URL], onto destination: URL,
                                   sameVolume: (URL, URL) -> Bool = Volumes.same) -> DropAction {
        sources.allSatisfy { sameVolume($0, destination) } ? .move : .copy
    }

    /// A move is a no-op when every item already sits in the destination.
    public static func canMove(_ sources: [URL], into destination: URL) -> Bool {
        let key = FilePaths.folderKey(destination)
        return !sources.allSatisfy { FilePaths.folderKey($0.deletingLastPathComponent()) == key }
    }

    public static func isApp(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    /// Explorer's drag tooltip: "Move to target", "Copy to target", "Create link in target".
    public static func badge(_ action: DropAction, into name: String) -> String? {
        switch action {
        case .move: "Move to " + name
        case .copy: "Copy to " + name
        case .alias: "Create link in " + name
        case .open: "Open with " + name
        case .ask: "Choose what to do in " + name
        case .none: nil
        }
    }

    /// True when the destination is the source folder or sits inside it.
    private static func inside(_ source: URL, _ destKey: String) -> Bool {
        let s = FilePaths.folderKey(source)
        return destKey == s || destKey.hasPrefix(s == "/" ? "/" : s + "/")
    }
}
