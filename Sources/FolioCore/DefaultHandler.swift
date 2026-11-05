import Foundation

/// Launch Services' default handlers, behind a protocol so the report can be tested without changing
/// the Mac's settings. The app's registry calls LSSetDefaultRoleHandlerForContentType and
/// LSCopyDefaultRoleHandlerForContentType.
public protocol HandlerRegistry {
    func defaultHandler(for contentType: String) -> String?
    /// An OSStatus: 0 when macOS took the request (it may still keep its own choice; read it back).
    func setDefaultHandler(_ bundleID: String, for contentType: String) -> Int32
}

/// What happened to one content type: what was asked, what macOS said, what it reports now.
public struct HandlerLine: Equatable, Sendable {
    public let contentType: String
    public let title: String
    public let asked: String
    public let status: Int32
    public let now: String?

    public var accepted: Bool { now?.lowercased() == asked.lowercased() }
}

public struct FolderHandlerReport: Equatable, Sendable {
    public let turnedOn: Bool
    public let lines: [HandlerLine]

    public var allAccepted: Bool { lines.allSatisfy(\.accepted) }

    public var headline: String {
        let target = turnedOn ? "Folio" : "Finder"
        if allAccepted { return turnedOn ? "macOS now opens folders and drives in Folio" : "macOS opens folders and drives in Finder again" }
        if lines.allSatisfy({ !$0.accepted }) {
            return turnedOn ? "macOS kept Finder for folders and drives" : "macOS kept Folio for folders and drives"
        }
        let yes = lines.filter(\.accepted).map { $0.title.lowercased() }.joined(separator: " and ")
        let no = lines.filter { !$0.accepted }.map { $0.title.lowercased() }.joined(separator: " and ")
        return "macOS opens \(yes) in \(target) but kept \(no) on another app"
    }

    /// One line per type, read back from Launch Services after asking.
    public var details: String {
        lines.map { l in
            let head = "\(l.title) (\(l.contentType)): "
            if l.accepted { return head + DefaultFolderHandler.appName(l.now) }
            let error = l.status == 0 ? "" : ", error \(l.status)"
            let now = l.now.map { DefaultFolderHandler.appName($0) == $0 ? $0 : "\(DefaultFolderHandler.appName($0)) (\($0))" } ?? "no app"
            return head + "asked for \(DefaultFolderHandler.appName(l.asked)), macOS still reports \(now)\(error)"
        }.joined(separator: "\n")
    }

    public var note: String { DefaultFolderHandler.revealNote }
}

/// Folder Options > General: "Open folders in Folio instead of Finder".
public enum DefaultFolderHandler {
    public static let finder = "com.apple.finder"
    /// Folders, and drives (a volume's root is a public.volume).
    public static let contentTypes: [(type: String, title: String)] = [("public.folder", "Folders"), ("public.volume", "Drives")]

    public static let revealNote = """
        macOS keeps "Reveal in Finder" and "Show in Finder" from other apps on Finder: those commands \
        call Finder by name, whatever the default for folders is. Folders opened with `open`, from \
        Spotlight or from an app's Open command follow the setting. For a reveal in Folio use \
        `ff --reveal <path>`.
        """

    public static func appName(_ bundleID: String?) -> String {
        switch bundleID?.lowercased() {
        case nil: "no app"
        case "com.apple.finder": "Finder"
        case "com.anshul.folio": "Folio"
        default: bundleID ?? "no app"
        }
    }

    /// Whether macOS reports Folio for folders now.
    public static func isFolio(bundleID: String, registry: HandlerRegistry) -> Bool {
        registry.defaultHandler(for: contentTypes[0].type)?.lowercased() == bundleID.lowercased()
    }

    /// On: Folio for folders and drives. Off: Finder again. Each is read back, so the report says what
    /// macOS kept, not what was asked.
    public static func apply(on: Bool, bundleID: String, registry: HandlerRegistry) -> FolderHandlerReport {
        let target = on ? bundleID : finder
        let lines = contentTypes.map { t in
            let status = registry.setDefaultHandler(target, for: t.type)
            return HandlerLine(contentType: t.type, title: t.title, asked: target, status: status,
                               now: registry.defaultHandler(for: t.type))
        }
        return FolderHandlerReport(turnedOn: on, lines: lines)
    }
}
