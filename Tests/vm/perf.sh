#!/bin/bash
# Speed harness: times the moments Anshul feels, on fixed fixtures, with Folio's own marks (PerfTrace).
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Folio starts with `-perfTrace <file>`: it writes one line per mark ("<seconds> <name> key=value"),
# and a "stall" line for every run-loop turn that kept the main thread busy 16 ms or more. Every moment runs
# $RUNS times (3 unless ~/folio/perf.conf says otherwise) and the table gives the median, min and max:
#   launch          quit, `open -a Folio f1k`: the script's clock to the first rows drawn (and the app's own
#                   time since its process started)
#   open-<n>        address bar to a flat folder of 1k, 10k, 50k or 200k files: the Return key reaching
#                   Folio to rows drawn (-load: the app's load start to display), the longest stall, and
#                   Folio's memory footprint once the rows are drawn
#   sort-<n>-<key>  View > Sort By > Size, Date modified, Name in that folder: sort start to rows drawn, and
#                   the longest main-thread stall of the three
#   filter-50k      Cmd+F in the 50k folder, type IMG_0123: last key to results drawn (300 ms of it is the
#                   box's wait for more typing), the search engine's own time, the longest stall
#   selectall-200k  Cmd+A in the 200k folder: the longest stall in the 2.5 s after (status bar, session)
#   scroll-50k      240 wheel events of 60 px at 120 Hz down the 50k folder in Details: frames dropped
#                   (sum of floor(stall/16.7)), stalls over 50 ms, the longest stall
#   view-10k        Details to Large icons and back in the 10k folder
#   thumbs-300      Details to Large icons on 300 fresh JPEGs: view drawn, then all thumbnails made; then
#                   120 wheel events down the icons: frames dropped while thumbnails load
#   search-200k     Cmd+F in a 200,000-file tree, "zqneedle", Return: Return to results drawn, engine time
#   copy-2gb        Cmd+C a 2 GB file, Cmd+V onto another APFS volume (a disk image): job done, MB/s
#   memory-50       after opening 50 folders of 1,000 files one after another: footprint and RSS
#   churn-cpu       a tab on a folder while 100 files a second are written below it for 20 s: Folio's CPU
#   refresh-<n>     a tab on a folder of 10,000 (and 50,000) files while 5 files a second come and go in it
#                   for 10 s (a busy Downloads): Folio's CPU, refreshes drawn, each one's time, longest stall
#   bench           (builds that have it) `Folio --bench` on the 50k and 200k folders: each step of opening
#                   them timed on its own (list, arrange, keys, tree, search walk), printed under the table
# ~/folio/perf.conf may set RUNS=n, ONLY="launch open sort ..." (moment groups) for a quicker pass, and
# LABEL=name to keep this run's table apart from another build's in the same session.
# Fixtures are made once under /private/tmp/folio-tests/perf-fixtures (about 460,000 small sparse files) and
# kept for the next run; the copy's 2 GB file is made when there is room and removed after the copy. The vm-test helper brings back only ~/folio/shots/*.png,
# so the results table also goes there as perf-results.txt.png (plain text). Ends with "result: ok".
set -u

