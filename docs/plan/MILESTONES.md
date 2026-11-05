# Folio milestones

Generated from the build plan report on 2026-11-05. Each milestone lists what it delivers, how it is checked, and every Explorer feature (from docs/research) that lands in it.

## Milestone 1: Scaffold and Details view

**Delivers:** Swift Package Manager project and the make-app script. A window lists any folder in Details view: Name, Date modified, Type, Size, with Name 34 em wide and never hidden. Click a header to sort, click again to reverse; Date modified starts newest first. Shift+click adds sort keys, up to 4. Folders sit on top when ascending and at the bottom when descending. Names sort as numbers (File2 before File10) and Type ties break by Name. Columns resize, reorder and fit on a divider double-click. Dates show in local time. Status bar: N items, N selected, selected size. Type to select and dark mode come free.

**Checked by:** make app builds and the app opens on your home folder; every column sorts both ways, folders on top and then at the bottom. Unit tests pin the comparator: File2 before File10, File.txt before File 1.txt.

**Features:**
- [Panes, tabs, windows] Status bar : Shows N items, N items selected and the total size of selected files, plus (filtered from N) while a filter is on.
- [Panes, tabs, windows] Classic menu bar (Always show menus) : The macOS menu bar is always there and carries every command.
- [Views and columns] Details view : The default for every folder and the only view until milestone 6.
- [Views and columns] Default columns: Name, Date modified, Type, Size : Explorer's General items set; Name starts 34 em wide and cannot be hidden.
- [Views and columns] Click a header to sort, click again to reverse : NSTableView draws the arrow; Date modified starts newest first on the first click, as in Explorer.
- [Views and columns] Shift+click a header for another sort key : Up to 4 sort keys, as Explorer's GUI allows.
- [Views and columns] Folders first : Folders on top when ascending and at the bottom when descending, since the whole list reverses.
- [Views and columns] Numerical sort (File2 before File10) : localizedStandardCompare, Finder's own sort, plus tests for Explorer's edge cases: File.txt before File 1.txt, and 1.5 before 1.25.
- [Views and columns] Type ties broken by Name : The tie-break follows the main direction, so Type descending puts file2.txt before file1.txt.
- [Views and columns] Resize, reorder and fit columns : Drag a divider, drag a header, or double-click a divider to fit; columns never stretch to the window.
- [Views and columns] Size column units : Classic Explorer always shows KB rounded up (a 15-byte file shows 1 KB); 2026 builds are testing KB, MB or GB.
- [Views and columns] Dates in local time : Each date uses the daylight-saving rule of its own day, as Explorer does, and sorting uses the real timestamp, never the text.
- [Selection] Type to select : Built into the macOS table view.
- [Better than Explorer (from macOS)] Dark mode follows the system : AppKit draws light and dark from the system setting with no extra code.

## Milestone 2: Address bar, history and keys

**Delivers:** Back, forward and up with a history per window and a right-click list. Breadcrumbs: click a segment to jump, the arrow after it lists that folder's subfolders, click empty space to edit the path. Cmd+L (your Cmd+D) selects the path. Typeahead lists matching folders as you type; Down and Enter pick, Tab fills, ~ expands. History dropdown, Copy address, pasted paths in quotes accepted, %temp% style variables and shell: names mapped to Mac places. Backspace back, F5 refresh, Enter opens, F6 cycles focus, Home and End, mouse buttons 4 and 5. Every key in the key map bound to what macOS sees after Karabiner.

**Checked by:** Unit tests on history, path parsing and the typeahead matcher; then I drive the real app with your Karabiner and BTT running and press every key in the key map.

**Features:**
- [Address bar and navigation] Back and forward (Alt+Left, Alt+Right, Backspace) : Bound to Option+Left and Option+Right, which your Cmd+Left and Cmd+Right send, and Backspace goes back even with files selected.
- [Address bar and navigation] Back and forward history list : Right-click or hold either arrow to jump several steps at once.
- [Address bar and navigation] Up one folder (Alt+Up) : Bound to Option+Up, so your Cmd+Up works as it does on Windows.
- [Address bar and navigation] Refresh (F5, Ctrl+R) : Your Mac already sends plain F-keys (fnState is 1, tested), so F5 works without Fn.
- [Address bar and navigation] Breadcrumb address bar : Each path segment is a button that jumps to that folder.
- [Address bar and navigation] Breadcrumb arrow flyout : The arrow after a segment lists that folder's subfolders, so you can jump sideways without going up first.
- [Address bar and navigation] Click to edit the path : Click empty space in the bar and the crumbs turn into a selected text path.
- [Address bar and navigation] Focus the address bar (Alt+D, Ctrl+L, F4) : Cmd+L in the app, which your Cmd+D already sends through the BTT rule.
- [Address bar and navigation] Address bar autocomplete : A dropdown lists matching folders under the path so far; Down and Enter pick one, Tab fills the top match, ~ expands to home.
- [Address bar and navigation] Address bar history dropdown : Recent typed and visited locations; Windows 11 shows only about 5.
- [Address bar and navigation] Copy address, Copy address as text : Right-click the bar to copy the folder path as plain text without quotes.
- [Address bar and navigation] Lenient path parsing : Pasted paths in quotes or with doubled slashes still open, as Windows added in 2026.
- [Address bar and navigation] Environment variables in the path (%appdata%, %temp%) : %userprofile% maps to your home, %appdata% to ~/Library/Application Support and %temp% to $TMPDIR, and $HOME works too.
- [Address bar and navigation] shell: folders (shell:downloads, shell:startup) : The common ones map to Mac places, such as shell:appsfolder to /Applications and shell:recyclebinfolder to the Trash; Windows-only ones are ignored.
- [Shortcuts and mouse] Open the selection (Enter) : Folders navigate and files launch; Return never renames (Top 25, item 2).
- [Shortcuts and mouse] Cycle focus (F6, Tab, Shift+Tab) : Moves between the address bar, the tree and the file list.
- [Shortcuts and mouse] First and last item (Home, End) : Switchers miss these in Finder (Top 25, item 9).
- [Shortcuts and mouse] Mouse back and forward buttons : Buttons 4 and 5 go back and forward.
- [Shortcuts and mouse] Close the window (Alt+F4) : Option+F4, which your Cmd+F4 sends, closes the window, like Cmd+W.
- [Shortcuts and mouse] Your Karabiner and BTT keys : The app binds what macOS sees after Karabiner, such as Option+Left and Cmd+L, so BTT's Finder-only rules can stay as they are.
- [Shortcuts and mouse] Function keys (F2, F3, F4, F5, F6) : Your Mac sends plain F1 to F12 (fnState is 1, tested), so they work without Fn.

