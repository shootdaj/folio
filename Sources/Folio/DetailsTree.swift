import AppKit
import FolioCore

/// Details view's folders that open in place, as in the Finder's list view (FolioCore's ListTree): a
/// triangle on each folder row, Right and Left, Option+click for every level, View > Expand Selected
/// Folders and Collapse All Folders. The open folders belong to the folder on screen (`expandedFor`).
extension BrowserWindowController {
    /// One folder's items, with the window's hidden-item options (an open folder is never a zip or the Recycle Bin).
    nonisolated static func listFolder(_ url: URL, hidden: Bool, protected: Bool, home: URL) throws -> [FileEntry] {
        try FolderListing.list(url, includeHidden: hidden, cloud: CloudFolders.isCloud(url, home: home), hideProtected: protected)
    }

    /// The items of each open folder that can still be listed.
    nonisolated static func listChildren(_ keys: Set<String>, hidden: Bool, protected: Bool, home: URL) -> [String: [FileEntry]] {
        var out: [String: [FileEntry]] = [:]
        for key in keys {
            if let rows = try? listFolder(URL(fileURLWithPath: key, isDirectory: true), hidden: hidden, protected: protected, home: home) {
                out[key] = rows
            }
        }
        return out
    }

    /// A listing landed with the open folders it `tried`: their items replace the old ones, a folder that is
    /// gone (or can no longer be read) closes, and a folder opened while it ran keeps its own listing.
    func takeChildListings(_ children: [String: [FileEntry]], tried: Set<String>) {
        var kept = childListings.filter { !tried.contains($0.key) && expandedFolders.contains($0.key) }
        kept.merge(children) { $1 }
        childListings = kept
        let failed = tried.subtracting(children.keys)
        if !failed.isEmpty { expandedFolders.subtract(failed) }
    }

    /// Item `i`'s triangle: open or closed, or nil for no triangle (a file, a link, or not in Details view).
    func disclosure(ofItem i: Int) -> Bool? {
        guard arrangedWith?.tree == true, entries.indices.contains(i), ListTree.canExpand(entries[i]) else { return nil }
        return expandedFolders.contains(entryKeys[i])
    }

    /// Opens or closes the folders among `items`. `recursive` (Option+click) takes every level below too.
    func setFolders(open: Bool, items: [Int], recursive: Bool) {
        guard treeAvailable else { return }
        let keys = items.filter { entries.indices.contains($0) && ListTree.canExpand(entries[$0]) }.map { entryKeys[$0] }
        guard !keys.isEmpty else { return }
        let inside: (String) -> Bool = { k in keys.contains { k.hasPrefix($0 + "/") } }
        if !open {
            var closing = Set(keys)
            if recursive { closing.formUnion(expandedFolders.filter(inside)) }
            expandedFolders.subtract(closing)
            // Closed folders are not watched, so their items are listed again when they open.
            childListings = childListings.filter { !keys.contains($0.key) && !inside($0.key) }
            // A selected item inside a folder that closes is deselected; with nothing left, its folder is selected.
            let selected = Set(selectedKeys)
            let kept = selected.filter { !inside($0) }
            let folders = Set(keys.filter { k in selected.contains { $0.hasPrefix(k + "/") } })
            rearrange(selecting: kept.isEmpty && !folders.isEmpty ? folders : kept, scroll: false)
            return
        }
        expandedFolders.formUnion(keys)
        // The folders and any open folders kept inside them (shown again with them).
        let missing = recursive ? keys : (keys + expandedFolders.filter(inside)).filter { childListings[$0] == nil }
        guard !missing.isEmpty else {
            rearrange(scroll: false)
            return
        }
        reloadVisibleItems() // the triangles turn now; the items follow when listed
        let hidden = ListOptions.showHidden
        let protected = ListOptions.folder.hideProtectedOSFiles
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = expandedFor
        Task.detached(priority: .userInitiated) { [weak self] in
            var found: [String: [FileEntry]] = [:]
            for key in missing {
                let url = URL(fileURLWithPath: key, isDirectory: true)
                if recursive {
                    let all = ListTree.descendants(of: url) { try Self.listFolder($0, hidden: hidden, protected: protected, home: home) }
                    found.merge(all) { old, _ in old }
                } else if let rows = try? Self.listFolder(url, hidden: hidden, protected: protected, home: home) {
                    found[key] = rows
                }
            }
            await self?.childrenListed(found, requested: missing, recursive: recursive, folder: folder)
        }
    }

