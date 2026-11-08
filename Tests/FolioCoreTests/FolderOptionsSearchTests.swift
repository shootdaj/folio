import Foundation
import Testing
@testable import FolioCore

/// The Folder Options search box: every control is in the list once, and a query finds settings by the
/// words at the start of their title, group, tab, tooltip or keywords.
@Suite struct FolderOptionsSearchTests {
    private func titles(_ query: String) -> [String] { FolderOptions.search(query).map(\.title) }

    @Test func everySettingOfTheDialogIsInTheListOnce() {
        let shown = FolderOptions.entries.compactMap { e -> FolderOptions.Setting? in
            switch e.control {
            case .check(let s), .radio(let s): s
            default: nil
            }
        }
        #expect(Set(shown) == Set(FolderOptions.Setting.allCases))
        #expect(shown.count == FolderOptions.Setting.allCases.count)
        for c: FolderOptions.Entry.Control in [.openFoldersInFolio, .revealInFolio, .launchAtLogin, .clearHistory] {
            #expect(FolderOptions.entries.filter { $0.control == c }.count == 1)
        }
    }

    @Test func theViewTabKeepsTheAdvancedListsOrderAndGroups() {
        let rows = FolderOptions.viewRows.filter { $0.kind != .heading }
        #expect(FolderOptions.viewEntries.map(\.title) == rows.map(\.title))
        let hidden = FolderOptions.viewEntries.filter { $0.control == .radio(.hiddenOn) || $0.control == .radio(.hiddenOff) }
        #expect(hidden.map(\.group) == ["Hidden files and folders", "Hidden files and folders"])
        #expect(FolderOptions.entry(.check(.hideEmptyDrives))?.group == "Files and folders")
        #expect(FolderOptions.entry(.radio(.typingSelect))?.group == "When typing into list view")
        #expect(FolderOptions.entry(.check(.showNetwork))?.place == "View > Navigation pane")
        #expect(FolderOptions.entry(.unavailable)?.note == nil)
    }

    @Test func hiddenFindsBothRadiosFirstAndTheOtherHiddenSettingsAfter() {
        let found = titles("hidden")
        #expect(Array(found.prefix(2)) == ["Don't show hidden files, folders or drives", "Show hidden files, folders and drives"])
        #expect(found.contains("Hide protected operating system files (Recommended)"))
        #expect(titles("show hidden").prefix(2) == ["Don't show hidden files, folders or drives", "Show hidden files, folders and drives"])
    }

    @Test func theTreeHasItsOwnHiddenFoldersBoxApartFromTheList() {
        let e = FolderOptions.entry(.check(.navPaneShowHidden))
        #expect(e?.group == "Navigation pane" && e?.title == "Show hidden folders")
        #expect(titles("hidden").contains("Show hidden folders"))
        #expect(titles("sidebar hidden") == ["Show hidden folders"])
        var o = FolderOptions()
        o.toggle(.hiddenOn)
        #expect(o.showHidden && !o.navPaneShowHidden, "showing hidden items in the list leaves the tree as it was")
        o.toggle(.navPaneShowHidden)
        o.toggle(.hiddenOff)
        #expect(!o.showHidden && o.navPaneShowHidden)
    }

    @Test func keywordsFindASettingByAnotherName() {
        #expect(titles("dot files").contains("Show hidden files, folders and drives"))
        #expect(titles("spotlight") == [FolderOptions.searchEntries[0].title])
        #expect(titles("zip") == ["Include compressed files (ZIP)"])
        #expect(titles("finder").prefix(2) == ["Open folders in Folio instead of Finder", "Reveal in Folio instead of Finder"])
        #expect(titles("login") == ["Launch Folio at login"])
    }

    @Test func wordsMatchAtTheirStartInAnyCaseAndOrder() {
        #expect(titles("EXTENS") == ["Hide extensions for known file types"])
        #expect(titles("bar status") == ["Show status bar"])
        #expect(titles("tatus").isEmpty)
        #expect(titles("Préview handlers") == ["Show preview handlers in preview pane"])
    }

    @Test func aGroupOrTabNameFindsEverySettingInIt() {
        #expect(titles("privacy") == ["Show recently used files", "Show frequently used folders",
                                      "Clear recent files, folders, addresses"])
        #expect(FolderOptions.search("search").contains { $0.title == "Include system directories" })
    }

    @Test func anEmptyQueryOrNoMatchFindsNothing() {
        #expect(titles("").isEmpty)
        #expect(titles("  ,. ").isEmpty)
        #expect(titles("zzzz").isEmpty)
    }

    @Test func greyedRowsAreFoundByTitleButNotByTheirNotOnMacOSTip() {
        #expect(titles("sharing wizard") == ["Use Sharing Wizard (Recommended)"])
        #expect(!titles("not on").contains("Use Sharing Wizard (Recommended)"))
    }
}
