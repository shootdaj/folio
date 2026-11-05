import Foundation
import Testing
@testable import FolioLink

/// The folio: URL `ff` sends and the app reads: every parameter, percent-encoding both ways, relative
/// paths resolved against the folder `ff` ran in, and what the app then shows.
@Suite struct FolioRequestTests {
    private func parse(_ s: String) -> FolioRequest? { URL(string: s).flatMap(FolioRequest.parse) }

    @Test func readsEveryParameter() throws {
        let r = try #require(parse("folio://open?path=/tmp/a&cwd=/Users/x&select=1&newWindow=1&newTab=1&search=bert"))
        #expect(r.path == "/tmp/a")
        #expect(r.cwd == "/Users/x")
        #expect(r.select && r.newWindow && r.newTab)
        #expect(r.search == "bert")
    }

    @Test func flagsAreOffUnlessSaidAndAcceptOneTrueYesOrNoValue() throws {
        let plain = try #require(parse("folio://open?path=/tmp"))
        #expect(!plain.select && !plain.newWindow && !plain.newTab && plain.search == nil && plain.cwd == nil)
        let words = try #require(parse("folio://open?path=/tmp&select=true&newWindow=yes&newTab"))
        #expect(words.select && words.newWindow && words.newTab)
        let off = try #require(parse("folio://open?path=/tmp&select=0&newWindow=false&newTab=no"))
        #expect(!off.select && !off.newWindow && !off.newTab)
        #expect(try #require(parse("folio://open?path=/tmp&search=")).search == nil, "an empty search is no search")
    }

    @Test func percentEncodingRoundTripsSpacesAmpersandsPlusAndUnicode() throws {
        let path = "/tmp/Ä folder & co/50% + more?#=.txt"
        let query = "kind:document AND \"two words\" size:>1MB & stuff+"
        let r = FolioRequest(path: path, cwd: "/Users/a b", select: true, search: query)
        let text = r.url.absoluteString
        #expect(text.hasPrefix("folio://open?"))
        #expect(!text.contains(" "), "spaces are encoded")
        #expect(!text.contains("& co"), "an ampersand inside a value is encoded")
        let back = try #require(FolioRequest.parse(URL(string: text)!))
        #expect(back == r)
        #expect(back.path == path && back.search == query && back.cwd == "/Users/a b")
        // A plus sign stays a plus (it is not a space in a folio: URL).
        #expect(try #require(parse("folio://open?path=/tmp/a+b")).path == "/tmp/a+b")
        #expect(try #require(parse("folio://open?path=/tmp/a%20b%2Bc")).path == "/tmp/a b+c")
    }

    @Test func otherSchemesAndOtherCommandsAreNotRequests() {
        #expect(parse("file:///tmp") == nil)
        #expect(parse("https://open?path=/tmp") == nil)
        #expect(parse("folio://delete?path=/tmp") == nil)
        #expect(parse("FOLIO://OPEN?path=/tmp")?.path == "/tmp", "scheme and host ignore case")
        #expect(parse("folio:open?path=/tmp")?.path == "/tmp", "folio:open without the slashes")
    }

    @Test func relativePathsResolveAgainstTheFolderFFRanIn() {
        func resolved(_ p: String, _ cwd: String?) -> String? { FolioRequest(path: p, cwd: cwd).resolvedPath }
        #expect(resolved("docs", "/Users/a/work") == "/Users/a/work/docs")
        #expect(resolved("./docs/../notes.md", "/Users/a/work") == "/Users/a/work/notes.md")
        #expect(resolved("..", "/Users/a/work") == "/Users/a")
        #expect(resolved(".", "/Users/a/work") == "/Users/a/work")
        #expect(resolved("/abs/path/", "/Users/a/work") == "/abs/path", "absolute paths ignore cwd")
        #expect(resolved("~/Downloads", "/x") == NSHomeDirectory() + "/Downloads")
        #expect(resolved("docs", nil) == "/docs", "no cwd: relative to the top of the disk")
        #expect(FolioRequest(path: nil, newWindow: true).resolvedPath == nil, "no path: Folio's start place")
        #expect(resolved("../..", "/a") == "/")
    }

    // MARK: What the app shows

    private func kinds(_ table: [String: FolioRequest.ItemKind]) -> (String) -> FolioRequest.ItemKind {
        { table[$0] ?? .missing }
    }

    @Test func aFolderOpensItselfAFileOpensItsFolderWithItSelected() throws {
        let k = kinds(["/w": .folder, "/w/a.txt": .file, "/w/sub": .folder])
        let folder = try #require(FolioRequest(path: "/w").plan(kind: k))
        #expect(folder == FolioRequest.Plan(folder: "/w", select: nil, search: nil, placement: .usual))
        let file = try #require(FolioRequest(path: "a.txt", cwd: "/w").plan(kind: k))
        #expect(file.folder == "/w" && file.select == "/w/a.txt", "Explorer's /select for a file")
        let reveal = try #require(FolioRequest(path: "/w/sub", select: true).plan(kind: k))
        #expect(reveal.folder == "/w" && reveal.select == "/w/sub", "--reveal on a folder selects it in its parent")
        #expect(FolioRequest(path: "/w/gone").plan(kind: k) == nil, "a path that is not there opens nothing")
    }

