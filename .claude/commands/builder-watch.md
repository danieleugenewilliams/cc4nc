---
allowed-tools: Bash(gh pr list*, gh pr view*, gh pr diff*, gh pr comment*, gh pr edit*, gh pr merge*, gh issue list*, gh issue view*, gh api repos/danieleugenewilliams/cc4nc/issues/*/timeline*, gh api repos/danieleugenewilliams/cc4nc/compare/*, gh label*, git fetch*, git merge*, git rev-parse*, git log*, git show*, git diff*, git status*, git add*, git commit*, git push origin HEAD:*, jq*, comm*, printf*, sort*, grep*, sleep*, date*, bash scripts/check.sh*), Monitor, TaskStop, Agent, PushNotification
description: Watch the builder queue — place handed-back fixes, re-queue PRs whose base has moved, and act on what is mergeable after the checks. Usage: /builder-watch [poll-seconds] [max-active]
---

# /builder-watch — hold the builder end of the loop

Arms a persistent watch over the things the builder owes an answer to on `danieleugenewilliams/cc4nc`. Read
`docs/review-loop.md` first; this command executes that contract and does not restate it.

Arguments: `$ARGUMENTS` → `[poll-seconds] [max-active]`, defaulting to `120` (minimum
`60`) and `3`. **Substitute both into the script before arming it** — a `$POLL` or
`$ACTIVE` the script never receives is a setting that silently does nothing.

## Arm the watch

One `Monitor`, `persistent: true`, described as "builder queue on danieleugenewilliams/cc4nc". It emits a
tagged line for three events, because all three need the builder and none needs a second
poll loop:

```bash
POLL=120
ACTIVE=3
R=danieleugenewilliams/cc4nc
prev=""
fails=0
while true; do
  ok=1
  labels=$(gh label list --repo "$R" --limit 100 --json name --jq '.[].name' 2>/dev/null) || ok=0
  for want in 'needs-changes' 'ready-to-merge' 'ready-for-review'; do
    printf '%s\n' "$labels" | grep -qx "$want" || ok=0
  done
  handback=$(gh pr list --repo "$R" --label 'needs-changes' --state open --limit 100 \
             --json number,headRefOid \
             --jq '.[] | "handback \(.number) \(.headRefOid[0:7])"' 2>/dev/null) || ok=0
  passed=$(gh pr list --repo "$R" --label 'ready-to-merge' --state open --limit 100 \
           --json number,baseRefName,headRefName,headRefOid \
           --jq '.[] | "\(.number)\t\(.baseRefName)\t\(.headRefName)\t\(.headRefOid[0:7])"' \
           2>/dev/null) || ok=0
  routed=""
  notes=""
  while IFS=$'\t' read -r n b h sha; do
    [ -n "$n" ] || continue
    behind=$(gh api "repos/$R/compare/$b...$h" --jq '.behind_by' 2>/dev/null) || { ok=0; break; }
    case "$behind" in ''|*[!0-9]*) ok=0; break;; esac
    if [ "$behind" -gt 0 ]; then
      routed="${routed}stale $n $behind"$'\n'
    else
      notes="${notes}mergeable $n $sha"$'\n'
    fi
  done <<< "$passed"
  if [ "$ok" -eq 0 ]; then
    fails=$((fails+1))
    if [ "$fails" -eq 5 ]; then echo "watchdog builder 5 failed polls"; fi
    sleep "$POLL"; continue
  fi
  fails=0
  work=$(printf '%s\n%s\n' "$handback" "$routed" | grep . | sort -k2,2n)
  eligible=$(printf '%s\n' "$work" | grep . | head -n "$ACTIVE")
  held=$(( $(printf '%s\n' "$work" | grep -c .) - $(printf '%s\n' "$eligible" | grep -c .) ))
  cur=$(printf '%s\n%s\nheld %s\n' "$eligible" "$notes" "$held" | grep . | sort)
  comm -13 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") | grep .
  prev="$cur"
  sleep "$POLL"
done
```

The same rules as `/reviewer-watch` apply — key on the head commit, publish nothing on a
failed poll, `grep .` the output, sleep on both paths, name the repo, bound the list, break
the silence at five failures, cap on queue membership, always publish `held`. These are the
ones this file sharpens:

- **The tick starts by listing labels and checking all three are there**, for the reason
  `/reviewer-watch` gives: `gh pr list --label` answers `[]`, exit 0, for a wrong slug or a
  missing label, and that is silence forever.
- **Any one call failing skips the whole tick.** Partial failure is likelier than total: a
  rate limit on one list, or on one `compare` call, loses that category, `prev` is
  overwritten with the partial set, and the next good tick re-emits everything in it.
- **`stale` is a state check, not an event.** It asks which open PRs carrying
  `ready-to-merge` are *behind their base*. The event-shaped version — poll for merged
  PRs — replays history: merged PRs keep `ready-to-merge` by design, so every arm and
  every restart would emit every one of them as fresh. A state check has no first-tick
  replay and no gap while the watch is down.
- **`handback` and `mergeable` are label reads, and both labels survive the state they
  describe**, so every arm re-emits every PR carrying one. Neither handler may assume it is
  seeing the event for the first time: the hand-back handler checks whether the fix is
  already placed before placing it again, and the cap comment is posted once.
- **`stale` and `mergeable` come out of one pass and are exclusive by construction.** Same
  candidate set, split on `behind_by`. Two independent queries emitted both for every
  behind PR on every tick.
- **A non-numeric `behind_by` skips the tick rather than the PR.** A 200 with the key
  absent prints `null`, and `[ null -gt 0 ]` is a shell error that would write noise into
  the event stream. A degraded path that cannot tell says so.
- **`mergeable` is outside the cap; `handback` and `stale` are inside it.** The cap meters
  work that costs an agent round. A `mergeable` line costs a notification, so a loop
  holding four PRs behind the cap still says the fifth is ready — withholding that would
  make the cap an outage rather than a brake. That is why `mergeable` goes into `notes`.
- **The sort is on the second field.** The number sits behind the tag; sorting whole lines
  would rank every `handback` above every `stale` regardless of number.

## On each event

Hand the work to a subagent and keep only the event line. The tag says what it is, and a
tag this section does not name is **not** dispatched on a guess. There is exactly one:
`held N`, the cap's state line, a count for the person, dropped here. It is the most
confusable line in the stream because every event is tag-first and `held 2` has the shape
of one; a handler that falls through to a default would hand a subagent the PR numbered 2.

**First, the claim.** Hold the set of PR numbers this session has a round running on and
drop any event naming one of them. `needs-changes` stays on while the fix is being
placed, and placing a fix means pushing, so a tick mid-round sees the PR at a new head and
emits `handback <n> <newsha>` as fresh work. A second fix-placement round on a PR already
being fixed is how one finding becomes two conflicting commits.

When a round ends, release the claim and re-read the PR once — head and labels — and
dispatch again only if the trigger label is still on at a head that round did not handle.
A claim held past about half an hour is a round that did not come back: notify once, naming
the PR, and hold it. Restarting the watch is the release, and that is a person's call.

**`handback <n> <sha>`** — the reviewer could not place a finding. Read the PR's last
review comment. Put the fix where it belongs, which may be a **different PR** if this repo
stacks; *fix a finding in the PR that introduced it*. If the fix went elsewhere, that PR
has to land before this one goes back in the queue — until it does, this diff is the one
the reviewer already read, defect included. Run `bash scripts/check.sh`. Then `needs-changes`
off, `ready-for-review` on.

Read the PR before placing anything. `needs-changes` persists until the swap, so this
event re-emits on every arm of the watch, and a restart mid-round would otherwise open a
second fix-placement pass on a PR whose fix is already in the branch.

**`stale <n> <behind>`** — this PR carries a pass taken against a diff its base has since
moved past. **Swap first, then merge forward:** `ready-to-merge` off, `ready-for-review`
on, and only then `git fetch origin`, merge `origin/<base>`, `git push origin HEAD:<branch>`.

The order is the finding, not a preference. Merging first leaves a window in which the PR
is no longer behind and still carries `ready-to-merge` — and the next tick is one `$POLL`
away, less than the merge and two label calls take. In that window this same loop
classifies it `mergeable`. Swapping first cannot do that: the label is gone before
`behind_by` reaches 0.

**Finish the push.** A rejected push means the reviewer pushed a fix while this ran; never
`--force`. Fetch, merge again, push again — and do not leave it for the next tick, because
after the swap this PR no longer carries `ready-to-merge` and the stale query will never
return it a second time.

**`mergeable <n> <sha>`** — run the four checks below and merge. The watch's line is a state read from one
tick ago; the checks are against the PR as it is now:

1. `ready-to-merge` is still on and `ready-for-review` and `needs-changes` are both
   off. If not, a round moved them between the tick and now — do nothing.
2. The head is the head the label was set at: on the PR's timeline the last
   `labeled ready-to-merge` event comes after the last commit, and the sha equals the one
   the reviewer's **latest LGTM** first line names. A commit after the labelling is a diff
   nobody has passed — swap `ready-to-merge` off and `ready-for-review` on and stop. A
   `committed` timeline event carries `committer.date`, which is when the commit was
   *made*, not pushed — so the sha equality is the half that is exact, and both are
   required. An LGTM naming no sha fails this check.
3. The base is `main`. A PR based on another open branch is a stack whose base
   has not landed; leave it for the base's own `mergeable`. After that base lands, retarget
   the child (`gh pr edit <n> --base main`) and it will come back as `stale`,
   which is the right thing for it to be.
4. `behind_by` is 0 against `main`. If not, the tick was stale itself; the
   `stale` handler is the one to run.

The **builder** merges, on `mergeable` and only after the checks below.

Merge with `gh pr merge <n> --repo danieleugenewilliams/cc4nc --merge`, never `--delete-branch` on a
stack, never `--admin`. Say what landed, at which sha. Children the landing staled show up
as `stale` on the next tick. **If `gh pr merge` exits non-zero, stop and say so.** Do not
retry with other flags, resolve nothing, and never reach for
`git push origin HEAD:main`. Leave the labels as they are — the pass is still
true of the head — and notify: a merge that fails is a PR that needs a person.

Note what `gh pr merge*` on the allowlist admits: `--squash` and `--delete-branch` too,
because the number comes before the flags and no glob refuses a trailing flag. The prose is
what keeps those out. And `git push origin HEAD:*` matches `HEAD:main`, which
lands everything and skips every check; the contract names that hole and its repairs.

## The hand-back cap

Three hand-backs on one PR and the loop stops on it — same count, same source as
`/reviewer-watch`, read from the PR's timeline, never from session memory:

```bash
gh api repos/danieleugenewilliams/cc4nc/issues/<n>/timeline --paginate --slurp \
  | jq '[.[][] | select(.event=="labeled" and .label.name=="needs-changes")] | length'
```

Paginate or the count fails open: the timeline pages at 30 ascending, so the events lost
are the recent ones. At 3 or more: place no fix, swap no label. Comment saying the loop has
stopped on this PR and why, and `PushNotification`. Once — *swap no label* leaves
`needs-changes` on, so the PR re-emits on every session start; read the comments first
and say nothing if the stopped-comment is already posted.

## Taking new work

Between events, when the queue is quiet and fewer than `$ACTIVE` rounds are live, take the
oldest open issue from `gh issue list --repo danieleugenewilliams/cc4nc --state open` that no PR already
references. Before starting an item, label it `in-progress`; an item already carrying it belongs to someone else. Remove it when the PR is labelled `ready-for-review`. Branch from `main`, do the work in a subagent, run
`bash scripts/check.sh`, open the PR with `Closes #<issue>` in the body, and label it
`ready-for-review`. Never self-review.

## Stopping

`TaskStop` on the monitor's task id, and say that you did. A stopped watch looks exactly
like an empty queue.
