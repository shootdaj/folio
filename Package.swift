// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Swift model (no AppKit), testable with `swift test`.
        .target(name: "FolioCore"),
        // The folio: URL and the ff command line, shared by the app and ff (Foundation only).
        .target(name: "FolioLink"),
        // The AppKit app. `make app` wraps this binary in build/Folio.app.
        .executableTarget(name: "Folio", dependencies: ["FolioCore", "FolioLink"], linkerSettings: [.linkedFramework("NetFS")]),
        // `ff <path>`: opens a folder in Folio from the shell (`make install-cli`).
        .executableTarget(name: "ff", dependencies: ["FolioLink"]),
        // Draws the Dock icon's iconset for `make app` (iconutil turns it into Folio.icns).
        .executableTarget(name: "folio-icon", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore", "FolioLink"]),
    ]
)
