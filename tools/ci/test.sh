#!/bin/bash
# Checks version.sh and changelog-section.sh on throwaway git repos, and release-signing.sh's verify on a
# stand-in bundle, under $TMPDIR (moved to the Trash at the end). Runs nothing Folio builds. Exits non-zero
# when any answer is wrong.
set -euo pipefail

CI="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/folio-ci-test.XXXXXX")"
trap 'mv "$WORK" "$HOME/.Trash/folio-ci-test-$(date +%Y%m%d-%H%M%S)-$$" 2>/dev/null || true' EXIT
fails=0

expect() { # expect <what> <want> <got>
    if [ "$2" = "$3" ]; then echo "ok   $1: $3"; else echo "FAIL $1: want [$2], got [$3]"; fails=$((fails + 1)); fi
}
matches() { # matches <what> <extended regex> <got>
    if echo "$3" | grep -Eq "$2"; then echo "ok   $1: $3"; else echo "FAIL $1: [$3] does not match $2"; fails=$((fails + 1)); fi
}

repo="$WORK/repo"
mkdir -p "$repo" && cd "$repo"
git init -q
git config user.email ci@example.invalid
git config user.name ci
git config commit.gpgsign false
git config tag.gpgsign false
commit() { echo "$1" >> notes.txt; git add notes.txt; git commit -qm "$1"; }

# No tag yet: 0.0.0-<sha>.
commit one
sha=$(git rev-parse --short HEAD)
expect "no tag" "0.0.0-$sha" "$("$CI/version.sh")"
expect "no tag, short" "0.0.0" "$("$CI/version.sh" --short)"
expect "no tag, build" "1" "$("$CI/version.sh" --build)"
expect "no tag, sha" "$sha" "$("$CI/version.sh" --sha)"

# Tags that are not vX.Y.Z are ignored.
git tag nightly
git tag -a release-candidate -m rc
expect "other tags ignored" "0.0.0-$sha" "$("$CI/version.sh")"

# On the tag: the tag without the v.
git tag -a v0.1.0 -m "Folio 0.1.0"
expect "on tag" "0.1.0" "$("$CI/version.sh")"
expect "on tag, short" "0.1.0" "$("$CI/version.sh" --short)"

# Uncommitted change to a tracked file: -dirty.
echo change >> notes.txt
expect "dirty" "0.1.0-dirty" "$("$CI/version.sh")"
expect "dirty, short" "0.1.0" "$("$CI/version.sh" --short)"
git checkout -q notes.txt

# Two commits ahead: <tag>-2-g<sha>; the build number is the commit count.
commit two
commit three
sha=$(git rev-parse --short HEAD)
matches "ahead" "^0\.1\.0-2-g$sha$" "$("$CI/version.sh")"
expect "ahead, short" "0.1.0" "$("$CI/version.sh" --short)"
expect "ahead, build" "3" "$("$CI/version.sh" --build)"

# A lightweight tag counts too, and the newest one wins.
git tag v0.2.0
expect "newer lightweight tag" "0.2.0" "$("$CI/version.sh")"

# Not a git repo at all: still a version string, never an empty one.
mkdir "$WORK/plain" && cd "$WORK/plain"
expect "outside git" "0.0.0-unknown" "$(GIT_CEILING_DIRECTORIES="$WORK" "$CI/version.sh")"

# changelog-section.sh prints one version's notes, without its heading.
cat > "$WORK/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

### Added
- Something new.

## [0.2.0] - 2026-12-01

### Fixed
- A bug.

## [0.1.0] - 2026-11-07

### Added
- First release.

[Unreleased]: https://example.invalid/compare/v0.2.0...HEAD
[0.2.0]: https://example.invalid/releases/tag/v0.2.0
MD
expect "section 0.2.0" "$(printf '### Fixed\n- A bug.')" "$("$CI/changelog-section.sh" 0.2.0 "$WORK/CHANGELOG.md")"
expect "section v0.1.0" "$(printf '### Added\n- First release.')" "$("$CI/changelog-section.sh" v0.1.0 "$WORK/CHANGELOG.md")"
expect "section Unreleased" "$(printf '### Added\n- Something new.')" "$("$CI/changelog-section.sh" Unreleased "$WORK/CHANGELOG.md")"
if "$CI/changelog-section.sh" 9.9.9 "$WORK/CHANGELOG.md" >/dev/null 2>&1; then
    echo "FAIL missing section: exit 0"; fails=$((fails + 1))
else
    echo "ok   missing section: non-zero exit"
fi
# 0.1.0 must not match 0.1.01 or 10.1.0.
printf '# Changelog\n\n## [10.1.0] - 2026-01-01\n\n- ten\n' > "$WORK/near.md"
if "$CI/changelog-section.sh" 0.1.0 "$WORK/near.md" >/dev/null 2>&1; then
    echo "FAIL near miss: 0.1.0 matched 10.1.0"; fails=$((fails + 1))
else
    echo "ok   near miss: 0.1.0 does not match 10.1.0"
fi

# release-signing.sh verify, on a stand-in bundle signed ad hoc here (no keychain is touched): it passes as ad
# hoc and fails as a release; one that only writes the release requirement into an ad hoc signature fails too.
app="$WORK/Folio.app"
mkdir -p "$app/Contents/MacOS"
cp /usr/bin/true "$app/Contents/MacOS/Folio"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
    '<key>CFBundleIdentifier</key><string>com.anshul.folio</string>' \
    '<key>CFBundleExecutable</key><string>Folio</string>' '</dict></plist>' > "$app/Contents/Info.plist"
codesign --force -s - "$app" 2>/dev/null
refuses() { # refuses <what> <command...>: the command must exit non-zero
    local what=$1; shift
    if "$@" >/dev/null 2>&1; then echo "FAIL $what: exit 0"; fails=$((fails + 1)); else echo "ok   $what: refused"; fi
}
if "$CI/release-signing.sh" verify "$app" adhoc >/dev/null 2>&1; then
    echo "ok   verify adhoc: an ad hoc bundle passes"
else
    echo "FAIL verify adhoc: an ad hoc bundle was refused"; fails=$((fails + 1))
fi
refuses "verify release, ad hoc bundle" "$CI/release-signing.sh" verify "$app" release
leaf=$(sed -n 's/^RELEASE_CERT=//p' "$CI/release-signing.sh" | tr 'A-F' 'a-f')
codesign --force -s - -r="designated => identifier \"com.anshul.folio\" and certificate leaf = H\"$leaf\"" "$app" 2>/dev/null
refuses "verify release, requirement claimed by an ad hoc signature" "$CI/release-signing.sh" verify "$app" release

# build.sh: a pull request build never reaches the release keychain; unknown options stop it at once.
refuses "build.sh --release in a pull request" env GITHUB_EVENT_NAME=pull_request "$CI/build.sh" --release
matches "build.sh --release in a pull request, why" "never signed for release" \
    "$(GITHUB_EVENT_NAME=pull_request "$CI/build.sh" --release 2>&1 || true)"
refuses "build.sh --sign" "$CI/build.sh" --sign

if [ "$fails" -eq 0 ]; then echo "tools/ci/test.sh: ok"; else echo "tools/ci/test.sh: $fails failed"; exit 1; fi
