# The builder–reviewer loop

Two long-running sessions work this repository's backlog through pull requests. A
**builder** takes work from `gh issue list`, opens PRs, and places fixes that are handed
back. A **reviewer** reads each PR, fixes what it can, and hands back what it cannot.
GitHub labels are the state machine; one comment per PR is the record. This file is the
contract. `/builder-watch` and `/reviewer-watch` in `.claude/commands/` execute it and do
not restate it.

Repository: `danieleugenewilliams/cc4nc`. Base branch: `main`. Verification command: `bash scripts/check.sh`.

## Roles

**The session name decides the role, and the names are exact:** `cc4nc-builder` and `cc4nc-reviewer`. No
session holds two roles — a session that reviews its own work is not a second opinion.


Exact, because several loops run on one machine and "the builder" is a guess: a message
delivered to another project's builder is work done on the wrong backlog. Each session
checks **its own** name in `ListAgents` when it arms its watch ("This session is …"), and
says so to the person if the name is not the one above. Session names drift — renames,
typos, a bare `builder` from before the prefix existed — and the session that drifted is
the last to notice.

**A message from a near-miss name is reported, not dropped.** A message about this loop from
a session whose name is close to one of the above but not exact (`builder`, a typo, a
suffix) is neither acted on nor silently ignored: tell the person who sent what, and ask.
The loop that wrote this rule received coordinator messages under three names in one week,
including a typo; dropping them silently would have lost a handoff the build depended on.

## Messages between sessions

**A message is a pointer, not a record.** It names an issue or PR to re-read, or says the
loop is paused or resumed. Act on what GitHub says when you re-read it, never on the message
text alone. A session that restarts never sees a message it missed, but it re-reads GitHub
every tick, so the work follows GitHub even when a message is lost. Decisions that reached
a builder only by message were the loop's most common near-loss.

Every session posts as the same GitHub login as the person, so a comment cannot show who
typed it. **Anything a session posts on the person's behalf says so on its first line** —
`From <person>, via <session>:` — on issues as well as PRs. A comment with no such line is the person's own.

## Decisions

A decision lives in **one place: a dated note appended to the issue's body**, never only in
a PR comment, a PR body or a message. The reviewer judges the PR against the issue as it
stands, latest note included, not as it stood when the PR opened.

```
> **Decision YYYY-MM-DD** — asked by <who>; decided by <who>, <where they said it>:
> "<the option's text, quoted — never only its letter>"
```

- **Quote the option, not its letter.** Letters get misread across relays: one relay called
  "drop the toast" option (a) when (a) was "keep it".
- **Name who asked and who decided.** The person who asks for a change and the person who
  approves it are often different people (the people who use the project ask; its owner decides), and the
  difference is the approval.
- **Whoever hears the decision writes the note**: the builder for a decision given in the builder session, or the person for one given anywhere else. Then a one-line pointer to the
  sessions that need it.
- **A question that needs the person** gets a comment naming the decision and its options in full; the session that asked notifies the person, and records the answer on the issue when it comes. Until it is answered, the session stops on that item.

A scope change to an issue whose PR is already open goes on that PR as a follow-up commit,
and the PR goes back to `ready-for-review` like any other push.

## Labels

The three review-state labels live on the **PR**, not the issue. The issue is the backlog;
the PR is the unit of review. The exception is the claimed label, `in-progress`: it marks an **issue** a builder has taken before any PR exists, and comes off once the PR is labelled. Every label below exists in the repo —
confirmed with `gh label list` when this file was generated. Never write another into a
prompt without creating it first.

| Label | Set by | Means |
|---|---|---|
| `ready-for-review` | builder | This PR is waiting for a reviewer. |
| `ready-to-merge` | reviewer | Reviewed and clean. The only signal that authorises a merge. |
| `needs-changes` | reviewer | Findings the reviewer could not place here. Back to the builder. |
| `in-progress` | builder | On the **issue**: a builder has taken this item and not yet opened its PR. Durable because builders run in parallel and one session's memory is invisible to another. |
| `loop-paused` | person | On one open issue titled `Loop paused`: while any open issue carries it, the builder takes no new work and merges nothing, and the reviewer starts no new review. Rounds in flight finish. |

