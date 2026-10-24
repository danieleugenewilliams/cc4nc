# The builder–reviewer loop

Two long-running sessions work this repository's backlog through pull requests. A
**builder** takes work from `gh issue list`, opens PRs, and places fixes that are handed
back. A **reviewer** reads each PR, fixes what it can, and hands back what it cannot.
GitHub labels are the state machine; one comment per PR is the record. This file is the
contract. `/builder-watch` and `/reviewer-watch` in `.claude/commands/` execute it and do
not restate it.

Repository: `{{REPO}}`. Base branch: `{{BASE_BRANCH}}`. Verification command: `{{TEST_CMD}}`.

## Roles

**The session name decides the role.** A session named some variation of `builder` is a
builder; one named some variation of `reviewer` is a reviewer. No session holds both — a
session that reviews its own work is not a second opinion.

## Labels

The three review-state labels live on the **PR**, not the issue. The issue is the backlog;
the PR is the unit of review. The one exception is a claimed label, if this loop has one: it
marks an **issue** a builder has taken before any PR exists, and comes off once the PR is
labelled. Every label below exists in the repo — confirmed with `gh label list` when this
file was generated. Never write a fourth into a prompt without creating it first.

| Label | Set by | Means |
|---|---|---|
| `{{LABEL_WAITING}}` | builder | This PR is waiting for a reviewer. |
| `{{LABEL_PASSED}}` | reviewer | Reviewed and clean. The only signal that authorises a merge. |
| `{{LABEL_CHANGES}}` | reviewer | Findings the reviewer could not place here. Back to the builder. |
{{CLAIMED_ROW}}

`{{LABEL_PASSED}}` and `{{LABEL_CHANGES}}` are mutually exclusive. A reviewer sets **at
most** one of them and removes `{{LABEL_WAITING}}` with whichever it sets. *At most*, not
*exactly*: a reviewer that cannot vouch for what the head now contains labels nothing, and
`{{LABEL_WAITING}}` stays on. Written as *exactly one* the rule reads as an instruction to
pick a label anyway, which is a pass over an unread diff.

Claims: {{CLAIMED_RULE}}

## State table

Every state has one way in and one way out. `W` = `{{LABEL_WAITING}}`, `P` =
`{{LABEL_PASSED}}`, `C` = `{{LABEL_CHANGES}}`.

| From | Event | Who | To |
|---|---|---|---|
| (no label) | PR opened | builder | W |
| W | review passes at the head the reviewer read | reviewer | P |
| W | review finds work only the builder can place | reviewer | C |
| W | head moved during the review | reviewer | W (labels nothing; comment says so) |
| C | fix placed and pushed | builder | W |
| P | base moved (`behind_by > 0`) | builder | W — swap **before** merging forward |
| P | head pushed after the pass | builder | W — a stale pass must not outlive the pass |
| P | checks below hold | {{MERGER}} | merged, **P stays on** |
| any | third hand-back | either | unchanged; comment once; notify |

A merged PR keeps `{{LABEL_PASSED}}`. It is the only durable evidence the merged work was
reviewed, which a revert cannot recover, and closed PRs sit in no queue — every query here
filters open PRs.

## The merge predicate

A PR may merge only when **all** of these hold, re-read at merge time, not from the watch's
last tick:

1. `{{LABEL_PASSED}}` is on.
2. `{{LABEL_CHANGES}}` is off.
3. `{{LABEL_WAITING}}` is off. *This clause is the one that gets left out.* With only 1
   and 2, push a commit and hand the PR back, and it carries both `{{LABEL_PASSED}}` and
   `{{LABEL_WAITING}}` at once — the predicate is still true and the unreviewed commit
   merges.
4. The head is the head the pass was taken at: the last `labeled {{LABEL_PASSED}}` event on
   the PR's timeline comes after the last commit, **and** the sha equals the one named on
   the first line of the reviewer's latest **LGTM** comment. Exact equality on both. The
   timeline orders a commit by the date it was *made*, not pushed, so the sha equality is
   the half that is exact.
5. The base is `{{BASE_BRANCH}}` and `behind_by` is 0 against it.

{{MERGER_SENTENCE}} A failed check is a refusal, never a merge on the label alone. A merge
GitHub refuses stops there and says so — no retry with different flags, no `--admin`, no
conflict resolution, never `git push origin HEAD:{{BASE_BRANCH}}`.

## Builder

