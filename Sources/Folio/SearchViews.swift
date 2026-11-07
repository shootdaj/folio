import AppKit
import FolioCore

/// The search box's text field: tells the box when it takes focus (for the Recent searches dropdown).
final class SearchField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }
}

/// The search box, top right (`.search`): a magnifier, "Search <folder>", and a clear button once there
/// is text. Typing runs the search live (the window debounces); Esc clears it and returns to the folder;
/// Down, or focus on an empty box, lists recent searches.
final class SearchBoxView: NSView, NSTextFieldDelegate, ThemeAware {
    var folderName = "" {
        didSet {
            guard folderName != oldValue else { return }
            placeholder()
            field.setAccessibilityLabel("Search " + folderName)
            setAccessibilityLabel("Search " + folderName)
        }
    }
    /// Every edit.
    var onChange: ((String) -> Void)?
    /// Return: run now.
    var onEnter: ((String) -> Void)?
    /// Esc with no list open, or the clear button.
    var onClear: (() -> Void)?
    var onFocus: (() -> Void)?
    /// Down: the Recent searches list.
    var onDown: (() -> Void)?
    var dropdown: Dropdown?
    let field = SearchField(string: "")
    private let clear: ChromeButton
    private var hovered = false

    override init(frame: NSRect) {
        clear = ChromeButton(glyph: .close, label: "Clear search", target: nil, action: nil)
        super.init(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typeface.ui(13)
        field.textColor = ThemeColors.current.text.ns
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.onFocus = { [weak self] in
            self?.needsDisplay = true
            self?.onFocus?()
        }
        addSubview(field)
        clear.iconSize = 14
        clear.tone = { $0.muted }
        clear.target = self
        clear.action = #selector(clearPressed(_:))
        clear.isHidden = true
        addSubview(clear)
        setAccessibilityRole(.group)
        placeholder()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var text: String {
        get { field.stringValue }
        set {
            guard field.stringValue != newValue else { return }
            field.stringValue = newValue
            textChanged(notify: false)
        }
    }

    var isEditing: Bool {
        guard let editor = window?.firstResponder as? NSText else { return false }
        return editor.delegate === field
    }

    /// Cmd+E, Cmd+F, F3: focus with the text selected, so typing replaces it.
    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        styleEditor()
    }

    /// The caret at the end (after Other properties wrote "name:").
    func focusAtEnd() {
        window?.makeFirstResponder(field)
        let end = NSRange(location: (field.stringValue as NSString).length, length: 0)
        field.currentEditor()?.selectedRange = end
        styleEditor()
    }

    private func styleEditor() {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let p = ThemeColors.current
        editor.insertionPointColor = p.accent.ns
        editor.selectedTextAttributes = [.backgroundColor: p.markFill.ns]
        needsDisplay = true
    }

    private func placeholder() {
        let p = ThemeColors.current
        field.placeholderAttributedString = NSAttributedString(string: "Search " + folderName,
                                                               attributes: [.font: Typeface.ui(13), .foregroundColor: p.muted.ns])
        field.textColor = p.text.ns
    }

    func themeDidChange() {
        placeholder()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let h = ceil((field.font?.ascender ?? 12) - (field.font?.descender ?? -4)) + 4
        let clearW: CGFloat = clear.isHidden ? 0 : 30
        field.frame = NSRect(x: 36, y: (bounds.height - h) / 2, width: max(0, bounds.width - 36 - 8 - clearW), height: h)
        clear.frame = NSRect(x: bounds.width - 6 - 28, y: (bounds.height - 28) / 2, width: 28, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    /// A click anywhere in the box focuses the field.
    override func mouseDown(with event: NSEvent) { focusAtEnd() }

    /// D4's `.search`: the field box 3 pt in from top and bottom, --field with a line-2 hairline (outline on
    /// hover) at radius 12; focused, an accent border with the 3 pt accent-soft halo. The magnifier is muted,
    /// the accent once there is text.
    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        let box = bounds.insetBy(dx: 0, dy: 3)
        if isEditing {
            withGlow(p.accent.withAlpha(0.18), blur: 24) { fillRounded(box.insetBy(dx: -3, dy: -3), radius: 15, p.accentSoft) }
        }
        fillRounded(box, radius: 12, p.field)
        strokeRounded(box, radius: 12, isEditing ? p.accent : (hovered ? p.outline : p.line2))
        let has = !field.stringValue.isEmpty
        Glyph.search.draw(in: NSRect(x: 12, y: bounds.midY - 8, width: 16, height: 16), color: (has ? p.accent : p.muted).ns)
    }

    @objc private func clearPressed(_ sender: Any?) {
        field.stringValue = ""
        textChanged(notify: false)
        onClear?()
        focusAtEnd()
    }

    private func textChanged(notify: Bool) {
        let empty = field.stringValue.isEmpty
        if clear.isHidden != empty {
            clear.isHidden = empty
            needsLayout = true
        }
        if notify { onChange?(field.stringValue) }
    }

    func controlTextDidChange(_ obj: Notification) {
        if dropdown?.isOpen("recentSearches") == true { dropdown?.close() }
        textChanged(notify: true)
    }

    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) {
        needsDisplay = true
        if dropdown?.isOpen("recentSearches") == true { dropdown?.close() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let listOpen = dropdown?.isOpen("recentSearches") == true
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            if listOpen { dropdown?.close(); return true }
            field.stringValue = ""
            textChanged(notify: false)
            onClear?()
        case #selector(NSResponder.moveDown(_:)):
            if listOpen { dropdown?.moveHighlight(1) } else { onDown?() }
        case #selector(NSResponder.moveUp(_:)) where listOpen:
            dropdown?.moveHighlight(-1)
        case #selector(NSResponder.insertNewline(_:)):
            if listOpen, dropdown?.pickHighlighted() == true { break }
            dropdown?.close()
            onEnter?(field.stringValue)
        default:
            return false
        }
        return true
    }

    /// Recent searches, under the box at its width; picking one runs it.
    func showRecent(_ items: [String]) {
        guard let dropdown else { return }
        if dropdown.isOpen("recentSearches") { return }
        let content = DropdownContent(style: .field(header: "Recent searches", count: "\(items.count) of \(RecentSearches.limit)"),
                                      title: "Recent searches", rows: items.map { DropdownRow(text: $0, value: $0) },
                                      empty: "No recent searches", isSearchList: true)
        // At least 340 pt wide, growing left from the box's right edge.
        let w = max(bounds.width, 340)
        dropdown.show(content, id: "recentSearches", below: NSRect(x: bounds.maxX - w, y: 0, width: w, height: bounds.height), in: self) { [weak self] row in
            guard let self else { return }
            self.field.stringValue = row.value
            self.textChanged(notify: false)
            self.focusAtEnd()
            self.onEnter?(row.value)
        }
        dropdown.keepOpenRect = convert(bounds, to: nil)
    }
}

/// One Search options chip (`.chip`): icon, label, and the value written in the box once there is one
/// (then the chip is pressed: selection fill, accent border, a tick for the icon).
final class OptionChip: NSButton {
    let glyph: Glyph
    var value: String? {
        didSet {
            guard value != oldValue else { return }
            setAccessibilityValue(value ?? "")
            superview?.needsLayout = true
            needsDisplay = true
        }
    }
    private var hovered = false