## Milestone 3: Selection and file operations

**Delivers:** Click, Cmd+click, Shift+click, Cmd+Shift+click, rubber band, Select all, Select none, Invert selection, keyboard focus moves with a Space toggle, optional check boxes. A real cut that moves on paste; cut items dim and Esc cancels. Pasting into the same folder makes Name - Copy, then Name - Copy (2). One progress window for all jobs with pause, cancel, speed graph, time left and progress on the Dock icon. Clashes wait until the end, then Replace, Skip or Let me decide, with Do this for the next N conflicts, keep both and skip identical; folders merge instead of being replaced. F2 renames the base name only, Tab moves to the next name, batch rename gives Name (1), Name (2). New folder, New text document. Trash, Shift+Delete, and undo and redo for copy, move, rename, delete and new folder.

**Checked by:** Tests on a temp folder for every operation, undo included; then a 2 GB folder copy with the progress window paused and resumed.

**Features:**
- [Panes, tabs, windows] Command bar and See more menu : New, Cut, Copy, Paste, Rename, Share, Delete, Sort and View in a toolbar, with Select all, Select none, Invert selection, Properties and Options under See more.
- [Selection] Click, Ctrl+click, Shift+click : Cmd+click toggles on the Mac, since Ctrl+click is right-click there; Shift+click selects a range from the anchor.
- [Selection] Ctrl+Shift+click : Adds a second range without dropping the first.
- [Selection] Rubber-band selection : Drag from empty space to draw a rectangle; Cmd+drag on the Mac adds to the selection.
- [Selection] Select all (Ctrl+A) : Covers filtered and search results too.
- [Selection] Select none, Invert selection : In the See more menu.
- [Selection] Shift+arrows, Shift+Home, Shift+End : Extends the selection from the keyboard.
- [Selection] Ctrl+arrows, then Ctrl+Space : Moves the focus without selecting and toggles the focused item; AppKit tables move the selection with the arrows, so this needs a custom focus row.
- [Selection] Item check boxes : A box inside the Name cell, shown on hover and on selected rows, and a box at the left of the Name header that selects all.
- [File operations] Cut, Copy, Paste (Ctrl+X, Ctrl+C, Ctrl+V) : A real cut that moves on paste, which Finder only does with Cmd+Option+V; cut items dim until pasted and Esc cancels (Top 25, item 1).
- [File operations] Paste into the same folder : Makes Name - Copy, then Name - Copy (2), where Finder would write Name copy.
- [File operations] New folder (Ctrl+Shift+N) : Creates New folder and starts the rename at once.
- [File operations] New, Text document and other types : Finder has no New file at all (Top 25, item 6); the list takes your own templates too.
- [File operations] Rename (F2) : Selects the base name only so the extension stays; Enter opens and never renames.
- [File operations] Tab, Shift+Tab while renaming : Commits and moves to rename the next or previous item.
- [File operations] Batch rename : Select several, press F2, type one name: they become Name (1), Name (2), each keeping its extension.
- [File operations] Rename warnings : Asks before an extension change; a Mac only rejects / and Finder shows : as /, so the app blocks both.
- [File operations] Delete to Recycle Bin (Delete, Ctrl+D) : Forward delete (Fn+Delete on your keys) moves items to the macOS Trash, while the Mac Delete key stays Back.
- [File operations] Permanent delete (Shift+Delete) : Asks first, then removes for good.
- [File operations] Undo, Redo (Ctrl+Z, Ctrl+Y) : Many steps of copy, move, rename, delete and new folder, with the menu naming the action, such as Undo rename.
- [File operations] One progress window for all jobs : Jobs stack in one window, each with pause, resume and cancel, and links to open the source or destination.
- [File operations] More details: speed graph : Live speed, current file, time left and items and bytes left, a paused job turns yellow, and the Dock icon shows the progress.
- [File operations] Replace or skip files dialog : Replace, Skip or Let me decide, with Do this for the next N conflicts; clashes wait until the other files are done.
- [File operations] Compare dialog: keep both, skip identical : Source and destination side by side with thumbnail, size and date; tick both to keep both and the copy gets a number.
- [File operations] Folder merge on copy : Same-named folders merge, where Finder's Replace wipes the target (Top 25, item 5).
- [File operations] Error dialogs: file in use, access denied : Try again, Skip, Cancel, and an admin password prompt for protected places; the 260-character path limit does not exist on a Mac.
- [Shortcuts and mouse] Cancel (Esc) : Cancels a rename, a drag or a pending cut.
- [Shortcuts and mouse] Copy and paste (Ctrl+Insert, Shift+Insert) : Mac keyboards have no Insert key, so this is for a PC keyboard plugged in.

