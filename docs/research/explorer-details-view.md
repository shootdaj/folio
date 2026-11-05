# Windows 11 File Explorer: Details view columns, sort, filter, group

Research for a macOS clone. Goal: copy Explorer's Details-view behaviour faithfully ("all columns are sortable and filterable").
Started 2026-11-05. Complete; see "Confidence notes" at the end for what still needs a real Win11 check.

## TL;DR for the clone
```
header click ──► sort by column (property default direction) ──► click again = reverse
shift+click  ──► add secondary key (GUI allows 4)
hover header ──► chevron at right edge ──► checkbox popover of buckets
                 (Name 0-9/A-H/I-P/Q-Z/Other · Size Empty..Gigantic · Date calendar + Today..A long time ago · Type distinct)
                 OR within a column, AND across columns, header shows ✓ while filtered
group by     ──► same buckets, "Label (count)" headers, collapsible, Expand/Collapse all
view memory  ──► Explorer: per folder (Bags, 5000 cap) + per template; no off switch since Win7
                 Clone: ONE global view, never persist filters
```

## 1. Header click sort

### Click behaviour
- Click a column header: sorts by that column. Click the same header again: reverses direction. The sorted column shows a small chevron/arrow in the header (up = ascending, down = descending; in Win11 it sits centred above the header text). [S1][S2]
- Clicking a *different* header makes it the primary sort, starting in that **property's default direction**: each propdesc has `displayInfo/@defaultSortDirection` = Ascending (default) or Descending. Prism's Win11 measurement: "in Downloads, a first click on Date modified starts newest first, as File Explorer's does". [S5][S13]
- Menu labels come from `labelInfo/@sortDescription`: General → "Sort going up / Sort going down", AToZ → "A on top / Z on top", OldestNewest → "Oldest on top / Newest on top", SmallestLargest → "Smallest on top / Largest on top", LowestHighest. Win11's command bar simply shows "Ascending / Descending". [S72][S22]
- NSTableView maps directly: the first click uses the prototype's `ascending` value, so give Date/Size prototypes the Explorer default.
- **Shift+click a second header adds a secondary sort key** (multi-column sort). Common use: Shift+click Name so folders stay grouped on top, then click Date modified to flip date direction. Reported on Microsoft Q&A and ElevenForum; no official MS doc. [S2][S3]
- Same options exist in the command bar: **Sort ▸ Name / Date modified / Type / Size / ... ▸ Ascending / Descending / More...** and right-click on empty space ▸ **Sort by** ▸ same list. [S1]

### Folders-first rule
- Explorer "tries to keep all folders together" (Raymond Chen). Folders form a block that is sorted among themselves, files form a second block. [S4]
- The block follows the direction: **ascending → folders on top; descending → folders at the bottom** (the whole list is reversed, folders included). Users repeatedly ask for "folders always on top regardless of direction" and the only built-in workaround is the Shift+click-Name secondary sort. [S2][S3]
- Exception measured on Win11 by Prism: *inside a Group-by group*, Explorer puts files before folders. [S5]
- Clone decision: the requester wants folders-first; implement "folders first in ascending, folders last in descending" for Explorer fidelity, or offer "always first" as a toggle (Explorer has no such toggle).