APP="$HOME/folio/Folio.app"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
FIX="/private/tmp/folio-tests/perf-fixtures"
RUN="/private/tmp/folio-tests/perf-$STAMP"
MARKS="$RUN/marks.log"
RAW="$RUN/raw.tsv"
TOOL="$HOME/folio/folio-perftool"
RUNS=3
LABEL=""
ONLY="launch open sort filter selectall scroll view thumbs search copy memory churn refresh bench"
# A perf.conf counts for one run only.
[ -f "$HOME/folio/perf.conf" ] && { . "$HOME/folio/perf.conf"; rm -f "$HOME/folio/perf.conf"; }
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "perf: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "perf: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi
mkdir -p "$SHOTS" "$RUN"
: > "$MARKS"
: > "$RAW"
wants() { case " $ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
fail() { echo "perf: FAILED - $1"; fails=$((fails + 1)); }

# --- folio-perftool: fixtures, wheel events, churn (Swift, compiled here) --------------------------------
cat > "$RUN/folio-perftool.swift" <<'SWIFT'
// folio-perftool: the speed harness's helper (Tests/vm/perf.sh). Compiled and run INSIDE the test VM only
// (docs/plan/RULES.md, rule 0); every path it writes is under /private/tmp/folio-tests/.
//   folio-perftool fixtures <root>                 the flat folders and the 200k tree
//   folio-perftool big <dir>                        the 2 GB file for the copy
//   folio-perftool images <dir> <count> <seed>      fresh JPEGs (new files, so no thumbnail cache knows them)
//   folio-perftool scroll <x> <y> <events> <px> <hz> wheel events in pixels (negative px scrolls down)
//   folio-perftool churn <dir> <seconds> <perSecond> create, write and remove files in <dir>
//   folio-perftool files <dir> <count>             that many small files (the names the flat folders have)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func die(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(2) }

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { die("usage: folio-perftool fixtures|images|scroll|churn ...") }
guard args.count < 2 || args[1].hasPrefix("/private/tmp/folio-tests/") || cmd == "scroll" else {
    die("folio-perftool: only writes under /private/tmp/folio-tests/")
}

/// One file of `size` bytes (sparse: the size is set, nothing written) dated `age` seconds ago.
func makeFile(_ path: String, size: Int, age: Int) {
    let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { die("cannot create \(path)") }
    ftruncate(fd, off_t(size))
    let t = time(nil) - age
    var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
    futimes(fd, &times)
    close(fd)
}

func mkdirs(_ path: String) { try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }

/// Names as people have them: photos, reports, notes, songs, screenshots, data, archives, bare names,
/// accents, numbers that sort by value.
func name(_ i: Int) -> String {
    switch i % 10 {
    case 0: return String(format: "IMG_%05d.jpg", i)
    case 1: return "Report \(i).pdf"
    case 2: return "notes-\(i).txt"
    case 3: return String(format: "track %02d - song %d.mp3", i % 30, i)
    case 4: return "data_\(i).json"
    case 5: return String(format: "Screenshot 2026-%02d-%02d at %d.png", 1 + i % 12, 1 + i % 28, i)
    case 6: return "archive-\(i).zip"
    case 7: return "File\(i)"
    case 8: return "résumé \(i).docx"
    default: return "Clip \(i).mov"
    }
}

func flat(_ dir: String, count: Int) {
    mkdirs(dir)
    // A few folders too, so folders-first matters in every sort.
    for f in 0..<20 { mkdirs(dir + "/Folder \(f)") }
    for i in 0..<count { makeFile(dir + "/" + name(i), size: (i &* 7919) % 50_000, age: (i &* 7907) % 63_072_000) }
}

func jpeg(_ path: String, seed: Int) {
    let w = 800, h = 600
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    var r = UInt64(seed &* 2654435761 &+ 1)
    func next() -> CGFloat { r = r &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(r >> 40) / CGFloat(1 << 24) }
    ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for _ in 0..<40 {
        ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: next() * CGFloat(w), y: next() * CGFloat(h), width: 40 + next() * 300, height: 40 + next() * 300))
    }
    guard let image = ctx.makeImage(),
          let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    CGImageDestinationFinalize(out)
}

