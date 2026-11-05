import Foundation
import UniformTypeIdentifiers

/// One of your own Send to targets: a folder (items are copied there) or an app (items open with it).
public struct SendTarget: Sendable, Equatable {
    public let name: String
    public let url: URL
    public let isApp: Bool

    public init(name: String, url: URL, isApp: Bool) {
        self.name = name
        self.url = url
        self.isApp = isApp
    }
}

/// Explorer's shell:sendto: whatever sits in Folio's Send To folder (folders, apps, or aliases and links
/// to them) becomes a Send to entry.
public enum SendTo {
    /// `~/Library/Application Support/Folio/Send To`.
    public static func folder(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Folio/Send To", isDirectory: true)
    }

    public static func targets(in folder: URL) -> [SendTarget] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.compactMap { item -> SendTarget? in
            let target = Aliases.kind(of: item) == nil ? item : Aliases.resolve(item)
            guard let target else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return SendTarget(name: item.lastPathComponent, url: target, isApp: DropRules.isApp(target))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Print: PDFs, text and images go straight to the default printer with lp (CUPS reads them all);
/// other documents are handed to their app's print command.
public enum PrintRoute: Sendable, Equatable {
    case lp, app

    public static func route(for url: URL) -> PrintRoute {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .app }
        return type.conforms(to: .pdf) || type.conforms(to: .plainText) || type.conforms(to: .image) ? .lp : .app
    }

    public static func lpArguments(_ urls: [URL]) -> [String] { ["--"] + urls.map(\.path) }
}

/// Typing a command instead of a path, as in Explorer's address bar: cmd, powershell, wt or terminal
/// opens Terminal in the current folder; notepad, calc or any app name launches that app.
public enum AddressCommand: Sendable, Equatable {
    case terminal
    case app(String)

    private static let terminals: Set<String> = ["cmd", "terminal", "wt", "powershell", "pwsh", "bash", "zsh", "sh", "shell"]
    private static let windowsApps: [String: String] = [
        "notepad": "TextEdit", "calc": "Calculator", "mspaint": "Preview", "control": "System Settings",
        "explorer": "Folio", "taskmgr": "Activity Monitor", "write": "TextEdit",
    ]

    /// Nil for anything that looks like a path, or more than one word.
    public static func parse(_ text: String) -> AddressCommand? {
        let word = text.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !word.contains("/"), !word.hasPrefix("~"), !word.contains(" ") else { return nil }
        let lower = word.lowercased().replacingOccurrences(of: ".exe", with: "")
        if terminals.contains(lower) { return .terminal }
        if let mapped = windowsApps[lower] { return .app(mapped) }
        return .app(word)
    }

    /// `<name>.app` in the given folders or one level below them, matched ignoring case.
    public static func findApp(named name: String, in folders: [URL]) -> URL? {
        let want = name.lowercased() + ".app"
        let fm = FileManager.default
        for folder in folders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let hit = items.first(where: { $0.lastPathComponent.lowercased() == want }) { return hit }
            for sub in items where sub.pathExtension.isEmpty {
                let inner = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? []
                if let hit = inner.first(where: { $0.lastPathComponent.lowercased() == want }) { return hit }
            }
        }
        return nil
    }

    public static let appFolders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                                    "/System/Library/CoreServices/Applications"].map { URL(fileURLWithPath: $0) }
}