    init(_ title: String, glyph: Glyph) {
        self.glyph = glyph
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var labelFont: NSFont { Typeface.ui(13, weight: 500) }

    /// The chip's dot colour (D4: Date violet, Kind the accent, Size amber).
    var hue: (ThemeColors) -> NSColor = { $0.muted }

    private var text: String { value.map { title + ": " + $0 } ?? title }

    var fitWidth: CGFloat { 10 + 9 + 7 + textWidth(text, font: labelFont) + 11 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    /// D4's `.os-chip.chip`: s1 with a line-2 border at radius 10, a glowing 9 pt dot in the chip's hue and
    /// the label in text-2; on (`aria-pressed`), the hue's border over a 14% tint, the label in text and
    /// "Date modified: This week". Pressing shrinks it a little.
    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        let hue = self.hue(p)
        let on = value != nil
        let r = isHighlighted ? bounds.insetBy(dx: bounds.width * 0.02, dy: bounds.height * 0.02) : bounds
        fillRounded(r, radius: 10, on ? hue.withAlpha(0.14).over(p.s1) : p.s1)
        strokeRounded(r, radius: 10, on || (hovered && isEnabled) ? hue : p.line2)
        let d: CGFloat = on ? 11 : 9
        withGlow(hue.withAlpha(on ? 1 : 0.7), blur: on ? 14 : 10) {
            fillRounded(NSRect(x: 10 + 4.5 - d / 2, y: bounds.midY - d / 2, width: d, height: d), radius: d / 2, hue)
        }
        drawLine(text, font: labelFont, color: on || hovered ? p.text : (isEnabled ? p.text2 : p.muted), x: 10 + 9 + 7,
                 midY: bounds.midY, maxWidth: bounds.width - 26 - 11)
    }
}

/// All subfolders / Current folder (D4's `.seg`): a pair of radio buttons on one track; the chosen one sits
/// on the thumb.
final class ScopeButton: NSButton {
    var isOn = false { didSet { needsDisplay = true; setAccessibilityValue(isOn ? 1 : 0) } }

