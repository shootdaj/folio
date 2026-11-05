import Foundation
import Testing
@testable import FolioCore

@Suite struct SavedSearchTests {
    @Test func aSavedSearchRoundTripsThroughItsXML() throws {
        let s = SavedSearch(text: "bert kind:=document \"a & <b>\"", location: .folder(URL(fileURLWithPath: "/private/tmp/work", isDirectory: true)),
                            recursive: false, view: "details", sort: [SortTerm(key: .modified, ascending: false), SortTerm(key: .name, ascending: true)],
                            group: GroupSpec(key: .folder, ascending: true))
        let xml = s.xml()
        #expect(xml.contains("<persistedQuery"))
        #expect(xml.contains("nonRecursive=\"true\""))
        #expect(xml.contains("&amp;"))
        #expect(try SavedSearch(xml: xml) == s)
    }

    @Test func homeAndThisPCAndDefaults() throws {
        for location in [SearchLocation.home, .thisPC] {
            let s = SavedSearch(text: "notes", location: location)
            #expect(try SavedSearch(xml: s.xml()) == s)
        }
        #expect(throws: SavedSearch.ReadError.notASavedSearch) { try SavedSearch(xml: "<plist version=\"1.0\"/>") }
        #expect(throws: (any Error).self) { try SavedSearch(xml: "not xml at all <") }
    }

    @Test func savedToAFileAndReadBack() throws {
        let t = try TestTree(); defer { t.close() }
        let folder = SavedSearch.folder(home: t.root)
        #expect(folder.path.hasSuffix("Library/Application Support/Folio/Searches"))
        let s = SavedSearch(text: "content:needle", location: .folder(URL(fileURLWithPath: t.url("work").path, isDirectory: true)))
        let url = try s.write(to: folder.appendingPathComponent(SavedSearch.suggestedName(for: s.text)))
        #expect(url.lastPathComponent == "content-needle.foliosearch")
        #expect(try SavedSearch.read(from: url) == s)
        #expect(SavedSearch.suggestedName(for: "  ") == "Search.foliosearch")
        #expect(SavedSearch.suggestedName(for: "a/b") == "a-b.foliosearch")
    }
}

@Suite struct RecentSearchesTests {
    @Test func theLastTenNewestFirstWithoutRepeats() throws {
        let defaults = try #require(UserDefaults(suiteName: "folio-recent-\(UUID().uuidString)"))
        let recent = RecentSearches(defaults: defaults)
        for i in 1...12 { recent.record("query \(i)") }
        #expect(recent.items.count == 10)
        #expect(recent.items.first == "query 12")
        recent.record("query 5")
        #expect(recent.items.first == "query 5")
        #expect(recent.items.filter { $0 == "query 5" }.count == 1)
        recent.record("   ")
        #expect(recent.items.first == "query 5")
        recent.clear()
        #expect(recent.items.isEmpty)
    }
}

@Suite struct SearchBoxTextTests {
    @Test func aPickIsAddedAtTheEnd() {
        #expect(SearchBoxText.setting(.modified, to: "today", in: "bert") == "bert datemodified:today")
        #expect(SearchBoxText.setting(.size, to: "tiny", in: "") == "size:tiny")
        #expect(SearchBoxText.setting(.kind, to: "=document", in: "bert size:tiny") == "bert size:tiny kind:=document")
    }

    @Test func aSecondPickOfTheSameFilterReplacesTheFirst() {
        #expect(SearchBoxText.setting(.modified, to: "yesterday", in: "bert datemodified:today") == "bert datemodified:yesterday")
        #expect(SearchBoxText.setting(.modified, to: "today", in: "datemodified:this week bert") == "bert datemodified:today")
        #expect(SearchBoxText.setting(.modified, to: "this week", in: "modified:lastmonth notes") == "notes datemodified:this week")
        #expect(SearchBoxText.setting(.size, to: "large", in: "size:tiny \"budget 2024\" (a OR b)") == "\"budget 2024\" (a OR b) size:large")
        #expect(SearchBoxText.clearing(.size, in: "bert size:tiny") == "bert")
    }

    @Test func theChipsReadTheirValueFromTheBox() {
        #expect(SearchBoxText.value(of: .modified, in: "bert datemodified:this week") == "this week")
        #expect(SearchBoxText.value(of: .modified, in: "bert date:today") == "today")
        #expect(SearchBoxText.value(of: .kind, in: "kind:=document") == "document")
        #expect(SearchBoxText.value(of: .size, in: "bert") == nil)
        #expect(SearchBoxText.value(of: .size, in: "-size:tiny") == nil)
    }

    @Test func otherPropertiesLeaveTheCaretAfterTheColon() {
        #expect(SearchBoxText.appendingKeyword(.name, to: "bert") == "bert name:")
        #expect(SearchBoxText.appendingKeyword(.tag, to: "") == "tag:")
        #expect(SearchBoxText.appendingKeyword(.folder, to: "bert ") == "bert folder:")
    }

