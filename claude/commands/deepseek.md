---
description: Delegate test generation, docstrings, or routine boilerplate to DeepSeek-V3 (preserves Claude quota)
argument-hint: <what to generate, e.g. "Write Jest unit tests for services/auth.ts">
allowed-tools: Bash(~/.claude/scripts/deepseek.sh:*)
---
Task for DeepSeek-V3, not you: $ARGUMENTS

If the task names specific files, read them first so you can paste their real contents
into the prompt below — DeepSeek has no filesystem access of its own.

Run it via the Bash tool: `~/.claude/scripts/deepseek.sh deepseek-chat "<task plus any relevant file contents>"`

Read DeepSeek's output, check it actually compiles/type-checks and matches this repo's
conventions, fix anything wrong, then use your own Write/Edit tool to save the result —
never write DeepSeek's output to disk unread.