    init(_ title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 34))
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var fitWidth: CGFloat { 12 + textWidth(title, font: Typeface.ui(13, weight: 500)) + 12 }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        if isOn {
            // `.seg-t`: --thumb, an inset ring of the accent mixed into line-2, a soft accent glow.
            withGlow(p.accent.withAlpha(0.22), blur: 16) { fillRounded(bounds, radius: 8, p.thumb) }
            strokeRounded(bounds, radius: 8, p.accent.mixed(0.5, with: p.line2))
        }
        if isHighlighted { fillRounded(bounds, radius: 8, p.text.withAlpha(0.08)) }
        let font = Typeface.ui(13, weight: 500)
        let w = textWidth(title, font: font)
        drawLine(title, font: font, color: isOn ? p.text : p.muted, x: (bounds.width - w) / 2, midY: bounds.midY)
    }
}

/// The Search options row (`.opts`): appears once a search runs, above the results. Every pick writes
/// AQS into the box (the window does that); the chips show what the box says.
final class SearchOptionsBar: NSView {
    let date = OptionChip("Date modified", glyph: .calendar)
    let kind = OptionChip("Kind", glyph: .kind)
    let size = OptionChip("Size", glyph: .size)
    let other = OptionChip("Other properties", glyph: .view)
    let advanced = OptionChip("Advanced options", glyph: .more)
    let all = ScopeButton("All subfolders")
    let current = ScopeButton("Current folder")
    private let scopeBox = NSView()

    var recursive = true {
        didSet {
            all.isOn = recursive
            current.isOn = !recursive
        }
    }
    /// The chip a menu is wanted for.
    var onChip: ((OptionChip) -> Void)?
    var onScope: ((Bool) -> Void)?

    static let height: CGFloat = 52

