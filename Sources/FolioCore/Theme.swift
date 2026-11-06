import Foundation

/// An sRGB colour with alpha, as written in the D4 CSS. AppKit turns it into an NSColor.
public struct RGBA: Sendable, Equatable, CustomStringConvertible {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `0xRRGGBB`, like `#4F8CFF`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255, a: alpha)
    }

    /// `rgba(20,23,30,.08)`.
    public init(_ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        self.init(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255, a: a)
    }

    /// CSS `color-mix(in srgb, <colour> N%, transparent)` is the colour at N% alpha.
    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// CSS `color-mix(in srgb, self N%, other)` for two opaque colours: the channels mixed.
    public func mixed(_ fraction: Double, with other: RGBA) -> RGBA {
        RGBA(r: r * fraction + other.r * (1 - fraction), g: g * fraction + other.g * (1 - fraction),
             b: b * fraction + other.b * (1 - fraction), a: a * fraction + other.a * (1 - fraction))
    }

    /// This colour (with its alpha) laid over an opaque `base`: what the eye sees.
    public func over(_ base: RGBA) -> RGBA {
        RGBA(r: r * a + base.r * (1 - a), g: g * a + base.g * (1 - a), b: b * a + base.b * (1 - a), a: 1)
    }

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

/// A CSS `oklch(L C H)` colour, turned into sRGB the way a browser shows it on an sRGB screen
/// (channels outside 0...1 clipped).
public struct OKLCH: Sendable, Equatable {
    public var lightness: Double, chroma: Double, hue: Double

    public init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
        self.lightness = lightness; self.chroma = chroma; self.hue = hue
    }

    public var srgb: RGBA {
        let a = chroma * cos(hue * .pi / 180), b = chroma * sin(hue * .pi / 180)
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func encode(_ x: Double) -> Double {
            let v = abs(x) <= 0.0031308 ? 12.92 * x : (x < 0 ? -1 : 1) * (1.055 * pow(abs(x), 1 / 2.4) - 0.055)
            return min(max(v, 0), 1)
        }
        return RGBA(r: encode(lr), g: encode(lg), b: encode(lb))
    }
}

/// The accent is one hue (degrees on the OKLCH wheel), saved as a number. Dark and light share the
/// hue; light is the deeper shade (`--acc-ll` .528 against dark's `--acc-ld` .657).
public enum Accent {
    /// 262 gives the look's electric blue.
    public static let defaultHue = 262
    public static let dark = (lightness: 0.657, chroma: 0.182)
    public static let light = (lightness: 0.528, chroma: 0.207)
    /// The picker's eight swatches, from D4's PRESETS.
    public static let presets: [(name: String, hue: Int)] = [
        ("Electric blue", 262), ("Violet", 295), ("Magenta", 330), ("Red", 25),
        ("Orange", 55), ("Gold", 90), ("Green", 145), ("Teal", 190),
    ]

    /// Any number of degrees as 0...359, rounded (D4's `((a % 360) + 360) % 360`).
    public static func normalized(_ hue: Double) -> Int {
        guard hue.isFinite else { return defaultHue }
        let r = Int(hue.rounded()) % 360
        return r < 0 ? r + 360 : r
    }

    public static func lch(hue: Int, _ appearance: Appearance) -> OKLCH {
        let v = appearance == .dark ? dark : light
        return OKLCH(v.lightness, v.chroma, Double(normalized(Double(hue))))
    }

    /// The accent for a hue in a theme. The default hue is the look's exact tokens (#4F8CFF and
    /// #1F5FE0, which oklch rounds one step away from); every other hue is computed.
    public static func color(hue: Int, _ appearance: Appearance) -> RGBA {
        let h = normalized(Double(hue))
        if h == defaultHue { return appearance == .dark ? RGBA(hex: 0x4F8CFF) : RGBA(hex: 0x1F5FE0) }
        return lch(hue: h, appearance).srgb
    }
}

