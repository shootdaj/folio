import Foundation
import FolioCore

/// `Folio --selftest <folder>`: lists the folder through the same listing + sort call the window
/// uses, prints the row count, the first 5 names and the elapsed time, and exits without any UI.
enum SelfTest {
    static func run(_ path: String?) -> Int32 {
        guard let path else {
            print("usage: Folio --selftest <folder>")
            return 2
        }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let started = Date()
        do {
            let rows = try FolderListing.list(folder, sortedBy: .standard)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("selftest \(folder.path): \(rows.count) rows in \(ms) ms")
            print("first 5: " + rows.prefix(5).map(\.name).joined(separator: ", "))
            return 0
        } catch {
            print("selftest failed: \(error.localizedDescription)")
            return 1
        }
    }
}

/// `Folio --bench <folder> [runs]`: times each step of opening the folder outside the UI, so a change to
/// the listing, the sort, the item keys, the drive figures or the tree can be measured. Each step runs
/// `runs` times (5 by default); it prints the fastest and the middle time in milliseconds.
enum Bench {
    static func run(_ args: [String]) -> Int32 {
        guard let path = args.first else {
            print("usage: Folio --bench <folder> [runs]")
            return 2
        }
        let runs = args.dropFirst().first.flatMap(Int.init) ?? 5
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        guard let rows = try? FolderListing.list(folder) else {
            print("bench: cannot list \(folder.path)")
            return 1
        }
        let chain = FolderTree.chain(from: "/", to: folder.path) ?? [folder.path]
        print("bench \(folder.path): \(rows.count) items, \(FolderTree.subfolders(of: folder.path).count) subfolders, "
              + "\(chain.count) folders from /, \(runs) runs")
        let key = BrowserWindowController.ArrangeKey(filters: FilterSet(), sort: .standard, group: nil, collapsed: [])
        time("list", runs) { _ = try? FolderListing.list(folder) }
        time("arrange (name sort, keys)", runs) { _ = BrowserWindowController.arrange(rows, key) }
        time("item keys", runs) { _ = FilePaths.itemKeys(rows.map(\.url)) }
        time("volume figures", runs) { _ = VolumeCapacity.read(folder) }
        time("tree: this folder", runs) { _ = FolderTree.subfolders(of: folder.path) }
        time("tree: every folder from /", runs) { for p in chain { _ = FolderTree.subfolders(of: p) } }
        // The live search walk over the folder and everything below it, for a word few names hold.
        if let query = try? SearchQuery.parse("zqx") {
            let walk = SearchWalk(roots: [folder], matcher: SearchMatcher(query), options: SearchWalk.Options())
            time("search walk (all below)", max(1, runs / 2)) { walk.run(isCancelled: { false }, onBatch: { _, _ in }) }
        }
        return 0
    }

    private static func time(_ label: String, _ runs: Int, _ body: () -> Void) {
        var ms: [Double] = []
        for _ in 0..<max(1, runs) {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            ms.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        ms.sort()
        print("  " + label.padding(toLength: 28, withPad: " ", startingAt: 0) + String(format: " min %8.2f ms   median %8.2f ms", ms[0], ms[ms.count / 2]))
    }
}
