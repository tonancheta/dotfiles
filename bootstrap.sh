#!/usr/bin/env bash
set -e

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "🚀 Setting up Claude Code + OMP dotfiles..."

# --- symlink helper -----------------------------------------------------
# Windows without Developer Mode (or an elevated shell) lacks
# SeCreateSymbolicLinkPrivilege, so `ln -sf` fails with "A required privilege
# is not held by the client." Probe once and fall back to a one-time copy so
# bootstrap.sh still completes; a copy means edits require re-running this
# script, so the probe failure is printed clearly with the real fix.
SYMLINKS_WORK=""
check_symlinks() {
    if [ -n "$SYMLINKS_WORK" ]; then
        return
    fi
    local probe="$DOTFILES_DIR/.symlink-probe-$$"
    if ln -sf "$DOTFILES_DIR/bootstrap.sh" "$probe" 2>/dev/null; then
        rm -f "$probe"
        SYMLINKS_WORK="yes"
    else
        SYMLINKS_WORK="no"
        echo "⚠️  Symlinks are not permitted on this machine (Windows without Developer"
        echo "    Mode, or a non-admin shell). Falling back to copying files instead of"
        echo "    linking them — re-run bootstrap.sh after editing anything in this repo."
        echo "    Fix permanently: Settings → Privacy & Security → For Developers →"
        echo "    Developer Mode (Windows 11), then re-run this script."
    fi
}

# link_path SRC DEST — symlinks SRC to DEST, or copies SRC into DEST when
# this machine cannot create symlinks. DEST's existing content (file or dir)
# is replaced.
link_path() {
    local src="$1" dest="$2"
    check_symlinks
    rm -rf "$dest"
    if [ "$SYMLINKS_WORK" = "yes" ]; then
        ln -sf "$src" "$dest"
    elif [ -d "$src" ]; then
        cp -r "$src" "$dest"
    else
        cp "$src" "$dest"
    fi
}

# 1. Install prerequisites (jq is needed for parsing API responses in settings.json)
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y && sudo apt-get install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    fi
fi

# 1b. Install the Gemini CLI (required by claude/commands/gemini.md; OMP's own
# "gemini" agent talks to the Google API directly and does not need this CLI).
# Best-effort: an install failure here (flaky registry, or npm's refusal to
# run under WSL 1) must not abort the rest of bootstrap via `set -e`, which
# also sets up the independent OMP environment below.
if ! command -v gemini &> /dev/null; then
    echo "📦 Installing @google/gemini-cli..."
    if ! npm install -g @google/gemini-cli; then
        echo "⚠️  @google/gemini-cli install failed — Claude Code's /gemini command won't work here (OMP's /gemini agent is unaffected). If this is WSL 1, npm refuses to run under it: upgrade with 'wsl --set-version <distro> 2' from Windows, then re-run bootstrap.sh."
    fi
fi

# 1c. Force the Gemini CLI to use GEMINI_API_KEY instead of OAuth.
# On first run it defaults ~/.gemini/settings.json to "oauth-personal", which
# silently ignores GEMINI_API_KEY and fails with a 401 "expected OAuth 2 access
# token" error. Merge (not overwrite) so any other gemini CLI settings survive.
mkdir -p "$HOME/.gemini"
if [ -f "$HOME/.gemini/settings.json" ]; then
    jq '.security.auth.selectedType = "gemini-api-key"' "$HOME/.gemini/settings.json" \
        > "$HOME/.gemini/settings.json.tmp" && mv "$HOME/.gemini/settings.json.tmp" "$HOME/.gemini/settings.json"
else
    echo '{"security":{"auth":{"selectedType":"gemini-api-key"}}}' > "$HOME/.gemini/settings.json"
fi
echo "✅ Set Gemini CLI auth type to gemini-api-key"

# 2. Ensure ~/.claude directory exists
mkdir -p "$HOME/.claude"

# 3. Symlink settings.json
if [ -f "$DOTFILES_DIR/claude/settings.json" ]; then
    link_path "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
    echo "✅ Linked ~/.claude/settings.json"
fi

# 4. Symlink CLAUDE.md
if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
    link_path "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    echo "✅ Linked ~/.claude/CLAUDE.md"
fi

