#!/usr/bin/env bash
# Read-only diagnostic: which Anthropic accounts are logged into OMP, and
# which one currently wins credential-resolution priority for chat requests.
#
# Background (see AGENTS.md's "Anthropic Account Priority" section): OMP
# exposes no config-level setting to pin OAuth account priority, and the
# real selection logic is closed-source. Repeated `omp dry-balance` checks
# across 2026-09-10 through 2026-09-25 show the winner can flip between
# sessions with no identified trigger, so there is no stable "priority
# order" to assert as fact -- this script reports today's live state
# instead of hardcoding an expectation.
#
# Usage:
#   bash omp/agent/scripts/check-anthropic-accounts.sh [MODEL] [SAMPLE_COUNT]
#
# MODEL defaults to anthropic/claude-sonnet-5. SAMPLE_COUNT (random session
# ids dry-run against `omp dry-balance`) defaults to 200. Never modifies
# agent.db or config -- `omp usage` and `omp dry-balance` are both read-only.
set -euo pipefail

MODEL="${1:-anthropic/claude-sonnet-5}"
SAMPLE_COUNT="${2:-200}"

# User's documented preference (AGENTS.md), not a guaranteed outcome.
PREFERRED_EMAIL="ton@servio.ph"

if ! command -v omp >/dev/null 2>&1; then
  echo "❌ 'omp' not found on PATH." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ 'python3' not found on PATH." >&2
  exit 1
fi

ERR_TMP="$(mktemp)"
trap 'rm -f "$ERR_TMP"' EXIT

echo "== Anthropic accounts logged into OMP =="
if ! USAGE_JSON="$(omp usage --provider anthropic --json 2>"$ERR_TMP")"; then
  echo "❌ 'omp usage --provider anthropic --json' failed:" >&2
  cat "$ERR_TMP" >&2
  exit 1
fi
echo "$USAGE_JSON" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"  (could not parse `omp usage` output: {e})")
    sys.exit(0)

reports = data.get("reports", [])
if not reports:
    print("  (no authenticated Anthropic accounts found)")
    sys.exit(0)

for r in reports:
    meta = r.get("metadata", {})
    email = meta.get("email", "<unknown>")
    org = meta.get("orgName", "")
    label = f"{email} ({org})" if org else email
    print(f"  * {label}")
    for limit in r.get("limits", []):
        window = limit.get("window", {}).get("label", limit.get("id", "?"))
        amount = limit.get("amount", {})
        used = amount.get("usedFraction")
        used_pct = f"{used * 100:.1f}%" if isinstance(used, (int, float)) else "?"
        print(f"      - {window}: {used_pct} used")
'

echo
echo "== Live credential-resolution priority (omp dry-balance, ${SAMPLE_COUNT} samples, ${MODEL}) =="
if ! DRY_BALANCE_JSON="$(omp dry-balance "$MODEL" --count "$SAMPLE_COUNT" --json 2>"$ERR_TMP")"; then
  echo "❌ 'omp dry-balance ${MODEL} --count ${SAMPLE_COUNT} --json' failed:" >&2
  cat "$ERR_TMP" >&2
  exit 1
fi

echo "$DRY_BALANCE_JSON" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"  (could not parse `omp dry-balance` output: {e})")
    sys.exit(0)

accounts = data.get("success", {}).get("accounts", [])
if not accounts:
    print("  (no successful credential resolutions -- is anyone logged in?)")
    sys.exit(0)

accounts = sorted(accounts, key=lambda a: a.get("count", 0), reverse=True)
for a in accounts:
    acct = a.get("account", "?")
    pct = a.get("percent", 0)
    cnt = a.get("count", 0)
    print(f"  * {acct}: {pct:.1f}% of sampled sessions ({cnt} samples)")
'

WINNING_ACCOUNT="$(echo "$DRY_BALANCE_JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    accounts = data.get("success", {}).get("accounts", [])
    print(max(accounts, key=lambda a: a.get("count", 0)).get("account", "") if accounts else "")
except Exception:
    print("")
')"

echo
echo "== Comparison to documented preference (AGENTS.md) =="
echo "  Preferred account: ${PREFERRED_EMAIL}"
if [ -z "$WINNING_ACCOUNT" ]; then
  echo "  ⚠️  Could not determine today's winning account (no successful samples)."
elif [[ "$WINNING_ACCOUNT" == "${PREFERRED_EMAIL}"* ]]; then
  echo "  ✅ ${PREFERRED_EMAIL} is winning account selection right now."
else
  echo "  ⚠️  Today's winner is ${WINNING_ACCOUNT}, not ${PREFERRED_EMAIL}."
  echo "      OMP has no account-priority config setting; this can flip between"
  echo "      sessions for reasons not yet identified (see AGENTS.md)."
  echo "      The only verified guaranteed fix: '/logout anthropic' then keep ONLY"
  echo "      ${PREFERRED_EMAIL} logged in -- not done by default, since the user"
  echo "      keeps the other account as an intentional quota-exhaustion fallback."
fi
