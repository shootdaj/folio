// folio-icon: draws Folio's Dock icon (FolioCore's AppIcon) for `make app`.
//   folio-icon <dir>/Folio.iconset      the ten PNGs iconutil turns into Folio.icns
//   folio-icon --svg <dir>              AppIcon.svg and AppIcon-light.svg (kept in Resources/)
// It draws pictures only; it is not the Folio app (docs/plan/RULES.md, rule 0).
import Foundation
import FolioCore

let args = Array(CommandLine.arguments.dropFirst())
do {
    if args.first == "--svg", args.count == 2 {
        let dir = URL(fileURLWithPath: args[1], isDirectory: true)
        try AppIcon.svg(.dark).write(to: dir.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
        try AppIcon.svg(.light).write(to: dir.appendingPathComponent("AppIcon-light.svg"), atomically: true, encoding: .utf8)
        print("wrote \(dir.path)/AppIcon.svg and AppIcon-light.svg")
    } else if args.count == 1 {
        let written = try AppIcon.writeIconset(to: URL(fileURLWithPath: args[0], isDirectory: true))
        print("wrote \(written.count) PNGs to \(args[0])")
    } else {
        FileHandle.standardError.write(Data("usage: folio-icon <dir>.iconset | folio-icon --svg <dir>\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("folio-icon: \(error)\n".utf8))
    exit(1)
}
