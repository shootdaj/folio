#!/bin/bash
# Release signing check: a Full Disk Access grant made for one Folio build stays with the next build signed
# with the same certificate (an update), and does not carry over to an ad hoc build. Folio > Full Disk
# Access… opens that System Settings page.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Three builds of Folio, installed one after another at the same place, as an update would:
#   A   signed with a certificate
#   B   a different build (another version, so another code hash), signed with the same certificate
#   B'  the same B, signed ad hoc, as every release up to 1.0.0 was
# Where they come from:
#   - ~/folio/signing/{A,B,Bprime}.app when present: builds signed on the Mac Ultra with Folio Release
#     Signing (tools/ci/build.sh --release), copied in for a check of the release identity itself; the
#     folder goes to the Trash at the end, so the next run is back to the default;
#   - otherwise made here from ~/folio/Folio.app, signed with a throwaway self-signed certificate in a
#     temporary keychain under /private/tmp/folio-tests/signing-<stamp>/ (deleted at the end). No release
#     keychain is needed.
#
# The grant is what flipping Folio's switch in System Settings writes: a row in the system TCC.db for
# com.anshul.folio holding A's designated requirement (written here with sqlite; the VM has SIP off). The
# same requirement goes in an Input Monitoring row (kTCCServiceListenEvent), because tccd checks that
# service for Folio at every launch and logs how the build matched the stored requirement
# (SecStaticCodeCheckValidity, status 0 = matched): that log is tccd's own verdict on each build, the same
# check it makes for Full Disk Access. With SIP off, macOS guards no folder (Terminal without Full Disk
# Access lists ~/Library/Mail here), so whether ~/Library/Mail lists or is blocked is asserted only when
# the VM has SIP on; with SIP off those shots are a record. Every row is removed at the end.
# PNGs go to ~/folio/shots/:
#   signing-1-a-nogrant.png      A, no grant: ~/Library/Mail (blocked, with the status line, when SIP is on)
#   signing-2a-menu.png          the Folio menu open: Full Disk Access… under Keep Running When the Last Window Closes
#   signing-2-settings.png       Folio > Full Disk Access…: System Settings at Privacy & Security > Full Disk Access
#   signing-3-a-granted.png      A after the grant: ~/Library/Mail
#   signing-4-settings-on.png    Folio > Full Disk Access… again: Folio in the list, its switch on
#   signing-5-b-update.png       B installed over A: ~/Library/Mail, the grant untouched
#   signing-6-adhoc.png          B' installed over B: ~/Library/Mail (blocked when SIP is on)
# Prints one line per step and exits non-zero if any step fails.
set -u

STAGED="$HOME/folio/Folio.app"
PRESIGNED="$HOME/folio/signing"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/signing-$STAMP"
INSTALL="$ROOT/Applications/Folio.app"
DB="/Library/Application Support/com.apple.TCC/TCC.db"
FDA=kTCCServiceSystemPolicyAllFiles
INPUT=kTCCServiceListenEvent
ID=com.anshul.folio
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
MAIL="$HOME/Library/Mail"
BLOCKED="macOS blocked this folder. Folio > Full Disk Access… fixes it for all folders."
KC=""
SEARCH_LIST=""
sign_errors=""
failed=""
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "signing: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if ! sudo -n true 2>/dev/null; then
    echo "signing: needs passwordless sudo for the TCC database (docs/plan/VM.md)"
    exit 2
fi
[ -d "$MAIL" ] || { echo "signing: missing $MAIL in the VM"; exit 2; }
if csrutil status | grep -q enabled; then guarded=yes; else guarded=no; fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); failed="$failed $1"; }

frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }
front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }
window_names() {
    osascript -e 'tell application "System Events" to tell process "Folio" to get name of every window' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}
has_window() { window_names | grep -Fxq "$1"; }
wait_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}
shot() {
    local f="$SHOTS/$1.png"
    rm -f "$f"
    screencapture -x "$f" 2>/dev/null
    if [ -s "$f" ]; then echo "$f"; fi
}
menu_bar() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$2\" of menu \"$1\" of menu bar 1" >/dev/null 2>&1
}

