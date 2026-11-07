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
