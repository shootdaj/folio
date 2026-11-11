#!/bin/bash
# build.sh [--release]: the CI build, also run by hand: the script checks, the unit tests, build/Folio.app,
# its signature and the version stamped into it, then build/Folio-<version>.zip and build/ff for the VM tests.
# Runs nothing it builds (docs/plan/RULES.md, rule 0): the version is read from Info.plist with defaults,
# never from Folio --version.
# Without --release (pull requests, main, by hand) the app is signed ad hoc, and must be. With --release
# (the tag workflow, on the Mac Ultra only) it is signed with Folio Release Signing, the identity whose
# certificate stays the same from release to release, so a Full Disk Access grant survives updates
# (tools/ci/release-signing.sh). A pull request build never gets there.
set -euo pipefail
cd "$(dirname "$0")/../.."

step() { echo; echo "== $*"; }
die() { echo "build.sh: $*" >&2; exit 1; }

release=false
case "${1:-}" in
    --release) release=true ;;
    "") ;;
    *) die "usage: build.sh [--release]" ;;
esac
if $release; then
    case "${GITHUB_EVENT_NAME:-}" in pull_request*) die "a pull request build is never signed for release" ;; esac
    tools/ci/release-signing.sh check
fi

step "toolchain"
swift --version

step "script checks (tools/ci/test.sh)"
tools/ci/test.sh

step "unit tests (make test)"
make test

step "app bundle (make app)"
make app

if $release; then
    step "release signature (Folio Release Signing)"
    tools/ci/release-signing.sh sign build/Folio.app
fi

step "signature (codesign -dv)"
codesign -dv build/Folio.app 2>&1
if $release; then
    tools/ci/release-signing.sh verify build/Folio.app release
else
    tools/ci/release-signing.sh verify build/Folio.app adhoc
fi

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
