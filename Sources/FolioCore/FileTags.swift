import Darwin
import Foundation

/// Finder's label colours, numbered as Finder stores them.
public enum TagColor: Int, CaseIterable, Sendable {
    case none = 0, gray, green, purple, blue, yellow, red, orange

    public var name: String {
        switch self {
        case .none: "None"
        case .gray: "Gray"
        case .green: "Green"
        case .purple: "Purple"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .red: "Red"
        case .orange: "Orange"
        }
    }

    /// The Tags submenu, as Finder lists the seven colours.
    public static let menuOrder: [TagColor] = [.red, .orange, .yellow, .green, .blue, .purple, .gray]
}

public struct FileTag: Sendable, Hashable {
    public let name: String
    public let color: TagColor

    public init(name: String, color: TagColor) {
        self.name = name
        self.color = color
    }

    /// One of the seven colour tags under its standard name.
    public static func standard(_ color: TagColor) -> FileTag { FileTag(name: color.name, color: color) }
}

/// Tags read and written in `com.apple.metadata:_kMDItemUserTags`, the attribute Finder, Spotlight
/// (`tag:` search) and URL tag names all use: a binary plist of "Name\nColour" strings.
public enum FileTags {
    static let attribute = "com.apple.metadata:_kMDItemUserTags"

    public static func read(_ url: URL) -> [FileTag] { rawValues(url).map(parse) }

    /// The stored strings ("Red\n6").
    public static func rawValues(_ url: URL) -> [String] {
        let size = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard n > 0 else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String] ?? []
    }

    /// "Red\n6", or a name alone (written by a tool that sets names only), which takes its standard colour.
    public static func parse(_ raw: String) -> FileTag {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts.first ?? "")
        if parts.count == 2, let n = Int(parts[1]) { return FileTag(name: name, color: TagColor(rawValue: n) ?? .none) }
        return FileTag(name: name, color: standardColor(for: name))
    }

    public static func standardColor(for name: String) -> TagColor {
        TagColor.allCases.first { $0 != .none && $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? .none
    }

    /// Replaces the item's tags; none removes the attribute.
    public static func write(_ tags: [FileTag], to url: URL) throws {
        if tags.isEmpty {
            if removexattr(url.path, attribute, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return
        }
        let raw = tags.map { $0.name + "\n" + String($0.color.rawValue) }
        let data = try PropertyListSerialization.data(fromPropertyList: raw, format: .binary, options: 0)
        let r = data.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        if r != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    /// Names typed in the Details pane: tags kept keep their colour, new ones take the standard one.
    public static func setNames(_ names: [String], of url: URL) throws {
        let old = read(url)
        try write(names.map { name in old.first { $0.name == name } ?? FileTag(name: name, color: standardColor(for: name)) }, to: url)
    }

    public enum State: Sendable, Equatable { case off, mixed, on }

    /// A Tags submenu tick: on every item, some of them, or none.
    public static func state(of tag: FileTag, on urls: [URL]) -> State {
        let has = urls.map { read($0).contains { $0.name == tag.name } }
        if has.allSatisfy({ $0 }) && !has.isEmpty { return .on }
        return has.contains(true) ? .mixed : .off
    }

    /// A pick in the Tags submenu: on every item unless all have it already, then off every item.
    public static func toggle(_ tag: FileTag, on urls: [URL]) throws {
        let adding = state(of: tag, on: urls) != .on
        for url in urls {
            var tags = read(url).filter { $0.name != tag.name }
            if adding { tags.append(tag) }
            try write(tags, to: url)
        }
    }
}