# 5. Symlink commands/ (whole directory, so new commands need no bootstrap.sh change)
if [ -d "$DOTFILES_DIR/claude/commands" ]; then
    link_path "$DOTFILES_DIR/claude/commands" "$HOME/.claude/commands"
    echo "✅ Linked ~/.claude/commands"
fi

# 6. Symlink scripts/ and install their dependencies (node_modules is gitignored, not committed)
if [ -d "$DOTFILES_DIR/claude/scripts" ]; then
    link_path "$DOTFILES_DIR/claude/scripts" "$HOME/.claude/scripts"
    echo "✅ Linked ~/.claude/scripts"
    if [ -f "$DOTFILES_DIR/claude/scripts/package.json" ] && command -v npm &> /dev/null; then
        echo "📦 Installing scripts/ dependencies..."
        (cd "$DOTFILES_DIR/claude/scripts" && npm install)
    fi
fi

echo "🎉 Claude Code environment successfully configured!"

# --- OMP (Oh My Pi) --------------------------------------------------------
# omp/agent/AGENTS.md is the single canonical source for routing rules, agents,
# and commands: OMP reads it natively as ~/.omp/agent/AGENTS.md, and
# ~/.claude/CLAUDE.md (step 4 above) imports this same file via Claude Code's
# `@~/.omp/agent/AGENTS.md` syntax instead of keeping a separate duplicate copy.
# This section must run on every machine (even Claude-Code-only ones) so that
# import target exists.
echo "🚀 Setting up OMP dotfiles..."

mkdir -p "$HOME/.omp/agent"

# 7. Symlink native context file (routing rules, memory setup, Frappe notes)
if [ -f "$DOTFILES_DIR/omp/agent/AGENTS.md" ]; then
    link_path "$DOTFILES_DIR/omp/agent/AGENTS.md" "$HOME/.omp/agent/AGENTS.md"
    echo "✅ Linked ~/.omp/agent/AGENTS.md"
fi

# 8. Symlink custom agents/ and commands/ (whole directories)
if [ -d "$DOTFILES_DIR/omp/agent/agents" ]; then
    link_path "$DOTFILES_DIR/omp/agent/agents" "$HOME/.omp/agent/agents"
    echo "✅ Linked ~/.omp/agent/agents"
fi
if [ -d "$DOTFILES_DIR/omp/agent/commands" ]; then
    link_path "$DOTFILES_DIR/omp/agent/commands" "$HOME/.omp/agent/commands"
    echo "✅ Linked ~/.omp/agent/commands"
fi

# 8b. Symlink FLUX helper scripts (whole directory, so new scripts need no
# bootstrap.sh change). Used by the /flux command; pure-stdlib Python 3, no deps.
if [ -d "$DOTFILES_DIR/omp/agent/scripts" ]; then
    link_path "$DOTFILES_DIR/omp/agent/scripts" "$HOME/.omp/agent/scripts"
    echo "✅ Linked ~/.omp/agent/scripts"
fi

# 8c. Symlink models.yml (shared model registry — adds DeepSeek R1 for /diagram).
# Unlike config.yml this holds no machine-specific settings, so linking it
# wholesale is safe and keeps ~/.omp/agent/models.yml in sync across machines.
if [ -f "$DOTFILES_DIR/omp/agent/models.yml" ]; then
    link_path "$DOTFILES_DIR/omp/agent/models.yml" "$HOME/.omp/agent/models.yml"
    echo "✅ Linked ~/.omp/agent/models.yml"
fi

