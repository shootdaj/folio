#!/bin/bash
# changelog-section.sh <version> [CHANGELOG.md]: prints the notes under "## [<version>]" (a leading v is
# dropped, "Unreleased" works too), without the heading, up to the next version heading or the link list.
# Exits 1 when the section is missing or empty, so a release never goes out without notes.
set -euo pipefail

want=${1:?usage: changelog-section.sh <version> [CHANGELOG.md]}
want=${want#v}
file=${2:-"$(cd "$(dirname "$0")/../.." && pwd)/CHANGELOG.md"}

notes=$(awk -v want="$want" '
    /^## \[/ {
        if (inside) exit
        heading = $0
        sub(/^## \[/, "", heading)
        sub(/\].*$/, "", heading)
        if (heading == want) { inside = 1; next }
    }
    /^\[[^]]+\]: / { if (inside) exit }
    inside { print }
' "$file" | sed -e '/./,$!d')  # leading blank lines go here, trailing ones with the $( )

if [ -z "$notes" ]; then
    echo "changelog-section.sh: no notes under \"## [$want]\" in $file" >&2
    exit 1
fi
printf '%s\n' "$notes"
