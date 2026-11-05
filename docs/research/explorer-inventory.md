# Windows 11 File Explorer: exhaustive feature inventory

Purpose: reference list for a native macOS clone of Windows 11 File Explorer. Every line is one feature: **name**: what it does (one plain sentence). Source URL.

Compiled 2026-11-05 from Microsoft Support, Microsoft Learn, Windows Insider blog, Wikipedia, and power-user guides (How-To Geek, Windows Central, Winaero, ElevenForum, Reddit).

Status: all sections complete (2026-11-05). 375 distinct features in sections 1–7 and 9–12, plus 76 rows in the shortcut table (section 8, overlaps the others by design) and the Top 25 (section 13).

Caveats: about two-thirds of the citations are third-party guides (ElevenForum, Pureinfotech, Geekrewind, Winaero), because Microsoft documents few Explorer details. Lines marked "verify" or "(guide)" rest on weaker evidence. Several 2025–2026 items (preloading, Manage file flyout, customizable context menu, WinUI Properties, hover actions) are Insider or staged rollouts and may not be on every build. Some cited sites (ElevenForum, ninjaone, computerhope, dell, ucdavis) return HTTP 403 to bots but open normally in a browser.

## Sections and feature counts

| # | Area | Features |
|---|---|---|
| 1 | Address bar and navigation | 33 |
| 2 | Panes, tabs, windows, command bar | 39 |
| 3 | Views and columns | 39 |
| 4 | Selection | 17 |
| 5 | File operations | 51 |
| 6 | Context menu and Properties | 47 |
| 7 | Search (brief) | 10 |
| 8 | Keyboard and mouse shortcuts table | 76 rows |
| 9 | Folder Options, every setting | 48 |
| 10 | Drives, network, devices | 31 |
| 11 | Integration (Home, Gallery, Recommended, OneDrive, sharing) | 33 |
| 12 | Obscure power-user tricks (incl. 6 PowerToys add-ons) | 27 |
| 13 | Top 25 features power users name most | 25 |

---

## 1. Address bar and navigation

- **Back / Forward buttons**: Step through this window's (or tab's) folder history. Keys: Alt+Left / Alt+Right, Backspace for back. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Back/Forward history list**: Right-clicking, or holding, the Back or Forward arrow lists earlier locations so you can jump several steps at once. https://www.elevenforum.com/t/dropdown-arrow-in-file-explorer-history-navigation-missing.31624
- **Up button**: Goes to the parent folder (Alt+Up). It sits beside the address bar. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Refresh button**: Reloads the current folder listing (F5 or Ctrl+R). https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Breadcrumb address bar**: Shows the path as clickable segments, and clicking any segment jumps to that ancestor folder. https://en.wikipedia.org/wiki/File_Explorer
- **Breadcrumb chevron flyout**: The ">" arrow after a segment drops down a list of that folder's subfolders, so you can jump sideways without going up first. https://it.environment.ucdavis.edu/file-explorer
- **Click-to-edit path**: Clicking empty space in the address bar turns the breadcrumbs into an editable, selectable text path. https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/
- **Focus address bar (Alt+D, Ctrl+L, F4)**: Puts the cursor in the address bar with the path selected, ready to type. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Address bar history dropdown**: The dropdown at the right of the address bar lists recently typed or visited locations (Windows 11 caps it at about 5 entries). https://techcommunity.microsoft.com/t5/windows-11/win11-file-explorer-address-bar-dropdown-list-shows-only-5-items/m-p/4547039
- **Copy address / Copy address as text**: Right-clicking the address bar copies the current folder's path, either as an object or as plain text without quotes. https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/
- **Address bar as a Run box**: Typing a program name (e.g. `notepad`) or URL in the address bar launches it, the same as Win+R. https://binaryfork.com/file-explorer-run-commands-13621/
- **Open a shell in this folder**: Typing `cmd`, `powershell` or `wt` in the address bar opens that shell with the current folder as working directory. https://binaryfork.com/file-explorer-run-commands-13621/
- **shell: commands**: Typing `shell:sendto`, `shell:startup`, `shell:appsfolder` and ~100 others jumps to special system folders. https://www.elevenforum.com/t/list-of-windows-11-shell-commands-for-shell-folder-shortcuts.1080/
- **CLSID (GUID) shell locations**: `shell:::{GUID}` paths open virtual folders such as Control Panel items and the Recycle Bin. https://winaero.com/windows-11-shell-commands-the-complete-list
- **Environment variables in the path**: `%appdata%`, `%localappdata%`, `%temp%`, `%userprofile%` resolve and open in place. https://geekrewind.com/browse-to-the-appdata-roaming-folder-in-windows-11/
- **Lenient path parsing (2026)**: The address bar accepts pasted paths wrapped in quotation marks or with doubled backslashes. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/
- **Drag files onto breadcrumbs**: Dropping files on a breadcrumb segment moves or copies them into that ancestor folder. https://blogs.windows.com/windows-insider/2024/06/19/announcing-windows-11-insider-preview-build-26241-canary-channel/
- **Middle-click in address bar / Home (2026)**: Middle-clicking a breadcrumb or a Home folder opens it in a new tab. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/
- **Full path in title bar**: Optional setting that shows the full path (not just the folder name) in the window/tab title. https://www.elevenforum.com/t/display-full-path-in-title-bar-of-file-explorer-in-windows-11.3585/
- **Search box beside the address bar**: Searches the current folder and its subfolders; Ctrl+E, Ctrl+F or F3 focuses it. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **OneDrive status button in the header**: In OneDrive folders, a cloud button shows sync state and storage quota, with links to OneDrive web and settings. https://pureinfotech.com/file-explorer-new-header-ui-home-gallery-changes-windows-11/
- **Navigation pane tree**: The left pane lists Home, Gallery, OneDrive, pinned Quick access folders, This PC, drives, Network and Linux, as an expandable tree. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Tree keyboard navigation**: Right arrow expands or enters the first subfolder, Left collapses or selects the parent, and NumLock+* expands all subfolders, NumLock+/- expand/collapse. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Expand tree to current folder (Ctrl+Shift+E)**: Expands the navigation pane down to the folder you are viewing. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Expand to open folder**: Option that keeps the navigation tree synced to, and expanded at, the current folder. https://learn.microsoft.com/en-us/answers/a/7663685
- **Show all folders**: Option that adds Desktop as tree root with your user folder, Control Panel, Libraries and Recycle Bin. https://www.elevenforum.com/t/turn-on-or-off-show-all-folders-in-navigation-pane-of-file-explorer-in-windows-11.2535/
- **Show libraries**: Option that adds the Libraries node to the navigation pane. https://www.elevenforum.com/t/turn-on-or-off-show-all-folders-in-navigation-pane-of-file-explorer-in-windows-11.2535/
- **Linux (WSL) node**: With WSL installed, a Linux node in the tree browses each distro's file system. https://www.elevenforum.com/t/add-or-remove-linux-in-navigation-pane-of-file-explorer-in-windows-11.2531
- **Pin to Quick access**: Right-click a folder (or drag it to the Quick access area) to pin it in the navigation pane and Home. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Reorder Quick access pins**: Drag pinned folders up or down in the navigation pane, and the order carries over to Home. https://elevenforum.com/t/rearrange-quick-access-folders-in-navigation-pane-of-file-explorer-in-windows-11.16179/
- **Drop onto tree nodes**: Dragging files onto any folder or drive in the navigation pane moves or copies them there; hovering auto-expands the node. https://en.wikipedia.org/wiki/File_Explorer
- **Start location (Open File Explorer to)**: Choose whether new windows open to Home, This PC or OneDrive. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Win+E**: Opens a new File Explorer window from anywhere. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec

## 2. Panes, tabs, windows, command bar

### Panes
- **Navigation pane toggle**: View > Show > Navigation pane hides or shows the left tree; its width is user-resizable. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Preview pane (Alt+P)**: A right-side pane renders the selected file (images, PDFs, Office docs, text, audio/video) without opening an app. https://en.wikipedia.org/wiki/File_Explorer
- **Pluggable preview handlers**: Apps register preview handlers that render their formats in the Preview pane, and Folder Options can turn handlers off. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Details pane (Alt+Shift+P)**: A right-side pane shows the selected item's thumbnail, sharing status, recent activity, related files/emails and properties. https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/
- **Details pane property layout (2026)**: Properties in the Details pane were regrouped so common fields (size, dates, type) are easier to find. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/
- **Pane toggle button**: A "Details" button at the right end of the command bar opens or closes the right pane in one click. https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/
- **Folder summary in Details pane**: With nothing selected, the pane summarizes the folder; with several items selected it shows the count and combined size. https://en.wikipedia.org/wiki/File_Explorer
- **Status bar**: A bottom strip shows the item count, how many are selected and their total size, plus two buttons that switch between Details and Large icons. https://geekrewind.com/how-to-show-or-hide-status-bar-in-file-explorer-in-windows-11/

### Command bar (toolbar)
- **Core buttons**: New, Cut, Copy, Paste, Rename, Share, Delete, Sort and View sit on the command bar as icon buttons. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **New menu**: Creates Folder, Shortcut, Bitmap image, Text Document, Compressed (zipped) Folder, Library, plus any app-registered types (ShellNew). https://www.elevenforum.com/t/add-or-remove-default-items-on-new-context-menu-in-windows-11.10362/
- **Sort menu**: Picks the sort column, Ascending/Descending, and Group by from one dropdown. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **View menu**: Picks the layout (Extra large icons through Content), Compact view and the Show submenu. https://geekrewind.com/how-to-change-folder-layout-view-in-windows-11-file-explorer/
- **Show submenu**: Toggles Navigation pane, Details pane, Preview pane, Item check boxes, File name extensions and Hidden items. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **See more (…) menu**: Holds Burn to disc, Pin to Quick access, Select all, Select none, Invert selection, Properties and Options. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Context-dependent commands**: The bar changes with location, e.g. This PC offers Map network drive and Add a network location, and New disappears there. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Access keys (KeyTips)**: Pressing Alt shows letter badges on command bar buttons for keyboard-only use. https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/
- **Classic menu bar via Alt**: The "Always show menus" option (or tapping Alt in some views) shows the legacy File/Edit/View/Tools/Help menu bar. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca

