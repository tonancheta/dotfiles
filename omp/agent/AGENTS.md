# Token-Preservation Task Routing

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test
generation tasks to Gemini, DeepSeek, and NVIDIA-hosted Nemotron.

## Routing Rules
1. **Repository Audits & Code Reviews -> `/gemini`**
   - Use `/gemini` for large file reviews, monorepo context scanning, or reading massive log files.
   - Dispatches via the `task` tool to the `gemini` OMP agent (`omp/agent/agents/gemini.md`,
     `modelRoles.gemini` in `config.yml`, Google `gemini-3-pro-preview`).
   - Example: `/gemini "Review the changes in src/ controller for security flaws."`
   - Requires `GEMINI_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

2. **Test Generation & Documentation -> `/deepseek`**
   - Use `/deepseek` for writing unit tests, docstrings, or routine feature boilerplate.
   - Dispatches via the `task` tool to the `deepseek` OMP agent (`omp/agent/agents/deepseek.md`,
     `modelRoles.deepseek` in `config.yml`, `deepseek-v4-flash`).
   - Example: `/deepseek "Write Jest unit tests for services/auth.ts."`
   - Requires `DEEPSEEK_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

3. **Complex Logic & Debugging -> `/deepseek-r`**
   - Use `/deepseek-r` for heavy algorithmic reasoning or complex bug investigations.
   - Dispatches via the `task` tool to the `deepseek-r` OMP agent (`omp/agent/agents/deepseek-r.md`,
     `modelRoles.deepseek-r` in `config.yml`, `deepseek-v4-pro`).
   - Example: `/deepseek-r "Explain why this database query causes deadlocks."`
   - Requires `DEEPSEEK_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

4. **File Writes & Orchestration -> Native agent**
   - Use the native session (OMP or Claude Code) to write edited files to disk, run local git commands, and manage terminal execution.
   - Rules 1-3 and 5 are read-only (`read, grep, glob, lsp`): they report findings/content back to you, not to disk.

5. **Second-Opinion Review -> `/nemotron`**
   - Use `/nemotron` to cross-check a diff, design decision, or debugging conclusion via
     NVIDIA-hosted `nvidia/llama-3.3-nemotron-super-49b-v1.5` before finalizing. It is
     independently trained from Gemini/DeepSeek, so it catches blind spots a same-lineage
     reviewer (rules 1-3) would share.
   - Do not route primary audits, test generation, or first-pass debugging here — it is a
     checker, not a replacement for rules 1-3.
   - Dispatches via the `task` tool to the `nemotron` OMP agent (`omp/agent/agents/nemotron.md`,
     `modelRoles.nemotron` in `config.yml`).
   - Example: `/nemotron "Check this auth diff for race conditions and edge cases."`
   - Requires `NVIDIA_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

6. **Technical Diagrams -> `/diagram`**
   - Use `/diagram` to turn architecture, flows, sequences, ER models, or state
     machines into renderable diagram-as-code (Mermaid, Graphviz/DOT, PlantUML, D2).
   - Dispatches via the `task` tool to the `diagram` OMP agent (`omp/agent/agents/diagram.md`,
     `modelRoles.diagram` in `config.yml`, NVIDIA-hosted `nvidia/nemotron-3-ultra-550b-a55b`).
     No custom registration needed — the bundled model catalog already ships this one with
     `reasoning: true`. (Previously DeepSeek R1 via a custom `omp/agent/models.yml` entry;
     NVIDIA removed DeepSeek R1 from its catalog entirely as of 2026-08-20, so the entry
     and this model choice were retired together — see `models.yml`'s changelog comment.)
   - It's a text model: it emits diagram *source*, not images. Render/save it yourself.
   - Example: `/diagram "Sequence diagram of the OAuth refresh flow in services/auth.ts."`
   - Requires `NVIDIA_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

7. **Image Generation -> `/flux`**
   - Use `/flux` to generate an image from a text prompt with FLUX.1 on NVIDIA Build.
   - Runs `~/.omp/agent/scripts/flux.py` (symlinked from `omp/agent/scripts/flux.py`), which POSTs to
     NVIDIA's Visual GenAI endpoint (`https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-dev`)
     and saves the returned image to the current directory. FLUX.1 is a REST image API, not a chat
     model, so it is a script/command — not a `models.yml` model or a task-routing agent.
   - Example: `/flux "isometric 3D icon of a database, soft studio lighting" --width 1024 --height 1024`
   - Requires `NVIDIA_API_KEY` in the shell environment or `~/.omp/agent/.env` (per machine, not committed).

# graphify
- **graphify** (`~/.omp/agent/skills/graphify/SKILL.md` or `~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Frappe Bench Troubleshooting
When a Frappe bench dev site misbehaves in ways that don't point to an obvious code change — blank `/desk` page, login form resetting with no error, JS console errors like `$(...).dropdown is not a function` — check these in order before deep app-level debugging, especially after moving/copying a bench directory:
1. **Port mismatch**: compare `sites/common_site_config.json`'s `webserver_port` against the actual bound port in `Procfile`'s `web: bench serve --port <port>` line.
2. **Stale browser site data**: cookies/cache/localStorage for the dev domain can linger from before a port change or move and cause profile-specific JS failures that don't reproduce in Incognito or another browser. Clear via DevTools → Application → Clear site data.
3. **Stale incremental build**: `bench watch`'s esbuild live-rebuild can leave an inconsistent bundle that looks byte-correct on disk but misbehaves at runtime. Force a clean rebuild with `bench build --app <app> --force` before assuming it's a real code/dependency bug.

# User-Run Terminal Commands (sudo/root-gated or otherwise out of agent reach)
When a task needs commands the agent cannot run itself (missing sudo password, no
SSH credentials, interactive prompts, etc.) in this or any other project:
1. Write the exact commands into a single `.sh` script in the project (e.g.
   `deploy/setup-foo.sh`), `chmod +x` it. Never hand the user ad-hoc commands to
   retype or paste output back from — script it.
2. Make it idempotent/safe to re-run, and `set -euxo pipefail` (or equivalent) so
   it fails loudly and every command is echoed into its own output.
3. Tell the user to run it with output redirected to a file the agent names, e.g.:
     sudo bash path/to/setup-foo.sh > path/to/setup-foo.log 2>&1
   The file must land somewhere the invoking user's shell owns (redirection happens
   before `sudo` execs, so plain user-owned paths are readable back by the agent
   without another round trip — do not have the script itself write the log).
4. After the user confirms it ran, `read`/`grep` the log file directly instead of
   asking them to paste output.