    override init(frame: NSRect) {
        super.init(frame: frame)
        date.hue = { $0.hue(.violet) }
        kind.hue = { $0.accent }
        size.hue = { $0.hue(.amber) }
        other.hue = { $0.hue(.teal) }
        advanced.hue = { $0.muted }
        for chip in [date, kind, size, other, advanced] {
            chip.target = self
            chip.action = #selector(chipPressed(_:))
            addSubview(chip)
        }
        all.target = self
        all.action = #selector(scopePressed(_:))
        current.target = self
        current.action = #selector(scopePressed(_:))
        addSubview(all)
        addSubview(current)
        recursive = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Search options")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func chipPressed(_ sender: OptionChip) { onChip?(sender) }
    @objc private func scopePressed(_ sender: ScopeButton) { onScope?(sender === all) }

    private var labelFont: NSFont { Typeface.mono(12, weight: 600) }
    private var labelW: CGFloat { textWidth("SEARCH OPTIONS", font: labelFont, kern: Typeface.labelKern(12)) }

    /// D4's `.opts` wraps: chips flow left to right (8 pt apart) and onto a new 44 pt line when the row is full.
    private func arrange(width: CGFloat) -> (frames: [NSRect], height: CGFloat) {
        let first: CGFloat = 24 + labelW + 6 + 8
        var x = first, line = 0
        var frames: [NSRect] = []
        let widths = [date, kind, size, other, advanced].map(\.fitWidth) + [3 + all.fitWidth + current.fitWidth + 3]
        for (i, w) in widths.enumerated() {
            let gap: CGFloat = i == widths.count - 1 ? 4 : 0
            if x + gap + w > width - 24, x > first || line > 0, x > 24 {
                line += 1
                x = 24
            } else {
                x += gap
            }
            let h: CGFloat = i == widths.count - 1 ? 40 : 34
            frames.append(NSRect(x: x, y: (52 - h) / 2 + CGFloat(line) * 44, width: w, height: h))
            x += w + 8
        }
        return (frames, Self.height + CGFloat(line) * 44)
    }

    /// The row's height at this width (one line is 50 pt).
    func preferredHeight(width: CGFloat) -> CGFloat { arrange(width: width).height }

    override func layout() {
        super.layout()
        needsDisplay = true
        let frames = arrange(width: bounds.width).frames
        for (chip, f) in zip([date, kind, size, other, advanced], frames) { chip.frame = f }
        let seg = frames[5]
        all.frame = NSRect(x: seg.minX + 3, y: seg.minY + 4, width: all.fitWidth, height: 32)
        current.frame = NSRect(x: all.frame.maxX, y: seg.minY + 4, width: current.fitWidth, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(bounds, p.headBg)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        drawLine("SEARCH OPTIONS", font: labelFont, color: p.muted, x: 24, midY: 26, kern: Typeface.labelKern(12))
        // `.seg`: the track, 3 pt around the two buttons, line-2 at radius 12.
        let seg = all.frame.union(current.frame).insetBy(dx: -3, dy: -3)
        fillRounded(seg, radius: 12, p.segBg)
        strokeRounded(seg, radius: 12, p.line2)
    }
}

/// Under the results: "Search again in:" This PC and Home, Windows 7's links for a wider search.
final class SearchFooterView: NSView {
    let thisPC = OSButton("This PC", glyph: .pc, style: .ghost)
    let home = OSButton("Home", glyph: .home, style: .ghost)
    static let height: CGFloat = 40

    override init(frame: NSRect) {
        super.init(frame: frame)
        thisPC.setAccessibilityLabel("Search again in This PC")
        home.setAccessibilityLabel("Search again in Home")
        addSubview(thisPC)
        addSubview(home)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Search again in")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var font: NSFont { Typeface.ui(12, weight: 600) }

    override func layout() {
        super.layout()
        let x = 14 + textWidth("Search again in:", font: font) + 8
        thisPC.frame = NSRect(x: x, y: 4, width: thisPC.fit(), height: bounds.height - 8)
        home.frame = NSRect(x: thisPC.frame.maxX + 4, y: 4, width: home.fit(), height: bounds.height - 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: 1), p.line)
        drawLine("Search again in:", font: font, color: p.text2, x: 14, midY: bounds.midY)
    }
}

/// "No items match your search." (or "Working on it..." before the first results), centred in the list.
final class SearchEmptyView: NSView {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            setAccessibilityValue(text)
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Search status")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        let font = Typeface.ui(14, weight: 500)
        let w = textWidth(text, font: font)
        drawLine(text, font: font, color: p.text2, x: (bounds.width - w) / 2, midY: bounds.midY)
    }
}
