---
description: Delegate complex algorithmic reasoning or deep bug investigation to DeepSeek-R1 (preserves Claude quota)
argument-hint: <bug or logic to analyze, e.g. "Explain why this database query causes deadlocks">
allowed-tools: Bash(~/.claude/scripts/deepseek.sh:*)
---
Task for DeepSeek-R1, not you: $ARGUMENTS

If the task references specific code, read it first so you can paste the real contents
into the prompt below — DeepSeek has no filesystem access of its own.

Run it via the Bash tool: `~/.claude/scripts/deepseek.sh deepseek-reasoner "<task plus any relevant code/logs>"`

R1's reasoning traces can be long. Read the conclusion, verify it against the actual
code/logs yourself before trusting it, then explain the finding to the user in your own words.
