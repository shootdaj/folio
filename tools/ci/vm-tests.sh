#!/bin/bash
# vm-tests.sh [Folio.app] [ff]: runs on the Mac Ultra, by CI or by hand. Stages the build into the test VM
# folio-test (stage-vm.sh), runs Tests/vm/m2.sh to m9.sh there one after another through vm-ssh.sh, and
# brings the PNGs back with vm-fetch.sh into build/vm-shots/ (each script's output in build/vm-shots/logs/).
# Exits non-zero unless every script exits 0 with a "result: ok" line. The app runs only inside the VM
# (docs/plan/RULES.md, rule 0). Defaults: build/Folio.app and build/ff from tools/ci/build.sh.
#   VM_TESTS="m2 m9"     run only these scripts
#   VM_WAIT_MINUTES=20   how long to wait while another VM script is running before taking the VM over
set -uo pipefail
# One VM, many users (CI and agents): hold the shared lock for the whole run. Agents take the same lock
# through /Users/anshul/AgentWork/folio/vm-test.sh, so a run never stages over another one mid-test.
if [ -z "${FOLIO_VM_LOCKED:-}" ] && [ -x /usr/bin/lockf ]; then
    export FOLIO_VM_LOCKED=1
    echo "vm-tests.sh: waiting for the VM lock"
    exec /usr/bin/lockf -k -t 7200 "${FOLIO_VM_HOME:-/Users/anshul/AgentWork/folio}/vm.lock" "$0" "$@"
fi
cd "$(dirname "$0")/../.." || exit 1

FOLIO_VM_HOME=${FOLIO_VM_HOME:-/Users/anshul/AgentWork/folio}
app=${1:-build/Folio.app}
ff=${2:-"$(dirname "$app")/ff"}
OUT="$PWD/build/vm-shots"
read -r -a scripts <<<"${VM_TESTS:-m2 m3 m4 m5 m6 m7 m8 m9}"

vm() { "$FOLIO_VM_HOME/vm-ssh.sh" "$@" </dev/null; }
vm_running() { "$FOLIO_VM_HOME/bin/tart.app/Contents/MacOS/tart" list 2>/dev/null | grep -q "folio-test.*running"; }
script_busy() { vm "pgrep -f '/folio/.*[.]sh'" >/dev/null 2>&1; }

# Another agent may be driving the VM by hand. Wait until no script has run there for 30 s.
waited=0 idle=0 limit=$(( ${VM_WAIT_MINUTES:-20} * 6 ))
while vm_running && [ "$idle" -lt 3 ] && [ "$waited" -lt "$limit" ]; do
    if script_busy; then
        idle=0
        [ $((waited % 6)) -eq 0 ] && echo "waiting: another script is running in the VM ($((waited / 6)) min)"
    else
        idle=$((idle + 1))
    fi
    waited=$((waited + 1))
    sleep 10
done
[ "$waited" -ge "$limit" ] && echo "vm-tests.sh: the VM was still busy after ${VM_WAIT_MINUTES:-20} min; taking it over"

mkdir -p "$OUT/logs"
echo "== staging"
tools/ci/stage-vm.sh "$app" "$ff" || { echo "vm-tests.sh: staging failed"; exit 1; }
vm "if [ -d ~/folio/shots ]; then mv ~/folio/shots ~/.Trash/folio-shots-\$(date +%Y%m%d-%H%M%S); fi; mkdir -p ~/folio/shots"

failed=()
results=()
for m in "${scripts[@]}"; do
    echo
    echo "== $m (Tests/vm/$m.sh in the VM)"
    vm "pkill -x Folio" >/dev/null 2>&1
    sleep 1
    start=$(date +%s)
    vm "bash ~/folio/tests/$m.sh" 2>&1 | tee "$OUT/logs/$m.log"
    rc=${PIPESTATUS[0]}
    last=$(grep '^result:' "$OUT/logs/$m.log" | tail -1)
    if [ "$rc" -eq 0 ] && [[ "$last" == "result: ok"* ]]; then
        results+=("$m: ok ($(( $(date +%s) - start )) s)")
    else
        failed+=("$m")
        results+=("$m: FAILED, exit $rc, [${last:-no result line}]")
    fi
done
vm "pkill -x Folio" >/dev/null 2>&1

echo
echo "== fetching PNGs (vm-fetch.sh)"
touch "$OUT/logs/.fetch-mark"
"$FOLIO_VM_HOME/vm-fetch.sh" '*.png' >/dev/null
find "$FOLIO_VM_HOME/shots/fetched" -name '*.png' -newer "$OUT/logs/.fetch-mark" -exec cp {} "$OUT/" \;
shots=$(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
echo "$shots PNGs in $OUT"

echo
echo "== results"
printf '%s\n' "${results[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
    echo "vm-tests.sh: FAILED: ${failed[*]}"
    exit 1
fi
if [ "$shots" -eq 0 ]; then
    echo "vm-tests.sh: FAILED: no PNGs came back"
    exit 1
fi
echo "vm-tests.sh: ok, ${#scripts[@]} scripts, $shots PNGs"
