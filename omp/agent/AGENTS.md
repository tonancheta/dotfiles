# Token-Preservation Task Routing

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test
generation tasks to Gemini, DeepSeek, and NVIDIA-hosted Nemotron.

## Default Rule
Coding work is distributed to an integrated AI (currently DeepSeek or Gemini) **by default**. Only keep a coding task on the native agent session when one of these exceptions applies:
- The delegated AI cannot handle the task (unfamiliar framework/convention, needs context too large or too specific to hand off cleanly, output quality is unreliable for the task at hand).
- The task needs fine-grained precision control (exact schema/spec adherence where a subtly-wrong output is costly to catch, intricate multi-step reasoning that must stay coherent with prior decisions in-session).
- The task needs local file access, terminal execution, or git operations (writing to disk, running bench/build/test commands, commits, pushes).

This is a default, not an absolute — judgment calls in either direction are fine, but the starting assumption for any new coding task should be "can this go to DeepSeek or Gemini first?" not "let me just do this directly."

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

# Memory (Hindsight)
Autonomous memory is on (`memory.backend: hindsight` in `config.yml`) backed by a local
`hindsight` Docker container that bootstrap.sh starts and keeps restarted
(`ghcr.io/vectorize-io/hindsight:latest`, API on `localhost:8888`, UI on `localhost:9999`,
Gemini as its LLM backend via `GEMINI_API_KEY` — no separate key needed). This is a
background system, not a manual workflow:
- `recall`/`retain`/`reflect` tools are exposed automatically; the primary session
  auto-recalls on its first turn and auto-retains conversation turns periodically.
- Nothing to invoke by hand for routine use. Only reach for `recall`/`retain`/`reflect`
  explicitly when you need to query or store something outside that automatic cadence.
- `/memory view` inspects what's currently injected; `/memory stats`/`diagnose` for
  backend health; container logs via `docker logs hindsight` for the server itself.
- Bank scoping is per-project-tagged by default (see `omp://memory.md`), so this
  project's memories don't bleed into an unrelated repo's recall.
- The Hindsight database itself is per-machine (a local `hindsight-data` Docker
  volume) — it does NOT sync across machines on its own. Cross-machine sync goes
  through this dotfiles repo, via `omp/agent/scripts/sync-hindsight-memory.sh`:
  - `push`: `hindsight-admin backup` the running container -> `omp/hindsight-backup.zip`
    -> commit -> `git push`.
  - `pull`: `git pull` -> `hindsight-admin restore --yes` into the running container.
    bootstrap.sh runs this automatically, but ONLY right after starting a brand-new
    empty container (step 8h) — it never touches an already-populated one, so a
    normal bootstrap.sh re-run can't clobber local data. `bootstrap-new.sh` (repo
    root) is a variant that starts Hindsight the same way but deliberately skips
    this pull, so a fresh container comes up empty instead of seeded from the
    last-pushed snapshot — use it when you want this machine's memory bank to
    start clean rather than inherit the shared one.
  - `omp/agent/hooks/post/hindsight-sync.ts` best-effort auto-pushes in the
    background on every omp `session_shutdown` (failures are silent — logged to
    `~/.omp/agent/scripts/hindsight-sync.log`, not surfaced). `mem-push`/`mem-pull`
    shell aliases (step 9b) run the same script manually when you want to see
    success/failure live, e.g. before switching machines mid-day.
  - **This is a full snapshot overwrite, not a merge.** Working on machine A, then
    working on machine B without pulling A's snapshot first, then pushing from B,
    silently discards A's un-pushed memories — git has no visibility into the zip's
    contents to warn you. Pull before you start on any machine; push when you're done.
  - **Which variant runs on future logins is switchable, not fixed.** Both
    scripts' step 9c/9d write `~/.omp/agent/.bootstrap-variant` with their own
    path and register `bootstrap-autorun.sh` (repo root) in `~/.bashrc`/
    `~/.zshrc`. On each new interactive shell, `bootstrap-autorun.sh` re-runs
    whichever script that state file names, at most once per calendar day, in
    the background (log: `~/.omp/agent/bootstrap-autorun.log`). So running
    `bootstrap-new.sh` once makes it the one that keeps running on subsequent
    logins; running plain `bootstrap.sh` again switches it back.

(Previously graphify's per-repo knowledge-graph skill filled this role. Removed:
redundant with Hindsight, and its skill discovery was independently found to be
non-deterministic on `.omp` native provider installs — see the removal decision's
chat history if resurrecting either tool.)

# Web UI/UX Design
Whenever designing, redesigning, critiquing, or polishing a **web** frontend (websites, landing pages, dashboards, product UI, components), consult and apply both skills below together — treat them as required references for that work, not optional flavor:
- **impeccable** (`~/.claude/skills/impeccable/SKILL.md`) — design vocabulary and 23 commands (`/impeccable init`, `craft`, `critique`, `audit`, `polish`, `bolder`, `quieter`, etc.) plus 59 deterministic anti-pattern detector rules against generic "AI slop" (default fonts, purple-to-blue gradients, nested cards, gray-on-color text).
- **design-taste-frontend** ("taste") (`~/.claude/skills/design-taste-frontend/SKILL.md`) — reads the brief, infers design direction (brand vibe, layout variance, motion intensity, visual density), and enforces anti-slop layout/typography/motion rules.
Run `/impeccable audit` or `/impeccable critique` on existing UI before shipping changes to it, not just on new builds.

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
