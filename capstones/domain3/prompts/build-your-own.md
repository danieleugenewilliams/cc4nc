# Build Your Own: a self-hosted review gate

Paste this into Claude Code, in a repository you own, to stand up the same
gate on your own code. It is self-contained — you do not need the CC4NC repo.

---

I want a **self-hosted code-review gate** for this repository: a script that
runs Claude over a git diff, on my machine, and blocks a push when the diff
introduces a high-severity defect. No GitHub Actions, no managed service.

Build it for me, step by step, and explain each decision as a tradeoff I'm
making as the person who owns this pipeline:

1. **The reviewer script** (`scripts/ai-review.sh`):
   - Take a diff from `git diff HEAD`, a `--range A..B`, a `--diff file`, or stdin.
   - Call `claude -p --bare --output-format json --json-schema <schema>` so the
     reviewer runs in a *fresh* context that does NOT inherit this repo's
     `CLAUDE.md`, hooks, or MCP — an independent reviewer, not the author.
   - Use a JSON schema whose `severity` enum has strict definitions: reserve
     `high` for correctness/security defects that cause data loss, financial
     loss, a crash, or a security hole.
   - Parse the findings, print a readable report, and print the run's real
     `total_cost_usd` and latency.
   - Exit 1 if any finding is at/above a `REVIEW_FAIL_ON` threshold (default
     `high`), 0 if clean, 2 on an operational error.

2. **Credentials the safe way**: read `ANTHROPIC_API_KEY` from a gitignored
   `.env`, and add `.env` to `.gitignore`. Never write a key into a tracked file.

3. **An opt-in `pre-push` hook** that reviews the commit range being pushed and
   aborts on a block, with `git push --no-verify` as the escape hatch. Do NOT
   install it into `.git/hooks` automatically — show me the one command to
   symlink it when I'm ready.

4. **Prove it works, honestly**: plant an unambiguous high-severity change in a
   throwaway file (e.g. delete an authorization or bounds check), and show the
   gate blocking it **8 times in a row** — review is probabilistic, so one block
   proves nothing. Then show a behaviour-preserving refactor that the gate lets
   through, so I know it isn't just blocking everything.

Before you start, ask me anything you need about my repo, my test setup, and how
strict I want the gate. Then build it and run the proof.
