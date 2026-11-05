import AppKit
import FolioCore

/// F2's edit box, laid over a row's name: the base name selected so the extension stays, Enter
/// commits, Esc cancels, Tab and Shift+Tab commit and move to the next or previous item (Explorer).
/// D1 look: s3 field, 1 pt accent outline, Archivo 13.
@MainActor
final class RenameEditor: NSObject, NSTextFieldDelegate {
    /// The new name and where to go next (-1, 0, +1). Return false to keep editing (a bad name).
    var onCommit: ((String, Int) -> Bool)?
    /// The box went down, committed or not.
    var onEnd: (() -> Void)?
    private(set) var row: Int?
    private let box = RenameBox()
    private var ending = false
    private var committing = false

    var isActive: Bool { row != nil }

    /// Over the Name cell of `tableRow`; `row` is the item it renames.
    func begin(in table: NSTableView, tableRow: Int, row: Int, entry: FileEntry, textX: CGFloat) {
        guard let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == SortKey.name.rawValue }) else { return }
        let cell = table.frameOfCell(atColumn: column, row: tableRow)
        begin(in: table, cell: cell, row: row, entry: entry, textX: textX)
    }

    /// Over a name drawn at `textX` inside `cell` (the icon grid's label line).
    func begin(in host: NSView, cell: NSRect, row: Int, entry: FileEntry, textX: CGFloat) {
        end()
        let table = host
        let font = Typeface.ui(13)
        let want = textWidth(entry.name, font: font) + 40
        let x = cell.minX + textX - 5
        box.frame = NSRect(x: x, y: cell.minY + 1, width: max(120, min(max(cell.maxX - x, 120), want)), height: cell.height - 2)
        box.field.font = font
        box.field.textColor = Palette.current.txt.ns
        box.field.stringValue = entry.name
        box.field.delegate = self
        box.field.setAccessibilityLabel("Rename " + entry.name)
        table.addSubview(box)
        self.row = row
        table.window?.makeFirstResponder(box.field)
        if let editor = box.field.currentEditor() as? NSTextView {
            let p = Palette.current
            editor.insertionPointColor = p.accent.ns
            editor.selectedTextAttributes = [.backgroundColor: p.markFill.ns]
            let r = FileNaming.baseNameRange(entry.name, isFolder: entry.isFolder)
            editor.setSelectedRange(NSRange(location: r.lowerBound, length: r.count))
        }
    }

    /// Takes the box down without committing.
    func end() {
        guard row != nil else { return }
        ending = true
        row = nil
        let window = box.window
        box.removeFromSuperview()
        if let controller = window?.windowController as? BrowserWindowController {
            window?.makeFirstResponder(controller.listView)
        }
        ending = false
        onEnd?()
    }

    func cancel() { end() }

    private func commit(_ move: Int) {
        guard isActive, !ending, !committing else { return }
        committing = true
        let accepted = onCommit?(box.field.stringValue, move) ?? true
        committing = false
        if accepted {
            end()
        } else if box.window?.firstResponder !== box.field.currentEditor() {
            // An alert took the focus: keep editing.
            box.window?.makeFirstResponder(box.field)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commit(0)
        case #selector(NSResponder.cancelOperation(_:)): cancel()
        case #selector(NSResponder.insertTab(_:)): commit(1)
        case #selector(NSResponder.insertBacktab(_:)): commit(-1)
        default: return false
        }
        return true
    }

    /// Clicking elsewhere commits, as in Explorer; a name that can't be used is dropped instead.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard isActive, !ending, !committing else { return }
        if onCommit?(box.field.stringValue, 0) ?? true { end() } else { cancel() }
    }
}

final class RenameBox: NSView {
    let field = NSTextField(string: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = ceil((field.font?.ascender ?? 12) - (field.font?.descender ?? -3)) + 2
        field.frame = NSRect(x: 4, y: (bounds.height - h) / 2, width: bounds.width - 8, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(bounds, radius: 3, p.s3)
        strokeRounded(bounds, radius: 3, p.accent)
    }
}
