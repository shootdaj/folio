import Foundation
import Testing
@testable import FolioCore

/// The real scanner on the VM fixture, with the VM's rules scaled down. The VM shot checks the same set,
/// so a broken fixture or a changed rule shows up here, on the host.
@Suite struct SuggestionFixtureContractTests {
    @Test func theScannerFindsExactlyTheExpectedSet() throws {
        let run = URL(fileURLWithPath: "/private/tmp/folio-tests/contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.trashItem(at: run, resultingItemURL: nil) }
        let home = run.appendingPathComponent("Home", isDirectory: true)
        let now = Date()
        try UITestFixture.makeCleanupSamples(at: home, unit: 1024, now: now)

        let config = SuggestionConfig.uitest(home: home, now: now, unit: 1024)
        let report = SuggestionScanner(config: config, ignores: .init()).collect()

        var found: [SuggestionKind: [String]] = [:]
        let prefix = home.path + "/"
        for s in report.suggestions {
            for item in s.items {
                #expect(item.url.path.hasPrefix(prefix))
                found[s.kind, default: []].append(String(item.url.path.dropFirst(prefix.count)))
            }
        }
        var expected: [SuggestionKind: [String]] = [:]
        for e in UITestFixture.cleanupExpected { expected[e.kind] = e.paths }
        for kind in SuggestionKind.allCases {
            #expect(found[kind, default: []].sorted() == expected[kind, default: []].sorted(), "\(kind)")
        }
        #expect(report.suggestions.filter { $0.kind == .duplicates }.count == 1)
        #expect(report.suggestions.first { $0.kind == .trash }.map { $0.bytes > 0 } == true)
        #expect(!report.suggestions.contains { $0.items.contains { $0.url.path.contains("Tool.app/") || $0.url.path.contains("Library/Preferences") } })
        #expect(!report.suggestions.contains { $0.items.contains { $0.url.lastPathComponent == "new-edit.mov" || $0.url.lastPathComponent.hasPrefix("notes-") } })
    }
}
