import Foundation
import Testing
@testable import FolioCore

/// The sort's own comparison gives the same order as `localizedStandardCompare`, which Finder uses.
@Suite struct StandardOrderTests {
    static let names = [
        "File2", "File10", "file1", "FILE1", "file01", "File 1", "File-1", "File_1", "file.1", "a", "A", "á", "Ä", "ä",
        "Zebra", "zebra", "ﬁle", "ｆｉｌｅ", "file", "日本", "にほん", "Ångström", "angstrom", "100", "20", "2", "02",
        "IMG_0001.jpg", "IMG_0010.jpg", "IMG_10.jpg", ".hidden", "_under", "-dash", "#hash", "~tilde", "Ünïcödé", "unicode",
        "résumé", "resume", "Resume", "x1y2", "x1y10", "x01y2", "😀", "emoji", "", " space", "tab\tname", "Straße", "strasse",
    ]

    @Test func everyPairComparesAsLocalizedStandardCompare() {
        let order = StandardOrder()
        for a in Self.names {
            for b in Self.names {
                let want: Int = switch a.localizedStandardCompare(b) {
                case .orderedAscending: -1
                case .orderedDescending: 1
                case .orderedSame: 0
                }
                #expect(order.compare(StandardOrder.key(a), StandardOrder.key(b)) == want, "\(a) vs \(b)")
            }
        }
    }
}
