#!/bin/bash
# The build's version, from git tags vX.Y.Z only (git describe --tags --always --dirty), for the repo
# holding the current directory. `make app` stamps these into Info.plist.
#   version.sh           1.2.3 on the tag v1.2.3; 1.2.3-4-gabc1234 four commits after it; 0.0.0-abc1234
#                        with no tag; -dirty on the end when tracked files differ from the commit
#   version.sh --short   1.2.3, the tag part (CFBundleShortVersionString)
#   version.sh --build   the commit count (CFBundleVersion)
#   version.sh --sha     the short commit (Folio --version shows it in brackets)
set -u

described=$(git describe --tags --always --dirty --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null) || described=unknown
case "$described" in
    v[0-9]*) version=${described#v} ;;
    *) version=0.0.0-$described ;;
esac

case "${1:-}" in
    "") echo "$version" ;;
    --short) echo "${version%%-*}" ;;
    --build) git rev-list --count HEAD 2>/dev/null || echo 0 ;;
    --sha) git rev-parse --short HEAD 2>/dev/null || echo unknown ;;
    *) echo "usage: $0 [--short | --build | --sha]" >&2; exit 2 ;;
esac
