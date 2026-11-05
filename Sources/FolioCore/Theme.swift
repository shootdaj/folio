import Foundation

/// An sRGB colour with alpha, as written in the D1 CSS. AppKit turns it into an NSColor.
public struct RGBA: Sendable, Equatable, CustomStringConvertible {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `0xRRGGBB`, like `#9BFF57`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255, a: alpha)
    }

    /// `rgba(201,209,219,.10)`.
    public init(_ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        self.init(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255, a: a)
    }

    /// CSS `color-mix(in oklab, <colour> N%, transparent)` is the colour at N% alpha.
    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// `#RRGGBB`, alpha left out.
    public var hex: String {
        func byte(_ v: Double) -> String {
            let n = Int((min(max(v, 0), 1) * 255).rounded())
            let s = String(n, radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + byte(r) + byte(g) + byte(b)
    }

    public var description: String { a == 1 ? hex : "\(hex)@\(a)" }
}

public enum Appearance: String, Sendable { case dark, light }

/// The View > Theme choice, saved under the `theme` key.
public enum ThemeChoice: String, Sendable, CaseIterable {
    case system, dark, light

    public func resolve(systemIsDark: Bool) -> Appearance {
        switch self {
        case .system: systemIsDark ? .dark : .light
        case .dark: .dark
        case .light: .light
        }
    }

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The View > Accent choice, saved under the `accent` key. Values from D1's `--acc-dark` and `--acc-light`.
public enum AccentChoice: String, Sendable, CaseIterable {
    case green, amber, cyan

    public var dark: RGBA {
        switch self {
        case .green: RGBA(hex: 0x9BFF57)
        case .amber: RGBA(hex: 0xFFB347)
        case .cyan: RGBA(hex: 0x5EC8E0)
        }
    }

    public var light: RGBA {
        switch self {
        case .green: RGBA(hex: 0x2F7D1E)
        case .amber: RGBA(hex: 0xB45309)
        case .cyan: RGBA(hex: 0x0E7490)
        }
    }

    public func color(for appearance: Appearance) -> RGBA { appearance == .dark ? dark : light }

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Every semantic token of the D1 control room for one theme and accent.
public struct Palette: Sendable, Equatable {
    public let appearance: Appearance
    public let accentChoice: AccentChoice

    public let bg, s1, s2, s3: RGBA
    public let line, line2, line3: RGBA
    public let txt, txt2, txt3: RGBA
    public let accent, onAccent: RGBA
    public let ok, part, miss: RGBA
    public let hudBg, hudLine, hudTxt, hudTxt2, hudAccent: RGBA
    public let foldBack, foldFront, foldLine, fileBg: RGBA
    public let typeDoc, typeCode, typeWeb, typeData: RGBA
    /// `--sel-bg`: the selected row and sidebar item fill.
    public let selectionFill: RGBA
    /// `--mark-bg`: text selection and match highlight.
    public let markFill: RGBA
    /// Corner brackets: the accent at 70%.
    public let bracket: RGBA
    /// The sidebar blueprint grid, 64 px lines and 16 px lines.
    public let gridMajor, gridMinor: RGBA
    /// Dark draws soft glows around lights (`--glow: 0 0 9px`); light has none.
    public let glows: Bool
}

public enum Theme {
    public static func palette(_ appearance: Appearance, accent choice: AccentChoice) -> Palette {
        let accent = choice.color(for: appearance)
        switch appearance {
        case .dark:
            return Palette(
                appearance: .dark, accentChoice: choice,
                bg: RGBA(hex: 0x0C0E11), s1: RGBA(hex: 0x111419), s2: RGBA(hex: 0x161A20), s3: RGBA(hex: 0x1B2028),
                line: RGBA(201, 209, 219, 0.10), line2: RGBA(201, 209, 219, 0.17), line3: RGBA(201, 209, 219, 0.30),
                txt: RGBA(hex: 0xC9D1DB), txt2: RGBA(hex: 0x9BA6B3), txt3: RGBA(hex: 0x838E9B),
                accent: accent, onAccent: RGBA(hex: 0x0C0E11),
                ok: RGBA(hex: 0x9BFF57), part: RGBA(hex: 0xFFB347), miss: RGBA(hex: 0xFF5C5C),
                hudBg: RGBA(hex: 0x08090C), hudLine: RGBA(201, 209, 219, 0.12),
                hudTxt: RGBA(hex: 0xC9D1DB), hudTxt2: RGBA(hex: 0x8E99A6), hudAccent: choice.dark,
                foldBack: RGBA(hex: 0x262C35), foldFront: RGBA(hex: 0x343C48), foldLine: RGBA(hex: 0x5F6B79),
                fileBg: RGBA(hex: 0x1C2229),
                typeDoc: RGBA(hex: 0x8FB4D9), typeCode: RGBA(hex: 0xE3C15C), typeWeb: RGBA(hex: 0x5EC8E0),
                typeData: RGBA(hex: 0xF0915F),
                selectionFill: accent.withAlpha(0.13), markFill: accent.withAlpha(0.24),
                bracket: accent.withAlpha(0.70),
                gridMajor: accent.withAlpha(0.08), gridMinor: accent.withAlpha(0.036),
                glows: true)
        case .light:
            return Palette(
                appearance: .light, accentChoice: choice,
                bg: RGBA(hex: 0xF4F6F8), s1: RGBA(hex: 0xFFFFFF), s2: RGBA(hex: 0xF9FAFB), s3: RGBA(hex: 0xFFFFFF),
                line: RGBA(28, 44, 62, 0.11), line2: RGBA(28, 44, 62, 0.19), line3: RGBA(28, 44, 62, 0.34),
                txt: RGBA(hex: 0x2A3441), txt2: RGBA(hex: 0x48535F), txt3: RGBA(hex: 0x5B6672),
                accent: accent, onAccent: RGBA(hex: 0xFFFFFF),
                ok: RGBA(hex: 0x2F7D1E), part: RGBA(hex: 0xB45309), miss: RGBA(hex: 0xC81E1E),
                hudBg: RGBA(hex: 0x1A1F26), hudLine: RGBA(201, 209, 219, 0.14),
                hudTxt: RGBA(hex: 0xDCE2E9), hudTxt2: RGBA(hex: 0xA3ADB9), hudAccent: choice.dark,
                foldBack: RGBA(hex: 0xD2DAE2), foldFront: RGBA(hex: 0xE6ECF1), foldLine: RGBA(hex: 0x7A8796),
                fileBg: RGBA(hex: 0xFFFFFF),
                typeDoc: RGBA(hex: 0x3B6E9E), typeCode: RGBA(hex: 0x97700A), typeWeb: RGBA(hex: 0x0E7490),
                typeData: RGBA(hex: 0xB4501F),
                selectionFill: accent.withAlpha(0.12), markFill: accent.withAlpha(0.20),
                bracket: accent.withAlpha(0.70),
                gridMajor: accent.withAlpha(0.11), gridMinor: accent.withAlpha(0.05),
                glows: false)
        }
    }
}

/// The saved theme and accent. Keys are `theme` (system, dark, light) and `accent` (green, amber, cyan).
public struct ThemeSettings {
    public static let themeKey = "theme"
    public static let accentKey = "accent"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var theme: ThemeChoice {
        get { defaults.string(forKey: Self.themeKey).flatMap(ThemeChoice.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.themeKey) }
    }

    public var accent: AccentChoice {
        get { defaults.string(forKey: Self.accentKey).flatMap(AccentChoice.init(rawValue:)) ?? .green }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.accentKey) }
    }
}
