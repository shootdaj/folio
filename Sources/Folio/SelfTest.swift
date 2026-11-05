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
