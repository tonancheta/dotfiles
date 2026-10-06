#!/usr/bin/env bash
# Unlock ~/.ssh/sante.key into the dedicated ssh-agent-sante.service agent —
# the one herdr's managed ~/.ssh/config (manage_ssh_config=true) actually
# points IdentityAgent at for elev8-test/elev8-demo. Plain ssh-agent, no
# gpg-agent/pinentry involved (that path is a dead end — see gpg-agent
# pinentry incidents 2026-10-03/10-04).
#
# Needed again whenever ssh-agent-sante.service restarts (reboot, WSL
# restart, manual `systemctl --user restart`) — a bare ssh-agent has zero
# persistence of unlocked keys across its own process restarts; that's
# unavoidable for a passphrase-protected key, not a bug to chase further.
set -euo pipefail
export SSH_AUTH_SOCK="/run/user/1000/ssh-agent-sante.sock"

echo "Current identities before:"
ssh-add -l || true

ssh-add ~/.ssh/sante.key

echo
echo "Identities after:"
ssh-add -l

echo
echo "Testing elev8-test and elev8-demo (should succeed with no prompt):"
ssh -o BatchMode=yes -o ConnectTimeout=5 elev8-test exit && echo "elev8-test: OK"
ssh -o BatchMode=yes -o ConnectTimeout=5 elev8-demo exit && echo "elev8-demo: OK"
