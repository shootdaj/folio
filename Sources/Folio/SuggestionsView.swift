import AppKit
import FolioCore

/// What the Suggestions page shows: a copy of the center's state, given to the view by the window.
struct SuggestionsState {
    var phase: SuggestionState = .idle
    var report: SuggestionReport?
    /// The cards of the fixed places, sent while the walk still runs.
    var early: [Suggestion] = []
    var progress: ScanProgress?
    var failure: String?
    var lastScan: Date?
    /// The item ids that a Move to Trash is working on.
    var pending: Set<String> = []
    var ignoredCount = 0
    var home = FileManager.default.homeDirectoryForCurrentUser
}

/// The Suggestions page in the list's place: a scroll view that holds the page view. The page tells it when its
/// height changes (Home reaches up the superview chain for this; the page uses a callback).
final class SuggestionsPaneView: NSView {
    let scrollView = NSScrollView()
    let page = SuggestionsView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = page
        addSubview(scrollView)
        page.onHeightChange = { [weak self] in self?.needsLayout = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let width = scrollView.contentSize.width
        page.frame = NSRect(x: 0, y: 0, width: width, height: max(page.fittingHeight(width: width), scrollView.contentSize.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        fillRect(bounds, ThemeColors.current.pane)
    }
}

/// The page itself. One custom-drawn document view with real controls on top: OSButton for the push buttons,
/// ChromeButton for the row actions and NSProgressIndicator for the scan. Native draws a plain list in system
/// colours with Finder icons. D4 draws Home's cards: s1 fill, a line, radius 12, mono uppercase heads, and an accent progress line.
final class SuggestionsView: NSView {
    var state = SuggestionsState() {
        didSet {
            rebuildSections()
            relayout()
        }
    }

    // What the window does for each control.
    var onTrash: ((Suggestion, SuggestionItem) -> Void)?
    var onReveal: ((Suggestion, SuggestionItem) -> Void)?
    var onIgnore: ((Suggestion, SuggestionItem) -> Void)?
    /// The card button: Move to Trash for the shown suggestions of the section, or Empty Trash on the Trash card.
    var onCard: ((SuggestionSection) -> Void)?
    var onRescan: (() -> Void)?
    var onStop: (() -> Void)?
    var onScan: (() -> Void)?
    var onOpenAccessSettings: (() -> Void)?
    var onScanAnyway: (() -> Void)?
    var onShowIgnored: (() -> Void)?
    var menuProvider: ((Suggestion, SuggestionItem) -> NSMenu?)?
    var onHeightChange: (() -> Void)?

    private(set) var focusedID: String?
    private var hoveredID: String?
    /// The kinds that show up to 500 rows. Per window, not saved.
    private var expanded: Set<SuggestionKind> = []
    private var sections: [SuggestionSection] = []

    // MARK: Layout model

    private enum Command: Hashable {
        case rescan, stop, scan, openSettings, scanAnyway, showIgnored
        case card(SuggestionKind), more(SuggestionKind)
    }

    private struct Placement {
        let command: Command
        let title: String
        let style: OSButton.Style
        let frame: NSRect
        var enabled = true
    }

    private struct Label {
        let text: String
        let font: NSFont
        let color: NSColor
        let x: CGFloat
        let midY: CGFloat
        var maxWidth: CGFloat = .greatestFiniteMagnitude
        var alignRight = false
        /// D4 only: the palette token, read again each time the label is drawn so an accent change shows at once.
        var tone: KeyPath<ThemeColors, NSColor>?
        var kern: CGFloat = 0
    }

    private struct RowBox {
        let row: SuggestionRow
        let rect: NSRect
        let kind: SuggestionKind
    }

    private struct Layout {
        var height: CGFloat = 0
        var labels: [Label] = []
        var lines: [NSRect] = []
        var glyphs: [(Glyph, NSRect, NSColor)] = []
        var rows: [RowBox] = []
        var heads: [(SuggestionSection, NSRect)] = []
        /// D4 only: one card for each section.
        var cards: [NSRect] = []
        var controls: [Placement] = []
        var progress: NSRect?
    }

    private var layout = Layout()
    private var lastHeight: CGFloat = 0
    private var axParts: [AddressPart] = []

    private enum NativeMetrics {
        static let pad: CGFloat = 20, inset: CGFloat = 8, headH: CGFloat = 28, rowH: CGFloat = 40, groupH: CGFloat = 30
        static let gap: CGFloat = 14, buttonH: CGFloat = 22, iconSize: CGFloat = 24, sizeW: CGFloat = 72
        static let stripButton: CGFloat = 26, stripGap: CGFloat = 0
    }
    private enum D4Metrics {
        static let pad: CGFloat = 18, cardInset: CGFloat = 6, headH: CGFloat = 40, rowH: CGFloat = 48, groupH: CGFloat = 34
        static let gap: CGFloat = 14, buttonH: CGFloat = 30, iconSize: CGFloat = 20, sizeW: CGFloat = 84, stripButton: CGFloat = 28
        static let rowPad: CGFloat = 12
    }
    private var native: Bool { ThemeController.shared.isNative }

    // MARK: Controls

    private var buttons: [Command: OSButton] = [:]
    private let progressBar = NSProgressIndicator()
    private let trashButton = ChromeButton(glyph: .trash, label: "Move to Trash", target: nil, action: nil)
    private let revealButton = ChromeButton(glyph: .search, label: PlaceNames.reveal, target: nil, action: nil)
    private let ignoreButton = ChromeButton(glyph: .eyeOff, label: "Ignore", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Suggestions")
        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true
        addSubview(progressBar)
        for (button, action) in [(trashButton, #selector(stripTrash)), (revealButton, #selector(stripReveal)),
                                 (ignoreButton, #selector(stripIgnore))] {
            button.target = self
            button.action = action
            button.iconSize = 14
            button.isHidden = true
            addSubview(button)
        }
        revealButton.toolTip = PlaceNames.reveal
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { relayout() }
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    // MARK: Model

    private func rebuildSections() {
        let cards = SuggestionPage.cards(report: state.report, early: state.early)
        sections = SuggestionPage.sections(cards: cards, home: state.report?.home ?? state.home, expanded: expanded)
        let ids = Set(sections.flatMap { $0.rows.filter(\.isFocusable).map(\.id) })
        if let focusedID, !ids.contains(focusedID) { self.focusedID = nil }
        if let hoveredID, !ids.contains(hoveredID) { self.hoveredID = nil }
    }

    private func isPending(_ row: SuggestionRow) -> Bool {
        guard let item = row.item else { return false }
        return state.pending.contains(item.id)
    }

    func fittingHeight(width: CGFloat) -> CGFloat { makeLayout(width: width).height }

    private func relayout() {
        layout = makeLayout(width: bounds.width)
        applyControls()
        rebuildAccessibility()
        needsDisplay = true
        if layout.height != lastHeight {
            lastHeight = layout.height
            onHeightChange?()
        }
    }

    // MARK: Layout

    private func makeLayout(width: CGFloat) -> Layout {
        native ? makeNativeLayout(width: width) : makeD4Layout(width: width)
    }

    private func buttonWidth(_ title: String, _ style: OSButton.Style) -> CGFloat {
        if !native { return 16 + textWidth(title, font: Typeface.ui(14, weight: style == .primary ? 600 : 500)) + 16 }
        let w = textWidth(title, font: .systemFont(ofSize: 13))
        return style == .ghost ? w + 16 : max(60, w + 28)
    }

    private func wrap(_ text: String, font: NSFont, width: CGFloat) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            let next = line.isEmpty ? String(word) : line + " " + word
            if line.isEmpty || textWidth(next, font: font) <= width {
                line = next
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    private func makeNativeLayout(width: CGFloat) -> Layout {
        typealias M = NativeMetrics
        var out = Layout()
        let x = M.pad, w = max(240, width - 2 * M.pad), right = x + w
        let st = state
        let digits = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        // Header: title, the one button on the right, and the line under the title.
        out.labels.append(Label(text: PlaceNames.suggestions, font: .systemFont(ofSize: 20, weight: .semibold), color: .labelColor,
                                x: x, midY: 28))
        var headerButton: (Command, String)?
        switch st.phase {
        case .scanning: headerButton = (.stop, "Stop")
        case .idle: if st.report != nil { headerButton = (.rescan, "Rescan") }
        case .needsAccess: break
        case .done, .failed: headerButton = (.rescan, "Rescan")
        }
        if let (command, title) = headerButton {
            let bw = buttonWidth(title, .plain)
            out.controls.append(Placement(command: command, title: title, style: .plain,
                                          frame: NSRect(x: right - bw, y: 28 - M.buttonH / 2, width: bw, height: M.buttonH)))
        }
        var subtitle: String
        switch st.phase {
        case .scanning: subtitle = SuggestionPage.progressText(st.progress)
        case .needsAccess: subtitle = "Full Disk Access is off"
        case .failed: subtitle = SuggestionPage.checkedText(st.lastScan, now: Date())
        case .idle, .done:
            if let report = st.report {
                subtitle = report.suggestions.isEmpty ? "Nothing to clean up" : SuggestionPage.freeableText(report)
                subtitle += " \u{00B7} " + SuggestionPage.checkedText(st.lastScan, now: Date())
            } else {
                subtitle = "Not scanned yet"
            }
        }
        out.labels.append(Label(text: subtitle, font: digits, color: .secondaryLabelColor, x: x, midY: 50, maxWidth: w))
        var y: CGFloat = 70
        if st.phase == .scanning {
            out.progress = NSRect(x: x, y: 62, width: w, height: 12)
            y = 80
        }
        y += 8

        // Notices: a partial scan, and the Trash that needs Full Disk Access.
        if let report = st.report, st.phase != .scanning {
            if report.isPartial {
                out.labels.append(Label(text: "The scan stopped early, so some files were not checked. The list can be incomplete.",
                                        font: .systemFont(ofSize: 12), color: .secondaryLabelColor, x: x, midY: y + 10, maxWidth: w))
                y += 28
            }
            if report.needsFullDiskAccess {
                let title = "Open Privacy Settings"
                let bw = buttonWidth(title, .ghost)
                out.labels.append(Label(text: "Folio needs Full Disk Access to measure the Trash.", font: .systemFont(ofSize: 12),
                                        color: .secondaryLabelColor, x: x, midY: y + 10, maxWidth: max(100, w - bw - 12)))
                out.controls.append(Placement(command: .openSettings, title: title, style: .ghost,
                                              frame: NSRect(x: right - bw, y: y, width: bw, height: M.buttonH)))
                y += 28
            }
        }

        if st.phase == .failed, let failure = st.failure, !sections.isEmpty {
            out.labels.append(Label(text: failure, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, x: x, midY: y + 10, maxWidth: w))
            y += 28
        }

        // Sections.
        for s in sections {
            let head = NSRect(x: x - M.inset, y: y, width: w + 2 * M.inset, height: M.headH)
            out.heads.append((s, head))
            let mid = y + M.headH / 2
            var edge = right
            do {
                let title = s.kind == .trash ? "Empty " + PlaceNames.recycleBin : SuggestionPage.moveTitle(count: s.shown.count)
                let style: OSButton.Style = s.kind == .trash ? .warn : .plain
                let bw = buttonWidth(title, style)
                let allPending = s.shown.allSatisfy { sug in sug.items.allSatisfy { st.pending.contains($0.id) } }
                out.controls.append(Placement(command: .card(s.kind), title: title, style: style,
                                              frame: NSRect(x: right - bw, y: mid - M.buttonH / 2, width: bw, height: M.buttonH),
                                              enabled: !allPending))
                edge = right - bw - 10
            }
            out.labels.append(Label(text: SuggestionPage.sectionTotal(s), font: digits, color: .secondaryLabelColor, x: edge, midY: mid,
                                    alignRight: true))
            let tw = textWidth(s.title, font: .systemFont(ofSize: 11, weight: .semibold))
            out.labels.append(Label(text: s.title, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor,
                                    x: x, midY: mid, maxWidth: max(80, w * 0.5)))
            out.labels.append(Label(text: ByteText.grouped(s.count), font: .systemFont(ofSize: 11), color: .tertiaryLabelColor,
                                    x: x + min(tw, max(80, w * 0.5)) + 6, midY: mid))
            out.lines.append(NSRect(x: x, y: y + M.headH - 1, width: w, height: 1))
            y += M.headH
            for row in s.rows {
                let h = row.role == .groupHead ? M.groupH : M.rowH
                out.rows.append(RowBox(row: row, rect: NSRect(x: x - M.inset, y: y, width: w + 2 * M.inset, height: h), kind: s.kind))
                y += h
            }
            if s.hidden > 0 && !s.isExpanded {
                let title = SuggestionPage.showAllTitle(count: s.count)
                out.controls.append(Placement(command: .more(s.kind), title: title, style: .ghost,
                                              frame: NSRect(x: x - 4, y: y + 4, width: buttonWidth(title, .ghost), height: M.buttonH)))
                y += 30
            } else if s.isCapped {
                out.labels.append(Label(text: SuggestionPage.cappedText(section: s), font: .systemFont(ofSize: 11),
                                        color: .tertiaryLabelColor, x: x, midY: y + 15))
                y += 30
            }
            y += M.gap
        }

        // The panel for a page with no cards.
        if sections.isEmpty { y = nativePanel(&out, width: width, top: y + 40) }

        if st.ignoredCount > 0 && st.phase != .needsAccess && st.phase != .scanning {
            let title = SuggestionPage.ignoredTitle(count: st.ignoredCount)
            out.controls.append(Placement(command: .showIgnored, title: title, style: .ghost,
                                          frame: NSRect(x: x - 4, y: y, width: buttonWidth(title, .ghost), height: M.buttonH)))
            y += 34
        }
        out.height = y + M.pad
        return out
    }

    /// The text, glyph and buttons of a page that has no cards. Returns the y below them.
    private func nativePanel(_ out: inout Layout, width: CGFloat, top: CGFloat) -> CGFloat {
        let cx = width / 2
        var y = top
        func centered(_ text: String, _ font: NSFont, _ color: NSColor, midY: CGFloat) {
            let tw = textWidth(text, font: font)
            out.labels.append(Label(text: text, font: font, color: color, x: cx - tw / 2, midY: midY))
        }
        func body(_ text: String) {
            let font = NSFont.systemFont(ofSize: 13)
            for line in wrap(text, font: font, width: min(420, width - 80)) {
                centered(line, font, .secondaryLabelColor, midY: y + 10)
                y += 18
            }
        }
        func buttons(_ list: [(Command, String, OSButton.Style)]) {
            y += 10
            let widths = list.map { buttonWidth($0.1, $0.2) }
            var bx = cx - (widths.reduce(0, +) + CGFloat(list.count - 1) * 10) / 2
            for (i, b) in list.enumerated() {
                out.controls.append(Placement(command: b.0, title: b.1, style: b.2,
                                              frame: NSRect(x: bx, y: y, width: widths[i], height: NativeMetrics.buttonH)))
                bx += widths[i] + 10
            }
            y += NativeMetrics.buttonH
        }
        let head = NSFont.systemFont(ofSize: 15, weight: .semibold)
        switch state.phase {
        case .idle:
            centered("Find what you can remove", head, .labelColor, midY: y + 10)
            y += 28
            body("Find large, old and duplicate files you can remove.")
            buttons([(.scan, "Scan", .primary)])
        case .needsAccess:
            centered("Full Disk Access is off", head, .labelColor, midY: y + 10)
            y += 28
            body("Folio needs Full Disk Access to look through Desktop, Documents, Downloads and the Trash. Without it, macOS asks for each folder.")
            buttons([(.openSettings, "Open Privacy Settings", .primary), (.scanAnyway, "Scan anyway", .plain)])
        case .scanning:
            body("Looking through your home folder. This can take a minute.")
        case .done:
            out.glyphs.append((.check, NSRect(x: cx - 16, y: y, width: 32, height: 32), .secondaryLabelColor))
            y += 44
            centered("Nothing to clean up", head, .labelColor, midY: y + 10)
            y += 28
            body(SuggestionPage.checkedText(state.lastScan, now: Date()))
        case .failed:
            centered("The scan did not finish", head, .labelColor, midY: y + 10)
            y += 28
            body(state.failure ?? "Try again.")
        }
        return y + 16
    }

    // MARK: D4 layout

    /// The subtitle under the title, as Native has it.
    private func d4Subtitle() -> String {
        let st = state
        switch st.phase {
        case .scanning: return SuggestionPage.progressText(st.progress)
        case .needsAccess: return "Full Disk Access is off"
        case .failed: return SuggestionPage.checkedText(st.lastScan, now: Date())
        case .idle, .done:
            guard let report = st.report else { return "Not scanned yet" }
            let head = report.suggestions.isEmpty ? "Nothing to clean up" : SuggestionPage.freeableText(report)
            return head + " \u{00B7} " + SuggestionPage.checkedText(st.lastScan, now: Date())
        }
    }

    /// D4 Obsidian: a title strip, then one spotlight card for each section (s1, a hairline, radius 12) with a
    /// mono uppercase head, a count and the card button. The rows sit inside the card.
    private func makeD4Layout(width: CGFloat) -> Layout {
        typealias M = D4Metrics
        let p = ThemeColors.current
        var out = Layout()
        let x = M.pad, w = max(240, width - 2 * M.pad), right = x + w
        let st = state
        let note = Typeface.mono(11)

        out.labels.append(Label(text: PlaceNames.suggestions, font: Typeface.ui(18, weight: 700), color: p.text, x: x, midY: 28,
                                tone: \.text))
        var headerButton: (Command, String)?
        switch st.phase {
        case .scanning: headerButton = (.stop, "Stop")
        case .idle: if st.report != nil { headerButton = (.rescan, "Rescan") }
        case .needsAccess: break
        case .done, .failed: headerButton = (.rescan, "Rescan")
        }
        if let (command, title) = headerButton {
            let bw = buttonWidth(title, .plain)
            out.controls.append(Placement(command: command, title: title, style: .plain,
                                          frame: NSRect(x: right - bw, y: 28 - M.buttonH / 2, width: bw, height: M.buttonH)))
        }
        out.labels.append(Label(text: d4Subtitle(), font: Typeface.mono(11, weight: 500), color: p.muted, x: x, midY: 54,
                                maxWidth: w, tone: \.muted))
        var y: CGFloat = 70
        if st.phase == .scanning {
            // The accent line under the title, as the search address has it.
            out.progress = NSRect(x: x, y: 68, width: w, height: 2)
            y = 78
        }
        y += 8

        if let report = st.report, st.phase != .scanning {
            if report.isPartial {
                out.labels.append(Label(text: "The scan stopped early, so some files were not checked. The list can be incomplete.",
                                        font: note, color: p.muted, x: x, midY: y + 10, maxWidth: w, tone: \.muted))
                y += 28
            }
            if report.needsFullDiskAccess {
                let title = "Open Privacy Settings"
                let bw = buttonWidth(title, .ghost)
                out.labels.append(Label(text: "Folio needs Full Disk Access to measure the Trash.", font: note, color: p.muted,
                                        x: x, midY: y + 15, maxWidth: max(100, w - bw - 12), tone: \.muted))
                out.controls.append(Placement(command: .openSettings, title: title, style: .ghost,
                                              frame: NSRect(x: right - bw, y: y, width: bw, height: M.buttonH)))
                y += M.buttonH + 6
            }
        }
        if st.phase == .failed, let failure = st.failure, !sections.isEmpty {
            out.labels.append(Label(text: failure, font: note, color: p.muted, x: x, midY: y + 10, maxWidth: w, tone: \.muted))
            y += 28
        }

        for s in sections {
            let top = y
            let mid = top + M.headH / 2
            out.heads.append((s, NSRect(x: x, y: top, width: w, height: M.headH)))
            let title = s.kind == .trash ? "Empty " + PlaceNames.recycleBin : SuggestionPage.moveTitle(count: s.shown.count)
            let style: OSButton.Style = s.kind == .trash ? .warn : .plain
            let bw = buttonWidth(title, style)
            let allPending = s.shown.allSatisfy { sug in sug.items.allSatisfy { st.pending.contains($0.id) } }
            out.controls.append(Placement(command: .card(s.kind), title: title, style: style,
                                          frame: NSRect(x: right - 10 - bw, y: mid - M.buttonH / 2, width: bw, height: M.buttonH),
                                          enabled: !allPending))
            let edge = right - 10 - bw - 12
            out.labels.append(Label(text: SuggestionPage.sectionTotal(s), font: Typeface.mono(12, weight: 500), color: p.text2,
                                    x: edge, midY: mid, alignRight: true, tone: \.text2))
            let caption = Typeface.caption(s.title)
            let capFont = Typeface.mono(12, weight: 600), kern = Typeface.labelKern(12)
            let cap = min(textWidth(caption, font: capFont, kern: kern), max(80, w * 0.4))
            out.labels.append(Label(text: caption, font: capFont, color: p.muted, x: x + 14, midY: mid, maxWidth: cap, tone: \.muted,
                                    kern: kern))
            out.labels.append(Label(text: ByteText.grouped(s.count), font: Typeface.mono(12, weight: 500), color: p.muted,
                                    x: x + 14 + cap + 6, midY: mid, tone: \.muted))
            out.lines.append(NSRect(x: x + 1, y: top + M.headH, width: w - 2, height: 1))
            y += M.headH + 1
            for row in s.rows {
                let h = row.role == .groupHead ? M.groupH : M.rowH
                out.rows.append(RowBox(row: row, rect: NSRect(x: x + M.cardInset, y: y, width: w - 2 * M.cardInset, height: h),
                                       kind: s.kind))
                y += h
            }
            if s.hidden > 0 && !s.isExpanded {
                let more = SuggestionPage.showAllTitle(count: s.count)
                out.controls.append(Placement(command: .more(s.kind), title: more, style: .ghost,
                                              frame: NSRect(x: x + M.cardInset + 4, y: y + 4, width: buttonWidth(more, .ghost),
                                                            height: M.buttonH)))
                y += M.buttonH + 8
            } else if s.isCapped {
                out.labels.append(Label(text: SuggestionPage.cappedText(section: s), font: note, color: p.faint,
                                        x: x + 14, midY: y + 15, tone: \.faint))
                y += 30
            }
            y += 6
            out.cards.append(NSRect(x: x, y: top, width: w, height: y - top))
            y += M.gap
        }

        if sections.isEmpty { y = d4Panel(&out, width: width, top: y + 40) }

        if st.ignoredCount > 0 && st.phase != .needsAccess && st.phase != .scanning {
            let title = SuggestionPage.ignoredTitle(count: st.ignoredCount)
            out.controls.append(Placement(command: .showIgnored, title: title, style: .ghost,
                                          frame: NSRect(x: x - 4, y: y, width: buttonWidth(title, .ghost), height: M.buttonH)))
            y += M.buttonH + 6
        }
        out.height = y + M.pad
        return out
    }

    /// The text, glyph and buttons of a page with no cards, in D4's type. Returns the y below them.
    private func d4Panel(_ out: inout Layout, width: CGFloat, top: CGFloat) -> CGFloat {
        let p = ThemeColors.current
        let cx = width / 2
        var y = top
        func centered(_ text: String, _ font: NSFont, _ tone: KeyPath<ThemeColors, NSColor>, midY: CGFloat) {
            let tw = textWidth(text, font: font)
            out.labels.append(Label(text: text, font: font, color: p[keyPath: tone], x: cx - tw / 2, midY: midY, tone: tone))
        }
        func body(_ text: String) {
            let font = Typeface.mono(12)
            for line in wrap(text, font: font, width: min(440, width - 80)) {
                centered(line, font, \.muted, midY: y + 10)
                y += 20
            }
        }
        func buttons(_ list: [(Command, String, OSButton.Style)]) {
            y += 12
            let widths = list.map { buttonWidth($0.1, $0.2) }
            var bx = cx - (widths.reduce(0, +) + CGFloat(list.count - 1) * 10) / 2
            for (i, b) in list.enumerated() {
                out.controls.append(Placement(command: b.0, title: b.1, style: b.2,
                                              frame: NSRect(x: bx, y: y, width: widths[i], height: D4Metrics.buttonH)))
                bx += widths[i] + 10
            }
            y += D4Metrics.buttonH
        }
        let head = Typeface.ui(16, weight: 700)
        switch state.phase {
        case .idle:
            centered("Find what you can remove", head, \.text, midY: y + 10)
            y += 30
            body("Find large, old and duplicate files you can remove.")
            buttons([(.scan, "Scan", .primary)])
        case .needsAccess:
            centered("Full Disk Access is off", head, \.text, midY: y + 10)
            y += 30
            body("Folio needs Full Disk Access to look through Desktop, Documents, Downloads and the Trash. Without it, macOS asks for each folder.")
            buttons([(.openSettings, "Open Privacy Settings", .primary), (.scanAnyway, "Scan anyway", .plain)])
        case .scanning:
            body("Looking through your home folder. This can take a minute.")
        case .done:
            out.glyphs.append((.check, NSRect(x: cx - 16, y: y, width: 32, height: 32), p.muted))
            y += 44
            centered("Nothing to clean up", head, \.text, midY: y + 10)
            y += 30
            body(SuggestionPage.checkedText(state.lastScan, now: Date()))
        case .failed:
            centered("The scan did not finish", head, \.text, midY: y + 10)
            y += 30
            body(state.failure ?? "Try again.")
        }
        return y + 16
    }

    // MARK: D4 drawing

    private func drawD4() {
        let p = ThemeColors.current
        let dirty = bounds
        for card in layout.cards {
            fillRounded(card, radius: 12, p.s1)
            strokeRounded(card, radius: 12, p.line)
        }
        for line in layout.lines { fillRect(line, p.line) }
        for l in layout.labels {
            let color = l.tone.map { p[keyPath: $0] } ?? l.color
            drawLine(l.text, font: l.font, color: color, x: l.x, midY: l.midY, maxWidth: l.maxWidth, alignRight: l.alignRight,
                     kern: l.kern)
        }
        for (glyph, rect, _) in layout.glyphs { glyph.draw(in: rect, color: p.muted.ns) }
        if let r = layout.progress { drawD4Progress(r, p) }
        for b in layout.rows where b.rect.intersects(dirty) { drawD4Row(b, p) }
    }

    /// The scan's accent line, ported from the search address: a 2 pt line that grows with the glow, on a hairline track.
    /// With no known fraction the line is a short stretch at the start.
    private func drawD4Progress(_ r: NSRect, _ p: ThemeColors) {
        fillRect(r, p.line)
        let fraction = CGFloat(max(0, min(1, state.progress?.fraction ?? 0)))
        let line = NSRect(x: r.minX, y: r.minY, width: r.width * (fraction > 0 ? fraction : 0.12), height: r.height)
        withGlow(p.accent, blur: 10) { fillRect(line, p.accent) }
    }

    private func drawD4Row(_ b: RowBox, _ p: ThemeColors) {
        typealias M = D4Metrics
        let row = b.row, r = b.rect
        let selected = focusedID == row.id
        let hot = hoveredID == row.id
        if selected {
            // As the sidebar's selected row: the accent at 16%, and a hairline of it while the page has the keys.
            fillRounded(r, radius: 8, p.accent.withAlpha(0.16))
            if emphasized { strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 8, p.accent.withAlpha(0.55)) }
        } else if hot {
            fillRounded(r, radius: 8, p.text.withAlpha(0.07))
        }
        let pending = isPending(row)
        if pending {
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setAlpha(0.45)
        }
        defer { if pending { NSGraphicsContext.current?.cgContext.restoreGState() } }

        if row.role == .groupHead {
            let nameW = drawLine(row.name, font: Typeface.ui(13, weight: 600), color: p.text, x: r.minX + M.rowPad, midY: r.midY,
                                 maxWidth: r.width * 0.5)
            drawLine("\u{00B7} " + row.detail, font: Typeface.mono(12), color: p.muted, x: r.minX + M.rowPad + nameW + 8, midY: r.midY,
                     maxWidth: max(40, r.width - nameW - 2 * M.rowPad - 8))
            return
        }
        let indent: CGFloat = row.role == .member ? 18 : 0
        let iconRect = NSRect(x: r.minX + M.rowPad + indent, y: r.midY - M.iconSize / 2, width: M.iconSize, height: M.iconSize)
        let name = displayName(b)
        if b.kind == .trash {
            Glyph.trash.draw(in: iconRect.insetBy(dx: 2, dy: 2), color: p.text2.ns)
        } else {
            ItemIcon.draw(name: row.name, isFolder: row.item?.isFolder ?? false, in: iconRect, palette: p, glow: hot || selected)
            if b.kind == .brokenLinks {
                ItemIcon.drawLinkBadge(in: NSRect(x: iconRect.maxX - 9, y: iconRect.maxY - 9, width: 10, height: 10), palette: p)
            }
        }
        let left = iconRect.maxX + 12
        let textMax = max(60, r.maxX - M.rowPad - M.sizeW - 8 - 3 * M.stripButton - left)
        let nameW = drawLine(name, font: Typeface.ui(13, weight: 500), color: p.text, x: left, midY: r.minY + 16, maxWidth: textMax)
        if row.isKept, nameW + 40 < textMax {
            drawLine(row.detail, font: Typeface.mono(11, weight: 500), color: p.accent, x: left + nameW + 10, midY: r.minY + 16)
        }
        let second = row.role == .member ? row.place : row.place + " \u{00B7} " + row.detail
        drawLine(second, font: Typeface.mono(11), color: p.muted, x: left, midY: r.minY + 33, maxWidth: textMax)
        if let size = row.size {
            drawLine(SuggestionPage.size(size), font: Typeface.mono(12, weight: 500), color: p.text2, x: r.maxX - M.rowPad,
                     midY: r.midY, alignRight: true)
        }
    }

    // MARK: Controls

    private func applyControls() {
        var live = Set<Command>()
        for p in layout.controls {
            live.insert(p.command)
            let button: OSButton
            if let existing = buttons[p.command] {
                button = existing
            } else {
                button = OSButton(p.title)
                buttons[p.command] = button
                addSubview(button)
            }
            button.setTitle(p.title, glyph: nil, style: p.style)
            button.frame = p.frame
            button.isEnabled = p.enabled
            button.isHidden = false
            let command = p.command
            button.onPress = { [weak self] in self?.perform(command) }
        }
        for (command, button) in buttons where !live.contains(command) { button.isHidden = true }
        if native, let frame = layout.progress {
            progressBar.isHidden = false
            progressBar.frame = frame
            let fraction = state.progress?.fraction ?? 0
            if fraction <= 0 {
                progressBar.isIndeterminate = true
                progressBar.startAnimation(nil)
            } else {
                progressBar.stopAnimation(nil)
                progressBar.isIndeterminate = false
                progressBar.doubleValue = min(1, fraction)
            }
        } else {
            progressBar.stopAnimation(nil)
            progressBar.isHidden = true
        }
        updateStrip()
    }

    private func perform(_ command: Command) {
        switch command {
        case .rescan: onRescan?()
        case .stop: onStop?()
        case .scan: onScan?()
        case .openSettings: onOpenAccessSettings?()
        case .scanAnyway: onScanAnyway?()
        case .showIgnored: onShowIgnored?()
        case .card(let kind):
            if let section = sections.first(where: { $0.kind == kind }) { onCard?(section) }
        case .more(let kind):
            expanded.insert(kind)
            rebuildSections()
            relayout()
        }
    }

    // MARK: The row action strip

    private var activeID: String? { hoveredID ?? focusedID }

    private func box(_ id: String?) -> RowBox? {
        guard let id else { return nil }
        return layout.rows.first { $0.row.id == id && $0.row.isFocusable }
    }

    /// One set of three buttons that sits on the hovered row, or on the focused row. It keeps the count of buttons fixed.
    private func updateStrip() {
        let all = [trashButton, revealButton, ignoreButton]
        guard state.phase != .scanning, let b = box(activeID), let item = b.row.item else {
            all.forEach { $0.isHidden = true }
            return
        }
        let busy = isPending(b.row)
        var visible: [ChromeButton] = []
        if b.kind.canMoveToTrash {
            trashButton.isEnabled = !busy && !b.row.isKept
            trashButton.toolTip = b.row.isKept ? "Kept copy" : "Move to Trash"
            visible.append(trashButton)
        }
        revealButton.isEnabled = !busy
        visible.append(revealButton)
        if b.kind.canIgnore {
            ignoreButton.isEnabled = !busy
            visible.append(ignoreButton)
        }
        _ = item
        all.forEach { $0.isHidden = !visible.contains($0) }
        let side = native ? NativeMetrics.stripButton : D4Metrics.stripButton
        let edge = native ? NativeMetrics.inset + NativeMetrics.sizeW : D4Metrics.rowPad + D4Metrics.sizeW
        var x = b.rect.maxX - edge - 8 - CGFloat(visible.count) * side
        for button in visible {
            button.iconSize = native ? 14 : 16
            button.frame = NSRect(x: x, y: b.rect.midY - side / 2, width: side, height: side)
            x += side
        }
    }

    @objc private func stripTrash() { activate(onTrash) }
    @objc private func stripReveal() { activate(onReveal) }
    @objc private func stripIgnore() { activate(onIgnore) }

    private func activate(_ callback: ((Suggestion, SuggestionItem) -> Void)?) {
        guard let b = box(activeID), let item = b.row.item, !isPending(b.row) else { return }
        callback?(b.row.suggestion, item)
    }

    // MARK: Drawing

    private var emphasized: Bool { window?.isKeyWindow == true && window?.firstResponder === self }

    override func draw(_ dirtyRect: NSRect) {
        guard native else { drawD4(); return }
        for line in layout.lines where line.intersects(dirtyRect) { fillRect(line, .separatorColor) }
        for l in layout.labels {
            drawLine(l.text, font: l.font, color: l.color, x: l.x, midY: l.midY, maxWidth: l.maxWidth, alignRight: l.alignRight)
        }
        for (glyph, rect, color) in layout.glyphs { glyph.draw(in: rect, color: color) }
        for b in layout.rows where b.rect.intersects(dirtyRect) { drawNativeRow(b) }
    }

    /// The Trash row shows the look's name for the Trash, not the folder's.
    private func displayName(_ b: RowBox) -> String { b.kind == .trash ? PlaceNames.recycleBin : b.row.name }

    private func drawNativeRow(_ b: RowBox) {
        typealias M = NativeMetrics
        let row = b.row, r = b.rect
        let selected = focusedID == row.id
        let hot = hoveredID == row.id
        let strong = selected && emphasized
        if selected {
            let fill: NSColor = emphasized ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor
            fillRounded(r, radius: 6, fill)
        } else if hot {
            fillRounded(r, radius: 6, NSColor.quaternarySystemFill)
        }
        let primary: NSColor = strong ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor = strong ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        if isPending(row) {
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setAlpha(0.45)
        }
        defer { if isPending(row) { NSGraphicsContext.current?.cgContext.restoreGState() } }

        if row.role == .groupHead {
            let nameW = drawLine(row.name, font: .systemFont(ofSize: 13, weight: .medium), color: primary, x: r.minX + M.inset,
                                 midY: r.midY, maxWidth: r.width * 0.5)
            drawLine("\u{00B7} " + row.detail, font: .systemFont(ofSize: 11), color: secondary, x: r.minX + M.inset + nameW + 8,
                     midY: r.midY, maxWidth: max(40, r.width - nameW - 3 * M.inset - 8))
            return
        }
        let indent: CGFloat = row.role == .member ? 16 : 0
        let iconRect = NSRect(x: r.minX + M.inset + indent, y: r.midY - M.iconSize / 2, width: M.iconSize, height: M.iconSize)
        let name = displayName(b)
        if b.kind == .trash {
            Glyph.trash.draw(in: iconRect.insetBy(dx: 2, dy: 2), color: secondary, lineWidth: 2)
        } else {
            FinderIcon.draw(name: row.name, isDir: row.item?.isFolder ?? false, isLink: b.kind == .brokenLinks, in: iconRect)
        }
        let left = iconRect.maxX + 10
        let textMax = max(60, r.maxX - M.inset - M.sizeW - 8 - 3 * M.stripButton - left)
        let nameW = drawLine(name, font: .systemFont(ofSize: 13), color: primary, x: left, midY: r.minY + 14, maxWidth: textMax)
        if row.isKept, nameW + 40 < textMax {
            drawLine(row.detail, font: .systemFont(ofSize: 11), color: secondary, x: left + nameW + 8, midY: r.minY + 14)
        }
        let second = row.role == .member ? row.place : row.place + " \u{00B7} " + row.detail
        drawLine(second, font: .systemFont(ofSize: 11), color: secondary, x: left, midY: r.minY + 29, maxWidth: textMax)
        if let size = row.size {
            drawLine(SuggestionPage.size(size), font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular), color: primary,
                     x: r.maxX - M.inset, midY: r.midY, alignRight: true)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func rowBox(at point: NSPoint) -> RowBox? { layout.rows.first { $0.rect.contains(point) } }

    override func mouseMoved(with event: NSEvent) {
        let hit = rowBox(at: convert(event.locationInWindow, from: nil))
        let id = hit?.row.isFocusable == true ? hit?.row.id : nil
        guard id != hoveredID else { return }
        hoveredID = id
        updateStrip()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredID = nil
        updateStrip()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let hit = rowBox(at: convert(event.locationInWindow, from: nil)), hit.row.isFocusable else { return }
        focus(hit.row.id)
        if event.clickCount == 2, let item = hit.row.item { onReveal?(hit.row.suggestion, item) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = rowBox(at: convert(event.locationInWindow, from: nil)), hit.row.isFocusable, let item = hit.row.item
        else { return nil }
        focus(hit.row.id, scroll: false)
        return menuProvider?(hit.row.suggestion, item)
    }

    // MARK: Keyboard

    /// Moves the focus to a row (nil clears it) and scrolls the row into view.
    func focus(_ id: String?, scroll: Bool = true) {
        focusedID = id
        updateStrip()
        needsDisplay = true
        if scroll, let b = box(id) { scrollToVisible(b.rect.insetBy(dx: 0, dy: -4)) }
    }

    private func moveFocus(_ move: SuggestionFocus.Move) {
        let ids = layout.rows.filter(\.row.isFocusable).map(\.row.id)
        focus(SuggestionFocus.next(ids: ids, current: focusedID, move: move))
    }

    /// The focused row can go to the Trash: it is not a kept copy, not a Trash row, and not already on its way.
    var canTrashFocused: Bool {
        guard state.phase != .scanning, let b = box(focusedID), b.row.item != nil else { return false }
        return b.kind.canMoveToTrash && !b.row.isKept && !isPending(b.row)
    }

    /// Cmd+Backspace and Move to Trash in the menus. Only the focused row, never the row under the mouse.
    func trashFocused() {
        guard canTrashFocused, let b = box(focusedID), let item = b.row.item else { NSSound.beep(); return }
        onTrash?(b.row.suggestion, item)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if flags == .command {
            switch event.keyCode {
            case 51: trashFocused()
            case 15: onRescan?()
            default: super.keyDown(with: event)
            }
            return
        }
        guard flags.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 126: moveFocus(.by(-1))
        case 125: moveFocus(.by(1))
        case 116: moveFocus(.by(-SuggestionFocus.pageStep))
        case 121: moveFocus(.by(SuggestionFocus.pageStep))
        case 115: moveFocus(.first)
        case 119: moveFocus(.last)
        case 53: focus(nil)
        case 36, 76:
            // Return reveals the item. A 5 GB file is never opened by accident.
            if let b = box(focusedID), let item = b.row.item, !isPending(b.row) { onReveal?(b.row.suggestion, item) }
        default: super.keyDown(with: event)
        }
    }

    // MARK: Accessibility: each row is a button with actions, each card head is text, the real controls follow.

    private func rebuildAccessibility() {
        var parts: [AddressPart] = []
        for (s, rect) in layout.heads {
            let e = AddressPart()
            e.setAccessibilityRole(.staticText)
            e.setAccessibilityLabel("\(s.title), \(s.count) items, \(SuggestionPage.sectionTotal(s))")
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(rect)
            parts.append(e)
        }
        for b in layout.rows {
            let e = AddressPart()
            e.setAccessibilityRole(b.row.isFocusable ? .button : .staticText)
            let size = b.row.size.map { ", " + SuggestionPage.size($0) } ?? ""
            e.setAccessibilityLabel(displayName(b) + size + ", " + (b.row.detail.isEmpty ? b.row.place : b.row.detail)
                                    + (b.row.isFocusable && !b.row.place.isEmpty ? ", in " + b.row.place : ""))
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(b.rect)
            if let item = b.row.item {
                let suggestion = b.row.suggestion
                e.press = { [weak self] in self?.onReveal?(suggestion, item) }
                var actions: [NSAccessibilityCustomAction] = []
                if b.kind.canMoveToTrash && !b.row.isKept {
                    actions.append(NSAccessibilityCustomAction(name: "Move to Trash") { [weak self] in self?.onTrash?(suggestion, item); return true })
                }
                actions.append(NSAccessibilityCustomAction(name: PlaceNames.reveal) { [weak self] in self?.onReveal?(suggestion, item); return true })
                if b.kind.canIgnore {
                    actions.append(NSAccessibilityCustomAction(name: "Ignore") { [weak self] in self?.onIgnore?(suggestion, item); return true })
                }
                e.setAccessibilityCustomActions(actions)
            }
            parts.append(e)
        }
        axParts = parts
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = axParts
        children += subviews.filter { !$0.isHidden }
        return children
    }
}
