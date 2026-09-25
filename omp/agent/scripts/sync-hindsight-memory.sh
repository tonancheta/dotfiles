#!/usr/bin/env bash
# Sync the Hindsight memory server's database through this dotfiles repo so
# multiple machines share one growing memory instead of each accumulating an
# isolated local copy.
#
# Merge-aware: neither `push` nor `pull` ever destructively replaces the live
# container's data with a `restore --yes` unless that container's database is
# verified empty (nothing to lose). Otherwise, an incoming snapshot — however
# it arrives, a clean git fast-forward or a genuine git merge conflict on
# omp/hindsight-backup.zip because both machines pushed independently since
# the last common snapshot — is reconciled at the row level: loaded into a
# disposable scratch container, dumped as `INSERT ... ON CONFLICT DO NOTHING`
# statements (primary-key dedup) in the archive's own dependency-safe table
# order, and applied against the live database. No DELETE/TRUNCATE/UPDATE
# ever runs against the live container, so nothing already there is lost —
# working on machine A and machine B concurrently without pulling in between
# is safe; both sides' memories survive the next sync in either direction.
#
# `push` always pull-merges first, so a push can never regress what's already
# on the remote, and retries a few times if another machine's push races it.
#
# Usage:
#   sync-hindsight-memory.sh push   # merge remote in, then commit+push the live container's state
#   sync-hindsight-memory.sh pull   # merge the latest pushed snapshot into the live container
#
# Requires: docker, git, python3, a running `hindsight` container (see
# bootstrap.sh step 8h), and this dotfiles checkout to already have a
# configured git remote/auth + upstream tracking branch.
set -euo pipefail

# Resolve through the ~/.omp/agent/scripts symlink (bootstrap.sh step 8b) to
# this script's real location in the dotfiles checkout — BASH_SOURCE alone
# reflects the invocation path, and going ../../.. from a symlinked
# ~/.omp/agent/scripts lands under $HOME instead of the dotfiles root.
DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd)"
BACKUP_REL="omp/hindsight-backup.zip"
BACKUP_PATH="$DOTFILES_DIR/$BACKUP_REL"
CONTAINER_TMP="/tmp/hindsight-backup.zip"
# Overridable for integration testing against a throwaway container instead
# of the real one; unset/default in normal use.
LIVE_CONTAINER="${HINDSIGHT_CONTAINER:-hindsight}"

usage() {
  echo "Usage: $(basename "$0") push|pull" >&2
  exit 1
}

require_container() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on this machine." >&2
    exit 1
  fi
  if [ -z "$(docker ps -q -f name="^/${LIVE_CONTAINER}\$" 2>/dev/null)" ]; then
    echo "ERROR: '$LIVE_CONTAINER' container is not running. Start it first (bootstrap.sh step 8h, or 'docker start $LIVE_CONTAINER')." >&2
    exit 1
  fi
  wait_for_pg "$LIVE_CONTAINER"
}

wait_for_pg() {
  # hindsight-admin talks to Postgres directly, not the HTTP API — right
  # after a fresh `docker run` the embedded pg0 instance may still be
  # initializing. Poll instead of assuming it's already up.
  local c="$1" attempt
  for attempt in $(seq 1 30); do
    if docker exec "$c" hindsight-admin worker-status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: '$c' container's database never became ready." >&2
  exit 1
}

pg_bin_dir() {
  # The embedded pg0's install path is versioned (.../installation/18.1.0/bin)
  # and psql/pg_dump aren't on PATH — resolve the actual dir each call
  # instead of hardcoding a version that'll go stale on the next image bump.
  docker exec "$1" sh -c 'ls -d /home/hindsight/.pg0/installation/*/bin 2>/dev/null | head -1'
}

docker_env_lines() {
  # All HINDSIGHT_API_LLM_* vars configured on $1, so a scratch container
  # spun up for merging boots with the same LLM backend — embedded pg0
  # startup hard-requires HINDSIGHT_API_LLM_API_KEY to be set even though a
  # merge never calls the LLM — without ever hardcoding a key in this script.
  docker inspect "$1" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^HINDSIGHT_API_LLM_' || true
}

zip_table_order() {
  # The manifest's table names, in the same dependency-safe order
  # hindsight-admin itself restores/backs them up in — read from the archive
  # instead of a hardcoded list so a future hindsight schema change can't
  # silently go stale here.
  python3 - "$1" <<'PY'
import json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
m = json.loads(z.read("manifest.json"))
print(" ".join(m["tables"].keys()))
PY
}