## Milestone 4: Drag and drop, menus, Properties

**Delivers:** Drag in and out of Finder, Terminal, browsers and Mail. Same drive moves, another drive copies, Option copies, Cmd+Option makes an alias, and the drag badge names the action. Right-drag, or a modifier on drop, gives Copy here, Move here, Create shortcuts here. Spring-loaded folders and breadcrumbs as drop targets. Right-click menu with the icon row, Open, Open with (Always sets the Mac default), Open in Terminal, Copy as path, Create shortcut (alias), Send to, Print, Share and Properties. Properties (Option+Return, your Cmd+Enter): type, opens with, size, size on disk, dates, folder contents counted live, locked and hidden flags, owner and permissions, metadata, and an Unblock box that clears the quarantine flag.

**Checked by:** Drag to and from four other apps with each modifier; every menu item run once on a temp folder.

**Features:**
- [Address bar and navigation] Address bar runs commands (cmd, powershell, notepad) : Typing terminal, cmd or wt opens Terminal in this folder, and an app name such as TextEdit launches that app.
- [Address bar and navigation] Drag files onto breadcrumbs : Drop on a segment to move or copy into that folder.
- [File operations] Copy as path (Ctrl+Shift+C) : Copies full paths in quotes, one per line.
- [File operations] Copy and paste files with other apps : File URLs on the macOS pasteboard, so files copied in Finder paste here and the other way round.
- [File operations] Drag to move or copy : Same drive moves and another drive copies, the rule Finder also uses.
- [File operations] Drag modifiers and badge : macOS uses Option to copy, Cmd to move and Cmd+Option for an alias, since Ctrl+click is right-click; the badge reads Copy to, Move to or Create link in, plus the folder name.
- [File operations] Right-button drag menu: Copy here, Move here, Create shortcuts here : With a mouse right button, or a held modifier on drop with the trackpad.
- [File operations] Drag in and out of other apps : Finder, Terminal, browsers and Mail, and dropping on an app opens the files with it.
- [Context menu and Properties] Icon row: Cut, Copy, Paste, Rename, Share, Delete : Drawn as a custom row at the top of the menu, with names on hover.
- [Context menu and Properties] Open, Open with : Open with lists apps from Launch Services plus Choose another app, and its Always box sets the Mac default.
- [Context menu and Properties] Share : The macOS share sheet, with AirDrop, Mail and Messages.
- [Context menu and Properties] Create shortcut, Paste shortcut : Makes a Finder alias, with a symlink option next to it.
- [Context menu and Properties] Send to : Desktop (as an alias), Mail recipient, Compressed folder, other drives, and your own targets.
- [Context menu and Properties] Print : Hands documents to their app's print command, and PDFs and text to lp.
- [Context menu and Properties] Background menu: View, Sort by, Group by, Refresh, New, Paste, Undo : Right-click empty space.
- [Context menu and Properties] Show more options (Shift+right-click, Shift+F10, Menu key) : A Mac menu needs no second tier, so everything sits in one menu; other apps' items arrive through the Services submenu, since Finder Sync extensions only load in Finder.
- [Context menu and Properties] Properties (Alt+Enter, Alt+double-click) : Option+Return and Option+double-click as macOS sees your Cmd key, and Cmd+I works too.
- [Context menu and Properties] Properties, General tab : Type, Opens with and Change, location, size, size on disk, dates, Read-only and Hidden as the Mac locked and hidden flags, and for folders Contains N files, M folders counted live.
- [Context menu and Properties] Properties, Security tab : Owner, group, permissions and ACLs, editable.
- [Context menu and Properties] Properties, Details tab : Title, authors, tags, comments and EXIF or ID3 fields from Spotlight and ImageIO.
- [Context menu and Properties] Unblock (downloaded files) : Maps to the macOS quarantine flag: ticking Unblock removes com.apple.quarantine.
- [Context menu and Properties] Shortcut tab : For aliases and symlinks: the target path and Open file location.
- [Context menu and Properties] Multi-selection Properties : Combined size and count, and set flags or tags on all at once.
- [Better than Explorer (from macOS)] Open folder in Terminal : From the right-click menu, the background menu or the address bar, at the selected or current folder.
- [Better than Explorer (from macOS)] Spring-loaded folders : Hover a drag over a folder and it opens so you can drop deep inside; Explorer only does this for tree nodes and tabs, and switchers name it as a Finder feature they miss.

