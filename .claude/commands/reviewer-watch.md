---
allowed-tools: Bash(gh pr list*, gh pr view*, gh pr diff*, gh pr comment*, gh pr edit*, gh api repos/danieleugenewilliams/cc4nc/issues/*/timeline*, gh label*, git fetch*, git worktree*, git rev-parse*, git log*, git show*, git diff*, git status*, git add*, git commit*, git push origin HEAD:*, jq*, comm*, printf*, sort*, grep*, sleep*, date*, bash*), Monitor, TaskStop, Agent, PushNotification
description: Watch the reviewer queue and review each PR that enters it. Usage: /reviewer-watch [poll-seconds] [max-active]
---

# /reviewer-watch — hold the reviewer end of the loop

Arms a persistent watch over `gh pr list --label ready-for-review` on `danieleugenewilliams/cc4nc` and
reviews each PR that enters the queue. Read `docs/review-loop.md` first; this command
executes that contract and does not restate it.

Arguments: `$ARGUMENTS` → `[poll-seconds] [max-active]`. `poll-seconds` defaults to
`120`, minimum `60` — this is a remote API and the queue moves at human speed.
`max-active` defaults to `3` and is the fan-out cap. **Substitute both values into
the script before arming it.** A `$POLL` or `$ACTIVE` the script never receives is a
setting that silently does nothing.

## Arm the watch

Call `Monitor` with `persistent: true` and a description naming the queue, not the tool
("reviewer queue on danieleugenewilliams/cc4nc"). The command:

```bash
POLL=120
ACTIVE=3
R=danieleugenewilliams/cc4nc
prev=""
fails=0
while true; do
  if ! labels=$(gh label list --repo "$R" --limit 100 --json name --jq '.[].name' 2>/dev/null) \
     || ! printf '%s\n' "$labels" | grep -qx 'ready-for-review' \
     || ! queue=$(gh pr list --repo "$R" --label 'ready-for-review' --state open --limit 100 \
               --json number,headRefOid \
               --jq '.[] | "\(.number) \(.headRefOid[0:7])"' 2>/dev/null); then
    fails=$((fails+1))
    if [ "$fails" -eq 5 ]; then echo "watchdog reviewer 5 failed polls"; fi
    sleep "$POLL"; continue
  fi
  fails=0
  queue=$(printf '%s\n' "$queue" | grep . | sort -n)
  eligible=$(printf '%s\n' "$queue" | grep . | head -n "$ACTIVE")
  held=$(( $(printf '%s\n' "$queue" | grep -c .) - $(printf '%s\n' "$eligible" | grep -c .) ))
  cur=$(printf '%s\nheld %s\n' "$eligible" "$held" | grep . | sort)
  comm -13 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") | grep .
  prev="$cur"
  sleep "$POLL"
done
```

Every line is load-bearing. The contract's invariants say why; these are the ones that
map to a specific line here:

- **The tick starts by listing the repo's labels and checking its own is there.** `gh pr list
  --label X` goes through the search API, which answers `[]` with exit 0 for a repo that
  does not exist, a repo the token cannot see, *and a label that does not exist* — so a
  typo in the slug or the label is an empty queue forever and the watchdog never fires.
  `gh label list` exits 1 on an unreachable repo, and the `grep -qx` turns a missing
  label into a failed poll. Measured: `gh pr list --repo owner/no-such-repo --label bug`
  printed `[]` and exited 0.
  The same index lags a label change by a few seconds — observed: a PR labelled at creation
  was absent from the list, then present 5 s later. Invisible at a poll of minutes; do not
  "fix" a blank first read by polling faster.
- **The label is quoted.** Step 2 reuses labels the repo already has, and `help wanted`
  is one most repos have. Unquoted, `gh` reads `wanted` as a positional argument and
  exits 1 — a failed poll on every tick, so the watchdog fires once and the queue is
  silent forever. Measured: `gh pr list --label help wanted` printed `unknown argument
  "wanted"; please quote all values that have spaces`.
- **Keys on number _and_ head commit.** Number alone is silent when a PR already in the
  queue is pushed to — the second round.
- **A failed poll publishes nothing and leaves `prev` alone.** `2>/dev/null` alone turns an
  API error into an empty queue; `prev` is overwritten with nothing and the next good tick
  re-emits every PR as new. The `continue` prevents that.
- **`grep .` on the `comm` output.** `printf '%s\n' ""` writes a newline, so an emptying
  queue otherwise emits one blank event, and a blank event dispatches a review with no PR.
- **`sleep` on both paths.** A `continue` that skips it spins the API.
- **`--repo`, `--state open`, `--limit 100`.** Bare `gh pr list` resolves from `cwd` and
  exits 1 anywhere else; the default limit is 30 and says nothing about what it dropped.
- **Five consecutive failed polls emit one `watchdog` line**, reset on the first good poll.
- **Only the `$ACTIVE` lowest-numbered PRs are eligible on any tick.** The cap counts queue
  membership, not dispatches: a PR whose round is running still holds a slot. Do not "fix"
  it to release early — that bounds nothing. Numeric sort, because as text `100` precedes
  `99` and the base of a stack would queue behind its children.
- **Held, never dropped.** `prev` is built from the eligible set, so a PR held behind the
  cap emits normally the first tick a slot frees.
- **`held N` is always published, including `held 0`.** `comm -13` publishes additions, so
  a count falling to zero would otherwise say nothing and the last thing heard is the
  backlog at its worst.

The first tick emits the front of whatever is already labelled. That is intended: it picks
up a backlog left by the previous session.

## On each event

The event line is `<number> <sha>`, with one exception: **`held N` is not an event and is
never dispatched.** It fits the shape closely enough that nothing downstream would notice.
Show the count and drop the line.

**Hand the whole review to a subagent** and keep only the event line. The diff, the file
reads and the finding text never enter this session, which is what lets the watch run all
day.

**Before dispatching, check the claim.** Hold the set of PR numbers this session has a
round running on. If the event names one of them, **drop the line** — it is this round's
own fix push showing up as a fresh event. The window between pushing a fix and swapping the
label is minutes, against a poll measured in minutes, so this is the common path.

**When a round ends, release the claim and re-read the PR once:**

```bash
gh pr view <n> --repo danieleugenewilliams/cc4nc \
  --json headRefOid,labels --jq '"\(.headRefOid[0:7]) \(.labels|map(.name)|join(","))"'
```

Dispatch again only if `ready-for-review` is still on **and** the head differs from the one
that round recorded at step 5. On the normal path the round took the label off, so this
answers *nothing to do*. The path it exists for is step 7's refusal, where the label is
deliberately left on at a head nobody has read.

**A claim held past about half an hour is a round that did not come back.** Say so once by
`PushNotification`, naming the PR, and **do not** release it and dispatch again — nothing
can tell a dead subagent from a slow one. Restarting the watch clears every claim; that is
the release, and it is a person's call.

Give the subagent the PR number and nothing it could not read for itself. It must:

1. Check the hand-back count **before reviewing** (below). Stop if it is at the cap.
2. `git fetch origin` **first**, then create its own worktree, **detached**, under the
   scratchpad: `git worktree add --detach <dir> <sha>`. The fetch is not hygiene: the sha
   comes from the API and the watch fired *because* the builder just pushed it, so the
   local clone has never seen that object. Detached because a branch checks out once and
   the builder is very likely holding this one. Push with `git push origin HEAD:<branch>`,
   which needs no local branch and never touches the builder's tree.
3. Review the PR — `gh pr diff <n> --repo danieleugenewilliams/cc4nc` and the files it touches.
4. Reproduce each finding before believing it. *Review findings are claims.*
5. Fix what this PR introduced, verify the fix, and run `bash scripts/check.sh`. **Record the head
   it expects to see at step 7**: `git rev-parse HEAD | cut -c1-7` after its own push if it
   pushed, otherwise the sha from the event line. `cut`, not `--short=7`: `--short` is a
   *minimum* width and git widens it when seven characters are ambiguous locally, so it
   would compare eight characters against the `[0:7]` step 7 asks GitHub for and match
   nothing.

   A **rejected** push is step 7's condition arriving early: the builder pushed during the
   review. Never `--force` — the commit that would go is the builder's. Leave the push
   undone and take step 7's refusal.
6. Post **one comment on that PR** carrying only that PR's findings and what it changed.
7. **Re-read the head before labelling**, and label only if it matches the sha step 5
   recorded:

   ```bash
   gh pr view <n> --repo danieleugenewilliams/cc4nc --json headRefOid --jq '.headRefOid[0:7]'
   ```

   Compare against **step 5's recorded head, not the event line**. A review that found
   something fixed and pushed, so on that path the head has always moved, by the reviewer's
   own commit; comparing to the event line would refuse to label every review that did
   work.

   A head matching neither is someone else's push while the review ran. Say so in the
   comment, **leave `ready-for-review` on**, and label nothing. The next tick fires on the
   new sha because the loop keys on the sha.
8. Otherwise label exactly one of `ready-to-merge` (with **LGTM `<sha>`** on the first
   line of the comment, naming the head from step 7) or `needs-changes`, and remove
   `ready-for-review` either way.
9. **Remove its worktree** — `git worktree remove`. Not because it holds the branch: step 2
   detached precisely so it holds nothing. It is that the tree stays in the registry and on
   disk and nothing complains, so every round leaves one unless the round removes it.

## The hand-back cap

Three hand-backs on one PR and the loop stops on it. Count them from the PR itself, never
from session memory:

```bash
gh api repos/danieleugenewilliams/cc4nc/issues/<n>/timeline --paginate --slurp \
  | jq '[.[][] | select(.event=="labeled" and .label.name=="needs-changes")] | length'
```

The pagination is not optional. The timeline pages at 30 **ascending**, so an
un-paginated count drops the *most recent* events, and a PR handed back three times is
exactly the long-timeline PR whose later hand-backs fall past the cut. `--slurp` cannot be
combined with `--jq`, hence the pipe into standalone `jq`; `--slurp` yields an array of
pages, hence `.[][]`.

At 3 or more: do not review, do not label. Post a comment saying the PR has been handed
back three times and the loop has stopped on it, and send a `PushNotification`.

**Say it once.** A capped PR keeps `ready-for-review`, so it is still in the queue and the
first tick of every new session emits it again. Read the PR's comments first and stay
silent if the stopped-comment is already there. A notification that repeats every session
is one the person learns to ignore, and it is the only one in this loop that needs them.

## What the allowlist is for

`gh pr merge` is not in this command's `allowed-tools`, and the only `gh api` path
pre-approved is the timeline count — the REST merge route
(`gh api repos/danieleugenewilliams/cc4nc/pulls/<n>/merge -X PUT`) would otherwise merge a PR from a command
whose contract says the reviewer never merges. `allowed-tools` is **pre-approval, not a
deny**: a call outside it prompts a person, and under bypassed permissions it stops
nothing. What it removes is the silent path.

One route is still pre-approved: `git push origin HEAD:*` matches `HEAD:main`.
No glob admits runtime branch names while excluding the base branch. The contract names
this hole and the repairs; do not read this section as saying it is closed.

## Stopping

`TaskStop` on the monitor's task id. Say the watch is stopped — a stopped watch and an
empty queue look identical from the outside.
