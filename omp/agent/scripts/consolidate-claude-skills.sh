#!/bin/bash
# Merge any content that has drifted back into ~/.claude/skills into the
# canonical ~/.omp/skills, then remove the drifted entries from
# ~/.claude/skills.
#
# Why this exists: OMP's native skill provider reads ~/.omp/skills (highest
# discovery priority); its separate "claude" provider also reads
# ~/.claude/skills, so OMP itself never needs both populated. Third-party
# installers (e.g. `graphify install --platform claude`) hardcode
# ~/.claude/skills as their install target and recreate it on every
# self-update, so this re-merges that drift back to one canonical location
# instead of letting two copies of the same skill diverge.
#
# Symlinked entries under ~/.claude/skills (bootstrap.sh's own
# claude/skills/* installs, e.g. impeccable, design-taste-frontend) are
# left untouched: a symlink there means "dotfiles put this here on
# purpose," not drift, and it must stay put for Claude Code's own skill
# discovery on OMP-less machines. Only real (non-symlink) directories --
# i.e. content a third-party installer actually wrote -- count as drift.
#
# IMPORTANT — only meaningful on machines that actually run OMP. Native
# Claude Code without OMP has no concept of ~/.omp/skills at all and reads
# ONLY ~/.claude/skills for its own skill auto-invocation. Callers MUST gate
# this on `command -v omp` before running it: running it unconditionally
# would silently break Claude Code's native skill discovery (graphify, etc.)
# on OMP-less machines (e.g. a Claude-Code-only macOS/Windows box), since
# nothing there ever reads ~/.omp/skills.
set -e

CLAUDE_SKILLS="$HOME/.claude/skills"
OMP_SKILLS="$HOME/.omp/skills"

if [ ! -e "$CLAUDE_SKILLS" ]; then
    echo "consolidate-claude-skills: no drift ($CLAUDE_SKILLS absent), nothing to do."
    exit 0
fi

if [ ! -d "$CLAUDE_SKILLS" ]; then
    echo "consolidate-claude-skills: WARNING $CLAUDE_SKILLS exists but is not a directory -- leaving it, needs manual review." >&2
    exit 1
fi

mkdir -p "$OMP_SKILLS"

shopt -s nullglob dotglob
entries=("$CLAUDE_SKILLS"/*)
shopt -u nullglob dotglob

if [ ${#entries[@]} -eq 0 ]; then
    rmdir "$CLAUDE_SKILLS"
    echo "consolidate-claude-skills: $CLAUDE_SKILLS was empty, removed it."
    exit 0
fi

moved=0
skipped=0
for entry in "${entries[@]}"; do
    if [ -L "$entry" ]; then
        # Dotfiles-managed skill symlink (bootstrap.sh step 8d) -- leave in place.
        skipped=$((skipped + 1))
        continue
    fi
    name="$(basename "$entry")"
    dest="$OMP_SKILLS/$name"
    if [ -e "$dest" ]; then
        echo "consolidate-claude-skills: replacing stale $dest with fresh copy from $CLAUDE_SKILLS/$name"
        rm -rf "$dest"
    else
        echo "consolidate-claude-skills: moving new skill $name to $OMP_SKILLS"
    fi
    mv "$entry" "$dest"
    moved=$((moved + 1))
done

remaining_non_symlinks="$(find "$CLAUDE_SKILLS" -mindepth 1 -maxdepth 1 ! -type l 2>/dev/null)"
if [ -z "$remaining_non_symlinks" ] && [ $skipped -eq 0 ]; then
    rmdir "$CLAUDE_SKILLS"
    echo "consolidate-claude-skills: merged $moved skill(s), removed now-empty $CLAUDE_SKILLS."
elif [ -z "$remaining_non_symlinks" ]; then
    echo "consolidate-claude-skills: merged $moved skill(s); left $skipped dotfiles-managed symlink(s) in place under $CLAUDE_SKILLS (expected)."
else
    echo "consolidate-claude-skills: WARNING merged $moved skill(s) but $CLAUDE_SKILLS still has unexpected non-symlink contents: $remaining_non_symlinks" >&2
fi
