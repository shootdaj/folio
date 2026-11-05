import Foundation

/// Every column the Details view can show; Choose details lists them all. Raw values are the table
/// column identifiers and what the settings and the session store.
public enum ColumnID: String, CaseIterable, Sendable, Codable {
    case name, modified, kind, size
    case created, accessed, added
    case dimensions, duration, bitRate, frameRate, dateTaken, cameraModel
    case album, artist, title
    case owner, permissions, attributes, tags, comments
    case uti, folderPath, linkTarget, ext
    /// Search results: the item's folder as name (parent path), Explorer's System.ItemFolderPathDisplayNarrow.
    case folder
}

/// Sorting, filtering and grouping all work on columns.
public typealias SortKey = ColumnID

/// How a column's values fall into the buckets its filter lists and Group by makes.
public enum BucketStyle: Sendable, Equatable {
    /// Name: 0 - 9, A - H, I - P, Q - Z, Other.
    case alphanumeric
    /// One bucket per distinct value (Type, Owner, Album...).
    case discrete
    /// One bucket per value of a multi-value property (Tags).
    case multiValue
    /// Empty, Tiny, Small, Medium, Large, Huge, Gigantic, folders under Unspecified.
    case size
    /// Today, Yesterday, Earlier this week, ... A long time ago (and the future ones).
    case date
    /// Very short to Very long.
    case duration
}

extension ColumnID {
    /// The header and menu text, as Explorer words it.
    public var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date modified"
        case .kind: "Type"
        case .size: "Size"
        case .created: "Date created"
        case .accessed: "Date accessed"
        case .added: "Date added"
        case .dimensions: "Dimensions"
        case .duration: "Duration"
        case .bitRate: "Bit rate"
        case .frameRate: "Frame rate"
        case .dateTaken: "Date taken"
        case .cameraModel: "Camera model"
        case .album: "Album"
        case .artist: "Artist"
        case .title: "Title"
        case .owner: "Owner"
        case .permissions: "Permissions"
        case .attributes: "Attributes"
        case .tags: "Tags"
        case .comments: "Comments"
        case .uti: "Kind (UTI)"
        case .folderPath: "Folder path"
        case .linkTarget: "Link target"
        case .ext: "Extension"
        case .folder: "Folder"
        }
    }

    /// Width a column starts at, in points (Name then takes whatever the list has left).
    public var defaultWidth: Double {
        switch self {
        case .name: 320
        case .modified, .created, .accessed, .added, .dateTaken: 150
        case .kind: 132
        case .size: 88
        case .dimensions: 110
        case .duration, .bitRate, .ext: 84
        case .frameRate: 130
        case .cameraModel, .album, .artist, .title, .tags: 140
        case .owner, .attributes: 96
        case .permissions: 100
        case .comments: 180
        case .uti: 190
        case .folderPath, .linkTarget: 240
        case .folder: 300
        }
    }

    public var isDate: Bool {
        switch self {
        case .modified, .created, .accessed, .added, .dateTaken: true
        default: false
        }
    }

    /// Direction of the first click on this column: dates newest first, as in Explorer.
    public var defaultAscending: Bool { !isDate }

    /// Sizes and media numbers sit at the right edge of their column.
    public var alignsRight: Bool {
        switch self {
        case .size, .duration, .bitRate, .frameRate: true
        default: false
        }
    }

    /// Dates, sizes and numbers are drawn in the mono face.
    public var isMono: Bool {
        isDate || alignsRight || self == .dimensions || self == .permissions || self == .uti
    }

    /// Read from file attributes, Spotlight, ImageIO or AVFoundation (MetadataReader), not the listing.
    public var needsMetadata: Bool {
        switch self {
        case .name, .modified, .kind, .size, .folderPath, .ext, .folder: false
        default: true
        }
    }

    /// Offered as a tick in the header's right-click menu; every other column is under More...
    public var isCommon: Bool {
        switch self {
        case .name, .modified, .kind, .size, .created, .accessed, .tags, .title, .dimensions, .duration, .ext: true
        default: false
        }
    }

    public var bucketStyle: BucketStyle {
        switch self {
        case .name: .alphanumeric
        case .size: .size
        case .duration: .duration
        case .tags: .multiValue
        default: isDate ? .date : .discrete
        }
    }
}

/// What the metadata reader finds for one item beyond the listing's name, date, type and size.
public struct ItemMetadata: Sendable, Equatable {
    public var created: Date?
    public var accessed: Date?
    public var added: Date?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// Seconds.
    public var duration: Double?
    /// Bits per second.
    public var bitRate: Double?
    /// Frames per second.
    public var frameRate: Double?
    public var dateTaken: Date?
    public var cameraModel: String?
    public var album: String?
    public var artist: String?
    public var title: String?
    public var owner: String?
    /// "rwxr-xr-x".
    public var permissions: String?
    public var isLocked = false
    public var isHidden = false
    public var tags: [String] = []
    public var comments: String?
    /// The uniform type identifier, e.g. "public.png".
    public var uti: String?
    public var linkTarget: String?

