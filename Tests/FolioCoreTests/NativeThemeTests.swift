import AppKit
import Testing
@testable import FolioCore

/// The Native look's colours: each palette token names one of the Mac's system colours (resolved when
/// drawn, so light, dark, Increase Contrast and the accent follow the Mac). docs/design/native.md.
@Suite struct NativeThemeTests {
    @Test func everyTokenHasANativeRole() {
        for token in PaletteToken.allCases {
            #expect(!NativeTheme.role(for: token).isEmpty, "no role for \(token)")
        }
    }

    @Test func textAndLinesUseTheLabelFamily() {
        #expect(NativeTheme.role(for: .text) == "labelColor")
        #expect(NativeTheme.role(for: .text2) == "secondaryLabelColor")
        #expect(NativeTheme.role(for: .muted) == "secondaryLabelColor")
        #expect(NativeTheme.role(for: .faint) == "tertiaryLabelColor")
        #expect(NativeTheme.role(for: .line) == "separatorColor")
    }

    @Test func accentAndSelectionFollowSystemSettings() {
        #expect(NativeTheme.role(for: .accent) == "controlAccentColor")
        #expect(NativeTheme.role(for: .accentSoft) == "keyboardFocusIndicatorColor")
        #expect(NativeTheme.role(for: .markFill) == "selectedTextBackgroundColor")
        #expect(NativeTheme.role(for: .selectionFill) == "selectedContentBackgroundColor")
        #expect(NativeTheme.role(for: .selectionInactive) == "unemphasizedSelectedContentBackgroundColor")
        #expect(NativeTheme.role(for: .selectedText) == "alternateSelectedControlTextColor")
        #expect(NativeTheme.role(for: .onAccent) == "alternateSelectedControlTextColor")
    }

    @Test func statusColoursAreTheSystemOnes() {
        #expect(NativeTheme.role(for: .ok) == "systemGreenColor")
        #expect(NativeTheme.role(for: .part) == "systemOrangeColor")
        #expect(NativeTheme.role(for: .miss) == "systemRedColor")
    }

    @Test func surfacesUseWindowAndControlBackgrounds() {
        #expect(NativeTheme.role(for: .bg) == "windowBackgroundColor")
        #expect(NativeTheme.role(for: .pane) == "controlBackgroundColor")
        #expect(NativeTheme.role(for: .rowLine) == "clearColor")
    }

    @Test func fileTypeHuesBecomeSystemColoursSoTagsMatchFinder() {
        // Finder's tag colours: red, orange, yellow, green, blue, purple (TagDots maps through these).
        #expect(NativeTheme.role(for: NeonHue.orange) == "systemOrangeColor")
        #expect(NativeTheme.role(for: NeonHue.gold) == "systemYellowColor")
        #expect(NativeTheme.role(for: NeonHue.blue) == "systemBlueColor")
        #expect(NativeTheme.role(for: NeonHue.violet) == "systemPurpleColor")
        for hue in NeonHue.allCases { #expect(NativeTheme.role(for: hue).hasPrefix("system")) }
    }

    /// Every role is a real NSColor class property, so the app can resolve it (runs no app code).
    @Test func everyRoleIsAnNSColor() {
        let roles = PaletteToken.allCases.map(NativeTheme.role(for:)) + NeonHue.allCases.map(NativeTheme.role(for:))
        for role in Set(roles) {
            #expect((NSColor.self as AnyObject).responds(to: Selector(role)), "NSColor has no \(role)")
        }
    }
}

/// D4's tokens by name: the same values the Palette's fields hold.
@Suite struct PaletteTokenTests {
    @Test func d4TokensReadTheirFields() {
        for appearance in [Appearance.dark, .light] {
            let p = Theme.palette(appearance)
            #expect(p.rgba(.text) == p.text)
            #expect(p.rgba(.accent) == p.accent)
            #expect(p.rgba(.scrim) == p.scrim)
            // The two tokens D4 does not have: its selection and its text, unchanged.
            #expect(p.rgba(.selectionInactive) == p.selectionFill)
            #expect(p.rgba(.selectedText) == p.text)
        }
    }

    @Test func thereIsOneTokenForEveryColourField() {
        #expect(PaletteToken.allCases.count == 35)
    }
}
