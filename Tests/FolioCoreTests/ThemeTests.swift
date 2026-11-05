import Foundation
import Testing
@testable import FolioCore

/// Token values come straight from the CSS variables in docs/design/d1-control-room.html.
@Suite struct ThemeTests {
    @Test func darkGreenMatchesTheD1DarkTokens() {
        let p = Theme.palette(.dark, accent: .green)
        #expect(p.bg.hex == "#0C0E11")
        #expect(p.s1.hex == "#111419")
        #expect(p.s2.hex == "#161A20")
        #expect(p.s3.hex == "#1B2028")
        #expect(p.txt.hex == "#C9D1DB")
        #expect(p.txt2.hex == "#9BA6B3")
        #expect(p.txt3.hex == "#838E9B")
        #expect(p.accent.hex == "#9BFF57")
        #expect(p.onAccent.hex == "#0C0E11")
        #expect(p.ok.hex == "#9BFF57")
        #expect(p.part.hex == "#FFB347")
        #expect(p.miss.hex == "#FF5C5C")
        #expect(p.line.hex == "#C9D1DB" && p.line.a == 0.10)
        #expect(p.line2.a == 0.17 && p.line3.a == 0.30)
        #expect(p.hudBg.hex == "#08090C")
        #expect(p.hudTxt.hex == "#C9D1DB")
        #expect(p.hudTxt2.hex == "#8E99A6")
        #expect(p.hudAccent.hex == "#9BFF57")
        #expect(p.foldBack.hex == "#262C35")
        #expect(p.foldFront.hex == "#343C48")
        #expect(p.foldLine.hex == "#5F6B79")
        #expect(p.fileBg.hex == "#1C2229")
        #expect(p.glows)
    }

    @Test func lightGreenMatchesTheD1LightTokens() {
        let p = Theme.palette(.light, accent: .green)
        #expect(p.bg.hex == "#F4F6F8")
        #expect(p.s1.hex == "#FFFFFF")
        #expect(p.s2.hex == "#F9FAFB")
        #expect(p.txt.hex == "#2A3441")
        #expect(p.txt3.hex == "#5B6672")
        #expect(p.accent.hex == "#2F7D1E")
        #expect(p.onAccent.hex == "#FFFFFF")
        #expect(p.miss.hex == "#C81E1E")
        #expect(p.line.hex == "#1C2C3E" && p.line.a == 0.11)
        #expect(p.foldBack.hex == "#D2DAE2")
        #expect(p.fileBg.hex == "#FFFFFF")
        // The HUD strip stays dark in the light theme and keeps the bright accent.
        #expect(p.hudBg.hex == "#1A1F26")
        #expect(p.hudAccent.hex == "#9BFF57")
        #expect(!p.glows)
    }

    @Test(arguments: [
        (AccentChoice.green, "#9BFF57", "#2F7D1E"),
        (AccentChoice.amber, "#FFB347", "#B45309"),
        (AccentChoice.cyan, "#5EC8E0", "#0E7490"),
    ])
    func everyAccentResolvesPerTheme(accent: AccentChoice, dark: String, light: String) {
        let d = Theme.palette(.dark, accent: accent)
        let l = Theme.palette(.light, accent: accent)
        #expect(d.accent.hex == dark)
        #expect(l.accent.hex == light)
        #expect(d.hudAccent.hex == dark)
        #expect(l.hudAccent.hex == dark)
        // Selection fill, brackets and the sidebar grid are mixes of the accent.
        #expect(d.selectionFill == d.accent.withAlpha(0.13))
        #expect(l.selectionFill == l.accent.withAlpha(0.12))
        #expect(d.bracket == d.accent.withAlpha(0.70))
        #expect(d.gridMajor == d.accent.withAlpha(0.08) && d.gridMinor == d.accent.withAlpha(0.036))
        #expect(l.gridMajor == l.accent.withAlpha(0.11) && l.gridMinor == l.accent.withAlpha(0.05))
        // Okay, partial and missing stay fixed whatever the accent.
        #expect(d.part.hex == "#FFB347" && l.part.hex == "#B45309")
    }

    @Test func themeChoiceFollowsTheSystemUnlessForced() {
        #expect(ThemeChoice.system.resolve(systemIsDark: true) == .dark)
        #expect(ThemeChoice.system.resolve(systemIsDark: false) == .light)
        #expect(ThemeChoice.dark.resolve(systemIsDark: false) == .dark)
        #expect(ThemeChoice.light.resolve(systemIsDark: true) == .light)
        #expect(ThemeChoice.allCases.map(\.title) == ["System", "Dark", "Light"])
        #expect(AccentChoice.allCases.map(\.title) == ["Green", "Amber", "Cyan"])
    }

    @Test func hexParsingRoundTrips() {
        #expect(RGBA(hex: 0x9BFF57).hex == "#9BFF57")
        #expect(RGBA(201, 209, 219, 0.1).hex == "#C9D1DB")
    }
}

/// Persistence goes through a real UserDefaults whose plist lives in a temp folder
/// (an absolute suite name), so tests never write into ~/Library/Preferences.
@Suite struct ThemeSettingsTests {
    private func withTempDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/theme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let suite = dir.appendingPathComponent("prefs").path
        let defaults = try #require(UserDefaults(suiteName: suite))
        try body(defaults, suite)
    }

    @Test func defaultsToSystemThemeAndGreenAccent() throws {
        try withTempDefaults { defaults, _ in
            let settings = ThemeSettings(defaults: defaults)
            #expect(settings.theme == .system)
            #expect(settings.accent == .green)
        }
    }

    @Test func choicesPersistUnderThemeAndAccentKeys() throws {
        try withTempDefaults { defaults, suite in
            var settings = ThemeSettings(defaults: defaults)
            settings.theme = .light
            settings.accent = .cyan
            #expect(defaults.string(forKey: "theme") == "light")
            #expect(defaults.string(forKey: "accent") == "cyan")
            // A fresh reader of the same store sees the saved choice.
            let again = ThemeSettings(defaults: try #require(UserDefaults(suiteName: suite)))
            #expect(again.theme == .light)
            #expect(again.accent == .cyan)
        }
    }

    @Test func unknownStoredValuesFallBackToDefaults() throws {
        try withTempDefaults { defaults, _ in
            defaults.set("purple", forKey: "theme")
            defaults.set("magenta", forKey: "accent")
            let settings = ThemeSettings(defaults: defaults)
            #expect(settings.theme == .system)
            #expect(settings.accent == .green)
        }
    }
}
