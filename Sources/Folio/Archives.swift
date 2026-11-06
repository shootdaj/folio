import AppKit
import FolioCore

/// Milestone 8's archives in the window: Compress to ZIP, 7z or TAR (and Send to > Compressed folder),
/// Extract all with Explorer's destination dialog, and a zip browsed like a folder, read-only, its
/// entries copied, dragged or opened out of it.
extension BrowserWindowController {
    // MARK: Compress to

    /// Compress to > ZIP file, 7z file, TAR file (the item's `representedObject` names the format).
    @objc func compressSelection(_ sender: Any?) {
        let raw = (sender as? NSMenuItem)?.representedObject as? String
        compress(selectedURLsInFocusOrder, format: raw.flatMap(ArchiveFormat.init(rawValue:)) ?? .zip)
    }

    /// Send to > Compressed (zipped) folder.
    @objc func sendToCompressedFolder(_ sender: Any?) { compress(selectedURLsInFocusOrder, format: .zip) }

    /// The selection with the item that was right-clicked (the focus) first: Explorer names a
    /// several-item archive after it.
    var selectedURLsInFocusOrder: [URL] {
        var urls = selectedURLs
        if let f = selection.focus, entries.indices.contains(f), let i = urls.firstIndex(of: entries[f].url) {
            urls.insert(urls.remove(at: i), at: 0)
        }
        return urls
    }

    func compress(_ urls: [URL], format: ArchiveFormat) {
        guard let first = urls.first, !isInZip else { NSSound.beep(); return }
        var folder = first.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            // Explorer: "Do you want it to be placed on the desktop instead?"
            let alert = NSAlert()
            alert.messageText = "Folio can't make the compressed file here."
            alert.informativeText = "Do you want it to be placed on the Desktop instead?"
            alert.addButton(withTitle: "Yes")
            alert.addButton(withTitle: "No")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        }
        let name = ArchiveNaming.archiveName(for: urls, format: format) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let out = folder.appendingPathComponent(name)
        OperationCenter.shared.startArchive(ArchiveJob(compress: urls, format: format, to: out), near: window)
    }

    // MARK: Extract all

    /// The archive to extract: the selected one, or the zip being browsed.
    var archiveForExtract: URL? {
        if !isInZip, selectedURLs.count == 1, let url = selectedURLs.first, ArchiveNaming.isExtractable(url) { return url }
        return zipLocation?.archive
    }

    @objc func extractAll(_ sender: Any?) {
        guard let archive = archiveForExtract, let window else { NSSound.beep(); return }
        // Spelt as the title bar spells paths (/tmp, not /private/tmp).
        let proposed = archive.deletingLastPathComponent().appendingPathComponent(ArchiveNaming.extractFolderName(for: archive),
                                                                                   isDirectory: true).standardizedFileURL
        let sheet = ExtractSheetController(archive: archive, destination: proposed)
        sheet.onExtract = { [weak self] dest, show in self?.startExtract(archive, into: dest, show: show) }
        sheet.begin(on: window)
        extractSheet = sheet
    }

    private func startExtract(_ archive: URL, into dest: URL, show: Bool) {
        extractSheet = nil
        let job = ArchiveJob(extract: archive, into: dest)
        OperationCenter.shared.startArchive(job, near: window) { result in
            guard result.state == .done else { return }
            // "Show extracted files when complete": a window on the folder, as Explorer opens one.
            if show { (NSApp.delegate as? AppDelegate)?.openWindow(at: dest) }
        }
    }

    // MARK: A zip as a folder

    /// The zip this tab is browsing and the folder inside it ("" at its top), or nil.
    var zipLocation: (archive: URL, inner: String)? { isInZip ? ZipPath.split(history.current) : nil }

    /// Entries copied out of the zip into a temp folder of their own (Copy, a drag, Open).
    func stagedFromZip(_ urls: [URL]) -> [URL] {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-zip-\(UUID().uuidString)", isDirectory: true)
        do {
            return try ZipFolder.extract(urls, to: folder)
        } catch {
            OperationCenter.shared.present(error, window: window)
            return []
        }
    }

    /// Copy inside a zip: the entries are copied out first, then they go on the clipboard as files.
    func copyOutOfZip() {
        let staged = stagedFromZip(selectedURLs)
        guard !staged.isEmpty else { NSSound.beep(); return }
        FileClipboard.write(staged, cut: false)
    }

    /// A file inside the zip opens from a copy, as Explorer opens it from a temp folder.
    func openFromZip(_ url: URL) {
        guard let staged = stagedFromZip([url]).first else { return }
        NSWorkspace.shared.open(staged)
    }
}