    @Test func whatTheMenuWritesParsesBackToTheSameFilter() throws {
        let text = SearchBoxText.setting(.modified, to: "this week", in: SearchBoxText.setting(.size, to: "tiny", in: "bert"))
        #expect(try parse(text) == .and([word("bert"), try parse("size:tiny"), try parse("datemodified:thisweek")]))
    }
}

@Suite struct SearchHistoryTests {
    private func dir(_ p: String) -> URL { URL(fileURLWithPath: p, isDirectory: true) }

    @Test func aSearchIsAStepBackReturnsToWithTheQuery() {
        var h = NavigationHistory(start: dir("/work"))
        h.push(dir("/work"), search: HistorySearch(text: "b"))
        h.updateSearch(HistorySearch(text: "bert"))
        #expect(h.search?.text == "bert")
        #expect(h.canGoBack)
        // Open a folder from the results, then Back: the results with the query.
        h.push(dir("/work/level2"))
        #expect(h.search == nil)
        #expect(h.goBack()?.path == "/work")
        #expect(h.search?.text == "bert")
        // Back again: the folder without the search; Forward brings the search back.
        #expect(h.goBack()?.path == "/work")
        #expect(h.search == nil)
        #expect(h.goForward()?.path == "/work")
        #expect(h.search?.text == "bert")
    }

    @Test func closingTheSearchDropsItsStep() {
        var h = NavigationHistory(start: dir("/work"))
        h.push(dir("/work"), search: HistorySearch(text: "bert"))
        h.closeSearch()
        #expect(h.search == nil)
        #expect(!h.canGoBack)
        // A search restored by Back on a folder reached otherwise is just dropped in place.
        var g = NavigationHistory(start: dir("/a"))
        g.push(dir("/work"), search: HistorySearch(text: "bert", recursive: false))
        g.closeSearch()
        #expect(g.current.path == "/work")
        #expect(g.search == nil)
        #expect(g.goBack()?.path == "/a")
    }

    @Test func pushingTheSamePlaceTwiceDoesNothingButASearchIsANewPlace() {
        var h = NavigationHistory(start: dir("/work"))
        h.push(dir("/work"))
        #expect(!h.canGoBack)
        h.push(dir("/work"), search: HistorySearch(text: "x"))
        #expect(h.canGoBack)
        h.push(dir("/work"), search: HistorySearch(text: "x"))
        #expect(h.backList.count == 1)
        // Up leaves the search.
        #expect(h.goUp()?.path == "/")
        #expect(h.search == nil)
    }
}

@Suite struct FolderColumnTests {
    @Test func nameFirstThenTheParentPathWithTheHomeAsTilde() {
        let home = "/Users/anshul"
        #expect(ColumnValues.folderText(URL(fileURLWithPath: "/Users/anshul/Documents/2026/invoices/a.pdf"), home: home) ==
            "invoices (~/Documents/2026)")
        #expect(ColumnValues.folderText(URL(fileURLWithPath: "/Users/anshul/Documents/a.pdf"), home: home) == "Documents (~)")
        #expect(ColumnValues.folderText(URL(fileURLWithPath: "/Users/anshul/a.pdf"), home: home) == "~")
        #expect(ColumnValues.folderText(URL(fileURLWithPath: "/private/tmp/work/level2/Bertie.md"), home: home) ==
            "level2 (/private/tmp/work)")
        #expect(ColumnValues.folderText(URL(fileURLWithPath: "/Volumes/USB/x.txt"), home: home) == "USB (/Volumes)")
    }

    @Test func theFolderColumnSortsAndGroups() {
        func e(_ p: String) -> FileEntry {
            FileEntry(url: URL(fileURLWithPath: p), name: (p as NSString).lastPathComponent, isFolder: false, modified: nil, size: 1, kind: "Text")
        }
        let items = [e("/w/level2/b.txt"), e("/w/a.txt"), e("/w/level2/level3/c.txt"), e("/w/level2/d.txt")]
        let groups = GroupBuilder.build(items, by: GroupSpec(key: .folder, ascending: true), sort: .standard, context: searchContext)
        #expect(groups.map(\.title) == ["level2 (/w) (2)", "level3 (/w/level2) (1)", "w (/) (1)"])
        #expect(ColumnID.folder.title == "Folder")
        #expect(!ColumnID.folder.needsMetadata)
    }
}

@Suite struct SearchHudTests {
    @Test func theHudReadsQueryScopeResultsAndRelevance() {
        let none = SelectionSummary([])
        let running = Hud.searchSegments(query: "bert", scope: "work", results: 0, searching: true, sort: nil, selection: none)
        #expect(running.map(\.key) == ["Query", "Scope", "Results", "Sort", "Selected"])
        #expect(running[0].pulses)
        #expect(running[2].value == "Scanning")
        #expect(running[3].value == "Relevance")
        let done = Hud.searchSegments(query: "bert", scope: "work", results: 1234, searching: false, sort: .standard, selection: none)
        #expect(!done[0].pulses)
        #expect(done[2].value == "1,234")
        #expect(done[3].value != "Relevance")
    }
}
