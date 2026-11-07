import AppKit
import FolioCore
import Quartz

/// Quick Look's own preview view, or a line of text when there is nothing to preview (a folder,
/// several items, nothing selected). Used by the Preview pane and the Gallery.
final class QuickLookBox: NSView {
    private var preview: QLPreviewView?
    private var shown: URL?
    var message = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    /// A file to preview, or nil with a message.
    func show(_ url: URL?, message: String) {
        self.message = message
        guard let url else {
            preview?.isHidden = true
            shown = nil
            needsDisplay = true
            return
        }
        if preview == nil, let view = QLPreviewView(frame: bounds, style: .normal) {
            view.autoresizingMask = [.width, .height]
            view.shouldCloseWithWindow = false
            view.setAccessibilityLabel("Preview")
            addSubview(view)
            preview = view
        }
        preview?.isHidden = false
        if shown != url {
            shown = url
            preview?.previewItem = url as NSURL
        }
        needsDisplay = true
    }

    func close() {
        preview?.close()
        preview?.removeFromSuperview()
        preview = nil
        shown = nil
    }

    override func layout() {
        super.layout()
        preview?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        guard preview == nil || preview?.isHidden == true else { return }
        let p = ThemeColors.current
        drawLine(message, font: Typeface.ui(13), color: p.text2, x: bounds.midX - textWidth(message, font: Typeface.ui(13)) / 2,
                 midY: bounds.midY, maxWidth: bounds.width - 24)
    }
}

