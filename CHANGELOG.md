# Changelog

All notable changes to Folio are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A version exists once its `vX.Y.Z` tag is
pushed; the release workflow publishes the section below with that number as the release notes.

## [Unreleased]

### Added

- **View > Theme: Native and D4 Obsidian.** Native is the new default and follows macOS: SF Pro, the
  system colours (light, dark and Increase Contrast follow the Mac), and the accent and highlight
  colours from System Settings > Appearance, so the title bar's accent swatch is hidden. Labels keep
  their case and menus use the system menu font. D4 Obsidian is unchanged, pixel for pixel. Native's
  reference is docs/design/native.md; icons, the list, the sidebar and the window chrome follow in
  the next releases.

### Changed

- **The app icon is a manila folder.** A warm manila folder with a sheet and a blue index tab, on a slate
  tile with the Mac's continuous corners and top light, replaces the D1 grid icon. It fills the whole icon
  shape, so macOS 26 shows it as drawn (no grey box). It is one picture for light and dark, as the
  system's icons are, so the Dock no longer swaps it. Resources/AppIcon.png (from `folio-icon --png`)
  replaces the two SVGs.

- **Quick access starts with Explorer's set.** A fresh install pins Desktop, Downloads, Documents,
  Pictures, Music and Movies, in that order, and leaves out any of them that does not exist. It no
  longer starts with the author's own `Anshul/Code` folder. Saved pins do not change.

### Fixed

- **A drag no longer sticks when Mission Control takes the mouse-up.** Dragging files, a marquee
  selection, resizing the navigation pane or the search box, and the date filter's calendar now stop
  when the mouse button is up, even if the release never reached Folio (Mission Control, a Space
  switch). Before, the window stayed in the press until the next click.

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
