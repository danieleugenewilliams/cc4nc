# Domain 3 — Regression Checklist

Run from `capstones/domain3/`. Requires auth (see `reviewer/.env.example`).

| # | Test | Command | Expected |
|---|------|---------|----------|
| A | Plumbing / no-auth failure is graceful | unset auth, then `./reviewer/ai-review.sh --diff demo_project/changes/introduce-overdraft-bug.diff` | exit 2, prints "Not logged in" guidance (no stack trace) |
| B | High-severity diff blocks | `./reviewer/ai-review.sh --diff demo_project/changes/introduce-overdraft-bug.diff` | ≥1 HIGH finding, prints BLOCKED, exit 1 |
| C | Block is stable | `STABILITY_RUNS=8 ./run-demo.sh` | bug diff blocks 8/8 |
| D | Safe refactor passes | `./reviewer/ai-review.sh --diff demo_project/changes/safe-refactor.diff` | 0 HIGH findings, PASSED, exit 0 |
| E | Empty diff passes | `printf '' \| ./reviewer/ai-review.sh -` | "nothing to review", exit 0 |
| F | Threshold override | `REVIEW_FAIL_ON=low ./reviewer/ai-review.sh --diff demo_project/changes/safe-refactor.diff` | blocks if any finding at all (demonstrates the knob) |
| G | Missing dependency is graceful | (temporarily hide `jq`) | exit 2 with "'jq' not found" |
| H | `.env` is not tracked | `git check-ignore capstones/domain3/reviewer/.env` | path is ignored |
| I | Cost/latency reported | any authed run | output shows a `cost:` and `latency:` line |
| J | Range mode works | `./reviewer/ai-review.sh --range HEAD~1..HEAD` on a repo with commits | reviews only that range |

## Results log

<!-- Record real results here after running on Daniel's machine. Date each run. -->

| Date | B (block) | C (stability) | D (refactor) | Cost/run | Latency | Notes |
|------|-----------|---------------|--------------|----------|---------|-------|
|      |           |               |              |          |         |       |
