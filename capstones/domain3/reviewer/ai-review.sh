#!/usr/bin/env bash
#
# ai-review.sh — a self-hosted, fresh-context code-review gate.
#
# Runs a Claude review over a git diff with a SEPARATE, unattended Claude
# instance (--bare skips this repo's hooks/plugins/MCP/CLAUDE.md, so the
# reviewer never inherits the context that wrote the code — Lesson 3.6's
# "independent review instance"). Emits schema-constrained JSON, gates on
# severity, and reports the real cost + latency of the run.
#
# No GitHub Actions. No managed service. Runs on the box you own.
#
# Usage:
#   ./ai-review.sh                      # review `git diff HEAD` in $PWD
#   ./ai-review.sh --range main..HEAD   # review a commit range
#   ./ai-review.sh --diff path/to.diff  # review a diff file
#   cat some.diff | ./ai-review.sh -    # review a diff on stdin
#
# Exit codes:
#   0  gate passed  (no finding at or above $REVIEW_FAIL_ON)
#   1  gate blocked (a finding at or above $REVIEW_FAIL_ON)
#   2  operational error (no auth, no diff, missing dependency, bad model output)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$HERE/schema.json"

# Severity that trips the gate: high (default) | medium | low
REVIEW_FAIL_ON="${REVIEW_FAIL_ON:-high}"

# Run the reviewer in --bare mode (skip this repo's hooks/plugins/MCP/CLAUDE.md
# so it can't inherit the context that wrote the code). Default on; this is the
# Lesson 3.6 "independent reviewer" mechanism. Set REVIEW_BARE=0 only when your
# auth can't be read in bare mode (e.g. subscription/Keychain OAuth in some
# environments) — the reviewer is still a separate process with no shared
# session memory, but it WILL load the target repo's CLAUDE.md.
REVIEW_BARE="${REVIEW_BARE:-1}"
bare_flag="--bare"
[[ "$REVIEW_BARE" == "0" ]] && bare_flag=""

# --- Load credentials the Lesson 2.4 way: gitignored .env, never committed ----
# Look for .env next to the reviewer, then at the demo root.
for envfile in "$HERE/.env" "$HERE/../.env"; do
  if [[ -f "$envfile" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$envfile"; set +a
    break
  fi
done

# --- Dependency + auth preflight -------------------------------------------
command -v claude >/dev/null 2>&1 || { echo "error: 'claude' CLI not found on PATH" >&2; exit 2; }
command -v jq     >/dev/null 2>&1 || { echo "error: 'jq' not found on PATH"        >&2; exit 2; }

# --- Resolve the diff to review --------------------------------------------
mode="worktree"; arg="${1:-}"
diff=""
case "${arg}" in
  --range) diff="$(git diff "${2:?--range needs a revision range}")" ;;
  --diff)  diff="$(cat "${2:?--diff needs a file path}")" ;;
  -)       diff="$(cat -)" ;;
  "")      diff="$(git diff HEAD)" ;;
  *)       echo "error: unknown argument '$arg' (see header for usage)" >&2; exit 2 ;;
esac

if [[ -z "${diff//[$'\t\r\n ']/}" ]]; then
  echo "gate: nothing to review (empty diff) — passing." >&2
  exit 0
fi

# --- Build the review prompt -----------------------------------------------
# Prompt is deliberately explicit about the job and the severity contract so
# the gate decision is stable run-to-run (Lesson 3.5: precise instructions +
# examples beat vague ones). Severity definitions live in the schema.
read -r -d '' PROMPT <<'EOF' || true
You are a code reviewer acting as an independent gate in a pre-push hook.
Review ONLY the unified diff below. Report every distinct defect the diff
introduces. Judge severity strictly by the definitions in the output schema:
reserve "high" for correctness or security defects that can cause data loss,
financial loss, a crash, or a security hole in production. Do not invent
issues to look thorough; an empty findings array is the correct answer for a
clean diff. Output must match the provided JSON schema exactly — no prose.

--- DIFF START ---
EOF
PROMPT="$PROMPT
$diff
--- DIFF END ---"

# --- Run the independent reviewer ------------------------------------------
started="$(date +%s)"
raw="$(printf '%s' "$PROMPT" | claude -p $bare_flag \
        --output-format json \
        --json-schema "$(cat "$SCHEMA_FILE")" 2>&1)" || true
ended="$(date +%s)"

# Envelope sanity
if ! printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
  echo "error: reviewer did not return JSON. Raw output:" >&2
  printf '%s\n' "$raw" | head -c 800 >&2; echo >&2
  exit 2
fi

is_error="$(printf '%s' "$raw" | jq -r '.is_error // false')"
result_str="$(printf '%s' "$raw" | jq -r '.result // empty')"
cost="$(printf '%s' "$raw" | jq -r '.total_cost_usd // 0')"
dur_ms="$(printf '%s' "$raw" | jq -r '.duration_ms // 0')"

if [[ "$is_error" == "true" || -z "$result_str" ]]; then
  echo "error: reviewer call failed: ${result_str:-unknown error}" >&2
  echo "       (if this says 'Not logged in', add ANTHROPIC_API_KEY to reviewer/.env" >&2
  echo "        or run 'claude /login' — see .env.example)" >&2
  exit 2
fi

# The schema-constrained answer is a JSON string inside .result
if ! findings="$(printf '%s' "$result_str" | jq -c '.findings' 2>/dev/null)" || [[ "$findings" == "null" ]]; then
  echo "error: could not parse findings from model output:" >&2
  printf '%s\n' "$result_str" | head -c 800 >&2; echo >&2
  exit 2
fi

# --- Report -----------------------------------------------------------------
n_high="$(printf '%s' "$findings"   | jq '[.[]|select(.severity=="high")]   | length')"
n_medium="$(printf '%s' "$findings" | jq '[.[]|select(.severity=="medium")] | length')"
n_low="$(printf '%s' "$findings"    | jq '[.[]|select(.severity=="low")]    | length')"
n_total="$(printf '%s' "$findings"  | jq 'length')"

echo "──────────────────────────────────────────────"
echo "  self-hosted review gate"
echo "──────────────────────────────────────────────"
if [[ "$n_total" -eq 0 ]]; then
  echo "  findings: none"
else
  printf '%s' "$findings" | jq -r '.[] |
    "  [\(.severity|ascii_upcase)] \(.file // "?"):\(.line // 0)\n      \(.issue)\n      → \(.recommendation)"'
fi
echo "──────────────────────────────────────────────"
echo "  high:$n_high  medium:$n_medium  low:$n_low   (total:$n_total)"
printf '  cost: $%s   latency: %ss   gate: fail-on=%s\n' "$cost" "$((ended-started))" "$REVIEW_FAIL_ON"
echo "──────────────────────────────────────────────"

# --- Gate decision ----------------------------------------------------------
block=0
case "$REVIEW_FAIL_ON" in
  high)   [[ "$n_high" -gt 0 ]] && block=1 ;;
  medium) { [[ "$n_high" -gt 0 ]] || [[ "$n_medium" -gt 0 ]]; } && block=1 ;;
  low)    [[ "$n_total" -gt 0 ]] && block=1 ;;
  *) echo "error: REVIEW_FAIL_ON must be high|medium|low (got '$REVIEW_FAIL_ON')" >&2; exit 2 ;;
esac

if [[ "$block" -eq 1 ]]; then
  echo "  ✗ BLOCKED — fix the finding(s) above, or override with REVIEW_FAIL_ON." >&2
  exit 1
fi
echo "  ✓ PASSED"
exit 0
