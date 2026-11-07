import AppKit
import FolioCore

extension RGBA {
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// The colours every view draws with, as NSColor. D4 Obsidian builds them from FolioCore's Palette (fixed
/// sRGB, the exact D4 tokens); Native will hold the Mac's dynamic system colours, resolved when drawn.
/// The token names are the Palette's, so a view asks for the same name in both looks.
struct ThemeColors {
    let appearance: Appearance
    let accentHue: Int
    let bg, s1, s2, s3, s4: NSColor
    let line, line2, outline: NSColor
    let text, text2, muted, faint: NSColor
    let accent, onAccent, accentSoft, markFill, selectionFill: NSColor
    /// The selection when the list does not have focus in the key window (D4: the same fill).
    let selectionInactive: NSColor
    /// Text on an emphasised selection (D4: the normal text colour).
    let selectedText: NSColor
    let ok, part, miss: NSColor
    let pane, chrome, side, bar: NSColor
    let pop, tray: NSColor
    let field, headBg, rowLine, well, segBg, thumb, scrim: NSColor
    let glowAlpha: Double
    let glows: Bool
    private let neon: (NeonHue) -> NSColor

    /// D4 Obsidian: every token is the Palette's fixed sRGB value.
    init(_ p: Palette) {
        appearance = p.appearance; accentHue = p.accentHue
        bg = p.bg.ns; s1 = p.s1.ns; s2 = p.s2.ns; s3 = p.s3.ns; s4 = p.s4.ns
        line = p.line.ns; line2 = p.line2.ns; outline = p.outline.ns
        text = p.text.ns; text2 = p.text2.ns; muted = p.muted.ns; faint = p.faint.ns
        accent = p.accent.ns; onAccent = p.onAccent.ns; accentSoft = p.accentSoft.ns; markFill = p.markFill.ns
        selectionFill = p.selectionFill.ns; selectionInactive = p.selectionFill.ns; selectedText = p.text.ns
        ok = p.ok.ns; part = p.part.ns; miss = p.miss.ns
        pane = p.pane.ns; chrome = p.chrome.ns; side = p.side.ns; bar = p.bar.ns
        pop = p.pop.ns; tray = p.tray.ns
        field = p.field.ns; headBg = p.headBg.ns; rowLine = p.rowLine.ns; well = p.well.ns
        segBg = p.segBg.ns; thumb = p.thumb.ns; scrim = p.scrim.ns
        glowAlpha = p.glowAlpha; glows = p.glows
        neon = { p.hue($0).ns }
    }

    /// One of the twelve file-type hues.
    func hue(_ h: NeonHue) -> NSColor { neon(h) }

    /// A file's icon colour; a folder takes the accent.
    func typeHue(name: String, isFolder: Bool) -> NSColor {
        TypeHue.hue(name: name, isFolder: isFolder).map(neon) ?? accent
    }

    /// What every view draws with now.
    @MainActor static var current: ThemeColors { ThemeController.shared.colors }
}

/// RGBA's colour arithmetic on NSColor, so a view's code reads the same in both looks. `mixed` and
/// `over` repeat RGBA's sRGB math exactly (D4's pixels must not move); on a dynamic colour they resolve
/// it for the current drawing appearance, so they belong inside draw().
extension NSColor {
    var ns: NSColor { self }
    var cg: CGColor { cgColor }
    var a: Double { Double(alphaComponent) }

    func withAlpha(_ alpha: Double) -> NSColor { withAlphaComponent(alpha) }

    private var rgba: RGBA {
        let c = usingColorSpace(.sRGB) ?? self
        return RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }

    func mixed(_ fraction: Double, with other: NSColor) -> NSColor { rgba.mixed(fraction, with: other.rgba).ns }

    func over(_ base: NSColor) -> NSColor { rgba.over(base.rgba).ns }
}

/// Views that hold colours outside `draw(_:)` (layers) refresh them here.
@MainActor
protocol ThemeAware: AnyObject {
    func themeDidChange()
}

/// Redraws a view tree after a theme or accent change.
@MainActor
func refreshTheme(in view: NSView) {
    (view as? ThemeAware)?.themeDidChange()
    view.needsDisplay = true
    for sub in view.subviews { refreshTheme(in: sub) }
}

/// Owns the accent hue (UserDefaults key `accentHue`) and the resolved palette. The theme follows the
/// Mac's appearance only: `NSApp.appearance` stays nil (under `--uitest`, a forced appearance for that run).
@MainActor
final class ThemeController {
    static let shared = ThemeController()
    static let didChange = Notification.Name("FolioThemeDidChange")

    private var settings = AccentSettings(defaults: .standard)
    private var lookSettings = LookSettings(defaults: .standard)
    private(set) var palette = Theme.palette(.dark)
    private(set) var colors = ThemeColors(Theme.palette(.dark))
    /// A hue being dragged in the picker: drawn everywhere, saved when the drag ends.
    private var previewHue: Int?

    private init() {}

    /// Called once at launch, before any window. `defaults` is a temp store under `--uitest`.
    func start(defaults: UserDefaults, forcedAppearance: Appearance? = nil) {
        settings = AccentSettings(defaults: defaults)
        lookSettings = LookSettings(defaults: defaults)
        settings.clearRetiredKeys()
        switch forcedAppearance {
        case .dark?: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light?: NSApp.appearance = NSAppearance(named: .aqua)
        case nil: NSApp.appearance = nil
        }
        refresh(force: true)
    }

    /// The saved hue (0...359).
    var hue: Int {
        get { previewHue ?? settings.hue }
        set { previewHue = nil; settings.hue = newValue; refresh(force: false) }
    }

    /// View > Theme (UserDefaults key `lookTheme`). Setting it saves it and redraws; the AppDelegate
    /// then opens each browser window again, since a look also changes how views are built.
    var look: LookTheme {
        get { lookSettings.look }
        set {
            guard newValue != lookSettings.look else { return }
            lookSettings.look = newValue
            refresh(force: true)
        }
    }

    /// Live preview while the hue slider moves: every window recolours, nothing is saved yet.
    func preview(hue: Int) {
        previewHue = Accent.normalized(Double(hue))
        refresh(force: false)
    }

    /// The system switched light and dark.
    func systemAppearanceMayHaveChanged() { refresh(force: false) }

    private func refresh(force: Bool) {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let next = Theme.palette(systemIsDark ? .dark : .light, hue: previewHue ?? settings.hue)
        guard force || next != palette else { return }
        palette = next
        colors = ThemeColors(next)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
