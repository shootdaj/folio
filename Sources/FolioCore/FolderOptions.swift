import Foundation

/// Explorer's Folder Options (See more > Options), every setting of its General, View and Search tabs.
/// The ones that mean nothing on a Mac stay in the list, greyed, as Microsoft kept all nine it once removed.
public struct FolderOptions: Equatable, Sendable {
    public enum OpenTo: String, Sendable, CaseIterable { case home, thisPC }
    public enum Underline: String, Sendable { case always, onHover }
    public enum Typing: String, Sendable { case selectItem, searchBox }
    public enum Tab: String, Sendable, CaseIterable { case general = "General", view = "View", search = "Search" }

    // General
    public var openTo = OpenTo.home
    public var openFoldersInNewWindow = false
    public var singleClickOpens = false
    public var underline = Underline.onHover
    public var showRecentFiles = true
    public var showFrequentFolders = true
    // General: Folio and macOS (milestone 9)
    /// Explorer's "Open desktop folders and external folder links in a new tab": folders from ff and
    /// other apps open as a tab in the front window.
    public var externalFoldersInNewTab = true
    /// Explorer's "Restore previous folder windows at logon", on here: windows and tabs come back.
    public var reopenWindows = true
    /// Explorer stays alive with no window open; Cmd+Q still quits.
    public var keepRunning = true

    // View: Files and folders
    public var alwaysShowIcons = false
    public var fileIconOnThumbnails = true
    public var fileSizeInFolderTips = true
    public var fullPathInTitleBar = false
    public var showHidden = false
    public var hideEmptyDrives = true
    public var hideExtensions = false
    public var hideFolderMergeConflicts = true
    public var hideProtectedOSFiles = true
    /// A Mac has no drive letters: this shows each drive's mount path after its name.
    public var showDriveLetters = false
    /// NTFS compression and encryption have no Mac form: locked and compressed items draw dimmed.
    public var showCompressedInColour = false
    public var showPopupDescriptions = true
    public var showPreviewHandlers = true
    public var showStatusBar = true
    public var useCheckBoxes = false
    public var typing = Typing.selectItem
    /// View > Details Size: the Details list's text, icons and rows.
    public var detailsSize = DetailsSize.small
    /// The Recycle Bin's Display delete confirmation dialog, off as in Explorer.
    public var confirmDelete = false

    // View: Navigation pane
    public var expandToOpenFolder = true
    public var showAllFolders = false
    public var showNetwork = true
    public var showThisPC = true
    /// Hidden folders in the tree, apart from the list's "Show hidden files": off keeps the tree to the
    /// folders Finder shows, with hidden items shown in the list.
    public var navPaneShowHidden = false

    // Search
    public var dontUseIndex = false
    public var includeSystemDirectories = false
    public var includeCompressedFiles = false
    public var alwaysSearchContents = false

    public init() {}

    /// Restore Defaults on one tab: only that tab's settings go back.
    public mutating func restoreDefaults(_ tab: Tab) {
        let d = FolderOptions()
        switch tab {
        case .general:
            openTo = d.openTo
            openFoldersInNewWindow = d.openFoldersInNewWindow
            singleClickOpens = d.singleClickOpens
            underline = d.underline
            showRecentFiles = d.showRecentFiles
            showFrequentFolders = d.showFrequentFolders
            externalFoldersInNewTab = d.externalFoldersInNewTab
            reopenWindows = d.reopenWindows
            keepRunning = d.keepRunning
        case .view:
            let keep = (openTo, openFoldersInNewWindow, singleClickOpens, underline, showRecentFiles, showFrequentFolders,
                        dontUseIndex, includeSystemDirectories, includeCompressedFiles, alwaysSearchContents)
            let folio = (externalFoldersInNewTab, reopenWindows, keepRunning)
            self = d
            (openTo, openFoldersInNewWindow, singleClickOpens, underline, showRecentFiles, showFrequentFolders,
             dontUseIndex, includeSystemDirectories, includeCompressedFiles, alwaysSearchContents) = keep
            (externalFoldersInNewTab, reopenWindows, keepRunning) = folio
        case .search:
            dontUseIndex = d.dontUseIndex
            includeSystemDirectories = d.includeSystemDirectories
            includeCompressedFiles = d.includeCompressedFiles
            alwaysSearchContents = d.alwaysSearchContents
        }
    }

    /// The keys whose values differ between two sets of options.
    public static func allChanged(from a: FolderOptions, to b: FolderOptions) -> [String] {
        let x = FolderOptionsStore.values(a), y = FolderOptionsStore.values(b)
        return FolderOptionsStore.keys.filter { !(x[$0] as AnyObject).isEqual(y[$0]) }
    }

