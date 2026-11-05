# The test VM

Folio runs only inside the tart VM `folio-test` on the Mac Ultra (docs/plan/RULES.md, rule 0).

- Helpers on the Ultra: `/Users/anshul/AgentWork/folio/vm-run.sh [--theme dark|light|system] [--accent green|amber|cyan]` builds nothing; it starts the VM headless (tmux `folio-vm-run`), copies `/Users/anshul/AgentWork/folio/Folio.app` in, runs `Folio --uitest new --shot ...` there and fetches the PNGs to `/Users/anshul/AgentWork/folio/shots/<stamp>/`. `/Users/anshul/AgentWork/folio/vm-ssh.sh "<cmd>"` runs any command in the VM as `admin`.
- Stage a build from a worktree: `make app && rsync -aq --delete build/Folio.app/ macultra:/Users/anshul/AgentWork/folio/Folio.app/`.
- Inside the VM: macOS 15.7.x guest, System Events works over SSH, sshd has Accessibility and Full Disk Access, passwordless sudo. Real keystrokes and clicks are allowed there, never on the host.
- Each milestone ships `tests/vm/<milestone>.sh`: a script that runs inside the VM, launches the app normally on a temp folder under `/private/tmp/folio-tests/`, drives it with System Events (keystrokes, clicks) or the app's own `--uitest` steps, and writes PNGs to `~/folio/shots/`. The main session runs it with `vm-ssh.sh` and fetches the PNGs.
