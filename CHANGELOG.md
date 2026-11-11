# Changelog

All notable changes to Folio are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A version exists once its `vX.Y.Z` tag is
pushed; the release workflow publishes the section below with that number as the release notes.

## [Unreleased]

## [1.1.0] - 2026-11-11

### Added

- **Folio > Settings... (Cmd+,)** opens Folder Options, as Cmd+, opens an app's settings on a Mac, also
  with no window open. View > Options... (Cmd+Option+,) stays.
- **Open "Show in Finder" from other apps in Folio.** A new box in View > Options... > General > Folio
  and macOS, off on a new install. On, it sets the `NSFileViewer` default to Folio, so "Show in Finder" and
  "Reveal in Finder" in apps that ask macOS through NSWorkspace show the item selected in Folio. Apps that
  call Finder by name still go to Finder. Off sends reveals to Finder again, and `make uninstall` removes
  the key. See docs/INSTALL.md section 5.
- **Columns view.** Finder's column view in Folio's look, beside Details, List, the icons, Tiles, Content
  and Gallery (View > Columns, the View button, Ctrl+Shift+9). A column per folder from the first one
  (home, a Quick access place or the drive) to the current folder; a selected folder's contents or a
  selected file's preview card after it. Right goes into the selected folder, Left back to the column
  before; Back, Forward and Up work as everywhere; every file command, drag and menu works in the current
  column, and a click in another column makes its folder the current one at once. Dividers drag to resize
  (the width is kept for every folder) and double-click to fit. Group by and filters are greyed there, and
  search results keep their list.

### Fixed

- **Mission Control works again after a drag over the navigation pane or the file list.** The drag ended
  with an error inside macOS's drag code ("unrecognized selector draggingEnded:"), so macOS still saw a
  drag, and Mission Control did not open, by key or by mouse, until Folio quit.
- **A press no longer sticks when its release never reaches Folio.** Dragging files, a marquee selection,
  resizing the navigation pane or the search box, and the date filter's calendar now stop once the mouse
  button is up, even when Mission Control or a Space switch took the release. Before, the window stayed
  in the press, and the next click went to ending it.
- **A Quick access click no longer scrolls the navigation pane.** The tree still opens down to the
  folder, but the pane scrolls to it only when no row for that folder (a pin, a tree row) is in view.
  Before, a click on a pin scrolled the pane to the same folder under This PC, and the pin left the view.
  A typed path, New folder from a node's menu and Ctrl+Shift+E still scroll to the folder's tree row.
- **"Show hidden files, folders and drives" can be chosen in Folder Options.** AppKit made one radio
  group of every radio in a view, so View > Advanced settings had one group, not two: "Select the typed
  item in the view" turned the hidden-files radio off again at once. General's "Click items as follows"
  had the same fault for its two pairs. Each group now keeps its own choice. View > Show > Hidden Items
  (Cmd+Shift+.) was not affected.
- **Open folders in Folio says why macOS 26 keeps folders on Finder.** macOS 26 protects the default
  app for folders and refuses it with error -50 for every app, Finder too. Folio now says that macOS
  protects the setting and that only Finder can change it, in place of a bare "error -50". Drives still
  open in Folio, and the box now shows on while they do, so a second click hands them back to Finder.
- **A reload during a re-sort no longer leaves the window marked as busy.** The reload dropped the
  re-sort's result, as it should, but the re-sort's flag stayed set, so the window never counted as
  settled again until it loaded another folder.

### Changed

- **Big folders open, sort and search many times faster, and the window no longer freezes on them.**
  Measured in the test VM with `Tests/vm/perf.sh` (fixed fixtures, median of 3 runs, 1.0.0 -> now):
  - Opening a folder of 10,000 files: 0.70 -> 0.11 s; 50,000 files: 3.7 -> 0.47 s (the window froze
    for 1.6 s of it); 200,000 files: 42 -> 5.5 s, where the window froze for 29 s while every item's
    path was resolved on the main thread (now its longest stall is 24 ms).
  - Sorting 50,000 files: 2.4-2.7 -> 0.15-0.21 s; 200,000 files: 13.6-27 -> 0.64-0.89 s.
  - Searching a 200,000-file tree: 11.9 -> 1.5 s; typing to filter a 50,000-file folder: 2.4 -> 0.76 s.
  - Select all in a 200,000-file folder: the longest stall 510 -> 224 ms.
  - A folder where files keep coming and going: 10,000 files, each refresh 685 -> 129 ms and 12.3 ->
    3.9 s of CPU in 10 s; 50,000 files, 39 -> 5.1 s of CPU, and 8 refreshes shown where 1.0.0 showed none.
  - How: folders are read with `getattrlistbulk`; the sort works out each item's keys once and uses every
    core; item paths are resolved off the main thread, once per folder; a file with no extension is typed
    once per name; search and tag dots skip files the file system says have no extended attributes; the
    search walk takes a folder per core; auto-refresh paces itself by what a listing costs; Select all
    counts in place; the tree reads folders with `readdir` off the main thread; file operations reload
    only the windows they touched; the session is written off the main thread. Much of it is Taylor
    King's work (PR #23), re-landed with tests that only touch temp folders.

