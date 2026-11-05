import Foundation
import Testing
@testable import FolioCore

/// What the address bar does with typed or pasted text, before anything touches the disk.
@Suite struct AddressInputTests {
    private let env = AddressEnvironment(
        home: URL(fileURLWithPath: "/Users/someone", isDirectory: true),
        temp: URL(fileURLWithPath: "/private/var/folders/xy/T", isDirectory: true),
        variables: ["HOME": "/Users/someone", "PROJECT": "/private/tmp/proj", "USER": "someone"])
    private let current = URL(fileURLWithPath: "/private/tmp/run", isDirectory: true)

    private func resolved(_ text: String) -> String? {
        AddressInput.resolve(text, current: current, env: env)?.path
    }

    @Test func tildeIsHome() {
        #expect(resolved("~") == "/Users/someone")
        #expect(resolved("~/") == "/Users/someone")
        #expect(resolved("~/Downloads") == "/Users/someone/Downloads")
        #expect(resolved("~/../../private/tmp") == "/private/tmp")
    }

    @Test func trailingAndDoubledSlashesAreFine() {
        #expect(resolved("/private/tmp/") == "/private/tmp")
        #expect(resolved("/private//tmp///run/") == "/private/tmp/run")
        #expect(resolved("  /private/tmp  ") == "/private/tmp")
    }

    @Test func quotesAroundAPastedPathAreDropped() {
        #expect(resolved("\"/private/tmp/a b\"") == "/private/tmp/a b")
        #expect(resolved("'~/Code'") == "/Users/someone/Code")
        #expect(resolved("\u{201C}/private/tmp\u{201D}") == "/private/tmp")
        // A quote inside a name is part of the name.
        #expect(resolved("/private/tmp/it's") == "/private/tmp/it's")
    }

    @Test func windowsVariablesMapToMacPlaces() {
        #expect(resolved("%userprofile%") == "/Users/someone")
        #expect(resolved("%USERPROFILE%/Desktop") == "/Users/someone/Desktop")
        #expect(resolved("%AppData%") == "/Users/someone/Library/Application Support")
        #expect(resolved("%localappdata%") == "/Users/someone/Library")
        #expect(resolved("%temp%") == "/private/var/folders/xy/T")
        #expect(resolved("%TMP%/x") == "/private/var/folders/xy/T/x")
        #expect(resolved("%homedrive%%homepath%") == "/Users/someone")
        // Anything else is looked up in the environment, and left alone when unknown.
        #expect(resolved("%PROJECT%/src") == "/private/tmp/proj/src")
        #expect(resolved("/private/tmp/%nope%") == "/private/tmp/%nope%")
    }

    @Test func shellVariablesExpand() {
        #expect(resolved("$HOME/Code") == "/Users/someone/Code")
        #expect(resolved("${HOME}/Code") == "/Users/someone/Code")
        #expect(resolved("$TMPDIR") == "/private/var/folders/xy/T")
        #expect(resolved("$PROJECT/sub") == "/private/tmp/proj/sub")
        #expect(resolved("/private/tmp/$NOPE") == "/private/tmp/$NOPE")
    }

    @Test func shellFoldersMapToMacPlaces() {
        #expect(resolved("shell:downloads") == "/Users/someone/Downloads")
        #expect(resolved("shell:Desktop") == "/Users/someone/Desktop")
        #expect(resolved("shell:personal") == "/Users/someone/Documents")
        #expect(resolved("shell:My Pictures") == "/Users/someone/Pictures")
        #expect(resolved("shell:profile") == "/Users/someone")
        #expect(resolved("shell:appsfolder") == "/Applications")
        #expect(resolved("shell:RecycleBinFolder") == "/Users/someone/.Trash")
        #expect(resolved("shell:startup") == "/Users/someone/Library/LaunchAgents")
        #expect(resolved("shell:appdata") == "/Users/someone/Library/Application Support")
        #expect(resolved("shell:downloads/sub/") == "/Users/someone/Downloads/sub")
    }

    @Test func windowsOnlyShellFoldersAreIgnored() {
        #expect(resolved("shell:sendto") == nil)
        #expect(resolved("shell:quick launch") == nil)
        #expect(resolved("shell:") == nil)
    }

    @Test func relativePathsStartAtTheCurrentFolder() {
        #expect(resolved("sub/inner") == "/private/tmp/run/sub/inner")
        #expect(resolved("..") == "/private/tmp")
        #expect(resolved("./x/") == "/private/tmp/run/x")
    }

    @Test func emptyTextMeansNothing() {
        #expect(resolved("") == nil)
        #expect(resolved("   ") == nil)
        #expect(resolved("\"\"") == nil)
    }

    @Test func expandKeepsTheTrailingSlashForTheCompleter() {
        #expect(AddressInput.expand("~/Code/", env: env) == "/Users/someone/Code/")
        #expect(AddressInput.expand("\"%temp%/a\"", env: env) == "/private/var/folders/xy/T/a")
        #expect(AddressInput.expand("rel/a", env: env) == "rel/a")
    }
}
