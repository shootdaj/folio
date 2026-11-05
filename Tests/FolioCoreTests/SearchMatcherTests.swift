import Foundation
import Testing
@testable import FolioCore

/// An item for the matcher with whatever properties a test sets.
final class FakeSubject: SearchSubject {
    var name: String
    var path: String
    var isFolder = false
    var isLink = false
    var size: Int64? = 100
    var modified: Date? = day(2026, 11, 5, 9)
    var created: Date? = day(2026, 1, 1)
    var contentType: String?
    var typeText = "Plain Text Document"
    var tags: [String] = []
    var authors: [String] = []
    var title: String?
    var content: SearchContent = .none
    /// How many times the matcher asked for contents (they are read lazily).
    var contentReads = 0

    init(_ name: String, in folder: String = "/work", content: SearchContent = .none) {
        self.name = name
        path = folder + "/" + name
        self.content = content
    }
}

private func hits(_ text: String, _ items: [FakeSubject], trustUnknown: Bool = false) throws -> [String] {
    let m = SearchMatcher(try parse(text))
    return items.filter { m.matches($0, trustUnknown: trustUnknown) }.map(\.name)
}

private let names = ["Bert.txt", "Bertie.md", "my_bert.log", "Albert.txt", "MyBertFile.txt", "report-2024.txt", "notes.txt",
                     "invoicenumber12345.pdf", "Ethelbert.doc", "bert-and-ernie.txt"]

@Suite struct WordStartMatchingTests {
    @Test func bertFindsBertBertieAndMyBertNotAlbert() throws {
        let items = names.map { FakeSubject($0) }
        #expect(try hits("bert", items) == ["Bert.txt", "Bertie.md", "my_bert.log", "bert-and-ernie.txt"])
        #expect(try hits("BERT", items) == ["Bert.txt", "Bertie.md", "my_bert.log", "bert-and-ernie.txt"])
    }

    @Test func camelCaseAndDigitsDoNotSplitWords() {
        // Spotlight's word mode splits these (tested); Windows does not.
        #expect(!TextMatcher.matches(.word("bert"), "MyBertFile.txt"))
        #expect(!TextMatcher.matches(.word("image"), "MyImageFactory.txt"))
        #expect(!TextMatcher.matches(.word("12345"), "invoicenumber12345.pdf"))
        #expect(TextMatcher.matches(.word("invoicenumber"), "invoicenumber12345.pdf"))
        #expect(TextMatcher.matches(.word("2024"), "report-2024.txt"))
    }

    @Test func accentsAndCaseAreIgnored() {
        #expect(TextMatcher.matches(.word("cafe"), "Café menu.txt"))
        #expect(TextMatcher.matches(.word("CAFÉ"), "cafe.txt"))
        #expect(TextMatcher.matches(.word("uber"), "Über.txt"))
    }

    @Test func punctuationInTheQueryMatchesAtAWordStart() {
        #expect(TextMatcher.matches(.word("report-2024"), "report-2024.txt"))
        #expect(TextMatcher.matches(.word("my_bert"), "my_bert.log"))
        #expect(TextMatcher.matches(.word(".txt"), "notes.txt"))
    }

    @Test func starIsTheSubstringFormAndQuestionMarkIsOneCharacter() throws {
        let items = names.map { FakeSubject($0) }
        #expect(try hits("*bert*", items) == ["Bert.txt", "Bertie.md", "my_bert.log", "Albert.txt", "MyBertFile.txt",
                                               "Ethelbert.doc", "bert-and-ernie.txt"])
        #expect(try hits("*bert", items).contains("Albert.txt"))
        #expect(try hits("B?rt", items) == ["Bert.txt", "Bertie.md", "my_bert.log", "bert-and-ernie.txt"])
        #expect(TextMatcher.matches(.wildcard("B?rt"), "Bart.txt"))
        #expect(!TextMatcher.matches(.wildcard("B?rt"), "Brt.txt"))
        #expect(!TextMatcher.matches(.wildcard("B?rt"), "Beert.txt"))
        // ??bert: exactly two characters before.
        #expect(TextMatcher.matches(.wildcard("??bert"), "Albert.txt"))
        #expect(!TextMatcher.matches(.wildcard("??bert"), "Ethelbert.doc"))
        #expect(TextMatcher.matches(.wildcard("*.pdf"), "invoicenumber12345.pdf"))
        #expect(TextMatcher.matches(.wildcard("*joe*smith"), "notes from joe and smith.txt"))
    }

    @Test func phrasesAreWholeWordsInOrder() {
        #expect(TextMatcher.matches(.phrase("budget 2024"), "Budget 2024 final.xlsx"))
        #expect(TextMatcher.matches(.phrase("budget 2024"), "my_budget-2024.xlsx"))
        #expect(!TextMatcher.matches(.phrase("budget 2024"), "2024 budget.xlsx"))
        #expect(!TextMatcher.matches(.phrase("budget 2024"), "budgets 2024.xlsx"))
        #expect(TextMatcher.matches(.wordEqual("bert"), "Bert.txt"))
        #expect(!TextMatcher.matches(.wordEqual("bert"), "Bertie.md"))
    }

    @Test func valueOperators() {
        #expect(TextMatcher.matches(.contains("ber"), "Albert.txt"))
        #expect(TextMatcher.matches(.valueStarts("al"), "Albert.txt"))
        #expect(!TextMatcher.matches(.valueStarts("bert"), "Albert.txt"))
        #expect(TextMatcher.matches(.valueEnds(".TXT"), "Albert.txt"))
        #expect(TextMatcher.matches(.exact("albert.txt"), "Albert.txt"))
        #expect(!TextMatcher.matches(.exact("albert"), "Albert.txt"))
    }

    @Test func highlightsCoverTheMatchedWordStarts() {
        let name = "Bert and my_bert.txt"
        let ranges = TextMatcher.highlights([.word("bert")], in: name)
        #expect(ranges.map { String(name[$0]) } == ["Bert", "bert"])
        let wild = "Albert.txt"
        #expect(TextMatcher.highlights([.wildcard("*bert*")], in: wild).map { String(wild[$0]) } == ["bert"])
        let accented = "Café Bert.txt"
        #expect(TextMatcher.highlights([.word("cafe")], in: accented).map { String(accented[$0]) } == ["Café"])
        #expect(TextMatcher.highlights([.word("zzz")], in: name).isEmpty)
    }
}

