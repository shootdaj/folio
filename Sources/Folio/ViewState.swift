import AppKit
import FolioCore

/// The one view every window and folder shows (ViewSettings): a change applies everywhere at once;
/// "Make this the default view" saves it for the next launch.
@MainActor
final class ViewCenter {
    static let shared = ViewCenter()
    static let didChange = Notification.Name("FolioViewDidChange")

    private(set) var settings = ViewSettings(defaults: UserDefaults(suiteName: "folio-unstarted") ?? .standard)
    private var defaults: UserDefaults = .standard

    func start(defaults: UserDefaults) {
        self.defaults = defaults
        settings = ViewSettings(defaults: defaults)
    }

    var mode: ViewMode { settings.current }

    func set(_ mode: ViewMode) {
        guard mode != settings.current else { return }
        settings.set(mode)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func makeDefault() {
        settings.makeDefault(in: defaults)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// The Details columns, shared by every window and saved as they change (ColumnSet).
@MainActor
final class ColumnCenter {
    static let shared = ColumnCenter()
    static let didChange = Notification.Name("FolioColumnsDidChange")

    private var store = ColumnSetStore(defaults: .standard)
    private(set) var set = ColumnSet.standard

    func start(defaults: UserDefaults) {
        store = ColumnSetStore(defaults: defaults)
        set = store.load()
    }

    /// `post` false for a width drag: the other windows pick it up on their next rebuild.
    func update(_ change: (inout ColumnSet) -> Void, post: Bool = true) {
        var next = set
        change(&next)
        guard next != set else { return }
        set = next
        store.save(next)
        if post { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }
}
