# Folio

A native macOS file manager that behaves like Windows Explorer. Swift 6 + AppKit, built with the free
Command Line Tools, no Xcode, no Apple developer account. The look is D4 Obsidian spotlight
(docs/design/d4-obsidian-spotlight.html), dark and light following the Mac, with an accent of any hue
picked from the swatch at the right end of the title bar.

Install it on a Mac: [docs/INSTALL.md](docs/INSTALL.md). Every key: [docs/KEYS.md](docs/KEYS.md).

## The golden rule for development

**The Folio binary never runs on the physical Mac, in any mode** (docs/plan/RULES.md, rule 0). On the host:
`swift build`, `make app`, `make test` (unit tests on temp folders they make), `codesign`. Every run of the
app, `ff` included, happens in the tart VM `folio-test` on the Ultra (docs/plan/VM.md): stage the build,
run `Tests/vm/m<N>.sh` there, bring the PNGs back and look at them. Anshul's files are never a test
target. Tests first (swift-testing), then code, then proof in docs/proof/.

```sh
make test     # swift test: FolioCore and FolioLink, temp folders only
make app      # build/Folio.app (runs nothing but folio-icon, which draws the Dock icon)
```

## What it does, milestone by milestone

| | Milestone | What came with it |
|---|---|---|
| 1 | Scaffold and Details view | Name, Date modified, Type, Size; Explorer's sort (folders first, File2 before File10, up to 4 keys with Shift+click); resize, reorder, fit columns; status bar |
| 2 | Address bar, history and keys | Back, Forward, Up with history lists; breadcrumbs with flyouts; typed paths with typeahead, %temp% and shell: names; F-keys, Backspace, Home and End, mouse buttons 4 and 5; the Karabiner and BTT key map |
| 3 | Selection and file operations | Explorer's selection rules and check boxes; a real cut; Name - Copy; one progress window with pause, speed graph and Dock progress; Replace or Skip with Compare; folder merge; F2 rename (batch, Tab to the next); New folder and text document; Trash and Shift+Delete; undo and redo |
| 4 | Drag and drop, menus, Properties | Drags in and out of other apps with Explorer's modifiers and a right-drag menu; spring-loaded folders; the item and background menus (Open with, Copy as path, Send to, Share, Print, aliases); Properties with General, Security, Details, Shortcut and Unblock |
| 5 | Tree, tabs, drives, Home | The navigation pane's tree; Quick access pins; Home with Favorites and Recent; This PC with usage bars, eject and rename; Network, SMB and mapped shares; the Recycle Bin with Restore; tabs (tear out, merge, reopen) and windows |
| 6 | Views, columns, filters, groups | Icons, List, Tiles, Content, Gallery; header filters and Group by on Explorer's buckets; Choose details and 20 more columns; preview and details panes; Quick Look; one view for every folder |
| 7 | Search | The search box with live results, word-start matching, AQS (AND, OR, NOT, kind:, size:, date:, ext:, folder:, tag:, content:), Search options, the Folder column, Open file location, saved and recent searches; Spotlight plus a live walk for the places it skips |
| 8 | Compress, options, tags, extras | Compress to ZIP, 7z, TAR and Extract all (bsdtar); zips as folders; Folder Options (General, View, Search); Finder tags; auto-refresh; access keys; full screen; rotate, desktop picture, folder icons, format and check, previous versions, cloud files |
| 9 | Make it the default | `ff` from the shell (new window, new tab, --reveal, --search) over a folio: URL; Open folders in Folio instead of Finder; a BetterTouchTool Win+E preset; the Dock icon; windows, tabs, history, selection, scroll, sort, search, tree and view back after a relaunch (crash-safe session file); keep running with no window; launch at login; `Folio --version`; docs/KEYS.md |

Proof screenshots from the VM for each milestone are in docs/proof/; the plan is docs/plan/MILESTONES.md and
the Explorer research behind it is in docs/research/.