### Tabs
- **New tab (+ button, Ctrl+T)**: Opens a tab, by default at Home. https://www.thurrott.com/books/windows-11-field-guide/archived-22h2/312540/file-explorer-24h2
- **Open in new tab**: Right-click a folder, or a navigation pane item, and choose Open in new tab. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Middle-click folder → new tab**: Middle-clicking a folder in the file list or navigation pane opens it in a background tab. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Close tab**: The X on a tab, middle-clicking the tab, Close tab in its menu, or Ctrl+W (the last tab closes the window). https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Close other tabs / Close tabs to the right**: Tab right-click menu commands that close tabs in bulk. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Duplicate tab**: Tab right-click command that opens a second tab at the same folder. https://www.windowslatest.com/2024/04/30/windows-11-kb5037002-tests-a-new-duplicate-tabs-feature-in-file-explorer/
- **Reorder tabs**: Drag a tab sideways to change its position. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Tab switching keys**: Ctrl+Tab and Ctrl+Shift+Tab cycle tabs, and Ctrl+1…9 jumps to tab N. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Tab overflow scroll**: When tabs don't fit, left/right arrows scroll the tab strip. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Drop files on a tab**: Dragging files over a tab switches to it so you can drop into that location; right-drag gives a Copy/Move menu. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Tear out tab**: Dragging a tab out of the strip opens it in its own window. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Merge tab into another window**: Dragging a tab onto another Explorer window's tab strip moves it there. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Independent tab history**: Each tab keeps its own back/forward history and location. https://www.thurrott.com/books/windows-11-field-guide/archived-22h2/312540/file-explorer-24h2
- **Restore tabs at logon**: With "Restore previous folder windows at logon" on, Explorer reopens previous windows and their tabs after restart. https://pureinfotech.com/restore-file-explorer-folders-tabs-after-restart-windows-11/
- **Open external folder links in new tab**: Folders opened from the desktop or other apps open as a new tab in the existing window instead of a new window (toggleable). https://www.elevenforum.com/t/open-desktop-folders-and-external-folder-links-in-new-tab-in-file-explorer-in-windows-11.30886/

### Windows
- **New window (Ctrl+N)**: Opens another Explorer window at the current folder. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Open in new window**: Context-menu command that opens the selected folder in a separate window. https://www.elevenforum.com/t/add-or-remove-open-in-new-window-context-menu-in-windows-11.11971/
- **Open each folder in its own window**: General-tab option where double-clicking a folder spawns a new window instead of navigating. https://www.elevenforum.com/t/open-folder-in-new-or-same-window-in-windows-11.6629/
- **Full screen (F11)**: Toggles a full-screen, chrome-light Explorer window. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Launch folder windows in a separate process**: Runs each Explorer window in its own process so one crash doesn't take down the others. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Window preloading**: "Enable window preloading for faster launch times" keeps Explorer warm in memory so new windows open instantly. https://pureinfotech.com/enable-disable-file-explorer-preloading-windows-11/
- **Per-folder view memory**: Each folder remembers its own view, sort, grouping and column layout. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca

## 3. Views and columns

### Layouts
- **Eight layouts**: Extra large icons, Large icons, Medium icons, Small icons, List, Details, Tiles and Content, picked from View or Ctrl+Shift+1…8. https://geekrewind.com/how-to-change-folder-layout-view-in-windows-11-file-explorer/
- **Compact view**: Toggle that reduces padding between items in every layout. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Ctrl+mouse wheel zoom**: Ctrl+scroll steps continuously through icon sizes and layouts. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Tiles view**: Medium icon plus name, type and size beside it. https://www.elevenforum.com/t/change-folder-layout-view-in-windows-11-file-explorer.1246/
- **Content view**: One row per item showing a thumbnail and several metadata fields (e.g. author, dates, size). https://www.elevenforum.com/t/change-folder-layout-view-in-windows-11-file-explorer.1246/
- **Thumbnails**: Images, videos, PDFs and Office files show content previews as icons; folders show a peek of what's inside. https://en.wikipedia.org/wiki/File_Explorer
- **Always show icons, never thumbnails**: Option that disables content thumbnails for speed or privacy. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **File-type badge on thumbnails**: "Display file icon on thumbnails" overlays the app icon on a thumbnail's corner. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Overlay icons**: Small badges on icons mark shortcuts (arrow), OneDrive sync state, shared items and similar states. https://support.microsoft.com/en-us/office/what-do-the-onedrive-icons-mean-11143026-8000-44f8-aaa9-67c985aa49b3
- **Hidden items appear faded**: With hidden items shown, they render semi-transparent so you can tell them apart. https://www.elevenforum.com/t/turn-on-or-off-hide-empty-drives-in-windows-11.11141/
- **NTFS compressed/encrypted in color**: Compressed files show in blue and EFS-encrypted files in green when enabled. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Hover infotips**: Hovering an item shows a tooltip with type, size, dates or dimensions; folder tips can include folder size and contents. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Selection border (2024)**: Selected items get a thin outline in addition to the highlight fill. https://blogs.windows.com/windows-insider/2024/06/19/announcing-windows-11-insider-preview-build-26241-canary-channel/
- **Readable size units (2026)**: The Size column shows KB, MB or GB as appropriate instead of always KB. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/

### Sorting and grouping
- **Sort by any column**: Sort by Name, Date modified, Type, Size or any property via More, ascending or descending. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Click header to sort**: In Details, clicking a column header sorts by it, and clicking again reverses. https://winaero.com/how-to-sort-in-any-explorer-folder-view-by-turning-on-column-headers-for-sorting-and-filtering-by-property
- **Shift+click secondary sort**: Shift-clicking a second header adds it as a secondary sort key under the first. https://www.sevenforums.com/general-discussion/183892-sort-files-folders-using-multiple-criteria-post1562592.html
- **Folders-first ordering**: Folders are always listed before files in a name sort, regardless of direction. https://www.wps.com/office-quick-solution/others/how-to-sort-files-by-name-and-date-in-windows-file-explorer/
- **Numerical (natural) sorting**: "File2" sorts before "File10"; a policy (NoStrCmpLogical) switches to strict character order. https://www.elevenforum.com/t/enable-or-disable-numerical-sorting-in-file-explorer-in-windows-11.9030/
- **Group by**: Groups items under collapsible headers by Name, Date, Type, Size or any property, or (None). https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Date group buckets**: Date grouping uses Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year and A long time ago. https://learn.microsoft.com/en-us/answers/questions/5853207/windows-file-explorer-group-by-date-modified
- **Name group buckets**: Name grouping uses letter ranges (A–H, I–P, Q–Z), and Type groups by file type. https://learn.microsoft.com/en-us/answers/questions/5853207/windows-file-explorer-group-by-date-modified
- **Collapse/expand groups**: Double-clicking a group header (or its arrow) collapses it; right-clicking a header offers Collapse all groups / Expand all groups. https://elevenforum.com/t/expand-or-collapse-group-in-file-explorer-in-windows-11.6518
- **Click group header to select group**: Single-clicking a group's header selects every item in that group (long-standing behaviour; no doc found, verify on a Windows box). https://elevenforum.com/t/expand-or-collapse-group-in-file-explorer-in-windows-11.6518

### Columns (Details view)
- **Show/hide columns**: Right-click any column header to tick or untick common columns. https://www.elevenforum.com/t/add-or-remove-columns-for-folder-in-windows-11-file-explorer.8058/
- **Choose Details dialog (More…)**: Lists every available property column (~300), with checkboxes, Move up/Move down and a pixel "Width of selected column" field. https://www.thewindowsclub.com/choose-folder-details-to-display-windows
- **Representative columns**: Date created, Date accessed, Authors, Tags, Title, Rating, Dimensions, Length, Bit rate, Date taken, Camera model, Attributes, Owner, Folder path, Computer, Comments, etc. https://www.elevenforum.com/t/add-or-remove-columns-for-folder-in-windows-11-file-explorer.8058/
- **Reorder columns by drag**: Drag a column header left or right to change its position. https://www.elevenforum.com/t/add-or-remove-columns-for-folder-in-windows-11-file-explorer.8058/
- **Resize columns**: Drag a header edge; double-click the divider to auto-fit that column. https://www.elevenforum.com/t/change-size-of-columns-width-for-folder-in-windows-11-file-explorer.1278/
- **Size column to fit / Size all columns to fit**: Header right-click commands that auto-size one or all columns (Ctrl+Plus on keypad = all). https://www.thewindowsclub.com/change-the-column-width-size-of-file-explorer-in-windows
- **Header filter dropdown**: Hovering a header shows a chevron that opens a checklist of that column's values (names A–H, each Type, etc.) to filter the view. https://winaero.com/how-to-sort-in-any-explorer-folder-view-by-turning-on-column-headers-for-sorting-and-filtering-by-property
- **Date filter calendar**: The Date header's filter offers a calendar (click a day, drag or Shift-click a range) plus preset buckets. https://learn.microsoft.com/en-us/answers/questions/5855312/how-do-i-search-o-windows-11-for-files-modified-on
- **Size filter buckets**: The Size filter offers Empty (0 KB), Tiny (0–16 KB), Small (16 KB–1 MB), Medium (1–128 MB), Large (128 MB–1 GB), Huge (1–4 GB) and Gigantic (>4 GB). https://windowscentral.com/software-apps/windows-11/how-to-boost-search-efficiency-on-file-explorer-for-windows-11
- **Filtered-view indicator**: A filtered column shows a tick in its header and the address bar shows the filter as an extra breadcrumb segment. https://winaero.com/how-to-sort-in-any-explorer-folder-view-by-turning-on-column-headers-for-sorting-and-filtering-by-property

