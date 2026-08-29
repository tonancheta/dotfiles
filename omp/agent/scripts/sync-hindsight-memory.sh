#!/usr/bin/env bash
# Sync the Hindsight memory server's database through this dotfiles repo so
# multiple machines share one growing memory instead of each accumulating an
# isolated local copy.
#
# IMPORTANT: this is a full snapshot overwrite, not a merge. `restore` deletes
# all existing data in the target database before importing the backup. If
# you work on machine A, then work on machine B WITHOUT pulling A's snapshot
# first, then push from B, A's un-pushed memories are gone with no warning
# and no conflict marker — git has no idea what's inside the zip. Discipline:
# `pull` before you start working on any machine, `push` when you're done.
#
# Usage:
#   sync-hindsight-memory.sh push   # backup the running container -> commit -> push
#   sync-hindsight-memory.sh pull   # git pull -> restore into the running container
#
# Requires: docker, a running `hindsight` container (see bootstrap.sh step 8h),
# and this dotfiles checkout to already have a configured git remote/auth.
set -euo pipefail

# Resolve through the ~/.omp/agent/scripts symlink (bootstrap.sh step 8b) to
# this script's real location in the dotfiles checkout — BASH_SOURCE alone
# reflects the invocation path, and going ../../.. from a symlinked
# ~/.omp/agent/scripts lands under $HOME instead of the dotfiles root.
DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd)"
BACKUP_REL="omp/hindsight-backup.zip"
BACKUP_PATH="$DOTFILES_DIR/$BACKUP_REL"
CONTAINER_TMP="/tmp/hindsight-backup.zip"

usage() {
  echo "Usage: $(basename "$0") push|pull" >&2
  exit 1
}

require_container() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on this machine." >&2
    exit 1
  fi
  if [ -z "$(docker ps -q -f name='^/hindsight$' 2>/dev/null)" ]; then
    echo "ERROR: 'hindsight' container is not running. Start it first (bootstrap.sh step 8h, or 'docker start hindsight')." >&2
    exit 1
  fi
  # hindsight-admin talks to Postgres directly, not the HTTP API — right
  # after a fresh `docker run` the embedded pg0 instance may still be
  # initializing. Poll instead of assuming it's already up.
  local attempt
  for attempt in $(seq 1 20); do
    if docker exec hindsight hindsight-admin worker-status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: 'hindsight' container's database never became ready." >&2
  exit 1
}

do_push() {
  require_container

  docker exec hindsight hindsight-admin backup "$CONTAINER_TMP"
  docker cp "hindsight:$CONTAINER_TMP" "$BACKUP_PATH"
  docker exec hindsight rm -f "$CONTAINER_TMP"

  cd "$DOTFILES_DIR"
  git add "$BACKUP_REL"
  if git diff --cached --quiet -- "$BACKUP_REL"; then
    echo "hindsight-sync: no memory changes since last push."
    exit 0
  fi

  git commit -m "hindsight memory sync: $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- "$BACKUP_REL"
  git push
  echo "hindsight-sync: pushed $BACKUP_REL"
}

do_pull() {
  cd "$DOTFILES_DIR"
  git pull --ff-only

  if [ ! -f "$BACKUP_PATH" ]; then
    echo "hindsight-sync: no snapshot at $BACKUP_REL yet — nothing to restore."
    exit 0
  fi

  require_container

  docker cp "$BACKUP_PATH" "hindsight:$CONTAINER_TMP"
  docker exec hindsight hindsight-admin restore "$CONTAINER_TMP" --yes
  docker exec -u root hindsight rm -f "$CONTAINER_TMP"
  # A logical restore populates banks outside their normal create-time path,
  # so their per-(bank, fact_type) vector index coverage is missing until
  # rebuilt — otherwise recall silently falls back to a slower global-index
  # scan. CONCURRENTLY-built, so this never blocks the container's traffic.
  docker exec hindsight hindsight-admin repair-bank --all
  echo "hindsight-sync: restored $BACKUP_REL into the running container"
}

case "${1:-}" in
  push) do_push ;;
  pull) do_pull ;;
  *) usage ;;
esac
