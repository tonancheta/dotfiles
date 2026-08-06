#!/usr/bin/env bash
set -e

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "🚀 Setting up Claude Code dotfiles..."

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
    ln -sf "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
    echo "✅ Symlinked ~/.claude/settings.json"
fi

# 4. Symlink CLAUDE.md
if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
    ln -sf "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    echo "✅ Symlinked ~/.claude/CLAUDE.md"
fi

# 5. Symlink commands/ (whole directory, so new commands need no bootstrap.sh change)
if [ -d "$DOTFILES_DIR/claude/commands" ]; then
    rm -rf "$HOME/.claude/commands"
    ln -sf "$DOTFILES_DIR/claude/commands" "$HOME/.claude/commands"
    echo "✅ Symlinked ~/.claude/commands"
fi

# 6. Symlink scripts/ and install their dependencies (node_modules is gitignored, not committed)
if [ -d "$DOTFILES_DIR/claude/scripts" ]; then
    rm -rf "$HOME/.claude/scripts"
    ln -sf "$DOTFILES_DIR/claude/scripts" "$HOME/.claude/scripts"
    echo "✅ Symlinked ~/.claude/scripts"
    if [ -f "$DOTFILES_DIR/claude/scripts/package.json" ] && command -v npm &> /dev/null; then
        echo "📦 Installing scripts/ dependencies..."
        (cd "$DOTFILES_DIR/claude/scripts" && npm install)
    fi
fi

echo "🎉 Claude Code environment successfully configured!"