## Milestone 5: Tree, tabs, drives, Home

**Delivers:** Navigation pane folder tree with Right and Left keys, expand to the current folder, and right-click actions on any node. Quick access pins you drag to reorder; Home with Quick access, Favorites and Recent. This PC: every volume with a usage bar that turns red when nearly full, rename, eject, disk images. Network: Bonjour finds SMB servers, \\server\share and smb:// paths connect, passwords go in the Keychain, mapped shares come back at sign-in. Trash view with Original location and Date deleted. Tabs: new, close, middle-click a folder for a background tab, duplicate, close others, drag to reorder, tear out or merge, drop files on a tab, each with its own history. New windows, and macOS tiling for two locations side by side.

**Checked by:** Pin, unpin and reorder; open ten tabs and tear one out; eject a USB stick from the sidebar.

**Features:**
- [Panes, tabs, windows] Navigation pane with folder tree : Expand arrows live in the sidebar tree only, never in the file list; show, hide and resize it from View.
- [Panes, tabs, windows] Tree keys (Right, Left, NumLock+*, Ctrl+Shift+E) : Right expands, Left collapses or goes to the parent, Option+Right expands everything below as in any Mac outline, and Ctrl+Shift+E expands down to the current folder.
- [Panes, tabs, windows] Right-click any tree node : Act on a folder, such as New folder or Paste, without opening it (Top 25, item 15).
- [Panes, tabs, windows] Drop onto tree nodes : Hovering a drag over a node expands it so you can drop deeper.
- [Panes, tabs, windows] Pin to Quick access, Unpin : Pin from the right-click menu or by dragging a folder into Quick access.
- [Panes, tabs, windows] Reorder Quick access pins : Drag up or down; the order carries over to Home.
- [Panes, tabs, windows] Home: Quick access, Favorites, Recent : Recent files come from Spotlight's last-opened date, which records opens through Finder and apps (tested), and each section collapses and stays collapsed.
- [Panes, tabs, windows] New tab, Close tab (Ctrl+T, Ctrl+W) : Cmd+T and Cmd+W as macOS sees them; a new tab opens at Home with its own history, and closing the last tab closes the window.
- [Panes, tabs, windows] Open in new tab (middle-click a folder or breadcrumb) : Middle-click opens it in a background tab; a trackpad has no middle button, so the right-click menu covers it.
- [Panes, tabs, windows] Tab menu: Duplicate tab, Close other tabs, Close tabs to the right
- [Panes, tabs, windows] Switch tabs (Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+1 to 9) : Mac window tabs already use Ctrl+Tab and Ctrl+Shift+Tab, and Cmd+1 to 9 jump to a tab; Cmd+Tab stays the app switcher.
- [Panes, tabs, windows] Reorder, tear out and merge tabs : macOS window tabs give drag to reorder, drag out for a new window and Merge all windows for free; hovering a drag over a tab switches to it.
- [Panes, tabs, windows] New window (Ctrl+N), Open in new window : Cmd+N as macOS sees it.
- [Panes, tabs, windows] Two locations side by side : macOS 15 tiles two windows from the Window menu or by dragging to a screen edge (Top 25, item 14).
- [Drives, network, devices] This PC: devices and drives : Every mounted volume from /Volumes plus the startup disk.
- [Drives, network, devices] Drive usage bars : X GB free of Y GB, red when nearly full, with a used and free chart in the drive properties.
- [Drives, network, devices] Rename a drive (F2) : Uses diskutil rename.
- [Drives, network, devices] Eject : From the sidebar, the menu and the toolbar, through NSWorkspace's unmount and eject.
- [Drives, network, devices] Mount ISO and disk images : Opening a .dmg or .iso mounts it with hdiutil, and Eject detaches it.
- [Drives, network, devices] Recycle Bin view : Original location and Date deleted with Restore and Empty; ~/.Trash is a dot folder Spotlight never indexes and may need Full Disk Access, so this needs testing.
- [Drives, network, devices] Network: computers and NAS : Bonjour finds SMB servers as Finder's Network sidebar does; macOS 15 asks for Local Network permission first, and a banner shows when it is denied.
- [Drives, network, devices] UNC paths (\\server\share) : Typed \\server\share or smb://server/share both mount under /Volumes through NetFS.
- [Drives, network, devices] Credential prompt, Remember my credentials : Saved in the macOS Keychain.
- [Drives, network, devices] Map network drive, Disconnect : A remembered share that the app mounts again at sign-in.
- [Drives, network, devices] Add a network location (WebDAV, FTP) : macOS mounts WebDAV read and write, and FTP read-only, as Finder does.
- [Drives, network, devices] Cloud folders: iCloud Drive, Dropbox, Google Drive : They live under ~/Library/CloudStorage and iCloud Drive, with a cloud badge on online-only files.

## Milestone 6: Views, columns, filters, groups

