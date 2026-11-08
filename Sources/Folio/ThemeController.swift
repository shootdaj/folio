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
        self.init(appearance: p.appearance, accentHue: p.accentHue, glowAlpha: p.glowAlpha, glows: p.glows,
                  color: { p.rgba($0).ns }, neon: { p.hue($0).ns })
    }

    /// Native: every token is one of the Mac's dynamic system colours (NativeTheme's table), resolved
    /// whenever it is drawn, so light, dark, Increase Contrast and the accent follow System Settings.
    static func native(appearance: Appearance) -> ThemeColors {
        ThemeColors(appearance: appearance, accentHue: Accent.defaultHue, glowAlpha: 0, glows: false,
                    color: { system(NativeTheme.role(for: $0)) }, neon: { system(NativeTheme.role(for: $0)) })
    }

    /// An NSColor class property by name; a loud pink if the name is not one (the unit tests check them all).
    private static func system(_ role: String) -> NSColor {
        (NSColor.perform(Selector(role))?.takeUnretainedValue() as? NSColor) ?? .systemPink
    }

    private init(appearance: Appearance, accentHue: Int, glowAlpha: Double, glows: Bool,
                 color c: (PaletteToken) -> NSColor, neon: @escaping (NeonHue) -> NSColor) {
        self.appearance = appearance; self.accentHue = accentHue
        bg = c(.bg); s1 = c(.s1); s2 = c(.s2); s3 = c(.s3); s4 = c(.s4)
        line = c(.line); line2 = c(.line2); outline = c(.outline)
        text = c(.text); text2 = c(.text2); muted = c(.muted); faint = c(.faint)
        accent = c(.accent); onAccent = c(.onAccent); accentSoft = c(.accentSoft); markFill = c(.markFill)
        selectionFill = c(.selectionFill); selectionInactive = c(.selectionInactive); selectedText = c(.selectedText)
        ok = c(.ok); part = c(.part); miss = c(.miss)
        pane = c(.pane); chrome = c(.chrome); side = c(.side); bar = c(.bar)
        pop = c(.pop); tray = c(.tray)
        field = c(.field); headBg = c(.headBg); rowLine = c(.rowLine); well = c(.well)
        segBg = c(.segBg); thumb = c(.thumb); scrim = c(.scrim)
        self.glowAlpha = glowAlpha; self.glows = glows
        self.neon = neon
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
    private var observing = false

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
        observeSystemColours()
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

    /// True when View > Theme is Native.
    var isNative: Bool { look == .native }

    /// Live preview while the hue slider moves: every window recolours, nothing is saved yet.
    func preview(hue: Int) {
        previewHue = Accent.normalized(Double(hue))
        refresh(force: false)
    }

    /// The system switched light and dark.
    func systemAppearanceMayHaveChanged() { refresh(force: false) }

    /// Native draws with the Mac's dynamic colours: they resolve by themselves, but views redraw when
    /// System Settings changes the accent or highlight colour, Increase Contrast or Reduce Transparency.
    private func observeSystemColours() {
        guard !observing else { return }
        observing = true
        let redraw: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { ThemeController.shared.systemColoursChanged() }
        }
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: redraw)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main, using: redraw)
        // An appearance change while no window is open has no view to report it.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ThemeController.shared.refresh(force: false) }
        }
    }

    private func systemColoursChanged() {
        guard look == .native else { return }
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let next = Theme.palette(systemIsDark ? .dark : .light, hue: previewHue ?? settings.hue)
        guard force || next != palette else { return }
        palette = next
        colors = look == .native ? ThemeColors.native(appearance: next.appearance) : ThemeColors(next)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