    // MARK: The View tab's Advanced settings list

    /// One line of Advanced settings: a check box, a radio of a group, or a group's heading.
    public struct Row: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case heading, check, radio(group: String) }
        public let title: String
        public let kind: Kind
        /// The setting it shows (`FolderOptions.Setting`), nil for headings and greyed rows.
        public let setting: Setting?
        public let isAvailable: Bool
        /// Shown as a tooltip: why a row is greyed, or what it does on a Mac.
        public let note: String?
        public let indent: Int

        init(_ title: String, _ kind: Kind = .check, _ setting: Setting?, indent: Int = 1, note: String? = nil) {
            self.title = title
            self.kind = kind
            self.setting = setting
            isAvailable = setting != nil || kind == .heading
            self.note = setting == nil && kind != .heading ? "Not on macOS" : note
            self.indent = indent
        }
    }

    /// Each check box and radio of the dialog, so it can read and write the right field.
    public enum Setting: String, Sendable, CaseIterable {
        case openToHome, openToThisPC, sameWindow, ownWindow, singleClick, doubleClick, underlineAlways, underlineHover
        case showRecentFiles, showFrequentFolders, externalFoldersInNewTab, reopenWindows, keepRunning
        case alwaysShowIcons, fileIconOnThumbnails, fileSizeInFolderTips, fullPathInTitleBar
        case hiddenOff, hiddenOn, hideEmptyDrives, hideExtensions, hideFolderMergeConflicts, hideProtectedOSFiles
        case showDriveLetters, showCompressedInColour, showPopupDescriptions, showPreviewHandlers, showStatusBar
        case useCheckBoxes, typingSearchBox, typingSelect, confirmDelete
        case detailsSmall, detailsMedium, detailsLarge, detailsExtraLarge
        case expandToOpenFolder, showAllFolders, showNetwork, showThisPC, navPaneShowHidden
        case dontUseIndex, includeSystemDirectories, includeCompressedFiles, alwaysSearchContents
    }

    public func isOn(_ s: Setting) -> Bool {
        switch s {
        case .openToHome: openTo == .home
        case .openToThisPC: openTo == .thisPC
        case .sameWindow: !openFoldersInNewWindow
        case .ownWindow: openFoldersInNewWindow
        case .singleClick: singleClickOpens
        case .doubleClick: !singleClickOpens
        case .underlineAlways: underline == .always
        case .underlineHover: underline == .onHover
        case .showRecentFiles: showRecentFiles
        case .showFrequentFolders: showFrequentFolders
        case .externalFoldersInNewTab: externalFoldersInNewTab
        case .reopenWindows: reopenWindows
        case .keepRunning: keepRunning
        case .alwaysShowIcons: alwaysShowIcons
        case .fileIconOnThumbnails: fileIconOnThumbnails
        case .fileSizeInFolderTips: fileSizeInFolderTips
        case .fullPathInTitleBar: fullPathInTitleBar
        case .hiddenOff: !showHidden
        case .hiddenOn: showHidden
        case .hideEmptyDrives: hideEmptyDrives
        case .hideExtensions: hideExtensions
        case .hideFolderMergeConflicts: hideFolderMergeConflicts
        case .hideProtectedOSFiles: hideProtectedOSFiles
        case .showDriveLetters: showDriveLetters
        case .showCompressedInColour: showCompressedInColour
        case .showPopupDescriptions: showPopupDescriptions
        case .showPreviewHandlers: showPreviewHandlers
        case .showStatusBar: showStatusBar
        case .useCheckBoxes: useCheckBoxes
        case .typingSearchBox: typing == .searchBox
        case .typingSelect: typing == .selectItem
        case .confirmDelete: confirmDelete
        case .detailsSmall: detailsSize == .small
        case .detailsMedium: detailsSize == .medium
        case .detailsLarge: detailsSize == .large
        case .detailsExtraLarge: detailsSize == .extraLarge
        case .expandToOpenFolder: expandToOpenFolder
        case .showAllFolders: showAllFolders
        case .showNetwork: showNetwork
        case .showThisPC: showThisPC
        case .navPaneShowHidden: navPaneShowHidden
        case .dontUseIndex: dontUseIndex
        case .includeSystemDirectories: includeSystemDirectories
        case .includeCompressedFiles: includeCompressedFiles
        case .alwaysSearchContents: alwaysSearchContents
        }
    }

    /// A click: a check box flips, a radio turns on (and its partner off).
    public mutating func toggle(_ s: Setting) {
        switch s {
        case .openToHome: openTo = .home
        case .openToThisPC: openTo = .thisPC
        case .sameWindow: openFoldersInNewWindow = false
        case .ownWindow: openFoldersInNewWindow = true
        case .singleClick: singleClickOpens = true
        case .doubleClick: singleClickOpens = false
        case .underlineAlways: underline = .always
        case .underlineHover: underline = .onHover
        case .showRecentFiles: showRecentFiles.toggle()
        case .showFrequentFolders: showFrequentFolders.toggle()
        case .externalFoldersInNewTab: externalFoldersInNewTab.toggle()
        case .reopenWindows: reopenWindows.toggle()
        case .keepRunning: keepRunning.toggle()
        case .alwaysShowIcons: alwaysShowIcons.toggle()
        case .fileIconOnThumbnails: fileIconOnThumbnails.toggle()
        case .fileSizeInFolderTips: fileSizeInFolderTips.toggle()
        case .fullPathInTitleBar: fullPathInTitleBar.toggle()
        case .hiddenOff: showHidden = false
        case .hiddenOn: showHidden = true
        case .hideEmptyDrives: hideEmptyDrives.toggle()
        case .hideExtensions: hideExtensions.toggle()
        case .hideFolderMergeConflicts: hideFolderMergeConflicts.toggle()
        case .hideProtectedOSFiles: hideProtectedOSFiles.toggle()
        case .showDriveLetters: showDriveLetters.toggle()
        case .showCompressedInColour: showCompressedInColour.toggle()
        case .showPopupDescriptions: showPopupDescriptions.toggle()
        case .showPreviewHandlers: showPreviewHandlers.toggle()
        case .showStatusBar: showStatusBar.toggle()
        case .useCheckBoxes: useCheckBoxes.toggle()
        case .typingSearchBox: typing = .searchBox
        case .typingSelect: typing = .selectItem
        case .confirmDelete: confirmDelete.toggle()
        case .detailsSmall: detailsSize = .small
        case .detailsMedium: detailsSize = .medium
        case .detailsLarge: detailsSize = .large
        case .detailsExtraLarge: detailsSize = .extraLarge
        case .expandToOpenFolder: expandToOpenFolder.toggle()
        case .showAllFolders: showAllFolders.toggle()
        case .showNetwork: showNetwork.toggle()
        case .showThisPC: showThisPC.toggle()
        case .navPaneShowHidden: navPaneShowHidden.toggle()
        case .dontUseIndex: dontUseIndex.toggle()
        case .includeSystemDirectories: includeSystemDirectories.toggle()
        case .includeCompressedFiles: includeCompressedFiles.toggle()
        case .alwaysSearchContents: alwaysSearchContents.toggle()
        }
    }

    /// Advanced settings in Explorer's order and wording (colour spelt the British way, as Anshul writes it).
    public static let viewRows: [Row] = [
        Row("Files and folders", .heading, nil, indent: 0),
        Row("Always show icons, never thumbnails", .check, .alwaysShowIcons),
        Row("Display delete confirmation dialog", .check, .confirmDelete, note: "Asks before Move to Trash"),
        Row("Display file icon on thumbnails", .check, .fileIconOnThumbnails),
        Row("Display file size information in folder tips", .check, .fileSizeInFolderTips),
        Row("Display the full path in the title bar", .check, .fullPathInTitleBar),
        Row("Hidden files and folders", .heading, nil),
        Row("Don't show hidden files, folders or drives", .radio(group: "hidden"), .hiddenOff, indent: 2),
        Row("Show hidden files, folders and drives", .radio(group: "hidden"), .hiddenOn, indent: 2),
        Row("Hide empty drives", .check, .hideEmptyDrives, note: "Drives with no media, such as an empty card reader"),
        Row("Hide extensions for known file types", .check, .hideExtensions),
        Row("Hide folder merge conflicts", .check, .hideFolderMergeConflicts, note: "Off asks before merging same-named folders"),
        Row("Hide protected operating system files (Recommended)", .check, .hideProtectedOSFiles,
            note: ".DS_Store, .localized, Icon and the like, even with hidden items shown"),
        Row("Launch folder windows in a separate process", .check, nil),
        Row("Show drive letters", .check, .showDriveLetters, note: "A Mac has no drive letters: shows the mount path, such as /Volumes/USB"),
        Row("Show encrypted or compressed files in colour", .check, .showCompressedInColour,
            note: "Locked and compressed items draw dimmed"),
        Row("Show pop-up description for folder and desktop items", .check, .showPopupDescriptions),
        Row("Show preview handlers in preview pane", .check, .showPreviewHandlers),
        Row("Show status bar", .check, .showStatusBar),
        Row("Show sync provider notifications", .check, nil),
        Row("Use check boxes to select items", .check, .useCheckBoxes),
        Row("Use Sharing Wizard (Recommended)", .check, nil),
        Row("When typing into list view", .heading, nil),
        Row("Automatically type into the Search Box", .radio(group: "typing"), .typingSearchBox, indent: 2),
        Row("Select the typed item in the view", .radio(group: "typing"), .typingSelect, indent: 2),
        Row("Text and icon size in Details view", .heading, nil),
        Row("Small", .radio(group: "detailsSize"), .detailsSmall, indent: 2, note: "13 pt names and 16 pt icons, as Finder"),
        Row("Medium", .radio(group: "detailsSize"), .detailsMedium, indent: 2, note: "14 pt names and 20 pt icons"),
        Row("Large", .radio(group: "detailsSize"), .detailsLarge, indent: 2, note: "16 pt names and 24 pt icons"),
        Row("Extra large", .radio(group: "detailsSize"), .detailsExtraLarge, indent: 2, note: "18 pt names and 32 pt icons"),
        Row("Navigation pane", .heading, nil, indent: 0),
        Row("Expand to open folder", .check, .expandToOpenFolder),
        Row("Show all folders", .check, .showAllFolders, note: "Roots the tree at the top of the Mac: Home, drives, Network and the Recycle Bin"),
        Row("Show hidden folders", .check, .navPaneShowHidden,
            note: "Dot folders and hidden folders in the tree. The list follows Hidden files and folders"),
        Row("Show libraries", .check, nil),
        Row("Show Network", .check, .showNetwork),
        Row("Show This PC", .check, .showThisPC),
    ]
}

