#!/usr/bin/env bash
# Verification gate for this repo: fails on any Python or shell file that does not parse.
# There is no test suite here — the capstones are runnable demos — so the loop's
# "command that fails on broken code" is a syntax check over everything the repo ships.
# Note: server_broken.py, loop_demo_wrong.py and payments_buggy.py are *semantically*
# broken on purpose and must still parse; a future demo that is deliberately unparseable
# needs an exclusion added here.
set -u
cd "$(dirname "$0")/.."
fail=0

echo "== python: compileall capstones skills =="
PYTHONDONTWRITEBYTECODE=1 python3 -m compileall -q capstones skills || fail=1

echo "== shell: bash -n =="
while IFS= read -r f; do
  bash -n "$f" || { echo "FAIL $f"; fail=1; }
done < <(find capstones skills scripts -name '*.sh')

if [ "$fail" -ne 0 ]; then echo "CHECK FAILED"; exit 1; fi
echo "CHECK OK"