@Suite struct SearchMatcherTests {
    @Test func aBareWordAlsoMatchesTagsTitleAuthorsAndContents() throws {
        let tagged = FakeSubject("a.txt"); tagged.tags = ["Bertram project"]
        let titled = FakeSubject("b.txt"); titled.title = "Bert's notes"
        let authored = FakeSubject("c.txt"); authored.authors = ["Bert Jansch"]
        let body = FakeSubject("d.txt", content: .text("a letter to bert"))
        let none = FakeSubject("e.txt", content: .text("nothing here"))
        #expect(try hits("bert", [tagged, titled, authored, body, none]) == ["a.txt", "b.txt", "c.txt", "d.txt"])
        // name: limits it to names, content: to contents.
        #expect(try hits("name:bert", [tagged, titled, authored, body]).isEmpty)
        #expect(try hits("content:bert", [tagged, titled, authored, body]) == ["d.txt"])
    }

    @Test func severalWordsAreAndedAcrossProperties() throws {
        let a = FakeSubject("quarterly.txt", content: .text("the budget for Q3"))
        let b = FakeSubject("quarterly.txt", content: .text("nothing"))
        #expect(try hits("quarterly budget", [a, b]).count == 1)
    }

    @Test func contentsOnlySpotlightKnowsAreTrustedOnlyForSpotlightResults() throws {
        let pdf = FakeSubject("scan.pdf", content: .unknown)
        let m = SearchMatcher(try parse("needle"))
        #expect(m.evaluate(pdf) == .unknown)
        #expect(m.matches(pdf, trustUnknown: true))
        #expect(!m.matches(pdf, trustUnknown: false))
        // The name decides when it can: no content read needed.
        let named = FakeSubject("needle.pdf", content: .unknown)
        #expect(m.evaluate(named) == .yes)
        #expect(SearchMatcher(try parse("NOT needle")).evaluate(named) == .no)
        #expect(SearchMatcher(try parse("NOT needle")).evaluate(pdf) == .unknown)
    }

    @Test func spotlightsCamelCaseHitsAreDroppedWhenTheContentsCanBeRead() throws {
        // Spotlight returns MyBertFile for "bert" (it splits CamelCase); the readable contents say no.
        let camel = FakeSubject("MyBertFile.txt", content: .text("hello"))
        #expect(try hits("bert", [camel], trustUnknown: true).isEmpty)
    }

    @Test func phrasesInContentsAreCheckedOnTheText() throws {
        let yes = FakeSubject("trip.txt", content: .text("Europe trip budget"))
        let words = FakeSubject("other.txt", content: .text("a trip around Europe"))
        #expect(try hits("\"europe trip\"", [yes, words]) == ["trip.txt"])
        #expect(try hits("content:\"europe trip\"", [yes, words]) == ["trip.txt"])
    }

    @Test func questionMarkIsCheckedAgainAfterSpotlight() throws {
        let items = ["Bert.txt", "Bart.txt", "Beert.txt", "Brt.txt"].map { FakeSubject($0) }
        // Spotlight's B*rt* would return all four.
        #expect(try hits("name:B?rt", items, trustUnknown: true) == ["Bert.txt", "Bart.txt"])
    }