# status_text <window>: the status bar's text (its accessibility value), among the window's UI elements and
# theirs (`entire contents` comes back empty for this window in the VM), as m3.sh reads it.
status_text() {
    osascript - "$1" 2>/dev/null <<'OSA'
on isStatus(e)
    tell application "System Events"
        try
            return (role of e is "AXGroup") and (description of e is "Status bar")
        end try
    end tell
    return false
end isStatus

on run argv
    set winName to item 1 of argv
    tell application "System Events" to tell process "Folio"
        if not (exists window winName) then return "no window"
        set top to UI elements of window winName
        repeat with e in top
            if my isStatus(e) then return (value of e) as text
        end repeat
        repeat with c in top
            try
                repeat with e in (UI elements of c)
                    if my isStatus(e) then return (value of e) as text
                end repeat
            end try
        end repeat
    end tell
    return "missing"
end run
OSA
}
# wait_status <window>: the status bar once the folder is read (not "Loading ...").
wait_status() {
    local s i=0
    while [ "$i" -lt 40 ]; do
        s=$(status_text "$1")
        case "$s" in "Loading"*|""|missing|"no window") ;; *) echo "$s"; return ;; esac
        sleep 0.25
        i=$((i + 1))
    done
    echo "$s"
}
listed() { [[ "$1" =~ ^[0-9,]+\ items?, ]]; }

# A macOS privacy prompt ("Folio would like to access ...") on screen.
prompt_up() {
    local n
    n=$(osascript -e 'tell application "System Events" to count windows of process "UserNotificationCenter"' 2>/dev/null)
    [ "${n:-0}" -gt 0 ]
}

quit_folio() {
    osascript -e 'quit app "Folio"' >/dev/null 2>&1
    sleep 1
    pkill -x Folio 2>/dev/null
    sleep 0.5
}
quit_settings() {
    osascript -e 'quit app "System Settings"' >/dev/null 2>&1
    sleep 1
    pkill -x "System Settings" 2>/dev/null
}
# wait_settings: System Settings' front window name once it reads "Full Disk Access" (or after 20 s).
wait_settings() {
    local pane="" i
    for i in $(seq 1 40); do
        pane=$(osascript -e 'tell application "System Events" to tell process "System Settings" to get name of window 1' 2>/dev/null)
        [ "$pane" = "Full Disk Access" ] && break
        sleep 0.5
    done
    echo "$pane"
}