/// D4's twelve neon hues (`--h-*`), each file type's colour.
public enum NeonHue: String, Sendable, CaseIterable {
    case blue, violet, amber, teal, pink, orange, cyan, lime, gold, coral, green, magenta

    public func color(_ appearance: Appearance) -> RGBA {
        let dark = appearance == .dark
        switch self {
        case .blue: return RGBA(hex: dark ? 0x4D9BFF : 0x1A5FE0)
        case .violet: return RGBA(hex: dark ? 0xA98BFF : 0x6B3FD6)
        case .amber: return RGBA(hex: dark ? 0xFFB443 : 0x9A5A00)
        case .teal: return RGBA(hex: dark ? 0x2DD4BF : 0x0A7C70)
        case .pink: return RGBA(hex: dark ? 0xFF6BB5 : 0xC2187A)
        case .orange: return RGBA(hex: dark ? 0xFF6A3D : 0xC43B0E)
        case .cyan: return RGBA(hex: dark ? 0x5EC8E0 : 0x0C6F8A)
        case .lime: return RGBA(hex: dark ? 0xB8E63A : 0x4C7A00)
        case .gold: return RGBA(hex: dark ? 0xE8C547 : 0x8A6500)
        case .coral: return RGBA(hex: dark ? 0xFF8A80 : 0xC0392B)
        case .green: return RGBA(hex: dark ? 0x4ADE80 : 0x1B7F3F)
        case .magenta: return RGBA(hex: dark ? 0xE255FF : 0xA21CAF)
        }
    }
}

/// Which neon hue a file's icon takes, by extension (D4's EXT_HUE, widened to the types a Mac holds).
/// Folders carry the accent instead, so they have none.
public enum TypeHue {
    static let table: [String: NeonHue] = {
        var t: [String: NeonHue] = [:]
        func set(_ hue: NeonHue, _ exts: [String]) { for e in exts { t[e] = hue } }
        set(.violet, ["md", "markdown", "txt", "rtf", "log"])
        set(.pink, ["css", "scss", "sass", "less", "mov", "mp4", "m4v", "mkv", "avi", "webm"])
        set(.cyan, ["ts", "tsx"])
        set(.gold, ["js", "jsx", "cjs"])
        set(.lime, ["mjs", "zip", "7z", "tar", "gz", "tgz", "bz2", "xz", "rar", "dmg", "iso"])
        set(.magenta, ["json", "yaml", "yml", "toml", "plist", "xml"])
        set(.teal, ["go", "csv", "tsv", "xls", "xlsx", "numbers", "sqlite", "db"])
        set(.orange, ["html", "htm", "swift"])
        set(.blue, ["py", "rb", "rs", "c", "h", "cpp", "m", "java", "kt", "sh", "zsh", "doc", "docx", "pages"])
        set(.amber, ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tif", "tiff", "bmp", "psd"])
        set(.green, ["mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg"])
        set(.coral, ["pdf", "key", "ppt", "pptx"])
        return t
    }()

    /// nil for a folder (it takes the accent); cyan for anything not in the table.
    public static func hue(name: String, isFolder: Bool) -> NeonHue? {
        guard !isFolder else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        return table[ext] ?? .cyan
    }
}

/// D4's motion tokens: durations, the cubic curves and the two springs (CSS `linear()` stops).
public enum Motion {
    public static let fast = 0.12, standard = 0.22, slow = 0.42
    /// `--ease`, `--ease-out`, `--ease-in` as cubic-bezier control points.
    public static let ease = (0.2, 0.0, 0.0, 1.0)
    public static let easeOut = (0.16, 1.0, 0.3, 1.0)
    public static let easeIn = (0.4, 0.0, 1.0, 1.0)
    /// `--spring`: overshoots to 1.05 and settles.
    public static let spring: [(t: Double, v: Double)] = [
        (0, 0), (0.008, 0.013), (0.017, 0.05), (0.036, 0.19), (0.086, 0.64), (0.112, 0.83), (0.136, 0.96),
        (0.161, 1.03), (0.187, 1.05), (0.24, 1.03), (0.305, 0.99), (1, 1),
    ]
    /// `--spring-soft`: a gentler settle, peaking at 1.01.
    public static let springSoft: [(t: Double, v: Double)] = [
        (0, 0), (0.04, 0.2), (0.09, 0.5), (0.15, 0.8), (0.22, 0.96), (0.30, 1.01), (1, 1),
    ]

