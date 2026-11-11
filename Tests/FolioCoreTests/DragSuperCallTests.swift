import AppKit
import Foundation
import Testing

/// `draggingEnded(_:)` is optional in NSDraggingDestination. NSTableView and NSOutlineView do not implement it, so
/// `super.draggingEnded` there throws "unrecognized selector" inside the system's drag completion. The drag then
/// never ends for the window server, and Mission Control stops working until Folio quits (2026-11-08).
/// This test reads the app's sources: each `super.draggingEnded` must be in a class whose AppKit base has the method.
@Suite struct DragSuperCallTests {
    private static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Folio")

    @Test func superDraggingEndedOnlyWhereAppKitHasIt() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let declaration = try Regex(#"^\s*(?:(?:final|private|fileprivate|public|internal|@\w+)\s+)*class\s+(\w+)\s*:\s*(\w+)"#)
        var parent: [String: String] = [:]
        var texts: [(URL, [Substring])] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                if let m = try declaration.firstMatch(in: line), let name = m[1].substring, let base = m[2].substring {
                    parent[String(name)] = String(base)
                }
            }
            texts.append((file, lines))
        }
        func appKitBase(_ name: String) -> String {
            var current = name
            for _ in 0..<10 { guard let next = parent[current] else { break }; current = next }
            return current
        }
        var bad: [String] = []
        var checked = 0
        for (file, lines) in texts {
            var owner: String?
            for (i, line) in lines.enumerated() {
                if let m = try declaration.firstMatch(in: line), let name = m[1].substring { owner = String(name) }
                guard line.contains("super.draggingEnded(") else { continue }
                checked += 1
                let base = owner.map(appKitBase) ?? "?"
                let responds = NSClassFromString(base)?.instancesRespond(to: NSSelectorFromString("draggingEnded:")) ?? false
                if !responds { bad.append("\(file.lastPathComponent):\(i + 1) (\(owner ?? "?") from \(base))") }
            }
        }
        #expect(checked > 0, "the grid view calls super.draggingEnded on NSCollectionView, which has it")
        #expect(bad.isEmpty, "super.draggingEnded where AppKit does not implement it: \(bad)")
    }
}
