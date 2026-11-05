import Foundation
import Testing
@testable import FolioCore

/// Copy path and Copy as path (Explorer's Ctrl+Shift+C): full paths one per line, quoted so they paste
/// into Terminal as one argument each.
@Suite struct PathTextTests {
    @Test func copyAsPathQuotesEachPathOnItsOwnLine() {
        let urls = [URL(fileURLWithPath: "/private/tmp/work/a b.txt"), URL(fileURLWithPath: "/private/tmp/work/target")]
        #expect(PathText.quoted(urls) == "\"/private/tmp/work/a b.txt\"\n\"/private/tmp/work/target\"")
    }

    @Test func characterTheShellReadsInsideQuotesAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/say \"hi\" $HOME `x` back\\slash.txt")
        #expect(PathText.quoted([url]) == "\"/tmp/say \\\"hi\\\" \\$HOME \\`x\\` back\\\\slash.txt\"")
    }

    @Test func copyPathIsPlainOnePerLine() {
        let urls = [URL(fileURLWithPath: "/a/one.txt"), URL(fileURLWithPath: "/a/two words")]
        #expect(PathText.plain(urls) == "/a/one.txt\n/a/two words")
        #expect(PathText.plain([]) == "")
        #expect(PathText.quoted([]) == "")
    }

    @Test func aFolderPathHasNoTrailingSlash() {
        #expect(PathText.quoted([URL(fileURLWithPath: "/a/Docs", isDirectory: true)]) == "\"/a/Docs\"")
    }
}
