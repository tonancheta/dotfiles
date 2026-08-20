# Instructions

Canonical task-routing policy, graphify trigger, and troubleshooting notes live in
`~/.omp/agent/AGENTS.md` (this repo's `omp/agent/AGENTS.md`), shared with OMP so the two
tools don't maintain drifting copies of the same rules. Imported below.

@~/.omp/agent/AGENTS.md

## Claude Code Adapter Notes

The imported rules describe OMP's dispatch mechanism (`task` tool -> an OMP agent file
under `omp/agent/agents/`). Claude Code has no `task` tool and no OMP agent files, so the
actual mechanism per rule is:

- **`/gemini`, `/deepseek`, `/deepseek-r`** — implemented here as real slash commands at
  `~/.claude/commands/{gemini,deepseek,deepseek-r}.md`. They shell out via the `Bash` tool
  to the `gemini` CLI / DeepSeek API directly (not the OMP `task` tool). Use them exactly
  as named in the imported routing rules.
- **`/nemotron`, `/diagram`, `/flux`** — OMP-only for now; no Claude Code slash command
  exists yet. Don't attempt to invoke them here — fall back to doing that work natively
  (or ask for it to be ported to a `~/.claude/commands/` entry) until one exists.
