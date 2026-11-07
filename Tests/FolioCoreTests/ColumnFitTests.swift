import Foundation
import Testing
@testable import FolioCore

@Suite struct ColumnFitTests {
    /// Date 150 + Type 132 + Size 88, a 14 pt gap per column and D1's 7 pt right inset.
    private func fit(_ clip: Double) -> Double {
        ColumnFit.nameWidth(clipWidth: clip, otherWidths: [150, 132, 88], gap: 14, minimum: 120)
    }

    @Test func nameTakesWhatTheOtherColumnsLeave() {
        // 1440 pt window with an always-visible 15 pt scroller: the clip is 1131 pt wide.
        let name = fit(1131)
        #expect(name == 1131 - 370 - 56 - 7)
        #expect(name + 370 + 4 * 14 <= 1131)  // no horizontal overflow
    }

    @Test func overlayScrollersGiveNameTheFullWidth() {
        #expect(fit(1146) - fit(1131) == 15)
    }

    @Test func nameNeverDropsBelowItsMinimum() {
        #expect(fit(300) == 120)
    }

    @Test func fractionalWidthsRoundDownSoTheyStillFit() {
        let name = fit(1000.6)
        let want: Double = (1000.6 - 370 - 56 - 7).rounded(.down)  // typed, or Swift 6.3 times out on it
        #expect(name == want)
    }
}
