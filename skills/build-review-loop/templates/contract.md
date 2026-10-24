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

Labels live on the **PR**, not the issue. The issue is the backlog; the PR is the unit of
review. Every label below exists in the repo — confirmed with `gh label list` when this
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

- **The `allowed-tools` lines in the two watch commands pre-approve nothing.** They use
  the comma-inside form, `Bash(gh pr list*, gh pr view*, …)`, and that form matches no
  command at all. The loop runs because its sessions run in auto mode and **the auto-mode
  classifier passes the commands**; in default mode every call prompts a person. Do not
  rewrite the lines into one `Bash()` per rule to make them match: that would create the
  `gh pr merge*` and `git merge*` pre-approvals the prose has only been assuming. They are
  left as they are on purpose.
- **`git push origin HEAD:*` matches nothing either.** `:*` is the trailing-wildcard
  spelling, so the entry reads `git push origin HEAD *` — neither `HEAD:{{BASE_BRANCH}}` nor
  the branch pushes it was put there to allow. What keeps a session off `{{BASE_BRANCH}}` is
  the deny rules below.
- **The loop converges; it does not decide.** Nothing here can mechanise "this feature is
  good enough." A third hand-back is where a person comes in.

## Keeping sessions off `{{BASE_BRANCH}}`: deny rules

The control is four `deny` rules in `.claude/settings.json`, because **deny outranks allow
in every mode and scope**:

```
Bash(git push * {{BASE_BRANCH}})
Bash(git push * {{BASE_BRANCH}} *)
Bash(git push *:{{BASE_BRANCH}})
Bash(git push *:{{BASE_BRANCH}} *)
```

Four because a refspec names `{{BASE_BRANCH}}` either bare or right of a colon, and either
can carry a trailing flag. Two shapes times two positions.

They sit **beside** any `Bash(git push --force-with-lease *)` allow rather than replacing
it. That allow is what lets a session rewind its own branch under a lease; removing it
reopens a different problem, and the deny covers the `{{BASE_BRANCH}}` case the allow would
otherwise reach.

Three spellings escape, recorded rather than chased: `git -C . push`, and
`refs/heads/{{BASE_BRANCH}}` on either side of the refspec. Each has the standing every push
had before: a prompt in default mode, the classifier in auto mode.

Verify them with `scripts/check-deny.sh` from the build-review-loop skill, run from the repo
root. It hands each spelling to a fresh `claude -p --permission-mode default`, reads the
deny rules off this repo's real settings file with `jq`, loads a wide `Bash(git push *)`
allow on purpose (or a deny and a no-match look the same), and puts an echo-only `git` first
on `PATH` so nothing contacts a remote. A row the session did not run verbatim is a FAIL,
not a pass, and the script refuses unless it reports on every row.

**Branch protection on the remote is the cleaner fix**, and the only one enforced off this
machine; on a paid plan or a public repo, reach for it first. It was unavailable on the plan
these rules were proven on: 403, "Upgrade to GitHub Pro or make this repository public." A
`PreToolUse` hook that refuses pushes to `{{BASE_BRANCH}}` is a further option.
