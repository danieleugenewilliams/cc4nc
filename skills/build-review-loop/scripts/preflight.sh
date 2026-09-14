#!/usr/bin/env bash
# Preflight for the builder-reviewer loop. Prints every check and a verdict.
# Usage: preflight.sh [repo-path]     (default: current directory)
# Exit codes: 0 ready, 2 needs-setup, 3 not-applicable, 4 toolchain missing.
# The verdict is advisory on one point: it DETECTS a test command but cannot
# know whether it passes. The caller must run it and see it pass.

set -u
repo="${1:-.}"
fail=0; setup=0; na=0
say() { printf '%-34s %s\n' "$1" "$2"; }

echo "== toolchain (on this machine) =="
if command -v gh >/dev/null 2>&1; then say "gh installed" "yes"; else say "gh installed" "NO"; fail=1; fi
if gh auth status >/dev/null 2>&1; then say "gh authenticated" "yes"; else say "gh authenticated" "NO"; fail=1; fi
if command -v jq >/dev/null 2>&1; then say "jq installed" "yes"; else say "jq installed" "NO (watch scripts need it)"; fail=1; fi
[ "$fail" -eq 1 ] && { echo; echo "VERDICT: toolchain missing — fix the lines marked NO, then rerun."; exit 4; }

echo; echo "== repository =="
if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
  say "git repository" "NO"; echo; echo "VERDICT: not applicable — a folder that is not a git repo does not get a review loop."; exit 3
fi
say "git repository" "yes"
if ! origin=$(git -C "$repo" remote get-url origin 2>/dev/null); then
  say "remote origin" "NO"; echo; echo "VERDICT: not applicable — no remote, so no pull requests and no labels."; exit 3
fi
say "remote origin" "$origin"
slug=$(cd "$repo" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || slug=""
if [ -z "$slug" ]; then say "gh can reach the repo" "NO"; setup=1; else say "gh can reach the repo" "$slug"; fi
default_branch=$(cd "$repo" && gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null) || default_branch="?"
say "default branch" "$default_branch"

echo; echo "== labels that exist (derive from these; never assume) =="
(cd "$repo" && gh label list --limit 100 --json name --jq '.[].name' 2>/dev/null | sed 's/^/  /') || echo "  (could not list)"

echo; echo "== backlog and PR history =="
open_issues=$(cd "$repo" && gh issue list --state open --limit 100 --json number --jq 'length' 2>/dev/null || echo "?")
say "open issues" "$open_issues"
# gh, not `git log --merges`: squash- and rebase-merged PRs leave no merge commit.
merged_prs=$(cd "$repo" && gh pr list --state merged --limit 100 --json number --jq 'length' 2>/dev/null || echo "?")
say "merged PRs (any merge method)" "$merged_prs"
if [ "$merged_prs" = "0" ] || [ "$merged_prs" = "?" ]; then
  echo "  -> no pull-request history: a reviewer has nowhere to stand until work goes through PRs."; setup=1
fi
if [ "$open_issues" = "0" ]; then echo "  -> no open issues: the builder has no backlog to take from."; fi

echo; echo "== test command (detected, NOT yet verified — run it) =="
test_cmd=""
if [ -f "$repo/package.json" ] && node -e "process.exit(require('$repo/package.json').scripts?.test?0:1)" 2>/dev/null; then
  test_cmd="npm test"
elif [ -f "$repo/go.mod" ] && find "$repo" -name '*_test.go' -not -path '*/vendor/*' | grep -q .; then
  test_cmd="go test ./..."
elif [ -f "$repo/pyproject.toml" ] || [ -f "$repo/pytest.ini" ] || [ -f "$repo/setup.cfg" ] || find "$repo" -maxdepth 3 -name 'test_*.py' | grep -q .; then
  test_cmd="python3 -m pytest   # or python3 -m unittest discover — verify which one finds the tests"
elif [ -f "$repo/Cargo.toml" ]; then
  test_cmd="cargo test"
fi
if [ -n "$test_cmd" ]; then
  say "detected" "$test_cmd"
  echo "  -> run it now. Detection is not evidence; only a passing run is."
else
  say "detected" "none"
  echo "  -> no test suite found. The loop needs A COMMAND THAT FAILS ON BROKEN CODE,"
  echo "     which need not be a suite: a syntax check, a build, booting the server and"
  echo "     hitting one route. Ask the person for one and verify it passes. If there is"
  echo "     nothing, the verdict is needs-setup."
  setup=1
fi

echo
if [ "$setup" -eq 1 ]; then echo "VERDICT: needs setup first — see the -> lines above."; exit 2; fi
echo "VERDICT: ready, pending a passing run of the test command."
exit 0