switch cmd {
case "fixtures" where args.count == 2:
    let root = args[1]
    for (n, label) in [(1_000, "f1k"), (10_000, "f10k"), (50_000, "f50k"), (200_000, "f200k")] {
        flat(root + "/flat/" + label, count: n)
        print("fixtures: \(label) \(n) files")
    }
    mkdirs(root + "/flat/small")
    for i in 0..<5 { makeFile(root + "/flat/small/" + name(i), size: 100, age: 60) }
    // 200,000 files in 200 folders of 1,000, two levels deep, with 60 needles scattered for the search.
    var made = 0
    for a in 0..<20 {
        for b in 0..<10 {
            let dir = root + String(format: "/tree200k/Area %02d/Part %02d", a, b)
            mkdirs(dir)
            for i in 0..<1_000 {
                let k = (a * 10 + b) * 1_000 + i
                let n = k % 3_331 == 7 ? "zqneedle \(k).txt" : name(k)
                makeFile(dir + "/" + n, size: (k &* 7919) % 50_000, age: (k &* 7907) % 63_072_000)
                made += 1
            }
        }
    }
    print("fixtures: tree200k \(made) files")
case "big" where args.count == 2:
    // The 2 GB file for the copy: real blocks (not sparse), one random megabyte over and over. Made for
    // the copy moment and removed after it (the VM's disk is shared).
    mkdirs(args[1])
    let fd = open(args[1] + "/big.bin", O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    var block = [UInt8](repeating: 0, count: 1 << 20)
    for i in block.indices { block[i] = UInt8.random(in: 0...255) }
    for _ in 0..<2048 { _ = block.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }
    close(fd)
    print("big: big.bin 2 GB")
case "images" where args.count == 4:
    let dir = args[1], count = Int(args[2]) ?? 0, seed = Int(args[3]) ?? 0
    mkdirs(dir)
    for i in 0..<count { jpeg(dir + String(format: "/photo %03d.jpg", i), seed: seed * 10_000 + i) }
    print("images: \(count) in \(dir)")
case "scroll" where args.count == 6:
    let x = Double(args[1]) ?? 0, y = Double(args[2]) ?? 0
    let events = Int(args[3]) ?? 0, px = Int32(args[4]) ?? 0, hz = Double(args[5]) ?? 60
    let source = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(200_000)
    let start = Date().timeIntervalSince1970
    for i in 0..<events {
        if let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: px, wheel2: 0, wheel3: 0) {
            e.location = p
            e.post(tap: .cghidEventTap)
        }
        // Paced on the clock, not on sleeps, so a slow post does not stretch the run.
        let due = start + Double(i + 1) / hz
        let wait = due - Date().timeIntervalSince1970
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
    }
    print(String(format: "scrolled %d events of %d px at %.0f Hz from %.4f to %.4f", events, px, hz, start, Date().timeIntervalSince1970))
case "files" where args.count == 3:
    flat(args[1], count: Int(args[2]) ?? 0)
    print("files: \(args[2]) in \(args[1])")
case "churn" where args.count == 4:
    let dir = args[1], seconds = Double(args[2]) ?? 10, rate = Double(args[3]) ?? 100
    mkdirs(dir)
    let start = Date().timeIntervalSince1970
    var i = 0
    while Date().timeIntervalSince1970 - start < seconds {
        let path = dir + "/churn-\(i % 50).tmp"
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 { _ = write(fd, "x", 1); close(fd) }
        if i % 2 == 1 { unlink(path) }
        i += 1
        let wait = start + Double(i) / rate - Date().timeIntervalSince1970
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
    }
    print("churn: \(i) writes in \(dir)")
default:
    die("usage: folio-perftool fixtures <root> | images <dir> <count> <seed> | scroll <x> <y> <events> <px> <hz> | churn <dir> <s> <rate>")
}
SWIFT
if ! cmp -s "$RUN/folio-perftool.swift" "$HOME/folio/folio-perftool.swift" || [ ! -x "$TOOL" ]; then
    cp "$RUN/folio-perftool.swift" "$HOME/folio/folio-perftool.swift"
    swiftc -O "$HOME/folio/folio-perftool.swift" -o "$TOOL" 2>&1 | tail -5
fi
[ -x "$TOOL" ] || { echo "perf: could not build folio-perftool"; exit 2; }

if [ ! -f "$FIX/.made-v1" ]; then
    echo "perf: making fixtures in $FIX (once)"
    rm -rf "$FIX"
    t0=$(perl -MTime::HiRes=time -e 'printf "%.1f", time')
    "$TOOL" fixtures "$FIX" || { echo "perf: fixtures failed"; exit 2; }
    touch "$FIX/.made-v1"
    echo "perf: fixtures made in $(perl -MTime::HiRes=time -e "printf '%.0f', time - $t0") s"
fi
echo "perf: $(sysctl -n hw.ncpu) cpus, $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, $(df -h /private/tmp | tail -1 | awk '{print $4}') free; runs=$RUNS; only=$ONLY; label=${LABEL:-none}; build=$(defaults read "$APP/Contents/Info" FolioVersion 2>/dev/null)"
if sudo -n true 2>/dev/null; then CANPURGE=1; else CANPURGE=0; fi

# --- helpers ------------------------------------------------------------------------------------------
now() { perl -MTime::HiRes=time -e 'printf "%.4f", time'; }
osa() { osascript -e "$1" >/dev/null 2>&1; }
front() { osa 'tell application "System Events" to set frontmost of process "Folio" to true'; }
key() { osa "tell application \"System Events\" to tell process \"Folio\" to $1"; }
lines() { wc -l < "$MARKS" | tr -d ' '; }
shot() { local f="$SHOTS/$1.png"; rm -f "$f"; screencapture -x "$f" 2>/dev/null; [ -s "$f" ] && echo "  shot: $f"; }

