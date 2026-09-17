---
description: Delegate a large-context repo audit or code review to Qwen (preserves Claude quota)
argument-hint: <what to review, e.g. "Review the changes in src/ controller for security flaws">
allowed-tools: Bash(qwen:*)
---
Task for Qwen, not you: $ARGUMENTS

Run it via the Bash tool: `qwen -p "$ARGUMENTS"`

Qwen Code's Trusted Folders feature is disabled by default (unlike the old Gemini CLI's),
so there's no per-directory trust prompt to bypass here — bootstrap.sh's `~/.qwen/settings.json`
write never sets `security.folderTrust`, and this headless `-p` invocation needs no extra flag
for that reason.

Qwen Code has its own large context window and can read files/directories itself
(it supports `@path/to/file` and `@path/to/dir` inside the prompt) — prefer pointing it
at real paths over pasting file contents yourself.

Once Qwen responds, do not relay it verbatim. Spot-check anything that references
specific code by reading the file yourself, then give the user a concise summary of
the findings. Flag anything that looks wrong or contradicts what you can see in the repo.
