# dotfiles

Cross-machine Claude Code + OMP (Oh My Pi) environment setup. Symlinks agent
config, commands, skills, and hooks from this repo into `~/.claude` and
`~/.omp/agent`, installs prerequisites, starts a shared Hindsight memory
server, and wires shared git hooks.

## Layout
- `bootstrap.sh` / `bootstrap-new.sh` — entry points; see [Bootstrapping](#bootstrapping).
- `bootstrap-autorun.sh` — login hook; see [Login autorun & variant switching](#login-autorun--variant-switching).
- `claude/` — Claude Code config (`CLAUDE.md`, `commands/`, `scripts/`, `skills/`), symlinked to `~/.claude`.
- `omp/agent/` — OMP config (`AGENTS.md`, `agents/`, `commands/`, `hooks/`, `scripts/`, `config.yml`, `models.yml`), symlinked to `~/.omp/agent`. `AGENTS.md` is the canonical source of task-routing rules, memory setup, and troubleshooting notes.
- `git/hooks/` — shared git hooks, linked to `~/.git-hooks` and set as `core.hooksPath` globally.

## Bootstrapping
Run once per machine:
```sh
./bootstrap.sh
```
This installs `jq`/the Gemini CLI, symlinks Claude Code + OMP config, starts a
`hindsight` Docker container for OMP's autonomous memory (seeded from the last
snapshot pushed to this repo, if any — see `omp/agent/scripts/sync-hindsight-memory.sh`),
wires `~/.bashrc`/`~/.zshrc`, and sets `core.hooksPath` globally. Every step is
idempotent, so it's safe to re-run.

### `bootstrap-new.sh` — clean-memory variant
`bootstrap-new.sh` is identical to `bootstrap.sh` except it does **not**
restore the shared Hindsight snapshot when starting a fresh container —
memory comes up on but empty, instead of inherited from another machine. Use
it on a machine you want to start with a clean memory bank:
```sh
./bootstrap-new.sh
```
Diff the two files to confirm that's the only behavioral difference:
```sh
diff bootstrap.sh bootstrap-new.sh
```

### Login autorun & variant switching
Both scripts register `bootstrap-autorun.sh` in `~/.bashrc`/`~/.zshrc` and
record which one you last ran in `~/.omp/agent/.bootstrap-variant`. On every
new interactive shell, `bootstrap-autorun.sh` re-runs that recorded script in
the background — at most once per calendar day, logged to
`~/.omp/agent/bootstrap-autorun.log` — so config drift and Hindsight/OMP
setup stay current without a manual re-run.

Practically: whichever of `bootstrap.sh` / `bootstrap-new.sh` you run
manually becomes the one that keeps running on subsequent logins, until you
manually run the other one — which switches it back.

## Memory sync across machines
Hindsight's database is per-machine and does not sync on its own.
`omp/agent/scripts/sync-hindsight-memory.sh push|pull` backs it up to /
restores it from `omp/hindsight-backup.zip`, committed to this repo. See
`omp/agent/AGENTS.md`'s "Memory (Hindsight)" section for the full mechanism,
including the automatic `session_shutdown` push hook and the `mem-push` /
`mem-pull` shell aliases bootstrap sets up.

## Task routing (Claude Code / OMP)
See `omp/agent/AGENTS.md` for the full token-preservation routing policy
(`/gemini`, `/deepseek`, `/deepseek-r`, `/nemotron`, `/diagram`, `/flux`) and
other project conventions. The policy is mechanically enforced, not just
documented: `omp/agent/hooks/pre/routing-guard.ts` blocks direct test-file
writes, `task` dispatches with no `agent` set, and prod-deploy commands run
without a prior `/nemotron` pass this session — see AGENTS.md's
"Enforcement" section for the `[routing:<reason>]` bypass tag.
