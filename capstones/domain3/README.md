# Domain 3 — The Self-Hosted Review Gate

Companion build for the CC4NC Architecture series, Domain 3 (Claude Code
Configuration & Workflows). It makes one argument concrete:

> **Judgment stays valuable when you stay the director — in the session, and in the pipeline.**

Most write-ups send you to a managed GitHub Action that runs on someone else's
infrastructure and meters you per run. This build shows the other path: a code
review gate that runs `claude` on a machine **you** own, gated on severity,
reporting its real cost — no GitHub Actions, no managed service.

It ties together three lessons:

| Lesson | Idea | Where it shows up here |
|---|---|---|
| **3.4** Plan vs. execute | You choose the altitude of engagement | You decide what the gate blocks on (`REVIEW_FAIL_ON`) |
| **3.5** Iterative refinement | You supply the *verification* | The gate is a runnable pass/fail check, not "looks done" |
| **3.6** CI/CD | Leave the loop on your terms | `claude -p --bare` in a hook you own, not a metered runner |

The connective tissue is **verification with fresh eyes**: in a session you give
Claude a check to run; in a pipeline you give it an *independent reviewer*. Same
principle, one altitude up.

## The independent-reviewer trick

The gate calls Claude with `--bare`, which skips this repo's hooks, plugins, MCP
servers, `CLAUDE.md`, and memory. The reviewer therefore does **not** inherit the
context that wrote the code — it can't be talked into approving a change by the
reasoning that produced it. That is Lesson 3.6's "the session that wrote the code
is worse at reviewing it," enforced structurally rather than by asking nicely.

## Layout

```
capstones/domain3/
├── reviewer/
│   ├── ai-review.sh        # the gate: diff → claude -p --bare → JSON → severity → exit code
│   ├── schema.json         # findings schema with strict severity definitions
│   └── .env.example        # credential pattern (copy to .env; gitignored)
├── demo_project/
│   ├── payments.py         # clean baseline
│   ├── payments_buggy.py   # drops all three transfer guards (the planted defect)
│   ├── payments_refactor.py# behaviour-preserving refactor (the control case)
│   └── changes/
│       ├── introduce-overdraft-bug.diff  # HIGH severity → gate must BLOCK
│       └── safe-refactor.diff            # clean → gate must PASS
├── hooks/pre-push          # opt-in git hook that runs the gate before a push
├── run-demo.sh             # drives both diffs + a stability loop
├── prompts/build-your-own.md          # paste-in prompt to build this gate in your own repo
└── verification/
    ├── REGRESSION.md                  # checklist A–J + results log
    └── health-agent-evidence.md       # real runs against the public health-fitness-agent repo
```

## The planted defect

`payments_buggy.py` removes three guards from `transfer()` at once:

1. **authorization** — anyone can move money out of an account they don't own,
2. **positive amount** — a negative amount reverses the transfer and drains the destination,
3. **balance** — the source overdrafts into a negative balance.

Any one of these is a high-severity, production-breaking defect. That is
deliberate: the gate fires on the model *classifying* the change as high
severity, and that decision needs to be stable run-to-run. An ambiguous "is this
really a bug?" change would make the gate flap. (Review is probabilistic — see
the stability note below.)

## Setup

```bash
cd capstones/domain3/reviewer
cp .env.example .env
# then either put ANTHROPIC_API_KEY in .env, or run `claude /login` once
```

Requirements: `claude` CLI (v2.1.205+ — earlier versions silently ignore `--json-schema`), `jq`, `bash`.

## Run it

```bash
# one pass over both diffs
./run-demo.sh

# prove the block is stable, not a lucky roll
STABILITY_RUNS=8 ./run-demo.sh

# review your own uncommitted work
./reviewer/ai-review.sh                 # git diff HEAD
./reviewer/ai-review.sh --range main..HEAD
```

Wire it into a repo you own as a real gate (run from that repo's root; the
hook follows the symlink back to this checkout to find the reviewer):

```bash
ln -s /path/to/cc4nc/capstones/domain3/hooks/pre-push .git/hooks/pre-push
# `git push` now runs the gate; `git push --no-verify` is the escape hatch
```

## Measured outcomes

<!-- MEASUREMENT: fill these from a real run on Daniel's machine before publishing.
     Do not quote sandbox numbers, and do not invent any (truth rule). -->

| Metric | Value |
|---|---|
| Bug diff blocked | `__ / __` stability runs |
| Safe refactor | PASS / FAIL (want PASS) |
| Cost per review | `$____` (API-key auth) |
| Latency per review | `__ s` |
| GitHub Actions minutes used | 0 |

## Honesty notes

- **Review is probabilistic.** A single block proves nothing; the stability loop
  is why. If the gate ever flaps on this diff, tighten `schema.json`'s severity
  definitions and the prompt in `ai-review.sh` before trusting it.
- The gate reviews the diff you give it; it does not run the code. Pair it with
  your existing test suite, don't replace it.