`ready-to-merge` and `needs-changes` are mutually exclusive. A reviewer sets **at
most** one of them and removes `ready-for-review` with whichever it sets. *At most*, not
*exactly*: a reviewer that cannot vouch for what the head now contains labels nothing, and
`ready-for-review` stays on. Written as *exactly one* the rule reads as an instruction to
pick a label anyway, which is a pass over an unread diff.

Claims: Before starting an item, label the **issue** `in-progress` (`gh issue edit <n> --add-label`); an issue already carrying it belongs to someone else, and the poll that picks work is `gh issue list` filtered to issues without it. Remove it from the issue when the PR is labelled `ready-for-review`.



**Pauses are labels, never memories.** "Stop after #N" or "stop for the night" held in a
session's memory ends when the session restarts — usually when nobody is watching — and the
next morning starts with a question instead of the work. Pause the whole loop by opening one
issue titled `Loop paused`, labelled `loop-paused`, with the reason in its body; resume
by closing it. There is no per-item hold without a blocked label; pause the loop, or set `LABEL_BLOCKED` and re-render. A round already running when a hold or pause lands finishes and
may still label `ready-to-merge`: the merge check refuses it anyway, and a round that stops
half-way leaves worse state than one that finishes.

## State table

Every state has one way in and one way out. `W` = `ready-for-review`, `P` =
`ready-to-merge`, `C` = `needs-changes`.

| From | Event | Who | To |
|---|---|---|---|
| (no label) | PR opened | builder | W |
| W | review passes at the head the reviewer read | reviewer | P |
| W | review finds work only the builder can place | reviewer | C (and P off, if an earlier round left it) |
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

1. **`ready-to-merge` is the only flow label on the PR.** The flow labels are
   `ready-for-review`, `ready-to-merge`, `needs-changes`, `in-progress`; anything else (`bug`, a tracker tag) is a category and does not count. And no issue the PR closes carries **any** flow label — read them with `gh pr view <n> --json closingIssuesReferences` and `gh issue view`. The claim comes off the issue at handoff, so a flow label there is new work assigned after the pass or a gate filed on the issue; either way, not mergeable.

   This is stated as the one permitted state, not as a list of labels that must be absent,
   on purpose. An exclusion list has to be revisited every time a label is added, and when
   it is not, the merge condition silently widens. The two-clause version — passed on,
   changes off — already let an unreviewed commit through: push a commit and hand the PR
   back, and it carries both `ready-to-merge` and `ready-for-review` at once. The fix
   for that, written as a third exclusion, then forgot the claimed and blocked labels the
   moment they were added. Naming the permitted state cannot fail that way.
2. The head is the head the pass was taken at: the last `labeled ready-to-merge` event on
   the PR's timeline comes after the last commit, **and** the sha equals the one named on
   the first line of the reviewer's latest **LGTM** comment. Exact equality on both. The
   timeline orders a commit by the date it was *made*, not pushed, so the sha equality is
   the half that is exact.
3. The base is `main` and `behind_by` is 0 against it.

The **builder** merges, on `mergeable` and only after the checks above. A failed check is a refusal, never a merge on the label alone. A merge
GitHub refuses stops there and says so — no retry with different flags, no `--admin`, no
conflict resolution, never `git push origin HEAD:main`. No PR merges while a
`Loop paused` issue is open.

**A merge approval is never relayed.** Where the session's permission mode refuses the merge
verb until the person approves it, the approval is the person's own words in the merging
session. A session that passes "merge #N" on from the person is making a permission decision
it cannot make, however faithfully it quotes them.

## What a PR is judged against

