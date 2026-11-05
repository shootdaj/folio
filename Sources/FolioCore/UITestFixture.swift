import Foundation

/// The folder `Folio --uitest new` browses: 40 folders and 8 files with fixed names, sizes and dates
/// (the first 28 folders are D1's sample rows). It is only ever made under a test root.
public enum UITestFixture {
    /// Where `--uitest` may point: test folders and the scratch volume, never a real folder.
    public static let allowedRoots = ["/private/tmp/folio-tests/", "/tmp/folio-tests/", "/Volumes/FolioScratch/"]

    public static func isAllowed(_ url: URL) -> Bool {
        let path = "/" + Breadcrumbs.components(of: url.path).joined(separator: "/") + "/"
        return allowedRoots.contains { path.hasPrefix($0) && path.count > $0.count }
    }

    public static let folders: [(name: String, modified: String)] = [
        ("agent-expert", "2026-05-22 21:28"), ("agent-expert-tests", "2025-12-21 06:25"),
        ("ai-crypto-alpha", "2026-09-26 08:18"), ("ai-harness", "2026-09-08 22:59"),
        ("ai-video-editing", "2026-09-26 08:18"), ("alldebrid-streaming-setup", "2026-04-27 03:27"),
        ("anshul-portfolio", "2026-09-26 08:18"), ("apple-knowledge-base", "2026-03-28 02:19"),
        ("automator", "2025-08-14 19:31"), ("ax", "2026-03-10 14:56"),
        ("ax-test-crm", "2026-09-26 08:18"), ("ax-test-crm2", "2026-09-26 08:18"),
        ("ax-test-dash2", "2026-09-26 08:18"), ("ax-test-dashboard", "2026-09-26 08:18"),
        ("ax-test-expenses", "2026-09-08 23:00"), ("ax-test-flags", "2026-09-26 08:18"),
        ("ax-test-flagsmith2", "2026-09-26 08:18"), ("ax-test-habits", "2026-09-26 08:18"),
        ("ax-test-inventory", "2026-07-21 04:03"), ("ax-test-linkpreview", "2026-09-26 08:18"),
        ("ax-test-music", "2026-03-18 19:14"), ("ax-test-music2", "2026-07-21 04:03"),
        ("ax-test-palette", "2026-09-26 08:18"), ("ax-test-polls", "2026-09-26 08:18"),
        ("ax-test-projtrack", "2026-09-26 08:18"), ("ax-test-recipes", "2026-09-08 23:00"),
        ("ax-test-snippets", "2026-09-26 08:18"), ("bench-notes", "2026-10-02 17:40"),
        ("camera-roll-2026", "2026-08-30 12:05"), ("dotfiles", "2026-06-11 09:12"),
        ("edc-th-dec-2026", "2026-10-30 22:03"), ("folio", "2026-11-05 11:26"),
        ("invoices-2026", "2026-10-01 08:00"), ("luminatlas", "2026-10-25 12:37"),
        ("luminatlas-fixtures", "2026-10-14 09:08"), ("make-clone-street-fighter-zero-2", "2026-11-03 21:21"),
        ("music-rig", "2026-09-19 23:44"), ("photo-sorter", "2026-02-07 15:30"),
        ("trip-planner", "2026-10-29 18:16"), ("zz-archive", "2024-12-31 23:59"),
    ]

    public static let files: [(name: String, bytes: Int, modified: String)] = [
        ("airbnb-bangkok-search.md", 3917, "2026-01-09 08:42"), ("README.md", 1210, "2026-10-12 10:15"),
        ("notes.txt", 640, "2026-11-01 07:58"), ("index.html", 5400, "2026-10-20 16:03"),
        ("styles.css", 2100, "2026-10-20 16:04"), ("build.py", 880, "2026-09-02 13:27"),
        ("data.json", 15399, "2026-10-30 22:03"), ("main.go", 3721, "2026-10-25 12:37"),
    ]

    public enum FixtureError: Error { case notATestRoot(String) }

    /// Makes the fixture at `folder` (which must sit under a test root) and returns it.
    @discardableResult
    public static func make(at folder: URL) throws -> URL {
        guard isAllowed(folder) else { throw FixtureError.notATestRoot(folder.path) }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for (name, modified) in folders {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            if let date = formatter.date(from: modified) { try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        }
        for (name, bytes, modified) in files {
            let url = folder.appendingPathComponent(name)
            try Data(repeating: 0x2E, count: bytes).write(to: url)
            if let date = formatter.date(from: modified) { try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        }
        return folder
    }
}