### Folder view templates
- **Optimize this folder for**: Properties > Customize sets the folder template (General items, Documents, Pictures, Music, Videos), which picks default columns and layout. https://www.elevenforum.com/t/change-template-of-drive-folder-or-library-in-windows-11-file-explorer.1259/
- **Apply template to subfolders**: "Also apply this template to all subfolders" pushes the template down the tree. https://www.elevenforum.com/t/change-template-of-drive-folder-or-library-in-windows-11-file-explorer.1259/
- **Automatic folder type discovery**: Explorer guesses a folder's template from its contents (e.g. a folder of photos opens as Pictures). https://www.ninjaone.com/blog/manage-folder-and-library-templates-in-file-explorer/
- **Apply to Folders**: Folder Options button that copies the current folder's view to every folder of the same template type. https://geekrewind.com/how-to-apply-folder-view-to-all-folders-of-same-template-type-in-windows-11/
- **Reset Folders**: Folder Options button that resets all folders of that type to default views. https://geekrewind.com/how-to-apply-folder-view-to-all-folders-of-same-template-type-in-windows-11/

## 4. Selection

- **Click / Ctrl+click / Shift+click**: Click selects one item, Ctrl+click toggles items in or out, Shift+click selects a contiguous range from the anchor. https://www.howtogeek.com/839443/how-to-select-multiple-files-on-windows/
- **Ctrl+Shift+click**: Adds a second range to an existing selection without dropping the first. https://www.computerhope.com/issues/ch000771.htm
- **Rubber-band (marquee) selection**: Dragging from empty space draws a selection rectangle, and Ctrl+drag adds to the current selection. https://geekrewind.com/select-multiple-files-with-a-selection-rectangle-in-windows-11/
- **Select all (Ctrl+A)**: Selects every item in the current view, including filtered/search results. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Select none**: See more > Select none clears the selection. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Invert selection**: See more > Invert selection flips the selection to every item not currently selected. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Shift+arrow range select**: Shift with arrow keys, Home, End, PgUp or PgDn extends the selection from the keyboard. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Ctrl+arrow + Space (non-adjacent keyboard select)**: Ctrl+arrows move the focus rectangle without changing the selection, and Ctrl+Space toggles the focused item. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Item check boxes**: View > Show > Item check boxes puts a checkbox on each item (shown on hover or when selected) to multi-select without modifier keys. https://www.elevenforum.com/t/turn-on-or-off-use-check-boxes-to-select-items-in-windows-11.764/
- **Header select-all checkbox**: With check boxes on in Details view, a checkbox in the first column header selects or clears every item. https://www.elevenforum.com/t/select-items-in-file-explorer-in-windows-11.7319/
- **Gallery check boxes**: Gallery thumbnails show check boxes too when Item check boxes is on. https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/
- **Type-to-select (type-ahead)**: Typing a name's first letters jumps to and selects the matching item; repeating a letter cycles matches. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Type into Search box instead (option)**: "When typing into list view" can be switched so typed characters go to the search box instead of selecting. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Single-click mode (point to select)**: General tab option where hovering selects and a single click opens, with underline-on-hover choices. https://www.elevenforum.com/t/open-folder-in-new-or-same-window-in-windows-11.6629/
- **Selection summary**: The status bar and Details pane show the count and combined size of the selection. https://geekrewind.com/how-to-show-or-hide-status-bar-in-file-explorer-in-windows-11/
- **Select a whole group**: Clicking a group header selects all items in that group (see Views > grouping). https://elevenforum.com/t/expand-or-collapse-group-in-file-explorer-in-windows-11.6518
- **Selection survives view/sort changes**: Changing layout, sort or grouping keeps the same items selected and scrolls the focused one into view. https://www.elevenforum.com/t/select-items-in-file-explorer-in-windows-11.7319/

## 5. File operations

### Clipboard
- **Cut / Copy / Paste (Ctrl+X/C/V)**: Cut-and-paste moves files and copy-and-paste copies them, using the system clipboard; also Ctrl+Insert / Shift+Insert. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Cut items dim until pasted**: Cut files render faded in place until pasted, and pressing Esc or copying something else cancels the cut. https://forums.macrumors.com/threads/there-is-no-cut-option-in-finder-app.2407806/
- **Paste into same folder = duplicate**: Pasting a copy into its own folder creates "Name - Copy", then "Name - Copy (2)". https://www.elevenforum.com/t/cut-copy-paste-and-move-in-file-explorer-in-windows-11.10423/
- **Paste shortcut**: Classic background menu command that pastes a shortcut (.lnk) to the copied item instead of the item. https://www.elevenforum.com/t/cut-copy-paste-and-move-in-file-explorer-in-windows-11.10423/
- **Copy as path (Ctrl+Shift+C)**: Copies the selected items' full paths, in quotes, as text. https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/

### Drag and drop
- **Default drag semantics**: Dragging within the same drive moves, and dragging to another drive copies. https://www.dell.com/support/kbdoc/en-us/000147309/move-and-copy-files-using-drag-and-drop-in-microsoft-windows
- **Modifier keys while dragging**: Hold Ctrl to force copy, Shift to force move, Alt (or Ctrl+Shift) to create a shortcut. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Drag tooltip**: The drag cursor shows a "+ Copy to X", "→ Move to X" or "Create link in X" label so you know what will happen. https://binaryfork.com/better-file-explorer-drag-and-drop-13603/
- **Right-button drag menu**: Dropping with the right mouse button shows Copy here, Move here, Create shortcuts here and Cancel (plus app items such as Extract here). https://answers.microsoft.com/en-us/windows/forum/all/ways-to-drag-files-or-folders/b83a8ee6-a9d6-4e8e-8e9b-778dc6d90b8b
- **Spring-loaded targets**: Hovering a drag over a navigation-pane node, tab or taskbar button expands or brings it forward so you can drop inside. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Drop onto an app or exe**: Dropping files onto a program's icon opens them with that program. https://www.dell.com/support/kbdoc/en-us/000147309/move-and-copy-files-using-drag-and-drop-in-microsoft-windows
- **Esc cancels a drag**: Pressing Esc mid-drag aborts the operation. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec

### Create and rename
- **New folder (Ctrl+Shift+N)**: Creates "New folder" and drops straight into rename mode. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **New file from template**: New > Text Document / Bitmap image / app types creates an empty file from the ShellNew template, already in rename mode. https://www.elevenforum.com/t/add-or-remove-default-items-on-new-context-menu-in-windows-11.10362/
- **Rename in place (F2)**: Inline edit box with only the base name selected, so the extension stays untouched. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Tab / Shift+Tab during rename**: Commits the name and moves to rename the next (or previous) item in view order. https://www.winhelponline.com/blog/quickly-rename-multiple-files-consecutively-using-tab-key/
- **Batch rename**: Select several files, press F2, type one name, and they become "Name (1)", "Name (2)", …, keeping each extension. https://digitalcitizen.life/how-quickly-rename-multiple-files-using-windows-shortcuts-features
- **Extension change warning**: Changing an extension prompts "If you change a file name extension, the file might become unusable." with Yes/No. https://www.windowsdigitals.com/how-to-change-or-remove-file-extension-in-windows-11
- **Invalid character tooltip**: Typing \ / : * ? " < > | in a name shows a balloon listing forbidden characters and blocks them. https://www.elevenforum.com/t/rename-file-in-windows-11.21024
- **Case-only renames apply instantly (2026)**: Changing only letter case now shows immediately, and background sync no longer interrupts renaming. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/

### Delete and Recycle Bin
- **Delete to Recycle Bin (Delete, Ctrl+D)**: Moves items to the Recycle Bin, from which they can be restored. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Permanent delete (Shift+Delete)**: Deletes without using the Recycle Bin, after a confirmation. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Delete confirmation option**: Recycle Bin Properties > "Display delete confirmation dialog" adds an "Are you sure?" prompt (off by default). https://windowscentral.com/how-change-recycle-bin-storage-settings-windows-11
- **Per-drive Recycle Bin size**: Each drive gets its own Custom size (MB) cap or "Don't move files to the Recycle Bin". https://www.elevenforum.com/t/change-maximum-size-for-recycle-bin-in-windows-11.5109/
- **Too-big-for-bin warning**: Items larger than the bin's cap trigger a "permanently delete?" prompt. https://windowscentral.com/how-change-recycle-bin-storage-settings-windows-11
- **Recycle Bin view**: Shows Original Location and Date Deleted columns, with Restore the selected items, Restore all items and Empty Recycle Bin commands. https://www.technipages.com/windows-11-how-to-manage-the-recycling-bin
- **Restore to original location**: Restoring puts the item back at its original path, recreating missing parent folders. https://www.technipages.com/windows-11-how-to-manage-the-recycling-bin

### Undo
- **Undo / Redo (Ctrl+Z / Ctrl+Y)**: Reverses or redoes copy, move, rename, delete and new-folder operations; repeated Ctrl+Z walks back through recent operations. https://www.elevenforum.com/t/undo-and-redo-in-file-explorer-in-windows-11.20133
- **Undo in context menu**: The background right-click menu (classic) shows "Undo Rename", "Undo Move", etc., naming the action to be undone. https://geekrewind.com/how-to-use-undo-and-redo-in-windows-11-file-explorer/

### Copy engine and dialogs
- **One consolidated progress dialog**: All running copy/move/delete jobs stack in a single window instead of separate popups. https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Pause / resume / stop per job**: Each job has its own pause and cancel buttons; a paused job's graph turns yellow. https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **More details / Fewer details**: Toggles between a compact progress bar and a detailed view (remembered). https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Throughput graph**: The detailed view plots live transfer speed, with current speed, current file name, time remaining and items/bytes remaining. https://www.pcworld.com/article/451532/how-to-use-windows-8s-cool-new-file-copy-feature.html
- **Open source/destination from dialog**: Links in the dialog open the source or destination folder while the copy runs. https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Taskbar progress**: The Explorer taskbar button fills with green (red on error, yellow when paused) to show progress. https://en.wikipedia.org/wiki/File_Explorer
- **Deferred conflicts**: Non-conflicting files copy first and conflicts are queued until the end of the job. https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Dark-mode file dialogs (2025)**: Copy, move, delete and confirmation dialogs follow dark mode, and the progress bar turns blue in dark theme. https://windowsreport.com/windows-11-kb5065797-refines-file-explorer-dark-mode-fixes-taskbar-bugs/

