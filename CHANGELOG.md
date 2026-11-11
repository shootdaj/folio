# Changelog

All notable changes to Folio are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A version exists once its `vX.Y.Z` tag is
pushed; the release workflow publishes the section below with that number as the release notes.

## [Unreleased]

### Added

- **Folio > Settings... (Cmd+,)** opens Folder Options, as Cmd+, opens an app's settings on a Mac, also
  with no window open. View > Options... (Cmd+Option+,) stays.

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
