import Foundation

/// The two looks, picked in View > Theme. Native follows the Mac's own styles (SF Pro, system colours,
/// the accent from System Settings > Appearance). D4 Obsidian is the ported design in
/// docs/design/d4-obsidian-spotlight.html. Both follow the Mac's light or dark setting.
public enum LookTheme: String, CaseIterable, Sendable {
    case native, obsidian

    /// The menu title.
    public var title: String {
        switch self {
        case .native: "Native"
        case .obsidian: "D4 Obsidian"
        }
    }

    /// The title bar's accent swatch and its hue picker. Native takes the accent from the system.
    public var showsAccentSwatch: Bool { self == .obsidian }
}

/// The saved look: one string under `lookTheme`. Not `theme`, which AccentSettings clears as a key of
/// the retired Control room menus.
public struct LookSettings {
    public static let key = "lookTheme"
    public static let defaultLook = LookTheme.native

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Native when nothing is saved or the saved value is not a look.
    public var look: LookTheme {
        get { defaults.string(forKey: Self.key).flatMap(LookTheme.init(rawValue:)) ?? Self.defaultLook }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}