/// Where Folder Options live: one defaults key per setting. The keys the View menu and Search options
/// already used are the same keys, so both places agree.
public struct FolderOptionsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public static let keys = [
        "openFolioTo", "browseFoldersOwnWindow", "singleClickOpen", "singleClickUnderline", "showRecentFiles", "showFrequentFolders",
        "externalFoldersInNewTab", "reopenWindows", "keepRunningWithoutWindows",
        "showThumbnails", "fileIconOnThumbnails", "folderTipSizes", "fullPathInTitle", "showHiddenItems", "hideEmptyDrives",
        "showFileExtensions", "hideFolderMergeConflicts", "hideProtectedFiles", "showDriveLetters", "showCompressedInColour",
        "showInfoTips", "showPreviewHandlers", "showStatusBar", "itemCheckBoxes", "typeIntoSearch", "confirmDelete", "detailsSize",
        "navPaneExpandToCurrent", "navPaneShowAllFolders", "navPaneShowNetwork", "navPaneShowThisPC", "navPaneShowHidden",
        "searchDontUseIndex", "searchSystemFiles", "searchZippedFolders", "searchFileContents",
    ]

    /// The options as stored values (inverted where the old key reads the other way round).
    static func values(_ o: FolderOptions) -> [String: Any] {
        [
            "openFolioTo": o.openTo.rawValue, "browseFoldersOwnWindow": o.openFoldersInNewWindow,
            "singleClickOpen": o.singleClickOpens, "singleClickUnderline": o.underline.rawValue,
            "showRecentFiles": o.showRecentFiles, "showFrequentFolders": o.showFrequentFolders,
            "externalFoldersInNewTab": o.externalFoldersInNewTab, "reopenWindows": o.reopenWindows,
            "keepRunningWithoutWindows": o.keepRunning,
            "showThumbnails": !o.alwaysShowIcons, "fileIconOnThumbnails": o.fileIconOnThumbnails,
            "folderTipSizes": o.fileSizeInFolderTips, "fullPathInTitle": o.fullPathInTitleBar,
            "showHiddenItems": o.showHidden, "hideEmptyDrives": o.hideEmptyDrives, "showFileExtensions": !o.hideExtensions,
            "hideFolderMergeConflicts": o.hideFolderMergeConflicts, "hideProtectedFiles": o.hideProtectedOSFiles,
            "showDriveLetters": o.showDriveLetters, "showCompressedInColour": o.showCompressedInColour,
            "showInfoTips": o.showPopupDescriptions, "showPreviewHandlers": o.showPreviewHandlers,
            "showStatusBar": o.showStatusBar, "itemCheckBoxes": o.useCheckBoxes, "typeIntoSearch": o.typing == .searchBox,
            "confirmDelete": o.confirmDelete, "detailsSize": o.detailsSize.rawValue, "navPaneExpandToCurrent": o.expandToOpenFolder,
            "navPaneShowAllFolders": o.showAllFolders, "navPaneShowNetwork": o.showNetwork, "navPaneShowThisPC": o.showThisPC,
            "navPaneShowHidden": o.navPaneShowHidden,
            "searchDontUseIndex": o.dontUseIndex, "searchSystemFiles": o.includeSystemDirectories,
            "searchZippedFolders": o.includeCompressedFiles, "searchFileContents": o.alwaysSearchContents,
        ]
    }

    public func load() -> FolderOptions {
        var o = FolderOptions()
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        o.openTo = defaults.string(forKey: "openFolioTo").flatMap(FolderOptions.OpenTo.init(rawValue:)) ?? o.openTo
        o.openFoldersInNewWindow = bool("browseFoldersOwnWindow", o.openFoldersInNewWindow)
        o.singleClickOpens = bool("singleClickOpen", o.singleClickOpens)
        o.underline = defaults.string(forKey: "singleClickUnderline").flatMap(FolderOptions.Underline.init(rawValue:)) ?? o.underline
        o.showRecentFiles = bool("showRecentFiles", o.showRecentFiles)
        o.showFrequentFolders = bool("showFrequentFolders", o.showFrequentFolders)
        o.externalFoldersInNewTab = bool("externalFoldersInNewTab", o.externalFoldersInNewTab)
        o.reopenWindows = bool("reopenWindows", o.reopenWindows)
        o.keepRunning = bool("keepRunningWithoutWindows", o.keepRunning)
        o.alwaysShowIcons = !bool("showThumbnails", !o.alwaysShowIcons)
        o.fileIconOnThumbnails = bool("fileIconOnThumbnails", o.fileIconOnThumbnails)
        o.fileSizeInFolderTips = bool("folderTipSizes", o.fileSizeInFolderTips)
        o.fullPathInTitleBar = bool("fullPathInTitle", o.fullPathInTitleBar)
        o.showHidden = bool("showHiddenItems", o.showHidden)
        o.hideEmptyDrives = bool("hideEmptyDrives", o.hideEmptyDrives)
        o.hideExtensions = !bool("showFileExtensions", !o.hideExtensions)
        o.hideFolderMergeConflicts = bool("hideFolderMergeConflicts", o.hideFolderMergeConflicts)
        o.hideProtectedOSFiles = bool("hideProtectedFiles", o.hideProtectedOSFiles)
        o.showDriveLetters = bool("showDriveLetters", o.showDriveLetters)
        o.showCompressedInColour = bool("showCompressedInColour", o.showCompressedInColour)
        o.showPopupDescriptions = bool("showInfoTips", o.showPopupDescriptions)
        o.showPreviewHandlers = bool("showPreviewHandlers", o.showPreviewHandlers)
        o.showStatusBar = bool("showStatusBar", o.showStatusBar)
        o.useCheckBoxes = bool("itemCheckBoxes", o.useCheckBoxes)
        o.typing = bool("typeIntoSearch", false) ? .searchBox : .selectItem
        o.confirmDelete = bool("confirmDelete", o.confirmDelete)
        o.detailsSize = defaults.string(forKey: "detailsSize").flatMap(DetailsSize.init(rawValue:)) ?? o.detailsSize
        o.expandToOpenFolder = bool("navPaneExpandToCurrent", o.expandToOpenFolder)
        o.showAllFolders = bool("navPaneShowAllFolders", o.showAllFolders)
        o.showNetwork = bool("navPaneShowNetwork", o.showNetwork)
        o.showThisPC = bool("navPaneShowThisPC", o.showThisPC)
        o.navPaneShowHidden = bool("navPaneShowHidden", o.navPaneShowHidden)
        o.dontUseIndex = bool("searchDontUseIndex", o.dontUseIndex)
        o.includeSystemDirectories = bool("searchSystemFiles", o.includeSystemDirectories)
        o.includeCompressedFiles = bool("searchZippedFolders", o.includeCompressedFiles)
        o.alwaysSearchContents = bool("searchFileContents", o.alwaysSearchContents)
        return o
    }

    public func save(_ o: FolderOptions) {
        for (key, value) in Self.values(o) { defaults.set(value, forKey: key) }
    }
}
