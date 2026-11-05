import Foundation

/// The address bar's history dropdown (F4, or the arrow at the right end of the bar): the last 20
/// folders typed or visited, most recent first, shared by every window and kept in UserDefaults.
/// Milestone 5's Home view reads the same list as Recent locations.
public struct AddressHistory {
    public static let key = "addressHistory"
    public static let limit = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var paths: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    /// The same list as folder URLs, for Home's Recent locations.
    public var recentLocations: [URL] { paths.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    /// Puts `path` at the top. A folder already in the list moves up instead of appearing twice.
    public func record(_ path: String) {
        guard !path.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let clean = Breadcrumbs.normalized(path)
        var list = paths.filter { $0 != clean }
        list.insert(clean, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }
}