/// The right-hand pane (`.pane` chassis): Preview (Option+P) or Details (Option+Shift+P), one at a time,
/// as in Explorer.
final class SidePaneView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 340
    var kind: ListOptions.SidePane = .none {
        didSet {
            guard kind != oldValue else { return }
            quickLook.isHidden = kind != .preview
            if kind != .preview { quickLook.close() }
            detailsHidden(kind != .details)
            setAccessibilityLabel(kind == .preview ? "Preview pane" : "Details pane")
            needsLayout = true
            needsDisplay = true
        }
    }
    var onClose: (() -> Void)?
    /// Tags or Comments edited for `url`.
    var onEdit: ((URL, _ tags: [String]?, _ comment: String?) -> Void)?

    private let quickLook = QuickLookBox()
    private let close = ChromeButton(glyph: .close, label: "Close pane", target: nil, action: nil)
    // Details
    private var entry: FileEntry?
    private var summary: (title: String, subtitle: String, isFolder: Bool) = ("", "", true)
    private var rows: [(String, String)] = []
    private var thumbnail: NSImage?
    private let tags = PaneField(label: "Tags")
    private let comments = PaneField(label: "Comments")
    private static let headerH: CGFloat = 36

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(quickLook)
        addSubview(close)
        close.target = self
        close.action = #selector(closePressed(_:))
        close.iconSize = 14
        for field in [tags, comments] {
            field.delegate = self
            addSubview(field)
        }
        detailsHidden(true)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func closePressed(_ sender: Any?) { onClose?() }

    private func detailsHidden(_ hidden: Bool) {
        tags.isHidden = hidden || entry == nil
        comments.isHidden = hidden || entry == nil
    }

    /// What the pane shows for this selection in this folder.
    func show(selection: [FileEntry], folder: URL, folderName: String, itemCount: Int, meta: ItemMetadata?) {
        switch kind {
        case .none: return
        case .preview:
            if selection.count == 1, let one = selection.first, !one.isFolder, !ListOptions.folder.showPreviewHandlers {
                // Folder Options > Show preview handlers in preview pane, off: no file is rendered.
                quickLook.show(nil, message: "No preview available (preview handlers are off in Folder Options)")
            } else if selection.count == 1, let one = selection.first, !one.isFolder, ZipPath.split(one.url) != nil {
                quickLook.show(nil, message: "Copy it out of the zip to preview it")
            } else if selection.count == 1, let one = selection.first, !one.isFolder {
                quickLook.show(one.url, message: "")
            } else {
                quickLook.show(nil, message: selection.isEmpty ? "Select a file to preview" :
                    selection.count == 1 ? "No preview for folders" : "\(selection.count) items selected")
            }
        case .details:
            showDetails(selection: selection, folder: folder, folderName: folderName, itemCount: itemCount, meta: meta)
        }
        needsLayout = true
        needsDisplay = true
    }

    private func showDetails(selection: [FileEntry], folder: URL, folderName: String, itemCount: Int, meta: ItemMetadata?) {
        let previous = entry?.url
        entry = selection.count == 1 ? selection.first : nil
        thumbnail = nil
        if let e = entry {
            summary = (e.name, e.kind, e.isFolder)
            var out: [(String, String)] = []
            func add(_ column: ColumnID) {
                let t = ColumnValues.text(e, column, meta)
                if !t.isEmpty { out.append((column.title, t)) }
            }
            if !e.isFolder { add(.size) }
            for c: ColumnID in [.modified, .created, .dimensions, .duration, .bitRate, .frameRate, .dateTaken,
                                .cameraModel, .album, .artist, .title, .owner, .permissions, .attributes, .uti, .linkTarget] {
                add(c)
            }
            rows = out
            if previous != e.url || !tags.isEditing { tags.text = meta?.tags.joined(separator: ", ") ?? "" }
            if previous != e.url || !comments.isEditing { comments.text = meta?.comments ?? "" }
            tags.isEnabled = meta != nil
            comments.isEnabled = meta != nil
            if ThumbnailCache.wants(e) {
                thumbnail = ThumbnailCache.shared.image(for: e, size: 160) { [weak self] image in
                    guard let self, self.entry?.url == e.url else { return }
                    self.thumbnail = image
                    self.needsDisplay = true
                }
            }
        } else if selection.isEmpty {
            summary = (folderName, ByteText.grouped(itemCount) + (itemCount == 1 ? " item" : " items"), true)
            rows = [("Folder path", folder.path)]
        } else {
            let s = SelectionSummary(selection)
            summary = ("\(selection.count) items selected", s.hasSize ? ByteText.kilobytes(s.bytes) : "", false)
            rows = []
        }
        detailsHidden(false)
        // What the pane shows, as one value for accessibility ("photo.png; PNG image; Dimensions: 900 x 675...").
        setAccessibilityValue(([summary.title, summary.subtitle] + rows.map { "\($0.0): \($0.1)" }).filter { !$0.isEmpty }
            .joined(separator: "; "))
    }

    // MARK: Editing Tags and Comments

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let e = entry, let field = (obj.object as? NSTextField)?.superview as? PaneField else { return }
        if field === tags { onEdit?(e.url, MetadataWriter.parseTags(field.text), nil) }
        if field === comments { onEdit?(e.url, nil, field.text) }
    }

    // MARK: Layout and drawing

    override func layout() {
        super.layout()
        close.frame = NSRect(x: bounds.width - 6 - 28, y: 4, width: 28, height: 28)
        quickLook.frame = NSRect(x: 1, y: Self.headerH, width: bounds.width - 2, height: max(0, bounds.height - Self.headerH - 1))
        // Tags and Comments right under the item, where they stay in view; the details follow.
        var y = fieldsTop
        for field in [tags, comments] {
            let h: CGFloat = field === comments ? 48 : 30
            field.frame = NSRect(x: 14, y: y + 18, width: bounds.width - 28, height: h)
            y += 18 + h + 8
        }
    }

    private static let iconSide: CGFloat = 80
    private var fieldsTop: CGFloat { Self.headerH + 12 + Self.iconSide + 50 }
    private var detailsTop: CGFloat { entry == nil ? fieldsTop : fieldsTop + 18 + 30 + 8 + 18 + 48 + 14 }
    private static let rowH: CGFloat = 21

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(bounds, p.side)
        fillRect(NSRect(x: 0, y: 0, width: 1, height: bounds.height), p.line)
        fillRect(NSRect(x: 1, y: Self.headerH - 1, width: bounds.width - 1, height: 1), p.line)
        let head = kind == .preview ? "PREVIEW" : "DETAILS"
        drawLine(head, font: Typeface.mono(12, weight: 600), color: p.muted, x: 14, midY: Self.headerH / 2, kern: Typeface.labelKern(12))
        guard kind == .details else { return }
        // The item: thumbnail or icon, name, type.
        let side = Self.iconSide
        let icon = NSRect(x: (bounds.width - side) / 2, y: Self.headerH + 12, width: side, height: side)
        if let thumbnail {
            let size = thumbnail.size
            let scale = min(icon.width / max(1, size.width), icon.height / max(1, size.height))
            let w = size.width * scale, h = size.height * scale
            thumbnail.draw(in: NSRect(x: icon.midX - w / 2, y: icon.maxY - h, width: w, height: h), from: .zero,
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if summary.isFolder {
            ItemIcon.drawFolder(in: NSRect(x: icon.minX, y: icon.midY - side * 0.4, width: side, height: side * 0.8), palette: p, lit: false)
        } else {
            ItemIcon.drawFile(named: entry?.name ?? "", in: icon, palette: p)
        }
        let nameFont = Typeface.ui(15, weight: 600)
        let ty = icon.maxY + 16
        drawLine(summary.title, font: nameFont, color: p.text, x: max(14, bounds.midX - textWidth(summary.title, font: nameFont) / 2),
                 midY: ty, maxWidth: bounds.width - 28)
        let sub = Typeface.ui(12)
        drawLine(summary.subtitle, font: sub, color: p.text2, x: max(14, bounds.midX - textWidth(summary.subtitle, font: sub) / 2),
                 midY: ty + 20, maxWidth: bounds.width - 28)
        if entry != nil {
            for field in [tags, comments] where !field.isHidden {
                drawLine(field.label.uppercased(), font: Typeface.ui(11, weight: 650), color: p.text2, x: 14,
                         midY: field.frame.minY - 9, kern: 0.5)
            }
            fillRect(NSRect(x: 14, y: detailsTop - 8, width: bounds.width - 28, height: 1), p.line)
        }
        var y = detailsTop
        for (key, value) in rows {
            drawLine(key, font: Typeface.ui(12), color: p.muted, x: 14, midY: y + Self.rowH / 2, maxWidth: 110)
            drawLine(value, font: Typeface.mono(12), color: p.text, x: 128, midY: y + Self.rowH / 2, maxWidth: bounds.width - 128 - 14)
            y += Self.rowH
        }
    }

    override func accessibilityChildren() -> [Any]? {
        var kids: [Any] = super.accessibilityChildren() ?? []
        if kind == .details {
            // The item's name and type, then one line per detail ("Dimensions: 900 x 675").
            let lines = [summary.title, summary.subtitle] + rows.map { "\($0.0): \($0.1)" }
            for (i, text) in lines.enumerated() where !text.isEmpty {
                let e = HeaderElement()
                e.setAccessibilityElement(true)
                e.setAccessibilityRole(.staticText)
                e.setAccessibilityLabel(text)
                e.setAccessibilityParent(self)
                let y = i < 2 ? Self.headerH + 12 + Self.iconSide + CGFloat(i) * 20 : detailsTop + CGFloat(i - 2) * Self.rowH
                e.setAccessibilityFrameInParentSpace(NSRect(x: 14, y: y, width: bounds.width - 28, height: 20))
                kids.append(e)
            }
        }
        return kids
    }
}

/// An editable line in the Details pane: an s2 well with a line-2 border and mono text.
final class PaneField: NSView {
    let label: String
    let field = NSTextField(string: "")
    weak var delegate: NSTextFieldDelegate? { didSet { field.delegate = delegate } }

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typeface.mono(12)
        field.textColor = ThemeColors.current.text.ns
        field.placeholderString = label == "Tags" ? "Add tags, separated by commas" : "Add a comment"
        field.setAccessibilityLabel(label)
        field.cell?.wraps = label != "Tags"
        field.cell?.isScrollable = label == "Tags"
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var isEnabled: Bool {
        get { field.isEnabled }
        set { field.isEnabled = newValue; field.isEditable = newValue }
    }

    var isEditing: Bool { field.currentEditor() != nil }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 8, dy: 6)
        field.textColor = ThemeColors.current.text.ns
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRounded(bounds, radius: 4, p.s2)
        strokeRounded(bounds, radius: 4, isEditing ? p.accent : p.line2)
    }
}
