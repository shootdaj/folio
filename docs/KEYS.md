# Folio keys

Every Folio shortcut, from Explorer's key to what you press on this Mac. Explorer's keys come from
docs/research/explorer-inventory.md (section 8); the key map in docs/plan/MILESTONES.md says how they
reach Folio.

How the columns relate, on Anshul's Mac:

- Karabiner swaps Command and Option, so his physical **Cmd** arrives as **Option** (Explorer's Alt sits
  there) and his physical **Option** arrives as **Cmd**.
- Karabiner turns **Fn+letter** into **Cmd+letter** (Explorer's Ctrl+letter), and **Fn+Tab** into
  **Ctrl+Tab**, **Fn+Delete** into **Option+Delete**.
- BetterTouchTool turns his **Cmd+D** (Option+D) into **Cmd+L** everywhere, and runs Folio on his Win+E key
  (Cmd+Shift+E, docs/btt/Folio.bttpreset). Its Finder-only rules (Option+arrows, Return) never fire in
  Folio, which binds those keys itself.
- F1 to F12 arrive as plain F-keys (fnState is 1).

"Menu" names the menu item that shows the key; "window" means Folio's window binds it (macOS lets a menu
item show only one key, or the key would take keys away from text fields).

## Opening Folio

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Win+E | Opens Folio (a window on Home when none is open) | Cmd+Shift+E | his Win+E key | BTT, global |
| `explorer <path>` | Opens a folder from the shell | | `ff <path>` | Terminal |
| `explorer /select,<file>` | Opens the folder with the item selected | | `ff --reveal <path>` | Terminal |
| | New window, new tab, search from the shell | | `ff -n`, `ff -t`, `ff --search "q" [path]` | Terminal |

## Navigation

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Alt+Left, Backspace | Back | Option+Left, Delete (Cmd+[ too) | Cmd+Left, Backspace | Go > Back |
| Alt+Right | Forward | Option+Right (Cmd+] too) | Cmd+Right | Go > Forward |
| Alt+Up | Up one folder | Option+Up (Cmd+Up too) | Cmd+Up | Go > Up |
| Alt+D, Ctrl+L | Edit the address, with typeahead | Cmd+L, Option+D | Cmd+D (BTT sends Cmd+L), Fn+L | Go > Edit Address |
| F4 | Address history dropdown | F4 | F4 | Go > Address History |
| F5, Ctrl+R | Refresh | F5, Cmd+R, Ctrl+R | F5, Fn+R | Go > Refresh |
| Mouse 4, 5 | Back, Forward | buttons 4 and 5 | buttons 4 and 5 | window |
| | Home | Cmd+Shift+H | Fn+Shift+H | Go > Home |
| | Suggestions | Cmd+Shift+S | Fn+Shift+S | Go > Suggestions |

## Search

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Ctrl+F | Search box | Cmd+F | Fn+F | Edit > Search |
| Ctrl+E | Search box | Cmd+E | Fn+E | window |
| F3 | Search box | F3 | F3 | window |
| Esc in the box | Back to the folder | Esc | Esc | search box |

## Tabs and windows

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Ctrl+T | New tab | Cmd+T | Fn+T | File > New Tab |
| Ctrl+W | Close tab (the window with its last tab) | Cmd+W | Fn+W | File > Close Tab |
| Ctrl+N | New window | Cmd+N | Fn+N | File > New Window |
| Alt+F4 | Close the window | Option+F4 (Cmd+Shift+W too) | Cmd+F4 | File > Close Window |
| Ctrl+Tab | Next tab | Ctrl+Tab | Fn+Tab | Window > Show Next Tab |
| Ctrl+Shift+Tab | Previous tab | Ctrl+Shift+Tab | Fn+Shift+Tab | Window > Show Previous Tab |
| Ctrl+1 to Ctrl+9 | Tab 1 to 9 | Cmd+1 to Cmd+9 | Fn+1 to Fn+9 | window |
| | Reopen closed tab | Cmd+Shift+T | Fn+Shift+T | File > Reopen Closed Tab |
| Middle-click a folder | Open it in a background tab | middle button | middle button | list, tree, crumbs |
| Middle-click a tab | Close it | middle button | middle button | tab strip |
| F11 | Full screen | Ctrl+Cmd+F (F11 when macOS leaves it to apps) | Control+Fn+F, F11 | View > Full Screen |
| F6, Tab, Shift+Tab | Address bar, tree, list in turn | F6, Tab | F6, Tab | window |

## Views and panes

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Ctrl+Shift+1 to 8 | Extra large, large, medium, small icons, List, Details, Tiles, Content | Ctrl+Shift+1 to 8 | Control+Shift+1 to 8 | View |
| Ctrl+wheel | Bigger or smaller icons, through the layouts | Cmd+scroll, pinch | Option+scroll, pinch | list |
| Ctrl+Numpad + | Size all columns to fit | Cmd+=, Cmd+Numpad + | Fn+= | View > Size All Columns to Fit |
| | Larger or smaller text and icons in Details | Cmd++ (Cmd+Shift+=), Cmd+- | Fn+Shift+=, Fn+- | View > Details Size |
| Alt+P | Preview pane | Option+P | Cmd+P | View > Show > Preview Pane |
| Alt+Shift+P | Details pane | Option+Shift+P | Cmd+Shift+P | View > Show > Details Pane |
| | Hidden items | Cmd+Shift+. | Fn+Shift+. | View > Show > Hidden Items |
| Alt, F10 | Access keys on the command bar | Option tapped alone | Cmd tapped alone | window |
| | Folder Options | Cmd+Option+, | Cmd+Option+, | View > Options... |
| | Settings: Folder Options, with the search box ready | Cmd+, | Option+, | Folio > Settings... |
| | Search settings (in Folder Options) | Cmd+F | Fn+F | window |