**Delivers:** Icons from small to extra large, List, Tiles, Content and Gallery, thumbnails from QuickLookThumbnailing, Cmd+scroll to resize, compact mode. Header right-click to show columns, Size column to fit and Size all columns to fit; Choose details lists every column with Move up, Move down and a width field. Header filter chevrons with checkbox buckets. Name: 0 to 9, A to H, I to P, Q to Z, Other. Size: Empty 0, Tiny to 16 KB, Small to 1 MB, Medium to 128 MB, Large to 1 GB, Huge to 4 GB, Gigantic over 4 GB, folders under Unspecified. Date: a calendar, then Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year, A long time ago. Type: one box per type present. Ticks OR within a column and AND across columns; a filtered header shows a tick and a token in the search box; filters are never saved. Group by on the same buckets, headers like Today (3) that collapse, Collapse all groups, a header click selects the group, and files come before folders inside a group. Preview pane, details pane, hidden items faded, extensions on or off, Space for Quick Look. One view for every folder; no folder keeps its own.

**Checked by:** Switch every view in a folder of 20,000 files and time it; tick two size buckets and a date bucket and match the status bar count against find.

**Features:**
- [Panes, tabs, windows] Preview pane (Alt+P) : Option+P as macOS sees your Cmd+P; it renders the selection with Quick Look's preview view, so every format Quick Look reads works.
- [Panes, tabs, windows] Details pane (Alt+Shift+P) : Thumbnail, type, size, dates and tags of the selection, or a folder summary when nothing is selected.
- [Views and columns] Header right-click menu (Ctrl+Numpad + fits all) : Ticks for common columns such as Date created, Authors, Tags and Title, Size column to fit, Size all columns to fit as a one-off, and More... at the bottom.
- [Views and columns] Choose details dialog (More...) : Every column with a checkbox, Move up, Move down and a width field in pixels; Name is greyed out.
- [Views and columns] More columns: Date created, Date accessed, Dimensions, Length, Bit rate, Date taken, Camera model, Album, Owner, Attributes : Read from file attributes, Spotlight, ImageIO and AVFoundation off the main thread, and cached.
- [Views and columns] Column header filters : Hover a header for a chevron that opens a checkbox list; ticks OR within a column and AND across columns.
- [Views and columns] Name and Type filters : Name offers 0 to 9, A to H, I to P, Q to Z and Other; Type offers one box per type present, such as File folder or PDF Document.
- [Views and columns] Size filter : Empty 0, Tiny to 16 KB, Small to 1 MB, Medium to 128 MB, Large to 1 GB, Huge to 4 GB, Gigantic over 4 GB, and folders under Unspecified.
- [Views and columns] Date filter : A calendar for a day or range, then Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year and A long time ago, with the week start from your Mac.
- [Views and columns] Filtered column shows a tick : The filter also shows as a removable token in the search box, such as Size: Large, Huge, and it is never saved with the folder.
- [Views and columns] Group by : Same buckets as the filters, headers like Today (3) that collapse from a chevron on the left, Collapse all groups, and files before folders inside a group.
- [Views and columns] Layouts (Ctrl+Shift+1 to 8) : Extra large, large, medium and small icons, List, Details, Tiles and Content, plus compact mode; Cmd+Shift+3, 4 and 5 are macOS screenshot keys, so those three need another binding.
- [Views and columns] Ctrl+mouse wheel zoom : Cmd+scroll or a trackpad pinch steps through icon sizes and layouts.
- [Views and columns] Thumbnails : QuickLookThumbnailing renders images, video, PDFs and documents, with an arrow badge on aliases and symlinks.
- [Views and columns] Gallery : A photo wall of images and videos from chosen folders, newest first, with a date scrubber on the right.
- [Views and columns] Show hidden items, Show file name extensions : One click each under View, Show; hidden means dot files plus the hidden flag, and hidden items draw faded.
- [Views and columns] Per-folder view memory and folder templates : Left out by your instruction: one view for every folder and no folder-type sniffing, while Explorer cannot turn this off at all.
- [Views and columns] Apply to Folders, Reset Folders : Become Save as default view and Reset view, since one view covers every folder.
- [Selection] Click a group header to select the group : One group at a time, as since Windows 7.
- [Selection] Selection survives view and sort changes : Sources disagree on whether Explorer keeps a multi-selection when the sort changes; keeping it is the safer choice.
- [Better than Explorer (from macOS)] Quick Look (Space) : The same panel Finder uses; switchers praise it and wish Explorer had it.

## Milestone 7: Search

**Delivers:** Box top right reading Search <folder>, focused by Cmd+E, Cmd+F or F3. It searches this folder and its subfolders, with a Current folder switch. Results fill the view live as you type, as in Windows 11 since 22H2, with a progress bar in the address bar. Word-start matching: bert finds Bertie, not Albert; *bert finds Albert. AND, OR, NOT in capitals only, quotes, brackets, * and ?. Filters kind:, size:, date:, datemodified:, ext:, name:, folder:, tag: and content:; size words empty to gigantic on the filter buckets; date words such as this week as calendar periods. The Search options menu writes these terms into the box. Results show in Details with a Folder column in name (parent path) form, plus Open file location and Save search. Engine: Spotlight through NSMetadataQuery scoped to the folder, with fixes for what testing on this Mac showed. Dates go as >= start and < end, since == $time.today returns nothing. Sizes go as >= and <= pairs, since InRange fails in mdfind. ? goes as * and is checked again. folder: is checked on result paths, since kMDItemPath is not searchable. Phrases in contents are checked by reading the candidates. CamelCase and digit splits are dropped to match Windows. A live walk covers what Spotlight skips: dot folders, the Trash, /private/tmp, external drives with indexing off, network shares and zip contents; both result sets merge by path.

