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

/// `Folio --bench <folder> [runs]`: times each step of opening the folder outside the UI (the listing,
/// the arrange with its item keys, the drive figures, the tree's reads, the search walk), so a change to
/// one of them can be measured on its own. Each step runs `runs` times (5 by default); it prints the
/// fastest and the middle time in milliseconds. It refuses to run outside a virtual machine: like every
/// other run of Folio it belongs in the test VM (docs/plan/RULES.md, rule 0). Tests/vm/perf.sh runs it.
enum Bench {
    static var inVirtualMachine: Bool {
        var on: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &on, &size, nil, 0) == 0 && on == 1
    }

    static func run(_ args: [String]) -> Int32 {
        guard inVirtualMachine else {
            print("bench: refusing to run outside the test VM (docs/plan/RULES.md, rule 0)")
            return 2
        }
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
        var bySize = key
        bySize.sort = SortSpec(key: .size, ascending: false)
        time("list", runs) { _ = try? FolderListing.list(folder) }
        time("arrange: name (keys too)", runs) { _ = BrowserWindowController.arrange(rows, key) }
        time("arrange: size (keys too)", runs) { _ = BrowserWindowController.arrange(rows, bySize) }
        time("item keys", runs) { _ = FilePaths.itemKeys(rows.map(\.url)) }
        time("volume figures", runs) { _ = VolumeCapacity.read(folder) }
        time("tree: this folder", runs) { _ = FolderTree.subfolders(of: folder.path) }
        time("tree: every folder from /", runs) { for p in chain { _ = FolderTree.subfolders(of: p) } }
        // The live search walk over the folder and everything below it, for a word no name holds.
        if let query = try? SearchQuery.parse("zqxzqx") {
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
        print("  " + label.padding(toLength: 28, withPad: " ", startingAt: 0)
              + String(format: " min %9.2f ms   median %9.2f ms", ms[0], ms[ms.count / 2]))
    }
}