### Conflicts and errors
- **Replace or Skip Files dialog**: On a name clash: Replace the file(s) in the destination, Skip these files, or Compare info for both files (Let me decide). https://www.elevenforum.com/t/replace-skip-or-keep-both-files-in-file-name-conflict-dialog-in-windows-11.26608/
- **Do this for the next N conflicts**: A checkbox applies the same choice to every remaining conflict. https://www.elevenforum.com/t/replace-skip-or-keep-both-files-in-file-name-conflict-dialog-in-windows-11.26608/
- **Compare/choose dialog**: Two columns (source vs destination) with thumbnails, size and date per file; tick either side, tick both to keep both (adds a number). https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Skip identical files**: The compare dialog offers a checkbox to skip files with the same date and size. https://www.elevenforum.com/t/replace-skip-or-keep-both-files-in-file-name-conflict-dialog-in-windows-11.26608/
- **Hover/open in conflict dialog**: Hovering a thumbnail shows its path and double-clicking opens the file to check it. https://learn.microsoft.com/en-us/archive/blogs/b8/improving-our-file-management-basics-copy-move-rename-and-delete
- **Silent folder merge**: Copying a folder onto a same-named folder merges contents; "Hide folder merge conflicts" off makes Explorer ask first. https://www.pcworld.com/article/1962876/windows-may-soon-have-fewer-folder-options-in-file-explorer.html
- **File In Use dialog**: If a file is locked it names the app holding it and offers Try Again / Skip / Cancel. https://en.wikipedia.org/wiki/File_Explorer
- **Destination Path Too Long dialog**: Explorer refuses paths over ~260 characters and offers Skip / Try again. https://learn.microsoft.com/en-us/answers/questions/3943637/how-to-extend-file-path-characters-maximum-limit-m
- **Elevation prompt for protected folders**: Writing to system locations shows "You'll need to provide administrator permission" with a Continue (UAC) button. https://en.wikipedia.org/wiki/File_Explorer

### Archives
- **ZIP as a folder**: ZIP files open like folders, and you can browse, drag files out or drop files in. https://en.wikipedia.org/wiki/File_Explorer
- **Extract All wizard**: Extracts an archive to a chosen folder, with "Show extracted files when complete". https://pureinfotech.com/window-11-extract-rar-7zip-archival-formats/
- **Native RAR/7z/TAR reading**: Via libarchive, Explorer opens and extracts .rar, .7z, .tar, .tar.gz, .tgz, .tar.bz2, .tar.zst, .tar.xz and more. https://pureinfotech.com/window-11-extract-rar-7zip-archival-formats/
- **Compress to ZIP / 7z / TAR**: Context-menu "Compress to" creates a ZIP, 7z or TAR archive from the selection. https://pureinfotech.com/windows-11-create-7-zip-tar-archive-files/
- **Create archive wizard (Additional options)**: Lets you pick the archive format, compression method and level, and what metadata is stored. https://www.neowin.net/news/kb5037867-microsoft-making-windows-11-native-archive-even-better-with-build-226353640/

## 6. Context menu and Properties

### Modern (Windows 11) context menu
- **Icon action row**: Cut, Copy, Paste, Rename, Share and Delete sit as icons at the top (or bottom) of the menu, with names on hover. https://support.microsoft.com/en-us/windows/finding-items-in-the-file-explorer-context-menu-2c458eb5-d27a-4b69-9301-60df221caaa0
- **Open / Open with**: Open uses the default app; Open with lists other apps plus "Choose another app" with an "Always" checkbox and a Microsoft Store link. https://pureinfotech.com/enable-open-with-windows-11/
- **Open in new tab / new window**: Folder menu items that open the folder without leaving the current view. https://pureinfotech.com/use-tabs-file-explorer-windows-11/
- **Open in Terminal**: Opens Windows Terminal at the selected folder (or the current folder from the background menu). https://winaero.com/windows-11-open-extended-context-menu-in-file-explorer/
- **Pin to Quick access / Unpin**: Adds or removes the folder from Quick access. https://support.microsoft.com/en-us/windows/finding-items-in-the-file-explorer-context-menu-2c458eb5-d27a-4b69-9301-60df221caaa0
- **Add to Favorites**: Pins a file to the Favorites section of Home. https://www.thurrott.com/?p=305401
- **Pin to Start**: Pins a folder, app or drive to the Start menu. https://www.elevenforum.com/t/enable-or-disable-show-more-options-context-menu-in-windows-11.1589/
- **Compress to…**: Submenu creating ZIP, 7z or TAR archives, or opening the Additional options wizard. https://pureinfotech.com/windows-11-create-7-zip-tar-archive-files/
- **Copy as path**: Copies the quoted full path (also Ctrl+Shift+C). https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/
- **Image commands**: For pictures, Set as desktop background, Rotate right, Rotate left and Edit (Photos/Paint) appear. https://betanews.com/article/microsoft-releases-windows-11-insider-preview-build-26220-7271-with-new-context-menu-xbox-full-screen-experience-for-pc-and-more
- **Manage file flyout (2025)**: Groups Compress to ZIP, Copy as path, Set as desktop background and Rotate into one submenu to declutter. https://betanews.com/article/microsoft-releases-windows-11-insider-preview-build-26220-7271-with-new-context-menu-xbox-full-screen-experience-for-pc-and-more
- **AI actions submenu**: For images, Visual search with Bing, Blur background, Erase objects and Remove background; for M365 docs, Summarize. Can be turned off. https://betanews.com/article/microsoft-adds-new-ai-actions-entry-to-the-windows-11-context-menu
- **Cloud provider submenu**: OneDrive (and other sync clients) add Share, View online, Version history, Always keep on this device and Free up space. https://support.microsoft.com/en-us/office/what-do-the-onedrive-icons-mean-11143026-8000-44f8-aaa9-67c985aa49b3
- **Properties (Alt+Enter)**: Opens the Properties dialog; Alt+double-click does the same. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Show more options**: Opens the full legacy (Windows 10-style) menu, which keeps every shell extension. https://support.microsoft.com/en-us/windows/finding-items-in-the-file-explorer-context-menu-2c458eb5-d27a-4b69-9301-60df221caaa0
- **Shift+right-click / Shift+F10**: Opens the legacy menu directly, skipping the modern one. https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Menu key**: The keyboard Menu (Application) key opens the context menu for the selection. https://www.elevenforum.com/t/enable-or-disable-show-more-options-context-menu-in-windows-11.1589/
- **Customize menu (2026)**: A "Customize menu" link opens Settings > Personalization > Context Menu to toggle built-ins (Send to, Create shortcut, Print), choose which app extensions show inline or in an "App extensions" submenu, show text labels instead of icons, and move Properties to the bottom. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/

### Legacy menu (Show more options)
- **Extended verbs with Shift**: Shift-opening the legacy menu reveals hidden items such as Open command window here / Open Linux shell here and Open in new process. https://winaero.com/windows-11-open-extended-context-menu-in-file-explorer/
- **Send to**: Bluetooth device, Compressed (zipped) folder, Desktop (create shortcut), Documents, Mail recipient, plus removable and mapped drives; editable via shell:sendto. https://tweaktown.com/guides/11464/the-send-to-menu-is-the-right-click-feature-on-windows-11-that-nobody-bothers-to-customize/index.html
- **Create shortcut**: Creates a .lnk next to the item (or offers to put it on the Desktop when the folder is read-only). https://www.elevenforum.com/t/add-or-remove-items-in-send-to-context-menu-in-windows-11.4984/
- **Restore previous versions**: Opens the Previous Versions tab for the file or folder. https://www.elevenforum.com/t/add-or-remove-previous-versions-from-context-menu-and-properties-in-windows-11.9391/
- **Give access to / Share with**: Shares a folder on the network with specific people or removes access. https://en.wikipedia.org/wiki/File_Explorer
- **Include in library**: Adds the folder to a library or creates a new library from it. https://en.wikipedia.org/wiki/File_Explorer
- **Print**: Sends documents to the default printer through their app's print verb. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/
- **Scan with Microsoft Defender**: Runs an on-demand antivirus scan of the selection. https://www.howtogeek.com/759559/how-to-find-missing-right-click-context-menu-options-on-windows-11/
- **Third-party shell extensions**: 7-Zip, WinRAR, Git, editors and others add their own items, mostly in the legacy menu. https://www.howtogeek.com/759559/how-to-find-missing-right-click-context-menu-options-on-windows-11/

### Background (empty-space) menu
- **View / Sort by / Group by / Refresh**: Layout, sorting, grouping and refresh from the empty-area right-click. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **New ▸**: Folder, Shortcut and registered file types created in place. https://www.elevenforum.com/t/add-or-remove-default-items-on-new-context-menu-in-windows-11.10362/
- **Paste / Paste shortcut / Undo**: Paste the clipboard, paste a shortcut to it, or undo the last named operation. https://geekrewind.com/how-to-use-undo-and-redo-in-windows-11-file-explorer/
- **Customize this folder**: Opens the folder's Properties at the Customize tab. https://www.elevenforum.com/t/add-or-remove-customize-this-folder-on-context-menu-and-properties-in-windows-11.9395