**Checked by:** Search ~/Downloads and ~/Anshul/Code and watch results fill as you type; a test folder with Bert, Bertie, Albert, a dot folder and a phrase file returns exactly the hits the Windows rules predict.

**Features:**
- [Search] Search box, top right: Search <folder> : The placeholder uses the display name, such as Search Downloads, each tab has its own box, and its left edge drags wider.
- [Search] Focus search (Ctrl+E, Ctrl+F, F3) : Cmd+E, Cmd+F and F3 as macOS sees them; Alt+D, Ctrl+L and F4 stay with the address bar.
- [Search] This folder and all subfolders : NSMetadataQuery scoped to the folder is recursive (tested), search never looks above it, and This PC searches the whole Mac.
- [Search] Current folder, All subfolders : Current folder keeps only results whose parent is this folder.
- [Search] Results as you type : Live in the main view since Windows 11 22H2 with no Enter; each key restarts the query after a 250 to 400 ms pause, a clone choice since Microsoft gives no number.
- [Search] Word-start matching : bert finds Bertie, not Albert, and *bert finds Albert; Spotlight's word mode also splits CamelCase and digits (tested), so the app drops those extra hits.
- [Search] A bare word searches more than the name : It also matches tags, authors, title and, where indexed, contents; name: limits it to names and content: to contents.
- [Search] AND, OR, NOT in capitals : Lowercase and, or, not are plain words, a space means AND, and binding runs left to right, so the parser adds brackets.
- [Search] Quotes and brackets : Exact phrases in names work in Spotlight; phrases in contents return 0 (tested), so each word goes to Spotlight and the app reads candidates to check the phrase.
- [Search] Wildcards * and ? : Spotlight ignores ? on macOS 15.4.1 (tested), so ? goes as * and the app checks the real pattern.
- [Search] Filters kind:, size:, date:, datemodified:, datecreated:, ext:, name:, folder:, tag:, author:, content: : Each becomes a Spotlight query; folder: is checked on result paths, because kMDItemPath is not searchable (tested).
- [Search] Size words (size:empty to size:gigantic) : Same buckets as the Size filter, sent as >= and <= pairs because InRange fails in mdfind (tested).
- [Search] Date words (today, this week, last month) : Calendar periods, not rolling days, sent as >= start and < end, because == $time.today returns nothing (tested).
- [Search] Kinds (kind:picture, kind:document, kind:folder) : Spotlight's type trees are broader (public.archive matched a raw .bin, tested), so an extension table gives Windows' exact kinds.
- [Search] Search options menu: Date modified, Kind, Size : Each pick adds a term to the box and re-runs; the filters are only text in the box.
- [Search] File contents, System files, Zipped folders : Each toggle turns on a live walk that reads contents, adds system folders or looks inside zips, none of which Spotlight does (zip tested).
- [Search] Places Spotlight skips : A live walk covers /private/tmp, dot folders, the Trash, external drives with indexing off and network shares, merged by path; files hidden with chflags read kMDItemFSInvisible 0 (tested), so hidden checks use isHidden.
- [Search] Search Results in <folder> : The address bar gains that last segment with a progress bar while gathering, Back returns to the results with the query restored, and clearing the box closes the search.
- [Search] Results view with a Folder column : The Folder column reads name (parent path), such as invoices (~/Documents/2026); Windows 11 forces Content view here, the clone keeps Details.
- [Search] Results order and empty state : Starts in relevance order, which the app scores (name, then properties, then contents), and an empty search reads No items match your search.
- [Search] Open file location : Right-click a result to open its folder with the item selected.
- [Search] Save search : Saves scope, query and view as a file that reruns live, like a .search-ms.
- [Search] Recent searches : Windows 11 dropped this dropdown when live results came, so it sits behind a setting.

## Milestone 8: Compress, options, tags, extras

**Delivers:** Compress to zip, 7z or tar and Extract all through bsdtar, which ships with macOS and uses libarchive like Windows 11; browse a zip like a folder. Folder options with General, View and Search tabs, including the nine settings Microsoft removed and restored in 2023. Full screen. Tags and colour labels shared with Finder. Auto-refresh when files change on disk. Rotate images, set the desktop picture, custom folder icons, format and check a drive, previous versions, keep or free cloud files.

**Checked by:** Zip and unzip a folder of 1,000 files in zip, 7z and tar; change a file in Terminal and see the list update within a second.

