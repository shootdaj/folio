import AppKit

// `Folio --version`: the version and commit `make app` wrote into Info.plist, nothing else runs.
if CommandLine.arguments.dropFirst().contains("--version") {
    print(BuildInfo.line)
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--selftest") {
    let folder = CommandLine.arguments.dropFirst(flag + 1).first
    exit(SelfTest.run(folder))
}

if let flag = CommandLine.arguments.firstIndex(of: "--bench") {
    exit(MainActor.assumeIsolated { Bench.run(Array(CommandLine.arguments.dropFirst(flag + 1))) })
}

let uitest = UITestConfig.parse(CommandLine.arguments)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(uitest: uitest)
    app.delegate = delegate
    // A --uitest run stays in the background: no Dock icon, no activation, no focus taken.
    app.setActivationPolicy(uitest == nil ? .regular : .accessory)
    app.run()
}
