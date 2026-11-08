/// Native's Details pane on the right: it comes up when items are selected and goes when none are, as
/// Finder's preview column does. D4 keeps a pane that stays until it is closed.
public enum DetailsPaneRule {
    /// Whether the Details pane shows. `chosen` is View > Show > Details Pane (on, the default in
    /// Native); `followsSelection` is true in Native. One item shows its details, several a summary.
    public static func shows(chosen: Bool, followsSelection: Bool, selectedCount: Int, isSpecial: Bool) -> Bool {
        guard chosen, !isSpecial else { return false }
        return !followsSelection || selectedCount > 0
    }
}
