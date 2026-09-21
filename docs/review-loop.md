# The builder–reviewer loop

Two long-running sessions work this repository's backlog through pull requests. A
**builder** takes work from `gh issue list`, opens PRs, and places fixes that are handed
back. A **reviewer** reads each PR, fixes what it can, and hands back what it cannot.
GitHub labels are the state machine; one comment per PR is the record. This file is the
contract. `/builder-watch` and `/reviewer-watch` in `.claude/commands/` execute it and do
not restate it.

Repository: `danieleugenewilliams/cc4nc`. Base branch: `main`. Verification command: `bash scripts/check.sh`.

## Roles

**The session name decides the role.** A session named some variation of `builder` is a
builder; one named some variation of `reviewer` is a reviewer. No session holds both — a
session that reviews its own work is not a second opinion.

## Labels

Labels live on the **PR**, not the issue. The issue is the backlog; the PR is the unit of
review. Every label below exists in the repo — confirmed with `gh label list` when this
file was generated. Never write a fourth into a prompt without creating it first.

| Label | Set by | Means |
|---|---|---|
| `ready-for-review` | builder | This PR is waiting for a reviewer. |
| `ready-to-merge` | reviewer | Reviewed and clean. The only signal that authorises a merge. |
| `needs-changes` | reviewer | Findings the reviewer could not place here. Back to the builder. |
| `in-progress` | builder | A builder has taken this item and not yet opened its PR. Durable because builders run in parallel and one session's memory is invisible to another. |

`ready-to-merge` and `needs-changes` are mutually exclusive. A reviewer sets **at
most** one of them and removes `ready-for-review` with whichever it sets. *At most*, not
*exactly*: a reviewer that cannot vouch for what the head now contains labels nothing, and
`ready-for-review` stays on. Written as *exactly one* the rule reads as an instruction to
pick a label anyway, which is a pass over an unread diff.

Claims: Before starting an item, label it `in-progress`; an item already carrying it belongs to someone else. Remove it when the PR is labelled `ready-for-review`.

## State table

Every state has one way in and one way out. `W` = `ready-for-review`, `P` =
`ready-to-merge`, `C` = `needs-changes`.

| From | Event | Who | To |
|---|---|---|---|
| (no label) | PR opened | builder | W |
| W | review passes at the head the reviewer read | reviewer | P |
| W | review finds work only the builder can place | reviewer | C |
| W | head moved during the review | reviewer | W (labels nothing; comment says so) |
| C | fix placed and pushed | builder | W |
| P | base moved (`behind_by > 0`) | builder | W — swap **before** merging forward |
| P | head pushed after the pass | builder | W — a stale pass must not outlive the pass |
| P | checks below hold | builder | merged, **P stays on** |
| any | third hand-back | either | unchanged; comment once; notify |

A merged PR keeps `ready-to-merge`. It is the only durable evidence the merged work was
reviewed, which a revert cannot recover, and closed PRs sit in no queue — every query here
filters open PRs.

## The merge predicate

A PR may merge only when **all** of these hold, re-read at merge time, not from the watch's
last tick:

1. `ready-to-merge` is on.
2. `needs-changes` is off.
3. `ready-for-review` is off. *This clause is the one that gets left out.* With only 1
   and 2, push a commit and hand the PR back, and it carries both `ready-to-merge` and
   `ready-for-review` at once — the predicate is still true and the unreviewed commit
   merges.
4. The head is the head the pass was taken at: the last `labeled ready-to-merge` event on
   the PR's timeline comes after the last commit, **and** the sha equals the one named on
   the first line of the reviewer's latest **LGTM** comment. Exact equality on both. The
   timeline orders a commit by the date it was *made*, not pushed, so the sha equality is
   the half that is exact.
5. The base is `main` and `behind_by` is 0 against it.

The **builder** merges, on `mergeable` and only after the checks below. A failed check is a refusal, never a merge on the label alone. A merge
GitHub refuses stops there and says so — no retry with different flags, no `--admin`, no
conflict resolution, never `git push origin HEAD:main`.

