import AppKit
import FolioCore

extension RGBA {
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension Palette {
    /// The palette every view draws with: the Mac's light or dark setting, plus the accent hue.
    @MainActor static var current: Palette { ThemeController.shared.palette }
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
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
