import AppKit
import ImageCaptureCore

/// Phones and cameras: a Mac has no MTP, so iPhones and cameras come through Image Capture's framework.
/// They show under This PC; opening one hands over to Image Capture to import pictures and videos.
@MainActor
final class DeviceCenter: NSObject, ICDeviceBrowserDelegate {
    static let shared = DeviceCenter()
    static let didChange = Notification.Name("FolioDevicesDidChange")

    private let browser = ICDeviceBrowser()
    private(set) var names: [String] = []

    func start() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue
            | ICDeviceLocationTypeMask.local.rawValue)!
        browser.start()
    }

    private func update() {
        names = (browser.devices ?? []).compactMap(\.name).sorted()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        MainActor.assumeIsolated { if !moreComing { update() } }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        MainActor.assumeIsolated { if !moreGoing { update() } }
    }
}

extension BrowserWindowController {
    @objc func devicesChanged(_ note: Notification) { chassis.sidebar.pane.setDevices(DeviceCenter.shared.names) }

    /// Import pictures and videos: Image Capture, the Mac's importer for phones and cameras.
    @objc func openImageCapture(_ sender: Any?) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Image_Capture") else { NSSound.beep(); return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
