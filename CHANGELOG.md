# Changelog

All notable changes to Folio are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A version exists once its `vX.Y.Z` tag is
pushed; the release workflow publishes the section below with that number as the release notes.

## [Unreleased]

### Added

- **Native shows the selected item's details on the right.** The pane comes up when items are
  selected and goes when none are, as Finder's preview column does. One item shows its name, kind,
  Tags and Comments and its details; several show how many and their size. An image shows as a
  picture across the top of the pane (220 pt high), in place of the icon. The navigation pane no
  longer has a Details section in Native. The pane is on by default in Native: its close button, or
  View > Show > Details Pane (Option+Shift+P), turns it off and on. It stays out of the way on Home and
  in Gallery, which previews the picture itself. D4 Obsidian keeps its Details card in the navigation
  pane and its pane that stays until it is closed. The Tags box no longer cuts off the bottom of its
  text in Native.

- **Search settings.** Folder Options has a "Search settings" box at the right of its tabs. Typing
  lists the matching settings of General, View and Search together, each with its tab and group, and
  each works in the list. A word matches at the start of a word in the title, the group, the tooltip or
  other names for the setting ("dot files" finds the hidden items). Esc empties the box, and a click
  on a tab shows that tab again. Cmd+F goes to the box. Folio > **Settings...** (Cmd+,) opens Folder
  Options with the box ready, also with no window open.

- **Reveal in Folio instead of Finder.** A new box in the Folio menu and in View > Options... >
  General > Folio and macOS. It sets the `NSFileViewer` default to Folio, so "Reveal in Finder" and
  "Show in Finder" in other apps show the item in Folio. A revealed folder shows selected in its parent,
  as in Finder. A folder from a command-line tool, the Dock, Finder or a drive's root still opens the
  folder itself. Turning the box off sends reveals to Finder again, and `make uninstall` removes the key.
  See docs/INSTALL.md section 5.

- **View > Theme: Native and D4 Obsidian.** Native is the new default and follows macOS: SF Pro, the
  system colours (light, dark and Increase Contrast follow the Mac), and the accent and highlight
  colours from System Settings > Appearance, so the title bar's accent swatch is hidden. Labels keep
  their case and menus use the system menu font. D4 Obsidian is unchanged, pixel for pixel. Native's
  reference is docs/design/native.md.

- **Native looks like a Mac app all through.** In the Native theme:
  - **Icons:** Finder's file icons, and SF Symbols for every glyph.
  - **Details list:** an inset rounded selection in the accent colour (grey when the list is not
    focused), white text in every column of a selected row, alternating rows, a 24 pt header with a
    chevron on the sorted column, and slim disclosure triangles.
  - **Window:** the sidebar runs the full height under the traffic lights, on the sidebar material. It
    has sentence-case section heads, accent symbols, a rounded selection and thin drive bars.
  - **Toolbar:** a material band with plain symbol buttons, a rounded address field and a real search
    field.
  - **Tabs:** they show only with two or more tabs, flat, with equal widths.
  - **Status bar:** 22 pt, with plain grey text.
  - **Icon views:** a plate behind the selected icon and an accent pill under its name.
  - **Dialogs and panels:** menus and drop-down panels on the menu material, the header filter on the
    popover material, and a context menu without the icon row. Home is a plain list. Folder Options,
    Properties ("Info"), the progress window and Choose Details use titled windows with real bezel
    buttons, check boxes and radios, and no cards.

  D4 Obsidian is unchanged, pixel for pixel. `Folio --uitest` takes `--tabs N`, `--view <mode>` and
  `--extra options|properties|preview|home`, to shoot more of the window.

- **The navigation pane has its own box for hidden folders.** View > Navigation Pane > Show Hidden
  Folders, also in View > Options... > View > Navigation pane. It is off by default, so hidden folders
  stay out of the tree when View > Show > Hidden Items (Cmd+Shift+.) shows them in the list. Before,
  the one setting filled the tree with dot folders. A hidden folder that you open still shows in the
  tree, on the way to the current folder.

- **A glass capsule behind the traffic lights (Native).** The close, minimise and zoom buttons sit on a
  capsule of Liquid Glass (frosted material before macOS 26), 36 pt high. Sidebar rows that scroll up
  under the buttons go behind it. The capsule is part of the buttons' own view, tied to them by
  constraints, so it stays centred on them. It goes in full screen. The Native window now has an empty
  system toolbar, as Finder has, so macOS itself centres the buttons on the 52 pt toolbar band. Before,
  Folio moved the buttons, and macOS put them back at its own place when it laid out the title bar
  again. Folio's own toolbar still takes every click.