    public init() {}
}

/// A column's value for sorting.
public enum ColumnValue: Sendable, Equatable {
    case none
    case text(String)
    case date(Date)
    case number(Double)

    /// -1, 0 or 1; no value sorts before any value, text compares as Finder sorts names.
    public static func compare(_ a: ColumnValue, _ b: ColumnValue) -> Int {
        switch (a, b) {
        case (.none, .none): return 0
        case (.none, _): return -1
        case (_, .none): return 1
        case (.text(let x), .text(let y)):
            switch x.localizedStandardCompare(y) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            case .orderedSame: return 0
            }
        case (.date(let x), .date(let y)): return x < y ? -1 : (x > y ? 1 : 0)
        case (.number(let x), .number(let y)): return x < y ? -1 : (x > y ? 1 : 0)
        default: return a.rank < b.rank ? -1 : (a.rank > b.rank ? 1 : 0)
        }
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .number: 1
        case .date: 2
        case .text: 3
        }
    }
}

/// Values and display text of every column for one item.
public enum ColumnValues {
    /// D1 shows dates as 2026-05-22 21:28 in local time, each date with its own daylight-saving rule.
    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static func dateText(_ date: Date) -> String { dateFormatter.string(from: date) }

    public static func date(_ entry: FileEntry, _ column: ColumnID, _ meta: ItemMetadata?) -> Date? {
        switch column {
        case .modified: entry.modified
        case .created: meta?.created
        case .accessed: meta?.accessed
        case .added: meta?.added
        case .dateTaken: meta?.dateTaken
        default: nil
        }
    }

    public static func value(_ entry: FileEntry, _ column: ColumnID, _ meta: ItemMetadata?) -> ColumnValue {
        if column.isDate { return date(entry, column, meta).map(ColumnValue.date) ?? .none }
        switch column {
        case .name: return .text(entry.name)
        case .size: return entry.size.map { .number(Double($0)) } ?? .none
        case .dimensions:
            guard let w = meta?.pixelWidth, let h = meta?.pixelHeight else { return .none }
            return .number(Double(w) * Double(h))
        case .duration: return meta?.duration.map(ColumnValue.number) ?? .none
        case .bitRate: return meta?.bitRate.map(ColumnValue.number) ?? .none
        case .frameRate: return meta?.frameRate.map(ColumnValue.number) ?? .none
        default:
            let t = text(entry, column, meta)
            return t.isEmpty ? .none : .text(t)
        }
    }

    /// What the cell shows.
    public static func text(_ entry: FileEntry, _ column: ColumnID, _ meta: ItemMetadata?) -> String {
        if column.isDate { return date(entry, column, meta).map(dateText) ?? "" }
        switch column {
        case .name: return entry.name
        case .kind: return entry.kind
        case .size: return entry.size.map(ByteText.kilobytes) ?? ""
        case .dimensions:
            guard let w = meta?.pixelWidth, let h = meta?.pixelHeight else { return "" }
            return "\(w) x \(h)"
        case .duration: return meta?.duration.map(durationText) ?? ""
        case .bitRate: return meta?.bitRate.map { "\(Int(($0 / 1000).rounded()))kbps" } ?? ""
        case .frameRate: return meta?.frameRate.map(frameRateText) ?? ""
        case .cameraModel: return meta?.cameraModel ?? ""
        case .album: return meta?.album ?? ""
        case .artist: return meta?.artist ?? ""
        case .title: return meta?.title ?? ""
        case .owner: return meta?.owner ?? ""
        case .permissions: return meta?.permissions ?? ""
        case .attributes:
            guard let meta else { return "" }
            return [meta.isLocked ? "Locked" : nil, meta.isHidden ? "Hidden" : nil].compactMap { $0 }.joined(separator: ", ")
        case .tags: return meta?.tags.joined(separator: "; ") ?? ""
        case .comments: return meta?.comments ?? ""
        case .uti: return meta?.uti ?? ""
        case .folderPath: return entry.url.deletingLastPathComponent().path
        case .linkTarget: return meta?.linkTarget ?? ""
        case .ext:
            let ext = entry.url.pathExtension
            return entry.isFolder || ext.isEmpty ? "" : "." + ext.lowercased()
        case .folder: return folderText(entry.url)
        default: return ""
        }
    }

    /// The Folder column of search results: the folder's name first, then its parent path in brackets,
    /// with the home folder as ~ ("invoices (~/Documents/2026)").
    public static func folderText(_ url: URL, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        let path = folder.path
        if path == "/" { return FileManager.default.displayName(atPath: "/") }
        if path == home { return "~" }
        let parent = (path as NSString).deletingLastPathComponent
        func tilde(_ p: String) -> String {
            p == home ? "~" : (p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p)
        }
        return folder.lastPathComponent + " (" + tilde(parent) + ")"
    }

    /// Explorer's Length: 00:03:07.
    public static func durationText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    static func frameRateText(_ fps: Double) -> String {
        let rounded = (fps * 100).rounded() / 100
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", rounded)
        return number + " frames/second"
    }
}
