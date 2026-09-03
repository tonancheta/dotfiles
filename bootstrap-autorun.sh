# Sourced (not executed) from ~/.bashrc / ~/.zshrc by a line that
# bootstrap.sh and bootstrap-new.sh both append there (step 9c in each —
# see their own comments). Re-runs whichever bootstrap variant last ran
# manually, so dotfiles changes and OMP/Hindsight setup stay current
# without remembering to re-run it yourself — and so running the OTHER
# variant later switches future logins back to that one, since "active
# variant" is just the one-line state file this script reads.
#
# Guards, both deliberate:
# - Interactive-only ($- check): .bashrc/.zshrc also run for non-interactive
#   shells (scp, rsync, some CI/tooling). Firing a background bootstrap run
#   there, with its own `set -e` and side effects, would be unexpected.
# - Once per calendar day (stamp file): .bashrc/.zshrc re-source on every
#   new terminal tab/pane, not just "logins" in the strict login-shell
#   sense. Re-running full bootstrap (npm install, docker --pull always,
#   apt-get) on every single new tab would be slow and noisy; once a day
#   is enough to pick up changes without that cost.
#
# Runs in the background (nohup + disown) and logs to
# ~/.omp/agent/bootstrap-autorun.log instead of running in the foreground,
# so shell startup stays instant either way and a failure is inspectable
# after the fact instead of interrupting typing.

case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

_BOOTSTRAP_AUTORUN_STATE_DIR="$HOME/.omp/agent"
_BOOTSTRAP_AUTORUN_VARIANT_FILE="$_BOOTSTRAP_AUTORUN_STATE_DIR/.bootstrap-variant"
_BOOTSTRAP_AUTORUN_STAMP_FILE="$_BOOTSTRAP_AUTORUN_STATE_DIR/.bootstrap-autorun-stamp"
_BOOTSTRAP_AUTORUN_LOG_FILE="$_BOOTSTRAP_AUTORUN_STATE_DIR/bootstrap-autorun.log"

if [ ! -f "$_BOOTSTRAP_AUTORUN_VARIANT_FILE" ]; then
    unset _BOOTSTRAP_AUTORUN_STATE_DIR _BOOTSTRAP_AUTORUN_VARIANT_FILE _BOOTSTRAP_AUTORUN_STAMP_FILE _BOOTSTRAP_AUTORUN_LOG_FILE
    return 0 2>/dev/null || exit 0
fi

_BOOTSTRAP_AUTORUN_TARGET="$(cat "$_BOOTSTRAP_AUTORUN_VARIANT_FILE" 2>/dev/null)"
if [ -z "$_BOOTSTRAP_AUTORUN_TARGET" ] || [ ! -f "$_BOOTSTRAP_AUTORUN_TARGET" ]; then
    unset _BOOTSTRAP_AUTORUN_STATE_DIR _BOOTSTRAP_AUTORUN_VARIANT_FILE _BOOTSTRAP_AUTORUN_STAMP_FILE _BOOTSTRAP_AUTORUN_LOG_FILE _BOOTSTRAP_AUTORUN_TARGET
    return 0 2>/dev/null || exit 0
fi

_BOOTSTRAP_AUTORUN_TODAY="$(date +%Y-%m-%d)"
if [ "$(cat "$_BOOTSTRAP_AUTORUN_STAMP_FILE" 2>/dev/null)" != "$_BOOTSTRAP_AUTORUN_TODAY" ]; then
    mkdir -p "$_BOOTSTRAP_AUTORUN_STATE_DIR"
    echo "$_BOOTSTRAP_AUTORUN_TODAY" > "$_BOOTSTRAP_AUTORUN_STAMP_FILE"
    nohup bash "$_BOOTSTRAP_AUTORUN_TARGET" >> "$_BOOTSTRAP_AUTORUN_LOG_FILE" 2>&1 &
    disown 2>/dev/null || true
fi

unset _BOOTSTRAP_AUTORUN_STATE_DIR _BOOTSTRAP_AUTORUN_VARIANT_FILE _BOOTSTRAP_AUTORUN_STAMP_FILE _BOOTSTRAP_AUTORUN_LOG_FILE _BOOTSTRAP_AUTORUN_TARGET _BOOTSTRAP_AUTORUN_TODAY