    /// The listings for `requested` landed. A folder closed meanwhile stays closed, and one that could not
    /// be listed closes again; Option+click opens every level found under a folder still open.
    private func childrenListed(_ found: [String: [FileEntry]], requested: [String], recursive: Bool, folder: String?) {
        guard folder == expandedFor else { return } // the window went to another folder meanwhile
        let wanted = requested.filter { expandedFolders.contains($0) }
        let under: (String) -> Bool = { k in wanted.contains { k == $0 || k.hasPrefix($0 + "/") } }
        expandedFolders.subtract(wanted.filter { found[$0] == nil })
        let kept = found.filter { under($0.key) }
        childListings.merge(kept) { $1 }
        if recursive { expandedFolders.formUnion(kept.keys) }
        rearrange(scroll: false)
    }

    /// The selected rows without items inside another selected folder: with folders open in place, a folder
    /// and its own items can both be selected, and Trash, Copy or a drag must take the folder alone.
    var outermostSelectedRows: IndexSet {
        let rows = selection.rows.filter { entries.indices.contains($0) }
        guard layout.depths.contains(where: { $0 > 0 }) else { return IndexSet(rows) }
        let keep = Set(ListTree.outermost(rows.map { entries[$0].url }).map { FilePaths.itemKey($0) })
        var seen = Set<String>()
        return IndexSet(rows.filter { keep.contains(entryKeys[$0]) && seen.insert(entryKeys[$0]).inserted })
    }

    /// Leaving Details: the grid gets the top level now (it must not draw the open folders' items for a
    /// moment); a selected item inside an open folder gives way to its top folder.
    func showTopLevelOnly() {
        let depths = layout.depths
        var selected = Set<String>()
        for i in selection.rows where entries.indices.contains(i) {
            var j = i
            while let p = ListTree.parent(of: j, depths: depths) { j = p }
            selected.insert(entryKeys[j])
        }
        let top = zip(entries, depths).filter { $0.1 == 0 }.map(\.0)
        // A rearrange still running would bring the tree back: it is dropped and its flag cleared.
        dropPendingRearrange()
        arrangedWith = arrangeKey
        show(ListLayout(items: top), selecting: selected)
    }

    /// A click on a row's triangle (the table, FileListDelegate).
    func toggleFolder(item i: Int, recursive: Bool) {
        guard let open = disclosure(ofItem: i) else { return }
        setFolders(open: !open, items: [i], recursive: recursive)
    }

    /// Right: the selected folders open. False outside Details' tree, so the key goes on to the table.
    func openSelectedFolders() -> Bool {
        guard treeAvailable else { return false }
        let closed = selection.rows.filter { disclosure(ofItem: $0) == false }
        if !closed.isEmpty { setFolders(open: true, items: Array(closed), recursive: false) }
        return true
    }

    /// Left: open folders in the selection close; otherwise the selection moves to the focus row's folder.
    func closeSelectedFolders() -> Bool {
        guard treeAvailable else { return false }
        let open = selection.rows.filter { disclosure(ofItem: $0) == true }
        if !open.isEmpty {
            setFolders(open: false, items: Array(open), recursive: false)
        } else if let f = selection.focus ?? selection.rows.first, let parent = ListTree.parent(of: f, depths: layout.depths) {
            selection.click(parent)
            applySelection(scrollTo: parent)
        }
        return true
    }

    @objc func expandSelectedFolders(_ sender: Any?) { _ = openSelectedFolders() }

    /// Every folder closes; a selected item inside one is deselected, and with nothing left its top folder is selected.
    @objc func collapseAllFolders(_ sender: Any?) {
        guard !expandedFolders.isEmpty else { return }
        let depths = layout.depths
        let selected = selection.rows.filter { entries.indices.contains($0) }
        let top = Set(selected.filter { layout.depth(ofItem: $0) == 0 }.map { entryKeys[$0] })
        let ancestors = Set(selected.map { i -> String in
            var j = i
            while let p = ListTree.parent(of: j, depths: depths) { j = p }
            return entryKeys[j]
        })
        expandedFolders = []
        rearrange(selecting: top.isEmpty ? ancestors : top, scroll: false)
    }

    /// View menu: Expand Selected Folders with a closed folder selected; Collapse All Folders with one open.
    func validateTreeItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(expandSelectedFolders(_:)): return treeAvailable && selection.rows.contains { disclosure(ofItem: $0) == false }
        case #selector(collapseAllFolders(_:)): return treeAvailable && !expandedFolders.isEmpty
        default: return nil
        }
    }
}
