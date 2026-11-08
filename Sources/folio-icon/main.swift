// folio-icon: draws Folio's Dock icon (FolioCore's AppIcon) for `make app`.
//   folio-icon <dir>/Folio.iconset      the ten PNGs iconutil turns into Folio.icns (the light look)
//   folio-icon --icon <dir>/AppIcon.icon the Icon Composer file actool turns into Assets.car (light and dark)
//   folio-icon --png <file>.png [--dark] the 1024 px picture kept in Resources/AppIcon.png (AppIcon-dark.png)
// It draws pictures only; it is not the Folio app (docs/plan/RULES.md, rule 0).
import Foundation
import FolioCore

let args = Array(CommandLine.arguments.dropFirst())
do {
    if args.first == "--png", args.count == 2 || (args.count == 3 && args[2] == "--dark") {
        try AppIcon.writePNG(to: URL(fileURLWithPath: args[1]), pixels: Int(AppIcon.canvas), look: args.count == 3 ? .dark : .light)
        print("wrote \(args[1])")
    } else if args.first == "--icon", args.count == 2 {
        try AppIcon.writeIconFile(to: URL(fileURLWithPath: args[1], isDirectory: true))
        print("wrote \(args[1])")
    } else if args.count == 1, !args[0].hasPrefix("--") {
        let written = try AppIcon.writeIconset(to: URL(fileURLWithPath: args[0], isDirectory: true))
        print("wrote \(written.count) PNGs to \(args[0])")
    } else {
        FileHandle.standardError.write(Data("usage: folio-icon <dir>.iconset | --icon <dir>.icon | --png <file>.png [--dark]\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("folio-icon: \(error)\n".utf8))
    exit(1)
}