live_is_empty() {
  local dir n
  dir="$(pg_bin_dir "$LIVE_CONTAINER")"
  n="$(docker exec "$LIVE_CONTAINER" env PGPASSWORD=hindsight "$dir/psql" -h localhost -U hindsight -d hindsight -t -A -c 'select count(*) from documents')"
  [ "$n" = "0" ]
}

restore_direct() {
  # $1 = zip path on host. Only safe when the live container's database is
  # verified empty (live_is_empty) — nothing to lose, so a plain restore is
  # equivalent to (and cheaper than) merging into nothing.
  docker cp "$1" "$LIVE_CONTAINER:$CONTAINER_TMP"
  docker exec "$LIVE_CONTAINER" hindsight-admin restore "$CONTAINER_TMP" --yes
  docker exec "$LIVE_CONTAINER" rm -f "$CONTAINER_TMP"
  docker exec "$LIVE_CONTAINER" hindsight-admin repair-bank --all
}

merge_zip_into_live() {
  # $1 = path (on host) to a hindsight-admin backup zip to additively merge
  # into $LIVE_CONTAINER's live database. Never touches rows already there.
  # Runs in a subshell so the cleanup EXIT trap is scoped to this call only
  # — a `trap ... RETURN` here would instead fire on every later function
  # return in the rest of the script (do_pull's, do_push's, ...), crashing
  # under `set -u` once $scratch/$scratch_vol/$sql_tmp are out of scope.
  local incoming="$1"
  (
    set -euo pipefail
    local scratch="hindsight-merge-$$"
    local scratch_vol="hindsight-merge-$$-data"
    local sql_tmp
    sql_tmp="$(mktemp)"
    trap 'docker rm -f "$scratch" >/dev/null 2>&1 || true; docker volume rm "$scratch_vol" >/dev/null 2>&1 || true; rm -f "$sql_tmp"' EXIT

    echo "hindsight-sync: merging incoming snapshot via scratch container $scratch..." >&2
    docker volume create "$scratch_vol" >/dev/null

    env_args=()
    while IFS= read -r line; do
      [ -n "$line" ] && env_args+=(-e "$line")
    done < <(docker_env_lines "$LIVE_CONTAINER")

    docker run -d --name "$scratch" -v "$scratch_vol:/home/hindsight/.pg0" \
      "${env_args[@]}" ghcr.io/vectorize-io/hindsight:latest >/dev/null
    wait_for_pg "$scratch"

    docker cp "$incoming" "$scratch:/tmp/incoming.zip"
    docker exec "$scratch" hindsight-admin restore /tmp/incoming.zip --yes >&2

    table_args=()
    for t in $(zip_table_order "$incoming"); do
      table_args+=(--table="$t")
    done

    dump_dir="$(pg_bin_dir "$scratch")"
    docker exec "$scratch" env PGPASSWORD=hindsight "$dump_dir/pg_dump" \
      -h localhost -U hindsight -d hindsight \
      --data-only --inserts --on-conflict-do-nothing --disable-triggers \
      "${table_args[@]}" > "$sql_tmp"

    live_dir="$(pg_bin_dir "$LIVE_CONTAINER")"
    docker exec -i "$LIVE_CONTAINER" env PGPASSWORD=hindsight "$live_dir/psql" \
      -h localhost -U hindsight -d hindsight -v ON_ERROR_STOP=1 -f - < "$sql_tmp" >&2

    # pg_dump's --inserts emits `setval()` calls reflecting the SOURCE side's
    # sequence position, which can be lower than the live side's and would
    # rewind it. Recompute every owned sequence in this schema from the live
    # table's actual MAX(column) instead — advance-only, safe to run always.
    docker exec "$LIVE_CONTAINER" env PGPASSWORD=hindsight "$live_dir/psql" \
      -h localhost -U hindsight -d hindsight -v ON_ERROR_STOP=1 -c "
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT s.relname AS seq, n.nspname AS schema, t.relname AS tbl, a.attname AS col
    FROM pg_class s
    JOIN pg_depend d ON d.objid = s.oid AND d.deptype = 'a'
    JOIN pg_class t ON t.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE s.relkind = 'S' AND n.nspname = 'public'
  LOOP
    EXECUTE format('SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I.%I), 1), true)', r.seq, r.col, r.schema, r.tbl);
  END LOOP;
END \$\$;
" >&2

    docker exec "$LIVE_CONTAINER" hindsight-admin repair-bank --all >&2
    echo "hindsight-sync: merge complete." >&2
  )
}

