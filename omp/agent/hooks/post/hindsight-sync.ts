// Best-effort auto-push of the Hindsight memory database to the dotfiles
// repo (see omp/agent/scripts/sync-hindsight-memory.sh) whenever the main
// omp session ends. Fire-and-forget: spawns the push script detached and
// does not await it, so a slow/failed git push or network hiccup never
// delays session exit. Failures are silent to the user by design — check
// the log file below if memory doesn't seem to be syncing across machines.
//
// This is a convenience layer, not the only sync path: run
// `sync-hindsight-memory.sh push` manually any time you want a push you can
// see succeed or fail in your own terminal (e.g. before switching machines
// mid-day), since this hook's failures are logged, not surfaced live.
import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
import { homedir } from "node:os";
import { join } from "node:path";

export default function hindsightSync(omp: HookAPI): void {
  omp.on("session_shutdown", () => {
    const script = join(homedir(), ".omp/agent/scripts/sync-hindsight-memory.sh");
    const log = join(homedir(), ".omp/agent/scripts/hindsight-sync.log");
    try {
      const proc = Bun.spawn({
        cmd: ["bash", "-c", `exec bash "$0" push >> "$1" 2>&1`, script, log],
        stdio: ["ignore", "ignore", "ignore"],
        detached: true,
      });
      proc.unref();
    } catch {
      // Best-effort: never let a sync failure affect session shutdown.
    }
  });
}
