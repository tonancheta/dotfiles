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

# 7. Symlink native context file (routing rules, graphify trigger, Frappe notes)
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

# 9. Layer the shared modelRoles config on top of the machine-local
# ~/.omp/agent/config.yml via PI_CONFIG_FILES, instead of symlinking
# config.yml itself — config.yml also holds machine-specific settings
# (shellPath, theme) that must not be clobbered by another machine's copy.
# PI_CONFIG_FILES overlays deep-merge objects (modelRoles) on top of the
# global config, so this is additive, not destructive. Idempotent: only
# appends if not already present.
OMP_CONFIG_LINE="export PI_CONFIG_FILES=\"$DOTFILES_DIR/omp/agent/config.yml\""
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "PI_CONFIG_FILES" "$rc"; then
        printf '\n# OMP shared config (dotfiles)\n%s\n' "$OMP_CONFIG_LINE" >> "$rc"
        echo "✅ Added PI_CONFIG_FILES to $rc"
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
