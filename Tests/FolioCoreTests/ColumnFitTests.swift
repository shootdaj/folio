import Foundation
import Testing
@testable import FolioCore

@Suite struct ColumnFitTests {
    /// D4's grid: Date 148 + Type 128 + Size 76 (168, 148 and 96 with their 10 pt padding each side), a
    /// 20 pt gap per column and the 44 pt right gutter.
    private func fit(_ clip: Double) -> Double {
        ColumnFit.nameWidth(clipWidth: clip, otherWidths: [148, 128, 76], gap: 20, trailing: 44, minimum: 120)
    }

    @Test func nameTakesWhatTheOtherColumnsLeave() {
        // A 1440 pt window with the 248 pt sidebar: the list is 1192 pt wide.
        let name = fit(1192)
        #expect(name == 1192 - 352 - 80 - 44)
        #expect(name + 352 + 4 * 20 + 44 <= 1192)  // no horizontal overflow
        // D4's Date column starts 14 + 722 pt in: Name's 716 plus its 20 pt of padding.
        #expect(name + 20 == 736)
    }

    @Test func alwaysVisibleScrollersTakeTheirWidthFromName() {
        #expect(fit(1192) - fit(1177) == 15)
    }

    @Test func nameNeverDropsBelowItsMinimum() {
        #expect(fit(300) == 120)
    }

    @Test func fractionalWidthsRoundDownSoTheyStillFit() {
        let name = fit(1000.6)
        #expect(name == (1000.6 - 352 - 80 - 44).rounded(.down))
    }
}