### Natural (numeric) name sort
- Since Windows XP, Explorer treats runs of digits in names as numbers: `file2` < `file10` < `file139`. Before XP it was plain `lstrcmpi` (so `file139` < `file20`). [S6]
- Locale-aware, case-insensitive. Hyphens and apostrophes get special treatment (inherited from `lstrcmpi`/CompareString word sort). [S6]
- Vista+ rule: **period sorts before space**, so `File.txt` < `File 1.txt`. [S6]
- Decimal points are NOT read as decimals: `1.5` sorts before `1.25` (5 < 25 as separate integers). Hex names like `1040A` sort after `1040`. [S6]
- Policy "Turn off numerical sorting in File Explorer" (Computer Configuration ▸ Administrative Templates ▸ Windows Components ▸ File Explorer) reverts to char-by-char: DWORD `NoStrCmpLogical = 1` under `HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` (gives `111 < 22 < 3`). [S6][S73]
- The public API that matches this is `StrCmpLogicalW` (shlwapi); reimplementations differ on names starting with special characters. [S7]
- macOS equivalent: `localizedStandardCompare:` (Finder's own sort) is the closest match; it is also case-insensitive, locale-aware and numeric. Differences vs Explorer to test: leading punctuation, `.` vs space, full-width digits.

### Tie-breaking and stability
- Columns with many equal values declare a tie-breaker. **Type ties are broken by Name**, and the tie-breaker reverses with the primary sort: Type descending puts `file2.txt` before `file1.txt` (changed in Windows 7; XP/Vista kept name ascending). [S6]
- So Explorer's sort is not a "stable sort of the previous order"; it is a deterministic multi-key compare: primary column, then the column's tie-break (Name), all in the same direction. Shift+click keys come after.
- Comparator must be a total order or results are inconsistent (Chen). [S4]
- Prism's own choice for date ties = name; Explorer's date tie-breaker is not documented. [S5]

## 2. Right-click header menu

Right-click anywhere on the header row:
```
 Size column to fit         ← fits the column under the cursor to its widest cell
 Size all columns to fit    ← fits every visible column
 ──────────────
 ✓ Name                      (greyed: Name cannot be hidden)
 ✓ Date modified
 ✓ Type
 ✓ Size
   Date created
   Authors
   Tags
   Title
   ... (the folder type's "common" columns)
 ──────────────
 More...                    ← opens Choose Details
```
- A check mark means the column is visible; clicking an item toggles it. [S37][S38]
- The middle list is per folder type: the template's `ColumnList` marks each property `0` = visible by default, `1` = offered in this header menu but hidden. Anything else is only reachable via **More...** [S39]
- Name cannot be removed (Choose Details greys it out). [S40]
- "Size all columns to fit" is also on the classic ribbon View tab and on the keyboard as **Ctrl + Numpad +**. It is a one-shot *verb*, not a mode: it measures current contents; new long names later are not re-fitted. [S38][S41]
- Win11's command bar dropped the old "More..." entry from **Sort**; the header right-click ▸ More... remains. [S1]

## 3. Column chooser dialog ("More...")

### Layout (title "Choose Details")
```
┌ Choose Details ──────────────────────────────── ✕ ┐
│ Select the details you want to display for the    │
│ items in this folder.                              │
│ Details:                                           │
│ ┌──────────────────────────────┐  [ Move Up   ]    │
│ │☑ Name            (greyed)    │  [ Move Down ]    │
│ │☑ Date modified               │  [ Show      ]    │
│ │☑ Type                        │  [ Hide      ]    │
│ │☑ Size                        │                    │
│ │☐ #                           │                    │
│ │☐ 35mm focal length           │                    │
│ │☐ Account name   ...          │                    │
│ └──────────────────────────────┘                    │
│ Width of selected column (in pixels): [ 238 ]      │
│                                 [  OK  ] [ Cancel ]│
└────────────────────────────────────────────────────┘
```
- Visible columns are listed first, in their current left→right order; all others follow alphabetically. Checking/unchecking = Show/Hide. Move Up/Down reorders (top of list = leftmost). Width field sets the selected column's pixel width. [S38][S42]
- **Name cannot be unchecked**. Legacy dialogs assume Name is the first column; Explorer warns if it is not. [S40]
- The list is filtered to properties with `isViewable="true"` in their propdesc. [S12]
- What you get is per folder (and with Apply to Folders, per template). Pictures folders surface Date taken, Dimensions; Music surfaces #, Contributing artists, Album. [S37]

### Full property list (Windows 10/11, `Shell.Application` `GetDetailsOf(null, i)` on C:, index: name) [S43]
Gaps in numbering are as published; the list varies slightly by namespace and Windows build. This is effectively the "~300 columns" set.

```
0 Name            1 Size              2 Item type          3 Date modified
4 Date created    5 Date accessed     6 Attributes         7 Offline status
8 Availability    9 Perceived type   10 Owner             11 Kind
12 Date taken    13 Contributing artists 14 Album         15 Year
16 Genre         17 Conductors       18 Tags              19 Rating
20 Authors       21 Title            22 Subject           23 Categories
24 Comments      25 Copyright        26 #                 27 Length
28 Bit rate      29 Protected        30 Camera model      31 Dimensions
32 Camera maker  33 Company          34 File description  35 Masters keywords
36 Masters keywords 42 Program name  43 Duration          44 Is online
45 Is recurring  46 Location         47 Optional attendee addresses
48 Optional attendees 49 Organizer address 50 Organizer name 51 Reminder time
52 Required attendee addresses 53 Required attendees 54 Resources
55 Meeting status 56 Free/busy status 57 Total size       58 Account name
60 Task status   61 Computer         62 Anniversary       63 Assistant's name
64 Assistant's phone 65 Birthday     66 Business address  67 Business city
68 Business country/region 69 Business P.O. box 70 Business postal code
71 Business state or province 72 Business street 73 Business fax
74 Business home page 75 Business phone 76 Callback number 77 Car phone
78 Children      79 Company main phone 80 Department      81 E-mail address
82 E-mail2       83 E-mail3          84 E-mail list       85 E-mail display name
86 File as       87 First name       88 Full name         89 Gender
90 Given name    91 Hobbies          92 Home address      93 Home city
94 Home country/region 95 Home P.O. box 96 Home postal code 97 Home state or province
98 Home street   99 Home fax        100 Home phone       101 IM addresses
102 Initials    103 Job title       104 Label            105 Last name
106 Mailing address 107 Middle name 108 Cell phone       109 Nickname
110 Office location 111 Other address 112 Other city     113 Other country/region
114 Other P.O. box 115 Other postal code 116 Other state or province 117 Other street
118 Pager       119 Personal title  120 City             121 Country/region
122 P.O. box    123 Postal code     124 State or province 125 Street
126 Primary e-mail 127 Primary phone 128 Profession      129 Spouse/Partner
130 Suffix      131 TTY/TTD phone   132 Telex            133 Webpage
134 Content status 135 Content type 136 Date acquired    137 Date archived
138 Date completed 139 Device category 140 Connected     141 Discovery method
142 Friendly name 143 Local computer 144 Manufacturer    145 Model
146 Paired      147 Classification  148 Status           149 Status
150 Client ID   151 Contributors    152 Content created  153 Last printed
154 Date last saved 155 Division    156 Document ID      157 Pages
158 Slides      159 Total editing time 160 Word count    161 Due date
162 End date    163 File count      164 File extension   165 Filename
166 File version 167 Flag color     168 Flag status      169 Space free
172 Group       173 Sharing type    174 Bit depth        175 Horizontal resolution
176 Width       177 Vertical resolution 178 Height       179 Importance
180 Is attachment 181 Is deleted    182 Encryption status 183 Has flag
184 Is completed 185 Incomplete     186 Read status      187 Shared
188 Creators    189 Date            190 Folder name      191 Folder path
192 Folder      193 Participants    194 Path             195 By location
196 Type        197 Contact names   198 Entry type       199 Language
200 Date visited 201 Description    202 Link status      203 Link target
204 URL         208 Media created   209 Date released    210 Encoded by
211 Episode number 212 Producers    213 Publisher        214 Season number
215 Subtitle    216 User web URL    217 Writers          219 Attachments
220 Bcc addresses 221 Bcc           222 Cc addresses     223 Cc
224 Conversation ID 225 Date received 226 Date sent      227 From addresses
228 From        229 Has attachments 230 Sender address   231 Sender name
232 Store       233 To addresses    234 To do title      235 To
236 Mileage     237 Album artist    238 Sort album artist 239 Album ID
240 Sort album  241 Sort contributing artists 242 Beats-per-minute 243 Composers
244 Sort composer 245 Disc          246 Initial key      247 Part of a compilation
248 Mood        249 Part of set     250 Period           251 Color
252 Parental rating 253 Parental rating reason 254 Space used 255 EXIF version
256 Event       257 Exposure bias   258 Exposure program 259 Exposure time
260 F-stop      261 Flash mode      262 Focal length     263 35mm focal length
264 ISO speed   265 Lens maker      266 Lens model       267 Light source
268 Max aperture 269 Metering mode  270 Orientation      271 People
272 Program mode 273 Saturation     274 Subject distance 275 White balance
276 Priority    277 Project         278 Channel number   279 Episode name
280 Closed captioning 281 Rerun     282 SAP              283 Broadcast date
284 Program description 285 Recording time 286 Station call sign 287 Station name
288 Summary     289 Snippets        290 Auto summary     291 Relevance
292 File ownership 293 Sensitivity  294 Shared with      295 Sharing status
297 Product name 298 Product version 299 Support link    300 Source
301 Start date  302 Sharing         303 Availability status 304 Status
305 Billing information 306 Complete 307 Task owner      308 Sort title
309 Total file size 310 Legal trademarks 311 Video compression 312 Directors
313 Data rate   314 Frame height    315 Frame rate       316 Frame width
317 Spherical   318 Stereo          319 Video orientation 320 Total bitrate
```

### Mapping the common ones to macOS sources (for the clone)
| Explorer column | Windows property | macOS source |
|---|---|---|
| Name | System.ItemNameDisplay | `URLResourceKey.localizedNameKey` / `nameKey` |
| Date modified / created / accessed | System.DateModified / DateCreated / DateAccessed | `contentModificationDateKey` / `creationDateKey` / `contentAccessDateKey` |
| Type | System.ItemTypeText | `localizedTypeDescriptionKey` (UTType description) |
| Size | System.Size | `fileSizeKey` / `totalFileAllocatedSizeKey` (folders: blank) |
| Attributes | System.FileAttributes (R H S A ...) | `isHiddenKey`, `isUserImmutableKey`, etc. (map to letters) |
| Owner | System.FileOwner | `FileManager.attributesOfItem[.ownerAccountName]` |
| Authors, Title, Subject, Tags, Comments | System.Author / Title / Subject / Keywords / Comment | Spotlight `kMDItemAuthors`, `kMDItemTitle`, `kMDItemSubject`, Finder tags `tagNamesKey`/`kMDItemKeywords`, `kMDItemFinderComment` |
| Rating | System.Rating | `kMDItemStarRating` (rarely set) |
| Dimensions, Width, Height | System.Image.Dimensions | `kMDItemPixelWidth` / `kMDItemPixelHeight` |
| Length / Duration | System.Media.Duration | `kMDItemDurationSeconds` |
| Bit rate / Total bitrate | System.Audio.EncodingBitrate | `kMDItemAudioBitRate` / `kMDItemTotalBitRate` |
| Frame rate, Frame width/height | System.Video.FrameRate ... | AVFoundation track `nominalFrameRate`, `naturalSize` |
| Date taken, Camera model/maker, F-stop, ISO, Focal length | System.Photo.DateTaken ... | `kMDItemContentCreationDate` / ImageIO EXIF dict |
| Album, Artist (Contributing artists), # (Track), Genre, Year, Album artist | System.Music.* | `kMDItemAlbum`, `kMDItemAuthors`, `kMDItemAudioTrackNumber`, `kMDItemMusicalGenre`, `kMDItemRecordingYear` |
| Folder path / Path / Folder name | System.ItemFolderPathDisplay | parent URL path |
| Link target | System.Link.TargetParsingPath | symlink: `destinationOfSymbolicLink`; alias: `URL(resolvingAliasFileAt:)` |
| File extension | System.FileExtension | `pathExtension` |

## 4. Per-folder-type default columns and "Optimize this folder for"

### Templates
- Right-click folder ▸ Properties ▸ **Customize** ▸ "Optimize this folder for:" **General items / Documents / Pictures / Music / Videos**, plus checkbox "Also apply this template to all subfolders" (reported not to work in Win11). [S33][S40]
- Without a manual choice, **folder type discovery** sniffs content (e.g. a folder of only audio files becomes Music). Downloads is its own type; in Win11 all Downloads subfolders are type Downloads too. [S40][S44]
- Defaults live in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{GUID}\TopViews\{GUID}` as `LogicalViewMode`, `ColumnList`, `SortByList`, `GroupBy`. 56 folder types exist; 38 have editable views. [S39][S40][S45]
- `ColumnList` syntax: `prop:0(34)System.ItemNameDisplay;0System.DateModified;1System.DateCreated;...` → `0` = visible by default, `1` = offered in header right-click menu, `2` = More... only; `(34)` = width in **ems** (~chars). `SortByList` syntax: `prop:-System.Search.Rank;-System.DateModified;System.ItemNameDisplay` → `-` descending, up to 3 keys stored (GUI Shift+click allows 4). [S39][S40]

### Defaults per template (Windows 10/11)
| Template | GUID | View | Visible columns (in order) | Header-menu extras (`1`) | Sort / Group |
|---|---|---|---|---|---|
| General items (Generic) | {5C4F28B5-F869-4E84-8E60-F11DB97C5CC7} | Details | **Name (34em), Date modified, Type, Size** | Date created, Authors, Tags, Title | Name ↑, no group [S45][S46] |
| Documents | {7D49D726-3C21-4F05-99AA-FDC2C9474656} | Details | Name, Date modified, Type, Size (same as General) | Date created, Authors, Tags, Title | Name ↑ [S46] |
| Pictures | {B3690E58-E961-423B-B687-386EBFD83239} | **Large icons** | Pictures library Details: **Name, Date taken, Tags, Size, Rating** | Type, Date created, Date modified, Date, Folder path, Dimensions | — [S46][S47] |
| Music | {94D6DDCC-4A68-4175-A374-BD584A510B78} | Details | **Name, #, Title, Contributing artists, Album** | Type, Size, Date created, Date modified, Album artist, Bit rate, Genre, Length, Protected, Rating, Year | Name ↑ [S45][S46] |
| Videos | {5FA96407-7E77-483C-AC93-691D05850DE8} | **Large icons** | Not confirmed from a source; observed commonly as Name, Date, Type, Size, Length | — | — [S46] |
| Downloads | {885A186E-A440-4ADA-812B-DB871B942259} | Details | Name, Date modified, Type, Size | — | Sort Date modified, **Group by Date modified** [S44][S46] |
| Search results (generic) | {7FDE1A1E-8B31-49A5-93B8-6BE14CFA4943} | **Content** | adds Folder path, Relevance | — | Rank ↓, Date modified ↓, Name [S46] |

### Clone recommendation
Requester wants one view everywhere: ship the **General items** set (Name, Date modified, Type, Size) as the global default and expose every other column through the header menu + Choose Details. Media columns (Length, Dimensions, Album, ...) appear only when the user adds them, not by content sniffing.

## 5. Header filter dropdown

### Where it is
- Details view only (the filter lives in the column header). [S8][S9]
- Hover a header → a small **down-chevron appears at the right edge of that header cell**. Click it → popover with a checkbox list of values for that column. [S8][S10]
- While Explorer computes the list it can show **"Computing filters..."** (and on slow/non-indexed folders it may close or never finish). [S11]
- Active filter: **the chevron is replaced by a check mark** in that header, and stays visible without hover. [S8][S9]

### What the list contains (driven by the property's `groupingRange` / `filterControl`)
Explorer builds the list from the same buckets it uses for Group by. Each property declares `typeInfo/@groupingRange` = `Discrete | Alphanumeric | Size | Date | TimeRelative | Dynamic | Percent | Enumerated`, and `displayInfo/filterControl` = `Default | Calendar | Rating`. [S12][S13]

| Column (property) | Bucket style | What the checkbox list shows |
|---|---|---|
| Name (`System.ItemNameDisplay`) | Alphanumeric | Letter/number ranges: **0 - 9**, **A - H**, **I - P**, **Q - Z** (plus "Other" for symbols/non-Latin) [S9][S14][S24] |
| Type (`System.ItemTypeText`) | Discrete | One checkbox per distinct type present, e.g. **File folder**, **PDF Document**, **Text Document**. Only types present in the folder are listed. [S8][S15] |
| Size (`System.Size`) | Size (enumRange) | **Empty / Tiny / Small / Medium / Large / Huge / Gigantic** (+ Unspecified for folders). Only buckets with items appear. Ranges below. [S16] |
| Date modified / created / accessed / taken | Date + `filterControl=Calendar` | Calendar picker ("Select a date or date range", click or drag a range) on top, then relative checkboxes: **A long time ago, Earlier this year, Last month, Earlier this month, Last week, Earlier this week, Yesterday, Today** (+ future buckets). Only buckets with items appear. [S17][S18][S19] |
| Rating | `filterControl=Rating` | Star rows (Unrated, 1–5 stars) [S12] |
| Authors, Tags, Album, Artist, Genre, ... | Discrete | Distinct values; multi-value properties (Tags, Authors) list each value separately |
| Length, Bit rate, Dimensions | Dynamic / enumRange | Property-defined ranges |

- **Win11 caveat:** several Win10 1909+ and Win11 users report the date calendar is gone and the Date modified filter only shows relative buckets that exist (e.g. just "Last month" and "A long time ago"). A forum-suggested `EnableDateRangePicker` registry value is unconfirmed. Clone choice: ship the calendar + buckets (Win7–Win10 1903 behaviour), it is strictly more useful. [S18][S19]
- **Win10 caveat:** on some machines the Name/Type/Folder path filters hang on "Computing filters..." while Date modified and Size work (non-indexed folders). Not a behaviour to copy. [S11]

### Size buckets (exact bytes)
Windows 10 1809 and later (= Windows 11), from `System.Size` propdesc `enumRange` minValues [S16]:

| Bucket | Label text | minValue (bytes) | Effective range |
|---|---|---|---|
| Empty | Empty (0 KB) | 0 | exactly 0 |
| Tiny | Tiny (0 - 16 KB) | 1 | 1 – 16,382 |
| Small | Small (16 - 1 MB) | 16,383 | 16,383 – 1,048,576 |
| Medium | Medium (1 - 128 MB) | 1,048,577 | 1,048,577 – 134,217,728 |
| Large | Large (128 MB - 1 GB) | 134,217,729 | 134,217,729 – 1,073,741,824 |
| Huge | Huge (1 - 4 GB) | 1,073,741,825 | 1,073,741,825 – 4,294,967,296 |
| Gigantic | Gigantic (>4 GB) | 4,294,967,297 | > 4 GiB |

(Note MS's Small minValue is 16,383, one less than 16 KiB; copy it literally or use 16,384 — the doc value is likely a typo.)

Windows 7 – Windows 10 1803 (older, widely quoted in blogs): Empty 0, Tiny 1–10 KB, Small 10–100 KB (min 10,241), Medium 100 KB–1 MB (min 102,401), Large 1–16 MB (min 1,048,577), Huge 16–128 MB (min 16,777,217), Gigantic >128 MB (min 134,217,729). [S16][S20]

Folders have no Size value; they fall into an "Unspecified" bucket when grouping/filtering by Size.

### Date buckets (exact rules, measured on Win11 Pro 26200 en-GB) [S5]
Checked in order, first match wins. Week start = user's first day of week (`HKCU\Control Panel\International\iFirstDayOfWeek`; macOS: `Calendar.current.firstWeekday`). Midnight splits days.
- Past: **Today, Yesterday, Earlier this week, Last week, Earlier this month, Last month, Earlier this year, A long time ago** (no "Last year" bucket; "A long time ago" = before Jan 1 of current year).
- Future: **Tomorrow, Later this week, Next week, Later this month, Later this year, Sometime in the future**.
- Example with today = Sun 4 Oct (Mon week start): 28–29 Sep → Earlier this week; 21–27 Sep → Last week; 1–20 Sep → Last month; 2 Jan–31 Aug → Earlier this year; ≤31 Dec prior year → A long time ago.
- Strings live in `propsys.dll.mui`. Group order newest first when descending.

### Combining filters
- Within one column: checked values are **OR**ed (Type = PDF OR Text Document).
- Across columns: **AND**ed (Type = PDF AND Date = Last week). Stack by repeating on each header. [S9][S21]
- Clear: open the header dropdown and uncheck all values (per column). Navigating away / pressing Back also drops the filter, since a filter is a transient query, not a saved view setting.

## 6. Filters as search query in the address/search bar

### What is documented
- After you tick a header filter, Explorer **"is displaying the filtering criteria in the address bar"**, and the header arrow becomes a check mark (Windows 10). Multiple filters show together ("File Explorer showing multiple filters"). [S9]
- A filtered view is a search-results view over the folder (Vista/7 design: column headers "filter items", the results are a query, not a saved view). [S28]
- The **requester's claim that "Type: File folder" appears in the search box could not be confirmed** from any source. What is documented is the criteria appearing in the address bar. The search-box route (typing AQS) is a separate, parallel way to get the same result. Verify on a real Win11 box before copying the exact text. [S9]

### Search-box equivalents (Advanced Query Syntax), useful as the clone's internal representation
| Header filter | AQS typed in search box |
|---|---|
| Size ▸ Huge | `size:huge` (also `size:>1GB`, `size:>1GB AND <2GB`) [S20][S48] |
| Date modified ▸ range | `datemodified:1/1/14..12/31/15`, `datemodified:last week` (search box shows a calendar when you type `datemodified:`) [S11][S17] |
| Type ▸ PDF / Text | `type:pdf`, `extension:(docx OR xlsx)`, `kind:=document`, `kind:folder` [S11][S49] |
| Folder path NOT archive | `folderpath:NOT archive` [S11] |
| Combined | space = AND: `extension:(docx OR xlsx) folderpath:NOT archive datemodified:1/1/14..12/31/15` [S11] |

### Clearing
- Per column: reopen that header's dropdown and untick everything ("remove the checkmark from all of the checked columns" and all files reappear). [S9]
- Whole filter set: navigating to the folder again (click the folder's breadcrumb segment, Back, or F5-style re-entry) drops it, since filters are not stored in the view Bag. (Inferred from the query model; not sourced.)

### Clone recommendation
- Represent every active filter as `{column, Set<bucket>}`; render them as removable **tokens in the search field** (macOS Finder already uses search tokens), e.g. `Type: File folder ✕`, `Size: Large, Huge ✕`. This satisfies both the requester's mental model and Explorer's "criteria visible in the bar" behaviour.
- Header shows a filled funnel/check glyph while that column has a filter; clicking the token ✕ or unticking all values clears it.
- Never persist filters per folder.

## 7. Group by

### Menus
- Command bar **Sort ▸ Group by ▸** {property list} / **Ascending** / **Descending** / **(None)**. Same under right-click empty space ▸ **Group by**. Ascending is the default direction. "(None)" only shows when a grouping is active. [S22][S23]
- The property list is the same set as Sort by: the visible Details columns (Name, Date modified, Type, Size, ...) plus "More..." in the classic menu (Win11 command bar dropped "More..." from Sort; switch to Details and add columns first). [S1][S22]
- Group direction is independent of sort direction: you can group by Type ascending and sort by Date modified descending inside each group.

### Buckets per property (same buckets the filter dropdown shows; see §5)
- Name → **0 - 9, A - H, I - P, Q - Z, Other**. Single-letter groups are not available. [S14][S24]
- Type → one group per type string ("File folder", "PDF Document", ...). [S24]
- Size → Empty / Tiny / ... / Gigantic, folders under **Unspecified**. [S16][S24]
- Dates → Today / Yesterday / Earlier this week / Last week / Earlier this month / Last month / Earlier this year / A long time ago (+ future buckets). [S5]
- Discrete text (Authors, Artist, Album, Genre, Tags) → one group per value; multi-value items appear in each value's group.

### Group headers
- Each header shows **label + item count**, e.g. `Today (3)`, followed by a thin divider line and a collapse chevron. [S24]
- **Collapse/expand one group**: click the chevron, or right-click the header ▸ **Collapse group / Expand group**. [S25]
- **All groups**: right-click a group header ▸ **Collapse all groups / Expand all groups**, or right-click empty background ▸ View ▸ Collapse all groups / Expand all groups. [S25]
- Clicking the header selects every item in that group. Since Windows 7, Ctrl+clicking several group headers to select multiple groups no longer works (one group at a time). Changing the sort while several items are selected deselects them (Win7+). [S28] Keyboard: Left arrow on a focused header collapses, Right expands (ListView convention, unsourced).
- The collapse chevron sits at the **left** of each group header (Win7 "arrows at the top left of each group"). [S74]
- Group order follows the group direction; Date groups run newest first when descending. Inside a group, items follow the current Sort by. Prism measured that inside date groups Explorer puts files before folders. [S5]

### Defaults
- No grouping by default, **except Downloads**, which ships grouped by Date modified (descending), sorted by Date modified. This is the #1 complaint thread on MS Q&A. Turn off: Group by ▸ (None), then Options ▸ View ▸ Apply to Folders to spread it. [S23][S26][S27]

## 8. Folder Options: Apply to Folders, Reset Folders, Remember each folder's view

### "Remember each folder's view settings" does NOT exist in Windows 11
- That checkbox was in Folder Options ▸ View on XP/Vista. **It was removed in Windows 7** ("Remember each folder's view settings was removed. It had let Explorer keep icon view modes and icon sizes per folder"). Windows 7 through 11 always remember per-folder views; there is no UI switch to turn it off. [S28][S29]
- The XP-era policy DWORD `ClassicViewState` (HKCU\...\Explorer\Advanced, 1 = don't remember) is reported in forums but unverified on 10/11. [S29][S30]

### How per-folder memory actually works (Win7–11)
- Views are stored in the **Shell Bags**: `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU` (folder → NodeSlot index) and `...\Shell\Bags\<n>` (the view state: layout, sort, group, columns, widths, icon size). [S29][S31]
- Cap: Explorer remembers the **first 5,000 folders** you customise; `BagMRU Size` DWORD raises it (max ~20,000). Older entries get dropped. [S31][S32]
- A folder without its own Bag inherits the default for its **folder type template** (General items, Documents, Pictures, Music, Videos), chosen by "folder discovery" (content sniffing) unless set manually in Properties ▸ Customize. [S27][S33]
- Bags are keyed by *how* the folder was reached (e.g. opened from a browser vs Explorer), so the same folder could show different views. **April–May 2026 fix**: builds 26100.8328 (24H2) / 26200.8328 (25H2) / 28000.2179 (26H1), "Improves folder view consistency so customized settings (such as sorting files by name or adjusting icon size) now apply across all ways you open a folder." [S34]

### Folder Options ▸ View tab buttons (scope = current folder's template)
- **Apply to Folders**: "Copies the current folder's view to all folders of the same template" (layout, columns, widths, sort, group). Does not touch folders of other templates; Pictures does not affect Documents or General items. [S27][S33]
- **Reset Folders**: "restores the default view for every folder that uses the current folder's template." [S33]
- Path in Win11: command bar **⋯ (See more) ▸ Options ▸ View**. [S27]

### Turning per-folder memory off (what the requester wants)
Explorer has no supported switch. Community recipe that gets "one view for all folders": delete `Bags` + `BagMRU`, create `Bags\AllFolders\Shell` with string `FolderType = NotSpecified` (disables folder-type discovery), set the view once in a General items folder, then Apply to Folders. [S35][S36]

### Clone recommendation
- Default: **one global view state** (columns, widths, order, sort, group) for every folder. No per-folder memory, no folder-type sniffing.
- Keep "Apply to Folders" / "Reset Folders" only as "Save as default view" / "Reset to default view" if wanted; they become trivial with a single global state.
- Optional per-folder override can stay off and hidden. Filters are never persisted (they are a transient search, see §6).

## 9. Column width, auto-size, drag to reorder

- **Resize**: drag the divider between two header cells. Cursor becomes ↔ over the divider. [S50]
- **Auto-size one column**: double-click the divider at the right edge of that column → width fits the widest visible value *and* the header text (standard Win32 ListView/Header behaviour; Explorer uses it). Same as right-click ▸ **Size column to fit**. [S38][S51]
- **Auto-size all**: right-click header ▸ **Size all columns to fit**, or **Ctrl + Numpad +**. One-shot verb, based on current contents. [S38][S41]
- **Reorder**: drag a header left/right; a drop indicator shows the insertion point. Explorer allows moving Name too, but legacy dialogs assume Name is first and WinSetView warns if it is not. Choose Details ▸ Move Up/Down does the same. [S40][S52][S53]
- **Defaults are in ems** (≈ 1 char): Name = 34 em; others ≈ 15–20 em. Scale with font/DPI. [S40]
- **Persistence**: widths, order and visible set are part of the folder's view Bag (per folder, per access route). Apply to Folders copies them to the template. Reports vary: some users say widths reset on reopen, especially on Box Drive / network locations and in Windows 11. [S27][S40][S54]
- Clone recommendation: one global column set (order, visibility, width) saved via `NSTableView.autosaveName` + `autosaveTableColumns = true`; double-click divider = fit to content (compute max string width of visible rows, cap at e.g. 600 pt); add "Size column to fit" / "Size all columns to fit" to the header menu and bind ⌘⌥+ or similar.

## 10. Check boxes column

- Toggle: Win11 **View ▸ Show ▸ Item check boxes**; older: Folder Options ▸ View ▸ "**Use check boxes to select items**". Registry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\AutoCheckSelect` = 1/0. [S55][S56][S57]
- Each row gets a checkbox in front of the icon, inside the Name cell (not a separate column). It is visible on hover and stays visible for selected rows; checking = selecting (it is selection UI, not a separate "marked" state). [S55][S57]
- In Details view, a **select-all checkbox sits at the left of the Name header**; click to select/deselect all items in the view. [S58]
- Clone: render a leading checkbox in the Name cell when the option is on, bound to row selection; header checkbox = select all / none, tri-state when partial.

## 11. Date columns and time zones

- **NTFS stores UTC** (FILETIME, 100 ns). FAT stores local time (2 s resolution); exFAT stores local + UTC offset. [S59][S60]
- **Display**: Explorer converts each UTC stamp to local time using **the time-zone/DST rule in effect at that timestamp's date**, not today's rule. `cmd`/`dir` still use the old `FileTimeToLocalFileTime` (today's bias), so a June file can show 1 hour different in `dir` vs Explorer in winter. [S59][S60]
- **Sort**: compares the raw UTC value, so sort order is true chronological order regardless of the zone/DST each file was written in. Display granularity is minutes (short date + short time); items in the same displayed minute still sort by their full-precision stamp. (Inference from storage model; Explorer sorts the property value, not the string.)
- Edge case: around the autumn "fall back" hour, chronological order can display as 01:50 then 01:10 (the repeated hour). Looks unsorted, is correct.
- **Date taken** is "the date when the photo was taken, as read from the camera in the file's EXIF tag" (type DateTime). EXIF `DateTimeOriginal` carries no zone, so Explorer shows the camera's wall clock and photos from different trips sort by camera-local clock, not absolute instant. (Propdesc sourced; the wall-clock conclusion is inferred, not stated by Microsoft.) [S61]
- Grouping/filter buckets (Today, Last week, ...) use the **local** calendar date after conversion, with the user's first-day-of-week. [S5]
- **Clone**: APFS/HFS+ stamps are UTC `Date`; format with `DateFormatter` in `TimeZone.current` (which applies the historical DST rule for each date, same as Explorer); sort on `Date`, never the string. For Date taken, use EXIF `OffsetTimeOriginal` if present, else treat as local wall time to match Explorer.

## 12. Status bar counts

- Left side: **"N items"** (total in view) and, with a selection, **"N items selected  X KB/MB"**. The selected size shows only when the selection contains files; folders have no size. [S62][S63]
- Win11 change (late 2023): the Details pane stopped totalling multi-selections ("Select a single file to get more information"); the status bar still shows count + size of selected files. [S63]
- When a header filter or search is active, "N items" counts the **visible (filtered) results**, because a filtered view is a result set. (Expected from the query model; no source found that states it explicitly.)
- Size column format: classic Explorer always shows **KB, rounded up** (a 15-byte file shows "1 KB", 0 bytes shows "0 KB"); Aug 2026 builds are testing adaptive units (KB/MB/GB), rollout inconsistent. [S48][S64]
- Clone: status bar shows `visibleCount items` · `selectedCount selected` · `sum(selected file sizes)`; when filters are active add "(filtered from totalCount)" so the requester always knows something is hidden.

## 13. macOS NSTableView: free vs build

### Free (AppKit does it)
| Explorer behaviour | AppKit piece |
|---|---|
| Header click sorts, 2nd click reverses, arrow indicator | `NSTableColumn.sortDescriptorPrototype` per column → table updates `sortDescriptors`, draws the indicator, calls `tableView(_:sortDescriptorsDidChange:)`; you sort + `reloadData()`. A column is sortable once its prototype has a key, direction and selector. [S65][S66][S67] |
| Secondary keys | AppKit puts the clicked column's descriptor first and keeps earlier ones after it, so you get a multi-key history for free (observed AppKit behaviour; trim to 3–4 to match Explorer). |
| Drag to reorder columns | `allowsColumnReordering = true` |
| Drag divider to resize | `allowsColumnResizing = true`; set `columnAutoresizingStyle = .noColumnAutoresizing` so columns don't stretch to the window like Explorer |
| Double-click divider = fit | `tableView(_:sizeToFitWidthOfColumn:)` delegate (10.6+). Default walks every row's cell (Monte Carlo sampling on big tables); implement it for view-based tables to measure real strings. [S68] |
| Hide/show column | `NSTableColumn.isHidden` |
| Persist widths, order, hidden state, sort | `autosaveName` + `autosaveTableColumns = true` saves "column width, column order, any applied sort descriptors, and column hidden state" per user per app. One autosave name = one global view (what the requester wants). [S69] |
| Natural name sort | `NSSortDescriptor(key:ascending:selector: #selector(NSString.localizedStandardCompare(_:)))` — "Compares strings as sorted by the Finder", current locale. [S70] |
| Group header rows, sticky | `tableView(_:isGroupRow:)` + `floatsGroupRows = true` (headers float at top while scrolling). [S71] |
| Header right-click | `headerView.menu = NSMenu` (you fill it; it doesn't list columns for you) |

### Must build
1. **Folders-first comparator**: compare `isDirectory` first, then the column key, then the column's tie-breaker (Name for Type/Size/Date), all reversed together on descending (Explorer puts folders last when descending). One comparator closure, not chained `NSSortDescriptor`s, so the folder rule can't be reordered by header clicks.
2. **Header filter chevron**: subclass `NSTableHeaderView` (or `NSTableHeaderCell`) to draw a chevron in the right 16 pt of the hovered cell and a check/funnel glyph when filtered; intercept `mouseDown` in that zone so it opens an `NSPopover` (checkbox list, date picker) instead of sorting. Tracking areas per column for hover.
3. **Bucket engine** shared by filter and group: Alphanumeric (0-9/A-H/I-P/Q-Z/Other), Size (7 buckets + Unspecified), Date (relative buckets, §5), Discrete (distinct values, multi-value aware). Compute values off the main thread; show "Computing filters..." while running.
4. **Filter tokens** in the search field (`NSSearchField` + `NSTokenField`-style tokens or a custom token bar) and the OR-within / AND-across logic.
5. **Collapsible groups**: `NSTableView` group rows don't collapse. Either switch to `NSOutlineView` (groups = top-level items, `expandItem`/`collapseItem`, gives disclosure triangles and ←/→ keys), or keep a `collapsedGroups` set and omit rows. Header text `"Label (count)"`, click selects group members, context menu Collapse group / Collapse all groups / Expand all groups.
6. **Group by + Sort by**: sort groups by group key (own direction), then rows within groups by the sort descriptors.
7. **Choose Details dialog** with the full property list (§3) and Move Up/Down/Width; header menu with Size column to fit / Size all columns to fit / common columns / More...
8. **Checkbox selection mode** (§10) and select-all header checkbox.
9. **Status bar** (§12) with visible vs total counts.
10. **Metadata fetchers** for non-basic columns (Spotlight `MDItem`, ImageIO EXIF, AVFoundation) with caching; most columns cost I/O.

SwiftUI `Table` (macOS 12+) also offers `sortOrder` with `KeyPathComparator` and, on macOS 14+, `TableColumnCustomization` for hide/reorder persistence, but it has no header-menu or header-cell hooks for a filter chevron and no collapsible groups, so `NSTableView`/`NSOutlineView` is the better base.

## Confidence notes
- **Solid (Microsoft docs / measured)**: size buckets, propdesc schema (groupingRange, filterControl, defaultSortDirection, sortDescription), sort history (natural sort, Type tie-break by name, period-before-space), date buckets (Prism UIA measurement on Win11 26200), Remember-each-folder removal (Win7), Bags/5000 limit, NSTableView APIs.
- **Community-sourced, consistent**: header chevron + check mark, Name A-H/I-P/Q-Z, Shift+click secondary sort, folders-last on descending, Apply/Reset Folders scope, default ColumnLists for General/Music/Pictures library, Downloads grouping.
- **Unverified, test on a real Win11 box before copying exact text**: what the address/search bar literally shows after a header filter (requester says "Type: File folder" in the search box; the only source says the criteria show in the address bar), Videos template default columns, status-bar count under filters, Left/Right keys on group headers, whether Win11 24H2+ still shows the calendar in the Date filter.

## Sources
- [S1] ElevenForum, Change Folder Sort by View in Windows 11 File Explorer — https://www.elevenforum.com/t/change-folder-sort-by-view-in-windows-11-file-explorer.1249/
- [S2] Microsoft Q&A, File Explorer Sort Customization (Shift+click Name) — https://learn.microsoft.com/en-us/answers/questions/4335186/file-explorer-sort-customization ; ElevenForum sorting question — https://www.elevenforum.com/t/file-explorer-sorting-question.20208/
- [S3] ElevenForum, Explorer: Make folders stick to the top when sorted by date? — https://www.elevenforum.com/t/explorer-make-folders-stick-to-the-top-when-sorted-by-date.35234/
- [S4] Raymond Chen, Why do files and directories with no time/date mess up sorting in Explorer? — https://devblogs.microsoft.com/oldnewthing/20050125-00/?p=36603
- [S5] Prism PR #287, Win11 date-group measurement via UI Automation — https://github.com/Maxaubert/Prism/pull/287
- [S6] Raymond Chen, Windows Confidential: The Evolution of Sorting — https://learn.microsoft.com/en-us/previous-versions/technet-magazine/hh475812(v=msdn.10)
- [S7] Stack Overflow (mirror), Windows Explorer sort method / StrCmpLogicalW — https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/442429/windows-explorer-sort-method
- [S8] TechRepublic, Quickly find the files you need with the Filter feature in Windows 10's File Explorer (403 to fetch; via search excerpts) — https://www.techrepublic.com/article/quickly-find-the-files-you-need-with-the-filter-feature-in-windows-10s-file-explorer/
- [S9] Windows Tips, Filtering a Folder's Content (Windows 10) — https://windows.tips.net/T013603_Filtering_a_Folders_Content.html
- [S10] Directory Opus forum, Explorer-style header filters — https://resource.dopus.com/t/filter-on-multiple-criteria-in-multiple-file-detail-fields/12194
- [S11] Microsoft Q&A, unable to filter by some headings ("computing filters...", AQS examples) — https://learn.microsoft.com/en-us/answers/questions/3152888/file-explorer-unable-to-filter-by-some-headings-na
- [S12] Microsoft Learn, propdesc typeInfo (groupingRange, isViewable) — https://learn.microsoft.com/en-us/windows/win32/properties/propdesc-schema-typeinfo
- [S13] Microsoft Learn, propdesc displayInfo (filterControl, defaultSortDirection, defaultColumnWidth) — https://learn.microsoft.com/en-us/windows/win32/properties/propdesc-schema-displayinfo
- [S14] Seven Forums, column drop-down filter menus A-H, I-P, Q-Z — https://www.sevenforums.com/general-discussion/334470-file-explorer-details-column-drop-down-arrow-filter-menus.html
- [S15] = S8 + S10 (Type list built from types present)
- [S16] Microsoft Learn, System.Size (enumRange tables per Windows version) — https://learn.microsoft.com/en-us/windows/win32/properties/props-system-size
- [S17] MiniTool, find files by date modified (column calendar) — https://www.minitool.com/news/find-files-by-date-modified-windows-10.html
- [S18] Microsoft Q&A, Date range picker on date modified missing Windows 11 — https://learn.microsoft.com/en-us/answers/questions/3951063/data-range-picker-on-date-modified-missing-windows
- [S19] AskWoody, datemodified calendar gone in 1909 (403 to fetch; via search excerpt) — https://askwoody.com/forums/topic/datemodified-available-in-file-explorer-in-win10-v1909
- [S20] WindowsLoop, filter files by size — https://www.windowsloop.com/filter-files-by-size-in-file-explorer/ ; AddictiveTips size filters — https://www.addictivetips.com/windows-tips/how-to-find-files-based-on-size-using-windows-explorer-search-filters
- [S21] = S8/S9 (multiple filters at once)
- [S22] ElevenForum, Change Folder Group by View in Windows 11 — https://elevenforum.com/t/change-folder-group-by-view-in-windows-11-file-explorer.1250/
- [S23] Help Desk Geek, enable or turn off grouping — https://helpdeskgeek.com/windows-11/how-to-enable-or-turn-off-grouping-in-windows-file-explorer/
- [S24] OpenXplorer PR #36 (Explorer group buckets, "Today (3)") — https://github.com/AKolenda/openxplorer/pull/36 ; Cyn Mackley, group files — https://cynmackley.com/2020/02/27/file-explorer-group-files/ ; Microsoft Q&A group alphabetically — https://learn.microsoft.com/en-us/answers/questions/2430656/
- [S25] ElevenForum, Expand or Collapse Group in File Explorer in Windows 11 — https://www.elevenforum.com/t/expand-or-collapse-group-in-file-explorer-in-windows-11.6518/
- [S26] Alphr, remove Today/Yesterday grouping — https://www.alphr.com/remove-today-yesterday-file-explorer/
- [S27] Microsoft Q&A, set default group by and sort by (per folder type, Apply to Folders) — https://learn.microsoft.com/en-us/answers/questions/5682769/how-to-set-the-default-group-by-and-sort-by-order
- [S28] Wikipedia, List of features removed in Windows 7 — https://en.wikipedia.org/wiki/List_of_features_removed_in_Windows_7
- [S29] Jeroen Tielen, Explaining the Bags/BagMRU registry tree — https://www.jeroentielen.nl/explaining-the-bagsbagmru-registry-tree-trying/
- [S30] Tom's Hardware, disable Remember each folder's view settings (ClassicViewState) — https://forums.tomshardware.com/threads/how-to-disable-remember-each-folders-view-settings-and.1085625/
- [S31] ElevenForum, Increase Folder View Settings Cache Memory Size (5000 / 20000) — https://www.elevenforum.com/t/increase-folder-view-settings-cache-memory-size-in-windows-11.1277/
- [S32] Winaero, change number of folder views to remember — https://winaero.com/change-number-of-folder-views-to-remember-in-windows-10/
- [S33] Help Desk Geek, reset folder view settings (Apply/Reset Folders scope) — https://helpdeskgeek.com/reset-file-explorer-folder-view-settings-windows-11/
- [S34] Windows Latest, Windows 11 finally fixes inconsistent folder views (Apr 2026) — https://www.windowslatest.com/2026/04/18/windows-11-finally-fixes-inconsistent-folder-views-in-file-explorer/
- [S35] GitHub, disable-folder-discovery (FolderType=NotSpecified) — https://github.com/MagnusJohansson/disable-folder-discovery
- [S36] Windows Latest, turn off folder discovery (2024) — https://www.windowslatest.com/2024/03/04/windows-11-can-open-big-folders-in-file-explorer-faster-if-you-turn-off-folder-discovery/
- [S37] All Things How, add or remove columns in Windows 11 — https://allthings.how/add-or-remove-columns-in-windows-11-file-explorer/
- [S38] Winaero, shortcut to fit all columns — https://winaero.com/use-this-secret-keyboard-shortcut-to-fit-all-columns-in-explorer-and-other-apps ; Ed Bott, automatically resize columns — https://edbott.com/2005/06/07/tip-of-the-day-automatically-resize-columns-in-windows-explorer/
- [S39] Microsoft Q&A, ColumnList syntax (0/1/2 flags, width) — https://learn.microsoft.com/en-us/answers/questions/2825286/
- [S40] WinSetView Manual (ems, Name 34 em, Name not removable, 3 stored / 4 GUI sort levels, Apply/Reset scope, Downloads) — https://lesferch.github.io/WinSetView/Manual.html
- [S41] Raymond Chen, Ctrl+Num+ resizes all columns (verb, not state) — https://devblogs.microsoft.com/oldnewthing/20121030-00/?p=6223
- [S42] Oracle WebCenter help, Explorer Choose Details width field label — https://docs.oracle.com/cd/E92951_01/wcc/use-desktop-help/column_settings.htm
- [S43] Tencent Cloud Q&A, GetDetailsOf column list Windows 10 (0–320) — https://cloud.tencent.com/developer/ask/sof/110700553
- [S44] Microsoft Q&A, audio-only folders treated as Music — https://learn.microsoft.com/en-us/answers/a/6858754
- [S45] ThiWeb forum, Generic and Music ColumnList values — https://forum.thiweb.com/viewtopic.php?t=19633
- [S46] coolvitto, FolderTypes details (LogicalViewMode, GroupBy, SortByList per type) — https://coolvitto.hateblo.jp/entry/2024/03/22/023859
- [S47] Microsoft Q&A, Windows 10 Library Grouping Labels (Pictures library ColumnLists) — https://learn.microsoft.com/en-us/answers/questions/3222621/windows-10-library-grouping-labels
- [S48] = S20 AddictiveTips (size: syntax, KB rounding)
- [S49] Microsoft Q&A, File Explorer Search Filtering (kind:=document) — https://learn.microsoft.com/en-us/answers/questions/4001875/file-explorer-search-filtering
- [S50] Microsoft Support KB 310297, change column settings in Windows Explorer (via search excerpt) — https://support.microsoft.com/kb/310297
- [S51] Microsoft Learn, HDN_DIVIDERDBLCLICK — https://learn.microsoft.com/en-us/windows/win32/controls/hdn-dividerdblclick
- [S52] KDE forum, "in Windows I can just drag the header" — https://forum.kde.org/viewtopic.php%3Ff=224&t=88536.html
- [S53] PCWorld, customize Details view column order — https://www.pcworld.com/article/2980339/how-to-customize-windows-file-explorers-details-view.html
- [S54] Microsoft Q&A, column widths remembered per folder / reset reports — https://learn.microsoft.com/en-us/answers/a/5286302 ; Box Drive — https://pulse.box.com/forums/909778-help-shape-the-future-of-box/suggestions/38384737-box-drive-windows-remember-folder-view-setting?page=2
- [S55] How-To Geek, turn off File Explorer check boxes on Windows 11 — https://www.howtogeek.com/756933/how-to-turn-off-file-explorer-check-boxes-on-windows-11/
- [S56] Winaero, check boxes in File Explorer (AutoCheckSelect) — https://winaero.com/check-boxes-file-explorer-windows-10/
- [S57] ElevenForum, Turn On or Off Use Check Boxes to Select Items — https://www.elevenforum.com/t/turn-on-or-off-use-check-boxes-to-select-items-in-windows-11.764/
- [S58] ElevenForum, Select Items in File Explorer in Windows 11 (header select-all checkbox) — https://www.elevenforum.com/t/select-items-in-file-explorer-in-windows-11.7319/
- [S59] Raymond Chen, Why do Explorer and the command prompt interpret file times differently? — https://devblogs.microsoft.com/oldnewthing/20130308-00/?p=5023
- [S60] Microsoft DST2007 blog, How Windows Explorer uses DST for file datetime — https://learn.microsoft.com/en-us/archive/blogs/dst2007/explain-how-windows-explorer-uses-dst-for-file-datetime ; File Times — https://learn.microsoft.com/en-us/windows/win32/sysinfo/file-times
- [S61] Microsoft Learn, System.Photo.DateTaken — https://learn.microsoft.com/en-us/windows/win32/properties/props-system-photo-datetaken
- [S62] UC Davis IT, Working with File Explorer in Windows 11 (status bar) — https://it.environment.ucdavis.edu/file-explorer
- [S63] Microsoft Q&A, selected files total size gone from Details pane — https://learn.microsoft.com/en-us/answers/a/7296374
- [S64] Microsoft Tech Community, file size display format changed (Aug 2026) — https://techcommunity.microsoft.com/discussions/windows11/the-file-size-display-format-in-windows-11-file-explorer-has-changed/4543445
- [S65] Apple, NSTableColumn.sortDescriptorPrototype — https://developer.apple.com/documentation/appkit/nstablecolumn/sortdescriptorprototype
- [S66] Apple, NSTableView.sortDescriptors — https://developer.apple.com/documentation/appkit/nstableview/sortdescriptors
- [S67] Apple, tableView(_:sortDescriptorsDidChange:) — https://developer.apple.com/documentation/appkit/nstableviewdatasource/tableview(_:sortdescriptorsdidchange:)
- [S68] Apple, tableView(_:sizeToFitWidthOfColumn:) — https://developer.apple.com/documentation/appkit/nstableviewdelegate/tableview(_:sizetofitwidthofcolumn:)
- [S69] Apple, NSTableView.autosaveTableColumns — https://developer.apple.com/documentation/appkit/nstableview/autosavetablecolumns
- [S70] Apple, localizedStandardCompare(_:) — https://developer.apple.com/documentation/foundation/nsstring/localizedstandardcompare(_:)
- [S71] Apple, tableView(_:isGroupRow:) / floatsGroupRows — https://developer.apple.com/documentation/appkit/nstableviewdelegate/tableview(_:isgrouprow:)
- [S72] Microsoft Learn, propdesc labelInfo (sortDescription strings) — https://learn.microsoft.com/en-us/windows/win32/properties/propdesc-schema-labelinfo
- [S73] Winaero, disable numerical sorting (NoStrCmpLogical) — https://winaero.com/disable-numerical-sorting-windows-10 ; ElevenForum — https://www.elevenforum.com/t/enable-or-disable-numerical-sorting-in-file-explorer-in-windows-11.9030/
- [S74] Petri, Grouping and Filtering Files in Windows 7 Explorer — https://petri.com/grouping-and-filtering-files-in-windows-7-explorer/
