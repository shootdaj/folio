// ff: opens a folder (or a file's folder, with it selected) in Folio, from the shell.
// It only builds a folio: URL and hands it to `open -b com.anshul.folio`, which starts Folio when it is not
// running. Never run on a host Mac during development (docs/plan/RULES.md, rule 0): the VM runs it.
import Foundation
import FolioLink

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let cwd = FileManager.default.currentDirectoryPath
switch FFArguments.parse(Array(CommandLine.arguments.dropFirst()), cwd: cwd) {
case .help:
    print(FFArguments.usage)
case .failure(let message):
    fail(message, 2)
case .open(let request):
    if let path = request.resolvedPath, !FileManager.default.fileExists(atPath: path) {
        fail("ff: no such file or folder: \(path)", 1)
    }
    let command = FFArguments.openCommand(for: request)
    let open = Process()
    open.executableURL = URL(fileURLWithPath: command[0])
    open.arguments = Array(command.dropFirst())
    do {
        try open.run()
    } catch {
        fail("ff: could not run /usr/bin/open: \(error.localizedDescription)", 1)
    }
    open.waitUntilExit()
    if open.terminationStatus != 0 {
        fail("ff: macOS could not reach Folio (\(FolioRequest.bundleID)). Install it with `make install`.", open.terminationStatus)
    }
}
