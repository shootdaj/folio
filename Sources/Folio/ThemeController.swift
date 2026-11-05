import AppKit
import FolioCore

extension RGBA {
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension Palette {
    /// The palette every view draws with: the saved theme resolved against the system, plus the accent.
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

/// Owns the theme and accent choice (UserDefaults keys `theme` and `accent`) and the resolved palette.
/// Theme System leaves `NSApp.appearance` nil so the app follows the Mac's light or dark setting.
@MainActor
final class ThemeController {
    static let shared = ThemeController()
    static let didChange = Notification.Name("FolioThemeDidChange")

    private var settings = ThemeSettings(defaults: .standard)
    private(set) var palette = Theme.palette(.dark, accent: .green)

    private init() {}

    /// Called once at launch, before any window. `defaults` is a temp store under `--uitest`.
    func start(defaults: UserDefaults) {
        settings = ThemeSettings(defaults: defaults)
        apply()
    }

    var theme: ThemeChoice {
        get { settings.theme }
        set { settings.theme = newValue; apply() }
    }

    var accent: AccentChoice {
        get { settings.accent }
        set { settings.accent = newValue; refresh(force: true) }
    }

    /// The system switched light and dark (only matters while the theme is System).
    func systemAppearanceMayHaveChanged() { refresh(force: false) }

    private func apply() {
        switch settings.theme {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let next = Theme.palette(settings.theme.resolve(systemIsDark: systemIsDark), accent: settings.accent)
        guard force || next != palette else { return }
        palette = next
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