# wait_mark <name> <after line> <timeout s> [text]: the first mark of that name after that line (holding the
# text, when given), printed; nothing on time-out.
wait_mark() {
    local name=$1 after=$2 limit=$3 text=${4:-} end hit
    end=$(perl -e "print time + $limit")
    while [ "$(date +%s)" -le "$end" ]; do
        hit=$(tail -n +"$((after + 1))" "$MARKS" | awk -v n="$name" '$2 == n' | grep -F -- "$text" | head -1)
        [ -n "$hit" ] && { echo "$hit"; return 0; }
        sleep 0.05
    done
    return 1
}
# key_before <time> [code]: the clock time of the last key mark (of that key code) at or before <time>.
key_before() {
    awk -v t="$1" -v c="${2:-}" '$2 == "key" && $1 <= t && (c == "" || $3 == "code=" c) { k = $1 } END { if (k) print k }' "$MARKS"
}
ms_between() { perl -e "printf '%.0f', ($2 - $1) * 1000"; }

field() { echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
stamp() { echo "$1" | awk '{print $1}'; }

# stalls <from> <to>: "<dropped frames> <stalls over 50 ms> <longest ms> <busy ms>" for the stalls that overlap
# the time between two clock times. A stall is written when it ends, so it started ms before its mark.
stalls() {
    awk -v a="$1" -v b="$2" '$2 == "stall" { sub("ms=", "", $3); ms = $3 + 0 }
        $2 == "stall" && $1 >= a && $1 - ms / 1000 <= b {
        d += int(ms / 16.7); if (ms > 50) n++; if (ms > m) m = ms; s += ms }
        END { printf "%d %d %.1f %.1f", d, n, m, s }' "$MARKS"
}

# record <moment> <value> <unit>
record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RAW"; echo "  $1 = $2 $3"; }

clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes \
             searchFileContents searchSystemFiles searchRecentDropdown recentSearches searchBoxWidth \
             openFolioTo browseFoldersOwnWindow singleClickOpen singleClickUnderline showRecentFiles showFrequentFolders \
             fileIconOnThumbnails folderTipSizes fullPathInTitle hideEmptyDrives hideFolderMergeConflicts hideProtectedFiles \
             showDriveLetters showCompressedInColour showInfoTips showPreviewHandlers showStatusBar typeIntoSearch confirmDelete \
             navPaneShowAllFolders navPaneShowNetwork navPaneShowThisPC searchDontUseIndex searchZippedFolders; do
        defaults delete com.anshul.folio "$k" >/dev/null 2>&1
    done
}

quit_folio() {
    osa 'quit app "Folio"'
    local i=0
    while pgrep -x Folio >/dev/null && [ "$i" -lt 60 ]; do sleep 0.25; i=$((i + 1)); done
    pgrep -x Folio >/dev/null && pkill -9 -x Folio
    sleep 0.5
}

# The path as Folio shows it: a standardized URL drops /private from /private/tmp.
shown() { echo "${1#/private}"; }

# launch <folder>: Folio started on it with tracing; prints the rows mark (empty when it never drew).
launch() {
    local before
    before=$(lines)
    open -a "$APP" "$1" --args -perfTrace "$MARKS"
    wait_mark rows "$before" 60 "path=$(shown "$1")"
}

# nav <folder>: Cmd+L, the path, Return; prints the rows mark for it.
nav() {
    local before
    front
    key 'keystroke "l" using command down'
    sleep 0.25
    key 'keystroke "a" using command down'
    key "keystroke \"$1\""
    sleep 0.3
    before=$(lines)
    NAV_T=$(now)
    key 'key code 36'
    wait_mark rows "$before" 120 "path=$(shown "$1")"
}

sort_by() { osa "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$1\" of menu 1 of menu item \"Sort By\" of menu 1 of menu bar item \"View\" of menu bar 1"; }

# The Details list's middle, on screen, for wheel events.
list_middle() {
    osascript -e 'tell application "System Events" to tell process "Folio"
        set {px, py} to position of scroll area 2 of window 1
        set {sx, sy} to size of scroll area 2 of window 1
        return ((px + (sx div 2)) as text) & " " & ((py + (sy div 2)) as text)
    end tell' 2>/dev/null
}

# A point in the window's list area (right of the navigation pane), whatever the view.
win_point() {
    osascript -e 'tell application "System Events" to tell process "Folio"
        set {px, py} to position of window 1
        set {sx, sy} to size of window 1
        return ((px + (sx * 62 div 100)) as text) & " " & ((py + (sy * 55 div 100)) as text)
    end tell' 2>/dev/null
}