    /// A `linear()` easing at progress `t` (0...1).
    public static func value(_ stops: [(t: Double, v: Double)], at t: Double) -> Double {
        let t = min(max(t, 0), 1)
        guard let i = stops.firstIndex(where: { $0.t >= t }) else { return stops.last?.v ?? 1 }
        if i == 0 { return stops[0].v }
        let a = stops[i - 1], b = stops[i]
        return b.t == a.t ? b.v : a.v + (b.v - a.v) * (t - a.t) / (b.t - a.t)
    }
}

/// Every token of D4 Obsidian spotlight for one theme and accent hue: tokens.css plus the app's
/// semantic tokens, with each `color-mix` resolved against the surface it sits on.
public struct Palette: Sendable, Equatable {
    public let appearance: Appearance
    public let accentHue: Int

    /// Near-black (or near-white) surfaces, darkest first in dark.
    public let bg, s1, s2, s3, s4: RGBA
    /// Hairlines: `--line`, `--line-2`, `--outline`.
    public let line, line2, outline: RGBA
    /// `--text`, `--text-2`, `--muted`, `--faint`.
    public let text, text2, muted, faint: RGBA
    public let accent: RGBA
    /// `--accent-ink`: text on an accent fill.
    public let onAccent: RGBA
    /// `--accent-soft`: focus halos (18% dark, 12% light).
    public let accentSoft: RGBA
    /// `--mark`: text selection and match highlight.
    public let markFill: RGBA
    /// `--sel`: the selected row's fill.
    public let selectionFill: RGBA
    /// `--ok`, `--part`, `--miss`: green, amber, coral.
    public let ok, part, miss: RGBA
    /// The window's areas: list pane, title and status bars (`--chrome`), sidebar, toolbar (`--bar-solid`).
    public let pane, chrome, side, bar: RGBA
    /// Popovers, menus and trays (`--pop`, `--tray`), drawn on their own window.
    public let pop, tray: RGBA
    /// Address and search fields on the toolbar (`--field` over `--bar`).
    public let field: RGBA
    /// The sticky column header (`--head-bg`).
    public let headBg: RGBA
    /// The row hairline (`--row-line`).
    public let rowLine: RGBA
    /// Inset wells in cards (`--well`), segmented control track and thumb.
    public let well, segBg, thumb: RGBA
    /// The dimming behind the copy window (`--scrim`).
    public let scrim: RGBA
    /// The cursor glow's strength (`--glow-a`: 16% dark, 12% light).
    public let glowAlpha: Double

    /// A neon hue in this theme.
    public func hue(_ h: NeonHue) -> RGBA { h.color(appearance) }

    /// An item's icon colour: the accent for folders, the type's neon hue for files.
    public func typeHue(name: String, isFolder: Bool) -> RGBA {
        TypeHue.hue(name: name, isFolder: isFolder).map(hue) ?? accent
    }

