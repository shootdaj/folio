import AppKit

if let flag = CommandLine.arguments.firstIndex(of: "--selftest") {
    let folder = CommandLine.arguments.dropFirst(flag + 1).first
    exit(SelfTest.run(folder))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
