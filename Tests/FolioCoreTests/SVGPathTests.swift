import CoreGraphics
import Foundation
import Testing
@testable import FolioCore

private func near(_ a: CGPoint, _ x: Double, _ y: Double) -> Bool {
    abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9
}

private func endPoint(_ e: SVGPath.Element) -> CGPoint? {
    switch e {
    case .move(let p), .line(let p): p
    case .curve(_, _, let p): p
    case .close: nil
    }
}

@Suite struct SVGPathTests {
    @Test func absoluteAndRelativeLinesWithImplicitRepeats() {
        // D1's Back arrow: "M19 12H5" and "m12 19-7-7 7-7".
        #expect(SVGPath.parse("M19 12H5") == [.move(CGPoint(x: 19, y: 12)), .line(CGPoint(x: 5, y: 12))])
        #expect(SVGPath.parse("m12 19-7-7 7-7") == [
            .move(CGPoint(x: 12, y: 19)), .line(CGPoint(x: 5, y: 12)), .line(CGPoint(x: 12, y: 5)),
        ])
    }

    @Test func packedNumbersAndClose() throws {
        // From the star: "l5.9.9-4.25 4.1" packs ".9" and "-4.25" without spaces.
        let els = SVGPath.parse("M3 3l5.9.9-4.25 4.1z")
        #expect(els.count == 4)
        #expect(near(try #require(endPoint(els[1])), 8.9, 3.9))
        #expect(near(try #require(endPoint(els[2])), 4.65, 8))
        #expect(els[3] == .close)
    }

    @Test func horizontalVerticalAndArcsEndWhereTheyShould() throws {
        let els = SVGPath.parse("M1.5 3a1 1 0 0 1 1-1h4.8l1.7 2h8.5a1 1 0 0 1 1 1v8.5")
        let last = try #require(els.last)
        #expect(near(try #require(endPoint(last)), 18.5, 13.5))
        // A quarter arc becomes one cubic ending at the arc's end point.
        guard case .curve(_, _, let end) = els[1] else { Issue.record("expected a curve"); return }
        #expect(near(end, 2.5, 2))
    }

    @Test func largeArcsSplitIntoQuarterCurves() {
        // Moon: a 270-degree arc from (21,12) back near (12,3).
        let els = SVGPath.parse("M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z")
        let curves = els.filter { if case .curve = $0 { true } else { false } }
        #expect(curves.count >= 4)
        #expect(els.last == .close)
    }
}
