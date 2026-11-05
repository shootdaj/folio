import Foundation

/// The text Copy path and Copy as path put on the pasteboard.
public enum PathText {
    /// Copy path: the full paths, one per line.
    public static func plain(_ urls: [URL]) -> String {
        urls.map(path).joined(separator: "\n")
    }

    /// Copy as path (Explorer's Ctrl+Shift+C): each path in double quotes, one per line. What the shell
    /// still reads inside double quotes (\ " $ `) is escaped, so each line pastes as one argument.
    public static func quoted(_ urls: [URL]) -> String {
        urls.map { url in
            var out = "\""
            for ch in path(url) {
                if ch == "\\" || ch == "\"" || ch == "$" || ch == "`" { out.append("\\") }
                out.append(ch)
            }
            return out + "\""
        }.joined(separator: "\n")
    }

    private static func path(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }
}
