#!/usr/bin/env bash
# Installs Docker (if missing) and starts the Hindsight memory server container
# for Oh My Pi's `memory.backend: hindsight` on this WSL2 Ubuntu 22.04 host.
#
# Run with:
#   sudo bash ~/.omp/agent/scripts/setup-hindsight-docker.sh > ~/.omp/agent/scripts/setup-hindsight-docker.log 2>&1
#
# Idempotent: safe to re-run. Installs docker.io via apt if `docker` is not on
# PATH, enables+starts the docker.service via systemd (WSL has systemd=true
# here), adds the invoking user to the `docker` group, then creates (or
# reuses) a `hindsight` container with --restart unless-stopped so it survives
# reboots without needing a supervisor script.
set -euxo pipefail

REAL_USER="${SUDO_USER:-$(logname)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# 1. Docker engine
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker.io
fi

systemctl enable --now docker

# 2. Let the real user run `docker` without sudo in future shells (takes
# effect on next login / new group-aware shell, not this script's shell).
if ! id -nG "$REAL_USER" | grep -qw docker; then
  usermod -aG docker "$REAL_USER"
fi

# 3. Resolve the Gemini API key: prefer it if already exported into this
# script's environment (e.g. `sudo -E`), otherwise pull it from the real
# user's ~/.bashrc where it's exported for interactive shells.
GEMINI_KEY="${GEMINI_API_KEY:-}"
if [ -z "$GEMINI_KEY" ] && [ -f "$REAL_HOME/.bashrc" ]; then
  GEMINI_KEY="$(grep -oP '(?<=^export GEMINI_API_KEY=).*' "$REAL_HOME/.bashrc" | tail -n1)"
fi
if [ -z "$GEMINI_KEY" ]; then
  echo "ERROR: GEMINI_API_KEY not found in environment or $REAL_HOME/.bashrc" >&2
  exit 1
fi

# 4. Start (or reuse) the Hindsight container.
if docker inspect hindsight >/dev/null 2>&1; then
  docker start hindsight >/dev/null 2>&1 || true
else
  docker run -d --pull always --name hindsight --restart unless-stopped \
    -p 8888:8888 -p 9999:9999 \
    -e HINDSIGHT_API_LLM_PROVIDER=gemini \
    -e HINDSIGHT_API_LLM_API_KEY="$GEMINI_KEY" \
    -e HINDSIGHT_API_WORKER_ID=hindsight \
    -v hindsight-data:/home/hindsight/.pg0 \
    ghcr.io/vectorize-io/hindsight:latest
fi

docker ps --filter name=hindsight
echo "Hindsight API:  http://localhost:8888"
echo "Hindsight UI:   http://localhost:9999"
echo "Done. Log out/in (or 'newgrp docker') for the docker-group membership to apply to your shell."