# 8d. Symlink authored web design skills (impeccable, taste) into
# ~/.claude/skills. Universal — no OMP gate: this is dotfiles-owned
# content (not third-party drift), read natively by Claude Code
# everywhere. Feeds step 8e (native OMP mirror) and step 8f
# (drift consolidation) below.
mkdir -p "$HOME/.claude/skills"
if [ -d "$DOTFILES_DIR/claude/skills" ]; then
    for skill_dir in "$DOTFILES_DIR"/claude/skills/*/; do
        skill_name="$(basename "$skill_dir")"
        link_path "$DOTFILES_DIR/claude/skills/$skill_name" "$HOME/.claude/skills/$skill_name"
        echo "✅ Linked ~/.claude/skills/$skill_name"
    done
fi

# 8e. Also mirror the same skills into ~/.omp/skills so OMP's native
# `.omp` skill provider (priority 100, always on, no source toggle,
# per omp://skills.md) picks them up as a reflex on every session —
# no per-request invocation needed. Do not rely on OMP's "claude"
# provider (priority 80, reads ~/.claude/skills) for this alone: it
# was verified NOT to expose skill://impeccable / skill://design-taste-
# frontend in a live session ("Unknown skill: impeccable") even with
# step 8d's symlinks in place, likely a disabled-by-default source
# toggle (enableClaudeUser) on that install. OMP-gated: ~/.omp/skills
# means nothing without omp.
if [ -d "$DOTFILES_DIR/claude/skills" ] && command -v omp &> /dev/null; then
    mkdir -p "$HOME/.omp/skills"
    for skill_dir in "$DOTFILES_DIR"/claude/skills/*/; do
        skill_name="$(basename "$skill_dir")"
        link_path "$DOTFILES_DIR/claude/skills/$skill_name" "$HOME/.omp/skills/$skill_name"
        echo "✅ Linked ~/.omp/skills/$skill_name (native OMP skill provider)"
    done
fi

# 8f. Re-merge any drift back into ~/.claude/skills (e.g. a third-party
# `<tool> install --platform claude`-style installer re-creating it on
# self-update) into the canonical ~/.omp/skills, then remove ~/.claude/skills
# again. OMP-only: native Claude Code without OMP only reads ~/.claude/skills
# for its own skill discovery, so running this on an OMP-less machine would
# silently break that — skip there and leave ~/.claude/skills as Claude
# Code's only functional copy. consolidate-claude-skills.sh itself skips
# symlinked entries (step 8d's impeccable/taste; step 8e's ~/.omp/skills
# mirrors are never scanned by it at all, since it only reads
# ~/.claude/skills), so it only ever sweeps real (third-party-written)
# directories left behind by that kind of self-update.
if [ -d "$DOTFILES_DIR/omp/agent/scripts" ]; then
    if command -v omp &> /dev/null; then
        bash "$HOME/.omp/agent/scripts/consolidate-claude-skills.sh" || echo "⚠️  consolidate-claude-skills.sh reported an issue (see above) — check ~/.claude/skills manually."
    else
        echo "ℹ️  Skipping ~/.claude/skills consolidation: omp not found on this machine (Claude Code needs ~/.claude/skills to stay populated here)."
    fi
fi

# 8g. Start the Hindsight memory server (OMP memory.backend: hindsight —
# see omp/agent/config.yml and AGENTS.md's "Memory (Hindsight)" section).
# Idempotent: does nothing if a `hindsight` container already exists
# (start/restart a stopped one yourself; this never recreates or updates
# it in place). Uses Gemini as the LLM backend so no new provider
# dependency is introduced beyond GEMINI_API_KEY, already required for
# /gemini (AGENTS.md routing rule 1). Named Docker volume (not a host bind
# mount) so the embedded Postgres (pg0) just works — no UID 1000
# permission setup needed.
if command -v docker &> /dev/null; then
    if [ -z "$(docker ps -aq -f name='^/hindsight$' 2>/dev/null)" ]; then
        if [ -n "$GEMINI_API_KEY" ]; then
            echo "🧠 Starting Hindsight memory server..."
            docker run -d --pull always --name hindsight --restart unless-stopped \
                -p 8888:8888 -p 9999:9999 \
                -e HINDSIGHT_API_LLM_PROVIDER=gemini \
                -e HINDSIGHT_API_LLM_API_KEY="$GEMINI_API_KEY" \
                -e HINDSIGHT_API_LLM_MODEL=gemini-3-flash-preview \
                -e HINDSIGHT_API_WORKER_ID=hindsight-omp \
                -v hindsight-data:/home/hindsight/.pg0 \
                ghcr.io/vectorize-io/hindsight:latest > /dev/null \
                && echo "✅ Started Hindsight (API http://localhost:8888, UI http://localhost:9999)" \
                || echo "⚠️  Failed to start Hindsight — check 'docker logs hindsight'."
        else
            echo "ℹ️  Skipping Hindsight memory server: GEMINI_API_KEY not set in this shell or ~/.omp/agent/.env."
        fi
    else
        echo "ℹ️  Hindsight container already exists — leaving it as-is (docker start/restart it yourself if stopped)."
    fi
