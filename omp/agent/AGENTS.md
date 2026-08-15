# Token-Preservation Task Routing

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test
generation tasks to Gemini, DeepSeek, and NVIDIA-hosted Nemotron.

## Routing Rules
1. **Repository Audits & Code Reviews -> `/gemini`**
   - Use `/gemini` for large file reviews, monorepo context scanning, or reading massive log files via the Gemini CLI.
   - Example: `/gemini "Review the changes in src/ controller for security flaws."`

2. **Test Generation & Documentation -> `/deepseek`**
   - Use `/deepseek` for writing unit tests, docstrings, or routine feature boilerplate via DeepSeek-V3.
   - Example: `/deepseek "Write Jest unit tests for services/auth.ts."`

3. **Complex Logic & Debugging -> `/deepseek-r`**
   - Use `/deepseek-r` for heavy algorithmic reasoning or complex bug investigations via DeepSeek-R1.
   - Example: `/deepseek-r "Explain why this database query causes deadlocks."`

4. **File Writes & Orchestration -> Native agent**
   - Use the native session (OMP or Claude Code) to write edited files to disk, run local git commands, and manage terminal execution.

5. **Second-Opinion Review -> `/nemotron`**
   - Use `/nemotron` to cross-check a diff, design decision, or debugging conclusion via
     NVIDIA-hosted `nvidia/llama-3.3-nemotron-super-49b-v1.5` before finalizing. It is
     independently trained from Gemini/DeepSeek, so it catches blind spots a same-lineage
     reviewer (rules 1-3) would share.
   - Do not route primary audits, test generation, or first-pass debugging here — it is a
     checker, not a replacement for rules 1-3.
   - Example: `/nemotron "Check this auth diff for race conditions and edge cases."`
   - Requires `NVIDIA_API_KEY` in `~/.omp/agent/.env` (per machine, not committed).

# graphify
- **graphify** (`~/.omp/agent/skills/graphify/SKILL.md` or `~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Frappe Bench Troubleshooting
When a Frappe bench dev site misbehaves in ways that don't point to an obvious code change — blank `/desk` page, login form resetting with no error, JS console errors like `$(...).dropdown is not a function` — check these in order before deep app-level debugging, especially after moving/copying a bench directory:
1. **Port mismatch**: compare `sites/common_site_config.json`'s `webserver_port` against the actual bound port in `Procfile`'s `web: bench serve --port <port>` line.
2. **Stale browser site data**: cookies/cache/localStorage for the dev domain can linger from before a port change or move and cause profile-specific JS failures that don't reproduce in Incognito or another browser. Clear via DevTools → Application → Clear site data.
3. **Stale incremental build**: `bench watch`'s esbuild live-rebuild can leave an inconsistent bundle that looks byte-correct on disk but misbehaves at runtime. Force a clean rebuild with `bench build --app <app> --force` before assuming it's a real code/dependency bug.
