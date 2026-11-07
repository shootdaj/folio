import Foundation
import Testing
@testable import FolioCore

/// Token values come straight from the CSS variables in docs/design/d4-obsidian-spotlight.html
/// (tokens.css and the Folio app tokens under it).
@Suite struct ThemeTests {
    @Test func darkResolvesToTheD4DarkTokens() {
        let p = Theme.palette(.dark)
        #expect(p.appearance == .dark && p.accentHue == 262)
        #expect([p.bg, p.s1, p.s2, p.s3, p.s4].map(\.hex) == ["#08090C", "#0F1116", "#14171E", "#1B1F28", "#232834"])
        #expect([p.line, p.line2, p.outline].map(\.hex) == ["#1E222B", "#2A2F3A", "#3A4050"])
        #expect([p.text, p.text2, p.muted, p.faint].map(\.hex) == ["#EDEFF3", "#C3C8D2", "#8A919E", "#5C6370"])
        #expect(p.accent.hex == "#4F8CFF" && p.accent.a == 1)
        #expect(p.onAccent.hex == "#08090C")
        #expect(p.ok.hex == "#4ADE80" && p.part.hex == "#FFB443" && p.miss.hex == "#FF8A80")
        // --pane, --chrome and --side are the bg; --bar-solid is s1 78% over the bg.
        #expect(p.pane == p.bg && p.chrome == p.bg && p.side == p.bg)
        #expect(p.bar.hex == "#0D0F14")
        #expect(p.selectionFill == p.accent.withAlpha(0.15))
        #expect(p.markFill == p.accent.withAlpha(0.34))
        #expect(p.accentSoft == p.accent.withAlpha(0.18))
        #expect(p.rowLine == p.line.withAlpha(0.62))
        #expect(p.segBg == p.s1 && p.thumb == p.s3)
        #expect(p.glowAlpha == 0.16)
    }

    @Test func lightResolvesToTheD4LightTokens() {
        let p = Theme.palette(.light)
        #expect([p.bg, p.s1, p.s2, p.s3, p.s4].map(\.hex) == ["#F7F8FA", "#FFFFFF", "#EEF0F4", "#E4E7ED", "#D9DDE5"])
        #expect([p.line, p.line2, p.outline].map(\.hex) == ["#E1E4EA", "#CFD4DD", "#B9BFCB"])
        #expect([p.text, p.text2, p.muted, p.faint].map(\.hex) == ["#14171E", "#2E3440", "#5B6270", "#8A919E"])
        #expect(p.accent.hex == "#1F5FE0")
        #expect(p.onAccent.hex == "#FFFFFF")
        #expect(p.ok.hex == "#1B7F3F" && p.part.hex == "#9A5A00" && p.miss.hex == "#C0392B")
        // Light: the list on white, title and status bars on s2, the sidebar on the bg.
        #expect(p.pane == p.s1 && p.chrome == p.s2 && p.side == p.bg && p.bar == p.s1)
        #expect(p.field == p.bg)
        #expect(p.selectionFill == p.accent.withAlpha(0.11))
        #expect(p.markFill == p.accent.withAlpha(0.22))
        #expect(p.accentSoft == p.accent.withAlpha(0.12))
        #expect(p.rowLine == p.line.withAlpha(0.80))
        #expect(p.glowAlpha == 0.12)
    }

