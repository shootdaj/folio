// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Swift model (no AppKit), testable with `swift test`.
        .target(name: "FolioCore"),
        // The AppKit app. `make app` wraps this binary in build/Folio.app.
        .executableTarget(name: "Folio", dependencies: ["FolioCore"]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
    ]
)