### Properties dialog
- **General tab (files)**: Type, Opens with + Change, Location, Size, Size on disk, Created/Modified/Accessed dates and Read-only/Hidden attributes. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **General tab (folders)**: Adds "Contains: N Files, M Folders", counted live as it scans, and the total size. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Advanced Attributes**: Archive, Allow indexing of contents, Compress contents to save disk space, Encrypt contents (EFS) and Details. https://geekrewind.com/how-to-encrypt-files-in-windows-11-a-simple-guide/
- **Unblock (Mark of the Web)**: "This file came from another computer and might be blocked…" with an Unblock checkbox on downloaded files. https://geekrewind.com/unblock-downloaded-files-in-windows-11-file-properties/
- **Security tab**: Shows the NTFS permissions per user/group, with Edit, and Advanced for owner, inheritance, auditing and effective access. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Details tab (metadata)**: Lists and edits properties such as Title, Subject, Rating, Tags, Comments, Authors and EXIF/ID3 fields. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Remove Properties and Personal Information**: A Details-tab link that strips metadata in place or makes a cleaned copy. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Previous Versions tab**: Lists older copies from File History or restore points with Open, Copy and Restore. https://ninjaone.com/blog/add-or-remove-previous-versions-in-windows
- **Sharing tab (folders)**: Share… (people picker), Advanced Sharing (share name, permissions, caching) and the password-protected sharing link. https://en.wikipedia.org/wiki/File_Explorer
- **Customize tab (folders)**: Template (Optimize for), Folder pictures (Choose File / Restore Default) and Change Icon. https://www.elevenforum.com/t/change-template-of-drive-folder-or-library-in-windows-11-file-explorer.1259/
- **Shortcut tab (.lnk)**: Target, Start in, Shortcut key, Run (Normal/Minimized/Maximized), Comment, Open File Location, Change Icon and Advanced > Run as administrator. https://mundobytes.com/en/properties-of-a-shortcut-in-Windows
- **Compatibility tab (.exe)**: Compatibility mode, reduced color, 640x480, high-DPI override, run as administrator and the compatibility troubleshooter. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Digital Signatures tab**: Shows Authenticode signer and timestamp for signed binaries. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Location tab (known folders)**: Moves Documents, Downloads, Pictures, etc. to another drive with Move / Restore Default. https://www.elevenforum.com/t/list-of-windows-11-shell-commands-for-shell-folder-shortcuts.1080/
- **Multi-selection Properties**: Selecting several items shows combined size and count, and lets you set attributes or common metadata for all at once. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **WinUI Properties dialog (2026 preview)**: A redesigned Properties window with dark mode and modern controls is in testing. https://windowslatest.com/2026/07/22/first-look-windows-11-is-replacing-windows-95-era-properties-dialog-now-with-dark-mode-and-winui

## 7. Search (brief; covered in depth by a separate agent)

- **Folder-scoped search box**: Searches the current folder and all its subfolders as you type (Ctrl+E / Ctrl+F / F3). https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- **Indexed vs non-indexed search**: Indexed locations return instantly via Windows Search; other folders are crawled live, with a progress bar in the address bar. https://en.wikipedia.org/wiki/File_Explorer
- **Search options menu**: While searching, the command bar offers Current folder / All subfolders, Date modified, Kind, Size, File contents, System files and Zipped (compressed) files. https://www.elevenforum.com/t/search-in-windows-11-file-explorer.21789/
- **Advanced Query Syntax**: Typed filters such as kind:, ext:, name:, datemodified:, size:>5MB, author:, tag:, plus AND/OR/NOT, quotes and wildcards. https://www.wps.com/office-quick-solution/others/how-to-use-advanced-search-syntax-in-windows-11-file-explorer/
- **Size keywords**: size:empty / tiny / small / medium / large / huge / gigantic map to the same buckets as the Size filter. https://windowscentral.com/software-apps/windows-11/how-to-boost-search-efficiency-on-file-explorer-for-windows-11
- **Results view with location**: Results show each hit's folder path, and "Open file location" jumps to its folder. https://en.wikipedia.org/wiki/File_Explorer
- **Saved searches**: A search can be saved as a .search-ms virtual folder that reruns live. https://en.wikipedia.org/wiki/File_Explorer
- **Search suggestions / recent searches**: The box drops down previous queries and property suggestions as you type. https://en.wikipedia.org/wiki/File_Explorer
- **Cloud results from Home**: Searching from Home also returns OneDrive / Microsoft 365 files when signed in. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Hit highlighting**: Matching text in names is highlighted in results. https://en.wikipedia.org/wiki/File_Explorer

## 8. Keyboard and mouse shortcuts (every Explorer shortcut found)

Source key: **[KB]** = Microsoft Support "Keyboard shortcuts in Windows", File Explorer + dialog + general tables, https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec

| # | Keys | Action | Source |
|---|---|---|---|
| 1 | Win+E | Open a new File Explorer window | [KB] |
| 2 | Alt+D | Select the address bar | [KB] |
| 3 | Ctrl+L | Focus the address bar | [KB] |
| 4 | F4 | Focus address bar to edit path (in dialogs: open the active dropdown list) | [KB] |
| 5 | Ctrl+E | Focus the search box | [KB] |
| 6 | Ctrl+F | Focus the search box | [KB] |
| 7 | F3 | Search for a file or folder | [KB] |
| 8 | Ctrl+N | Open a new window | [KB] |
| 9 | Ctrl+W | Close active tab (or window if last tab) | [KB] |
| 10 | Ctrl+T | Open a new tab | [KB] |
| 11 | Ctrl+Tab | Next tab | [KB] |
| 12 | Ctrl+Shift+Tab | Previous tab | [KB] |
| 13 | Ctrl+1 … Ctrl+9 | Jump to tab N | [KB] |
| 14 | Alt+Left / Backspace | Back | [KB] |
| 15 | Alt+Right | Forward | [KB] |
| 16 | Alt+Up | Up one level | [KB] |
| 17 | F5 / Ctrl+R | Refresh | [KB] |
| 18 | F6 | Cycle focus: address bar, nav pane, file list, etc. | [KB] |
| 19 | Tab / Shift+Tab | Move focus between controls / panes | [KB] |
| 20 | F11 | Full screen / restore | [KB] |
| 21 | Alt+P | Toggle Preview pane | [KB] |
| 22 | Alt+Shift+P | Toggle Details pane | [KB] |
| 23 | Alt+Enter | Properties of selection | [KB] |
| 24 | Alt+double-click | Properties of the clicked item | https://www.elevenforum.com/t/enable-or-disable-show-more-options-context-menu-in-windows-11.1589/ |
| 25 | F2 | Rename | [KB] |
| 26 | Tab / Shift+Tab (while renaming) | Commit and rename next / previous item | https://www.winhelponline.com/blog/quickly-rename-multiple-files-consecutively-using-tab-key/ |
| 27 | Esc | Cancel rename, drag, or current task; clears a pending cut | [KB] |
| 28 | Enter | Open selection (folders navigate, files launch) | [KB] |
| 29 | Ctrl+Shift+N | New folder | [KB] |
| 30 | Ctrl+A | Select all | [KB] |
| 31 | Shift+Arrow / Shift+Home / Shift+End | Extend selection | [KB] |
| 32 | Ctrl+Arrow, then Space | Move focus without selecting; toggle focused item (non-adjacent select) | [KB] |
| 33 | Home / End | First / last item (scroll to top/bottom) | [KB] |
| 34 | Right arrow (tree) | Expand node or go to first subfolder | [KB] |
| 35 | Left arrow (tree) | Collapse node or go to parent | [KB] |
| 36 | NumLock + * | Expand all subfolders under selected tree node | [KB] (Windows 10 table) |
| 37 | NumLock + + | Expand selected tree node | [KB] (Windows 10 table) |
| 38 | NumLock + − | Collapse selected tree node | [KB] (Windows 10 table) |
| 39 | Ctrl+Shift+E | Expand nav pane to current folder | [KB] |
| 40 | Ctrl+C / Ctrl+Insert | Copy | [KB] |
| 41 | Ctrl+X | Cut | [KB] |
| 42 | Ctrl+V / Shift+Insert | Paste | [KB] |
| 43 | Ctrl+Shift+C | Copy as path | https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/ |
| 44 | Delete / Ctrl+D | Move to Recycle Bin | [KB] |
| 45 | Shift+Delete | Delete permanently | [KB] |
| 46 | Ctrl+Z | Undo | [KB] |
| 47 | Ctrl+Y | Redo | [KB] |
| 48 | Ctrl+Shift+1 | Extra large icons | https://winaero.com/how-to-switch-between-views-in-file-explorer-with-keyboard-shortcuts |
| 49 | Ctrl+Shift+2 | Large icons | same |
| 50 | Ctrl+Shift+3 | Medium icons | same |
| 51 | Ctrl+Shift+4 | Small icons | same |
| 52 | Ctrl+Shift+5 | List | same |
| 53 | Ctrl+Shift+6 | Details | same |
| 54 | Ctrl+Shift+7 | Tiles | same |
| 55 | Ctrl+Shift+8 | Content | same |
| 56 | Ctrl+mouse wheel | Zoom icon size / step through layouts | [KB] |
| 57 | Ctrl+Plus (numpad) | Auto-size all columns in Details | [KB] |
| 58 | Shift+F10 | Context menu (legacy / full) | [KB] |
| 59 | Shift+right-click | Open "Show more options" (extended) menu directly | [KB] |
| 60 | Menu (Application) key | Context menu for selection | https://www.elevenforum.com/t/enable-or-disable-show-more-options-context-menu-in-windows-11.1589/ |
| 61 | Alt / F10 | Show access keys (KeyTips) on the command bar | https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/ |
| 62 | Ctrl+drag | Force copy | [KB] |
| 63 | Shift+drag | Force move | [KB] |
| 64 | Alt+drag | Create shortcut | [KB] |
| 65 | Right-drag | Drop menu: Copy here / Move here / Create shortcuts here / Cancel | https://answers.microsoft.com/en-us/windows/forum/all/ways-to-drag-files-or-folders/b83a8ee6-a9d6-4e8e-8e9b-778dc6d90b8b |
| 66 | Middle-click folder | Open in new tab | https://pureinfotech.com/use-tabs-file-explorer-windows-11/ |
| 67 | Middle-click tab | Close tab | https://pureinfotech.com/use-tabs-file-explorer-windows-11/ |
| 68 | Mouse Back/Forward buttons | Back / Forward | https://www.elevenforum.com/t/dropdown-arrow-in-file-explorer-history-navigation-missing.31624 |
| 69 | Type letters in file list | Type-ahead select (or type into search, per option) | https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca |
| 70 | Alt+Space | Window system menu | [KB] |
| 71 | Alt+F4 | Close the window | [KB] |
| 72 | Spacebar (dialogs) | Toggle focused check box | [KB] |
| 73 | Backspace (Open/Save dialogs) | Up one folder | [KB] |
| 74 | Alt+underlined letter (dialogs) | Activate that option | [KB] |
| 75 | Ctrl+Tab / Ctrl+Shift+Tab (Properties) | Switch dialog tabs | [KB] |
| 76 | Win+V | Clipboard history (text/images; not file lists) | [KB] |

## 9. Folder Options (File Explorer Options), every setting

Opened from See more (…) > Options, or Control Panel > File Explorer Options. Microsoft's Group Policy Preferences spec lists the registry value behind each View-tab item: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca

