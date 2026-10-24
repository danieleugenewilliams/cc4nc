#!/usr/bin/env bash
#
# run-demo.sh — drive the self-hosted review gate through two diffs and show
# the measured outcome of each:
#
#   1. introduce-overdraft-bug.diff  — HIGH severity → gate must BLOCK (exit 1)
#   2. safe-refactor.diff            — behaviour-preserving → gate must PASS (exit 0)
#
# Set STABILITY_RUNS=N to run the bug diff N times and confirm the gate
# decision is stable (review is probabilistic — one lucky block proves nothing).
#
#   ./run-demo.sh
#   STABILITY_RUNS=5 ./run-demo.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/reviewer/ai-review.sh"
CHANGES="$HERE/demo_project/changes"
STABILITY_RUNS="${STABILITY_RUNS:-1}"

pass=0; fail=0

run_case() {
  local label="$1" diff="$2" want="$3"   # want = block | pass
  echo; echo "### case: $label   (expect: $want)"
  "$GATE" --diff "$diff"
  local rc=$?
  local got="pass"; [[ $rc -eq 1 ]] && got="block"
  if [[ $rc -eq 2 ]]; then
    echo ">>> RESULT: operational error (rc=2) — check auth/deps above." ; fail=$((fail+1)); return
  fi
  if [[ "$got" == "$want" ]]; then
    echo ">>> RESULT: OK — gate returned '$got' as expected."; pass=$((pass+1))
  else
    echo ">>> RESULT: WRONG — wanted '$want', got '$got'."; fail=$((fail+1))
  fi
}

echo "=============================================="
echo "  CC4NC Domain 3 — self-hosted review gate demo"
echo "=============================================="

# Stability: the same high-severity diff, N times. Every run must BLOCK.
blocked=0
for i in $(seq 1 "$STABILITY_RUNS"); do
  echo; echo "### stability run $i/$STABILITY_RUNS  (bug diff, expect: block)"
  "$GATE" --diff "$CHANGES/introduce-overdraft-bug.diff"
  [[ $? -eq 1 ]] && blocked=$((blocked+1))
done
echo; echo ">>> stability: blocked $blocked / $STABILITY_RUNS runs (want $STABILITY_RUNS/$STABILITY_RUNS)"
[[ "$blocked" -eq "$STABILITY_RUNS" ]] && pass=$((pass+1)) || fail=$((fail+1))

# Control: a safe refactor must pass (guards against a trigger-happy gate).
run_case "safe refactor" "$CHANGES/safe-refactor.diff" "pass"

echo; echo "=============================================="
echo "  summary: $pass ok, $fail not-ok"
echo "=============================================="
[[ "$fail" -eq 0 ]]