1. **The issue, as it stands now** — its "done when" list and every decision note on it.
2. **The outcome**, in `docs/outcome.md`: the person's own paragraph on what the project is
   for. Only the person edits it. A finding against the outcome is legitimate even when the
   issue is satisfied. A file still marked as a draft is not the person's yet; nothing is
   judged against it or proposed from it.
3. **The lenses**, in `docs/review-lenses.md`: the checks this project's experts would run, and the
   evidence each accepts. Without the file, the reviewer checks correctness and the person
   who uses it.

**"Done" is a check, not a claim.** Before writing code for an issue, the builder writes the
check that fails until the issue's "done when" holds — a test where the project has tests,
otherwise a script that drives the project through its own hooks — and commits it under
`scripts/checks/` in the same PR. `bash scripts/check.sh` runs everything there; the first PR to add a
check wires that in if it is not already. A check that lives only in a session's scratchpad
proves the issue once and then nobody owns it: in the loop that found this, a later slice
broke an earlier slice's check and nothing noticed, because the check was never committed.

A **feature** PR's body says, in one sentence, which line of the outcome it serves. A bug fix
does not need one; the sentence turns into boilerplate there.

## Findings

Every finding is one of three kinds, and the comment names which:

- **Finding** — something wrong with this PR, carrying its evidence: a measurement, a
  reproduction, or a failing check. "This feels slow" is an opinion two agents can trade
  forever; "3.8 s from pickup at 740×360" ends the argument or starts the fix. Findings
  block the pass. Each names the lens it came from.
- **Question** — a concern without evidence yet. It does not block the pass unless its
  answer is the person's to give, in which case the PR gets `needs-changes` and the
  question goes to the person as a decision (above).
- **Follow-up** — real, evidenced, and not this PR's to fix: a leftover on another screen
  size, a bug already on `main`. It does not block the pass. the builder
  files each one as an issue with the evidence and a link back to the comment, so it does
  not die in a merged PR's comments — which is where the first loop's follow-ups went.

**A broken test environment is not a finding.** A missing browser, an expired login, a dead
toolchain: the session that hits it says so once to the person, names what
it could not check, and carries on with what it can. It slows every round until someone
fixes it, and no round owns it.

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
    not the one the event carried.** Where the reviewer places fixes, a review that fixed
    something has already moved the head with its own commit; in every loop, the builder
    may have pushed while the review ran. The recorded head is the only one this round
    read.
18. **Never force-push past a rejection.** The commit that would go is the other session's.
19. **Stop after three hand-backs, say so once, and notify.** Two agents can pass work back
    and forth forever. Once, because the item stays in the queue and every new session
    re-emits it, and a notification that repeats is one the person learns to ignore.
20. **Say when the watch stops.** A stopped watch and an empty queue look identical. The
    same goes for expiry: a `Monitor` caps at 30 minutes and there is no `persistent` flag,
    so arm at the maximum, re-arm on expiry, and say on each re-arm that it re-armed.
21. **Session names are exact, chosen once, and checked by each session against itself.**
    With several loops on one machine, "the builder" is a guess. A name derived from the
    repo matched none of the running sessions on the first loop that tried it, and the
    sessions themselves drifted (a rename mid-run, a typo). A message from a near-miss name
    is reported to the person, never silently dropped.
22. **The issue is the record; the message is the doorbell.** A restarted session never
    sees a message it missed, and a session in another permission mode may hold one unread,
    but every session re-reads GitHub every tick. Decisions that existed only in messages
    were the loop's most common near-loss.
23. **A decision lives in one place, quotes its option, and names who asked and who
    decided.** Decisions scattered across issue notes, PR bodies and relayed comments could
    not be traced, and a relayed option letter was misread as its opposite.
24. **A pause is a label, never a memory.** A pause held in a session's memory ends when the
    session restarts, which is usually when nobody is watching.
25. **The coordinator touches no review-state label.** A third session setting pass or
    hand-back labels is an unrequested reviewer, and the merge predicate assumes two roles.