do_pull() {
  cd "$DOTFILES_DIR"
  git fetch

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || {
    echo "ERROR: current branch has no upstream tracking branch configured." >&2
    exit 1
  }

  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$upstream")" ]; then
    echo "hindsight-sync: already up to date with $upstream."
    return 0
  fi

  local before_head
  before_head="$(git rev-parse HEAD)"

  if git merge --no-edit "$upstream" >/tmp/hindsight-pull-merge.log 2>&1; then
    if [ ! -f "$BACKUP_PATH" ]; then
      echo "hindsight-sync: no snapshot at $BACKUP_REL yet — nothing to restore."
      return 0
    fi
    if git diff --quiet "$before_head" HEAD -- "$BACKUP_REL"; then
      echo "hindsight-sync: pulled, but $BACKUP_REL unchanged — nothing to merge into the container."
      return 0
    fi
    require_container
    if live_is_empty; then
      restore_direct "$BACKUP_PATH"
    else
      merge_zip_into_live "$BACKUP_PATH"
    fi
  else
    local conflicts
    conflicts="$(git diff --name-only --diff-filter=U)"
    if [ "$conflicts" != "$BACKUP_REL" ]; then
      echo "ERROR: git merge failed with conflicts unrelated to $BACKUP_REL:" >&2
      echo "$conflicts" >&2
      echo "Resolve manually; merge is left in progress (MERGE_HEAD set)." >&2
      exit 1
    fi
    echo "hindsight-sync: git-level conflict on $BACKUP_REL (both sides diverged) — reconciling at the row level..."
    require_container
    local theirs_tmp
    theirs_tmp="$(mktemp)"
    git show ":3:$BACKUP_REL" > "$theirs_tmp"
    if live_is_empty; then
      restore_direct "$theirs_tmp"
    else
      merge_zip_into_live "$theirs_tmp"
    fi
    rm -f "$theirs_tmp"

    docker exec "$LIVE_CONTAINER" hindsight-admin backup "$CONTAINER_TMP"
    docker cp "$LIVE_CONTAINER:$CONTAINER_TMP" "$BACKUP_PATH"
    docker exec "$LIVE_CONTAINER" rm -f "$CONTAINER_TMP"
    git add "$BACKUP_REL"

    local remaining
    remaining="$(git diff --name-only --diff-filter=U)"
    if [ -n "$remaining" ]; then
      echo "ERROR: unexpected additional conflicts after resolving $BACKUP_REL: $remaining" >&2
      echo "Resolve manually; merge is left in progress (MERGE_HEAD set)." >&2
      exit 1
    fi
    git commit --no-edit
    echo "hindsight-sync: reconciled and merged both sides of $BACKUP_REL."
  fi

  echo "hindsight-sync: pull complete."
}

do_push() {
  require_container
  do_pull

  local attempt
  for attempt in 1 2 3; do
    cd "$DOTFILES_DIR"
    docker exec "$LIVE_CONTAINER" hindsight-admin backup "$CONTAINER_TMP"
    docker cp "$LIVE_CONTAINER:$CONTAINER_TMP" "$BACKUP_PATH"
    docker exec "$LIVE_CONTAINER" rm -f "$CONTAINER_TMP"

    git add "$BACKUP_REL"
    if git diff --cached --quiet -- "$BACKUP_REL"; then
      echo "hindsight-sync: no memory changes since last push."
      return 0
    fi

    git commit -m "hindsight memory sync: $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- "$BACKUP_REL"

    if git push; then
      echo "hindsight-sync: pushed $BACKUP_REL"
      return 0
    fi

    echo "hindsight-sync: push rejected (remote advanced) — re-merging (attempt $attempt/3)..." >&2
    git reset --mixed HEAD~1 >/dev/null
    do_pull
  done

  echo "ERROR: push failed after 3 attempts — remote kept advancing faster than we could merge. Try again shortly." >&2
  exit 1
}

case "${1:-}" in
  push) do_push ;;
  pull) do_pull ;;
  *) usage ;;
esac
