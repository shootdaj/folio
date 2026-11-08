import Foundation
import Testing
@testable import FolioCore

/// Folder Options: every setting of the General, View and Search tabs, what each starts as, that each is
/// kept under its own key and read back, and Restore Defaults per tab.
@Suite struct FolderOptionsTests {
    private func store() -> (FolderOptionsStore, UserDefaults) {
        let name = "folio-options-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return (FolderOptionsStore(defaults: d), d)
    }

    @Test func startsWithExplorersDefaultsWhereTheyMeanSomethingOnAMac() {
        let (s, _) = store()
        let o = s.load()
        #expect(o == FolderOptions())
        #expect(o.openTo == .home)
        #expect(!o.openFoldersInNewWindow)
        #expect(!o.singleClickOpens && o.underline == .onHover)
        #expect(o.showRecentFiles && o.showFrequentFolders)
        #expect(o.externalFoldersInNewTab && o.reopenWindows && o.keepRunning, "milestone 9: tabs, reopen, keep running")
        #expect(!o.alwaysShowIcons && o.fileIconOnThumbnails && o.fileSizeInFolderTips)
        #expect(!o.fullPathInTitleBar && !o.showHidden && o.hideEmptyDrives && !o.hideExtensions)
        #expect(o.hideFolderMergeConflicts && o.hideProtectedOSFiles)
        #expect(o.showPopupDescriptions && o.showPreviewHandlers && o.showStatusBar && !o.useCheckBoxes)
        #expect(o.typing == .selectItem && !o.confirmDelete)
        #expect(o.expandToOpenFolder && !o.showAllFolders && o.showNetwork && o.showThisPC && !o.navPaneShowHidden)
        #expect(!o.dontUseIndex && !o.includeSystemDirectories && !o.includeCompressedFiles && !o.alwaysSearchContents)
    }

    @Test func everySettingRoundTripsThroughItsOwnKey() {
        let (s, d) = store()
        var o = FolderOptions()
        o.openTo = .thisPC
        o.openFoldersInNewWindow = true
        o.singleClickOpens = true
        o.underline = .always
        o.showRecentFiles = false
        o.showFrequentFolders = false
        o.externalFoldersInNewTab = false
        o.reopenWindows = false
        o.keepRunning = false
        o.alwaysShowIcons = true
        o.fileIconOnThumbnails = false
        o.fileSizeInFolderTips = false
        o.fullPathInTitleBar = true
        o.showHidden = true
        o.hideEmptyDrives = false
        o.hideExtensions = true
        o.hideFolderMergeConflicts = false
        o.hideProtectedOSFiles = false
        o.showDriveLetters = true
        o.showCompressedInColour = true
        o.showPopupDescriptions = false
        o.showPreviewHandlers = false
        o.showStatusBar = false
        o.useCheckBoxes = true
        o.typing = .searchBox
        o.confirmDelete = true
        o.expandToOpenFolder = false
        o.showAllFolders = true
        o.showNetwork = false
        o.showThisPC = false
        o.navPaneShowHidden = true
        o.dontUseIndex = true
        o.includeSystemDirectories = true
        o.includeCompressedFiles = true
        o.alwaysSearchContents = true
        s.save(o)
        #expect(s.load() == o)
        for key in FolderOptionsStore.keys { #expect(d.object(forKey: key) != nil, "\(key) is written") }
        #expect(Set(FolderOptionsStore.keys).count == FolderOptionsStore.keys.count)
        #expect(FolderOptionsStore.keys.count == 35)
        // Every field differs from the default, so a field the store forgot would come back as the default.
        #expect(FolderOptions.allChanged(from: FolderOptions(), to: o).count == FolderOptionsStore.keys.count)
    }

    @Test func sharesTheKeysTheViewMenuAndSearchOptionsAlreadyUse() {
        let (s, d) = store()
        d.set(true, forKey: "itemCheckBoxes")
        d.set(true, forKey: "showHiddenItems")
        d.set(false, forKey: "showFileExtensions")
        d.set(false, forKey: "showThumbnails")
        d.set(false, forKey: "navPaneExpandToCurrent")
        d.set(true, forKey: "searchSystemFiles")
        d.set(true, forKey: "searchFileContents")
        let o = s.load()
        #expect(o.useCheckBoxes && o.showHidden && o.hideExtensions && o.alwaysShowIcons && !o.expandToOpenFolder)
        #expect(o.includeSystemDirectories && o.alwaysSearchContents)
    }

    @Test func restoreDefaultsResetsOnlyThatTab() {
        var o = FolderOptions()
        o.openTo = .thisPC
        o.fullPathInTitleBar = true
        o.dontUseIndex = true
        o.keepRunning = false
        o.reopenWindows = false
        var general = o
        general.restoreDefaults(.general)
        #expect(general.openTo == .home && general.fullPathInTitleBar && general.dontUseIndex)
        #expect(general.keepRunning && general.reopenWindows, "Folio and macOS live on General")
        var view = o
        view.restoreDefaults(.view)
        #expect(view.openTo == .thisPC && !view.fullPathInTitleBar && view.dontUseIndex)
        #expect(!view.keepRunning && !view.reopenWindows, "View's Restore Defaults leaves them alone")
        var search = o
        search.restoreDefaults(.search)
        #expect(search.openTo == .thisPC && search.fullPathInTitleBar && !search.dontUseIndex)
    }

    @Test func theViewTabListsEveryAdvancedSettingWithTheRemovedOnesGreyed() {
        let rows = FolderOptions.viewRows
        let titles = rows.map(\.title)
        for t in ["Always show icons, never thumbnails", "Display file icon on thumbnails",
                  "Display file size information in folder tips", "Display the full path in the title bar",
                  "Hide empty drives", "Hide extensions for known file types", "Hide folder merge conflicts",
                  "Hide protected operating system files (Recommended)", "Launch folder windows in a separate process",
                  "Show drive letters", "Show encrypted or compressed files in colour",
                  "Show pop-up description for folder and desktop items", "Show preview handlers in preview pane",
                  "Show status bar", "Show sync provider notifications", "Use check boxes to select items",
                  "Use Sharing Wizard (Recommended)", "Expand to open folder", "Show all folders", "Show libraries",
                  "Show Network", "Show This PC", "Display delete confirmation dialog"] {
            #expect(titles.contains(t), "\(t)")
        }
        let greyed = Set(rows.filter { !$0.isAvailable }.map(\.title))
        #expect(greyed == ["Launch folder windows in a separate process", "Show sync provider notifications",
                           "Use Sharing Wizard (Recommended)", "Show libraries"])
        #expect(rows.filter { !$0.isAvailable }.allSatisfy { $0.note == "Not on macOS" })
    }
}