### General tab
- **Open File Explorer to**: Dropdown with Home, This PC or OneDrive (account name). https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Browse folders**: Open each folder in the same window / Open each folder in its own window. https://www.elevenforum.com/t/open-folder-in-new-or-same-window-in-windows-11.6629/
- **Open desktop folders and external folder links in new tab**: Sub-option of "same window" that sends outside folder opens to a new tab. https://www.elevenforum.com/t/open-desktop-folders-and-external-folder-links-in-new-tab-in-file-explorer-in-windows-11.30886/
- **Click items as follows**: Single-click to open an item (point to select), with "Underline icon titles consistent with my browser" or "only when I point at them"; or Double-click to open an item (single-click to select). https://www.elevenforum.com/t/open-folder-in-new-or-same-window-in-windows-11.6629/
- **Privacy: Show recently used files**: Shows Recent files in Home/Quick access. https://www.webnots.com/4-ways-to-disable-recent-files-in-file-explorer-on-windows-11/
- **Privacy: Show frequently used folders**: Adds auto-frequent folders to Quick access. https://www.webnots.com/4-ways-to-disable-recent-files-in-file-explorer-on-windows-11/
- **Privacy: Include account-based insights, recent, favorite, and recommended files**: Pulls OneDrive/M365 cloud files into Home (formerly "Show files from Office.com"). https://geekrewind.com/how-to-enable-or-disable-the-recommended-section-in-file-explorer-on-windows-11/
- **Privacy: Show recommended section**: Shows the Recommended carousel on Home (depends on the box above). https://geekrewind.com/how-to-enable-or-disable-the-recommended-section-in-file-explorer-on-windows-11/
- **Clear File Explorer history**: The Clear button wipes recent files, frequent folders and address bar history. https://www.webnots.com/4-ways-to-disable-recent-files-in-file-explorer-on-windows-11/
- **Restore Defaults (General)**: Resets this tab. https://geekrewind.com/open-file-folder-options-in-windows-11/

### View tab: Folder views
- **Apply to Folders**: Apply the current folder's view to all folders of this template type. https://geekrewind.com/how-to-apply-folder-view-to-all-folders-of-same-template-type-in-windows-11/
- **Reset Folders**: Reset all folders of this type to default view. https://geekrewind.com/how-to-apply-folder-view-to-all-folders-of-same-template-type-in-windows-11/

### View tab: Advanced settings (Files and Folders)
- **Always show icons, never thumbnails** (IconsOnly). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Always show menus** (classic menu bar). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Decrease space between items (compact view)**: Same as View > Compact view. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Display file icon on thumbnails** (ShowTypeOverlay). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Display file size information in folder tips** (FolderContentsInfoTip). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Display the full path in the title bar** (CabinetState\FullPath). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Enable window preloading for faster launch times** (2025+). https://pureinfotech.com/enable-disable-file-explorer-preloading-windows-11/
- **Hidden files and folders**: radio, Don't show hidden files, folders, or drives / Show hidden files, folders, and drives (Hidden). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Hide empty drives**: Hides card readers or drives with no media in This PC. https://www.elevenforum.com/t/turn-on-or-off-hide-empty-drives-in-windows-11.11141/
- **Hide extensions for known file types** (HideFileExt; on by default). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Hide folder merge conflicts**: Off makes Explorer ask before merging same-named folders. https://www.pcworld.com/article/1962876/windows-may-soon-have-fewer-folder-options-in-file-explorer.html
- **Hide protected operating system files (Recommended)** (ShowSuperHidden). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Launch folder windows in a separate process** (SeparateProcess). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Restore previous folder windows at logon** (PersistBrowsers; now restores tabs). https://pureinfotech.com/restore-file-explorer-folders-tabs-after-restart-windows-11/
- **Show drive letters** (ShowDriveLettersFirst; off hides "C:" labels). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Show encrypted or compressed NTFS files in color** (ShowCompColor). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Show pop-up description for folder and desktop items** (ShowInfoTip). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Show preview handlers in preview pane** (ShowPreviewHandlers). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Show status bar**: Toggles the bottom status bar. https://geekrewind.com/how-to-show-or-hide-status-bar-in-file-explorer-in-windows-11/
- **Show sync provider notifications**: OneDrive/cloud-provider promo banners in Explorer. https://www.ninjaone.com/blog/show-sync-provider-notification-in-file-explorer/
- **Use check boxes to select items** (UseCheckBoxes). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Use Sharing Wizard (Recommended)** (SharingWizardOn; off gives the advanced share dialog). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **When typing into list view**: radio, Automatically type into the Search Box / Select the typed item in the view (TypeAhead). https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca

### View tab: Advanced settings (Navigation pane)
- **Always show availability status**: Always show OneDrive cloud-state icons in the nav pane, not only on hover. https://www.elevenforum.com/t/enable-or-disable-show-onedrive-status-on-navigation-pane-in-windows-11.10952/
- **Expand to open folder**: Keep the tree expanded to the current folder. https://learn.microsoft.com/en-us/answers/a/7663685
- **Show all folders** (FriendlyTree inverse / NavPaneShowAllFolders): Desktop-rooted full tree. https://www.elevenforum.com/t/turn-on-or-off-show-all-folders-in-navigation-pane-of-file-explorer-in-windows-11.2535/
- **Show libraries**: Libraries node in the tree. https://www.elevenforum.com/t/turn-on-or-off-show-all-folders-in-navigation-pane-of-file-explorer-in-windows-11.2535/
- **Show Network / Show This PC** (some builds; also via nav-pane right-click): Toggle those nodes. https://www.elevenforum.com/t/folder-options-missing-show-network-show-this-pc-in-windows-11.39219/
- **Restore Defaults (View)**: Resets every Advanced setting. https://geekrewind.com/open-file-folder-options-in-windows-11/

### Search tab
- **How to search: Don't use the index when searching in file folders for system files (searches might take longer)**. https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/
- **When searching non-indexed locations: Include system directories**. https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/
- **When searching non-indexed locations: Include compressed files (ZIP, CAB…)**. https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/
- **When searching non-indexed locations: Always search file names and contents (this might take several minutes)**. https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/
- **Restore Defaults (Search)**. https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/

### Settings app mirror (Settings > System > Advanced > File Explorer)
- **Show file extensions / Show hidden and system files / Show full path in title bar / Show empty drives / Show option to run as a different user in Start**: Toggles that mirror the Folder Options items. https://windowsloop.com/how-to-change-advanced-file-explorer-settings-in-windows-11/

### History note
- **Build 23481 removal and 23486 rollback (June 2023)**: Microsoft removed nine of these (Hide folder merge conflicts, Always show icons never thumbnails, Display file icon on thumbnails, Display file size in folder tips, Hide protected OS files, Show drive letters, Show pop-up description, Show encrypted/compressed in color, Use sharing wizard), then restored them after feedback; a clone should keep all. https://www.pcworld.com/article/1962876/windows-may-soon-have-fewer-folder-options-in-file-explorer.html

## 10. Drives, network, devices

### This PC and drives
- **This PC view**: Lists "Devices and drives" and "Network locations", plus (optionally) user folders. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Drive usage bars**: Each drive tile shows a capacity bar and "X GB free of Y GB", turning red when nearly full. https://en.wikipedia.org/wiki/File_Explorer
- **Drive letters and labels**: Drives show "Label (C:)"; F2 renames the volume label, and the option can hide letters or put them first. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **Hide empty drives**: Card readers and optical drives without media are hidden (shown faded when hidden items are on). https://www.elevenforum.com/t/turn-on-or-off-hide-empty-drives-in-windows-11.11141/
- **Eject**: Removable drives, mounted images and discs get Eject in the context menu and command bar. https://www.simplified.guide/microsoft-windows/burn-iso-image
- **Format…**: Drive context menu opens Format (file system, allocation unit size, volume label, Quick Format). https://en.wikipedia.org/wiki/File_Explorer
- **BitLocker integration**: Turn on / Manage BitLocker in the drive menu, with locked drives shown with a padlock and unlocked by double-click. https://en.wikipedia.org/wiki/File_Explorer
- **Drive Properties > General**: Used/free pie chart, Disk Cleanup button, "Compress this drive", "Allow files to be indexed". https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Drive Properties > Tools**: Error checking (Check) and Optimize/defragment. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Drive Properties > Hardware / Sharing / Security / Quota / ReadyBoost / Previous Versions**: Per-drive tabs, depending on drive type. https://fileinfo.com/tutorials/view_file_properties_windows_11
- **Mount ISO / VHD / VHDX**: Opening or choosing Mount on a disk image attaches it as a new drive letter; Eject detaches it. https://www.simplified.guide/microsoft-windows/burn-iso-image
- **Burn disc image**: An ISO's menu opens Windows Disc Image Burner to write it to CD/DVD/Blu-ray. https://digitalcitizen.life/burn-iso-file-windows
- **Burn to disc**: Copying to a blank disc asks "Like a USB flash drive" (Live File System) or "With a CD/DVD player" (staged, then Finish burning). https://helpdeskgeek.com/windows-11/how-to-burn-cds-dvds-and-blu-ray-discs-in-windows-11-10/
- **Portable devices (MTP)**: Phones and cameras over USB appear under This PC and can be browsed, with "Import pictures and videos". https://en.wikipedia.org/wiki/File_Explorer
- **AutoPlay**: Plugging in a drive or card triggers the AutoPlay prompt (Open folder to view files, Take no action, Import…), configurable per media type. https://www.digitalcitizen.life/autoplay-settings-windows-11/