cpu_seconds() { ps -o time= -p "$1" | awk -F: '{ if (NF == 3) print $1 * 3600 + $2 * 60 + $3; else print $1 * 60 + $2 }'; }

FLAT="$FIX/flat"
quit_folio
clean_defaults
osa 'tell application "System Events" to tell appearance preferences to set dark mode to true'

# --- launch ---------------------------------------------------------------------------------------------
if wants launch; then
    echo "perf: launch (cache: $([ $CANPURGE = 1 ] && echo 'purged before each' || echo 'warm, no sudo for purge'))"
    for r in $(seq 1 "$RUNS"); do
        quit_folio
        [ $CANPURGE = 1 ] && sudo -n purge
        t0=$(now)
        m=$(launch "$FLAT/f1k")
        [ -n "$m" ] || { fail "launch run $r: no rows mark"; continue; }
        record launch-script "$(perl -e "printf '%.0f', ($(stamp "$m") - $t0) * 1000")" ms
        record launch-app "$(field "$m" launch_ms)" ms
        record launch-mb "$(field "$m" mb)" MB
    done
    shot perf-1-launch
fi

# Everything else runs in one Folio, started on a small folder.
quit_folio
m=$(launch "$FLAT/small")
[ -n "$m" ] || { echo "perf: Folio did not draw $FLAT/small"; exit 1; }
front
osa 'tell application "System Events" to tell process "Folio" to keystroke "6" using {control down, shift down}'
sleep 0.5

# --- open and sort ---------------------------------------------------------------------------------------
for n in 1k 10k 50k 200k; do
    wants open || wants sort || break
    for r in $(seq 1 "$RUNS"); do
        nav "$FLAT/small" >/dev/null
        m=$(nav "$FLAT/f$n")
        [ -n "$m" ] || { fail "open-$n run $r: no rows mark"; continue; }
        t1=$(stamp "$m")
        k=$(key_before "$t1" 36)
        [ -n "$k" ] && record "open-$n" "$(ms_between "$k" "$t1")" ms
        record "open-$n-load" "$(field "$m" ms)" ms
        record "open-$n-mb" "$(field "$m" mb)" MB
        set -- $(stalls "${k:-$NAV_T}" "$t1")
        record "open-$n-longest-stall" "$3" ms
        if wants sort; then
            worst=0
            for k in "Size" "Date modified" "Name"; do
                before=$(lines)
                sort_by "$k"
                a=$(wait_mark arranged "$before" 120)
                [ -n "$a" ] || { fail "sort-$n $k run $r: no arranged mark"; continue; }
                record "sort-$n-$(echo "$k" | tr ' ' '-' | tr 'A-Z' 'a-z')" "$(field "$a" ms)" ms
                set -- $(stalls "$(perl -e "print $(stamp "$a") - $(field "$a" ms) / 1000")" "$(stamp "$a")")
                [ "${3%.*}" -gt "${worst:-0}" ] && worst=${3%.*}
            done
            record "sort-$n-longest-stall" "$worst" ms
        fi
    done
    [ "$n" = 200k ] && shot perf-2-open-200k
done

# --- typing to filter ------------------------------------------------------------------------------------
if wants filter; then
    for r in $(seq 1 "$RUNS"); do
        nav "$FLAT/f50k" >/dev/null || { fail "filter: f50k did not open"; break; }
        sleep 0.5
        before=$(lines)
        t0=$(now)
        key 'keystroke "f" using command down'
        sleep 0.3
        key 'keystroke "IMG_0123"'
        d=$(wait_mark search-done "$before" 60)
        [ -n "$d" ] || { fail "filter run $r: no search-done"; continue; }
        a=$(wait_mark arranged "$before" 30 "done=1")
        if [ -n "$a" ]; then
            k=$(key_before "$(stamp "$a")")
            [ -n "$k" ] && record filter-50k "$(ms_between "$k" "$(stamp "$a")")" ms
        fi
        record filter-50k-search "$(field "$d" ms)" ms
        record filter-50k-hits "$(field "$d" hits)" items
        set -- $(stalls "$t0" "$(stamp "${a:-$d}")")
        record filter-50k-longest-stall "$3" ms
        [ "$r" = 1 ] && shot perf-3-filter-50k
        key 'key code 53'
        sleep 0.5
    done
fi