    @Test func theTwelveNeonHuesResolvePerTheme() {
        let dark = ["#4D9BFF", "#A98BFF", "#FFB443", "#2DD4BF", "#FF6BB5", "#FF6A3D",
                    "#5EC8E0", "#B8E63A", "#E8C547", "#FF8A80", "#4ADE80", "#E255FF"]
        let light = ["#1A5FE0", "#6B3FD6", "#9A5A00", "#0A7C70", "#C2187A", "#C43B0E",
                     "#0C6F8A", "#4C7A00", "#8A6500", "#C0392B", "#1B7F3F", "#A21CAF"]
        #expect(NeonHue.allCases.map(\.rawValue) == ["blue", "violet", "amber", "teal", "pink", "orange",
                                                     "cyan", "lime", "gold", "coral", "green", "magenta"])
        #expect(NeonHue.allCases.map { Theme.palette(.dark).hue($0).hex } == dark)
        #expect(NeonHue.allCases.map { Theme.palette(.light).hue($0).hex } == light)
    }

    @Test(arguments: [
        (145, "#32AD41", "#008700"),
        (295, "#9B75F3", "#7844D3"),
        (190, "#00B2AA", "#008B86"),
        (25, "#EC5955", "#C71124"),
    ])
    func anArbitraryHueResolvesInBothThemes(hue: Int, dark: String, light: String) {
        let d = Theme.palette(.dark, hue: hue), l = Theme.palette(.light, hue: hue)
        #expect(d.accentHue == hue && l.accentHue == hue)
        #expect(d.accent.hex == dark)
        #expect(l.accent.hex == light)
        // Everything accent-coloured follows: selection, halos, marks.
        #expect(d.selectionFill == d.accent.withAlpha(0.15) && l.selectionFill == l.accent.withAlpha(0.11))
        #expect(d.accentSoft == d.accent.withAlpha(0.18) && d.markFill == d.accent.withAlpha(0.34))
        // Folders take the accent; surfaces and the status colours stay put.
        #expect(d.typeHue(name: "docs", isFolder: true) == d.accent)
        #expect(d.bg.hex == "#08090C" && d.ok.hex == "#4ADE80" && l.miss.hex == "#C0392B")
    }

    @Test func theLightAccentIsTheSameHueAtALowerLightness() {
        for hue in stride(from: 0, to: 360, by: 15) {
            let d = Accent.lch(hue: hue, .dark), l = Accent.lch(hue: hue, .light)
            #expect(l.hue == d.hue, "hue \(hue)")
            #expect(l.lightness == 0.528 && d.lightness == 0.657, "hue \(hue)")
            #expect(l.chroma == 0.207 && d.chroma == 0.182, "hue \(hue)")
            // The deeper shade really is darker on screen.
            func luminance(_ c: RGBA) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
            #expect(luminance(Accent.color(hue: hue, .light)) < luminance(Accent.color(hue: hue, .dark)), "hue \(hue)")
        }
    }

    @Test func huesWrapToOneTurn() {
        #expect(Accent.normalized(262) == 262)
        #expect(Accent.normalized(622) == 262)
        #expect(Accent.normalized(-98) == 262)
        #expect(Accent.normalized(359.6) == 0)
        #expect(Accent.normalized(.nan) == Accent.defaultHue)
        #expect(Theme.palette(.dark, hue: 622) == Theme.palette(.dark, hue: 262))
    }

    @Test func thePickerOffersD4sEightPresets() {
        #expect(Accent.presets.map(\.name) == ["Electric blue", "Violet", "Magenta", "Red", "Orange", "Gold", "Green", "Teal"])
        #expect(Accent.presets.map(\.hue) == [262, 295, 330, 25, 55, 90, 145, 190])
        #expect(Accent.presets.first?.hue == Accent.defaultHue)
    }

    @Test func theSpringsOvershootAndSettle() {
        #expect(Motion.value(Motion.spring, at: 0) == 0)
        #expect(Motion.value(Motion.spring, at: 1) == 1)
        #expect(abs(Motion.value(Motion.spring, at: 0.187) - 1.05) < 1e-9)
        let peak = stride(from: 0.0, through: 1.0, by: 0.001).map { Motion.value(Motion.spring, at: $0) }.max() ?? 0
        #expect(abs(peak - 1.05) < 1e-9)
        let soft = stride(from: 0.0, through: 1.0, by: 0.001).map { Motion.value(Motion.springSoft, at: $0) }.max() ?? 0
        #expect(abs(soft - 1.01) < 1e-9)
        #expect(Motion.fast == 0.12 && Motion.standard == 0.22 && Motion.slow == 0.42)
    }

    @Test func hexParsingRoundTrips() {
        #expect(RGBA(hex: 0x4F8CFF).hex == "#4F8CFF")
        #expect(RGBA(20, 23, 30, 0.08).hex == "#14171E")
        #expect(RGBA(hex: 0x0F1116).mixed(0.78, with: RGBA(hex: 0x08090C)).hex == "#0D0F14")
    }
}

