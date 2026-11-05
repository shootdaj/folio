import Foundation
import Testing
@testable import FolioCore

/// 2026-11-05 (a Thursday) 12:00 UTC, weeks starting Monday.
let searchContext = BucketContext(now: day(2026, 11, 5, 12), calendar: calendar(firstWeekday: 2))

func parse(_ text: String) throws -> QueryNode { try SearchQuery.parse(text, context: searchContext) }

func word(_ w: String, _ p: SearchProperty = .any) -> QueryNode { .term(QueryTerm(p, .text(.word(w)))) }

@Suite struct SearchQueryParserTests {
    @Test func aBareWordIsAWordStartTermOnEverything() throws {
        #expect(try parse("bert") == word("bert"))
        #expect(try parse("  ") == .all)
        #expect(try parse("") == .all)
    }

    @Test func spacesAndAndBothMeanAnd() throws {
        #expect(try parse("quarterly budget") == .and([word("quarterly"), word("budget")]))
        #expect(try parse("quarterly AND budget") == .and([word("quarterly"), word("budget")]))
        #expect(try parse("a b c") == .and([word("a"), word("b"), word("c")]))
    }

    @Test func orAndNotOnlyInCapitals() throws {
        #expect(try parse("apple OR pear") == .or([word("apple"), word("pear")]))
        #expect(try parse("apple NOT pear") == .and([word("apple"), .not(word("pear"))]))
        // Lowercase and, or, not are plain words.
        #expect(try parse("apple or pear") == .and([word("apple"), word("or"), word("pear")]))
        #expect(try parse("not this") == .and([word("not"), word("this")]))
        #expect(try parse("rock and roll") == .and([word("rock"), word("and"), word("roll")]))
    }

    @Test func andAndOrBindLeftToRightWithNoPrecedence() throws {
        // apple AND pear OR plum = (apple AND pear) OR plum
        #expect(try parse("apple AND pear OR plum") == .or([.and([word("apple"), word("pear")]), word("plum")]))
        // apple OR pear AND plum = (apple OR pear) AND plum
        #expect(try parse("apple OR pear AND plum") == .and([.or([word("apple"), word("pear")]), word("plum")]))
        // A space is AND at the same level.
        #expect(try parse("apple OR pear plum") == .and([.or([word("apple"), word("pear")]), word("plum")]))
    }

    @Test func bracketsGroup() throws {
        #expect(try parse("apple OR (pear AND plum)") == .or([word("apple"), .and([word("pear"), word("plum")])]))
        #expect(try parse("(a OR b) c") == .and([.or([word("a"), word("b")]), word("c")]))
        #expect(try parse("((bert))") == word("bert"))
    }

    @Test func notAndMinusNegateTheNextTerm() throws {
        #expect(try parse("NOT report") == .not(word("report")))
        #expect(try parse("-draft") == .not(word("draft")))
        #expect(try parse("notes -draft") == .and([word("notes"), .not(word("draft"))]))
        #expect(try parse("NOT (a OR b)") == .not(.or([word("a"), word("b")])))
        // Double negation does not cancel.
        #expect(try parse("--picture") == .not(word("picture")))
        // A hyphen inside a word is part of it.
        #expect(try parse("report-2024") == word("report-2024"))
    }

    @Test func quotesMakePhrasesAndDoubledQuotesAreLiteral() throws {
        #expect(try parse("\"budget 2024\"") == .term(QueryTerm(.any, .text(.phrase("budget 2024")))))
        #expect(try parse("\"The \"\"blue\"\" team\"") == .term(QueryTerm(.any, .text(.phrase("The \"blue\" team")))))
        #expect(try parse("\"bert\"") == .term(QueryTerm(.any, .text(.wordEqual("bert")))))
        // Operators inside quotes are words.
        #expect(try parse("\"a OR b\"") == .term(QueryTerm(.any, .text(.phrase("a OR b")))))
        // Still being typed: the phrase runs to the end.
        #expect(try parse("\"europe tr") == .term(QueryTerm(.any, .text(.phrase("europe tr")))))
    }

    @Test func starsAndQuestionMarksMakeWildcards() throws {
        #expect(try parse("*bert*") == .term(QueryTerm(.any, .text(.wildcard("*bert*")))))
        #expect(try parse("*bert") == .term(QueryTerm(.any, .text(.wildcard("*bert")))))
        #expect(try parse("B?rt") == .term(QueryTerm(.any, .text(.wildcard("B?rt")))))
        #expect(try parse("*.pdf") == .term(QueryTerm(.any, .text(.wildcard("*.pdf")))))
    }

    @Test func everyPropertyKeywordAndItsAliases() throws {
        let cases: [(String, SearchProperty)] = [
            ("name", .name), ("filename", .name), ("file", .name), ("type", .type), ("folder", .folder), ("path", .folder),
            ("under", .folder), ("in", .folder), ("folderpath", .folder), ("tag", .tag), ("tags", .tag), ("keywords", .tag),
            ("author", .author), ("authors", .author), ("by", .author), ("title", .title), ("subject", .title),
            ("content", .content), ("contents", .content), ("System.Author", .author), ("NAME", .name),
        ]
        for (keyword, property) in cases {
            #expect(try parse(keyword + ":bert") == word("bert", property), "\(keyword):")
        }
        #expect(try parse("ext:pdf") == .term(QueryTerm(.ext, .text(.exact("pdf")))))
        #expect(try parse("ext:.PDF") == .term(QueryTerm(.ext, .text(.exact("pdf")))))
        #expect(try parse("fileext:txt") == .term(QueryTerm(.ext, .text(.exact("txt")))))
        #expect(try parse("kind:pics") == .term(QueryTerm(.kind, .kind(.picture))))
        #expect(try parse("kind:=document") == .term(QueryTerm(.kind, .kind(.document))))
        #expect(try parse("kind:folder") == .term(QueryTerm(.kind, .kind(.folder))))
        #expect(try parse("kind:everything") == .all)
        #expect(try parse("size:tiny") == .term(QueryTerm(.size, .size(SizeRange(1, 16384)))))
        #expect(try parse("name:\"budget 2024\"") == .term(QueryTerm(.name, .text(.phrase("budget 2024")))))
        #expect(try parse("name:*bert*") == .term(QueryTerm(.name, .text(.wildcard("*bert*")))))
    }

