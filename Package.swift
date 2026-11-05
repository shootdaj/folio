// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FuckFinder",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Swift model (no AppKit), testable with `swift test`.
        .target(name: "FuckFinderCore"),
        // The AppKit app. `make app` wraps this binary in build/FuckFinder.app.
        .executableTarget(name: "FuckFinder", dependencies: ["FuckFinderCore"]),
        .testTarget(name: "FuckFinderCoreTests", dependencies: ["FuckFinderCore"]),
    ]
)
