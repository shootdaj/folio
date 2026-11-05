import Foundation
import Testing
@testable import FolioCore

private let ctx = BucketContext(now: day(2026, 11, 5, 15), calendar: calendar(firstWeekday: 2))

private func file(_ name: String, size: Int64? = 10, modified: Date? = day(2026, 11, 5, 9), folder: Bool = false,
                  kind: String = "Plain Text") -> FileEntry {
    FileEntry(url: URL(fileURLWithPath: "/fixture/" + name), name: name, isFolder: folder, modified: modified,
              size: folder ? nil : size, kind: folder ? "Folder" : kind)
}

/// The m6 VM folder: 0 B, 5 KB, 300 KB and 2 MB text files, two images, three folders, spread over dates.
private let folder: [FileEntry] = [
    file("empty.txt", size: 0, modified: day(2026, 11, 5, 8)),
    file("five-kb.txt", size: 5_000, modified: day(2026, 10, 28)),
    file("three-hundred-kb.txt", size: 300_000, modified: day(2026, 10, 10)),
    file("two-mb.txt", size: 2_000_000, modified: day(2025, 6, 1)),
    file("photo.png", size: 40_000, modified: day(2026, 11, 5, 10), kind: "PNG image"),
    file("photo.jpg", size: 9_000, modified: day(2026, 11, 4), kind: "JPEG image"),
    file("Albums", folder: true), file("Backups", modified: day(2026, 10, 28), folder: true),
    file("zeta", modified: day(2025, 3, 3), folder: true),
]

private func names(_ e: [FileEntry]) -> [String] { e.map(\.name) }

@Suite struct FilterTests {
    @Test func noFilterPassesEverything() {
        #expect(FilterSet().apply(folder, context: ctx).count == folder.count)
    }

    @Test func ticksWithinAColumnAreOred() {
        var f = FilterSet()
        f.toggle("small", in: .size)
        f.toggle("medium", in: .size)
        #expect(Set(names(f.apply(folder, context: ctx))) == ["three-hundred-kb.txt", "two-mb.txt", "photo.png"])
    }

    @Test func columnsAreAnded() {
        var f = FilterSet()
        f.toggle("small", in: .size)
        f.toggle("medium", in: .size)
        f.toggle("today", in: .modified)
        #expect(names(f.apply(folder, context: ctx)) == ["photo.png"])
        f.toggle("=PNG image", in: .kind)
        f.toggle("=Plain Text", in: .kind)
        #expect(names(f.apply(folder, context: ctx)) == ["photo.png"])
        f.toggle("=PNG image", in: .kind)
        #expect(names(f.apply(folder, context: ctx)).isEmpty)
    }

    @Test func untickingTheLastBucketClearsTheColumn() {
        var f = FilterSet()
        f.toggle("=Folder", in: .kind)
        #expect(f.isFiltered(.kind))
        #expect(Set(names(f.apply(folder, context: ctx))) == ["Albums", "Backups", "zeta"])
        f.toggle("=Folder", in: .kind)
        #expect(!f.isFiltered(.kind))
        #expect(f.isEmpty)
    }

    @Test func nameRangesAndUnspecifiedFolderSizes() {
        var f = FilterSet()
        f.toggle("Q-Z", in: .name)
        #expect(Set(names(f.apply(folder, context: ctx))) == ["three-hundred-kb.txt", "two-mb.txt", "zeta"])
        var g = FilterSet()
        g.toggle("unspecified", in: .size)
        #expect(Set(names(g.apply(folder, context: ctx))) == ["Albums", "Backups", "zeta"])
    }

    @Test func calendarDaysOrWithTheDateBuckets() {
        let cal = ctx.calendar
        var f = FilterSet()
        f.setDays(DayRange(day(2026, 10, 27), day(2026, 10, 28), calendar: cal), in: .modified)
        #expect(Set(names(f.apply(folder, context: ctx))) == ["five-kb.txt", "Backups"])
        f.toggle("longAgo", in: .modified)
        #expect(Set(names(f.apply(folder, context: ctx))) == ["five-kb.txt", "Backups", "two-mb.txt", "zeta"])
        f.setDays(nil, in: .modified)
        #expect(Set(names(f.apply(folder, context: ctx))) == ["two-mb.txt", "zeta"])
    }

    @Test func dayRangeTakesWholeDaysInEitherOrder() {
        let cal = calendar(firstWeekday: 2)
        let r = DayRange(day(2026, 10, 28, 23), day(2026, 10, 27, 1), calendar: cal)
        #expect(r.contains(day(2026, 10, 27, 0, 0), calendar: cal))
        #expect(r.contains(day(2026, 10, 28, 23, 59), calendar: cal))
        #expect(!r.contains(day(2026, 10, 29, 0, 0), calendar: cal))
        #expect(!r.contains(day(2026, 10, 26, 23, 59), calendar: cal))
    }

    @Test func tokensNameTheColumnAndTheTicksInListOrder() {
        var f = FilterSet()
        f.toggle("=Folder", in: .kind)
        f.toggle("medium", in: .size)
        f.toggle("small", in: .size)
        let tokens = f.tokens { column in Buckets.present(folder, column, context: ctx).map(\.bucket) }
        #expect(tokens == [FilterToken(column: .kind, text: "Type: Folder"), FilterToken(column: .size, text: "Size: Small, Medium")])
        f.clear(.kind)
        // Without the folder's bucket list the ticks fall back to id order.
        #expect(f.tokens().map(\.text) == ["Size: Medium, Small"])
        f.clearAll()
        #expect(f.tokens().isEmpty)
    }

