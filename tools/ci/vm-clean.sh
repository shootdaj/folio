#!/bin/bash
# vm-clean.sh: runs INSIDE the throwaway folio-test VM before each test run. The VM disk is 50 GB:
# drop test folders older than an hour, and empty the VM Trash when under 8 GB is free
# (the test scripts move their fixtures to the Trash).
find /private/tmp/folio-tests -mindepth 1 -maxdepth 1 -mmin +60 -exec rm -rf {} + 2>/dev/null
free=$(df -g / | awk 'NR==2{print $4}')
if [ "${free:-0}" -lt 8 ]; then osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1; fi
df -h / | awk 'NR==2{print "vm disk free: " $4}'
