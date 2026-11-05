import Foundation

/// The `ff` command line, read into the request it sends Folio.
public enum FFArguments {
    public enum Parsed: Equatable, Sendable {
        case open(FolioRequest)
        case help
        case failure(String)
    }

    public static let usage = """
        usage: ff [options] [path]

          ff                    open the current folder in Folio
          ff <path>             open a folder; a file opens its folder with it selected
          ff -n <path>          in a new window          (--new-window)
          ff -t <path>          in a new tab             (--new-tab)
          ff --reveal <path>    select it in its folder  (-r, --select; Explorer's /select)
          ff --search "<query>" [path]
                                search the folder (default: the current one), as typed in the box
          ff -h                 this help

        Paths may be relative to the current folder. Folio starts if it is not running.
        """

    public static func parse(_ args: [String], cwd: String) -> Parsed {
        var path: String?
        var newWindow = false, newTab = false, select = false
        var search: String?
        var i = 0
        var optionsDone = false

        func setPath(_ p: String) -> String? {
            if path != nil { return "ff: one path at a time" }
            path = p
            return nil
        }

        while i < args.count {
            let a = args[i]
            i += 1
            if optionsDone || !a.hasPrefix("-") || a == "-" {
                if let e = setPath(a) { return .failure(e) }
                continue
            }
            switch a {
            case "--": optionsDone = true
            case "-h", "--help": return .help
            case "-n", "--new-window": newWindow = true
            case "-t", "--new-tab": newTab = true
            case "-r", "--reveal", "--select":
                guard i < args.count else { return .failure("ff: \(a) needs a path") }
                select = true
                if let e = setPath(args[i]) { return .failure(e) }
                i += 1
            case "-s", "--search":
                guard i < args.count, !args[i].isEmpty else { return .failure("ff: \(a) needs a query") }
                search = args[i]
                i += 1
            default:
                if a.hasPrefix("--search=") {
                    let q = String(a.dropFirst("--search=".count))
                    guard !q.isEmpty else { return .failure("ff: --search needs a query") }
                    search = q
                } else {
                    return .failure("ff: unknown option \(a) (ff -h lists them)")
                }
            }
        }
        if newWindow && newTab { return .failure("ff: -n and -t do not go together: pick a new window or a new tab") }
        if select && search != nil { return .failure("ff: --reveal and --search do not go together") }
        return .open(FolioRequest(path: path ?? cwd, cwd: cwd, select: select, newWindow: newWindow,
                                  newTab: newTab, search: search))
    }

    /// How `ff` hands the request over: `open -b` starts Folio when it is not running, and passes the URL.
    public static func openCommand(for request: FolioRequest) -> [String] {
        ["/usr/bin/open", "-b", FolioRequest.bundleID, request.url.absoluteString]
    }
}
