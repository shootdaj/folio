#!/bin/bash
# The CI build, also run by hand: the script checks, the unit tests, build/Folio.app, its ad-hoc signature
# and the version stamped into it, then build/Folio-<version>.zip and build/ff for the VM tests.
# Runs nothing it builds (docs/plan/RULES.md, rule 0): the version is read from Info.plist with defaults,
# never from Folio --version.
set -euo pipefail
cd "$(dirname "$0")/../.."

step() { echo; echo "== $*"; }
die() { echo "build.sh: $*" >&2; exit 1; }

step "toolchain"
swift --version

step "script checks (tools/ci/test.sh)"
tools/ci/test.sh

step "unit tests (make test)"
make test

step "app bundle (make app)"
make app

step "signature (codesign -dv)"
signature=$(codesign -dv build/Folio.app 2>&1)
echo "$signature"
grep -qx 'Signature=adhoc' <<<"$signature" || die "build/Folio.app is not signed ad hoc"
codesign --verify --deep --strict build/Folio.app || die "codesign --verify failed"

step "version (Info.plist)"
info="$PWD/build/Folio.app/Contents/Info"
version=$(tools/ci/version.sh)
read_info() { defaults read "$info" "$1"; }
check() { # check <key> <want>
    local got
    got=$(read_info "$1")
    echo "$1 = $got"
    [ "$got" = "$2" ] || die "$1 is [$got], expected [$2]"
}
check CFBundleShortVersionString "$(tools/ci/version.sh --short)"
check CFBundleVersion "$(tools/ci/version.sh --build)"
check FolioVersion "$version"
check FolioGitCommit "$(tools/ci/version.sh --sha)"

step "package"
zip="build/Folio-$version.zip"
ditto -c -k --keepParent build/Folio.app "$zip"
cp "$(swift build -c release --show-bin-path)/ff" build/ff
ls -l "$zip" build/ff

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "version=$version"; echo "zip=$zip"; } >> "$GITHUB_OUTPUT"
fi
echo
echo "build.sh: ok, Folio $version ($(read_info FolioGitCommit)), $zip"
