import Foundation

/// Explorer's layouts plus Gallery.
public enum ViewMode: String, CaseIterable, Sendable, Codable {
    case extraLargeIcons, largeIcons, mediumIcons, smallIcons, list, details, tiles, content, gallery

    public var title: String {
        switch self {
        case .extraLargeIcons: "Extra large icons"
        case .largeIcons: "Large icons"
        case .mediumIcons: "Medium icons"
        case .smallIcons: "Small icons"
        case .list: "List"
        case .details: "Details"
        case .tiles: "Tiles"
        case .content: "Content"
        case .gallery: "Gallery"
        }
    }

    /// Explorer's Ctrl+Shift+1 to 8, in its own order; Gallery has no number.
    public var shortcut: Int? {
        switch self {
        case .extraLargeIcons: 1
        case .largeIcons: 2
        case .mediumIcons: 3
        case .smallIcons: 4
        case .list: 5
        case .details: 6
        case .tiles: 7
        case .content: 8
        case .gallery: nil
        }
    }

    public static func forShortcut(_ n: Int) -> ViewMode? { allCases.first { $0.shortcut == n } }

    /// Explorer's View slider, smallest to largest; Ctrl+wheel (Cmd+scroll here) walks it.
    public static let zoomOrder: [ViewMode] = [.content, .tiles, .details, .list, .smallIcons, .mediumIcons, .largeIcons, .extraLargeIcons]

    /// `steps` along the slider (positive is larger), stopping at either end. Gallery starts from Large icons.
    public func zoomed(by steps: Int) -> ViewMode {
        let i = Self.zoomOrder.firstIndex(of: self) ?? Self.zoomOrder.firstIndex(of: .largeIcons)!
        return Self.zoomOrder[min(max(0, i + steps), Self.zoomOrder.count - 1)]
    }

    /// The Details table; every other view is the icon grid.
    public var usesTable: Bool { self == .details }

    /// Icon edge in points (the grid's cells are laid out from it).
    public var iconSize: Double {
        switch self {
        case .extraLargeIcons: 256
        case .largeIcons: 96
        case .mediumIcons: 48
        case .smallIcons, .list: 16
        case .details: 16
        case .tiles: 48
        case .content: 40
        case .gallery: 120
        }
    }

    /// Big enough to be worth a content thumbnail rather than the type icon.
    public var showsThumbnails: Bool { iconSize >= 40 }
}

/// The one view every folder shows. Changing it applies at once to every window and folder and is not
/// saved; "Make this the default view" saves it, and each launch starts in the saved default. No
/// folder keeps a view of its own.
public struct ViewSettings: Sendable {
    public static let defaultKey = "defaultView"
    public private(set) var current: ViewMode
    public private(set) var defaultMode: ViewMode

    public init(defaults: UserDefaults) {
        let saved = defaults.string(forKey: Self.defaultKey).flatMap(ViewMode.init(rawValue:)) ?? .details
        defaultMode = saved
        current = saved
    }

    public mutating func set(_ mode: ViewMode) { current = mode }

    /// True when the current view is already the default (the menu item is then ticked).
    public var isDefault: Bool { current == defaultMode }

    public mutating func makeDefault(in defaults: UserDefaults) {
        defaultMode = current
        defaults.set(current.rawValue, forKey: Self.defaultKey)
    }
}
