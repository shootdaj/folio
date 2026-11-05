import Foundation

/// What is selected, reduced to what the status bar, HUD and ticker print.
public struct SelectionSummary: Sendable, Equatable {
    public let count: Int
    public let firstName: String?
    public let firstIsFolder: Bool
    /// Sum of file sizes in the selection; folders count as nothing.
    public let bytes: Int64
    /// True when at least one selected item has a size (a file).
    public let hasSize: Bool

    public init(_ selected: [FileEntry]) {
        count = selected.count
        firstName = selected.first?.name
        firstIsFolder = selected.first?.isFolder ?? false
        var total: Int64 = 0
        var any = false
        for item in selected {
            if let size = item.size { total += size; any = true }
        }
        bytes = total
        hasSize = any
    }
}

public enum SortLabel {
    /// "Name, A to Z", as the HUD shows it; Shift+click keys follow as "then Type, Name".
    public static func label(_ spec: SortSpec) -> String {
        let first = term(spec.key, spec.ascending)
        return spec.then.isEmpty ? first : first + ", then " + spec.then.map(\.key.title).joined(separator: ", ")
    }

    /// "Date modified, newest first".
    public static func term(_ key: SortKey, _ ascending: Bool) -> String {
        let way: String = if key.isDate {
            ascending ? "oldest first" : "newest first"
        } else if key == .size {
            ascending ? "smallest first" : "largest first"
        } else if key == .duration || key == .bitRate || key == .frameRate || key == .dimensions {
            ascending ? "lowest first" : "highest first"
        } else {
            ascending ? "A to Z" : "Z to A"
        }
        return key.title + ", " + way
    }

    /// "Sorted by name, A to Z", as the ticker shows it.
    public static func sentence(_ spec: SortSpec) -> String {
        let text = label(spec)
        return "Sorted by " + text.prefix(1).lowercased() + text.dropFirst()
    }
}

public enum StatusText {
    /// The status bar after Enter on an address that is not a folder.
    public static let noSuchFolder = "No such folder"

    /// The left of the status bar: "28 items, 1 selected", plus the selected files' size when there is one.
    /// With a header filter on, `total` is the folder's count: "3 items (filtered from 12), 0 selected".
    public static func count(items: Int, selection: SelectionSummary, total: Int? = nil) -> String {
        var text = ByteText.grouped(items) + (items == 1 ? " item" : " items")
        if let total { text += " (filtered from " + ByteText.grouped(total) + ")" }
        text += ", " + ByteText.grouped(selection.count) + " selected"
        if selection.hasSize { text += ", " + ByteText.kilobytes(selection.bytes) }
        return text
    }
}

/// A run of ticker text; strong runs are drawn in the main text colour.
public struct TickerSegment: Sendable, Equatable {
    public let text: String
    public let strong: Bool

    public init(_ text: String, strong: Bool = false) {
        self.text = text
        self.strong = strong
    }
}

public struct TickerItem: Sendable, Equatable {
    public let segments: [TickerSegment]

    public init(_ segments: [TickerSegment]) { self.segments = segments }

    public var plain: String { segments.map(\.text).joined() }
}

/// The right of the status bar: a ticker of free space, selection, sort and path that loops.
public enum Ticker {
    public static func items(volume: VolumeCapacity?, selection: SelectionSummary, sort: SortSpec,
                             path: String) -> [TickerItem] {
        var out: [TickerItem] = []
        if let volume {
            out.append(TickerItem([
                TickerSegment(volume.name + " "),
                TickerSegment(ByteText.storage(volume.free) + " free", strong: true),
                TickerSegment(" of " + ByteText.storage(volume.total)),
            ]))
        }
        out.append(selectionItem(selection))
        out.append(TickerItem([TickerSegment(SortLabel.sentence(sort))]))
        out.append(TickerItem([TickerSegment("Path "), TickerSegment(path, strong: true)]))
        if let volume {
            out.append(TickerItem([TickerSegment(
                "\(volume.percentText) of \(volume.name) used, \(ByteText.storage(volume.used))")]))
        }
        return out
    }