**Features:**
- [Panes, tabs, windows] Access keys (Alt) : Letter badges on the toolbar for keyboard-only use; Mac menus already open from the keyboard with Ctrl+F2.
- [Panes, tabs, windows] Full screen (F11) : macOS uses F11 for Show Desktop unless you turn that off in Keyboard Shortcuts, so Ctrl+Cmd+F is the fallback.
- [File operations] Compress to ZIP, 7z, TAR : bsdtar ships with macOS on libarchive, the same library Windows 11 uses, and made zip, 7z and tgz files on this Mac (tested).
- [File operations] Extract all : Picks a folder and shows it when done; libarchive also reads rar, which still needs a test here.
- [File operations] ZIP as a folder : Browse a zip like a folder and drag files out of it.
- [Context menu and Properties] Remove properties and personal information : Strips metadata in place or makes a clean copy.
- [Context menu and Properties] Image commands: Rotate, Set as desktop background : sips rotates in place and NSWorkspace sets the desktop picture.
- [Context menu and Properties] Customize this folder (icon) : Sets a custom folder icon, the way Finder's Get Info does.
- [Context menu and Properties] Restore previous versions : Lists saved document versions and Time Machine copies where they exist.
- [Folder options and settings] Folder options dialog : General, View and Search tabs with the same wording, each with Restore defaults.
- [Folder options and settings] Open File Explorer to: Home or This PC
- [Folder options and settings] Browse folders: same window or own window
- [Folder options and settings] Click items: single-click or double-click to open : Single-click mode underlines names on hover or always.
- [Folder options and settings] Privacy: recent files, frequent folders, Clear history : Clear wipes recent files, frequent folders and address bar history.
- [Folder options and settings] Always show icons, never thumbnails; Display file icon on thumbnails
- [Folder options and settings] Display file size information in folder tips
- [Folder options and settings] Display the full path in the title bar
- [Folder options and settings] Hide empty drives
- [Folder options and settings] Hide folder merge conflicts : Off makes the app ask before merging same-named folders.
- [Folder options and settings] Hide protected operating system files : Hides .DS_Store, .localized and similar files even while hidden items are shown.
- [Folder options and settings] Show drive letters : A Mac has no drive letters, so this shows or hides the mount path, such as /Volumes/USB.
- [Folder options and settings] Show pop-up description for folder and desktop items : Turns the hover tooltips with type, size, dates or dimensions on or off.
- [Folder options and settings] Show preview handlers in preview pane
- [Folder options and settings] Show status bar
- [Folder options and settings] When typing into list view : Select the typed item (default) or type into the search box.
- [Folder options and settings] Navigation pane: Expand to open folder, Show all folders, Show Network, Show This PC : Show all folders roots the tree at the top of the Mac, with Home, drives, Network and Trash.
- [Folder options and settings] Search tab: index and non-indexed options : Don't use the index forces the live walk; the other three match the Search options toggles.
- [Folder options and settings] Delete confirmation dialog : Off by default, as in Explorer.
- [Drives, network, devices] Format, Check for errors : diskutil eraseVolume after a confirm, and diskutil verifyVolume, the check behind Disk Utility's First Aid.
- [Drives, network, devices] Always keep on this device, Free up space : Download or evict iCloud and cloud-provider files.
- [Drives, network, devices] Phones and cameras : A Mac has no MTP; iPhones and cameras come through Image Capture's framework.
- [Drives, network, devices] Share a folder on the network : Turns on macOS File Sharing for the folder.
- [Better than Explorer (from macOS)] Tags and colour labels : Read and written as Finder tags so both apps agree, and tag: search uses kMDItemUserTags (tested).

## Milestone 9: Make it the default

**Delivers:** An ff <path> command, a BTT hotkey that opens the app instead of Finder (your Win+E), and a Dock icon. Folders sent from ff or other apps open as a new tab. Windows, tabs and last folders come back after a restart. No preloading needed: the app keeps running with no windows open.

**Checked by:** Press the hotkey and the app opens on the folder; restart the Mac and every tab comes back.

**Features:**
- [Folder options and settings] Open external folder links in a new tab : For folders sent from other apps or the ff command.
- [Folder options and settings] Window preloading : Not needed: a Mac app keeps running with no windows open, so new windows open at once.
- [Shortcuts and mouse] Open File Explorer from anywhere (Win+E) : A BTT hotkey opens the app instead of Finder.
- [Better than Explorer (from macOS)] Remembers windows and tabs across restarts : Explorer does this only with Restore previous folder windows at logon turned on; here it is always on.

## Key map (as Anshul presses them, Karabiner swaps Cmd and Option)