else
    echo "ℹ️  Skipping Hindsight memory server: docker not found on this machine."
fi

# 9. Layer the shared modelRoles config on top of the machine-local
# ~/.omp/agent/config.yml via PI_CONFIG_FILES, instead of symlinking
# config.yml itself — config.yml also holds machine-specific settings
# (shellPath, theme) that must not be clobbered by another machine's copy.
# PI_CONFIG_FILES overlays deep-merge objects (modelRoles) on top of the
# global config, so this is additive, not destructive. Self-healing: if the
# repo was cloned/moved to a different path since the last run (e.g. a
# leftover ~/Development/dotfiles clone that no longer exists), the old
# export line is replaced rather than left stale — grep-if-present alone
# would skip rewriting because the *variable name* is still found, even
# though the *path* it points to is wrong.
OMP_CONFIG_LINE="export PI_CONFIG_FILES=\"$DOTFILES_DIR/omp/agent/config.yml\""
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$OMP_CONFIG_LINE" "$rc"; then
        sed -i.bak -e '/^# OMP shared config (dotfiles)$/d' -e '/^export PI_CONFIG_FILES=/d' "$rc" && rm -f "$rc.bak"
        printf '\n# OMP shared config (dotfiles)\n%s\n' "$OMP_CONFIG_LINE" >> "$rc"
        echo "✅ Set PI_CONFIG_FILES in $rc"
    fi
done
if command -v setx &> /dev/null; then
    setx PI_CONFIG_FILES "$(cygpath -w "$DOTFILES_DIR/omp/agent/config.yml" 2>/dev/null || echo "$DOTFILES_DIR/omp/agent/config.yml")" > /dev/null
    echo "✅ Set PI_CONFIG_FILES via setx (new shells only — restart your terminal)"
fi

# 10. API keys for the AGENTS.md task-routing agents (nemotron, gemini, deepseek,
# deepseek-r, diagram) and the /flux script are per-machine, not committed. OMP
# environment first, then ~/.omp/agent/.env — either location satisfies the agent.
# Remind rather than fail if a key is in neither place.
check_api_key() {
    local var_name="$1" key_prefix="$2" agent_hint="$3"
    if [ -n "${!var_name:-}" ]; then
        return 0
    fi
    if [ -f "$HOME/.omp/agent/.env" ] && grep -Eq "${var_name}=\"?${key_prefix}[A-Za-z0-9]" "$HOME/.omp/agent/.env" 2>/dev/null; then
        return 0
    fi
    echo "⚠️  ${var_name} not found (shell env or ~/.omp/agent/.env) — add it manually to use ${agent_hint}."
}
check_api_key NVIDIA_API_KEY "nvapi-" "/nemotron, /diagram, and /flux"
check_api_key GEMINI_API_KEY "" "/gemini"
check_api_key DEEPSEEK_API_KEY "sk-" "/deepseek and /deepseek-r"

echo "🎉 OMP environment successfully configured!"

# --- Git hooks (all repos) --------------------------------------------------
# core.hooksPath points EVERY repo on this machine at one shared hooks dir
# instead of each repo's own .git/hooks, so a hook added here reaches
# existing repos immediately -- no per-project install step, and it
# propagates to other machines via this same bootstrap.sh run.
#
# Trade-off, not a bug: this replaces .git/hooks for ALL repos, including
# ones with their own local hooks. None of this user's repos had a real
# (non-.sample) local hook as of 2026-08-20. If a project later installs
# husky/pre-commit/etc., that tool's own core.hooksPath write in the
# project-local .git/config takes precedence over this global one (normal
# git config precedence) and our hooks silently stop firing there -- not a
# conflict, just scoped out for that repo.
echo "🚀 Setting up shared git hooks..."
if [ -d "$DOTFILES_DIR/git/hooks" ]; then
    link_path "$DOTFILES_DIR/git/hooks" "$HOME/.git-hooks"
    git config --global core.hooksPath "$HOME/.git-hooks"
    echo "✅ Linked ~/.git-hooks and set core.hooksPath globally"
fi
echo "🎉 Git hooks configured!"