## Builder

Takes work from `gh issue list`, opens the PR against `main`, runs
`bash scripts/check.sh`, labels it `ready-for-review`. Never self-reviews, however obviously
correct the work looks. A PR handed back as `needs-changes` gets the fix put where it
belongs — which may be a different PR if this repo stacks — then `needs-changes` off
and `ready-for-review` on, or the reviewer keeps polling a queue the work has dropped out
of. When a base lands, the builder swaps every child it staled: `ready-to-merge` off,
`ready-for-review` on, *then* merge the base forward. Nobody else can see that happen —
the child left the reviewer's queue when its pass was set.

## Reviewer

Polls `gh pr list --label ready-for-review`. Reviews, reproduces each finding before
believing it — *review findings are claims* — fixes what this PR introduced, verifies the
fix, runs `bash scripts/check.sh`, and posts **one comment on that PR** with only that PR's findings
and what it changed. Then labels: `ready-to-merge` with **LGTM `<sha>`** on the first
line if nothing is outstanding; `needs-changes` with the findings listed if something
is. **The LGTM names the head it vouches for** — the sha re-read just before labelling,
which is the reviewer's own fix commit if it pushed one. An LGTM naming no sha is a pass
nobody can act on.

The reviewer verifies its own fixes, and that is deliberate. The alternative is a fourth
state and a second round trip to bless a typo. Its repairs are covered by the *verify* it
already owes, and the comment naming them is on the PR before anything merges.

`needs-changes` does not mean *the review failed*. It means *there is work here only
the builder can put in the right place*: a decision that is a person's, or a repair that
belongs in an earlier PR.

## Two sessions, one branch

A branch checks out once. The reviewer works in a **detached** worktree at the sha it
reviewed (`git worktree add --detach`), pushes with `git push origin HEAD:<branch>`, and
removes the worktree when its comment is posted. The builder fetches before touching a
branch it has handed off. Neither commits into the other's tree, and neither force-pushes:
the commit that would go is the other session's.

## The invariants the watch commands are built on

Every rule below exists because a naive version broke in a real repo, and each ships with
its reason on purpose: a rule whose reason is missing gets optimised away by the next agent
that reads it. *An agent that reads a reason it can see is false skips the step.*

1. **The session name decides the role, and no session holds both.** A session that
   reviews its own work is not a second opinion.
2. **Key the watch on the item number *and* the head commit.** Number alone is silent when
   something already in the queue is pushed to — which is the second round, every time.
3. **A failed poll publishes nothing and leaves the previous state alone.** Swallowing an
   API error into an empty result overwrites the state with nothing, and the next good tick
   re-emits the whole queue as new work: a second review, a second comment, a second label
   swap on work already done.
4. **Sleep on every path, including the error path.** A `continue` that skips the sleep
   spins the API.
5. **Name the repo in every call.** A bare `gh pr list` resolves from the working directory
   and exits 1 anywhere else, which rule 3 then turns into a tick skipped forever.
6. **Bound every list explicitly.** `gh pr list` defaults to 30 and says nothing about what
   it dropped. A queue of 31 reviews 30 and leaves one invisible for as long as the queue
   stays full.
7. **Break the silence when polls keep failing.** Publishing nothing on a failure is right;
   doing it forever is not. Count consecutive failures, emit once at five, reset on the
   first good poll. Silence and an empty queue are the same picture.
8. **Ask state questions, never history.** "Which open items are behind their base"
   survives a restart and has no replay. "Which merged recently" re-emits everything on
   every arm — one repo replayed nine landed PRs every time the watch started.
9. **Cap on queue membership, loop-wide — never per item.** A per-item cap does not bound
   a loop: one repo's spiral was nine separate pull requests, each resetting the counter.
   A repo that stacks PRs is worse exposed, because one merge stales every child and each
   re-enters the queue.
