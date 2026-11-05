import Foundation
import Testing
@testable import FolioCore

private func compile(_ text: String) throws -> String? { SpotlightPredicate.compile(try parse(text)) }

private let bert = "(* == \"bert*\"cdw || kMDItemTextContent == \"bert*\"cdw)"

@Suite struct SpotlightPredicateTests {
    @Test func aBareWordIsSpotlightsOwnMenuQuery() throws {
        #expect(try compile("bert") == bert)
    }

    @Test func andOrNotAndBrackets() throws {
        let notes = "(* == \"notes*\"cdw || kMDItemTextContent == \"notes*\"cdw)"
        #expect(try compile("bert notes") == "(" + bert + " && " + notes + ")")
        #expect(try compile("bert OR notes") == "(" + bert + " || " + notes + ")")
        #expect(try compile("NOT bert") == "!(" + bert + ")")
        #expect(try compile("-bert") == "!(" + bert + ")")
        #expect(try compile("bert OR (notes AND bert)") == "(" + bert + " || (" + notes + " && " + bert + "))")
    }

    @Test func wildcardsAreCaseAndAccentInsensitiveWithoutWordMode() throws {
        #expect(try compile("*bert*") == "(* == \"*bert*\"cd || kMDItemTextContent == \"*bert*\"cd)")
        #expect(try compile("*bert") == "(* == \"*bert*\"cd || kMDItemTextContent == \"*bert*\"cd)")
        // ? is ignored by Spotlight on macOS 15 (tested): sent as *, checked again after.
        #expect(try compile("B?rt") == "(* == \"B*rt*\"cd || kMDItemTextContent == \"B*rt*\"cd)")
    }

