import Foundation

/// Every control of Folder Options as one list, so the dialog's search box can find a setting on any tab.
/// The General and Search tabs build their controls from these entries, and the View tab from `viewRows`,
/// so a title is written in one place only.
extension FolderOptions {
    public struct Entry: Sendable, Equatable {
        public enum Control: Sendable, Equatable {
            case check(Setting)
            case radio(Setting)
            /// A row that means nothing on a Mac: shown greyed.
            case unavailable
            /// The three boxes that change macOS itself at once, not on OK.
            case openFoldersInFolio, revealInFolio, launchAtLogin
            /// Privacy's Clear button.
            case clearHistory
        }

        public let tab: Tab
        /// The group box or the Advanced settings heading the control sits under.
        public let group: String
        public let title: String
        public let control: Control
        /// The tooltip.
        public let note: String?
        /// Other words for the setting, which the search also matches ("dot files" for hidden items).
        public let keywords: [String]

        init(_ tab: Tab, _ group: String, _ title: String, _ control: Control, note: String? = nil) {
            self.tab = tab
            self.group = group
            self.title = title
            self.control = control
            self.note = note
            keywords = FolderOptions.keywords(control)
        }

        /// Where the setting is, as the results list shows it: "View > Hidden files and folders".
        public var place: String { "\(tab.rawValue) > \(group)" }
    }

    public static let generalEntries: [Entry] = [
        Entry(.general, "Open Folio to", "Home", .radio(.openToHome)),
        Entry(.general, "Open Folio to", "This PC (the startup disk)", .radio(.openToThisPC)),
        Entry(.general, "Browse folders", "Open each folder in the same window", .radio(.sameWindow)),
        Entry(.general, "Browse folders", "Open each folder in its own window", .radio(.ownWindow)),
        Entry(.general, "Click items as follows", "Single-click to open an item (point to select)", .radio(.singleClick)),
        Entry(.general, "Click items as follows", "Underline icon titles consistent with my browser", .radio(.underlineAlways)),
        Entry(.general, "Click items as follows", "Underline icon titles only when I point at them", .radio(.underlineHover)),
        Entry(.general, "Click items as follows", "Double-click to open an item (single-click to select)", .radio(.doubleClick)),
        Entry(.general, "Privacy", "Show recently used files", .check(.showRecentFiles)),
        Entry(.general, "Privacy", "Show frequently used folders", .check(.showFrequentFolders)),
        Entry(.general, "Privacy", "Clear recent files, folders, addresses", .clearHistory),
        Entry(.general, "Folio and macOS", "Open folders in Folio instead of Finder", .openFoldersInFolio,
              note: "Asks macOS to open folders and drives in Folio, then says what macOS kept"),
        Entry(.general, "Folio and macOS", "Reveal in Folio instead of Finder", .revealInFolio,
              note: "\"Reveal in Finder\" and \"Show in Finder\" in other apps show the item in Folio (the NSFileViewer setting)"),
        Entry(.general, "Folio and macOS", "Open external folder links in a new tab", .check(.externalFoldersInNewTab),
              note: "Folders from ff and other apps open as a tab in the front window"),
        Entry(.general, "Folio and macOS", "Reopen windows and tabs on relaunch", .check(.reopenWindows)),
        Entry(.general, "Folio and macOS", "Keep running when the last window closes", .check(.keepRunning), note: "Cmd+Q still quits"),
        Entry(.general, "Folio and macOS", "Launch Folio at login", .launchAtLogin,
              note: "Adds Folio to your login items (System Settings > General > Login Items)"),
    ]

    public static let searchEntries: [Entry] = [
        Entry(.search, "How to search",
              "Don't use the index when searching in file folders for system files (searches might take longer)",
              .check(.dontUseIndex), note: "Spotlight is left out; the live walk covers everything"),
        Entry(.search, "When searching non-indexed locations", "Include system directories", .check(.includeSystemDirectories)),
        Entry(.search, "When searching non-indexed locations", "Include compressed files (ZIP)", .check(.includeCompressedFiles),
              note: "Looks inside zips, as Search options > Zipped folders"),
        Entry(.search, "When searching non-indexed locations",
              "Always search file names and contents (this might take several minutes)", .check(.alwaysSearchContents)),
    ]