    @Test func folderIsCheckedOnTheResultPath() throws {
        let a = FakeSubject("x.txt", in: "/private/tmp/work/deeper/level3")
        let b = FakeSubject("y.txt", in: "/private/tmp/other")
        #expect(try hits("folder:deeper", [a, b]) == ["x.txt"])
        #expect(try hits("path:work", [a, b]) == ["x.txt"])
        #expect(try hits("NOT folder:deeper", [a, b]) == ["y.txt"])
        #expect(try hits("folder:*eep*", [a, b]) == ["x.txt"])
    }

    @Test func kindsUseTheExtensionTable() throws {
        let folder = FakeSubject("Albums"); folder.isFolder = true; folder.size = nil
        let txt = FakeSubject("notes.txt")
        let png = FakeSubject("photo.png")
        let bin = FakeSubject("big.bin"); bin.contentType = "public.data"
        let all = [folder, txt, png, bin]
        #expect(try hits("kind:folder", all) == ["Albums"])
        #expect(try hits("kind:-folder", all) == ["notes.txt", "photo.png", "big.bin"])
        #expect(try hits("kind:document", all) == ["notes.txt"])
        #expect(try hits("kind:pics", all) == ["photo.png"])
        #expect(try hits("kind:unknown", all) == ["big.bin"])
        #expect(try hits("kind:everything", all).count == 4)
    }

    @Test func sizesAndDatesAndFoldersHaveNoSize() throws {
        let empty = FakeSubject("empty.txt"); empty.size = 0
        let tiny = FakeSubject("tiny.txt"); tiny.size = 5000
        let small = FakeSubject("small.txt"); small.size = 40_000
        let folder = FakeSubject("dir"); folder.isFolder = true; folder.size = nil
        let all = [empty, tiny, small, folder]
        #expect(try hits("size:empty", all) == ["empty.txt"])
        #expect(try hits("size:tiny", all) == ["tiny.txt"])
        #expect(try hits("size:small", all) == ["small.txt"])
        #expect(try hits("size:>4kb", all) == ["tiny.txt", "small.txt"])
        #expect(try hits("NOT size:empty", all) == ["tiny.txt", "small.txt", "dir"])
        #expect(try hits("size:[]", all) == ["dir"])
        let old = FakeSubject("old.txt"); old.modified = day(2025, 6, 1)
        let week = FakeSubject("week.txt"); week.modified = day(2026, 11, 2, 8)
        let today = FakeSubject("today.txt"); today.modified = day(2026, 11, 5, 1)
        #expect(try hits("datemodified:today", [old, week, today]) == ["today.txt"])
        #expect(try hits("datemodified:this week", [old, week, today]) == ["week.txt", "today.txt"])
        #expect(try hits("modified:lastyear", [old, week, today]) == ["old.txt"])
        #expect(try hits("date:<thisweek", [old, week, today]) == ["old.txt"])
        #expect(try hits("datecreated:2026", [old]) == ["old.txt"])
    }

    @Test func extTypeTagsAndEmptyValues() throws {
        let a = FakeSubject("report.PDF"); a.typeText = "PDF document"; a.tags = ["Red"]
        let b = FakeSubject("notes.txt"); b.typeText = "Plain Text Document"
        let c = FakeSubject("Makefile"); c.typeText = "Document"
        #expect(try hits("ext:pdf", [a, b, c]) == ["report.PDF"])
        #expect(try hits("ext:[]", [a, b, c]) == ["Makefile"])
        #expect(try hits("type:pdf", [a, b, c]) == ["report.PDF"])
        #expect(try hits("type:\"text document\"", [a, b, c]) == ["notes.txt"])
        #expect(try hits("type:txt", [a, b, c]) == ["notes.txt"])
        #expect(try hits("tag:red", [a, b, c]) == ["report.PDF"])
        #expect(try hits("tag:[]", [a, b, c]) == ["notes.txt", "Makefile"])
    }

    @Test func orNotAndBracketsCombine() throws {
        let items = names.map { FakeSubject($0) }
        #expect(try hits("Albert OR notes", items) == ["Albert.txt", "notes.txt"])
        #expect(try hits("bert NOT ernie", items) == ["Bert.txt", "Bertie.md", "my_bert.log"])
        #expect(try hits("NOT report", items).count == names.count - 1)
        #expect(try hits("(bert OR albert) ext:log", items) == ["my_bert.log"])
    }

    @Test func relevanceRanksNameStartThenNameThenPropertiesThenContents() throws {
        let m = SearchMatcher(try parse("bert"))
        let start = FakeSubject("Bert.txt")
        let inside = FakeSubject("my_bert.log")
        let tagged = FakeSubject("a.txt"); tagged.tags = ["bert"]
        let body = FakeSubject("b.txt", content: .text("bert"))
        let scores = [start, inside, tagged, body].map(m.score)
        #expect(scores == scores.sorted(by: >))
        #expect(Set(scores).count == 4)
        #expect(SearchMatcher(try parse("kind:document")).score(start) == 0)
    }
}