## The navigation pane

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Right, Left | Open or go in; close or go up | Right, Left | Right, Left | tree |
| NumLock + * | Open everything below | Numpad *, Option+click the arrow | Numpad * | tree |
| Ctrl+Shift+E | Open the tree down to this folder | Ctrl+Shift+E | Control+Shift+E | View > Navigation Pane > Expand to Current Folder |

## Folders open in place (Details view)

Explorer has no such keys; these are the Finder's list view keys. Cmd+Left and Cmd+Right stay Back and Forward.

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| (none) | Open the selected folders in place | Right | Right | list, View > Expand Selected Folders |
| (none) | Close the selected folders; on an item inside one, select its folder | Left | Left | list |
| (none) | Open or close one folder | a click on its triangle | a click | list |
| (none) | Open or close it and every folder below (8 levels, 2,000 folders) | Option+click the triangle | Cmd+click | list |
| (none) | Close every folder | | | View > Collapse All Folders |

## Selecting

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Ctrl+A | Select all | Cmd+A | Fn+A | Edit > Select All |
| Shift+arrows, Shift+Home, Shift+End | Extend the selection | the same | the same | list |
| Ctrl+arrows, Ctrl+Space | Move the focus only; toggle the focused item | Ctrl+arrows, Ctrl+Space | Control+arrows, Control+Space | list |
| Home, End | First, last item | Home, End | Fn+Left, Fn+Right | list |
| Typing | Jump to the name | letters | letters | list |

## Files

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| Enter | Open (never renames) | Return | Return | list |
| Alt+Enter, Alt+double-click | Properties | Option+Return, Option+double-click (Cmd+I too) | Cmd+Return, Cmd+double-click | File > Properties |
| Space | Quick Look | Space | Space | list (File > Quick Look) |
| F2 | Rename (the name, not the extension) | F2 | F2 | Edit > Rename |
| Tab, Shift+Tab while renaming | Rename the next or previous item | Tab | Tab | rename field |
| Esc | Cancel a rename or a cut | Esc | Esc | window |
| Ctrl+X, Ctrl+C, Ctrl+V | Cut (moves on paste), copy, paste | Cmd+X, Cmd+C, Cmd+V | Fn+X, Fn+C, Fn+V | Edit |
| Ctrl+Insert, Shift+Insert | Copy, paste (PC keyboard) | Ctrl+Insert, Shift+Insert | | window |
| Ctrl+Shift+C | Copy as path (quoted, one per line) | Cmd+Shift+C | Fn+Shift+C | Edit > Copy as Path |
| | Copy path without quotes | Cmd+Option+Shift+C | Cmd+Option+Shift+C | Edit > Copy Path |
| Ctrl+Shift+N | New folder | Cmd+Shift+N | Fn+Shift+N | Edit > New > Folder |
| Delete, Ctrl+D | Move to the Trash | Forward Delete, Option+Delete, Cmd+Delete, Cmd+D | Fn+Delete, Fn+D | Edit > Move to Trash (shows Cmd+Delete) |
| Shift+Delete | Delete permanently, after asking | Shift+Forward Delete, Cmd+Option+Delete | Fn+Shift+Delete | Edit > Delete Permanently... |
| Ctrl+Z | Undo | Cmd+Z | Fn+Z | Edit > Undo |
| Ctrl+Y | Redo | Cmd+Y (Cmd+Shift+Z too) | Fn+Y | Edit > Redo |
| Shift+F10, Menu key | The item menu | Shift+F10, Menu | Shift+F10 | window |
| Ctrl+drag, Shift+drag, Alt+drag | Copy, move, make a shortcut | Option-drag, Cmd-drag, Cmd+Option-drag | Cmd-drag, Option-drag, Cmd+Option-drag | drag |
| Right-drag | Copy here, Move here, Create shortcuts here | right-drag | right-drag | drag |
| | Create alias | Ctrl+Cmd+A | Control+Fn+A | Edit > Create Alias |

## Drives and the rest

| Explorer | Folio does | macOS sees | Anshul presses | Where |
|---|---|---|---|---|
| | Connect to server | Cmd+K | Fn+K | File > Connect to Server... |
| | Eject the drive this folder is on | Cmd+Shift+E | Fn+Shift+E (taken by BTT's Folio trigger while it runs; use the sidebar's eject button) | File > Eject |
| | Hide Folio, quit | Cmd+H, Cmd+Q | Fn+H, Fn+Q | Folio menu |

Cmd+Shift+3, 4 and 5 are macOS's screenshot keys and Cmd+Tab is the app switcher; Folio leaves them alone.