## [1.0.0] - 2026-11-07

The first release: all nine milestones of docs/plan/MILESTONES.md and the D4 Obsidian spotlight look,
each driven with real keystrokes and clicks in the test VM (Tests/vm/m2.sh to m9.sh).

### Added

- **Scaffold and Details view (M1).** Name, Date modified, Type and Size; Explorer's sort (folders first,
  File2 before File10, up to 4 keys with Shift+click); resize, reorder and fit columns; the status bar.
- **Address bar, history and keys (M2).** Back, Forward and Up with history lists; breadcrumbs with
  folder flyouts; typed paths with typeahead, %temp% and shell: names; F-keys, Backspace, Home and End,
  mouse buttons 4 and 5; keys bound to what macOS sees after Karabiner and BetterTouchTool.
- **Selection and file operations (M3).** Explorer's selection rules and check boxes; a real cut;
  Name - Copy; one progress window with pause, speed graph and Dock progress; Replace or Skip with
  Compare; folder merge; F2 rename (batch, Tab to the next); New folder and New text document; Trash
  and Shift+Delete; undo and redo.
- **Drag and drop, menus, Properties (M4).** Drags in and out of other apps with Explorer's modifiers
  and a right-drag menu; spring-loaded folders; the item and background menus (Open with, Copy as path,
  Send to, Share, Print, aliases); Properties with General, Security, Details, Shortcut and Unblock.
- **Tree, tabs, drives, Home (M5).** The navigation pane's tree; Quick access pins; Home with Favorites
  and Recent; This PC with usage bars, eject and rename; Network, SMB and mapped shares; the Recycle Bin
  with Restore; tabs (tear out, merge, reopen) and windows.
- **Views, columns, filters, groups (M6).** Icons, List, Tiles, Content and Gallery; header filters and
  Group by on Explorer's buckets; Choose details and 20 more columns; preview and details panes; Quick
  Look; one view for every folder.
- **Search (M7).** Live results with word-start matching; AQS (AND, OR, NOT, kind:, size:, date:, ext:,
  folder:, tag:, content:); Search options; the Folder column; Open file location; saved and recent
  searches; Spotlight plus a live walk for the places it skips.
- **Compress, options, tags, extras (M8).** Compress to ZIP, 7z and TAR and Extract all (bsdtar); zips
  browsed as folders; Folder Options (General, View, Search); Finder tags; auto-refresh; access keys;
  full screen; rotate, desktop picture, folder icons, format and check, previous versions, cloud files.
- **Make it the default (M9).** `ff` from the shell (new window, new tab, --reveal, --search) over a
  folio: URL; Open folders in Folio instead of Finder; a BetterTouchTool Win+E preset; the Dock icon;
  windows, tabs, history, selection, scroll, sort, search, tree and view back after a relaunch; keep
  running with no window; launch at login; `Folio --version`; docs/KEYS.md.
- The D4 Obsidian spotlight look (docs/design/d4-obsidian-spotlight.html): Geist type, dark and light
  following the Mac, an accent of any hue from the title bar's swatch, tabs in the title bar. It replaces
  the D1 Control room look the milestones were built in.
- Cmd+Left and Cmd+Right go back and forward in the list, as Option+Left and Option+Right do.
- Every key the window receives is logged to ~/Library/Logs/Folio/keys.log, to trace a shortcut that
  does nothing.
- Versions come from git tags `vX.Y.Z`: `make app` stamps the version and commit count into Info.plist
  and `Folio --version` prints `Folio <version> (<commit>)`.
- CI on a self-hosted runner on the Mac Ultra: unit tests, the app bundle and the VM scripts M2 to M9
  on every pull request; a pushed `vX.Y.Z` tag publishes `Folio-X.Y.Z.zip` as a GitHub release.

[Unreleased]: https://github.com/shootdaj/folio/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/shootdaj/folio/releases/tag/v1.0.0