| Press | macOS sees | App does | Why |
|---|---|---|---|
| Cmd + Left | Option + Left | Back | BTT turns this into Cmd+[ only inside Finder. The new app binds Option+Left itself, so BTT stays as it is. |
| Cmd + Right | Option + Right | Forward | Same as Back: bound directly to Option+Right. |
| Cmd + Up | Option + Up | Up one folder | Bound directly to Option+Up. |
| Cmd + D | Option + D → BTT sends Cmd + L | Edit the address bar, with typeahead | Your global BTT rule already sends Cmd+L for this. The app binds Cmd+L, like a browser. As you type, a dropdown lists matching folders under the path so far; Down and Enter pick one, Tab fills the top match, ~ expands to your home. |
| Enter | Return | Open file or folder | Never renames. Your Finder-only BTT rule (Return→Cmd+O) is not needed here. |
| Backspace | Delete | Back | Explorer habit. With files selected it still goes back; Delete key handles trash. |
| Fn + Delete | Option + Delete | Move to Trash | Karabiner maps Fn+Backspace to Option+Delete; the app treats forward-delete and Option+Delete as Trash. |
| F2 | F2 | Rename in place | Explorer habit. |
| Fn + X / C / V | Cmd + X / C / V | Cut, copy, paste files | Karabiner maps Fn+letter to Cmd+letter. Cut really moves the file on paste. |
| Space | Space | Quick Look | The one Finder feature worth keeping. |
| Type letters | Letters | Jump to the matching name | Built into the macOS table view. |

## Research findings that shape the build

- **Results fill live as you type** Since Windows 11 22H2 the full results page updates as you type, with no Enter. Windows 10 1909 to early Windows 11 showed a dropdown and filled the view only on Enter. Microsoft gives no delay, so the clone waits about 250 to 400 ms and cancels the old query on each key. (https://blogs.windows.com/windows-insider/2022/09/29/announcing-windows-11-insider-preview-build-22621-730-and-22623-730/)
- **Search matches the start of words** A plain term matches where a word starts: bert finds Bert and Bertie, not Albert, and *bert finds Albert. Words split on spaces and punctuation only, so Image does not find MyImageFactory. A bare word also searches tags, authors, title and, where indexed, contents. AND, OR and NOT work only in capitals and bind left to right. (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t)
- **Size buckets are exact byte ranges** Empty 0, Tiny to 16 KB, Small to 1 MB, Medium to 128 MB, Large to 1 GB, Huge to 4 GB, Gigantic over 4 GB, in binary units, since Windows 10 1809. The same buckets drive the Size filter, Group by and the size: words. Many guides still quote the smaller Windows 7 buckets, which are wrong for Windows 11. (https://learn.microsoft.com/en-us/windows/win32/properties/props-system-size)
- **Per-folder view memory has no off switch** Remember each folder's view settings was removed in Windows 7. Since then every folder keeps its own view, up to 5,000 folders, and nothing turns that off. The clone has no per-folder memory at all, by your instruction: one view for every folder, and filters are never saved. (https://en.wikipedia.org/wiki/List_of_features_removed_in_Windows_7)
- **Shift+click sorts on up to 4 keys** Shift+click a second header to add a sort key; the GUI allows 4 and the registry stores 3. Folders sit on top when ascending and at the bottom when descending. Type ties break by Name in the same direction. NSTableView already keeps earlier sort keys, so this costs little. (https://lesferch.github.io/WinSetView/Manual.html)
- **Dates group by calendar periods** Measured on Windows 11: Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year, A long time ago, with no Last year. The week starts on the user's first day of week. Filters and Group by share these buckets, so one bucket engine serves both. (https://github.com/Maxaubert/Prism/pull/287)
- **The Folder column reads name (parent path)** In Details view, search results add a Folder column with the folder name first and the parent path in brackets, for example Aerospace-Fiction (F:\My Pictures\Scanned Not Tagged\Objects\Vehicles). Windows 11 opens results in Content view and offers no setting to change it; the clone keeps Details. (https://learn.microsoft.com/en-us/answers/questions/3948497/how-to-set-the-folder-field-format-in-search)
- **Spotlight limits found by testing on this Mac** On macOS 15.4.1, == $time.today and InRange with $time return nothing, so dates go as >= start and < end. InRange on sizes fails in mdfind but works in NSMetadataQuery. The ? wildcard is ignored. Multi-word phrases in file contents return 0. kMDItemPath is not searchable, so folder: filters run on result paths. (https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryFormat.html)
- **The Trash and dot folders are gaps in Spotlight** Dot files and dot folders are not indexed, so ~/.Trash is not either, and neither are /private/tmp, external drives with indexing off, network shares or files inside zips. Windows search reaches the Recycle Bin with isdeleted: and crawls places its index skips. The clone runs a live walk for these places and merges it with Spotlight by path. (https://en.wikipedia.org/wiki/Windows_Search)
- **Nine Folder Options came back after feedback** Build 23481 in June 2023 removed nine settings: Hide folder merge conflicts, Always show icons never thumbnails, Display file icon on thumbnails, Display file size in folder tips, Hide protected operating system files, Show drive letters, Show pop-up description, Show encrypted or compressed NTFS files in color, and Use Sharing Wizard. Build 23486 restored them. The clone keeps the ones that mean something on a Mac. (https://www.pcworld.com/article/1962876/windows-may-soon-have-fewer-folder-options-in-file-explorer.html)
- **The Top 25 power users name most** Cut and paste files, Enter opens and F2 renames, editable address bar, always-visible folder tree, folder merge on copy, New text document, full path and Copy as path, keyboard-first navigation, Home and End, Delete to Recycle Bin and Shift+Delete, detailed copy dialog, This PC drive overview, open a terminal here, two locations side by side, right-click any tree node, one-click hidden items and extensions, UNC paths and Map network drive, Details view with folders first, icon sizes and Ctrl+wheel zoom, Shift+right-click extended menu, breadcrumbs you can click, drop on and drop down, column header filters, right-drag drop menu, F2 batch rename with Tab to the next file, global hotkeys. (https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/)
