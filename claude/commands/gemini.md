---
description: Delegate a large-context repo audit or code review to Gemini (preserves Claude quota)
argument-hint: <what to review, e.g. "Review the changes in src/ controller for security flaws">
allowed-tools: Bash(gemini:*)
---
Task for Gemini, not you: $ARGUMENTS

Run it via the Bash tool: `gemini --skip-trust -p "$ARGUMENTS"`

(`--skip-trust` bypasses the Gemini CLI's own per-directory trust prompt, which has no
way to be answered in this headless invocation — Claude Code's own trust model already
covers this.)

Gemini's CLI has its own large context window and can read files/directories itself
(it supports `@path/to/file` and `@path/to/dir` inside the prompt) — prefer pointing it
at real paths over pasting file contents yourself.

Once Gemini responds, do not relay it verbatim. Spot-check anything that references
specific code by reading the file yourself, then give the user a concise summary of
the findings. Flag anything that looks wrong or contradicts what you can see in the repo.
