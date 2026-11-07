#!/bin/bash
# stage-vm.sh <Folio.app> [ff]: runs on the Mac Ultra. Starts the test VM folio-test when it is stopped (as
# vm-run.sh does), then copies the build in: the app to ~/folio/Folio.app, ff to ~/folio/ff and
# Tests/vm/*.sh to ~/folio/tests/. ff defaults to the one next to the app. Runs nothing it copies
# (docs/plan/RULES.md, rule 0); modelled on /Users/anshul/AgentWork/folio/bin/stage-vm-m4.sh.
set -euo pipefail

FOLIO_VM_HOME=${FOLIO_VM_HOME:-/Users/anshul/AgentWork/folio}
TART="$FOLIO_VM_HOME/bin/tart.app/Contents/MacOS/tart"
KEY="$FOLIO_VM_HOME/vmkey"
VM=folio-test
LOG="$(dirname "$FOLIO_VM_HOME")/logs/folio-vm-run.log"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"   # tmux

die() { echo "stage-vm.sh: $*" >&2; exit 1; }

app=${1:?usage: stage-vm.sh <Folio.app> [ff]}
app="$(cd "$app" && pwd)"
ff=${2:-"$(dirname "$app")/ff"}
[ -x "$app/Contents/MacOS/Folio" ] || die "$app is not a built Folio.app"
[ -f "$ff" ] || die "missing ff at $ff"
[ -x "$TART" ] && [ -f "$KEY" ] || die "no tart or VM key under $FOLIO_VM_HOME (this runs on the Ultra)"

# Start the VM headless when it is stopped. The tmux session outlives a CI job: RUNNER_TRACKING_ID is
# dropped so the runner's orphan cleanup leaves the VM running, as vm-run.sh leaves it.
if ! "$TART" list | grep -q "$VM.*running"; then
    if ! tmux has-session -t folio-vm-run 2>/dev/null; then
        echo "starting $VM"
        mkdir -p "$(dirname "$LOG")"
        env -u RUNNER_TRACKING_ID tmux new-session -d -s folio-vm-run "$TART run $VM --no-graphics > $LOG 2>&1"
    fi
fi
IP=""
for _ in $(seq 1 60); do
    IP=$("$TART" ip "$VM" 2>/dev/null) && [ -n "$IP" ] && break
    sleep 3
done
[ -n "$IP" ] || die "$VM has no IP after 3 minutes (see $LOG)"
for _ in $(seq 1 40); do nc -z -w 2 "$IP" 22 2>/dev/null && break; sleep 3; done

O=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8)
vm() { ssh -n -i "$KEY" "${O[@]}" -o BatchMode=yes "admin@$IP" "$@"; }
vm true || die "cannot ssh into $VM as admin (run $FOLIO_VM_HOME/vm-run.sh once to install the key)"

vm "pkill -x Folio; mkdir -p ~/folio/tests /private/tmp/folio-tests" || true
rsync -a --delete -e "ssh -i $KEY ${O[*]}" "$app/" "admin@$IP:folio/Folio.app/"
rsync -a -e "ssh -i $KEY ${O[*]}" "$ff" "admin@$IP:folio/ff"
rsync -a --delete -e "ssh -i $KEY ${O[*]}" "$REPO/Tests/vm/" "admin@$IP:folio/tests/"
vm "chmod +x ~/folio/ff; xattr -dr com.apple.quarantine ~/folio/Folio.app 2>/dev/null; \
    echo \"staged Folio \$(defaults read ~/folio/Folio.app/Contents/Info FolioVersion) at \$(stat -f %Sm ~/folio/Folio.app/Contents/MacOS/Folio), \
\$(ls ~/folio/tests | tr '\n' ' ')in ~/folio/tests\""