    @Test func dateTokenShowsBucketsThenDays() {
        var f = FilterSet()
        f.toggle("today", in: .modified)
        f.setDays(DayRange(day(2026, 11, 2), day(2026, 11, 3), calendar: Calendar.current), in: .modified)
        let text = f.tokens().first?.text ?? ""
        #expect(text.hasPrefix("Date modified: Today, 2026-11-0"))
    }
}

@Suite struct GroupTests {
    @Test func groupsByDateNewestFirstWithCounts() {
        let groups = GroupBuilder.build(folder, by: GroupSpec(key: .modified, ascending: false), sort: .standard, context: ctx)
        #expect(groups.map(\.title) == ["Today (3)", "Yesterday (1)", "Last week (2)", "Last month (1)", "A long time ago (2)"])
        let asc = GroupBuilder.build(folder, by: GroupSpec(key: .modified, ascending: true), sort: .standard, context: ctx)
        #expect(asc.map(\.bucket.title) == ["A long time ago", "Last month", "Last week", "Yesterday", "Today"])
    }

    @Test func insideAGroupFilesComeBeforeFoldersInSortOrder() {
        let groups = GroupBuilder.build(folder, by: GroupSpec(key: .modified, ascending: false), sort: .standard, context: ctx)
        #expect(names(groups[0].items) == ["empty.txt", "photo.png", "Albums"])
        let byNameDown = GroupBuilder.build(folder, by: GroupSpec(key: .modified, ascending: false),
                                            sort: SortSpec(key: .name, ascending: false), context: ctx)
        #expect(names(byNameDown[0].items) == ["photo.png", "empty.txt", "Albums"])
    }

    @Test func sizeGroupsAscendAndFoldersStayLastUnderUnspecified() {
        let up = GroupBuilder.build(folder, by: GroupSpec(key: .size, ascending: true), sort: .standard, context: ctx)
        #expect(up.map(\.title) == ["Empty (1)", "Tiny (2)", "Small (2)", "Medium (1)", "Unspecified (3)"])
        let down = GroupBuilder.build(folder, by: GroupSpec(key: .size, ascending: false), sort: .standard, context: ctx)
        #expect(down.map(\.bucket.title) == ["Medium", "Small", "Tiny", "Empty", "Unspecified"])
        #expect(names(down[1].items) == ["photo.png", "three-hundred-kb.txt"])
    }

    @Test func typeGroupsAreAlphabeticalAndSortApplies() {
        let groups = GroupBuilder.build(folder, by: GroupSpec(key: .kind, ascending: true),
                                        sort: SortSpec(key: .size, ascending: false), context: ctx)
        #expect(groups.map(\.bucket.title) == ["Folder", "JPEG image", "Plain Text", "PNG image"])
        #expect(names(groups[2].items) == ["two-mb.txt", "three-hundred-kb.txt", "five-kb.txt", "empty.txt"])
    }

    @Test func anItemWithTwoTagsIsInBothGroups() {
        let a = file("a.txt"), b = file("b.txt"), c = file("c.txt")
        var ma = ItemMetadata(); ma.tags = ["Red", "Work"]
        var mb = ItemMetadata(); mb.tags = ["Work"]
        let meta: [String: ItemMetadata] = [a.url.path: ma, b.url.path: mb]
        let groups = GroupBuilder.build([a, b, c], by: GroupSpec(key: .tags, ascending: true), sort: .standard, context: ctx) {
            meta[$0.url.path] ?? ItemMetadata()
        }
        #expect(groups.map(\.title) == ["Red (1)", "Work (2)", "Unspecified (1)"])
    }

    @Test func layoutCollapsesAGroupAndMapsRowsToItems() {
        let groups = GroupBuilder.build(folder, by: GroupSpec(key: .size, ascending: true), sort: .standard, context: ctx)
        let open = ListLayout(groups: groups, collapsed: [])
        #expect(open.items.count == folder.count)
        #expect(open.rows.count == folder.count + groups.count)
        #expect(open.rows[0] == .header(0))
        #expect(open.item(atRow: 1) == 0)
        #expect(open.group(atRow: 2) == 1)
        #expect(open.rowOfItem[1] == 3)
        #expect(open.groupRanges[1] == 1..<3)
        let shut = ListLayout(groups: groups, collapsed: ["tiny"])
        #expect(shut.items.count == folder.count - 2)
        #expect(shut.rows.count == folder.count - 2 + groups.count)
        #expect(shut.groupRanges[1].isEmpty)
        #expect(shut.isCollapsed(1))
        #expect(shut.rows[2] == .header(1))
        #expect(shut.rows[3] == .header(2))
        #expect(shut.group(ofItem: 1) == 2)
    }

    @Test func ungroupedLayoutIsOneRowPerItem() {
        let layout = ListLayout(items: folder)
        #expect(!layout.isGrouped)
        #expect(layout.rows.count == folder.count)
        #expect(layout.item(atRow: 4) == 4)
        #expect(layout.group(atRow: 0) == nil)
    }
}
