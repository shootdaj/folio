/// The right-hand pane's width (Preview or Details): dragged at its left edge and kept in the defaults.
public enum SidePaneSize {
    public static let standard: Double = 340
    public static let minimum: Double = 220
    public static let maximum: Double = 720
    /// The list keeps at least this much beside the pane; a narrow window narrows the pane first.
    public static let listMinimum: Double = 360

    /// A chosen width brought into range.
    public static func clamped(_ w: Double) -> Double { min(maximum, max(minimum, w)) }

    /// The width the pane gets when `room` points lie right of the navigation pane.
    public static func shown(chosen: Double, room: Double) -> Double {
        max(0, min(clamped(chosen), room - listMinimum))
    }

    /// The width for the left edge dragged to `x`, with the pane's right edge at `rightEdge`.
    public static func dragged(toX x: Double, rightEdge: Double) -> Double { clamped(rightEdge - x) }
}