/// Explorer's Extract Compressed (Zipped) Folders dialog as a D1 sheet: the destination with Browse...,
/// Show extracted files when complete, Extract and Cancel.
@MainActor
final class ExtractSheetController: NSObject, NSTextFieldDelegate {
    let archive: URL
    var onExtract: ((URL, Bool) -> Void)?
    private let sheet: ExtractSheet
    private let field: TagField
    private let showCheck = D1Check("Show extracted files when complete")
    private weak var parent: NSWindow?

    init(archive: URL, destination: URL) {
        self.archive = archive
        sheet = ExtractSheet(contentRect: NSRect(x: 0, y: 0, width: 580, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        field = TagField(string: destination.path)
        super.init()
        sheet.title = "Extract Compressed (Zipped) Folders"
        sheet.backgroundColor = Palette.current.s2.ns
        let content = PropertiesContentView()
        sheet.contentView = content
        let heading = LabelView("Select a Destination and Extract Files", font: Typeface.ui(16, weight: 750), color: { $0.text })
        let sub = LabelView(archive.lastPathComponent, font: Typeface.mono(12), color: { $0.muted })
        let label = LabelView("Files will be extracted to this folder:", font: Typeface.ui(13), color: { $0.text2 })
        heading.frame = NSRect(x: 28, y: 26, width: 520, height: 24)
        sub.frame = NSRect(x: 28, y: 52, width: 520, height: 18)
        label.frame = NSRect(x: 28, y: 92, width: 520, height: 20)
        field.frame = NSRect(x: 28, y: 118, width: 400, height: 32)
        field.setAccessibilityLabel("Destination folder")
        field.target = self
        field.action = #selector(extractPressed(_:))
        let browse = D1Button("Browse...", glyph: .newFolder) { [weak self] in self?.browse() }
        browse.frame = NSRect(x: 440, y: 114, width: 112, height: 40)
        showCheck.isChecked = true
        showCheck.frame = NSRect(x: 28, y: 172, width: showCheck.fit(), height: 20)
        let extract = D1Button("Extract", glyph: .check, style: .primary) { [weak self] in self?.extractPressed(nil) }
        let cancel = D1Button("Cancel", glyph: .close) { [weak self] in self?.close() }
        extract.frame = NSRect(x: 580 - 28 - 120, y: 300 - 24 - 40, width: 120, height: 40)
        cancel.frame = NSRect(x: extract.frame.minX - 8 - 112, y: extract.frame.minY, width: 112, height: 40)
        for v in [heading, sub, label, field, browse, showCheck, extract, cancel] as [NSView] { content.addSubview(v) }
        sheet.onReturn = { [weak self] in self?.extractPressed(nil) }
        sheet.onCancel = { [weak self] in self?.close() }
    }

    func begin(on window: NSWindow) {
        parent = window
        window.beginSheet(sheet)
        sheet.makeFirstResponder(nil)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: field.stringValue).deletingLastPathComponent()
        panel.prompt = "Select Folder"
        panel.beginSheetModal(for: sheet) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.field.stringValue = url.path }
        }
    }

    @objc private func extractPressed(_ sender: Any?) {
        let path = (field.stringValue as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { NSSound.beep(); return }
        let dest = URL(fileURLWithPath: path, isDirectory: true)
        let show = showCheck.isChecked
        close()
        onExtract?(dest, show)
    }

    private func close() {
        parent?.endSheet(sheet)
        sheet.orderOut(nil)
    }
}

final class ExtractSheet: NSWindow {
    var onReturn: (() -> Void)?
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        super.keyDown(with: event)
    }
}