# --- select all in the 200k folder -------------------------------------------------------------------------
if wants selectall; then
    for r in $(seq 1 "$RUNS"); do
        nav "$FLAT/f200k" >/dev/null || { fail "selectall: f200k did not open"; break; }
        sleep 1
        t0=$(now)
        key 'keystroke "a" using command down'
        sleep 2.5
        set -- $(stalls "$t0" "$(now)")
        record selectall-200k-longest-stall "$3" ms
        record selectall-200k-busy "$4" ms
        [ "$r" = 1 ] && shot perf-3b-selectall-200k
        key 'key code 53'
    done
fi

# --- scrolling the 50k folder ------------------------------------------------------------------------------
if wants scroll; then
    nav "$FLAT/f50k" >/dev/null
    sleep 1
    pt=$(list_middle)
    if [ -z "$pt" ]; then fail "scroll: no list on screen"; else
        for r in $(seq 1 "$RUNS"); do
            key 'key code 115' # Home: back to the top
            sleep 0.8
            t0=$(now)
            "$TOOL" scroll ${pt% *} ${pt#* } 240 -60 120 >/dev/null
            sleep 0.4
            t1=$(now)
            set -- $(stalls "$t0" "$t1")
            record scroll-50k-dropped "$1" frames
            record scroll-50k-over50 "$2" stalls
            record scroll-50k-longest "$3" ms
            [ "$r" = 1 ] && shot perf-4-scrolled-50k
        done
    fi
fi

# --- view switches -----------------------------------------------------------------------------------------
if wants view; then
    nav "$FLAT/f10k" >/dev/null
    for r in $(seq 1 "$RUNS"); do
        sleep 0.5
        before=$(lines)
        osa 'tell application "System Events" to tell process "Folio" to keystroke "2" using {control down, shift down}'
        v=$(wait_mark view "$before" 30 "mode=largeIcons")
        [ -n "$v" ] && record view-10k-to-icons "$(field "$v" ms)" ms
        [ "$r" = 1 ] && shot perf-5-icons-10k
        sleep 0.5
        before=$(lines)
        osa 'tell application "System Events" to tell process "Folio" to keystroke "6" using {control down, shift down}'
        v=$(wait_mark view "$before" 30 "mode=details")
        [ -n "$v" ] && record view-10k-to-details "$(field "$v" ms)" ms
    done
fi
if wants thumbs; then
    for r in $(seq 1 "$RUNS"); do
        dir="$RUN/photos-$r"
        "$TOOL" images "$dir" 300 "$r$STAMP" >/dev/null
        nav "$dir" >/dev/null || { fail "thumbs: $dir did not open"; continue; }
        sleep 1
        before=$(lines)
        osa 'tell application "System Events" to tell process "Folio" to keystroke "2" using {control down, shift down}'
        v=$(wait_mark view "$before" 30 "mode=largeIcons")
        t=$(wait_mark thumbs-idle "$before" 60)
        [ -n "$v" ] && record thumbs-300-view "$(field "$v" ms)" ms
        if [ -n "$t" ]; then
            record thumbs-300-all-made "$(perl -e "printf '%.0f', ($(stamp "$t") - $(stamp "$v")) * 1000 + $(field "$v" ms)")" ms
            record thumbs-300-made "$(field "$t" made)" thumbnails
        else
            fail "thumbs run $r: no thumbs-idle mark"
        fi
        set -- $(stalls "$(stamp "$v")" "$(stamp "${t:-$v}")")
        record thumbs-300-longest-stall "$3" ms
        [ "$r" = 1 ] && shot perf-6-thumbnails
        pt=$(win_point)
        if [ -n "$pt" ]; then
            t0=$(now)
            "$TOOL" scroll ${pt% *} ${pt#* } 120 -60 120 >/dev/null
            sleep 0.5
            set -- $(stalls "$t0" "$(now)")
            record thumbs-300-scroll-dropped "$1" frames
            record thumbs-300-scroll-longest "$3" ms
            [ "$r" = 1 ] && shot perf-6b-thumbnails-scrolled
        fi
        osa 'tell application "System Events" to tell process "Folio" to keystroke "6" using {control down, shift down}'
        sleep 0.5
    done
fi

# --- search over the 200k tree ---------------------------------------------------------------------------------
if wants search; then
    for r in $(seq 1 "$RUNS"); do
        nav "$FIX/tree200k" >/dev/null || { fail "search: tree did not open"; break; }
        sleep 0.5
        key 'keystroke "f" using command down'
        sleep 0.3
        key 'keystroke "zqneedle"'
        before=$(lines)
        t0=$(now)
        key 'key code 36'
        d=$(wait_mark search-done "$before" 300)
        [ -n "$d" ] || { fail "search run $r: no search-done"; continue; }
        a=$(wait_mark arranged "$before" 30 "done=1")
        record search-200k "$(field "$d" ms)" ms
        record search-200k-hits "$(field "$d" hits)" items
        if [ -n "$a" ]; then
            k=$(key_before "$(stamp "$a")" 36)
            [ -n "$k" ] && record search-200k-drawn "$(ms_between "$k" "$(stamp "$a")")" ms
        fi
        set -- $(stalls "$t0" "$(stamp "${a:-$d}")")
        record search-200k-longest-stall "$3" ms
        [ "$r" = 1 ] && shot perf-7-search-200k
        key 'key code 53'
        sleep 0.5
    done
fi

# --- copy 2 GB to another volume -----------------------------------------------------------------------------
free_gb=$(df -g /private/tmp | tail -1 | awk '{print $4}')
if wants copy && [ ! -f "$FIX/big/big.bin" ] && [ "$free_gb" -ge 6 ]; then
    "$TOOL" big "$FIX/big" >/dev/null
    free_gb=$(df -g /private/tmp | tail -1 | awk '{print $4}')
fi
if wants copy && { [ "$free_gb" -lt 3 ] || [ ! -f "$FIX/big/big.bin" ]; }; then
    fail "copy: $free_gb GB free on the VM's disk (6 needed to make the 2 GB file, 3 more to copy it); skipped"
elif wants copy; then
    hdiutil create -size 3g -type SPARSE -fs APFS -volname FolioPerf "$RUN/perf" >/dev/null 2>&1
    vol=$(hdiutil attach -nobrowse "$RUN/perf.sparseimage" 2>/dev/null | awk -F'\t' '/FolioPerf/ {print $NF}' | tail -1)
    if [ -z "$vol" ] || [ ! -d "$vol" ]; then fail "copy: the disk image did not mount"; else
        mkdir -p "$vol/dst"
        for r in $(seq 1 "$RUNS"); do
            rm -f "$vol/dst/big.bin"
            nav "$FIX/big" >/dev/null || { fail "copy: big did not open"; break; }
            sleep 0.5
            key 'keystroke "a" using command down'
            key 'keystroke "c" using command down'
            nav "$vol/dst" >/dev/null || { fail "copy: $vol/dst did not open"; break; }
            sleep 0.5
            before=$(lines)
            key 'keystroke "v" using command down'
            j=$(wait_mark job-done "$before" 120)
            [ -n "$j" ] || { fail "copy run $r: no job-done"; continue; }
            ms=$(field "$j" ms)
            record copy-2gb "$ms" ms
            record copy-2gb-rate "$(perl -e "printf '%.0f', $(field "$j" bytes) / 1048576 / ($ms / 1000)")" MB/s
            [ "$(stat -f %z "$vol/dst/big.bin" 2>/dev/null)" = "$(stat -f %z "$FIX/big/big.bin")" ] || fail "copy run $r: sizes differ"
        done
        nav "$FLAT/small" >/dev/null
        sleep 1
        hdiutil detach -force "$vol" >/dev/null 2>&1
        rm -f "$RUN/perf.sparseimage"
    fi
fi
# The 2 GB file does not stay on the shared disk.
rm -f "$FIX/big/big.bin"

# --- memory after 50 folders -------------------------------------------------------------------------------------
if wants memory; then
    for r in $(seq 1 "$RUNS"); do
        quit_folio
        m=$(launch "$FLAT/small")
        front
        start_mb=$(field "$m" mb)
        i=0
        for a in 00 01 02 03 04; do
            for b in 00 01 02 03 04 05 06 07 08 09; do
                m=$(nav "$FIX/tree200k/Area $a/Part $b") || fail "memory: Area $a/Part $b did not open"
                i=$((i + 1))
            done
        done
        sleep 3
        pid=$(pgrep -x Folio | head -1)
        record memory-50-footprint "$(field "$m" mb)" MB
        record memory-50-rss "$(ps -o rss= -p "$pid" | awk '{printf "%.1f", $1 / 1024}')" MB
        record memory-start-footprint "$start_mb" MB
    done
fi

# --- CPU under churn ---------------------------------------------------------------------------------------------
if wants churn; then
    mkdir -p "$RUN/churn/deep/er"
    for r in $(seq 1 "$RUNS"); do
        nav "$RUN/churn" >/dev/null
        sleep 1
        pid=$(pgrep -x Folio | head -1)
        c0=$(cpu_seconds "$pid")
        t0=$(now)
        "$TOOL" churn "$RUN/churn/deep/er" 20 100 >/dev/null
        sleep 1
        c1=$(cpu_seconds "$pid")
        record churn-cpu "$(perl -e "printf '%.2f', $c1 - $c0")" s
        set -- $(stalls "$t0" "$(now)")
        record churn-stalls "$(awk -v a="$t0" '$2 == "stall" && $1 >= a' "$MARKS" | wc -l | tr -d ' ')" stalls
    done
fi

# --- auto-refresh in a big folder that keeps changing ------------------------------------------------------
if wants refresh; then
    for size in 10k 50k; do
        n=${size%k}000
        "$TOOL" files "$RUN/busy-$size" "$n" >/dev/null
        for r in $(seq 1 "$RUNS"); do
            nav "$RUN/busy-$size" >/dev/null || { fail "refresh: busy-$size did not open"; break; }
            sleep 1
            pid=$(pgrep -x Folio | head -1)
            c0=$(cpu_seconds "$pid")
            before=$(lines)
            t0=$(now)
            "$TOOL" churn "$RUN/busy-$size" 10 5 >/dev/null
            sleep 1.5
            t1=$(now)
            c1=$(cpu_seconds "$pid")
            record refresh-$size-cpu "$(perl -e "printf '%.2f', $c1 - $c0")" s
            tail -n +"$((before + 1))" "$MARKS" | awk '$2 == "rows"' > "$RUN/refreshes.txt"
            record refresh-$size-count "$(wc -l < "$RUN/refreshes.txt" | tr -d ' ')" refreshes
            each=$(sed -n 's/.* ms=\([0-9.]*\) .*/\1/p' "$RUN/refreshes.txt" | sort -g | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)] }')
            [ -n "$each" ] && record refresh-$size-each "$each" ms
            set -- $(stalls "$t0" "$t1")
            record refresh-$size-longest-stall "$3" ms
        done
    done