# The grant, as System Settings' switch writes it, and what TCC holds for Folio.
tcc() { sudo sqlite3 "$DB" "$1"; }
tcc_rows() { tcc "select service||' '||auth_value||' '||hex(csreq)||' '||last_modified from access where client='$ID' and service in ('$FDA', '$INPUT') order by service"; }
tcc_reload() { sudo killall tccd 2>/dev/null; killall tccd 2>/dev/null; sleep 1; }
tcc_clear() {
    tcc "delete from access where client='$ID' and service in ('$FDA', '$INPUT')"
    tcc_reload
}
requirement() { codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'; }
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
grant() {
    local hex s
    csreq -r="$(requirement "$1")" -b "$ROOT/grant.csreq" || return 1
    hex=$(xxd -p "$ROOT/grant.csreq" | tr -d '\n')
    for s in "$FDA" "$INPUT"; do
        tcc "insert or replace into access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, indirect_object_identifier) values ('$s', '$ID', 0, 2, 3, 1, X'$hex', 0, 'UNUSED')"
    done
    tcc_reload
}
# The requirement stored in the Full Disk Access row, as a file codesign -R reads.
stored_requirement() { tcc "select hex(csreq) from access where client='$ID' and service='$FDA'" | xxd -r -p > "$ROOT/stored.csreq"; }
# tccd_verdict <since>: how tccd matched the launched build against the stored requirement: the statuses
# of SecStaticCodeCheckValidity for Folio and a certificate requirement (0 matched, -67050 did not).
tccd_verdict() {
    log show --start "$1" --info --predicate 'subsystem == "com.apple.TCC"' --style compact 2>/dev/null \
        | grep 'matchesCodeRequirement' | grep "from $ID : identifier \"$ID\" and certificate leaf" \
        | sed -n 's/.*; status: //p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# install <app>: the build at the one install place, the previous one moved aside first.
install() {
    quit_folio
    if [ -d "$INSTALL" ]; then
        "$LSREGISTER" -u "$INSTALL" >/dev/null 2>&1
        mv "$INSTALL" "$ROOT/replaced-$(date +%H%M%S)-$RANDOM.app"
    fi
    ditto "$1" "$INSTALL"
}

# open_mail: opens ~/Library/Mail in the installed Folio; prints the status bar.
open_mail() {
    open -a "$INSTALL" "$MAIL"
    if ! wait_window Mail 15; then
        echo "no window Mail (windows: $(window_names | paste -sd '|' -))"
        return
    fi
    front
    sleep 1.5
    wait_status Mail
}

# check_build <step> <name> <app> <shot> granted|denied: installs the build, opens ~/Library/Mail and checks
# tccd's verdict on it, the stored requirement (codesign -R) and, with SIP on, the folder itself.
check_build() {
    local mark s f v req p=no want_v want_req ok=yes
    install "$3"
    mark=$(date '+%Y-%m-%d %H:%M:%S')
    sleep 1
    s=$(open_mail)
    prompt_up && p=yes
    f=$(shot "$4")
    sleep 1
    v=$(tccd_verdict "$mark")
    if codesign --verify -R "$ROOT/stored.csreq" "$INSTALL" 2>/dev/null; then req=yes; else req=no; fi
    if [ "$5" = granted ]; then want_v=0; want_req=yes; else want_v=-67050; want_req=no; fi
    [ "$v" = "$want_v" ] || ok=no
    [ "$req" = "$want_req" ] || ok=no
    [ "$p" = no ] || ok=no
    [ -n "$f" ] || ok=no
    if [ "$guarded" = yes ]; then
        if [ "$5" = granted ]; then listed "$s" || ok=no; else [ "$s" = "$BLOCKED" ] || ok=no; fi
    fi
    local what="$(defaults read "$INSTALL/Contents/Info" FolioVersion) cdhash $(cdhash "$INSTALL" | cut -c1-12): tccd verdict [$v], meets the stored requirement: $req, prompt: $p, ~/Library/Mail [$s]"
    if [ "$ok" = yes ]; then pass "$1" "$2" "$what, $f"; else fail "$1" "$2" "$what (want verdict $want_v, requirement $want_req), shot: ${f:-none}"; fi
}

cleanup() {
    quit_folio
    quit_settings
    tcc_clear
    for a in "$INSTALL" "$ROOT"/*.app "$PRESIGNED"/*.app; do
        [ -d "$a" ] && "$LSREGISTER" -u "$a" >/dev/null 2>&1
    done
    if [ -n "$KC" ]; then
        # shellcheck disable=SC2086
        [ -n "$SEARCH_LIST" ] && security list-keychains -d user -s $SEARCH_LIST
        security delete-keychain "$KC" 2>/dev/null
    fi
    if [ -d "$PRESIGNED" ]; then mv "$PRESIGNED" "$HOME/.Trash/folio-signing-$STAMP"; fi
}
trap cleanup EXIT

# --- 0: the three builds ------------------------------------------------------------------------------------
mkdir -p "$SHOTS" "$ROOT/Applications"
if [ -d "$PRESIGNED/A.app" ] && [ -d "$PRESIGNED/B.app" ] && [ -d "$PRESIGNED/Bprime.app" ]; then
    source="release-signed builds from $PRESIGNED"
    for v in A B Bprime; do ditto "$PRESIGNED/$v.app" "$ROOT/$v.app"; done
else
    [ -d "$STAGED" ] || { echo "signing: missing $STAGED (stage the build first, docs/plan/VM.md)"; exit 2; }
    # A throwaway certificate, made as tools/ci/release-signing.sh's identity was, in a keychain of its own.
    KC="$ROOT/test-signing.keychain-db"
    pw=$(openssl rand -hex 16)
    transfer=$(openssl rand -hex 16)
    key=$(openssl genrsa -aes256 -passout "pass:$transfer" 2048 2>/dev/null)
    openssl req -new -x509 -days 2 -sha256 -key <(printf '%s\n' "$key") -passin "pass:$transfer" \
        -out "$ROOT/test-signing.pem" -config <(printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Folio Test Signing %s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$STAMP")
    security create-keychain -p "$pw" "$KC"
    openssl pkcs12 -export -inkey <(printf '%s\n' "$key") -passin "pass:$transfer" -in "$ROOT/test-signing.pem" \
        -passout "pass:$transfer" | security import /dev/stdin -k "$KC" -f pkcs12 -P "$transfer" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$pw" "$KC" >/dev/null 2>&1
    security unlock-keychain -p "$pw" "$KC"
    SEARCH_LIST=$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $SEARCH_LIST "$KC"
    cert=$(openssl x509 -in "$ROOT/test-signing.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
    version=$(defaults read "$STAGED/Contents/Info" FolioVersion)
    for v in A B Bprime; do
        ditto --noextattr "$STAGED" "$ROOT/$v.app"
        xattr -cr "$ROOT/$v.app"
        tag=$v; [ "$v" = Bprime ] && tag=B
        /usr/libexec/PlistBuddy -c "Set :FolioVersion $version-signing-$tag" "$ROOT/$v.app/Contents/Info.plist"
        if [ "$v" = Bprime ]; then
            out=$(codesign --force --deep -s - "$ROOT/$v.app" 2>&1)
        else
            out=$(codesign --force --deep --timestamp=none --keychain "$KC" -s "$cert" "$ROOT/$v.app" 2>&1)
        fi
        [ $? -eq 0 ] || sign_errors="$sign_errors codesign $v: $(echo "$out" | tr '\n' ' ')"
    done
    security lock-keychain "$KC"
    source="made here from $STAGED, throwaway certificate $cert"
fi
ra=$(requirement "$ROOT/A.app"); rb=$(requirement "$ROOT/B.app"); rp=$(requirement "$ROOT/Bprime.app")
ha=$(cdhash "$ROOT/A.app"); hb=$(cdhash "$ROOT/B.app"); hp=$(cdhash "$ROOT/Bprime.app")
adhoc=$(codesign -dv "$ROOT/Bprime.app" 2>&1 | grep -c '^Signature=adhoc')
echo "builds: $source; SIP on (folders guarded): $guarded"
echo "  A  $(defaults read "$ROOT/A.app/Contents/Info" FolioVersion) cdhash $ha"
echo "  B  $(defaults read "$ROOT/B.app/Contents/Info" FolioVersion) cdhash $hb"
echo "  B' $(defaults read "$ROOT/Bprime.app/Contents/Info" FolioVersion) cdhash $hp, ad hoc"
echo "  A and B require: $ra"
if [[ "$ra" == "identifier \"$ID\" and certificate leaf = H\""* ]] && [ "$ra" = "$rb" ] && [ "$ha" != "$hb" ] \
    && [ "$adhoc" = 1 ] && [ "$rp" != "$ra" ] && codesign --verify --deep --strict "$ROOT/A.app" \
    && codesign --verify --deep --strict "$ROOT/B.app"; then
    pass 0 builds "A and B: one certificate requirement, two code hashes; B' ad hoc"
else
    fail 0 builds "A [$ra] B [$rb] B' [$rp], cdhash A $ha B $hb, B' ad hoc: $adhoc.$sign_errors"
    echo "result: the builds are not as expected"
    exit 1
fi

# A clean start: no Folio, no grant for it, the Mac in dark mode.
quit_folio
quit_settings
tcc_clear
defaults delete com.anshul.folio addressHistory >/dev/null 2>&1
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1

# --- 1: A, no grant yet ---------------------------------------------------------------------------------------
install "$ROOT/A.app"
s=$(open_mail)
f=$(shot signing-1-a-nogrant)
if [ "$guarded" = yes ]; then
    if [ "$s" = "$BLOCKED" ] && [ -n "$f" ]; then pass 1 a-blocked "no grant: [$s], $f"; else fail 1 a-blocked "status [$s], expected [$BLOCKED], shot: ${f:-none}"; fi
else
    echo "step 1 a-nogrant: record - SIP is off, so macOS guards no folder here: ~/Library/Mail [$s], ${f:-no shot}"
fi

# --- 2: Folio > Full Disk Access… opens System Settings at Full Disk Access ------------------------------------
# The Folio menu opened by a click, the item clicked in it, as a person would.
front
osascript -e 'tell application "System Events" to tell process "Folio" to click menu bar item "Folio" of menu bar 1' >/dev/null 2>&1
sleep 0.8
m=$(shot signing-2a-menu)
item=$(osascript -e 'tell application "System Events" to tell process "Folio" to get name of every menu item of menu 1 of menu bar item "Folio" of menu bar 1' 2>/dev/null | tr ',' '\n' | sed 's/^ *//' | grep -Fx "Full Disk Access…")
osascript -e 'tell application "System Events" to tell process "Folio" to click menu item "Full Disk Access…" of menu 1 of menu bar item "Folio" of menu bar 1' >/dev/null 2>&1
pane=$(wait_settings)
sleep 1.5
f=$(shot signing-2-settings)
if [ -n "$item" ] && [ "$pane" = "Full Disk Access" ] && [ "$(frontmost)" = "System Settings" ] && [ -n "$f" ] && [ -n "$m" ]; then
    pass 2 settings "Folio menu lists [$item]; clicked: System Settings frontmost, window [$pane], $m, $f"
else
    fail 2 settings "menu item [$item], System Settings window [$pane], frontmost [$(frontmost)], shots: ${m:-none} ${f:-none}"
fi
quit_settings
quit_folio

# --- 3: the switch flipped for A ------------------------------------------------------------------------------
grant "$INSTALL"
stored_requirement
row=$(tcc_rows)
echo "  grant written for A: $(echo "$row" | grep -c .) rows, requirement $(csreq -r "$ROOT/stored.csreq" -t 2>/dev/null)"
check_build 3 a-granted "$ROOT/A.app" signing-3-a-granted granted

# --- 4: System Settings shows Folio's switch on ---------------------------------------------------------------
front
menu_bar Folio "Full Disk Access…"
pane=$(wait_settings)
sleep 2
f=$(shot signing-4-settings-on)
if [ "$pane" = "Full Disk Access" ] && [ -n "$f" ]; then pass 4 settings-on "window [$pane], $f"; else fail 4 settings-on "window [$pane], shot: ${f:-none}"; fi
quit_settings

# --- 5: B installed over A, the update: the grant holds, nothing new written -----------------------------------
check_build 5 b-update "$ROOT/B.app" signing-5-b-update granted
now=$(tcc_rows)
if [ -n "$row" ] && [ "$now" = "$row" ]; then
    pass 5b no-new-grant "TCC holds the rows written for A, unchanged"
else
    fail 5b no-new-grant "TCC rows changed: before [$row], after [$now]"
fi

# --- 6: B' (ad hoc) installed over B: the grant does not carry over --------------------------------------------
check_build 6 adhoc "$ROOT/Bprime.app" signing-6-adhoc denied

echo
if [ "$fails" -eq 0 ]; then
    echo "result: ok, the grant made for A held for B (same certificate) and not for ad hoc B' ($source)"
else
    echo "result: $fails step(s) failed:$failed"
    exit 1
fi
exit 0
