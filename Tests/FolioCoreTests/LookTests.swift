import Foundation
import Testing
@testable import FolioCore

/// The look: Native (the Mac's own styles, the default) or D4 Obsidian (the ported design), saved
/// under `lookTheme` and offered in View > Theme.
@Suite struct LookSettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/look-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    @Test func defaultsToNative() throws {
        try withDefaults { d in #expect(LookSettings(defaults: d).look == .native) }
    }

    @Test func theChoicePersistsUnderLookTheme() throws {
        try withDefaults { d in
            LookSettings(defaults: d).look = .obsidian
            #expect(d.string(forKey: "lookTheme") == "obsidian")
            #expect(LookSettings(defaults: d).look == .obsidian)
            LookSettings(defaults: d).look = .native
            #expect(LookSettings(defaults: d).look == .native)
        }
    }

    @Test func unknownValuesFallBackToNative() throws {
        try withDefaults { d in
            d.set("solarized", forKey: LookSettings.key)
            #expect(LookSettings(defaults: d).look == .native)
            d.set(7, forKey: LookSettings.key)
            #expect(LookSettings(defaults: d).look == .native)
        }
    }

    @Test func clearingTheRetiredThemeKeyKeepsTheLook() throws {
        try withDefaults { d in
            #expect(!AccentSettings.retiredKeys.contains(LookSettings.key))
            LookSettings(defaults: d).look = .obsidian
            d.set("dark", forKey: "theme")
            AccentSettings(defaults: d).clearRetiredKeys()
            #expect(d.object(forKey: "theme") == nil)
            #expect(LookSettings(defaults: d).look == .obsidian)
        }
    }
}

@Suite struct LookThemeTests {
    @Test func menuOrderAndTitles() {
        #expect(LookTheme.allCases == [.native, .obsidian])
        #expect(LookTheme.allCases.map(\.title) == ["Native", "D4 Obsidian"])
    }

    @Test func onlyObsidianShowsTheAccentSwatch() {
        // Native takes the accent from System Settings > Appearance.
        #expect(LookTheme.obsidian.showsAccentSwatch)
        #expect(!LookTheme.native.showsAccentSwatch)
    }
}

/// The look's type: D4 writes its labels in uppercase mono with tracking; Native keeps the words as
/// written in SF Pro, untracked (docs/design/native.md, Type).
@Suite struct LookTypeTests {
    @Test func obsidianLabelsAreUppercaseAndTracked() {
        #expect(LookTheme.obsidian.caption("Date modified") == "DATE MODIFIED")
        #expect(LookTheme.obsidian.labelKern(12) == 12 * 0.12)
        #expect(LookTheme.obsidian.headKern(12) == 12 * 0.08)
    }

    @Test func nativeLabelsKeepTheirCaseUntracked() {
        #expect(LookTheme.native.caption("Date modified") == "Date modified")
        #expect(LookTheme.native.labelKern(12) == 0)
        #expect(LookTheme.native.headKern(12) == 0)
    }

    @Test func onlyNativeUsesTheSystemFont() {
        #expect(LookTheme.native.usesSystemFont)
        #expect(!LookTheme.obsidian.usesSystemFont)
    }

    @Test func cssWeightsMapToSystemWeights() {
        #expect(SystemWeight(css: 400) == .regular)
        #expect(SystemWeight(css: 500) == .regular)
        #expect(SystemWeight(css: 600) == .semibold)
        #expect(SystemWeight(css: 650) == .semibold)
        #expect(SystemWeight(css: 700) == .bold)
        #expect(SystemWeight(css: 800) == .bold)
    }
}