Takes work from `gh issue list`, opens the PR against `{{BASE_BRANCH}}`, runs
`{{TEST_CMD}}`, labels it `{{LABEL_WAITING}}`. Never self-reviews, however obviously
correct the work looks. A PR handed back as `{{LABEL_CHANGES}}` gets the fix put where it
belongs — which may be a different PR if this repo stacks — then `{{LABEL_CHANGES}}` off
and `{{LABEL_WAITING}}` on, or the reviewer keeps polling a queue the work has dropped out
of. When a base lands, the builder swaps every child it staled: `{{LABEL_PASSED}}` off,
`{{LABEL_WAITING}}` on, *then* merge the base forward. Nobody else can see that happen —
the child left the reviewer's queue when its pass was set.

## Reviewer

Polls `gh pr list --label {{LABEL_WAITING}}`. Reviews, reproduces each finding before
believing it — *review findings are claims* — fixes what this PR introduced, verifies the
fix, runs `{{TEST_CMD}}`, and posts **one comment on that PR** with only that PR's findings
and what it changed. Then labels: `{{LABEL_PASSED}}` with **LGTM `<sha>`** on the first
line if nothing is outstanding; `{{LABEL_CHANGES}}` with the findings listed if something
is. **The LGTM names the head it vouches for** — the sha re-read just before labelling,
which is the reviewer's own fix commit if it pushed one. An LGTM naming no sha is a pass
nobody can act on.

The reviewer verifies its own fixes, and that is deliberate. The alternative is a fourth
state and a second round trip to bless a typo. Its repairs are covered by the *verify* it
already owes, and the comment naming them is on the PR before anything merges.

`{{LABEL_CHANGES}}` does not mean *the review failed*. It means *there is work here only
the builder can put in the right place*: a decision that is a person's, or a repair that
belongs in an earlier PR.

## Two sessions, one branch

A branch checks out once. The reviewer works in a **detached** worktree at the sha it
reviewed (`git worktree add --detach`), pushes with `git push origin HEAD:<branch>`, and
removes the worktree when its comment is posted. The builder fetches before touching a
branch it has handed off. Neither commits into the other's tree, and neither force-pushes:
the commit that would go is the other session's.

## The invariants the watch commands are built on

{{INVARIANTS}}

## What this loop does not give you

- **`allowed-tools` is pre-approval, not a deny.** A call outside the list prompts a
  person; under bypassed permissions it stops nothing. It removes the silent path.
- **Reviewing a PR runs the PR.** The reviewer checks the branch out into a worktree and
  runs `{{TEST_CMD}}` against it — which executes that branch's own test and build scripts,
  package-manager lifecycle hooks included — and the moment the worktree is trusted, any
  `.claude/` hook, `.mcp.json`, or `CLAUDE.md` the branch carries auto-runs too, under whatever
  permissions the session holds (bypassed, for an unattended loop). The diff is data to read
  **and** code that runs. Where every PR comes from your own builder, that is your own code;
  where a PR can come from anywhere, it is arbitrary code execution on the review host, and
  neither `allowed-tools` nor the session name stands in front of it. The repairs are
  launch-time, not edits: start the sessions with `--setting-sources user` so a branch's
  project config cannot auto-run — **that flag also drops this repo's `.claude/commands/`**
  (verified: `/reviewer-watch` resolves without it and not with it), so first copy the two
  watch commands into `~/.claude/commands/`. And if the builder itself takes untrusted input,
  gate the merge verb behind something the session cannot call (a human tap, a one-shot
  token) rather than the session name.
- **`git push origin HEAD:*` admits `HEAD:{{BASE_BRANCH}}`**, which lands everything and
  skips every check. No glob admits arbitrary runtime branch names while excluding the base
  branch. The two real repairs are decisions, not edits: drop the push glob and let every
  push prompt, or add a `PreToolUse` hook that refuses pushes to `{{BASE_BRANCH}}`. Branch
  protection on the remote is the third and the only one enforced off this machine.
- **The loop converges; it does not decide.** Nothing here can mechanise "this feature is
  good enough." A third hand-back is where a person comes in.
- **Merging is not deploying.** The last state here is *merged* — that lands code, it does
  not run it. A repo that executes its own merged code — a service, a bot, an agent that reads
  its own config — needs a separate activation step (pull the deployed tree, restart what the
  change touched), and "merged" reported as "live" is where this project's worst latent bug sat
  undeployed for hours. The loop stops at the merge on purpose; wiring merge→live — and knowing
  which changes go live on next read versus which need a restart — is yours.