    @Test func placementSearchAndStartPlace() throws {
        let k = kinds(["/w": .folder, "/w/a.txt": .file])
        #expect(try #require(FolioRequest(path: "/w", newWindow: true).plan(kind: k)).placement == .newWindow)
        #expect(try #require(FolioRequest(path: "/w", newTab: true).plan(kind: k)).placement == .newTab)
        let search = try #require(FolioRequest(path: "/w", select: true, search: "bert").plan(kind: k))
        #expect(search.folder == "/w" && search.search == "bert" && search.select == nil, "a search runs in the folder itself")
        let inFile = try #require(FolioRequest(path: "/w/a.txt", search: "bert").plan(kind: k))
        #expect(inFile.folder == "/w", "a search given a file runs in its folder")
        let start = try #require(FolioRequest(path: nil, newWindow: true).plan(kind: k))
        #expect(start.folder == nil && start.placement == .newWindow, "no path: the start place (Home)")
        let root = try #require(FolioRequest(path: "/", select: true).plan(kind: { _ in .folder }))
        #expect(root.folder == "/" && root.select == nil, "the top of the disk has no parent to select it in")
    }
}

/// `ff`'s command line: ff, ff <path>, -n, -t, --search, --reveal, and its mistakes.
@Suite struct FFArgumentsTests {
    private let cwd = "/Users/a/work"

    private func request(_ args: [String]) -> FolioRequest? {
        if case .open(let r) = FFArguments.parse(args, cwd: cwd) { return r }
        return nil
    }

    private func error(_ args: [String]) -> String? {
        if case .failure(let message) = FFArguments.parse(args, cwd: cwd) { return message }
        return nil
    }

    @Test func noArgumentsOpensTheCurrentFolder() {
        #expect(request([]) == FolioRequest(path: cwd, cwd: cwd))
    }

    @Test func aPathOpensItRelativeToTheCurrentFolder() {
        #expect(request(["docs"]) == FolioRequest(path: "docs", cwd: cwd))
        #expect(request(["/tmp"]) == FolioRequest(path: "/tmp", cwd: cwd))
        #expect(request(["--", "-odd-name"]) == FolioRequest(path: "-odd-name", cwd: cwd), "-- ends the options")
    }

    @Test func newWindowAndNewTab() {
        #expect(request(["-n", "docs"]) == FolioRequest(path: "docs", cwd: cwd, newWindow: true))
        #expect(request(["docs", "--new-window"]) == FolioRequest(path: "docs", cwd: cwd, newWindow: true))
        #expect(request(["-t", "docs"]) == FolioRequest(path: "docs", cwd: cwd, newTab: true))
        #expect(request(["--new-tab"]) == FolioRequest(path: cwd, cwd: cwd, newTab: true))
    }

    @Test func searchTakesAQueryAndAnOptionalPath() {
        #expect(request(["--search", "bert"]) == FolioRequest(path: cwd, cwd: cwd, search: "bert"))
        #expect(request(["--search", "kind:document bert", "docs"]) == FolioRequest(path: "docs", cwd: cwd, search: "kind:document bert"))
        #expect(request(["--search=bert", "docs"]) == FolioRequest(path: "docs", cwd: cwd, search: "bert"))
        #expect(request(["-s", "bert"]) == FolioRequest(path: cwd, cwd: cwd, search: "bert"))
        #expect(error(["--search"]) != nil)
        #expect(error(["--search", ""]) != nil)
    }

    @Test func revealSelectsAndIsTheAliasForSelect() {
        #expect(request(["--reveal", "a.txt"]) == FolioRequest(path: "a.txt", cwd: cwd, select: true))
        #expect(request(["--select", "a.txt"]) == FolioRequest(path: "a.txt", cwd: cwd, select: true))
        #expect(request(["-r", "a.txt", "-n"]) == FolioRequest(path: "a.txt", cwd: cwd, select: true, newWindow: true))
        #expect(error(["--reveal"]) != nil, "--reveal needs a path")
    }

    @Test func mistakesSayWhatIsWrong() throws {
        #expect(try #require(error(["-n", "-t", "x"])).contains("-n"))
        #expect(try #require(error(["a", "b"])).contains("one path"))
        #expect(try #require(error(["--reveal", "a", "b"])).contains("one path"))
        #expect(try #require(error(["--frobnicate"])).contains("--frobnicate"))
        #expect(error(["--search", "q", "--reveal", "a"]) != nil)
        if case .help = FFArguments.parse(["-h"], cwd: cwd) {} else { Issue.record("-h is help") }
        if case .help = FFArguments.parse(["--help"], cwd: cwd) {} else { Issue.record("--help is help") }
        #expect(FFArguments.usage.contains("--reveal") && FFArguments.usage.contains("--search"))
    }

    @Test func theURLItSendsCarriesTheShellsFolder() throws {
        let r = try #require(request(["-t", "docs"]))
        let back = try #require(FolioRequest.parse(r.url))
        #expect(back.resolvedPath == "/Users/a/work/docs" && back.newTab)
        #expect(FFArguments.openCommand(for: r) == ["/usr/bin/open", "-b", "com.anshul.folio", r.url.absoluteString])
    }
}
