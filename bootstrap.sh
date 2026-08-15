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

# 1b. Install the Gemini CLI (required by claude/commands/gemini.md)
if ! command -v gemini &> /dev/null; then
    echo "📦 Installing @google/gemini-cli..."
    npm install -g @google/gemini-cli
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
# Same routing rules, agents, and commands, in OMP's native ~/.omp/agent/
# format (native context files take priority over .claude/CLAUDE.md inside
# OMP sessions, so this is the source of truth once OMP is in the loop).
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

# 10. NVIDIA API key is per-machine, not committed. Remind rather than fail.
if [ ! -f "$HOME/.omp/agent/.env" ] || ! grep -q "NVIDIA_API_KEY=nvapi-" "$HOME/.omp/agent/.env" 2>/dev/null; then
    echo "⚠️  NVIDIA_API_KEY not found in ~/.omp/agent/.env — add it manually to use /nemotron."
fi

echo "🎉 OMP environment successfully configured!"