- **View > Details Size: larger text and icons in Details view.** Small (as before: 13 pt names, 16 pt
  icons), Medium (14 and 20), Large (16 and 24) and Extra Large (18 and 32). The other columns, the rows,
  the rename box, the indent of open folders and the search marks grow with it. Bigger (Cmd++) and
  Smaller (Cmd+-) step through the sizes. The same choice is in View > Options... > View, under "Text and
  icon size in Details view", and the settings search finds it as "text size" or "icon size". Compact
  View still takes 4 pt off each row. The icon views keep their own sizes.

- **Folio asks once for Full Disk Access.** macOS asks again for each protected place (Desktop,
  Documents, Downloads, iCloud Drive, other apps' data, external and network drives). At launch, while
  Full Disk Access is off, Folio offers to open its page in System Settings: Open System Settings, Not
  Now, or Do Not Ask Again. Folio > Full Disk Access... opens the page any time. The guarded folders also
  get their own usage text in Info.plist.

- **Folders open in place in Details view.** As in the Finder's list view, each folder row has a triangle.
  A click shows the folder's items under it, indented, and a second click hides them. Option+click opens
  or closes every level below. Right opens the selected folders, and Left closes them or goes to the
  folder of an item inside one. View > Expand Selected Folders and Collapse All Folders do the same from
  the menu. Each level follows the list's sort and filters, auto-refresh follows the open folders, and
  each window remembers them per folder while Folio runs. The status bar counts the folder's own items.
  There are no triangles in the other views, in search results, with Group by, in a zip or in the
  Recycle Bin. The top level's icons and names do not move.

### Changed

- **Native uses Finder's names for places.** The navigation pane's sections are Favorites and Locations,
  and the Trash is "Trash" everywhere in Native: its row, the address bar, the tab, Empty Trash, and Move
  to Trash. A search of the whole Mac is "This Mac". D4 Obsidian keeps Explorer's names (Quick access,
  This PC, Recycle Bin). The Details section's "Select an item..." text now breaks between words, not
  inside one.

- **Less work everywhere else, too.**
  - **File operations:** a copy, move, trash or rename lists again only the windows on the folders it
    touched; before, every window listed its folder again. The decorations (tags, locked, custom
    icons) are forgotten only for the folder that was read, not for every window. A big paste resolves
    each folder once, not each pasted item twice.
  - **Rows:** custom folder icons and locked or compressed items come from the flags the listing
    already read: no disk read per row. App icons no longer read the app's date on every draw, and a
    batch of app icons that loads redraws the list once, not once per icon.
  - **Search:** streaming results are arranged at most 4 times a second (and at once at the end),
    ranked with the fast name order, and the tab strip updates only when the title changes. The live
    walk lists folders with the bulk read and checks tags with one `getxattr`: about twice as fast
    (20,330 items: 0.9 s to 0.5 s). Closing a window stops its search and its timer.
  - **Selection:** the session file keeps at most 1,000 selected items per tab and is written off the
    main thread (after Cmd+A in a big folder it wrote every path after each pause). The status bar
    updates once per change, the Paste button asks the pasteboard only when it changed, the sidebar
    redraws only the Details card, and the Preview pane, Gallery and Quick Look follow held arrow keys
    at most every 0.1 s.
  - **Sidebar:** the drop line is a thin strip, hidden when there is none, not a view the height of
    the whole tree. Native's outline has no background drawing of its own, so AppKit no longer draws
    one for its full height (over 100,000 pt with a big folder open in the tree). D4 keeps its cards.
  - **Watchers:** the folder watcher asks FSEvents for folder events, not one per file anywhere under
    the folder (a tab on ~ was sent every write in the home folder), and drops what is pending when it
    stops. A cancelled job no longer keeps a 30 Hz timer running, and the progress panel redraws only
    when something on it moved.
  - **Smaller things:** grouping by date works out the date edges once per arrange, not per item;
    Group by Name skips Unicode folding for plain letters; folder tips and the address bar's folder
    menus use the fast readers; the icon grid is not reloaded while hidden; Home works out its rows and
    dates once per change, not at each draw; and mapped shares already mounted are not mounted again
    at launch.

