import Foundation

/// A folder name that is a build folder when its marker file sits beside it.
public struct BuildFolderRule: Sendable, Hashable {
    public let name: String
    /// A sibling file that proves the folder is a build folder (nil: the name alone).
    public let marker: String?

    public init(_ name: String, marker: String?) {
        self.name = name
        self.marker = marker
    }
}

/// Every threshold, floor, budget and clock of a scan. `home` and `now` are injected, so a test or a
/// fixture scans a fake home and no rule reads the real one.
public struct SuggestionConfig: Sendable {
    public var home: URL
    /// Every age rule compares to this date.
    public var now: Date
    /// The clock for the budgets, in seconds. Tests give a fake one.
    public var elapsed: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    public var kinds: Set<SuggestionKind> = Set(SuggestionKind.allCases)

    public var largeFileMin: Int64 = 500_000_000
    public var unusedFor: TimeInterval = 180 * 86_400
    /// Downloads entries are old after this, by the date added.
    public var downloadsOldAfter: TimeInterval = 60 * 86_400
    public var installerOldAfter: TimeInterval = 14 * 86_400
    public var installerExts: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
    /// These count only directly in Downloads and Desktop.
    public var archiveExtsInDropFolders: Set<String> = ["zip"]

    public var duplicateMin: Int64 = 1_000_000
    public var cacheMin: Int64 = 50_000_000
    public var buildFolderMin: Int64 = 20_000_000
    public var projectIdleFor: TimeInterval = 30 * 86_400
    public var emptyFolderMinAge: TimeInterval = 7 * 86_400

    /// Folders under home. A trailing `/*` makes one card for each child.
    public var cachePlaces = ["Library/Caches/*", ".npm/_cacache", ".cache"]
    public var cacheExcludedPrefixes = ["com.apple.", "com.anshul.folio"]
    public var derivedData = "Library/Developer/Xcode/DerivedData"
    public var buildFolders: [BuildFolderRule] = [
        BuildFolderRule("node_modules", marker: nil), BuildFolderRule(".build", marker: "Package.swift"),
        BuildFolderRule("target", marker: "Cargo.toml"), BuildFolderRule("Pods", marker: "Podfile"),
    ]
    /// Folders that apps manage. Their files are counted and never offered as loose files.
    public var managedMedia = ["Music/Music", "Music/iTunes", "Movies/TV", "Pictures"]
    /// Never offered as empty.
    public var standardFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Sites", "Applications"]

    public var timeBudget: TimeInterval = 90
    public var maxEntries = 3_000_000
    public var maxDepth = 64
    public var hashBudgetBytes: Int64 = 8_000_000_000
    public var hashTimeBudget: TimeInterval = 45
    public var maxSpotlightLookups = 2_000
    public var maxAliasResolves = 2_000
    public var maxPerKind = 500

    /// When Folio hashed a file, by file. A file read by Folio gets a new access date, so an access date at
    /// or after this time is Folio's own read and does not count as use.
    public var hashedAt: [FileID: Date] = [:]

    public init(home: URL, now: Date) {
        self.home = home
        self.now = now
    }

    /// Floors a fixture can meet: a large file is 48 `unit`s, the other floors are 1 `unit`.
    public static func uitest(home: URL, now: Date, unit: Int64) -> SuggestionConfig {
        var c = SuggestionConfig(home: home, now: now)
        c.largeFileMin = 48 * unit
        c.duplicateMin = unit
        c.cacheMin = unit
        c.buildFolderMin = unit
        return c
    }
}
