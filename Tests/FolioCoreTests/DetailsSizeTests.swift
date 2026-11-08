import Testing
@testable import FolioCore

/// View > Details Size: text, icon and row grow together, Small is the list as it always was.
@Suite struct DetailsSizeTests {
    @Test func smallIsTheListAsItWas() {
        let s = DetailsSize.small
        #expect(s.textSize == 13 && s.iconSize == 16 && s.textDelta == 0)
        #expect(s.rowHeight(native: true, compact: false) == 24)
        #expect(s.rowHeight(native: true, compact: true) == 20)
        #expect(s.rowHeight(native: false, compact: false) == 26)
        #expect(s.rowHeight(native: false, compact: true) == 22)
    }

    @Test func eachStepIsLargerInEveryMeasure() {
        let all = DetailsSize.allCases
        for (a, b) in zip(all, all.dropFirst()) {
            #expect(a.textSize < b.textSize && a.iconSize < b.iconSize && a.nativeRowHeight < b.nativeRowHeight)
            // The icon and the text always fit the row with room to spare.
            #expect(b.iconSize + 4 <= b.rowHeight(native: true, compact: true))
        }
    }

    @Test func biggerAndSmallerStepOnceAndStopAtTheEnds() {
        #expect(DetailsSize.small.bigger == .medium)
        #expect(DetailsSize.large.bigger == .extraLarge)
        #expect(DetailsSize.extraLarge.bigger == .extraLarge)
        #expect(DetailsSize.medium.smaller == .small)
        #expect(DetailsSize.small.smaller == .small)
    }
}
