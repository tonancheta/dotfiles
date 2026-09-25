#!/usr/bin/env bash
# Makes python3.14 the default `python3`/`python` for interactive/dev use via
# update-alternatives, WITHOUT touching /usr/bin/python3 (the Ubuntu system
# symlink to python3.12 that apt/dpkg's python3-apt module is compiled
# against — repointing it breaks apt). Alternatives are installed under
# /usr/local/bin, which precedes /usr/bin in PATH, so PATH-based lookups
# (`python3`, `python`) resolve to 3.14 while any script with an absolute
# `#!/usr/bin/python3` shebang keeps using system 3.12 untouched.
#
# Idempotent: safe to re-run. Requires sudo (interactive password).
set -euxo pipefail

PY314=/usr/bin/python3.14
PY312=/usr/bin/python3.12

test -x "$PY314" || { echo "missing $PY314 — install python3.14 first" >&2; exit 1; }
test -x "$PY312" || { echo "missing $PY312" >&2; exit 1; }

for name in python3 python; do
  target="/usr/local/bin/$name"
  update-alternatives --install "$target" "$name" "$PY314" 100
  update-alternatives --install "$target" "$name" "$PY312" 50
  update-alternatives --set "$name" "$PY314"
done

hash -r || true

echo "--- verification ---"
update-alternatives --display python3
update-alternatives --display python
command -v python3
command -v python
python3 --version
python --version
