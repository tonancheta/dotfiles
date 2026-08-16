# Token-Preservation Execution Rules

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test generation tasks to Gemini and DeepSeek.

## Default Rule
Coding work is distributed to an integrated AI (currently DeepSeek or Gemini) **by default**. Only keep a coding task on native Claude Code when one of these exceptions applies:
- The delegated AI cannot handle the task (unfamiliar framework/convention, needs context too large or too specific to hand off cleanly, output quality is unreliable for the task at hand).
- The task needs fine-grained precision control (exact schema/spec adherence where a subtly-wrong output is costly to catch, intricate multi-step reasoning that must stay coherent with prior decisions in-session).
- The task needs local file access, terminal execution, or git operations (writing to disk, running bench/build/test commands, commits, pushes).

This is a default, not an absolute — judgment calls in either direction are fine, but the starting assumption for any new coding task should be "can this go to DeepSeek or Gemini first?" not "let me just do this directly."

## Routing Rules
1. **Repository Audits & Code Reviews -> `/gemini`**
   - Use `/gemini` for large file reviews, monorepo context scanning, or reading massive log files via Gemini API.
   - Example: `/gemini "Review the changes in src/ controller for security flaws."`

2. **Test Generation, Documentation & Routine Boilerplate -> `/deepseek`**
   - Use `/deepseek` for writing unit tests, docstrings, or routine feature boilerplate via DeepSeek-V3 — this includes ordinary implementation code (doctype/schema definitions, CRUD scaffolding, standard UI components), not just tests/docs.
   - Example: `/deepseek "Write Jest unit tests for services/auth.ts."`

3. **Complex Logic & Debugging -> `/deepseek-r`**
   - Use `/deepseek-r` for heavy algorithmic reasoning or complex bug investigations via DeepSeek-R1.
   - Example: `/deepseek-r "Explain why this database query causes deadlocks."`

4. **File Writes & Local Execution -> Native Claude Code**
   - Use native Claude Code to write files to disk, run local git commands, and manage terminal/bench execution — regardless of which AI authored the content being written or executed.
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Frappe Bench Troubleshooting
When a Frappe bench dev site misbehaves in ways that don't point to an obvious code change — blank `/desk` page, login form resetting with no error, JS console errors like `$(...).dropdown is not a function` — check these in order before deep app-level debugging, especially after moving/copying a bench directory:
1. **Port mismatch**: compare `sites/common_site_config.json`'s `webserver_port` against the actual bound port in `Procfile`'s `web: bench serve --port <port>` line.
2. **Stale browser site data**: cookies/cache/localStorage for the dev domain can linger from before a port change or move and cause profile-specific JS failures that don't reproduce in Incognito or another browser. Clear via DevTools → Application → Clear site data.
3. **Stale incremental build**: `bench watch`'s esbuild live-rebuild can leave an inconsistent bundle that looks byte-correct on disk but misbehaves at runtime. Force a clean rebuild with `bench build --app <app> --force` before assuming it's a real code/dependency bug.
