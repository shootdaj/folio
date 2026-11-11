#!/bin/bash
# release-signing.sh check | sign <app> | lock | verify <app> adhoc|release
#
# Release builds (tools/ci/build.sh --release, run by .github/workflows/release.yml on a tag push) are
# signed with "Folio Release Signing", a self-signed code-signing identity made once on the Mac Ultra
# with openssl. Every release then has the same designated requirement, identifier "com.anshul.folio"
# and certificate leaf = H"<the certificate's SHA-1>", so macOS keeps a Full Disk Access grant from one
# release to the next. The identity lives in its own keychain on the Ultra, never in the repo, never on
# another Mac:
#   /Users/anshul/AgentWork/folio/signing/folio-signing.keychain-db   (only codesign may use the key)
#   /Users/anshul/AgentWork/folio/signing/folio-signing.password      (its password, mode 600)
# PR builds run code from forks: they stay ad hoc and never call check, sign or lock.
#
#   check            exits non-zero unless the keychain and its password file are there
#   sign <app>       unlocks the keychain, adds it to the user's keychain search list (codesign finds
#                    identities only there), signs <app>, then locks it and takes it out of the list again,
#                    on failure too. The password reaches security on stdin, never a command line or a log.
#   lock             locks the keychain and takes it out of the search list; safe to run any time
#   verify <app> adhoc|release
#                    checks the signature: ad hoc, or this identity's designated requirement (prints the hash)
set -euo pipefail

RELEASE_NAME="Folio Release Signing"
# SHA-1 of its certificate (expires 2046-11-06). A new identity changes this, and every Mac then has to
# grant Full Disk Access again.
RELEASE_CERT=9C36E1B63F9B31B1F478AF4E445E1A8975DE2DB9
BUNDLE_ID=com.anshul.folio
KEYCHAIN=${FOLIO_SIGNING_KEYCHAIN:-/Users/anshul/AgentWork/folio/signing/folio-signing.keychain-db}
PASSWORD_FILE=${FOLIO_SIGNING_PASSWORD_FILE:-${KEYCHAIN%.keychain-db}.password}

die() { echo "release-signing.sh: $*" >&2; exit 1; }

# The user's keychain search list without ours, one path per line (security prints them quoted).
others() {
    security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' | grep -vxF "$KEYCHAIN" || true
}
listed() { security list-keychains -d user | grep -qF "\"$KEYCHAIN\""; }
set_list() { # bash 3.2: no mapfile
    local paths=() p
    while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done
    security list-keychains -d user -s ${paths[@]+"${paths[@]}"}
}

check() {
    [ -f "$KEYCHAIN" ] || die "no release keychain at $KEYCHAIN (it lives only on the Mac Ultra)"
    [ -r "$PASSWORD_FILE" ] || die "cannot read the keychain password at $PASSWORD_FILE"
}

lock() {
    security lock-keychain "$KEYCHAIN" 2>/dev/null || true
    if listed; then others | set_list; fi
    echo "release-signing.sh: $KEYCHAIN locked, not in the search list"
}

sign() {
    local app=$1
    check
    trap lock EXIT
    printf 'unlock-keychain -p %s %s\n' "$(cat "$PASSWORD_FILE")" "$KEYCHAIN" | security -i >/dev/null
    { others; echo "$KEYCHAIN"; } | set_list
    codesign --force --deep --timestamp=none --keychain "$KEYCHAIN" -s "$RELEASE_CERT" "$app" \
        || die "codesign with $RELEASE_NAME ($RELEASE_CERT) failed"
    lock
    trap - EXIT
}

verify() {
    local app=$1 kind=$2 info req want
    codesign --verify --deep --strict "$app" || die "codesign --verify failed for $app"
    info=$(codesign -dvv "$app" 2>&1) # -vv adds the Authority lines
    # An ad hoc signature has no requirement of its own; codesign prints the implied one as a comment.
    req=$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')
    echo "designated requirement: ${req:-none ($(codesign -d -r- "$app" 2>&1 | sed -n 's/^# designated => //p'), implied)}"
    case "$kind" in
        adhoc)
            grep -qx 'Signature=adhoc' <<<"$info" || die "$app is not signed ad hoc"
            ;;
        release)
            ! grep -qx 'Signature=adhoc' <<<"$info" || die "$app is signed ad hoc, not with $RELEASE_NAME"
            grep -qx "Authority=$RELEASE_NAME" <<<"$info" || die "$app is not signed by $RELEASE_NAME"
            want="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$(tr 'A-F' 'a-f' <<<"$RELEASE_CERT")\""
            [ "$req" = "$want" ] || die "the designated requirement is [$req], expected [$want]"
            echo "certificate leaf: $RELEASE_CERT ($RELEASE_NAME)"
            ;;
        *) die "verify <app> adhoc|release" ;;
    esac
}

case "${1:-}" in
    check) check ;;
    sign) sign "${2:?sign <app>}" ;;
    lock) lock ;;
    verify) verify "${2:?verify <app> adhoc|release}" "${3:?verify <app> adhoc|release}" ;;
    *) die "usage: release-signing.sh check | sign <app> | lock | verify <app> adhoc|release" ;;
esac
