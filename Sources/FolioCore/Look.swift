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

/// Every colour token of the palette, by name: the same names in both looks.
public enum PaletteToken: String, CaseIterable, Sendable {
    case bg, s1, s2, s3, s4
    case line, line2, outline
    case text, text2, muted, faint
    case accent, onAccent, accentSoft, markFill, selectionFill
    /// The selection when the list does not have focus in the key window.
    case selectionInactive
    /// Text on an emphasised selection.
    case selectedText
    case ok, part, miss
    case pane, chrome, side, bar
    case pop, tray
    case field, headBg, rowLine, well, segBg, thumb, scrim
}

extension Palette {
    /// D4's value for a token. D4 has no separate unfocused selection or selected text: its selection
    /// is a soft wash with the normal text colour.
    public func rgba(_ token: PaletteToken) -> RGBA {
        switch token {
        case .bg: bg
        case .s1: s1
        case .s2: s2
        case .s3: s3
        case .s4: s4
        case .line: line
        case .line2: line2
        case .outline: outline
        case .text: text
        case .text2: text2
        case .muted: muted
        case .faint: faint
        case .accent: accent
        case .onAccent: onAccent
        case .accentSoft: accentSoft
        case .markFill: markFill
        case .selectionFill: selectionFill
        case .selectionInactive: selectionFill
        case .selectedText: text
        case .ok: ok
        case .part: part
        case .miss: miss
        case .pane: pane
        case .chrome: chrome
        case .side: side
        case .bar: bar
        case .pop: pop
        case .tray: tray
        case .field: field
        case .headBg: headBg
        case .rowLine: rowLine
        case .well: well
        case .segBg: segBg
        case .thumb: thumb
        case .scrim: scrim
        }
    }
}

/// The Native look's colours: for each token, the name of the NSColor class property it is
/// (docs/design/native.md). The app resolves them as dynamic colours, so light, dark, Increase
/// Contrast and the accent and highlight colours follow System Settings.
public enum NativeTheme {
    public static func role(for token: PaletteToken) -> String {
        switch token {
        case .text: "labelColor"
        case .text2, .muted: "secondaryLabelColor"
        case .faint, .outline: "tertiaryLabelColor"
        case .line, .line2: "separatorColor"
        case .accent: "controlAccentColor"
        case .onAccent, .selectedText: "alternateSelectedControlTextColor"
        case .accentSoft: "keyboardFocusIndicatorColor"
        case .markFill: "selectedTextBackgroundColor"
        case .selectionFill: "selectedContentBackgroundColor"
        case .selectionInactive: "unemphasizedSelectedContentBackgroundColor"
        case .ok: "systemGreenColor"
        case .part: "systemOrangeColor"
        case .miss: "systemRedColor"
        case .pane, .s1, .headBg, .thumb: "controlBackgroundColor"
        // side, bar, pop and tray sit on a material once it is drawn; until then, the window's colour.
        case .bg, .s2, .chrome, .side, .bar, .pop, .tray: "windowBackgroundColor"
        case .s3: "secondarySystemFillColor"
        case .s4: "systemFillColor"
        case .field, .well, .segBg: "quaternarySystemFillColor"
        case .scrim: "shadowColor"
        case .rowLine: "clearColor"
        }
    }

    /// D4's file-type hues as system colours. Finder icons carry their own colour, so these are left
    /// for tag dots (Finder's tag colours) and the few glyphs that keep a hue.
    public static func role(for hue: NeonHue) -> String {
        switch hue {
        case .blue: "systemBlueColor"
        case .violet: "systemPurpleColor"
        case .amber, .orange: "systemOrangeColor"
        case .teal: "systemTealColor"
        case .pink, .magenta: "systemPinkColor"
        case .cyan: "systemCyanColor"
        case .lime, .green: "systemGreenColor"
        case .gold: "systemYellowColor"
        case .coral: "systemRedColor"
        }
    }
}