/// Each file type's icon hue, from D4's EXT_HUE (folders carry the accent).
@Suite struct TypeHueTests {
    @Test(arguments: [
        ("README.md", NeonHue.violet), ("report.css", .pink), ("index.ts", .cyan), ("report.js", .gold),
        ("build.mjs", .lime), ("package.json", .magenta), ("main.go", .teal), ("index.html", .orange),
    ])
    func d4sExtensionsTakeTheirHues(name: String, hue: NeonHue) {
        #expect(TypeHue.hue(name: name, isFolder: false) == hue)
    }

    @Test func folderHaveNoneAndTheRestAreCyan() {
        #expect(TypeHue.hue(name: "agent-expert", isFolder: true) == nil)
        #expect(TypeHue.hue(name: "notes.md", isFolder: true) == nil, "a folder named like a file is still a folder")
        #expect(TypeHue.hue(name: "Makefile", isFolder: false) == .cyan)
        #expect(TypeHue.hue(name: "data.qqq", isFolder: false) == .cyan)
        #expect(TypeHue.hue(name: "NOTES.MD", isFolder: false) == .violet, "extensions match in any case")
        #expect(TypeHue.hue(name: "photo.HEIC", isFolder: false) == .amber)
        #expect(TypeHue.hue(name: "song.mp3", isFolder: false) == .green)
        #expect(TypeHue.hue(name: "paper.pdf", isFolder: false) == .coral)
    }

    @Test func theIconColourIsTheHueInTheTheme() {
        let d = Theme.palette(.dark), l = Theme.palette(.light)
        #expect(d.typeHue(name: "a.md", isFolder: false).hex == "#A98BFF")
        #expect(l.typeHue(name: "a.md", isFolder: false).hex == "#6B3FD6")
        #expect(d.typeHue(name: "Code", isFolder: true).hex == "#4F8CFF")
        #expect(Theme.palette(.dark, hue: 145).typeHue(name: "Code", isFolder: true).hex == "#32AD41")
    }
}

/// Persistence goes through a real UserDefaults whose plist lives in a temp folder
/// (an absolute suite name), so tests never write into ~/Library/Preferences.
@Suite struct AccentSettingsTests {
    private func withTempDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/theme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let suite = dir.appendingPathComponent("prefs").path
        let defaults = try #require(UserDefaults(suiteName: suite))
        try body(defaults, suite)
    }

    @Test func defaultsToElectricBlue() throws {
        try withTempDefaults { defaults, _ in
            #expect(AccentSettings(defaults: defaults).hue == 262)
        }
    }

    @Test func theHuePersistsAsANumber() throws {
        try withTempDefaults { defaults, suite in
            let settings = AccentSettings(defaults: defaults)
            settings.hue = 145
            #expect((defaults.object(forKey: "accentHue") as? NSNumber)?.intValue == 145)
            // A fresh reader of the same store sees the saved hue.
            let again = AccentSettings(defaults: try #require(UserDefaults(suiteName: suite)))
            #expect(again.hue == 145)
            settings.hue = 400
            #expect(defaults.integer(forKey: "accentHue") == 40, "saved wrapped to one turn")
        }
    }

    @Test func unknownStoredValuesFallBackToTheDefault() throws {
        try withTempDefaults { defaults, _ in
            defaults.set("purple", forKey: "accentHue")
            #expect(AccentSettings(defaults: defaults).hue == 262)
            defaults.set(-30.4, forKey: "accentHue")
            #expect(AccentSettings(defaults: defaults).hue == 330)
        }
    }

    @Test func theRetiredThemeAndAccentKeysAreCleared() throws {
        try withTempDefaults { defaults, _ in
            defaults.set("light", forKey: "theme")
            defaults.set("amber", forKey: "accent")
            let settings = AccentSettings(defaults: defaults)
            settings.hue = 55
            settings.clearRetiredKeys()
            #expect(defaults.object(forKey: "theme") == nil)
            #expect(defaults.object(forKey: "accent") == nil)
            #expect(settings.hue == 55, "the hue stays")
        }
    }
}
