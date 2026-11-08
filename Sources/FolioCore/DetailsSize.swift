import CoreGraphics

/// View > Details Size: how large the Details list draws its names, other columns and icons. The four
/// steps grow the text, the icon and the row together. Small is the list as it always was.
public enum DetailsSize: String, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// The name's point size (the other columns move by the same amount from their own sizes).
    public var textSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 14
        case .large: 16
        case .extraLarge: 18
        }
    }

    /// How much larger than Small the text is.
    public var textDelta: CGFloat { textSize - DetailsSize.small.textSize }

    public var iconSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 20
        case .large: 24
        case .extraLarge: 32
        }
    }

    /// Native's row (Finder's 24 pt at Small). D4's rows are 2 pt taller and Compact View takes 4 pt off.
    public var nativeRowHeight: CGFloat {
        switch self {
        case .small: 24
        case .medium: 28
        case .large: 32
        case .extraLarge: 40
        }
    }

    public func rowHeight(native: Bool, compact: Bool) -> CGFloat {
        nativeRowHeight + (native ? 0 : 2) - (compact ? 4 : 0)
    }

    /// One step up, or the same at Extra Large.
    public var bigger: DetailsSize { Self.allCases.dropFirst().first { $0.step > step } ?? self }
    /// One step down, or the same at Small.
    public var smaller: DetailsSize { Self.allCases.reversed().first { $0.step < step } ?? self }

    private var step: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
