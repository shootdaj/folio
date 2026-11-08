import Darwin
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

    // MARK: The clean-up samples

    /// One path of the Suggestions fixture, under the fake home.
    public struct CleanupSample: Sendable {
        public enum Kind: Sendable {
            /// A file of `units` times the unit, every byte `fill`.
            case file(units: Int, fill: UInt8)
            /// A small file of exactly `count` bytes.
            case bytes(count: Int, fill: UInt8)
            case folder
            /// A symbolic link to a path under the fake home.
            case link(to: String)
        }

        public let path: String
        public let kind: Kind
        /// "yyyy-MM-dd HH:mm", or "-1d" for that many days before `now`. The added, modified and access dates all get it.
        public let date: String
    }

    /// What the scanner must offer for the samples: the paths of each kind, relative to the fake home.
    /// The VM shot and the host contract test check this same set.
    public struct CleanupExpectation: Sendable {
        public let kind: SuggestionKind
        public let paths: [String]
    }

    /// The date of every folder the samples make. It is old, so no folder looks new to a rule.
    private static let cleanupFolderDate = "2025-01-01 00:00"

    /// Every sample has a decoy that must not show. Same-size files have different fills, so only the real pair is a duplicate.
    public static let cleanupSamples: [CleanupSample] = [
        .init(path: "Movies/old-trip-4k.mov", kind: .file(units: 64, fill: 0x11), date: "2024-03-10 00:00"),
        .init(path: "Documents/archive/backup-2023.zip", kind: .file(units: 56, fill: 0x12), date: "2023-11-02 00:00"),
        // Decoy: big, but used yesterday.
        .init(path: "Movies/new-edit.mov", kind: .file(units: 64, fill: 0x13), date: "-1d"),
        .init(path: "Downloads/Install Tool 2.1.dmg", kind: .file(units: 40, fill: 0x21), date: "2025-06-01 00:00"),
        .init(path: "Downloads/setup-helper.pkg", kind: .file(units: 12, fill: 0x22), date: "2025-02-14 00:00"),
        .init(path: "Downloads/receipt-2024.pdf", kind: .file(units: 1, fill: 0x23), date: "2024-08-20 00:00"),
        .init(path: "Documents/report-final.mov", kind: .file(units: 24, fill: 0x5A), date: "2025-09-01 00:00"),
        .init(path: "Desktop/report-final copy.mov", kind: .file(units: 24, fill: 0x5A), date: "2025-09-03 00:00"),
        // Decoy: the same size as the pair, different content.
        .init(path: "Documents/notes-a.bin", kind: .file(units: 24, fill: 0x5B), date: "2025-09-01 00:00"),
        .init(path: "Desktop/notes-b.bin", kind: .file(units: 24, fill: 0x5C), date: "2025-09-01 00:00"),
        .init(path: "Code/web-app/package.json", kind: .bytes(count: 200, fill: 0x7B), date: "2025-04-01 00:00"),
        .init(path: "Code/web-app/node_modules/left-pad/index.js", kind: .file(units: 4, fill: 0x31), date: "2025-04-01 00:00"),
        .init(path: "Library/Developer/Xcode/DerivedData/WebApp-abc123/Build/a.o", kind: .file(units: 16, fill: 0x32), date: "2025-04-01 00:00"),
        .init(path: "Library/Caches/com.example.editor/Cache.db", kind: .file(units: 8, fill: 0x33), date: "2025-04-01 00:00"),
        // Decoy: Library/Preferences is never offered.
        .init(path: "Library/Preferences/com.example.plist", kind: .bytes(count: 150, fill: 0x3C), date: "2025-04-01 00:00"),
        // Decoy: a big file inside an app.
        .init(path: "Applications/Tool.app/Contents/Resources/big.bin", kind: .file(units: 60, fill: 0x41), date: "2023-01-05 00:00"),
        .init(path: "Documents/Empty Project", kind: .folder, date: "2025-01-01 00:00"),
        .init(path: "Desktop/Old Shortcut", kind: .link(to: "Documents/moved-away.txt"), date: "2025-01-01 00:00"),
        .init(path: ".Trash/old-draft.mov", kind: .file(units: 30, fill: 0x51), date: "2025-05-01 00:00"),
        .init(path: ".Trash/notes.txt", kind: .bytes(count: 120, fill: 0x52), date: "2025-05-01 00:00"),
    ]

    public static let cleanupExpected: [CleanupExpectation] = [
        .init(kind: .trash, paths: [".Trash"]),
        .init(kind: .largeUnused, paths: ["Movies/old-trip-4k.mov", "Documents/archive/backup-2023.zip"]),
        .init(kind: .duplicates, paths: ["Documents/report-final.mov", "Desktop/report-final copy.mov"]),
        .init(kind: .oldDownloads, paths: ["Downloads/receipt-2024.pdf"]),
        .init(kind: .installers, paths: ["Downloads/Install Tool 2.1.dmg", "Downloads/setup-helper.pkg"]),
        .init(kind: .appCaches, paths: ["Library/Caches/com.example.editor"]),
        .init(kind: .derivedData, paths: ["Library/Developer/Xcode/DerivedData"]),
        .init(kind: .buildFolders, paths: ["Code/web-app/node_modules"]),
        .init(kind: .emptyFolders, paths: ["Documents/Empty Project"]),
        .init(kind: .brokenLinks, paths: ["Desktop/Old Shortcut"]),
    ]

    /// Makes the clean-up samples with real bytes under `root`, which must sit under a test root, and returns it.
    /// A `unit` is 1 MiB, or less in a test. Every file gets all its dates after all the writes, the deepest
    /// first, and the folders last, because a write changes the date of the folder it is in.
    @discardableResult
    public static func makeCleanupSamples(at root: URL, unit: Int = 1 << 20, now: Date = Date()) throws -> URL {
        guard isAllowed(root) else { throw FixtureError.notATestRoot(root.path) }
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func parse(_ text: String) -> Date? {
            if text.hasPrefix("-"), text.hasSuffix("d"), let days = Double(text.dropFirst().dropLast()) {
                return now.addingTimeInterval(-days * 86_400)
            }
            return formatter.date(from: text)
        }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var folders: Set<String> = [root.path]
        var dated: [(path: String, date: String)] = []
        for sample in cleanupSamples {
            let url = root.appendingPathComponent(sample.path)
            var parent = url.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            while parent.path.count > root.path.count {
                folders.insert(parent.path)
                parent = parent.deletingLastPathComponent()
            }
            switch sample.kind {
            case .file(let units, let fill):
                try write(url, count: units * unit, fill: fill)
                dated.append((url.path, sample.date))
            case .bytes(let count, let fill):
                try write(url, count: count, fill: fill)
                dated.append((url.path, sample.date))
            case .folder:
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                folders.insert(url.path)
            case .link(let target):
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: root.appendingPathComponent(target).path)
                dated.append((url.path, sample.date))
            }
        }
        for sample in cleanupSamples {
            if case .folder = sample.kind { folders.insert(root.appendingPathComponent(sample.path).path) }
        }
        let folderDate = parse(cleanupFolderDate)
        // Files and links first, the deepest first, then the folders, the deepest first.
        for item in dated.sorted(by: { $0.path.count > $1.path.count }) {
            guard let date = parse(item.date) else { continue }
            try setDates(item.path, to: date)
        }
        if let folderDate {
            for path in folders.sorted(by: { $0.count > $1.count }) { try setDates(path, to: folderDate) }
        }
        return root
    }

    private static func write(_ url: URL, count: Int, fill: UInt8) throws {
        // A reused 1 MiB buffer, so a large sample is not held in memory twice.
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let chunk = Data(repeating: fill, count: min(count, 1 << 20))
        var left = count
        while left > 0 {
            try handle.write(contentsOf: left >= chunk.count ? chunk : chunk.prefix(left))
            left -= min(left, chunk.count)
        }
    }

    /// Sets the modified, access and added dates of the path itself, a link too, with one `setattrlist`.
    private static func setDates(_ path: String, to date: Date) throws {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_MODTIME | ATTR_CMN_ACCTIME | ATTR_CMN_ADDEDTIME)
        let seconds = date.timeIntervalSince1970
        let stamp = timespec(tv_sec: Int(seconds.rounded(.down)), tv_nsec: 0)
        // The attributes are packed in this order: modified, accessed, added.
        var values = [stamp, stamp, stamp]
        let size = MemoryLayout<timespec>.size * values.count
        guard setattrlist(path, &request, &values, size, UInt32(FSOPT_NOFOLLOW)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
        }
    }
}