    @Test func anUnknownKeywordIsAPlainWord() throws {
        #expect(try parse("foo:bar") == word("foo:bar"))
        #expect(try parse("10:30") == word("10:30"))
    }

    @Test func propertyOperators() throws {
        #expect(try parse("kind:-picture") == .not(.term(QueryTerm(.kind, .kind(.picture)))))
        #expect(try parse("kind:<>picture") == .not(.term(QueryTerm(.kind, .kind(.picture)))))
        #expect(try parse("kind:NOT picture") == .not(.term(QueryTerm(.kind, .kind(.picture)))))
        #expect(try parse("-kind:picture") == .not(.term(QueryTerm(.kind, .kind(.picture)))))
        #expect(try parse("name:=Bert.txt") == .term(QueryTerm(.name, .text(.exact("Bert.txt")))))
        #expect(try parse("name:~=ber") == .term(QueryTerm(.name, .text(.contains("ber")))))
        #expect(try parse("name:~~ber") == .term(QueryTerm(.name, .text(.contains("ber")))))
        #expect(try parse("name:~<Al") == .term(QueryTerm(.name, .text(.valueStarts("Al")))))
        #expect(try parse("name:~>txt") == .term(QueryTerm(.name, .text(.valueEnds("txt")))))
        #expect(try parse("name:~!ber") == .not(.term(QueryTerm(.name, .text(.contains("ber"))))))
        #expect(try parse("name:$=bert") == .term(QueryTerm(.name, .text(.wordEqual("bert")))))
        #expect(try parse("name:$<bert") == word("bert", .name))
    }

    @Test func aKeywordAppliesToABracketGroup() throws {
        // authors:(Charlie AND Herb) is both authors; authors:Charlie AND Herb is Herb anywhere.
        #expect(try parse("author:(Charlie OR Herb)") == .or([word("Charlie", .author), word("Herb", .author)]))
        #expect(try parse("author:Charlie AND Herb") == .and([word("Charlie", .author), word("Herb")]))
    }

    @Test func emptyBracketsMeanNoValue() throws {
        #expect(try parse("tag:[]") == .term(QueryTerm(.tag, .empty)))
        #expect(try parse("author:[]") == .term(QueryTerm(.author, .empty)))
        #expect(try parse("tag:-[]") == .not(.term(QueryTerm(.tag, .empty))))
    }

    @Test func aKeywordWithNothingAfterItYetMatchesEverything() throws {
        #expect(try parse("bert name:") == word("bert"))
        #expect(try parse("name: bert") == word("bert"))
        #expect(try parse("type:") == .all)
    }

    @Test func dateWordsWrittenApartAreOneValue() throws {
        let week = try parse("datemodified:this week")
        let joined = try parse("datemodified:thisweek")
        #expect(week == joined)
        #expect(try parse("modified:last month notes") == .and([try parse("datemodified:lastmonth"), word("notes")]))
        // Only after a date keyword: elsewhere "this week" is two words.
        #expect(try parse("this week") == .and([word("this"), word("week")]))
    }

    @Test func errors() {
        #expect(throws: SearchQueryError.unmatchedParenthesis) { try parse("(bert") }
        #expect(throws: SearchQueryError.unmatchedParenthesis) { try parse("bert)") }
        #expect(throws: SearchQueryError.unmatchedParenthesis) { try parse("a (b OR c") }
        #expect(throws: SearchQueryError.missingOperand("AND")) { try parse("bert AND") }
        #expect(throws: SearchQueryError.missingOperand("AND")) { try parse("AND bert") }
        #expect(throws: SearchQueryError.missingOperand("OR")) { try parse("bert OR") }
        #expect(throws: SearchQueryError.missingOperand("OR")) { try parse("a OR OR b") }
        #expect(throws: SearchQueryError.missingOperand("NOT")) { try parse("NOT") }
        #expect(throws: SearchQueryError.missingOperand("NOT")) { try parse("bert NOT") }
        #expect(throws: SearchQueryError.badValue(property: "size", value: "abc")) { try parse("size:abc") }
        #expect(throws: SearchQueryError.badValue(property: "size", value: ">1zb")) { try parse("size:>1zb") }
        #expect(throws: SearchQueryError.badValue(property: "kind", value: "spaceship")) { try parse("kind:spaceship") }
        #expect(throws: SearchQueryError.badValue(property: "datemodified", value: "someday")) { try parse("datemodified:someday") }
        #expect(throws: SearchQueryError.badValue(property: "date", value: "13/45/2020")) { try parse("date:13/45/2020") }
        #expect(SearchQueryError.missingOperand("AND").description == "AND needs a term on each side")
        #expect(SearchQueryError.unmatchedParenthesis.description == "A bracket is not closed")
    }

    @Test func positiveNameTermsLeaveOutNegatedOnes() throws {
        let q = try parse("bert name:*al* NOT report kind:document")
        #expect(q.positiveNameTerms == [.word("bert"), .wildcard("*al*")])
    }
}