### Network
- **Network node**: Lists computers, NAS and media devices discovered on the LAN. https://support.microsoft.com/help/4092694
- **Network discovery banner**: "Network discovery is turned off…" bar with one-click "Turn on network discovery and file sharing". https://support.microsoft.com/help/4092694
- **UNC paths in address bar**: Typing \\server or \\server\share browses SMB shares directly. https://support.microsoft.com/help/4092694
- **Credential prompt**: Protected shares prompt for username/password with "Remember my credentials". https://www.elevenforum.com/t/map-network-drive-in-windows-11.4796
- **Map network drive**: Wizard assigns a drive letter to \\server\share with "Reconnect at sign-in" and "Connect using different credentials". https://pureinfotech.com/map-network-drive-windows-11
- **Disconnect network drive**: Removes a mapped drive (This PC See more menu or the drive's menu). https://pureinfotech.com/map-network-drive-windows-11
- **Add a network location**: Wizard that adds a WebDAV, FTP or share shortcut under This PC's Network locations. https://www.itechguides.com/get-help-with-file-explorer-in-windows-11/0/
- **Share a folder on the network**: Folder Properties > Sharing, or Give access to, publishes an SMB share. https://support.microsoft.com/help/4092694
- **Offline files**: "Always available offline" keeps network files cached locally via Sync Center. https://en.wikipedia.org/wiki/File_Explorer

### Other locations
- **Libraries**: Virtual folders (Documents, Music, Pictures, Videos, Camera Roll, Saved Pictures) aggregating several real folders. https://www.elevenforum.com/t/change-default-save-locations-for-libraries-in-windows-11.5974/
- **Library management**: Library Properties lets you Add/Remove included folders, Set save location, Set public save location, Optimize library for, Show in navigation pane and Restore Defaults. https://pureinfotech.com/show-manage-libraries-file-explorer-windows/
- **Create new library**: Libraries > New > Library, or "Include in library > Create new library". https://www.elevenforum.com/t/create-new-library-in-windows-11.5980/
- **WSL distros**: Linux node, or \\wsl.localhost\<distro>, browses Linux file systems. https://www.elevenforum.com/t/add-or-remove-linux-in-navigation-pane-of-file-explorer-in-windows-11.2531
- **Android phone over Wi-Fi**: Via Phone Link, the paired phone appears in the navigation pane for browsing, copy, move, rename and delete. https://www.windowscentral.com/software-apps/windows-11/how-to-browse-your-android-storage-without-cables-from-windows-11
- **Recycle Bin node**: Can be shown in the tree or pinned to Quick access. https://pureinfotech.com/features-must-configure-file-explorer-windows-11/
- **Control Panel and virtual folders**: Control Panel, Network Connections and Printers are browsable shell namespaces in the same window. https://en.wikipedia.org/wiki/File_Explorer

## 11. Integration (Home, Recommended, Gallery, OneDrive, cloud, sharing)

### Home
- **Home page**: Default landing page with Quick access, Favorites, Recent and Shared sections instead of a file-system folder. https://www.thurrott.com/?p=305401
- **Quick access group**: Shows pinned and frequently used folders as tiles at the top of Home (Restore known folders if you unpin them). https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Recent tab**: Lists about 25 recently opened files (local and cloud) with location and activity date. https://www.thurrott.com/?p=305401
- **Favorites tab**: Files you starred with "Add to Favorites"; "Remove from Favorites" unpins. https://www.thurrott.com/?p=305401
- **Shared tab**: Files shared with your Microsoft account (OneDrive, email, Teams). https://www.thurrott.com/?p=305401
- **Recommended carousel**: A thumbnail carousel of suggested files (first for work/school accounts, later personal accounts) with a toggle to hide it. https://windowslatest.com/2025/01/31/windows-11s-file-explorer-is-getting-recommended-feed-with-microsoft-account-integration
- **Hover actions on Home files**: Hovering a file card shows "Open file location" and "Ask Copilot" buttons plus a more-actions button. https://windowsreport.com/windows-11-file-explorer-to-get-new-hover-buttons/
- **Collapsible Home sections, remembered (2026)**: Each Home section can be collapsed and Explorer remembers the state. https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/
- **Cloud search from Home**: The search box on Home covers local and signed-in cloud files. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1

### Gallery
- **Gallery node**: A photo-wall view of images and videos from chosen folders, newest first, with the Details pane showing the selected photo's info. https://www.windowslatest.com/2023/04/09/hands-on-windows-11s-new-file-explorer-biggest-update-since-windows-8/amp/
- **Timeline scrollbar**: A date timeline on the right lets you scrub quickly back through months and years. https://techradar.com/news/microsoft-has-big-changes-in-the-works-for-windows-11-and-one-just-arrived
- **Collection > Manage collection**: Add or remove the folders Gallery pulls from (defaults to Pictures). https://pureinfotech.com/add-remove-folders-gallery-file-explorer-windows-11/
- **Collection source filter**: The Collection dropdown narrows Gallery to one source folder (e.g. only OneDrive Camera Roll or iCloud Photos). https://www.elevenforum.com/t/add-or-remove-folder-locations-for-file-explorer-gallery-in-windows-11.18521/
- **OneDrive camera roll and Add phone photos**: Backed-up phone photos appear automatically, and an "Add phone photos" button sets up phone backup. https://www.windowscentral.com/software-apps/windows-11/microsoft-is-making-it-easier-to-browse-through-and-share-your-photos-on-windows-11
- **Gallery in file pickers**: Gallery appears in Open/Save dialogs for quick photo attachment. https://www.thurrott.com/windows/windows-11/281923/windows-11-insider-preview-build-23435-adds-file-explorer-gallery
- **Gallery selection and checkboxes**: Multi-select photos (checkboxes supported) and act on them with the normal commands. https://blogs.windows.com/windows-insider/2023/05/04/announcing-windows-11-insider-preview-build-23451/

### OneDrive and cloud providers
- **OneDrive in the navigation pane**: Each signed-in OneDrive account (Personal / work) gets its own root node. https://support.microsoft.com/en-us/windows/file-explorer-in-windows-ef370130-1cca-9dc5-e0df-2f7416fe1cb1
- **Files On-Demand status icons**: Blue cloud = online-only, green-outline check = locally available, solid green check = always kept, arrows = syncing, red X = error, people = shared, padlock = blocked/Personal Vault. https://support.microsoft.com/en-us/office/what-do-the-onedrive-icons-mean-11143026-8000-44f8-aaa9-67c985aa49b3
- **Status column**: Details view shows a Status column with the same cloud-state icon. https://www.elevenforum.com/t/set-onedrive-files-on-demand-status-states-in-windows-11.4374/
- **Always keep on this device / Free up space**: Pin a file or folder locally, or dehydrate it back to cloud-only. https://www.elevenforum.com/t/set-onedrive-files-on-demand-status-states-in-windows-11.4374/
- **Open on demand**: Opening an online-only file downloads it transparently with a progress toast. https://www.minitool.com/news/onedrive-files-on-demand-for-windows.html
- **View online / Version history / Manage access**: OneDrive submenu items that open the web view, restore old versions or edit permissions. https://geekrewind.com/how-to-share-your-files-with-onedrive-in-windows-11/
- **OneDrive storage flyout**: The header cloud button shows quota used and sync state, with links to OneDrive web and settings. https://pureinfotech.com/file-explorer-new-header-ui-home-gallery-changes-windows-11/
- **Known folder backup**: Desktop, Documents and Pictures can live inside OneDrive yet still show as the normal known folders. https://www.elevenforum.com/t/list-of-windows-11-shell-commands-for-shell-folder-shortcuts.1080/
- **Third-party cloud providers**: Dropbox, Google Drive, iCloud and others plug in through the Cloud Files API and get the same nav-pane node and status icons. https://www.elevenforum.com/t/enable-or-disable-show-onedrive-status-on-navigation-pane-in-windows-11.10952/
- **Sync provider notifications**: Cloud providers can show banners in Explorer (toggle in Folder Options). https://www.ninjaone.com/blog/show-sync-provider-notification-in-file-explorer/

### Sharing and other integrations
- **Share sheet**: Share opens a Windows share sheet with Nearby sharing (PCs/Bluetooth), email/contacts, apps and a Copy button. https://support.microsoft.com/en-us/help/4027674
- **OneDrive link sharing**: For OneDrive items, Share opens the OneDrive dialog (who can access, Copy link). https://support.microsoft.com/en-us/help/4027674
- **Nearby sharing**: Send files wirelessly to nearby Windows PCs over Wi-Fi/Bluetooth from the share sheet. https://www.thurrott.com/books/windows-11-field-guide/312466/nearby-sharing-24h2
- **Git / source control info**: With Dev Home's integration enabled for a repo folder, Explorer shows branch, status and last commit message (columns and Details pane). https://www.neowin.net/news/microsofts-dev-home-018-preview-is-out-with-file-explorer-source-control-integration/
- **Microsoft 365 / Copilot actions**: Summarize documents, ask Copilot about a file, and AI image actions from the menu or Home. https://www.windowslatest.com/2025/11/21/windows-11-tests-microsoft-365-copilot-button-in-file-explorer-and-universal-writing-assistant
- **Windows Terminal integration**: Open in Terminal on folders and backgrounds. https://winaero.com/windows-11-open-extended-context-menu-in-file-explorer/
- **Phone Link**: Android phone storage appears as a nav-pane location (see Drives). https://www.windowscentral.com/software-apps/windows-11/how-to-browse-your-android-storage-without-cables-from-windows-11

## 12. Obscure power-user tricks

- **GodMode folder**: Naming a folder `GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}` turns it into a virtual folder listing ~200 Control Panel tasks. https://pureinfotech.com/enable-god-mode-windows/
- **CLSID virtual folders anywhere**: `shell:::{GUID}` in the address bar or a shortcut opens hidden shell namespaces (This PC, Recycle Bin, All Tasks, Network Connections). https://winaero.com/windows-11-shell-commands-the-complete-list
- **Classic Explorer window via Control Panel**: Control Panel > System and Security > Windows Tools (or the Up arrow from Control Panel) opens a legacy-chrome Explorer window that still browses drives. https://www.notebookcheck.net/Newly-discovered-Windows-11-trick-brings-back-classic-Windows-10-File-Manager-without-any-registry-hacks.843917.0.html
- **Classic context menu by default**: An empty `InprocServer32` under CLSID `{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}` (HKCU) makes the full legacy menu the default. https://pureinfotech.com/bring-back-classic-context-menu-windows-11/
- **Copy To folder / Move To folder**: Registering shell handlers `{C2FBB630-…}` and `{C2FBB631-…}` adds folder-picker Copy/Move commands to the context menu. https://www.elevenforum.com/t/add-or-remove-copy-to-folder-and-move-to-folder-context-menu-in-windows-11.1339/
- **Hidden Send to entries**: Holding Shift while right-clicking expands Send to with every folder in your user profile. https://www.howtogeek.com/1398/stupid-geek-tricks-secret-items-on-the-windows-7-send-to-menu/
- **Custom Send to targets**: Any shortcut (app, folder, script) dropped into `shell:sendto` becomes a Send to destination. https://www.makeuseof.com/windows-11-add-new-shortcuts-to-send-to-menu/
- **Custom New-menu file types**: Adding a `ShellNew` key (with an optional template file) to any extension puts it in the New menu. https://www.elevenforum.com/t/add-or-remove-default-items-on-new-context-menu-in-windows-11.10362/
- **Hide or show Home, Gallery, Linux, Network, This PC**: Registry `System.IsPinnedToNameSpaceTree` values (or added Folder Options checkboxes) remove or restore nav-pane nodes. https://www.elevenforum.com/t/add-or-remove-home-in-navigation-pane-of-file-explorer-in-windows-11.2449
- **Move Gallery to top or bottom of nav pane**: A SortOrderIndex registry tweak repositions the Gallery node. https://www.elevenforum.com/t/move-gallery-to-top-or-bottom-of-navigation-pane-in-windows-11.18632/
- **Downloads defaults to Group by date**: Downloads ships grouped by Date modified; Group by > (None) plus Apply to Folders fixes it everywhere. https://windowsloop.com/fix-group-by-date-view-in-downloads-folder
- **Explorer taskbar jump list**: Right-clicking the File Explorer taskbar icon lists pinned Quick access folders and frequent locations for one-click opening. https://www.windowsdigitals.com/?p=14362
- **Pin a folder to the taskbar itself**: A shortcut with target `explorer "C:\path"` can be pinned to the taskbar as its own button. https://www.windowsdigitals.com/?p=14362
- **New Explorer window from the taskbar**: Shift+click or middle-click the taskbar icon opens another window instead of switching. https://www.intowindows.com/?p=535823
- **Restart Explorer to release locks/glitches**: Task Manager > Windows Explorer > Restart drops all Explorer handles and reloads the shell. https://thegeekpage.com/stop-the-file-in-use-error-on-a-file-you-already-closed/
- **Open/Save dialogs are mini-Explorers**: Common file dialogs carry the address bar, search, nav pane (incl. Gallery), view switching, rename, delete and context menus. https://www.thurrott.com/windows/windows-11/281923/windows-11-insider-preview-build-23435-adds-file-explorer-gallery
- **Open in new process (extended menu)**: Shift-right-click a folder > Open in new process isolates that window from the main Explorer process. https://winaero.com/windows-11-open-extended-context-menu-in-file-explorer/
- **Hidden-feature flags (ViVeTool)**: Power users switch on staged-rollout Explorer features (tabs-on-open, preloading, etc.) with ViVeTool feature IDs. https://www.elevenforum.com/t/open-desktop-folders-and-external-folder-links-in-new-tab-in-file-explorer-in-windows-11.30886/
- **Pin Recycle Bin / drives to Quick access**: Right-click the Recycle Bin or a drive > Pin to Quick access to put them in the nav pane. https://pureinfotech.com/features-must-configure-file-explorer-windows-11/
- **Super-hidden files**: Unticking "Hide protected operating system files" reveals desktop.ini, thumbs.db, $Recycle.Bin and similar. https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/a6ca3a17-1971-4b22-bf3b-e1a5d5c50fca
- **desktop.ini folder customization**: A folder's hidden desktop.ini stores its custom icon, localized name and info tip (what the Customize tab writes). https://www.elevenforum.com/t/change-template-of-drive-folder-or-library-in-windows-11-file-explorer.1259/

### Microsoft PowerToys add-ons Windows power users treat as part of Explorer
- **Peek**: Ctrl+Space quick-look preview of the selected file (Quick Look-style). https://learn.microsoft.com/en-us/windows/powertoys/peek
- **PowerRename**: Regex batch rename from the context menu with live preview. https://learn.microsoft.com/en-us/windows/powertoys/powerrename
- **File Locksmith**: "Unlock with File Locksmith" shows and kills the processes locking a file. https://learn.microsoft.com/en-us/windows/powertoys/file-locksmith
- **Image Resizer**: Bulk-resize images from the context menu. https://learn.microsoft.com/en-us/windows/powertoys/image-resizer
- **File Explorer add-ons**: Preview-pane and thumbnail handlers for SVG, Markdown, source code, PDF, STL, G-code, QOI. https://learn.microsoft.com/en-us/windows/powertoys/file-explorer
- **New+**: Custom file and folder templates in the New menu. https://learn.microsoft.com/en-us/windows/powertoys/newplus

## 13. Top 25 features power users name most

Ranked by how often they come up in Windows-to-Mac switcher complaints, Hacker News threads, Apple/MacRumors forums, and the feature lists of Finder replacements built for switchers (FileNav, Command X). Items marked *(guide)* are backed by a how-to rather than a complaint thread.

1. **Cut and paste files (Ctrl+X → Ctrl+V)**, the #1 complaint. https://www.nextofwindows.com/top-8-basic-windows-feature-missing-in-mac-and-some-workarounds · https://news.ycombinator.com/item?id=16742284 · https://forums.macrumors.com/threads/there-is-no-cut-option-in-finder-app.2407806/ · https://apps.apple.com/us/app/command-x/id6448461551
2. **Enter opens, F2 renames**: Finder's Return-renames behaviour trips switchers up. https://discussions.apple.com/thread/3140356?page=2 · https://alternativeto.net/software/filenav/about
3. **Editable address bar**: type or paste a path, see the real path. https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/ · https://alternativeto.net/software/filenav/about
4. **Always-visible folder tree (navigation pane)**. https://www.makeuseof.com/windows-file-explorer-vs-macos-finder/ · https://news.ycombinator.com/item?id=16742284 · https://news.ycombinator.com/item?id=4118378
5. **Folder merge on copy**: Explorer merges same-named folders, while Finder's "Replace" wipes the target. https://forums.macrumors.com/threads/behavior-of-finder-when-replacing-folder-it-deletes-the-old-instead-of-merging.985153 · https://lowendmac.com/misc/05/1031.html
6. **Right-click > New > Text Document (and other file types)**. https://discussions.apple.com/thread/2547680 · https://talk.macpowerusers.com/t/native-mac-way-to-create-text-files-via-finder-menu/36474
7. **Full path visible + Copy as path (Ctrl+Shift+C)**. https://news.ycombinator.com/item?id=49589722 · https://www.elevenforum.com/t/copy-path-of-drive-file-or-folder-in-windows-11.3581/
8. **Keyboard-first navigation**: Backspace/Alt+Left back, Alt+Up parent, type-ahead select, "almost vi-like". https://news.ycombinator.com/item?id=49589722 · https://news.ycombinator.com/item?id=16742284
9. **Home / End jump to first / last item**. https://discussions.apple.com/thread/652989 · https://gist.github.com/wizioo/2871238f1e9bd4f21286
10. **Delete key sends to Recycle Bin; Shift+Delete is permanent**. https://www.nextofwindows.com/top-8-basic-windows-feature-missing-in-mac-and-some-workarounds
11. **Detailed copy dialog**: speed graph, pause/resume, per-job progress, items/bytes remaining. https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/
12. **This PC overview**: every drive with a letter and a usage bar. https://www.makeuseof.com/windows-file-explorer-vs-macos-finder/
13. **Open a terminal here**: `cmd` in the address bar, Open in Terminal, Shift+right-click "Open command window here". https://asad.substack.com/p/windows-explorer-better-than-finder · https://binaryfork.com/file-explorer-run-commands-13621/
14. **Two locations side by side**: two trees in one window, or two snapped windows (dual-pane workflow). https://news.ycombinator.com/item?id=16742284 · https://alternativeto.net/software/filenav/about
15. **Right-click any tree node to act on it** (e.g. create a folder there) without navigating into it. https://news.ycombinator.com/item?id=16742284
16. **Doesn't hide the file system**: one-click Hidden items and File name extensions toggles, system files visible. https://news.ycombinator.com/item?id=49589722 · https://www.makeuseof.com/windows-file-explorer-vs-macos-finder/
17. **UNC / IP paths in the address bar and Map network drive** (\\192.168.1.10\share). https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/
18. **Details view with folders-first sorting** and sortable, resizable, reorderable columns. https://news.ycombinator.com/item?id=49589722
19. **Icon size steps and Ctrl+mouse-wheel zoom**. https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/
20. **Shift+right-click extended menu and the shell-extension ecosystem** (7-Zip, Git, editors). https://asad.substack.com/p/windows-explorer-better-than-finder · https://www.howtogeek.com/759559/how-to-find-missing-right-click-context-menu-options-on-windows-11/
21. **Breadcrumb segments you can click, drop onto and drop down**: Finder's path bar is "just a visual path". https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/ · https://blogs.windows.com/windows-insider/2024/06/19/announcing-windows-11-insider-preview-build-26241-canary-channel/
22. **Column header filters** (date calendar, size buckets); users protested when the date picker went missing. https://techcommunity.microsoft.com/discussions/windows11/user-dissatisfaction-with-date-filtering-functionality-in-windows-11-file-explor/4274528
23. **Right-drag drop menu** (Copy here / Move here / Create shortcuts here) *(guide)*. https://answers.microsoft.com/en-us/windows/forum/all/ways-to-drag-files-or-folders/b83a8ee6-a9d6-4e8e-8e9b-778dc6d90b8b
24. **F2 batch rename and Tab-to-next-file rename** *(guide)*. https://www.winhelponline.com/blog/quickly-rename-multiple-files-consecutively-using-tab-key/
25. **Global hotkeys (Win+E, Ctrl+Shift+N, Alt+Enter)**: "OS hotkey navigation is much better on Windows". https://news.ycombinator.com/item?id=16742284

Counter-evidence worth keeping in mind for the clone: switchers also praise Finder's Quick Look, column view and spring-loaded folders, and wish Explorer had them. https://news.ycombinator.com/item?id=49589722 · https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/

