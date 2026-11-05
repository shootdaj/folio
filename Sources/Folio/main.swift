import AppKit

if let flag = CommandLine.arguments.firstIndex(of: "--selftest") {
    let folder = CommandLine.arguments.dropFirst(flag + 1).first
    exit(SelfTest.run(folder))
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