    /// The View tab's Advanced settings, without the headings. A row under a sub-heading (the two radios
    /// of "Hidden files and folders") takes that heading as its group, the others the section's heading.
    public static let viewEntries: [Entry] = {
        var section = "", sub = "", out: [Entry] = []
        for row in viewRows {
            if row.kind == .heading {
                if row.indent == 0 { section = row.title } else { sub = row.title }
                continue
            }
            let group = row.indent >= 2 ? sub : section
            let control: Entry.Control
            switch (row.kind, row.setting) {
            case (.radio, let s?): control = .radio(s)
            case (_, let s?): control = .check(s)
            default: control = .unavailable
            }
            out.append(Entry(.view, group, row.title, control, note: control == .unavailable ? nil : row.note))
        }
        return out
    }()

    public static let entries: [Entry] = generalEntries + viewEntries + searchEntries

    /// The entry of one control, for the tabs that build from the list.
    public static func entry(_ control: Entry.Control) -> Entry? { entries.first { $0.control == control } }

    /// The entries that match every word of `query` at the start of a word, in the title, the group, the
    /// tab's name, the tooltip or the keywords. Entries with every word in the title come first; each part
    /// keeps the dialog's order. An empty query matches nothing.
    public static func search(_ query: String) -> [Entry] {
        let words = SettingsText.words(query)
        guard !words.isEmpty else { return [] }
        func matches(_ text: [String]) -> Bool { words.allSatisfy { w in text.contains { $0.hasPrefix(w) } } }
        var inTitle: [Entry] = [], elsewhere: [Entry] = []
        for e in entries {
            let title = SettingsText.words(e.title)
            if matches(title) { inTitle.append(e); continue }
            let all = title + SettingsText.words([e.group, e.tab.rawValue, e.note ?? ""].joined(separator: " "))
                + e.keywords.flatMap(SettingsText.words)
            if matches(all) { elsewhere.append(e) }
        }
        return inTitle + elsewhere
    }

    static func keywords(_ control: Entry.Control) -> [String] {
        switch control {
        case .radio(.hiddenOn), .radio(.hiddenOff): ["dot files", "invisible", "show all files"]
        case .check(.hideProtectedOSFiles): ["system files", "dot files"]
        case .check(.hideExtensions): ["file name extensions", "suffix"]
        case .check(.alwaysShowIcons), .check(.fileIconOnThumbnails): ["thumbnails", "previews"]
        case .check(.fullPathInTitleBar): ["window title"]
        case .check(.confirmDelete): ["Trash", "Recycle Bin", "warning", "ask"]
        case .check(.useCheckBoxes): ["checkboxes", "select"]
        case .check(.showStatusBar): ["item count"]
        case .check(.showPopupDescriptions): ["tooltips", "info tips"]
        case .check(.hideEmptyDrives), .check(.showDriveLetters): ["volumes", "disks"]
        case .radio(.typingSearchBox), .radio(.typingSelect): ["type ahead", "keyboard"]
        case .check(.expandToOpenFolder), .check(.showAllFolders), .check(.showNetwork), .check(.showThisPC):
            ["tree", "sidebar"]
        case .check(.navPaneShowHidden): ["tree", "sidebar", "dot files", "invisible"]
        case .radio(.openToHome), .radio(.openToThisPC): ["start", "new window", "startup folder"]
        case .radio(.sameWindow), .radio(.ownWindow): ["new window"]
        case .radio(.singleClick), .radio(.doubleClick), .radio(.underlineAlways), .radio(.underlineHover): ["mouse", "open"]
        case .check(.showRecentFiles), .check(.showFrequentFolders): ["Home", "history", "recent"]
        case .clearHistory: ["history", "recent", "forget", "privacy"]
        case .openFoldersInFolio: ["default file manager", "Finder", "Launch Services"]
        case .revealInFolio: ["Show in Finder", "default file manager", "NSFileViewer"]
        case .launchAtLogin: ["startup", "login items", "open at login"]
        case .check(.keepRunning): ["quit", "Dock", "background"]
        case .check(.reopenWindows): ["restore", "session", "relaunch"]
        case .check(.externalFoldersInNewTab): ["ff", "other apps"]
        case .check(.dontUseIndex): ["Spotlight", "index"]
        case .check(.includeCompressedFiles): ["zip", "archives"]
        case .check(.alwaysSearchContents): ["content", "text inside files"]
        case .check(.includeSystemDirectories): ["system files"]
        default: []
        }
    }
}

/// The words of a title or a query for the settings search: lower case, accents folded, split at
/// everything that is not a letter or a digit ("Don't" is "don" and "t", ".DS_Store" is "ds" and "store").
enum SettingsText {
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