    static func selectionItem(_ s: SelectionSummary) -> TickerItem {
        switch s.count {
        case 0:
            return TickerItem([TickerSegment("Nothing selected")])
        case 1:
            let tail = s.firstIsFolder ? ", folder" : ", " + ByteText.kilobytes(s.bytes)
            return TickerItem([TickerSegment("Selected "), TickerSegment(s.firstName ?? "", strong: true),
                               TickerSegment(tail)])
        default:
            var segments = [TickerSegment("Selected "),
                            TickerSegment(ByteText.grouped(s.count) + " items", strong: true)]
            if s.bytes > 0 { segments.append(TickerSegment(", " + ByteText.kilobytes(s.bytes))) }
            return TickerItem(segments)
        }
    }
}

/// One readout in the HUD strip under the toolbar.
public struct HudSegment: Sendable, Equatable {
    public let key: String
    public let value: String
    /// The breathing light before the key (Path depth only).
    public let hasLight: Bool
    /// Pushed to the right edge (Selected).
    public let trailing: Bool
}

public enum Hud {
    public static func segments(path: String, entries: [FileEntry], sort: SortSpec,
                                selection: SelectionSummary, view: String = "Details") -> [HudSegment] {
        let folders = entries.reduce(0) { $0 + ($1.isFolder ? 1 : 0) }
        return [
            HudSegment(key: "Path depth", value: "\(depth(path))", hasLight: true, trailing: false),
            HudSegment(key: "Items", value: ByteText.grouped(entries.count), hasLight: false, trailing: false),
            HudSegment(key: "Folders", value: ByteText.grouped(folders), hasLight: false, trailing: false),
            HudSegment(key: "Files", value: ByteText.grouped(entries.count - folders), hasLight: false, trailing: false),
            HudSegment(key: "Sort", value: SortLabel.label(sort), hasLight: false, trailing: false),
            HudSegment(key: "View", value: view, hasLight: false, trailing: false),
            HudSegment(key: "Selected", value: selectedText(selection), hasLight: false, trailing: true),
        ]
    }

    /// While the address bar is being edited (D1 step 2): Mode, Matches, Path depth, Keys, Selected.
    public static func editingSegments(shown: Int, total: Int, path: String, selection: SelectionSummary) -> [HudSegment] {
        [
            HudSegment(key: "Mode", value: "Edit address", hasLight: true, trailing: false),
            HudSegment(key: "Matches", value: ByteText.grouped(shown) + " of " + ByteText.grouped(total), hasLight: false, trailing: false),
            HudSegment(key: "Path depth", value: "\(depth(path))", hasLight: false, trailing: false),
            HudSegment(key: "Keys", value: "Tab, Enter, Esc", hasLight: false, trailing: false),
            HudSegment(key: "Selected", value: selectedText(selection), hasLight: false, trailing: true),
        ]
    }

    static func depth(_ path: String) -> Int {
        path.split(separator: "/", omittingEmptySubsequences: true).count
    }

    /// "Nothing", the one name, or "3 items", each followed by the selected files' size when there is one.
    static func selectedText(_ selection: SelectionSummary) -> String {
        let size = selection.hasSize ? ", " + ByteText.kilobytes(selection.bytes) : ""
        switch selection.count {
        case 0: return "Nothing"
        case 1: return (selection.firstName ?? "") + size
        default: return ByteText.grouped(selection.count) + " items" + size
        }
    }
}

/// The colour group of a file icon's badge, as D1 sorts extensions.
public enum FileTypeCategory: Sendable, Equatable {
    case doc, code, web, data

    public init(name: String) {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt": self = .doc
        case "js", "mjs", "ts", "go", "py", "swift": self = .code
        case "css", "html", "htm": self = .web
        default: self = .data
        }
    }
}
