import Foundation

/// The words of the Suggestions page: card titles and reason lines.
public enum SuggestionText {
    public static func title(_ kind: SuggestionKind) -> String {
        switch kind {
        case .trash: "Trash"
        case .largeUnused: "Large files you have not used"
        case .duplicates: "Duplicate files"
        case .oldDownloads: "Old downloads"
        case .installers: "Installers"
        case .appCaches: "App caches"
        case .derivedData: "Xcode build data"
        case .buildFolders: "Build folders"
        case .emptyFolders: "Empty folders"
        case .brokenLinks: "Broken links"
        }
    }

    /// The size as Finder writes it.
    public static func size(_ bytes: Int64) -> String { ByteText.storage(bytes) }

    /// "Not opened since 3 Mar 2026", "2 copies, keep 1". The locale and time zone make the dates the same on every Mac in a test.
    public static func reason(_ reason: SuggestionReason, locale: Locale = Locale(identifier: "en_US"),
                              timeZone: TimeZone = .current) -> String {
        func day(_ date: Date) -> String { DateFormats.day(date, locale: locale, timeZone: timeZone) }
        switch reason {
        case .notUsedSince(let date, let source):
            let verb = source == .lastUsed || source == .accessed ? "opened" : "changed"
            return "Not \(verb) since \(day(date))"
        case .inDownloadsSince(let date):
            return "In Downloads since \(day(date))"
        case .installer(let ext, let since):
            let name = ext.lowercased() == "zip" ? "ZIP archive" : ext.uppercased() + " installer"
            return "\(name), added \(day(since))"
        case .sameContent(let copies, _, let share):
            return "\(copies) copies, keep 1" + (share ? ", may share space" : "")
        case .trash(let items):
            return items == 1 ? "1 item in the Trash" : "\(ByteText.grouped(items)) items in the Trash"
        case .cache(let appID):
            return "Cache of \(appID)"
        case .derivedData(let projects):
            return projects == 1 ? "1 Xcode project" : "\(ByteText.grouped(projects)) Xcode projects"
        case .buildFolder(let name, let idle):
            return "\(name), project not changed since \(day(idle))"
        case .emptyFolder:
            return "Empty folder"
        case .brokenLink(let target):
            return "Points to \(target), which is missing"
        }
    }

    public static func reason(_ suggestion: Suggestion, locale: Locale = Locale(identifier: "en_US"),
                              timeZone: TimeZone = .current) -> String {
        reason(suggestion.reason, locale: locale, timeZone: timeZone)
    }
}

/// Formatters kept by locale and time zone: a page asks for hundreds of dates.
private enum DateFormats {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    static func day(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let key = locale.identifier + "|" + timeZone.identifier
        return lock.withLock {
            let f: DateFormatter
            if let hit = cache[key] {
                f = hit
            } else {
                f = DateFormatter()
                f.locale = locale
                f.timeZone = timeZone
                f.dateFormat = "d MMM yyyy"
                cache[key] = f
            }
            return f.string(from: date)
        }
    }
}