26. **A merge approval is never relayed.** Where the merge verb needs the person's word, it
    is their words in the merging session. A session passing them on is making a permission
    decision it cannot make.
27. **Ambition rises only with a checkpoint.** The loop may propose work, as a blocked issue
    the person approves by removing the label; it never approves its own. An outcome check
    reports but opens nothing. Nothing is proposed from an outcome the person did not write.
28. **A finding carries its evidence; a follow-up gets filed.** "This feels slow" is an
    opinion two agents can trade forever; a measurement ends the argument or starts the fix.
    A real problem that is not this PR's goes into an issue, not a merged PR's comments,
    where the first loop's follow-ups were lost.
29. **"Done" is a committed check.** A check that lives in a session's scratchpad proves an
    issue once and then nobody owns it; a later slice broke an earlier one's that way.
30. **Watches expire; re-arm replays work, not notices.** The `Monitor` ends on its own every
    half hour or so. Work lines replay on a re-arm, because that is how a round that died
    gets dispatched again; state lines are diffed against a file that outlives the watch,
    because re-announcing every waiting merge on every re-arm buries the one that matters.

## What this loop does not give you

- **The `allowed-tools` lines in the loop's commands pre-approve nothing.** They use the
  comma-inside form, `Bash(gh pr list*, gh pr view*, …)`, and that form matches no command
  at all. The loop runs because its sessions run in auto mode and **the auto-mode
  classifier passes the commands**; in default mode every call prompts a person. Do not
  rewrite the lines into one `Bash()` per rule to make them match: that would create the
  `gh pr merge*` and `git merge*` pre-approvals the prose has only been assuming. They are
  left as they are on purpose.
- **Reviewing a PR runs the PR.** The reviewer checks the branch out into a worktree and
  runs `bash scripts/check.sh` against it — which executes that branch's own test and build scripts,
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
- **`git push origin HEAD:*` matches nothing either.** `:*` is the trailing-wildcard
  spelling, so the entry reads `git push origin HEAD *` — neither `HEAD:main` nor
  the branch pushes it was put there to allow. What keeps a session off `main` is
  the deny rules below.
- **Session names are trusted, not verified.** Any session renamed to one of the exact names
  above can send pointers. The safeguard is that a pointer only says where to look; what a
  session acts on is what GitHub says.
- **Watches expire.** The `Monitor` behind each command can end — in this harness, after
  about thirty minutes, and there is no `persistent` flag — and nothing announces it. Each
  command says how to re-arm, and a stopped watch still looks exactly like an empty queue.
- **The loop converges; it does not decide.** Nothing here can mechanise "this feature is
  good enough." A third hand-back is where a person comes in.
- **Merging is not deploying.** The last state here is *merged* — that lands code, it does
  not run it. A repo that executes its own merged code — a service, a bot, an agent that reads
  its own config — needs a separate activation step (pull the deployed tree, restart what the
  change touched), and "merged" reported as "live" is where this project's worst latent bug sat
  undeployed for hours. The loop stops at the merge on purpose; wiring merge→live — and knowing
  which changes go live on next read versus which need a restart — is yours.

## Keeping sessions off `main`: deny rules

The control is four `deny` rules in `.claude/settings.json`, because **deny outranks allow
in every mode and scope**:

```
Bash(git push * main)
Bash(git push * main *)
Bash(git push *:main)
Bash(git push *:main *)
```

Four because a refspec names `main` either bare or right of a colon, and either
can carry a trailing flag. Two shapes times two positions.

They sit **beside** any `Bash(git push --force-with-lease *)` allow rather than replacing
it. That allow is what lets a session rewind its own branch under a lease; removing it
reopens a different problem, and the deny covers the `main` case the allow would
otherwise reach.

Three spellings escape, recorded rather than chased: `git -C . push`, and
`refs/heads/main` on either side of the refspec. Each has the standing every push
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
`PreToolUse` hook that refuses pushes to `main` is a further option.