    @Test func phrasesMatchNamesWholeAndContentsWordByWord() throws {
        #expect(try compile("\"budget 2024\"") ==
            "(* == \"*budget 2024*\"cd || (kMDItemTextContent == \"budget*\"cdw && kMDItemTextContent == \"2024*\"cdw))")
        #expect(try compile("content:\"europe trip\"") ==
            "(kMDItemTextContent == \"europe*\"cdw && kMDItemTextContent == \"trip*\"cdw)")
        #expect(try compile("name:\"budget 2024\"") == "kMDItemFSName == \"*budget 2024*\"cd")
    }

    @Test func nameExtTypeTagAuthorTitleContent() throws {
        #expect(try compile("name:bert") == "kMDItemFSName == \"bert*\"cdw")
        #expect(try compile("ext:pdf") == "kMDItemFSName == \"*.pdf\"c")
        #expect(try compile("ext:.TXT") == "kMDItemFSName == \"*.txt\"c")
        #expect(try compile("type:pdf") == "(kMDItemKind == \"pdf*\"cdw || kMDItemFSName == \"*.pdf\"c)")
        #expect(try compile("tag:vacation") == "(kMDItemUserTags == \"vacation*\"cdw || kMDItemKeywords == \"vacation*\"cdw)")
        #expect(try compile("tag:[]") == "kMDItemUserTags != \"*\"")
        #expect(try compile("author:king") == "kMDItemAuthors == \"king*\"cdw")
        #expect(try compile("author:[]") == "kMDItemAuthors != \"*\"")
        #expect(try compile("title:quarterly") == "kMDItemTitle == \"quarterly*\"cdw")
        #expect(try compile("content:needle") == "kMDItemTextContent == \"needle*\"cdw")
    }

    @Test func kindsGoAsTypeTreesAndTheExtensionTable() throws {
        #expect(try compile("kind:folder") == "kMDItemContentType == \"public.folder\"")
        let pictures = try #require(try compile("kind:picture"))
        #expect(pictures.hasPrefix("(kMDItemContentTypeTree == \"public.image\" || kMDItemFSName == \"*.arw\"c"))
        #expect(pictures.contains("kMDItemFSName == \"*.png\"c"))
        let docs = try #require(try compile("kind:=document"))
        #expect(docs.contains("kMDItemContentTypeTree == \"com.adobe.pdf\""))
        #expect(docs.contains("kMDItemFSName == \"*.txt\"c"))
        // No Mac kind at all: Spotlight is skipped.
        #expect(try compile("kind:game") == nil)
    }

    @Test func sizesGoAsPairsNeverInRange() throws {
        #expect(try compile("size:empty") == "(kMDItemFSSize == 0 && kMDItemContentType != \"public.folder\")")
        #expect(try compile("size:tiny") == "(kMDItemFSSize >= 1 && kMDItemFSSize <= 16384 && kMDItemContentType != \"public.folder\")")
        #expect(try compile("size:gigantic") == "(kMDItemFSSize >= 4294967297 && kMDItemContentType != \"public.folder\")")
        #expect(try compile("size:>50MB") == "(kMDItemFSSize >= 52428801 && kMDItemContentType != \"public.folder\")")
        #expect(try compile("size:10mb..20mb") == "(kMDItemFSSize >= 10485760 && kMDItemFSSize <= 20971520 && kMDItemContentType != \"public.folder\")")
        #expect(try !(compile("size:huge") ?? "").contains("InRange"))
    }

    @Test func datesGoAsStartAndEndNeverEqualsTime() throws {
        #expect(try compile("datemodified:today") ==
            "(kMDItemFSContentChangeDate >= $time.iso(2026-11-05T00:00:00Z) && kMDItemFSContentChangeDate < $time.iso(2026-11-06T00:00:00Z))")
        #expect(try compile("date:this week") ==
            "(kMDItemFSContentChangeDate >= $time.iso(2026-11-02T00:00:00Z) && kMDItemFSContentChangeDate < $time.iso(2026-11-09T00:00:00Z))")
        #expect(try compile("datecreated:>2024") == "kMDItemFSCreationDate >= $time.iso(2025-01-01T00:00:00Z)")
        #expect(try compile("modified:<lastyear") == "kMDItemFSContentChangeDate < $time.iso(2025-01-01T00:00:00Z)")
        for text in ["datemodified:today", "date:lastmonth", "created:thisyear"] {
            let s = try #require(try compile(text))
            #expect(!s.contains("== $time"))
            #expect(!s.contains("InRange"))
        }
    }

    @Test func folderIsCheckedOnTheResultsNotInSpotlight() throws {
        #expect(try compile("folder:work") == SpotlightPredicate.everything)
        #expect(try compile("folder:work bert") == bert)
        // Under NOT the folder term lets everything through for the check after.
        #expect(try compile("NOT folder:work") == SpotlightPredicate.everything)
        #expect(try compile("bert NOT folder:work") == bert)
    }

    @Test func approximateTermsUnderNotLetEverythingThrough() throws {
        // A superset under NOT would lose true results; the matcher decides instead.
        #expect(try compile("NOT B?rt") == SpotlightPredicate.everything)
        #expect(try compile("NOT \"budget 2024\"") == SpotlightPredicate.everything)
        #expect(try compile("notes NOT kind:picture") == "(* == \"notes*\"cdw || kMDItemTextContent == \"notes*\"cdw)")
        // Exact terms keep their NOT.
        #expect(try compile("NOT size:empty") == "!((kMDItemFSSize == 0 && kMDItemContentType != \"public.folder\"))")
        #expect(try compile("NOT kind:folder") == "!(kMDItemContentType == \"public.folder\")")
    }

    @Test func anEmptyQueryAsksForEverythingAndQuotesAreEscaped() throws {
        #expect(try compile("") == "kMDItemDisplayName == \"*\"")
        #expect(SpotlightPredicate.compile(.term(QueryTerm(.name, .text(.exact("say \"hi\" \\ there"))))) ==
            "kMDItemFSName == \"say \\\"hi\\\" \\\\ there\"cd")
    }

    @Test func everyCompiledQueryIsOneSpotlightCanRead() throws {
        for text in ["bert", "*bert*", "B?rt", "\"budget 2024\"", "NOT report", "kind:document size:tiny", "content:needle",
                     "datemodified:today", "tag:[]", "kind:picture OR kind:video", "name:~=ber", "ext:pdf", "type:pdf"] {
            let s = try #require(try compile(text))
            #expect(NSPredicate(fromMetadataQueryString: s) != nil, "\(text): \(s)")
        }
    }
}
