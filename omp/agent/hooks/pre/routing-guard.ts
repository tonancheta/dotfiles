// Mechanically enforces the parts of AGENTS.md's "Token-Preservation Task
// Routing" policy that are reliably detectable from tool-call shape alone.
// This exists because prose-only policy failed silently in practice: a long
// session with dozens of tool calls has no natural point where "should this
// specific file go to /deepseek?" gets re-asked, so the agent defaults to
// doing everything itself and only notices the drift when someone audits it
// after the fact. This hook forces the question at the moment it matters.
//
// What it enforces (see each block below for the specific rule):
//   1. Test-file writes/edits          -> AGENTS.md rule 2 (test gen -> /deepseek)
//   2. `task` calls with no `agent`    -> AGENTS.md Default Rule (never silently
//                                          default the spawn policy; state a
//                                          model on every dispatch)
//   3. Prod/shared-env deploy commands -> AGENTS.md rule 5 (get a /nemotron
//                                          second opinion before finalizing)
//
// What it deliberately does NOT enforce: which model is right for a given
// chunk of "write this new feature" coding work, or whether documentation
// should have been delegated. Those require judging task *content*, which a
// regex-based hook cannot do reliably without a high false-positive rate.
// That part of the policy stays enforced by AGENTS.md's todo-tagging
// requirement (state the route per planned artifact before starting) plus
// this agent's own judgment -- this hook is the mechanical backstop for the
// two categories that ARE syntactically checkable, not a replacement for the
// rest of the policy.
//
// Bypass: add a `[routing:<reason>]` tag anywhere in the tool call's `i`
// (intent) argument to proceed on the native agent anyway. This is the
// explicit, stated-exception path AGENTS.md requires instead of a silent
// judgment call -- it costs nothing (every write/edit/bash/task call already
// takes `i`), so it never actually blocks real work, it only forces the
// routing decision to be written down where an audit can see it.
import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";

const ROUTING_TAG = /\[routing:[^\]]*\]/i;

const TEST_DIR_PATTERN =
  /(^|\/)(tests?|__tests__|spec)\/.*\.(php|ts|tsx|jsx|js|mjs|cjs|py|rb|go|java|kt)$/i;
const TEST_FILENAME_PATTERN =
  /(\.test\.|\.spec\.|Test\.(php|java|kt)$|_test\.(go|py)$|_spec\.rb$)/i;

const DEPLOY_COMMAND_PATTERN =
  /docker\s+compose\b[^\n]*(-f|--file)\s*\S*prod\S*\.ya?ml[^\n]*\bup\b|kubectl\s+(apply|rollout)|git\s+push\b[^\n]*\borigin\b[^\n]*\b(main|master)\b/i;

function isTestPath(path: string): boolean {
  return TEST_DIR_PATTERN.test(path) || TEST_FILENAME_PATTERN.test(path);
}

/** `edit` tool sections open with a `[PATH#TAG]` header line; pull the path out of it. */
function extractEditPath(patchInput: string): string | null {
  const match = patchInput.match(/^\[([^\]#]+)#[0-9A-Fa-f]{4}\]/m);
  return match ? match[1] : null;
}

export default function routingGuard(omp: HookAPI): void {
  let nemotronRanThisSession = false;

  omp.on("tool_call", async (event) => {
    const intent = String((event.input as Record<string, unknown>).i ?? "");
    const hasRoutingTag = ROUTING_TAG.test(intent);

    if (event.toolName === "task") {
      const tasks = Array.isArray((event.input as Record<string, unknown>).tasks)
        ? ((event.input as Record<string, unknown>).tasks as Array<Record<string, unknown>>)
        : [];

      if (tasks.some((t) => t?.agent === "nemotron")) {
        nemotronRanThisSession = true;
      }

      if (!hasRoutingTag && tasks.some((t) => !t?.agent)) {
        return {
          block: true,
          reason:
            'Routing policy (AGENTS.md Default Rule): every tasks[] item must set an ' +
            'explicit "agent" -- never omit it and rely on the spawn-policy default. Try ' +
            '"deepseek" or "gemini" first for coding/test/doc work per the Default Rule; ' +
            'set agent to "task" explicitly (not omitted) only when a stated exception ' +
            'applies (local file/git access, precision-critical, delegated AI unsuitable). ' +
            'Add a "[routing:<reason>]" tag to the intent to note the exception, or set agent.',
        };
      }
      return;
    }

    if (hasRoutingTag) return; // Explicit, stated exception -- always allowed.

    if (event.toolName === "write") {
      const path = String((event.input as Record<string, unknown>).path ?? "");
      if (isTestPath(path)) {
        return {
          block: true,
          reason:
            'Routing policy (AGENTS.md rule 2): test files go to /deepseek by default. ' +
            'Dispatch via the task tool with agent:"deepseek", or re-issue this write with ' +
            'a "[routing:<reason>]" tag in its intent if a stated exception applies.',
        };
      }
    }

    if (event.toolName === "edit") {
      const path = extractEditPath(String((event.input as Record<string, unknown>).input ?? ""));
      if (path && isTestPath(path)) {
        return {
          block: true,
          reason:
            'Routing policy (AGENTS.md rule 2): test files go to /deepseek by default. ' +
            'Dispatch via the task tool with agent:"deepseek", or re-issue this edit with ' +
            'a "[routing:<reason>]" tag in its intent if a stated exception applies.',
        };
      }
    }

    if (event.toolName === "bash") {
      const command = String((event.input as Record<string, unknown>).command ?? "");
      if (DEPLOY_COMMAND_PATTERN.test(command) && !nemotronRanThisSession) {
        return {
          block: true,
          reason:
            'Routing policy (AGENTS.md rule 5): get a /nemotron second opinion on the diff ' +
            'before a production/shared-environment deploy. Dispatch a task with ' +
            'agent:"nemotron" first, or re-issue this command with a "[routing:<reason>]" ' +
            'tag if a stated exception applies (e.g. trivial one-line hotfix).',
        };
      }
    }
  });
}