10. **Hold the cap's slot for the whole round.** Freeing it when a round starts bounds
    nothing.
11. **Publish the held count every tick, including zero.** A diff-based emitter only
    publishes additions, so a count falling to zero says nothing and the last thing anyone
    heard is the backlog at its worst.
12. **Read the hand-back count off the item's own timeline, paginated, never from session
    memory.** The GitHub timeline pages at 30 ascending, so an un-paginated count drops the
    *most recent* events — and an item handed back three times is exactly the one long
    enough to lose them. Measured on one PR: 2 events un-paginated, 5 across all pages. A
    cap that reads 2 when the truth is 5 says *fine* when it means *I could not tell*.
13. **A round claims the item it is working on.** The window between pushing a fix and
    swapping the label is minutes, against a poll measured in minutes, so a second round on
    a live round is the common path rather than an edge.
14. **A round must be resumable from the item alone.** Labels are the state, one comment
    per item is the record. Test it by clearing context mid-queue and seeing whether the
    next round proceeds.
15. **Hand every round to a subagent and keep only the event line.** The diff, the file
    reads and the finding text never enter the watching session, which is what lets the
    watch run all day. This is the whole token argument.
16. **One detached worktree per round, removed when the round ends.** Detached because a
    branch checks out once and the other session is probably holding it. Removed because
    nothing complains if you don't — thirteen abandoned trees accumulated in one repo
    before anyone looked.
17. **Re-read the head before labelling, and compare against the head this round recorded,
    not the one the event carried.** A review that fixed something has already moved the
    head with its own commit.
18. **Never force-push past a rejection.** The commit that would go is the other session's.
19. **Stop after three hand-backs, say so once, and notify.** Two agents can pass work back
    and forth forever. Once, because the item stays in the queue and every new session
    re-emits it, and a notification that repeats is one the person learns to ignore.
20. **Say when the watch stops.** A stopped watch and an empty queue look identical.

## What this loop does not give you

- **`allowed-tools` is pre-approval, not a deny.** A call outside the list prompts a
  person; under bypassed permissions it stops nothing. It removes the silent path.
- **Reviewing a PR runs the PR.** The reviewer checks the branch out into a worktree and
  runs `bash scripts/check.sh` against it — which executes that branch's own test and build scripts,
  package-manager lifecycle hooks included — and the moment the worktree is trusted, any
  `.claude/` hook, `.mcp.json`, or `CLAUDE.md` the branch carries auto-runs too, under whatever
  permissions the session holds (bypassed, for an unattended loop). The diff is data to read
  **and** code that runs. Where every PR comes from your own builder, that is your own code;
  where a PR can come from anywhere, it is arbitrary code execution on the review host, and
  neither `allowed-tools` nor the session name stands in front of it. The repairs are
  launch-time, not edits: start the sessions with `--setting-sources user` so a branch's
  project config cannot auto-run, and — if the builder itself takes untrusted input — gate the
  merge verb behind something the session cannot call (a human tap, a one-shot token) rather
  than the session name.
- **`git push origin HEAD:*` admits `HEAD:main`**, which lands everything and
  skips every check. No glob admits arbitrary runtime branch names while excluding the base
  branch. The two real repairs are decisions, not edits: drop the push glob and let every
  push prompt, or add a `PreToolUse` hook that refuses pushes to `main`. Branch
  protection on the remote is the third and the only one enforced off this machine.
- **The loop converges; it does not decide.** Nothing here can mechanise "this feature is
  good enough." A third hand-back is where a person comes in.
- **Merging is not deploying.** The last state here is *merged* — that lands code, it does
  not run it. A repo that executes its own merged code — a service, a bot, an agent that reads
  its own config — needs a separate activation step (pull the deployed tree, restart what the
  change touched), and "merged" reported as "live" is where this project's worst latent bug sat
  undeployed for hours. The loop stops at the merge on purpose; wiring merge→live — and knowing
  which changes go live on next read versus which need a restart — is yours.