    /// Dark draws glows around lit things; light keeps them, softer.
    public var glows: Bool { true }
}

public enum Theme {
    public static func palette(_ appearance: Appearance, hue: Int = Accent.defaultHue) -> Palette {
        let h = Accent.normalized(Double(hue))
        let accent = Accent.color(hue: h, appearance)
        switch appearance {
        case .dark:
            let bg = RGBA(hex: 0x08090C), s1 = RGBA(hex: 0x0F1116), s2 = RGBA(hex: 0x14171E)
            let line = RGBA(hex: 0x1E222B)
            let bar = s1.mixed(0.78, with: bg)
            return Palette(
                appearance: .dark, accentHue: h,
                bg: bg, s1: s1, s2: s2, s3: RGBA(hex: 0x1B1F28), s4: RGBA(hex: 0x232834),
                line: line, line2: RGBA(hex: 0x2A2F3A), outline: RGBA(hex: 0x3A4050),
                text: RGBA(hex: 0xEDEFF3), text2: RGBA(hex: 0xC3C8D2), muted: RGBA(hex: 0x8A919E), faint: RGBA(hex: 0x5C6370),
                accent: accent, onAccent: RGBA(hex: 0x08090C),
                accentSoft: accent.withAlpha(0.18), markFill: accent.withAlpha(0.34), selectionFill: accent.withAlpha(0.15),
                ok: NeonHue.green.color(.dark), part: NeonHue.amber.color(.dark), miss: NeonHue.coral.color(.dark),
                pane: bg, chrome: bg, side: bg, bar: bar,
                pop: s2.withAlpha(0.88), tray: s1.withAlpha(0.86),
                field: bg.mixed(0.72, with: bar), headBg: bg,
                rowLine: line.withAlpha(0.62),
                well: bg.withAlpha(0.45), segBg: s1, thumb: RGBA(hex: 0x1B1F28),
                scrim: bg.withAlpha(0.58), glowAlpha: 0.16)
        case .light:
            let bg = RGBA(hex: 0xF7F8FA), s1 = RGBA(hex: 0xFFFFFF), s2 = RGBA(hex: 0xEEF0F4), s4 = RGBA(hex: 0xD9DDE5)
            let line = RGBA(hex: 0xE1E4EA)
            return Palette(
                appearance: .light, accentHue: h,
                bg: bg, s1: s1, s2: s2, s3: RGBA(hex: 0xE4E7ED), s4: s4,
                line: line, line2: RGBA(hex: 0xCFD4DD), outline: RGBA(hex: 0xB9BFCB),
                text: RGBA(hex: 0x14171E), text2: RGBA(hex: 0x2E3440), muted: RGBA(hex: 0x5B6270), faint: RGBA(hex: 0x8A919E),
                accent: accent, onAccent: RGBA(hex: 0xFFFFFF),
                accentSoft: accent.withAlpha(0.12), markFill: accent.withAlpha(0.22), selectionFill: accent.withAlpha(0.11),
                ok: NeonHue.green.color(.light), part: NeonHue.amber.color(.light), miss: NeonHue.coral.color(.light),
                pane: s1, chrome: s2, side: bg, bar: s1,
                pop: s1.withAlpha(0.93), tray: s1.withAlpha(0.90),
                field: bg, headBg: s1,
                rowLine: line.withAlpha(0.80),
                well: bg, segBg: s2, thumb: s1,
                scrim: s4.withAlpha(0.52), glowAlpha: 0.12)
        }
    }
}

/// The saved accent: one hue number under `accentHue`. The theme itself follows the Mac's light or
/// dark setting and is not saved; the Control room's `theme` and `accent` keys are cleared.
public struct AccentSettings {
    public static let hueKey = "accentHue"
    /// Keys the old View > Theme and View > Accent menus wrote.
    public static let retiredKeys = ["theme", "accent"]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var hue: Int {
        get {
            guard let n = defaults.object(forKey: Self.hueKey) as? NSNumber else { return Accent.defaultHue }
            return Accent.normalized(n.doubleValue)
        }
        nonmutating set { defaults.set(Accent.normalized(Double(newValue)), forKey: Self.hueKey) }
    }

    /// Drops the retired keys (once per launch is enough).
    public func clearRetiredKeys() {
        for key in Self.retiredKeys { defaults.removeObject(forKey: key) }
    }
}
