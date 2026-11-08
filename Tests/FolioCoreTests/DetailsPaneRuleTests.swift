import Testing
@testable import FolioCore

/// Native's Details pane follows the selection; D4's stays until it is closed.
@Suite struct DetailsPaneRuleTests {
    @Test func nativeShowsThePaneOnlyWhileItemsAreSelected() {
        #expect(!DetailsPaneRule.shows(chosen: true, followsSelection: true, selectedCount: 0, isSpecial: false))
        #expect(DetailsPaneRule.shows(chosen: true, followsSelection: true, selectedCount: 1, isSpecial: false))
        #expect(DetailsPaneRule.shows(chosen: true, followsSelection: true, selectedCount: 12, isSpecial: false),
                "several items show a summary")
    }

    @Test func turnedOffOrOnHomeItNeverShows() {
        #expect(!DetailsPaneRule.shows(chosen: false, followsSelection: true, selectedCount: 3, isSpecial: false))
        #expect(!DetailsPaneRule.shows(chosen: true, followsSelection: true, selectedCount: 3, isSpecial: true))
        #expect(!DetailsPaneRule.shows(chosen: true, followsSelection: false, selectedCount: 3, isSpecial: true))
    }

    @Test func d4KeepsThePaneWithNothingSelected() {
        #expect(DetailsPaneRule.shows(chosen: true, followsSelection: false, selectedCount: 0, isSpecial: false))
    }
}
