import Foundation

/// The navigation pane's width and its folded sections (Quick access, This PC, Network, All folders),
/// one setting for every window, kept as they change.
public struct SidebarStore {
    public static let widthKey = "navPaneWidth"
    public static let collapsedKey = "navPaneCollapsed"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Nil until the pane was dragged.
    public var width: Double? {
        let w = defaults.double(forKey: Self.widthKey)
        return w > 0 ? w : nil
    }

    public func setWidth(_ w: Double) { defaults.set(w, forKey: Self.widthKey) }

    public var collapsed: Set<String> { Set(defaults.stringArray(forKey: Self.collapsedKey) ?? []) }

    public func setCollapsed(_ sections: Set<String>) { defaults.set(sections.sorted(), forKey: Self.collapsedKey) }
}