fi

quit_folio

# --- the steps on their own (Folio --bench, VM only; older builds do not have it) --------------------------
: > "$RUN/bench.txt"
if wants bench && grep -q "Folio --bench" "$APP/Contents/MacOS/Folio"; then
    for n in 50k 200k; do "$APP/Contents/MacOS/Folio" --bench "$FLAT/f$n" 5 >> "$RUN/bench.txt" 2>&1; done
fi

# --- the table ---------------------------------------------------------------------------------------------------
{
    echo "Folio $(defaults read "$APP/Contents/Info" FolioVersion 2>/dev/null) ${LABEL:+($LABEL) }$(date '+%Y-%m-%d %H:%M'), runs=$RUNS, $(df -h /private/tmp | tail -1 | awk '{print $4}') free"
    [ "$fails" -gt 0 ] && echo "FAILED: $fails (see the run's output)"
    printf '%-30s %3s %9s %9s %9s  %s\n' moment n median min max unit
    awk -F'\t' '{ v[$1] = v[$1] " " $2; u[$1] = $3; if (!($1 in seen)) { seen[$1] = 1; order[++k] = $1 } }
        END { for (i = 1; i <= k; i++) print order[i] "\t" u[order[i]] "\t" v[order[i]] }' "$RAW" |
    while IFS=$'\t' read -r name unit vals; do
        sorted=$(echo $vals | tr ' ' '\n' | sort -g)
        n=$(echo "$sorted" | wc -l | tr -d ' ')
        med=$(echo "$sorted" | awk -v n="$n" 'NR == int((n + 1) / 2)')
        printf '%-30s %3s %9s %9s %9s  %s\n' "$name" "$n" "$med" "$(echo "$sorted" | head -1)" "$(echo "$sorted" | tail -1)" "$unit"
    done
    cat "$RUN/bench.txt"
} > "$RUN/results.txt"
cat "$RUN/results.txt"
cp "$RUN/results.txt" "$SHOTS/perf-results${LABEL:+-$LABEL}.txt.png"
cp "$MARKS" "$SHOTS/perf-marks${LABEL:+-$LABEL}.txt.png"
# The run's bulky leftovers go (the fixtures stay for the next run).
rm -rf "$RUN"/photos-* "$RUN"/busy-* "$RUN/churn" "$RUN/perf.sparseimage" 2>/dev/null
echo "perf: raw values in $RAW, marks in $MARKS"
if [ "$fails" -eq 0 ]; then echo "result: ok"; else echo "result: $fails failed"; exit 1; fi
