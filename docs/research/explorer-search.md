# Windows 11 File Explorer search box: behaviour spec for a macOS clone

Purpose: describe exactly how the Explorer search box (top right) behaves, so a developer who has never used it can clone it on macOS, backed by the Spotlight index where possible.

Compiled 2026-11-05. Sources: Microsoft Learn, Microsoft Support, Windows Insider blog, Wikipedia, power-user guides. Every claim carries a source URL. "Unverified" marks things only one secondary source says, or that come from general knowledge with no page found.

Status legend: sections marked 🔄 in progress are not finished yet.

## Sections

1. Placement, placeholder, focus shortcuts ✅
2. Scope (current folder + subfolders, navigation, Search again in) ✅
3. Typing, Enter, debounce, suggestions dropdown, history ✅
4. Results view (title, Folder column, Open file location, highlights, sort/group) ✅
5. Search options menu (Date modified, Kind, Size, Other properties, Advanced options, scope) ✅
6. Advanced Query Syntax (AQS) ✅
7. Indexed vs non-indexed locations, Classic vs Enhanced, what the index covers ✅
8. Save search (.search-ms) ✅
9. Search Windows vs Search this folder; Windows 10 differences ✅
10. macOS mapping: Spotlight / NSMetadataQuery / mdfind ✅
11. AQS to Spotlight mapping table ✅

---

## 1. Placement, placeholder, focus shortcuts

### 1.1 Where the box sits

