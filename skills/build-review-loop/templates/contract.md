# The builder–reviewer loop

Two long-running sessions work this repository's backlog through pull requests. A
**builder** takes work from `gh issue list`, opens PRs, and places fixes that are handed
back. A **reviewer** {{REVIEWER_SUMMARY}}
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
the PR is the unit of review.{{LABELS_INTRO_EXTRA}} Every label below exists in the repo —
confirmed with `gh label list` when this file was generated. Never write another into a
prompt without creating it first.

| Label | Set by | Means |
|---|---|---|
| `{{LABEL_WAITING}}` | builder | This PR is waiting for a reviewer. |
| `{{LABEL_PASSED}}` | reviewer | Reviewed and clean. The only signal that authorises a merge. |
| `{{LABEL_CHANGES}}` | reviewer | {{CHANGES_MEANING}} |{{CLAIMED_ROW}}{{BLOCKED_ROW}}

`{{LABEL_PASSED}}` and `{{LABEL_CHANGES}}` are mutually exclusive. A reviewer sets **at
most** one of them and removes `{{LABEL_WAITING}}` with whichever it sets. *At most*, not
*exactly*: a reviewer that cannot vouch for what the head now contains labels nothing, and
`{{LABEL_WAITING}}` stays on. Written as *exactly one* the rule reads as an instruction to
pick a label anyway, which is a pass over an unread diff.

Claims: {{CLAIMED_RULE}}

{{BLOCKED_RULE}}

## State table

Every state has one way in and one way out. `W` = `{{LABEL_WAITING}}`, `P` =
`{{LABEL_PASSED}}`, `C` = `{{LABEL_CHANGES}}`.

| From | Event | Who | To |
|---|---|---|---|
| (no label) | PR opened | builder | W |
| W | review passes at the head the reviewer read | reviewer | P |
| W | {{CHANGES_TRANSITION}} | reviewer | C (and P off, if an earlier round left it) |
| W | head moved during the review | reviewer | W (labels nothing; comment says so) |
| C | fix placed and pushed | builder | W |
| P | base moved (`behind_by > 0`) | builder | W — swap **before** merging forward |
| P | head pushed after the pass | builder | W — a stale pass must not outlive the pass |
| P | checks below hold | {{MERGER}} | merged, **P stays on** |
| any | third hand-back | either | unchanged; comment once; notify |{{BLOCKED_TABLE_ROWS}}

A merged PR keeps `{{LABEL_PASSED}}`. It is the only durable evidence the merged work was
reviewed, which a revert cannot recover, and closed PRs sit in no queue — every query here
filters open PRs.

## The merge predicate

A PR may merge only when **all** of these hold, re-read at merge time, not from the watch's
last tick:

1. **`{{LABEL_PASSED}}` is the only flow label on the PR.** The flow labels are
   {{FLOW_LABELS}}; anything else (`bug`, a tracker tag) is a category and does not count.{{BLOCKED_ISSUE_CLAUSE}}

   This is stated as the one permitted state, not as a list of labels that must be absent,
   on purpose. An exclusion list has to be revisited every time a label is added, and when
   it is not, the merge condition silently widens. The two-clause version — passed on,
   changes off — already let an unreviewed commit through: push a commit and hand the PR
   back, and it carries both `{{LABEL_PASSED}}` and `{{LABEL_WAITING}}` at once. The fix
   for that, written as a third exclusion, then forgot the claimed and blocked labels the
   moment they were added. Naming the permitted state cannot fail that way.
2. The head is the head the pass was taken at: the last `labeled {{LABEL_PASSED}}` event on
   the PR's timeline comes after the last commit, **and** the sha equals the one named on
   the first line of the reviewer's latest **LGTM** comment. Exact equality on both. The
   timeline orders a commit by the date it was *made*, not pushed, so the sha equality is
   the half that is exact.
3. The base is `{{BASE_BRANCH}}` and `behind_by` is 0 against it.

{{MERGER_SENTENCE}} A failed check is a refusal, never a merge on the label alone. A merge
GitHub refuses stops there and says so — no retry with different flags, no `--admin`, no
conflict resolution, never `git push origin HEAD:{{BASE_BRANCH}}`.

## Builder

Takes work from `gh issue list`{{NEW_WORK_SCOPE_SHORT}}, opens the PR against `{{BASE_BRANCH}}`, runs
`{{TEST_CMD}}`, labels it `{{LABEL_WAITING}}`. Never self-reviews, however obviously
correct the work looks. A PR handed back as `{{LABEL_CHANGES}}` gets the fix put where it
belongs — which may be a different PR if this repo stacks — then `{{LABEL_CHANGES}}` off
and `{{LABEL_WAITING}}` on, or the reviewer keeps polling a queue the work has dropped out
of. When a base lands, the builder swaps every child it staled: `{{LABEL_PASSED}}` off,
`{{LABEL_WAITING}}` on, *then* merge the base forward. Nobody else can see that happen —
the child left the reviewer's queue when its pass was set.

## Reviewer

{{REVIEWER_CONTRACT_SECTION}}

## Two sessions, one branch

{{TWO_SESSIONS}}

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
