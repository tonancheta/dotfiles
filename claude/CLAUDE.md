# Token-Preservation Execution Rules

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test generation tasks to Gemini and DeepSeek.

## Routing Rules
1. **Repository Audits & Code Reviews -> `/gemini`**
   - Use `/gemini` for large file reviews, monorepo context scanning, or reading massive log files via Gemini API.
   - Example: `/gemini "Review the changes in src/ controller for security flaws."`

2. **Test Generation & Documentation -> `/deepseek`**
   - Use `/deepseek` for writing unit tests, docstrings, or routine feature boilerplate via DeepSeek-V3.
   - Example: `/deepseek "Write Jest unit tests for services/auth.ts."`

3. **Complex Logic & Debugging -> `/deepseek-r`**
   - Use `/deepseek-r` for heavy algorithmic reasoning or complex bug investigations via DeepSeek-R1.
   - Example: `/deepseek-r "Explain why this database query causes deadlocks."`

4. **File Writes & Orchestration -> Native Claude Code**
   - Use native Claude Code to write edited files to disk, run local git commands, and manage terminal execution.
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Frappe Bench Troubleshooting
When a Frappe bench dev site misbehaves in ways that don't point to an obvious code change — blank `/desk` page, login form resetting with no error, JS console errors like `$(...).dropdown is not a function` — check these in order before deep app-level debugging, especially after moving/copying a bench directory:
1. **Port mismatch**: compare `sites/common_site_config.json`'s `webserver_port` against the actual bound port in `Procfile`'s `web: bench serve --port <port>` line.
2. **Stale browser site data**: cookies/cache/localStorage for the dev domain can linger from before a port change or move and cause profile-specific JS failures that don't reproduce in Incognito or another browser. Clear via DevTools → Application → Clear site data.
3. **Stale incremental build**: `bench watch`'s esbuild live-rebuild can leave an inconsistent bundle that looks byte-correct on disk but misbehaves at runtime. Force a clean rebuild with `bench build --app <app> --force` before assuming it's a real code/dependency bug.