- **Folders open faster, and the navigation pane no longer holds up a move.** Measured with the new
  `Folio --bench <folder>` on a folder of 20,331 items:
  - The listing took 255 ms. It now reads the folder with `getattrlistbulk` (name, type, date, size and
    flags of many items in one call) instead of URL resource values per item, and takes 51 ms (Downloads:
    4.5 ms to 0.5 ms). A file with no extension still asks macOS for its type, as macOS types some by name.
    The sealed system volume (/, /usr, /System), a folder that cannot be read this way and links still go
    the URL way. A test holds every field to the URL way on a fixture and on real folders.
  - The item keys (for selection and refresh) took 580 ms on the main thread for each load. They now
    come with the sort, off the main thread, and cost 36 ms.
  - The sort took 390 ms. It now compares names that are made into Core Foundation strings once, in the
    same order as `localizedStandardCompare`, and takes 125 ms.
  - The tree read each folder with every file's metadata on the main thread: 133 ms for that folder,
    194 ms for /tmp. It now reads folder entries with `readdir`, so files cost nothing: 12 ms and 38 ms.
  - On each move, the tree reads the folders on the way off the main thread, then opens. The session's
    open tree folders do the same at launch. Auto-refresh of the tree also reads off the main thread,
    once, instead of twice on the main thread.
  - Sidebar rows no longer resolve their path on every draw.
  - A load that a newer move replaces stops at its next step. Kind names ("PNG image") are kept while
    Folio runs.

- **`make app` signs with a local identity when the Mac has one.** `make signing-identity` makes a
  self-signed "Folio Local Signing" certificate in the login keychain, once. With it every build has the
  same designated requirement, so macOS keeps Full Disk Access and the folder grants after `make install`.
  Before, each ad hoc build had a new hash and lost them. Without the identity (CI, the VM) the build
  stays ad hoc.

- **The app icon is three glass leaves.** Three folder-shaped glass leaves, fanned like cards (a folio
  is a leaf), in the style of the macOS 26 system icons. It replaces the D1 grid icon. In the default icon
  style the front leaf is blue on a white tile. In macOS 26's dark icon style it is white on a graphite
  tile. `make app` compiles the two pictures with actool (from Xcode) into Assets.car. Without Xcode the
  bundle has Folio.icns only, with the light icon in every style. The pictures are full bleed, so macOS
  cuts its own shape and adds its rim and shadow, and no size gets the grey frame (a tile with a clear
  margin got one at 16 and 32 px). In the bundle the Dock draws the icon itself. Resources/AppIcon.png
  and AppIcon-dark.png (from `folio-icon --png`) replace the two SVGs.

- **Quick access starts with Explorer's set.** A fresh install pins Desktop, Downloads, Documents,
  Pictures, Music and Movies, in that order, and leaves out any of them that does not exist. It no
  longer starts with the author's own `Anshul/Code` folder. Saved pins do not change.

### Fixed

- **"Show hidden files, folders and drives" can be chosen in Folder Options.** AppKit made one radio
  group of every radio in a view, so View > Advanced settings had one group, not two. "Select the typed
  item in the view" then turned the hidden-files radio off again at once, and neither hidden-files radio
  showed as chosen. General's "Click items as follows" had the same fault for its two pairs. Each group
  now keeps its own choice. View > Show > Hidden Items (Cmd+Shift+.) was not affected.

- **Open Folders in Folio says why macOS 26 keeps folders on Finder.** macOS 26 protects the default
  app for folders (`public.folder`) and refuses it with error -50 for every app. Folio now says that
  macOS protects the setting and that only Finder can change it, in place of a bare "error -50". Drives
  still open in Folio. The box now shows on while drives open in Folio, so a second click hands them
  back to Finder. Before, the box stayed off, and a click only asked for Folio again.

- **A drag no longer sticks when Mission Control takes the mouse-up.** Dragging files, a marquee
  selection, resizing the navigation pane or the search box, and the date filter's calendar now stop
  when the mouse button is up, even if the release never reached Folio (Mission Control, a Space
  switch). Before, the window stayed in the press until the next click.

- **A Quick access click no longer scrolls the navigation pane.** The tree still opens down to the
  folder, but the pane scrolls to it only when no row for that folder (the pin, a tree row) is in view.
  Before, a click on a pin scrolled the pane to the same folder under This PC. Ctrl+Shift+E still
  scrolls to the tree row and selects it.

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
