import Foundation
import Testing
@testable import FolioCore

private func suite() -> UserDefaults {
    let name = "folio-columns-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Suite struct ColumnSetTests {
    @Test func startsWithExplorersGeneralItemsColumns() {
        #expect(ColumnSet.standard.visible == [.name, .modified, .kind, .size])
        #expect(ColumnSet.standard.width(of: .name) == 320)
        #expect(ColumnID.allCases.count == 26)
    }

    @Test func headerTicksShowAtTheRightEndAndNameCannotBeHidden() {
        var set = ColumnSet.standard
        set.toggle(.created)
        #expect(set.visible == [.name, .modified, .kind, .size, .created])
        set.toggle(.kind)
        #expect(set.visible == [.name, .modified, .size, .created])
        set.toggle(.name)
        #expect(set.isVisible(.name))
        #expect(ColumnSet(visible: [.size, .kind]).visible == [.name, .size, .kind])
    }

    @Test func chooserListsShownColumnsInOrderThenTheRestAlphabetically() {
        var set = ColumnSet.standard
        set.move(.size, to: 1)
        let order = set.chooserOrder
        #expect(Array(order.prefix(4)) == [.name, .size, .modified, .kind])
        #expect(order.count == 26)
        #expect(order[4] == .album)
        #expect(order[5] == .artist)
        #expect(order.last == .title)
        #expect(Set(order) == Set(ColumnID.allCases))
    }

    @Test func moveUpMoveDownAndTicksApplyOnOK() {
        var chooser = ColumnChooser(ColumnSet.standard)
        let movedName = chooser.moveUp(.name)
        #expect(!movedName)
        chooser.setChecked(.dimensions, true)
        // Dimensions sits among the hidden columns; three Move Ups put it before them, then above Size.
        let start = chooser.order.firstIndex(of: .dimensions)!
        for _ in 0..<(start - 3) { chooser.moveUp(.dimensions) }
        #expect(chooser.order.firstIndex(of: .dimensions) == 3)
        chooser.moveDown(.kind)
        chooser.setChecked(.name, false)
        chooser.setChecked(.modified, false)
        let applied = chooser.applied(to: .standard)
        #expect(applied.visible == [.name, .dimensions, .kind, .size])
        let last = ColumnChooser(ColumnSet.standard)
        var c = last
        let movedLast = c.moveDown(c.order.last!)
        #expect(!movedLast)
    }

    @Test func savesAndComesBackWithWidths() {
        let defaults = suite()
        let store = ColumnSetStore(defaults: defaults)
        #expect(store.load() == .standard)
        var set = ColumnSet.standard
        set.toggle(.tags)
        set.setWidth(210, of: .modified)
        store.save(set)
        let back = ColumnSetStore(defaults: defaults).load()
        #expect(back.visible == [.name, .modified, .kind, .size, .tags])
        #expect(back.width(of: .modified) == 210)
        #expect(back.width(of: .kind) == ColumnID.kind.defaultWidth)
    }

    @Test func unreadableOrUnknownSavedColumnsFallBack() {
        let defaults = suite()
        defaults.set(Data("nonsense".utf8), forKey: ColumnSetStore.key)
        #expect(ColumnSetStore(defaults: defaults).load() == .standard)
        let json = #"{"visible":["name","rating","size"],"widths":{}}"#
        defaults.set(Data(json.utf8), forKey: ColumnSetStore.key)
        #expect(ColumnSetStore(defaults: defaults).load().visible == [.name, .size])
    }
}

@Suite struct ViewModeTests {
    @Test func explorersShortcutNumbers() {
        #expect(ViewMode.forShortcut(1) == .extraLargeIcons)
        #expect(ViewMode.forShortcut(2) == .largeIcons)
        #expect(ViewMode.forShortcut(3) == .mediumIcons)
        #expect(ViewMode.forShortcut(4) == .smallIcons)
        #expect(ViewMode.forShortcut(5) == .list)
        #expect(ViewMode.forShortcut(6) == .details)
        #expect(ViewMode.forShortcut(7) == .tiles)
        #expect(ViewMode.forShortcut(8) == .content)
        #expect(ViewMode.forShortcut(9) == .columns)
        #expect(ViewMode.gallery.shortcut == nil)
    }

    @Test func cmdScrollWalksTheSliderAndStopsAtTheEnds() {
        #expect(ViewMode.details.zoomed(by: 1) == .list)
        #expect(ViewMode.list.zoomed(by: 1) == .smallIcons)
        #expect(ViewMode.largeIcons.zoomed(by: 1) == .extraLargeIcons)
        #expect(ViewMode.extraLargeIcons.zoomed(by: 1) == .extraLargeIcons)
        #expect(ViewMode.details.zoomed(by: -1) == .tiles)
        #expect(ViewMode.content.zoomed(by: -3) == .content)
        #expect(ViewMode.gallery.zoomed(by: -1) == .mediumIcons)
    }

    @Test func oneGlobalViewStartsAtTheSavedDefaultNotTheLastOneUsed() {
        let defaults = suite()
        var settings = ViewSettings(defaults: defaults)
        #expect(settings.current == .details)
        #expect(settings.isDefault)
        settings.set(.largeIcons)
        #expect(!settings.isDefault)
        // Switching views is not a setting: a new launch is back on the default.
        #expect(ViewSettings(defaults: defaults).current == .details)
        settings.makeDefault(in: defaults)
        #expect(settings.isDefault)
        settings.set(.tiles)
        let relaunched = ViewSettings(defaults: defaults)
        #expect(relaunched.current == .largeIcons)
        #expect(relaunched.defaultMode == .largeIcons)
    }

    @Test func anUnknownSavedViewIsDetails() {
        let defaults = suite()
        defaults.set("filmstrip", forKey: ViewSettings.defaultKey)
        #expect(ViewSettings(defaults: defaults).current == .details)
    }
}
