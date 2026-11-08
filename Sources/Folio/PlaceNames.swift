/// The names of Folio's places: Finder's in the Native look, Explorer's in D4 Obsidian.
@MainActor
enum PlaceNames {
    private static var native: Bool { ThemeController.shared.isNative }
    /// The pinned folders' section of the navigation pane.
    static var quickAccess: String { native ? "Favorites" : "Quick access" }
    /// The drives' section of the navigation pane.
    static var thisPC: String { native ? "Locations" : "This PC" }
    /// The whole Mac, as a search scope.
    static var thisComputer: String { native ? "This Mac" : "This PC" }
    /// The Trash.
    static var recycleBin: String { native ? "Trash" : "Recycle Bin" }
}
