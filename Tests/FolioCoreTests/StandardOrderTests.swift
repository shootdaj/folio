import Foundation
import Testing
@testable import FolioCore

/// The sort's own comparison gives the same order as `localizedStandardCompare`, which Finder uses, and
/// the sort built on it lists items exactly as the sort before it did.
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

    /// The sort as it was, comparing Swift strings with `localizedStandardCompare` each time.
    private func reference(_ entries: [FileEntry], _ spec: SortSpec, folders: FolderPlacement) -> [FileEntry] {
        let terms = spec.terms
        let up = spec.ascending
        return entries.map { e in (e, terms.map { ColumnValues.value(e, $0.key, nil) }) }.sorted { a, b in
            let (ea, eb) = (a.0, b.0)
            if ea.isFolder != eb.isFolder {
                switch folders {
                case .followSort: return up ? ea.isFolder : eb.isFolder
                case .filesFirst: return eb.isFolder
                }
            }
            for (i, term) in terms.enumerated() {
                let c = ColumnValue.compare(a.1[i], b.1[i])
                if c != 0 { return term.ascending ? c < 0 : c > 0 }
            }
            switch ea.name.localizedStandardCompare(eb.name) {
            case .orderedAscending: return up
            case .orderedDescending: return !up
            case .orderedSame: return up ? ea.url.path < eb.url.path : ea.url.path > eb.url.path
            }
        }.map(\.0)
    }

    @Test func theSortListsItemsAsTheSortBeforeIt() {
        let kinds = ["PNG image", "Plain Text", "Folder", "PDF document", "png image"]
        var entries: [FileEntry] = []
        for (i, name) in (Self.names + Self.names.map { $0 + " copy" }).enumerated() {
            let folder = i % 7 == 0
            entries.append(FileEntry(url: URL(fileURLWithPath: "/private/tmp/folio-tests/sort/\(i)/\(name)"), name: name, isFolder: folder,
                                     modified: i % 5 == 0 ? nil : Date(timeIntervalSince1970: Double((i * 7919) % 50)),
                                     size: folder ? nil : Int64((i * 31) % 9), kind: folder ? "Folder" : kinds[i % kinds.count]))
        }
        let specs = [SortSpec.standard, SortSpec(key: .name, ascending: false), SortSpec(key: .kind, ascending: true),
                     SortSpec(key: .size, ascending: false), SortSpec(key: .modified, ascending: true),
                     SortSpec(key: .kind, ascending: true, then: [SortTerm(key: .size, ascending: false)]),
                     SortSpec(key: .modified, ascending: false, then: [SortTerm(key: .kind, ascending: true), SortTerm(key: .name, ascending: false)])]
        for spec in specs {
            for folders in [FolderPlacement.followSort, .filesFirst] {
                #expect(SortEngine.sort(entries, by: spec, folders: folders).map(\.url) == reference(entries, spec, folders: folders).map(\.url),
                        "\(spec) \(folders)")
            }
        }
    }

    @Test func aListLargeEnoughToSortInPartsComesOutTheSame() {
        // Over the parallel threshold, with ties everywhere: few sizes, few dates, the same names in
        // several folders (the path decides), folders mixed in, and names with no number.
        var rng = SystemRandomNumberGenerator()
        let words = ["File", "file", "Report", "IMG_", "résumé", "track ", "ｆｉｌｅ", "Zeta", "alpha", ""]
        var entries: [FileEntry] = []
        for i in 0..<(SortEngine.parallelThreshold * 2 + 777) {
            let name = words[i % words.count] + (i % 3 == 0 ? "" : String(Int.random(in: 0..<500, using: &rng)))
            let folder = i % 13 == 0
            entries.append(FileEntry(url: URL(fileURLWithPath: "/private/tmp/folio-tests/big/\(i % 4)/\(name)"), name: name, isFolder: folder,
                                     modified: i % 7 == 0 ? nil : Date(timeIntervalSince1970: Double(Int.random(in: 0..<20, using: &rng))),
                                     size: folder ? nil : Int64(Int.random(in: 0..<30, using: &rng)), kind: ["PNG image", "Plain Text", "Folder"][i % 3]))
        }
        for spec in [SortSpec.standard, SortSpec(key: .size, ascending: false), SortSpec(key: .modified, ascending: true),
                     SortSpec(key: .kind, ascending: false, then: [SortTerm(key: .size, ascending: true)])] {
            let mine = SortEngine.sort(entries, by: spec).map(\.url)
            #expect(mine == reference(entries, spec, folders: .followSort).map(\.url), "\(spec)")
        }
        #expect(SortEngine.sort(entries, by: .standard, folders: .filesFirst).map(\.url)
                == reference(entries, .standard, folders: .filesFirst).map(\.url))
    }
}