- The search box is at the right end of the address-bar row, top right of every Explorer window/tab, to the right of the breadcrumb address bar. ("click the search box in the top right corner of your screen", https://nerdschalk.com/how-to-search-in-windows-11-everything-you-need-to-know/)
- Its left edge can be dragged to make it wider (the address bar shrinks). Introduced with the 1909 search box. (https://blogs.windows.com/windows-insider/2019/05/08/announcing-windows-10-insider-preview-build-18894/)
- It has a magnifier icon. Once text is typed, an X (clear) appears in the box. (Common UI knowledge; unverified with a source page.)
- Since Windows 10 1903, "The search box in File Explorer now opens as soon as you click in the box" (a single click gives it focus). (https://en.wikipedia.org/wiki/Windows_Search)

### 1.2 Placeholder text

- Placeholder is **"Search <current location display name>"**: "if you select This PC in the navigation pane, the Search box will read Search This PC." (https://www.thurrott.com/?p=337651). So: "Search Downloads", "Search Documents", "Search Home", "Search Local Disk (C:)", "Search Gallery". It uses the location's display name (localised known-folder name, drive label), not the raw path. Each tab has its own box and text.
- On Copilot+ PCs (KB5070311, 1 Dec 2025, builds 26100.7309 / 26200.7309), "The File Explorer Search Box placeholder text has been updated to highlight the enhanced Windows Search experiences" (semantic, describe-what-you-want search). Microsoft did not publish the new string. A clone should use "Search <name>". (https://support.microsoft.com/kb/5070311)
- When a search is active, the address bar shows **"Search Results in <folder>"** as the last breadcrumb, and the tab title/window title becomes "<query> - Search Results in <folder>" (the tab-title format is from general knowledge; unverified). (address-bar text: UC Davis IT guide, https://it.environment.ucdavis.edu/file-explorer , via search summary; the page blocks fetching)

### 1.3 Focus shortcuts

From Microsoft's official shortcut list (https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec):

| Keys | Windows 11 table text |
|---|---|
| Ctrl+E | "Select the search box." |
| Ctrl+F | "Select the search box." |
| F3 | "Search for a file or folder." (focuses the same box) |
| Alt+D / Ctrl+L / F4 | address bar (not search), listed so a clone does not bind them to search |
| Win+S / Win+Q | "Open search" = the taskbar/Start Windows Search, not the Explorer box |

Behaviour on focus:

- Focusing the box selects any existing text in it, so typing replaces the query (unverified; matches standard Win32 edit-box focus behaviour).
- Windows 10 1909 through early Windows 11: focusing the empty box (click or Ctrl+E) immediately opens a **history dropdown** of past searches: "as soon as you click the search box in File Explorer (or press CTRL+E to set focus to it), you'll see the dropdown list with your search history." (https://blogs.windows.com/windows-insider/2019/05/08/announcing-windows-10-insider-preview-build-18894/). Current Windows 11 builds reportedly dropped this dropdown when live results arrived (section 3.3).
- Esc while in the box: first press closes the dropdown; with an empty dropdown it clears the text / cancels the search and returns to the folder (from general use; unverified). Backspace to empty also returns to the folder listing (unverified).
- Folder Options > View > "When typing into list view": "Automatically type into the Search Box" vs "Select the typed item in the view" (default). With the first option, typing letters in the file list sends them to the search box. (Folder Options setting name; from general knowledge, unverified with a source page.)


---

## 2. Scope

### 2.1 Default: current folder plus all subfolders

- A search covers the folder shown in the window and everything below it. "By default, searches will be conducted in the folder you have selected & in all its sub-folders." (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t)
- Search options lets you switch scope: **All subfolders** (default) or **Current folder** (that folder only, no recursion). (Windows 8+ ribbon / Windows 11 menu; https://www.oreilly.com/library/view/windows-8-bible/9781118240748/xhtml/sec193.html via search summary; Windows Central quoted in search results: "change the scope to only search the current folder or subfolders")
- Searching never looks above the current folder. To search wider, navigate up first (or pick This PC).
- Libraries: searching a library searches all of its member folders together. (Windows 7 design; https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t)

### 2.2 Scope depends on where you start (Windows 11)

Microsoft's own guidance (https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/find-your-files-and-apps-in-windows):

| Start location | What gets searched | Speed |
|---|---|---|
| **Home** | the Windows index plus recent/cloud Microsoft 365 / OneDrive files ("To quickly find relevant files from your PC and the cloud, search from Home") | fast |
| a folder (e.g. Downloads) | that folder and its subfolders ("To find files stored inside a folder, search from a folder like Downloads") | fast if indexed, crawl if not |
| **This PC** | every drive ("To do a slow but in-depth search, search from This PC instead of Home") | slow; crawls non-indexed areas |
| a drive (C:) | the whole drive | mixed |

- Insider change, 11 Sep 2026, Experimental build 26340.9482: "Search from This PC in File Explorer is now indexer-based, making it much faster and consistent with search from File Explorer Home." (https://blogs.windows.com/windows-insider/2026/09/11/announcing-new-builds-for-11-september-2026/). Not yet in retail.
- Microsoft says more File Explorer speed/relevance work is coming: "The improvements we are making to performance and relevance for file searching are coming next to File Explorer" (Marcus Ash, quoted at https://www.windowslatest.com/2026/07/19/windows-11s-slowest-feature-is-about-to-get-dramatic-speed-improvements-and-its-file-explorer-search/). Taskbar Windows Search gained substring matching and 2-character queries in June 2026; Explorer had not yet (same article).
- Home search also covers Microsoft 365 cloud files "for users who are signed with their Microsoft account", searchable by location, extension and activity. (https://blogs.windows.com/windows-insider/2022/09/29/announcing-windows-11-insider-preview-build-22621-730-and-22623-730/)

### 2.3 What happens when you navigate

- A search result set is itself a location in the tab's history (a `search-ms:` URI with `crumb=location:<folder>`; see section 8). (https://learn.microsoft.com/en-us/windows/win32/search/getting-started-with-parameter-value-arguments)
- Opening a folder from the results navigates into it and leaves search mode; the box resets to the new folder's placeholder ("Search <new folder>"). Back returns to the results with the query restored in the box. (Behaviour from general use; unverified with a source page.)
- Clicking another folder in the navigation pane or breadcrumb also leaves search mode. The query is not carried over: a new search starts only when you type again, scoped to the new folder. (unverified, general use)
- **Close search** (X on the command bar / ribbon, or clearing the box) returns to the plain folder listing. (Windows 10 ribbon Options group; https://www.techrepublic.com/article/how-to-use-search-tool-windows-10-file-explorer/ via search summary)

### 2.4 "Search again in"

- Windows 7: after a search, the bottom of the result list offers "Search again in:" **Libraries**, **Computer**, **Custom...** (pick folders) and **Internet** (runs the query in the default browser/search engine). Homegroup and File Contents entries are from memory of Windows 7, unverified. ("Click Libraries to search across every library. Clicking Internet searches online, using your default web browser and your default search provider.", https://www.sevenforums.com/tutorials/36599-search-windows-7-a.html via search summary; four choices "Libraries, Computer, Custom, or Internet" from a Windows 7 course slide)
- Windows 8/10: the same choices moved to a **Search again in** dropdown in the ribbon's Search tab, Location group, next to **This PC** (search the whole computer), **Current folder**, **All subfolders**. ("click/tap on search again in in the Search tab and select a different location to search in", https://www.tenforums.com/tutorials/94452-search-file-explorer-windows-10-a.html via search summary)
- The "Internet" choice can be removed by Group Policy ("Remove the Search the Internet 'Search again' link"). (https://technet.microsoft.com/library/dd744693.aspx via search summary)
- Windows 11: no source found showing "Search again in" in the Windows 11 Search options menu; the command-bar menu only has the Current folder / All subfolders scope switch. To widen a search you navigate to This PC or a drive and search again. (Absence is my reading of the Windows 11 menu sources in section 5; treat as unverified.)


---

## 3. Typing, Enter, debounce, suggestions dropdown, history

This changed three times. A faithful Windows 11 clone should copy the **current** behaviour (3.3).

### 3.1 Windows 7/8/10 before 1909: instant search in the view

- Windows Search has "incremental search (search as you type or wordwheeling)": results appear in the file list as each character is typed and narrow as you type more. (https://en.wikipedia.org/wiki/Windows_Search). The registry key holding Explorer search history is still called `WordWheelQuery` after this. (https://answers.microsoft.com/en-us/windows/forum/all/remove-search-history-from-windows-explorer/906b8d72-dec3-43bb-85fb-58f6e720b74f)

### 3.2 Windows 10 1909 to Windows 11 22H2 (pre-Moment 2): dropdown while typing, Enter for the view

From the Insider post that introduced it (https://blogs.windows.com/windows-insider/2019/05/08/announcing-windows-10-insider-preview-build-18894/):

- File Explorer search is "now powered by Windows Search", integrating OneDrive online content with indexed results.
- "as you type in File Explorer's search box, you'll now see a dropdown populated with suggested files at your fingertips that you can pick from." Clicking a suggestion opens the file; right-click a suggestion to open its file location.
- "If you need to use commands or dig deeper into non-indexed locations, you can still press enter and populate the view with the traditional search results."
- "as soon as you click the search box in File Explorer (or press CTRL+E to set focus to it), you'll see the dropdown list with your search history."
- Right-click on a dropdown item offered: open file location, copy path, run as administrator (for apps). (https://windowslatest.com/2019/10/14/windows-10-november-2019-update-improves-file-explorer-search)
- A → (arrow) button at the right end of the box runs the full search, same as Enter. Users report clicking it when Enter seemed not to work. (https://learn.microsoft.com/en-us/answers/questions/4304856/search-tool-in-windows-file-explorer-enter-key-doe)
- History is stored per user as the raw query strings under `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery` (an MRU list). Deleting the key clears it; policy `HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions=1` turns the dropdown off. (https://answers.microsoft.com/en-us/windows/forum/all/remove-search-history-from-windows-explorer/906b8d72-dec3-43bb-85fb-58f6e720b74f ; policy name via search-result summary of https://winaero.com/clear-windows-search-history , unverified page text)
- Folder Options > General > Privacy > "Clear File Explorer history" > Clear also wipes it. (search-result summary, https://windowsloop.com/how-to-clear-file-explorer-history-in-windows-11/ ; unverified page text)

### 3.3 Windows 11 22H2 (Moment 2, 2023) and later: live results in the view

Official Insider note, Beta build 22623.730, 29 Sep 2022 (https://blogs.windows.com/windows-insider/2022/09/29/announcing-windows-11-insider-preview-build-22621-730-and-22623-730/):

> "File Explorer search will now show results as you type."
> "The full search results page will update live without needing to press enter."

What this means for the clone:

- **Results stream into the main file view as you type**. Enter is not required. That results start after a short pause, and that Enter (or the → button where present) re-runs the search at once, both come from general use (unverified).
- **Debounce:** Microsoft publishes no delay value. Community reports describe results starting after you pause typing; earlier Insider notes list fixes for "when you did a search it may unexpectedly trigger the search happening repeatedly" and "File Explorer may sometimes lose focus on the search box while typing" (https://blogs.windows.com/windows-insider/2025/01/17/previewing-improved-windows-search-on-copilot-pcs-with-windows-insiders-in-the-dev-channel/). Clone recommendation (not a Windows number): debounce ~250-400 ms, cancel the in-flight query on every keystroke, keep focus in the box while results load.
- **History dropdown removed:** forum members on 24H2 report the dropdown of past searches went away when live results arrived (they date it to build revision .1413, March 2023). Microsoft did not document this; treat it as community-reported. (https://www.elevenforum.com/t/windows-explorer-search-history-not-displayed.35974 , via search-result summary; the forum blocks fetching)
- **Suggestion dropdown:** on current builds the suggested-files dropdown is no longer the main interaction; results go straight into the view. Some users still see a history dropdown occasionally; a forum moderator attributes this to shell add-ons (ExplorerPatcher, StartAllBack). (same thread, community-reported)
- **Copilot+ PCs:** a "sparkles" icon and an animated underline mark the box when semantic search is on; a tip about the new search appears "whenever you set focus to the search box in File Explorer". (https://blogs.windows.com/windows-insider/2025/01/17/previewing-improved-windows-search-on-copilot-pcs-with-windows-insiders-in-the-dev-channel/)
- **Sorting re-runs the search:** one Microsoft Q&A answer says sorting results can re-trigger a search. (https://learn.microsoft.com/en-us/answers/questions/3857628/windows-11-explorer-search-and-sorting , via search-result summary)

Clone decision: implement 3.3 (live results in the view). Optionally keep a recent-searches dropdown on focus (3.2) behind a setting, because many users expect it from Windows 10.


---

## 4. Results view

### 4.1 What the window shows during and after a search

- **Address bar:** the breadcrumb gains a final segment **"Search Results in <folder>"**. (UC Davis IT guide, https://it.environment.ucdavis.edu/file-explorer , via search summary: the address bar shows "Search results in" followed by the current folder name)
- **Progress:** while the query runs, a **green progress bar fills the address bar** from left to right. In non-indexed locations it can creep for minutes ("the green progress bar of despair inching across the address bar", https://filelocator-net.pages.dev/windows/ , third-party). Results appear incrementally while the bar is still moving; the view shows "Working on it..." until the first batch arrives (the "Working on it" text: https://www.thewindowsclub.com/windows-file-explorer-stuck-on-working-on-it-message via search summary).
- **Empty result:** the view shows **"No items match your search."** (https://windowsreport.com/?p=222363 , search-result title "FIX: No items match your search in Windows 10/11 File Explorer"; the 4 GB "gigantic" thread: https://techcommunity.microsoft.com/discussions/windows11/why-cant-my-computer-search-for-gigantic-files/4567190)
- **Status bar:** the item count updates to the number of results ("N items"). (general Explorer status-bar behaviour; unverified for search specifically)
- **Command bar:** gains a **Search options** button and a **Close search** button (X). On a narrow window they fold into the "..." (See more) menu. (Search options appears only after a search runs: "By default, the 'Search options' will not be visible until you execute at least a search query", https://www.windowsdigitals.com/how-to-search-only-video-files-in-windows-11/ via search summary; "See more" route: https://www.majorgeeks.com/content/page/save_your_favorite_searches_in_windows_11_and_find_files_instantly.html)
- Results include **folders as well as files** that match. Use `kind:folder` / `kind:-folder` to restrict. (inferred from guides on folder-only search such as https://www.windowsdigitals.com/how-to-search-for-folders-only-by-name-in-windows-11/ ; Kind > Folder in the menu)

### 4.2 Default view and columns

- Windows 11 opens search results in **Content view** by default, regardless of the folder's view, and has no setting to change that ("all searches still yield the 'Contents' mode by default"; "Apply to Folders" is greyed out in search results). (https://learn.microsoft.com/en-us/answers/questions/1539317/make-windows-11-show-search-results-in-details-vie). The community workaround sets `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell` `Mode`="1" and `LogicalViewMode`="3" (REG_SZ) to force Details (same page).
- Windows 7 behaved differently: "The search results will normally be presented using the same view as the folder you started the search in." (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t). The Windows 7 Content view "includes a preview of each file, highlights the search terms in each preview, and ranks the search results by relevance." (https://www.bruceb.com/2011/12/windows-7-tips-for-power-searches/)
- **Content view rows** show: icon/thumbnail, name, folder path, and two or three type-dependent properties (Date modified, Size, Authors, Dimensions...), plus a text snippet for content hits. (Content view definition: "displays the most relevant content for each item", Microsoft developer docs quoted in search summary; row layout from general use, unverified detail.)
- **Details view in search results** adds a **Folder** column (System.ItemFolderPathDisplayNarrow). Its format is **folder name first, then the parent path in parentheses**: e.g. `Aerospace-Fiction (F:\My Pictures\Scanned Not Tagged\Objects\Vehicles)`. (https://learn.microsoft.com/en-us/answers/questions/3948497/how-to-set-the-folder-field-format-in-search). Microsoft defines this property as a display path "tailored so that the folder name comes first, to optimize for a narrow viewing column", using localised names for known folders. (https://learn.microsoft.com/en-us/windows/win32/properties/props-system-itemfolderpathdisplaynarrow)
- A saved search can define its own columns, grouping, and up to four sort keys (section 8). Microsoft's own sample "Recently shared by me" uses columns Name, Date modified, Tags, Shared with, Folder (ItemFolderPathDisplayNarrow). (https://learn.microsoft.com/en-us/windows/win32/search/-search-savedsearchfileformat)
- If nothing is specified, "the search results are presented with a default set of columns appropriate for the file types displayed." (same page)

### 4.3 Sorting and grouping in results

- All normal Details-view sorting and **Group by** work in results; **Group by > Folder** groups results under folder headers, which is the usual way to see "where" hits are. Sort by Folder sorts by the narrow folder path. (general Explorer behaviour; the Folder column is a normal sortable column per the saved-search schema, https://learn.microsoft.com/en-us/windows/win32/search/-search-savedsearchfileformat)
- Initial order is relevance-ranked (Windows 7: "ranks the search results by relevance", https://www.bruceb.com/2011/12/windows-7-tips-for-power-searches/). Clicking a column header switches to that sort. There is no visible "Relevance" column.
- Sorting can re-trigger the search (Microsoft Q&A community answer, https://learn.microsoft.com/en-us/answers/questions/3857628/windows-11-explorer-search-and-sorting via search summary).
- Column headers in Details view offer the usual filter dropdowns (checkbox lists such as Date modified ranges, Type values, Size buckets) which further narrow the results; picking one adds the matching AQS term to the box. (Windows 7+ header filters; unverified for Windows 11 specifically.)

### 4.4 Highlighting

- In Content view, matched search terms are **highlighted** in the name and in the content snippet (Windows 7: "highlights the search terms in each preview", https://www.bruceb.com/2011/12/windows-7-tips-for-power-searches/). No Microsoft page describes the Windows 11 highlight colour; it is a light (yellow-ish) background on the matched word prefix (unverified, general use).
- In the search box, recognised AQS keywords change colour (e.g. `content:` turns light blue once recognised). (https://beaconfind.app/guides/search-inside-files-windows/ via search summary, Windows 11)
- Details view does not highlight.

### 4.5 Actions on results

- Double-click/Enter opens the item as usual.
- **Open file location** (right-click a result): navigates to the parent folder with the item selected. ("Right-click a result and choose 'Open file location' to go to its folder", https://nerdschalk.com/how-to-search-in-windows-11-everything-you-need-to-know/). Windows 10 also had it as a ribbon button in Search > Options.
- All normal file operations (copy, move, rename, delete, drag out) work on results; deleted/moved items drop out of the list. (general behaviour)
- Right-click an empty area of the results > **Save search** (section 8).


---

## 5. Search options menu

### 5.1 Where it is

- **Windows 11:** a **Search options** dropdown button appears on the command bar only after a search has run, next to **Close search**. ("Search Tools have now been renamed as 'Search Options' in Windows 11 and you now get a drop-down menu", ElevenForum tutorial via search summary, https://elevenforum.com/t/search-in-windows-11-file-explorer.21789/ ; "the 'Search options' will not be visible until you execute at least a search query", https://www.windowsdigitals.com/how-to-search-only-video-files-in-windows-11/ via search summary)
- **Windows 8/10:** a contextual **Search** ribbon tab (Search Tools) appears as soon as the box gets focus, with groups **Location**, **Refine**, **Options**. ("arranged in several categories: Location, Refine, and Options", https://www.techrepublic.com/article/use-the-search-contextual-tab-in-windows-10-to-efficiently-find-files/ via search summary)

### 5.2 Menu contents (Windows 11), with the Windows 10 ribbon equivalent

| Windows 11 Search options item | Sub-items | Windows 10 ribbon home | What it does |
|---|---|---|---|
| **All subfolders** (default, checked) / **Current folder** | radio pair | Location group (+ This PC, Search again in) | recursive vs one-level scope (section 2) |
| **Date modified** | Today, Yesterday, This week, Last week, This month, Last month, This year, Last year | Refine | writes `datemodified:<range>` into the box |
| **Kind** | Calendar, Communication, Contact, Document, E-mail, Feed, Folder, Game, Instant Message, Journal, Link, Movie, Music, Note, Picture, Playlist, Program, Recorded TV, Saved Search, Task, Video, Web History, Unknown (23 items) | Refine | writes `kind:=<kind>` |
| **Size** | Empty (0 KB), Tiny (0 - 16 KB), Small (16 KB - 1 MB), Medium (1 - 128 MB), Large (128 MB - 1 GB), Huge (1 - 4 GB), Gigantic (> 4 GB) | Refine | writes `size:<bucket>` |
| (Windows 10: **Other properties**) | Type, Name, Folder path, Tags (set varies with folder template, e.g. Pictures adds Date taken) | Refine | writes `type:` / `name:` / `folderpath:` / `tags:` and leaves the caret after the colon for you to type a value |
| **File contents** (toggle) | | Options > Advanced options | also read file contents in non-indexed locations (slow) |
| **System files** (toggle) | | Options > Advanced options | include system directories in non-indexed searches |
| **Zipped (compressed) folders** (toggle) | | Options > Advanced options | look inside .zip/.cab while crawling |
| **Change indexed locations** | | Options > Advanced options | opens the Indexing Options control panel |
| (Windows 10: **Recent searches**) | MRU list + "Clear search history" | Options | re-run a previous query |
| (Windows 10: **Save search**, **Open file location**) | | Options | Windows 11 moved these to right-click (section 4.5, 8) |
| **Close search** | | Close search (red X) | leave search mode |

Sources for the table:
- Date modified items: listed as "Today, Yesterday, This Week, Last Week, This Month, Last Month, This Year, or Last Year" by one guide; others omit Last month/Last year, so the list differs a little by version. (https://computerhope.com/tips/tip202.htm , https://www.minitool.com/news/find-files-by-date-modified-windows-10.html , via search summary). A single third-party source adds "Date modified > Custom" with a calendar picker; unverified. (https://filelocator.net/guides/windows-search-syntax/)
- Kind items: the System.Kind enum labels (https://learn.microsoft.com/en-us/windows/win32/properties/props-system-kind); "over 23 types available" in the Windows 11 menu (https://nerdschalk.com/how-to-search-in-windows-11-everything-you-need-to-know/).
- Size items and ranges: Windows 11 menu list from https://nerdschalk.com/how-to-search-in-windows-11-everything-you-need-to-know/ ; exact byte boundaries in 6.5 (https://learn.microsoft.com/en-us/windows/win32/properties/props-system-size).
- Toggles: "The menu includes System files, Zipped (compressed) folders, File contents, which you can switch on or off by clicking each one" (https://nerdschalk.com/how-to-search-in-windows-11-everything-you-need-to-know/); "Advanced ... includes system files, compressed folders, or file contents in the search" and "Change indexed locations" (https://mundobytes.com/en/Search-for-files-with-advanced-filters-in-Windows-11-Explorer).
- Windows 10 Advanced options: "lets you change which folders are indexed for fast searching or add non-indexed locations to a search operation. Non-indexed locations include file contents, system files, and zipped folders." (https://www.tenforums.com/tutorials/94452-search-file-explorer-windows-10-a.html via search summary)
- Other properties list (Type, Name, Folder path, Tags): from the requester's brief and Windows 10 ribbon memory; no fetched page lists it verbatim (unverified).
- Exact inserted strings (`kind:=document`, `datemodified:this week`): sources only say "The text search box changes to reflect your choice and Windows performs the search" (computerhope/minitool via search summary) and "Explorer writes the AQS into the search box" (https://filelocator.net/guides/windows-search-syntax/). The `=` after `kind:` is from Windows 10 use; unverified. The written keyword is localised, which is why "The Date modified dropdown can also reveal the correct localized syntax for non-English installs" (same filelocator page).

Behaviour rules for the clone:

- Picking a filter **appends** an AQS term to whatever is in the box (space-separated, so it ANDs). Picking a second value of the same filter replaces the first (unverified; Windows 10 use).
- The search re-runs immediately after a pick.
- Filters are only text in the box; there is no hidden filter state. Clearing the text clears the filters. A clone should therefore implement the menu as an AQS-writer on top of one query parser.
- Toggles (File contents / System files / Zipped) are persistent global settings, not part of the query. They are the same settings as Folder Options > Search (5.3).

### 5.3 Folder Options > Search tab (the persistent settings behind the toggles)

Windows 10/11 dialog (File Explorer Options > Search):

| Group | Checkbox | Effect |
|---|---|---|
| How to search | Don't use the index when searching in file folders for system files (searches might take longer) | "enables searches for system files that may not be indexed" |
| When searching non-indexed locations | Include system directories | add system folders to crawls |
| | Include compressed files (ZIP, CAB...) | "allows searches within compressed folders" |
| | Always search file names and contents (this might take several minutes) | read contents of every file in non-indexed locations |

(Labels: https://www.ninjaone.com/blog/change-folder-and-search-options-in-windows/ ; descriptions: https://www.dummies.com/article/technology/computers/operating-systems/windows/windows-10/how-to-customize-windows-7s-search-settings-195323/. Default states not stated by sources; from use, "Include system directories" is on and the other three are off; unverified.)

Windows 7 also had "Find partial matches", "Use natural language search" and "Include subfolders in search results when searching in file folders"; Windows 10 removed them and "searching in Windows 10 is always partial" (word-prefix). (https://www.pchelp.zone/threads/where-is-find-partial-matches-in-windows-10-search-options.150261/ via search summary; https://www.dummies.com/article/technology/computers/operating-systems/windows/windows-10/how-to-customize-windows-7s-search-settings-195323/)


---

## 6. Advanced Query Syntax (AQS)

AQS is the query language typed into the Explorer search box. The same syntax works in the Start/taskbar search box. It is what the Search options menu writes into the box when you pick a filter (e.g. picking Size > Large puts a `size:` term in the box; exact strings in section 5). Source: https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-advancedquerysyntax , https://learn.microsoft.com/en-us/archive/blogs/alanlemarquand/using-advanced-query-syntax-to-find-files-in-windows-7

### 6.1 Grammar

```
<query>       ::= <basic query> | ( <query> ) | <query> AND <query>
                | <query> <query>        // juxtaposition = AND
                | <query> OR <query> | NOT <query>
<basic query> ::= <prop>:<basic restr> | <restr>
<prop>        ::= canonical name (System.DateModified) | UI-language label (datemodified, author)
<basic restr> ::= <value> | <op><value> | NOT <basic restr> | ( <restr> )
<restr>       ::= <basic restr> | <restr> AND <restr> | <restr> <restr> | <restr> OR <restr>
<value>       ::= <simplevalue> | <simplevalue> .. <simplevalue>
<simplevalue> ::= [] | word | number | datetime | Boolean | "phrase" | enumeration range
```
Source: https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-advancedquerysyntax

Rules a clone must copy:

- **Case:** AQS is case-insensitive except `AND`, `OR`, `NOT`, which must be ALL CAPS. Lowercase `and`/`or`/`not` are plain search words. (same source)
- **Implicit AND:** a space between terms means AND. `social security` finds items with both words in any order. (https://learn.microsoft.com/en-us/windows/win32/lwef/-search-2x-wds-aqsreference)
- **Left-to-right binding, no precedence:** `apple AND pear OR plum` = `(apple AND pear) OR plum`; `apple OR pear AND plum` = `(apple OR pear) AND plum`. Microsoft recommends explicit parentheses. (3x page)
- **No property = all properties:** a bare word is matched against every indexed property (file name, title, author, tags...) and, in indexed locations, file contents. (3x page; content caveat in section 7)
- **Default string operator is word-prefix ("starts with a word"):** for string properties with no operator, AQS uses COP_WORD_STARTSWITH. So `auto` matches `automobile.txt` and `my auto report.docx` (a word in the name starts with `auto`) but **not** `photoauto.jpg` (see 6.6 for how this plays out in real Explorer use). Non-string properties default to `=`. (3x page: "For a string property, the COP_WORD_STARTSWITH $< operator is assumed. For all other properties, the COP_EQUAL = operator is assumed.")
- **Property scoping binds only to the next value:** `authors:(Charlie AND Herb)` = both authors; `authors:Charlie AND Herb` = author Charlie, plus `Herb` anywhere. (https://learn.microsoft.com/en-us/archive/blogs/alanlemarquand/using-advanced-query-syntax-to-find-files-in-windows-7)
- **Property names drop spaces:** `Modified:`, `DateModified:`, `Date Modified:` are equal per the Win7 blog; rule of thumb "remove the space" (`datelastprinted`). (same blog)
- **Localised keywords:** since Windows 7, mnemonic keywords (`author`, `kind`, `size`...) work only in the current UI language; canonical names (`System.Author`) work everywhere. A German Windows does not understand `size:`. (3x page; Portuguese example: https://techcommunity.microsoft.com/discussions/windows11/why-cant-my-computer-search-for-gigantic-files/4567190)
- **Multi-value properties:** `p:restr` matches if any one value satisfies it (tags, authors). (3x page)
- **WDS 2.x note:** an older WDS page says NOT and OR "can't be combined in the same query"; the current Windows 7+ grammar above allows it with left-to-right binding. Treat the WDS note as obsolete. (https://learn.microsoft.com/en-us/windows/win32/lwef/-search-2x-wds-aqsreference)

### 6.2 Operators (value-level)

Verbatim from the Microsoft Learn "Query operators" table (3x page):

| Operator | Symbol(s) | Example | Meaning |
|---|---|---|---|
| COP_EQUAL | `=` | `System.FileExtension:=".txt"` | exact value |
| COP_NOTEQUAL | `≠` `-` `<>` `NOT` | `kind:<>picture`, `kind:-picture`, `kind:NOT picture`, `System.Photo.DateTaken:-[]` | not equal; `-[]` = "has a value". Double negation does not cancel (`- -picture` = `-picture`) |
| COP_LESSTHAN | `<` | `size:<1kb` | less than |
| COP_GREATERTHAN | `>` | `System.ItemDate:>System.StructuredQueryType.DateTime#Today` | greater than |
| COP_LESSTHANOREQUAL | `<=` `≤` | `size:<=1kb` | |
| COP_GREATERTHANOREQUAL | `>=` `≥` | `size:>=1kb` | |
| COP_VALUE_STARTSWITH | `~<` | `System.FileName:~<"C++ Primer"` | whole value starts with |
| COP_VALUE_ENDSWITH | `~>` | `System.Photo.CameraModel:~>non` | whole value ends with |
| COP_VALUE_CONTAINS | `~=` `~~` | `System.Subject:~=round` | substring anywhere ("ground rules" matches) |
| COP_VALUE_NOTCONTAINS | `~!` | `System.Author:~!"sanjay"` | substring absent |
| COP_DOSWILDCARDS | `~` | `System.FileName:~"Mic?osoft W*d"` | DOS wildcards: `?` = one char, `*` = zero or more |
| COP_WORD_EQUAL | `$=` `$$` | `From:$="Sanjay Jacobs"` | exact word/phrase |
| COP_WORD_STARTSWITH | `$<` | `System.Filename:$<"Micro Exe"` | each word starts with (the default for strings) |

Query-level operators (WDS reference table, https://learn.microsoft.com/en-us/windows/win32/lwef/-search-2x-wds-aqsreference):

| Operator | Example | Result |
|---|---|---|
| space | `social security` | both words, any order |
| `AND` | `social AND security` | same as space |
| `OR` | `social OR security` | either |
| `NOT` | `social NOT security` | first, not second |
| `"..."` | `"social security"` | exact phrase; a doubled `""` inside is a literal quote (`"The ""blue"" team"`) |
| `( )` | `(social security)` / `author:(john OR joanne)` | grouping |
| `>` `<` | `date:>11/13/21`, `size:>500` | comparison (bare numbers on size are bytes) |
| `..` | `date:11/13/21..11/15/21`, `size:5kb..10kb` | inclusive range |
| `-` prefix | `-draft` | same as NOT (from COP_NOTEQUAL symbol list; unverified as a bare term outside a property, commonly used) |

Wildcards: `*` and `?` work in plain terms and property values, e.g. `authors:alan*`, `*.pdf`. (Win7 blog; COP_DOSWILDCARDS row above). When a term contains `*`/`?`, the match is a DOS-style pattern instead of word-prefix.

### 6.3 Values

| Value | Example | Notes |
|---|---|---|
| word | `auto` | no whitespace; word-prefix match by default |
| phrase | `"Conclusions: valid"` | not parsed as syntax |
| integer | `5678` | digits only, no thousands separator |
| size with unit | `size:>250mb`, `size:10mb..20mb`, `System.Size:>1kb` | units B, KB, MB, GB; no unit = bytes (https://learn.microsoft.com/en-us/archive/blogs/alanlemarquand/using-advanced-query-syntax-to-find-files-in-windows-7) |
| size keyword | `size:empty/tiny/small/medium/large/huge/gigantic` | see 6.5 |
| empty value | `tag:[]`, `authors:[]` | "has no value" (untagged files, no author) |
| absolute date | `datemodified:1/26/2010`, `date:>11/13/21`, `modified:10/15/2002 19:00` | parsed in the user's locale (dd/mm vs mm/dd); time precision to the minute |
| ISO date | `2024-03-01T10:00:00` | supported since Windows 8 (3x page) |
| date range | `datemodified:1/7/2010..1/8/2010` | inclusive |
| relative date | `today`, `tomorrow`, `yesterday`, `this week`/`thisweek`, `last week`/`lastweek`, `next week`, `this month`, `last month`/`lastmonth`, `past month`/`pastmonth`, `next month`/`nextmonth`, `this year`, `last year`, `coming year`/`comingyear` | multi-word forms can be written joined (Win7 blog) |
| day / month names | `Monday`, `Monday..Wednesday`, `February` | (3x page; Win7 blog) |
| Boolean | `isdeleted:true`, `System.IsRead:=System.StructuredQueryType.Boolean#True` | |

What "this week" means: the calendar week containing today (starts on the locale's first day of week), not the last 7 days; "last week" is the previous calendar week. The WDS table says "a date falling within the current week" / "within the previous week". (https://learn.microsoft.com/en-us/windows/win32/lwef/-search-2x-wds-aqsreference). There is no AQS "last N minutes/hours" token; a Win7 blog commenter asks for "last 10 minutes" and gets no answer (Win7 blog comments).

### 6.4 Property keywords a clone should support

All from https://learn.microsoft.com/en-us/windows/win32/lwef/-search-2x-wds-aqsreference ("Everything" table) unless noted. Each keyword maps to a Windows shell property (canonical name in brackets, from general Windows property-system naming).

| Keyword(s) | Property | Example |
|---|---|---|
| `name:` | file name incl. extension [System.FileName / ItemNameDisplay] | `name:report` |
| `filename:` `file:` | file name | `filename:MyResume` |
| `ext:` `fileext:` | extension [System.FileExtension] | `ext:.txt`, `ext:pdf` (the dot is optional in practice; unverified) |
| `type:` | the Type column text ("PDF Document", "Text Document") or extension [System.ItemTypeText] | `type:pdf`, `type:"Text Document"` (Type is in Explorer's "Other properties" menu, section 5) |
| `kind:` | System.Kind (category) | `kind:pics`, `kind:=folder`, `kind:docs`, `kind:everything` |
| `size:` | System.Size (bytes) | `size:>50MB`, `size:large` |
| `date:` | "any date" (System.ItemDate: the main date for that kind, e.g. date taken for photos) | `date:last week` |
| `datemodified:` `modified:` | System.DateModified | `modified:last week` |
| `datecreated:` `created:` | System.DateCreated | `datecreated:2024` (keyword from general usage; not in the WDS table; unverified alias `created:`) |
| `dateaccessed:` `accessed:` | System.DateAccessed | (unverified) |
| `datetaken:` | System.Photo.DateTaken | `datetaken:yesterday` |
| `folder:` `under:` `path:` | folder path [System.ItemFolderPathDisplay] | `folder:downloads` |
| `foldername:` `in:` | folder name | `in:MyDocuments` |
| `tag:` `tags:` `keywords:` | System.Keywords (Tags column) | `tag:vacation`, `keywords:"sales projections"` (`tag:` alias per Win7 usage; WDS table lists `keywords`) |
| `author:` `authors:` `by:` | System.Author | `author:"Stephen King"` |
| `title:` `subject:` `about:` | System.Title | `title:"Quarterly Financial"` |
| `comments:` | System.Comment | |
| `rating:` | System.Rating (stars) | `rating:>3` (unverified syntax) |
| `content:` | full-text contents only (System.Search.Contents) | `content:invoice` (works only where contents are indexed; section 7) |
| `artist:` `album:` `genre:` `year:` `track:` `bitrate:` `duration:` | music | `year:>1980 <1990` |
| `width:` `height:` `dimensions:` `orientation:` `cameramake:` `cameramodel:` | pictures | `width:1600`, `orientation:landscape` |
| `slidecount:` | presentations | `slidecount:>20` |
| `isdeleted:` `deleted:` | System.IsDeleted | `isdeleted:true` |
| `attributes:` | file attributes | (unverified) |
| `System.<Anything>:` | any registered shell property by canonical name | `System.Size:>1kb` |

Kind keywords accepted (mnemonics from the System.Kind enum, https://learn.microsoft.com/en-us/windows/win32/properties/props-system-kind):

| Kind (menu text) | `kind:` mnemonics |
|---|---|
| Calendar | calendar, calendars, meeting, meetings, appointment, appointments |
| Communication | communication, communications |
| Contact | contact, contacts, person, people |
| Document | document, documents, doc, docs |
| E-mail | email, emails, e-mails, message, messages, mail |
| Feed | feed, feeds |
| Folder | folder, folders |
| Game | game, games |
| Instant Message | instant message, instant messages, im, ims |
| Journal | journal, journals |
| Link | link, links |
| Movie | movie, movies, film, films |
| Music | music, song, songs |
| Note | note, notes |
| Picture | picture, pictures, pic, pics, image, images, photo, photos |
| Playlist | playlist, playlists |
| Program | program, programs |
| Recorded TV | tv |
| Saved Search | saved search, search |
| Task | task, tasks |
| Video | video, videos |
| Web History | web history, history, webpage, webpages |
| Unknown | unknown |

Plus `kind:everything` (all kinds) from the WDS table. Kind is derived from the file extension via the registry key `HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\KindMap`; the list of kinds is not extensible. A file can have more than one kind (it is a multi-value string). (props-system-kind page)

### 6.5 Size keywords and exact byte boundaries

From the System.Size property description, Windows 10 1809 and later (applies to Windows 11). Source: https://learn.microsoft.com/en-us/windows/win32/properties/props-system-size

| Menu text (verbatim) | Keyword | minValue (bytes) | Effective range |
|---|---|---|---|
| Empty (0 KB) | `size:empty` | 0 | exactly 0 bytes |
| Tiny (0 - 16 KB) | `size:tiny` | 1 | 1 B to 16 KB |
| Small (16 - 1 MB) | `size:small` | 16383 | ~16 KB to 1 MB |
| Medium (1 - 128 MB) | `size:medium` | 1048577 | >1 MiB to 128 MiB |
| Large (128 MB - 1 GB) | `size:large` | 134217729 | >128 MiB to 1 GiB |
| Huge (1 - 4 GB) | `size:huge` | 1073741825 | >1 GiB to 4 GiB |
| Gigantic (>4 GB) | `size:gigantic` | 4294967297 | >4 GiB |

Each bucket runs from its minValue to the next bucket's minValue minus 1. Units are binary (1 MB = 1,048,576 bytes). The Small minValue 16383 is as Microsoft documents it (probably a typo for 16385; a clone can use 16385 or copy 16383). The menu text "Small (16 - 1 MB)" really lacks "KB" in the docs.

Windows 7 through Windows 10 1803 used smaller buckets: Tiny 0-10 KB, Small 10-100 KB, Medium 100 KB-1 MB, Large 1-16 MB, Huge 16-128 MB, Gigantic >128 MB (same page). Old guides still quote these; they are wrong for Windows 11.

### 6.6 How a plain term actually matches (the part users notice most)

- **Word-prefix, not substring.** "Windows only looks for the search terms at the start of words. It will not find the search term if it only appears later in a word." `bert` finds *Bert* and *Bertie* but not *Albert* or *Ethelbert*. (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t)
- **Words are split on spaces and punctuation, not on camelCase or digits.** `invoicenumber12345.pdf`: `invoicenumber` matches, `number12345` and `12345` do not. Searching `Image` does not find `MyImageFactory`. (https://learn.microsoft.com/en-us/answers/questions/2409312/windows-7-search-does-not-find-partial-matches-whe). Punctuation is not indexed in content ("Text content is indexed but punctuation is not", https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-wds-included-in-index).
- **Wildcards fix it.** `*bert` finds *Albert* and *Ethelbert*; `??bert` limits how many characters may come before. `*12345`, `*joe*smith`, `*Blazon*`. (same two Q&A pages; https://testbook.com/question-answer/how-do-you-search-for-files-with-partial-names-in--69d4b9cfba2c20dc60ddc4ec via search summary). Explicit substring: `name:~=term` or `name:~~term` (COP_VALUE_CONTAINS, 6.2).
- **"Always partial" in Windows 10/11.** Windows 7/8 let you turn prefix matching off ("Find partial matches"); Windows 10 removed the option and is "always partial" (prefix). (https://www.pchelp.zone/threads/where-is-find-partial-matches-in-windows-10-search-options.150261/ via search summary). With it off in Windows 8, "You wouldn't see items that contain Sarah until you type all five characters". (https://www.oreilly.com/library/view/windows-8-bible/9781118240748/xhtml/sec197.html via search summary)
- **Several words = AND across all properties.** `quarterly budget` returns items where some word starts with `quarterly` and some word starts with `budget`, in name, any indexed property, or (indexed) contents. Order does not matter. (6.1)
- **A plain term hits more than the name.** A bare word also matches Authors, Title, Tags, and other indexed text properties, and in indexed locations the contents. That is why results include files whose names do not contain the word. Use `name:` to restrict to the file name, `content:` for contents only. ("`filename:bert` restricts matching to file names", "`content:bert` restricts matching to file contents", same Q&A guide)
- **Quoted phrases in non-indexed content search are unreliable.** `contents:"d c"` returned many false positives on files containing just "d " or " c". (https://learn.microsoft.com/en-us/answers/questions/852199/windows-10-file-explorer-search-with-advanced-opti)
- **Case-insensitive.** AQS "is not case sensitive" except the operators. (https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-advancedquerysyntax)
- **Natural Query Syntax** (plain-English queries such as "email from john") exists but is off by default. (https://en.wikipedia.org/wiki/Windows_Search). A clone can skip it.
- **No regex.** "no regex support at all" (https://filelocator.net/guides/windows-search-syntax/ , third-party).
- **Known AQS bugs:** a Microsoft blog commenter warns AQS is "rife with bugs" and often doesn't behave as documented. A clone that is more consistent than Windows is fine. (https://learn.microsoft.com/en-us/archive/blogs/alanlemarquand/using-advanced-query-syntax-to-find-files-in-windows-7 comments)

### 6.7 Clone checklist for the parser

1. Tokenise: quoted strings (with `""` escapes), parentheses, `AND`/`OR`/`NOT` (uppercase only), `-` prefix, `prop:` prefixes, comparison ops (`>`, `<`, `>=`, `<=`, `=`, `<>`, `~<`, `~>`, `~=`, `~~`, `~!`, `~`, `$=`, `$<`), and `..` ranges.
2. Resolve property aliases (table 6.4) case-insensitively, ignoring spaces in the name.
3. Parse values by property type: size with B/KB/MB/GB (binary units) or bucket names; dates (locale order, ISO, relative words, weekday/month names, ranges); kind names via mnemonics; `[]` empty.
4. Combine with implicit AND, left-to-right AND/OR binding, parentheses.
5. Default match for bare terms: word-prefix over name + text properties (+ contents where indexed). `*`/`?` switch to wildcard matching over the whole value.



---

## 7. Indexed vs non-indexed locations; Classic vs Enhanced; what the index covers

### 7.1 Two engines behind one box

| | Indexed location | Non-indexed location |
|---|---|---|
| How | query against the Windows Search index (SearchIndexer.exe) | Explorer walks the folder tree on the fly ("crawls every file on the fly", https://filelocator-net.pages.dev/windows/ , third-party) |
| Speed | near-instant | seconds to many minutes; green bar creeps across the address bar |
| Free text matches | names, all indexed properties, **file contents** (for types with a filter) | **file names only** by default ("In indexed locations, search filenames and contents. In non-indexed locations, search filenames only", Windows 7 default, https://www.dummies.com/article/technology/computers/operating-systems/windows/windows-10/how-to-customize-windows-7s-search-settings-195323/) |
| Property filters (`size:`, `datemodified:`, `kind:`, `author:`) | from index | still work: "the property handlers and IFilters are invoked on the fly ... at the cost of searching speed" (https://en.wikipedia.org/wiki/Windows_Search) |
| Contents | yes, if file type set to "Index Properties and File Contents" | only if **File contents** toggle / "Always search file names and contents" is on; very slow; phrase matching unreliable (https://learn.microsoft.com/en-us/answers/questions/852199/windows-10-file-explorer-search-with-advanced-opti) |
| Inside .zip | indexed archives already have names/contents indexed | only with **Zipped (compressed) folders** on (Windows 7 guide: "indexed archives already have their filenames and contents indexed", dummies page) |
| Mixed | a folder that is partly indexed is searched by both, merged seamlessly: Windows Search "can seamlessly search indexed as well as non-indexed locations" (https://en.wikipedia.org/wiki/Windows_Search) | |

- `content:` works "only in indexed locations, and only for file types with an installed text filter (IFilter)" (https://filelocator-net.pages.dev/windows/ , third-party; consistent with Microsoft's index docs below).
- Network shares and mapped drives are not indexed on the client, so they always crawl and do not search contents unless toggled: "Since network locations are not indexed, searching them is relatively slow & does not include searching file contents." (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t). A Windows server running Windows Search can serve its own index remotely ("Windows Search also supports queries against a remote index", https://en.wikipedia.org/wiki/Windows_Search).
- Removable USB drives "cannot be indexed" (they report as removable). (https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-wds-included-in-index)
- Windows 7-10 showed an info bar on slow searches ("Searches might be slow in non-indexed locations ... Click to add to index"); I found no page confirming it still appears in Windows 11 (unverified). A related message "Your searches might be slow because the index is not running" exists in Windows 11 when the indexer is off. (https://www.kapilarya.com/your-searches-might-be-slow-because-the-index-is-not-running)

### 7.2 Classic vs Enhanced (Settings > Privacy & security > Searching Windows > Find my files)

From Microsoft Support (https://support.microsoft.com/en-us/windows/search-indexing-in-windows-da061c83-af6b-095c-0f7a-4dfecda4d15a):

- **Classic** (default): "indexes your Documents, Pictures, and Music folders plus the desktop by default." **Customize search locations** opens the legacy Indexing Options dialog (Modify > tick folders).
- **Enhanced**: "indexes your entire PC, including all user folders and files"; may use more battery/CPU. Has **Exclude folders from enhanced search** (Add an excluded folder). (exclusion label: https://geekrewind.com/how-to-turn-on-or-off-enhanced-search-mode-in-windows-11/ via search summary)
- Enhanced mode arrived in Windows 10 1903. Wikipedia: it indexes all file names across the PC; contents are still indexed only for configured locations (https://en.wikipedia.org/wiki/Windows_Search; Microsoft's own page does not make that distinction).
- Registry: `HKLM\SOFTWARE\Microsoft\Windows Search\UX\Configuration\EnableFindMyFiles` (1 = Enhanced). (https://geekrewind.com/how-to-enable-enhanced-search-indexing-in-windows-11/ via search summary; unverified)
- Copilot+ PCs add **semantic indexing** alongside the normal index (on by default). Supported: .txt, .pdf, .docx, .doc, .rtf, .pptx, .ppt, .xls, .xlsx and .jpg/.jpeg, .png, .gif, .bmp, .ico; it "will only work for files saved locally in indexed locations". (https://support.microsoft.com/en-us/windows/search-indexing-in-windows-da061c83-af6b-095c-0f7a-4dfecda4d15a ; https://blogs.windows.com/windows-insider/2025/01/17/previewing-improved-windows-search-on-copilot-pcs-with-windows-insiders-in-the-dev-channel/)

Default indexed locations on a new install (community answer, not official): Start Menu (`C:\ProgramData\Microsoft\Windows\Start Menu`), `C:\Users` minus each AppData, IE history, Outlook when installed, Offline Files. (https://learn.microsoft.com/en-us/answers/a/4236535 via search summary)

### 7.3 What the index stores

From Microsoft (https://support.microsoft.com/en-us/windows/search-indexing-in-windows-da061c83-af6b-095c-0f7a-4dfecda4d15a ; https://learn.microsoft.com/en-us/windows/win32/search/-search-3x-wds-included-in-index):

- "all the properties of your files are indexed, including file names and full file paths."
- "For files with text, their contents are indexed to allow you to search for words within the files."
- Per file type (Indexing Options > Advanced > File Types) you choose **Index Properties only** or **Index Properties and File Contents**. Properties-only types are findable by name but not contents.
- A type with no filter, or a file with no extension: system properties indexed, contents not.
- Built-in content filters: HTML (.htm/.html/.css/.asp...), MIME HTML (.mht), Office (.doc/.xls/.ppt..., modern .docx/.xlsx/.pptx via Office filters), Text (.txt, .c, .cpp, .h, .js, .ini, .log, .reg, .rtf, .bat, .vbs...), XML (.xml/.xsl), OneNote (.one). PDF contents need a PDF IFilter (Windows 10+ ships one; third-party guides say "Many PDFs are not, depending on what's installed", https://filelocator-net.pages.dev/windows/).
- "Text content is indexed but punctuation is not." HTML comments are not indexed. DRM/IRM-protected content is not indexed.
- Default folder exclusions: `ProgramData` (except the shared Start Menu), every `Users\*\AppData`, `Windows\`, `$Recycle.Bin`, `Windows.old`-style folders, temp folders, the index's own data folder.
- Index size: "less than 10 percent of the size of the indexed files"; initial build "up to a couple hours"; then only changed files are re-indexed (NTFS change notifications).
- Architecture (for a clone that builds its own index): SearchIndexer.exe hosts the index; SearchProtocolHost.exe runs protocol handlers (file system, Outlook, IE history, Offline Files); SearchFilterHost.exe runs IFilters (content) and property handlers (metadata) at low integrity. (https://en.wikipedia.org/wiki/Windows_Search)

---

## 8. Save search (.search-ms) and the search-ms: URI

### 8.1 User flow

- Windows 11: run a search, **right-click an empty area of the results > Save search**. The Save dialog defaults to `%USERPROFILE%\Searches`, lets you set name, Authors and Tags. (https://www.majorgeeks.com/content/page/save_your_favorite_searches_in_windows_11_and_find_files_instantly.html ; https://www.makeuseof.com/windows-save-file-explorer-search/)
- Windows 10: **Search tab > Save search** button on the ribbon. (https://winaero.com/save-search-windows-10/)
- Opening the saved file re-runs the query and "displays up-to-date results" (it is a live virtual folder, not a snapshot). You can pin it to Quick access/Start. (https://learn.microsoft.com/en-us/windows/win32/search/-search-savedsearchfileformat ; https://www.majorgeeks.com/content/page/save_your_favorite_searches_in_windows_11_and_find_files_instantly.html)

### 8.2 File format (XML), from https://learn.microsoft.com/en-us/windows/win32/search/-search-savedsearchfileformat

```xml
<?xml version="1.0"?>
<persistedQuery version="1.0">
  <viewInfo viewMode="details" iconSize="16">        <!-- details | icons | tiles; iconSize 16-256 -->
    <visibleColumns><column viewField="System.ItemNameDisplay"/> ...</visibleColumns>
    <groupBy viewField="System.ItemFolderPathDisplayNarrow" direction="ascending"/>
    <sortList><sort viewField="System.DateModified" direction="descending"/></sortList>  <!-- up to 4 -->
  </viewInfo>
  <query>
    <scope>
      <include path="E:\" />                                   <!-- or knownFolder="{GUID}" -->
      <include knownFolder="{FDD39AD0-238F-46AF-ADB4-6C85480369C7}" nonRecursive="true"/>
      <exclude path="E:\Windows" nonRecursive="false"/>
    </scope>
    <kindList><kind name="document"/></kindList>               <!-- union of System.Kind values -->
    <conditions>                                               <!-- and/or/not/leafCondition tree -->
      <condition type="leafCondition" property="System.Author" propertyType="string"
                 operator="wordmatch" value="John" valueType="System.StructuredQueryType.String"/>
    </conditions>
  </query>
  <properties>...</properties>                                 <!-- author, kind, description, tags -->
</persistedQuery>
```

- `scope` needs at least one `include`; paths may use environment variables; `nonRecursive="true"` = Current folder only.
- Relative dates are stored as encoded relative values (e.g. Microsoft's "Recent documents" sample stores `operator="imp" value="R00UUUUUUUUZZXD-30NU"` on System.DateModified), so "last 30 days" stays relative when reopened.
- `leafCondition` attributes: property, propertyType, operator (e.g. `eq`, `wordmatch`, `imp`), value, valueType.

### 8.3 search-ms: URI (what Explorer's address bar holds during a search)

From https://learn.microsoft.com/en-us/windows/win32/search/getting-started-with-parameter-value-arguments:

```
search-ms:parameter=value[&parameter=value]&
search-ms:query=seattle&crumb=location:C%3A%5CMyFolder&
search-ms:query=seattle&crumb=kind:pics&
search-ms:query=vacation&subquery=mydepartment.search-ms&
```

| Parameter | Meaning |
|---|---|
| `query` | URL-encoded text typed by the user (AQS by default) |
| `crumb` | scope restriction; full AQS plus a special `location:<path>` form |
| `syntax` | `AQS` (default) or `NQS` |
| `subquery` | path to a .search-ms whose results are the source set |
| `displayname` | name of the search |
| `inputlocale` / `keywordlocale` | LCIDs for query language / keyword language |
| `stackedby` | property to stack by |

Clone use: model "a search" as `(scope paths, recursive flag, query string)` and serialise it to a URL/bookmark/file so Back/Forward, tabs and saved searches all share one representation.

---

## 9. "Search Windows" vs "Search this folder"; Windows 10 differences

### 9.1 Two different search boxes

| | Taskbar / Start search ("Search Windows", Win+S) | Explorer box ("Search <folder>") |
|---|---|---|
| Scope | everything in the index: all indexed files, apps, settings, web (Bing) | the current folder and its subfolders (or Home/This PC, section 2.2) |
| Non-indexed places | never searched: "Start menu search box searches exclude network locations because they exclude all non-indexed locations" (https://learn.microsoft.com/en-us/answers/questions/2602231/a-guide-to-using-windows-search-two-alternatives-t) | crawled live (slow) |
| Results UI | flyout with Best match, category tabs (Apps, Documents, Settings, Web...) "Results for documents and files are show from across your PC and OneDrive" (https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/find-your-files-and-apps-in-windows) | full Explorer view with columns, sorting, grouping |
| Query language | AQS works ("You can use AQS from the search box on the Start menu or from within Explorer, the syntax is the same", https://learn.microsoft.com/en-us/archive/blogs/alanlemarquand/using-advanced-query-syntax-to-find-files-in-windows-7) | AQS |
| 2026 status | new Windows Search (Insider) finds files after 2 characters and does substring matching (https://www.windowslatest.com/2026/07/19/windows-11s-slowest-feature-is-about-to-get-dramatic-speed-improvements-and-its-file-explorer-search/) | still word-prefix; This PC search moving to the index in Insider builds (section 2.2) |

- Windows 7-10 linked the two: from a Start search, "See more results" opened the same query in an Explorer results window (Content view, highlighted terms). (https://www.computerhope.com/tips/tip106.htm via search summary)
- For the macOS clone: "Search this folder" = the Explorer box. "Search Windows" maps to Spotlight (Cmd+Space) and does not need to be rebuilt; a clone could offer an "everywhere" scope (This PC) that runs the same query over the whole Spotlight index.

### 9.2 Windows 10 differences that matter for a clone

- **Ribbon instead of a menu:** Windows 10 shows a Search tab (Location / Refine / Options) as soon as the box is focused, including **Recent searches**, **Save search**, **Open file location**, **Search again in**, and **Other properties**. Windows 11 shows a smaller Search options menu only after a search runs, and moved Save search / Open file location to right-click. (sections 5, 8)
- **Typing:** Windows 10 1909+ shows a dropdown of suggested files and history and fills the view only on Enter; Windows 11 (2023+) fills the view live. (section 3)
- **Default results view:** Windows 10 could be set to Details for search results and keep it; Windows 11 always opens Content view ("Windows 10 had this function", https://learn.microsoft.com/en-us/answers/questions/1539317/make-windows-11-show-search-results-in-details-vie).
- **Folder column format:** Windows 10 showed the full path form users expect; Windows 11 shows "name (parent path)" (https://learn.microsoft.com/en-us/answers/questions/3948497/how-to-set-the-folder-field-format-in-search).
- **Size buckets:** identical in Windows 10 1809+ and Windows 11 (6.5).
- **Settings location:** Windows 10 Settings > Search > Searching Windows; Windows 11 Settings > Privacy & security > Searching Windows. Both have Classic/Enhanced.

---

## 10. macOS mapping: Spotlight, NSMetadataQuery, mdfind

Everything marked **[tested]** was run on this Mac (macOS 15.4.1, build 24E263) against a probe folder of 20 test files, with both `mdfind` and a compiled Swift `NSMetadataQuery` probe. The probe script is at `/private/tmp/claude-501/-Users-anshul-Anshul-Code-fuck-finder/89435d14-36b6-4d4e-b0d7-24016200ecdd/scratchpad/scripts/mdq.swift`.

### 10.1 The query language (MDQuery strings)

From Apple's "File Metadata Query Expression Syntax" (https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryFormat.html):

- Form: `attribute == value`, operators `== != < > <= >=` (ordering only on numbers/dates) and `InRange(attr, min, max)`.
- Combine with `&&` and `||`, parentheses. **[tested]** `!( ... )` and `!=` also work as NOT.
- Value modifiers after the closing quote: `c` case-insensitive, `d` diacritic-insensitive. Undocumented but used by Spotlight itself: `w` word-based. `mdfind -interpret search` shows the Spotlight menu's own query: `(* = search* cdw || kMDItemTextContent = search* cdw)` (`man mdfind`). `w` splits words at spaces, underscore, hyphen and CamelCase changes (https://eclecticlight.co/2025/06/06/how-to-search-successfully-in-spotlight-query-languages/).
- Wildcards inside strings: `*` (many chars), `?` (one char). `"paris*"` = starts with, `"*paris"` = ends with, `"*paris*"` = contains.
- `*` as the attribute means "any key in the item" and only works with `==` (https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Predicates/Articles/pSpotlightComparison.html). **[tested]** `* == "quarter*"cdw` matched the file *name* but not the same word in file *contents*. You must OR in `kMDItemTextContent` yourself, as Spotlight's own UI query does.
- Dates: `$time.now`, `$time.today`, `$time.yesterday`, `$time.this_week`, `$time.this_month`, `$time.this_year`, each with an offset, e.g. `$time.today(-1)`, `$time.this_week(-1)`, `$time.now(-3600)` (seconds), plus `$time.iso(...)`. "The value of the $time variable is set when the query is first executed."

### 10.2 What the tests showed (important gotchas)

| Test | Result | Consequence for the clone |
|---|---|---|
| `kMDItemDisplayName == "bert*"cdw` | Bert, Bertie, my_bert_file, nested-bert; **not** Albert | same word-prefix rule as Windows (6.6) |
| `"image*"cdw` vs `MyImageFactory.txt` | **matches** | Spotlight splits CamelCase; Windows does not. To match Windows exactly, post-filter with a Windows-style tokenizer (split only on whitespace/punctuation) |
| `"12345*"cdw` vs `invoicenumber12345.txt` | **matches** | Spotlight splits letter-to-digit; Windows does not (6.6). Same post-filter fix |
| `"*bert*"cd` | includes Albert | `*x*` = substring, like Windows `*bert*` |
| `kMDItemFSName == "*.txt"c` | all .txt | extension filter works |
| `kMDItemFSSize > 10000000`, `== 0`, `>= 1 && <= 16384` | correct | size comparisons and buckets work |
| `InRange(kMDItemFSSize, 1, 16384)` | **0 results in `mdfind`**, correct in `NSMetadataQuery` (becomes `BETWEEN {1, 16384}`) | use `>= && <=`, or InRange only through NSMetadataQuery |
| `kMDItemFSContentChangeDate == $time.today` / `== $time.this_week` / `== $time.this_week(-1)` | **0 results** in both tools. `$time.today` resolves to one instant (`$time.iso(2026-11-04T17:00:00Z)` = local midnight here) | never use `==` with `$time`. Write `>= $time.today && < $time.today(1)` **[tested, correct]** |
| `InRange(date, $time.today, $time.today(1))` | becomes `BETWEEN {0, 0}`, 0 results | do not use InRange with `$time` |
| `$time.this_week` | = Sunday 00:00 local on this Mac | week start follows the Mac's calendar. Compute week/month bounds yourself with `Calendar.current` and pass `$time.iso(...)` so they match the clone's locale |
| `kMDItemTextContent == "paris*"cdw`, `"cafe*"cdw` (file has "café"), `"*rope*"cd` | correct | content prefix, diacritic-folding, and in-word substring all work |
| `kMDItemTextContent == "europe trip"cdw`, `"*europe trip*"cd`, `"europe trip budget"cd` | **0 results** (the file contains "Europe trip budget") | Spotlight cannot match multi-word phrases in contents. Query each word with `&&` for candidates, then open the candidate files and check the exact phrase |
| `kMDItemDisplayName == "*budget 2024*"cd` | correct | phrases in *names* work |
| `kMDItemUserTags == "*"` / `!= "*"` | has tags / has no tags | AQS `tag:[]` works |
| `kMDItemFSName == "*"` | 0 results (`kMDItemDisplayName == "*"` works) | test existence on DisplayName |
| `kMDItemPath == "*deeper*"` | 0 results | the path is not searchable. Scope with `searchScopes`/`-onlyin`, filter `folder:` by checking `NSMetadataItemPathKey` on results |
| `-onlyin dir` / `searchScopes = [dir]` | recursive | "Current folder" scope = post-filter on parent directory, or list the folder directly |
| files in `/private/tmp` | 0 results (not indexed) | non-indexed volumes and folders need a live walk |
| `.dotbert.txt`, `.hiddendir/hiddenbert.txt` | not returned | dot-files and dot-folders are not indexed. Live walk when "show hidden items" is on |
| `chflags hidden` file | returned; `kMDItemFSInvisible` = 0 | hidden-flag filtering must use `URLResourceValues.isHidden` |
| `node_modules/pkg/modbert.txt` | returned | ordinary folders are indexed |
| a .txt inside `archive.zip` | not returned | zip contents need a live read (the "Zipped (compressed) folders" toggle) |
| `kMDItemContentTypeTree == "public.archive"` | archive.zip **and** a raw `big.bin` | UTType kinds are broader than Windows KindMap; use an extension table for exact Windows Kind |
| `mdfind -interpret 'name:bert'`, `'tag:vacation'` | correct results, but with "Couldn't determine the mapping between prefab keywords and predicates" | Spotlight's own `kind:/author:/created:` keyword syntax exists (https://support.apple.com/guide/mac-help/narrow-search-results-mh15155/mac) but is fragile. Translate AQS to raw MDQuery strings yourself |
| `NSPredicate(fromMetadataQueryString: "kMDItemDisplayName == \"bert*\"cdw")` | becomes `kMDItemDisplayName BEGINSWITH[cdlw] "bert"`; results in 0.03 to 0.9 s | you can keep building MDQuery strings and convert them. `cdw` survives the conversion |

### 10.3 NSMetadataQuery mechanics

Apple's Spotlight query guide (https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html):

- `searchScopes`: array of URLs or constants (`NSMetadataQueryUserHomeScope`, `NSMetadataQueryLocalComputerScope`, `NSMetadataQueryNetworkScope`, iCloud scopes). Use the current folder URL for "Search <folder>", `NSMetadataQueryLocalComputerScope` for "This PC".
- `predicate`: built from the MDQuery string (`NSPredicate(fromMetadataQueryString:)`) or NSPredicate format (`kMDItemTextContent LIKE[cd] "FooBar"`; in NSPredicate, substring is `CONTAINS`, glob is `LIKE`).
- `sortDescriptors` on metadata keys; `groupingAttributes` gives grouped results (= Explorer "Group by"); `valueListAttributes` gives value counts (useful for building Kind/Type facets). **[tested]** valueLists returned content-type counts.
- Two phases: "an initial results gathering phase and a live-update phase". `NSMetadataQueryDidFinishGathering` fires when the first pass is done, then `NSMetadataQueryDidUpdate` fires as files change, with added/changed/removed item keys. Batch via `notificationBatchingInterval`. Call `disableUpdates()` before reading `results`, then `enableUpdates()`.
- Mapping to Explorer UX: start a new query on each debounced keystroke (`stop()` the old one). Show partial results on `NSMetadataQueryGatheringProgress`. That gives the incremental fill and green-bar progress of section 4.1: gathering = bar running, DidFinishGathering = bar done.

### 10.4 Architecture for a faithful clone

```
 typed text ──► AQS parser (6.7) ──► query plan
                                   ├─► Spotlight part  (NSMetadataQuery, scope = folder, recursive)
                                   │      MDQuery string from table 11
                                   ├─► Live-walk part  (FileManager enumerator) for:
                                   │      non-indexed volumes/folders, dot/hidden items, zip contents,
                                   │      properties Spotlight lacks (access date, attributes)
                                   └─► Post-filters on candidates:
                                          Windows tokenizer (no CamelCase/digit splits), exact phrases,
                                          Current-folder depth, folder:/path: substrings
                                   ▼
                     merge + dedupe by path ──► results view (Content view default, Folder column)
```

- Indexed check per volume: `mdutil -s <mountpoint>`, or try the query and fall back to a walk when the volume reports indexing disabled. No public API lists per-folder Spotlight Privacy exclusions, so dot-folders, `/private/tmp`, network shares and external drives with indexing off should always take the walk path. (/tmp result **[tested]**)
- Windows does the same merge: "can seamlessly search indexed as well as non-indexed locations" (https://en.wikipedia.org/wiki/Windows_Search).


Two more test results that change the mapping:

- **`?` single-character wildcard does not work** in Spotlight on macOS 15.4.1, although Apple's doc lists it. `kMDItemFSName == "B?rt*"c` became `BEGINSWITH[c] "B?rt"` and returned nothing; `"B?rt.txt"c` also returned nothing. **[tested]** Send `*` in place of each `?` to Spotlight, then post-filter with a real glob/regex.
- `kMDItemLastUsedDate >= $time.today` returned nothing for files created and read today by scripts. It records opens through LaunchServices (Finder, apps), not file-system access, so it cannot stand in for Windows "Date accessed". **[tested]**

---

## 11. AQS to Spotlight mapping table

Legend: **Full** = one Spotlight query does it. **Partial** = Spotlight gives candidates, then a cheap post-filter on the results (no disk walk). **Walk** = needs a live file-system walk (FileManager enumerator / stat / reading files), because Spotlight has no data for it.

| AQS feature | Windows meaning | Spotlight / NSMetadataQuery equivalent | Status |
|---|---|---|---|
| bare term `bert` | word-prefix over name + properties + indexed contents | `(* == "bert*"cdw \|\| kMDItemTextContent == "bert*"cdw)` (Spotlight's own UI query, `man mdfind`) | Partial: drop CamelCase/digit-split matches with a Windows tokenizer to be exact |
| several terms `a b` / `AND` | all must match | `(...a...) && (...b...)` | Full |
| `OR` | either | `\|\|` | Full |
| `NOT x` / `-x` | exclude | `!( ... )` or `!=` **[tested]** | Full |
| `( )` grouping | grouping | `( )` | Full |
| left-to-right AND/OR binding | `a AND b OR c` = `(a AND b) OR c` | parser emits explicit parentheses | Full (parser job) |
| `"exact phrase"` in names | phrase | `kMDItemDisplayName == "*exact phrase*"cd` **[tested]** | Full |
| `"exact phrase"` in contents | phrase | words ANDed on `kMDItemTextContent`, then read candidate text and check phrase (Spotlight phrase match returned 0 **[tested]**) | Partial + read files |
| `*` wildcard | DOS `*` | `*` inside the string **[tested]** | Full |
| `?` wildcard | one char | send `*`, then regex post-filter (`?` is literal in Spotlight **[tested]**) | Partial |
| `name:` / `filename:` | file name | `kMDItemFSName == "x*"cdw` (or `"*x*"cd` with wildcards) | Full / Partial (tokenizer) |
| `ext:pdf` / `*.pdf` | extension | `kMDItemFSName == "*.pdf"c` **[tested]** | Full |
| `type:"PDF Document"` | Type column text | `kMDItemKind == "PDF*"cd` (localised Kind string, wording differs from Windows) | Partial: better to map Windows type names to extensions/UTTypes |
| `kind:picture/music/video/movie` | System.Kind | `kMDItemContentTypeTree == "public.image"` / `"public.audio"` / `"public.movie"` | Full (UTType trees are broader, e.g. `public.archive` matched a raw `.bin` **[tested]**) |
| `kind:folder` | folders | `kMDItemContentType == "public.folder"` **[tested]** | Full |
| `kind:document` | KindMap "document" extensions | OR of `kMDItemContentTypeTree` = `public.text`, `com.adobe.pdf`, `public.composite-content`, `public.spreadsheet`, `public.presentation` ... or a port of Windows KindMap as an extension list on `kMDItemFSName` | Partial (no 1:1 category) |
| `kind:program/link/contact/email/calendar/playlist` | KindMap | `com.apple.application-bundle`/`public.executable`; `com.apple.alias-file`/`public.symlink`/`com.apple.web-internet-location`; `public.vcard`; `com.apple.mail.emlx`; `public.calendar-event`; `public.playlist` (UTI choices are mine, unverified) | Partial |
| `kind:game/feed/journal/note/task/im/tv/webhistory/searchfolder/unknown` | KindMap | no macOS category; use an extension table, `searchfolder` = `.savedSearch` files | Partial / no equivalent |
| `size:>50MB`, `<`, `>=`, `<=` | System.Size (bytes, binary units) | `kMDItemFSSize > 52428800` **[tested]** | Full |
| `size:10MB..20MB` | inclusive range | `kMDItemFSSize >= a && kMDItemFSSize <= b` **[tested]**, or `InRange(kMDItemFSSize,a,b)` in NSMetadataQuery only (fails in `mdfind` **[tested]**) | Full |
| `size:empty/tiny/small/medium/large/huge/gigantic` | buckets 6.5 | `== 0`; `>= 1 && <= 16384`; `> 16384 && <= 1048576`; `> 1048576 && <= 134217728`; `> 134217728 && <= 1073741824`; `> 1073741824 && <= 4294967296`; `> 4294967296` | Full |
| `datemodified:` / `modified:` | last write time | `kMDItemFSContentChangeDate` (file-system date; `kMDItemContentModificationDate` can come from document metadata) | Full |
| `datecreated:` / `created:` | creation time | `kMDItemFSCreationDate` **[tested]** | Full |
| `dateaccessed:` | last access time | none (`kMDItemLastUsedDate` = last opened via LaunchServices, not atime **[tested]**) | Walk (`URLResourceKey.contentAccessDateKey`) |
| `datetaken:` | EXIF capture date | `kMDItemContentCreationDate` on images (my mapping; unverified) | Full |
| `date:` | "main" date of the item | `kMDItemContentCreationDate \|\| kMDItemFSContentChangeDate` (approximation) | Partial |
| `today`, `yesterday` | calendar day | `>= $time.today && < $time.today(1)`; `>= $time.today(-1) && < $time.today` **[tested]** (never `== $time.x` **[tested]**) | Full |
| `this week`, `last week`, `this month`, `last month`, `this year`, `last year`, `next ...` | calendar periods | `>= $time.this_week && < $time.this_week(1)`, `>= $time.this_week(-1) && < $time.this_week`, same for month/year, or `$time.iso()` bounds computed with the clone's `Calendar` | Full |
| weekday/month names, `Monday..Wednesday`, `February` | relative to now | compute bounds in the app, send `$time.iso()` | Full (app computes) |
| absolute dates `1/26/2010`, `date:>11/13/21`, ranges `a..b` | locale-parsed | parse with the user's locale, send `$time.iso()` bounds | Full (app parses) |
| `author:` / `by:` | System.Author | `kMDItemAuthors == "x*"cdw` | Full |
| `title:` / `subject:` | System.Title | `kMDItemTitle == "x*"cdw` | Full |
| `tag:` / `tags:` / `keywords:` | System.Keywords (Tags column) | `kMDItemUserTags == "x*"cdw \|\| kMDItemKeywords == "x*"cdw` **[tested for UserTags]** | Full |
| `tag:[]` / `author:[]` | has no value | `kMDItemUserTags != "*"` **[tested]** | Full |
| `comments:` | System.Comment | `kMDItemComment \|\| kMDItemFinderComment` | Full |
| `rating:` | stars | `kMDItemStarRating` | Full (rarely set on macOS) |
| `content:` | contents only | `kMDItemTextContent == "x*"cdw` **[tested]**; in-word `"*x*"cd` **[tested]** | Full (indexed types only) |
| `folder:` / `path:` / `under:` / `in:` | folder path text | not queryable (`kMDItemPath` returned 0 **[tested]**); filter `NSMetadataItemPathKey` on results | Partial |
| scope: current folder + subfolders | default | `searchScopes = [folderURL]` / `-onlyin` (recursive **[tested]**) | Full |
| scope: **Current folder** only | one level | recursive query, keep only items whose parent is the folder, or list the folder with FileManager | Partial |
| scope: This PC / Home | everywhere | `NSMetadataQueryLocalComputerScope` / `UserHomeScope` | Full |
| `artist:`, `album:`, `genre:`, `year:`, `track:`, `duration:`, `bitrate:` | music | `kMDItemAuthors`, `kMDItemAlbum`, `kMDItemMusicalGenre`, `kMDItemRecordingYear`, `kMDItemAudioTrackNumber`, `kMDItemDurationSeconds`, `kMDItemAudioBitRate` (attribute names checked in the local schema with `mdimport -A`) | Full |
| `width:`, `height:`, `dimensions:`, `orientation:`, `cameramake:`, `cameramodel:` | pictures | `kMDItemPixelWidth`, `kMDItemPixelHeight`, both, `kMDItemOrientation`, `kMDItemAcquisitionMake`, `kMDItemAcquisitionModel` (names checked) | Full |
| `slidecount:` | presentations | `kMDItemNumberOfPages` where an importer sets it (unverified for .pptx) | Partial |
| `~=` `~~` contains | substring | `"*x*"cd` | Full |
| `~<` value starts with | whole-value prefix | `"x*"cd` (no `w`) | Full |
| `~>` value ends with | suffix | `"*x"cd` | Full |
| `~!` not contains | | `!= "*x*"cd` | Full |
| `$=` word equal / `$<` word starts with | word match | `"x"cdw` / `"x*"cdw` | Full (CamelCase caveat) |
| `=` exact | exact value | `== "x"c` | Full |
| `System.*` canonical properties | any shell property | map known ones to kMDItem keys; unknown ones have no equivalent | Partial |
| non-indexed locations (network, external with indexing off, `/tmp`, Privacy-excluded) | live crawl | Spotlight returns nothing **[tested for /tmp]** | Walk |
| **File contents** toggle (contents in non-indexed places) | read every file | read files during the walk (text, plus PDFKit/NSAttributedString for rich types) | Walk |
| **System files** toggle | include system directories | Spotlight does not index most system areas; walk them | Walk |
| **Zipped (compressed) folders** toggle | look inside archives | not indexed **[tested]**; read the zip directory during the walk | Walk |
| hidden items / `attributes:H` | Hidden attribute | dot-files not indexed **[tested]**; `chflags hidden` not reflected in `kMDItemFSInvisible` **[tested]**; use `URLResourceValues.isHidden` | Walk |
| `isdeleted:` / Recycle Bin | items in Recycle Bin | `~/.Trash` is a dot-folder, so not indexed (inferred from the dot-folder test) | Walk |
| relevance ranking | Windows ranks results | no rank from NSMetadataQuery; build a simple score (name match > property > content) | Partial (app) |
| live results while typing | Windows 11 | restart NSMetadataQuery per debounced keystroke; use gathering notifications for progress | Full |
| Natural Query Syntax | off by default | skip | n/a |

### 11.1 AQS features with no Spotlight equivalent (need a live walk or app logic)

1. Anything in **non-indexed locations**: network shares, external drives with indexing off, `/private/tmp`, dot-folders, Privacy-excluded folders.
2. **Hidden/system items** and the System files toggle.
3. **Inside zip/cab archives** (Zipped folders toggle).
4. **Contents in non-indexed locations** (File contents toggle), and **exact multi-word phrases in contents** anywhere (Spotlight gives candidates; the app must read the text).
5. **Date accessed** (`dateaccessed:`).
6. **Recycle Bin** (`isdeleted:`), because `~/.Trash` is not indexed.
7. **`?` single-character wildcard** (post-filter, no walk).
8. **Path filters** `folder:` / `path:` / `in:` and **Current folder** depth (post-filter on result paths, no walk).
9. **Exact Windows tokenization** (no CamelCase/digit splitting) and **Windows Kind categories without a UTType** (game, feed, journal, note, task, im, tv, web history): app logic over the candidates.
10. **Relevance ranking**: app logic.

