# The builder–reviewer loop

Two long-running sessions work this repository's backlog through pull requests. A
**builder** takes work from `gh issue list`, opens PRs, and places fixes that are handed
back. A **reviewer** {{REVIEWER_SUMMARY}}
GitHub labels are the state machine; one comment per PR is the record. This file is the
contract. `/builder-watch` and `/reviewer-watch` in `.claude/commands/` execute it and do
not restate it.

Repository: `{{REPO}}`. Base branch: `{{BASE_BRANCH}}`. Verification command: `{{TEST_CMD}}`.

## Roles

**The session name decides the role, and the names are exact:** {{SESSION_LIST}}. No
session holds two roles — a session that reviews its own work is not a second opinion.
{{COORDINATOR_ROLE}}

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
- **Whoever hears the decision writes the note**: {{NOTE_WRITER}}. Then a one-line pointer to the
  sessions that need it.
- **A question that needs the person** {{QUESTION_RULE}}

A scope change to an issue whose PR is already open goes on that PR as a follow-up commit,
and the PR goes back to `{{LABEL_WAITING}}` like any other push.

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
| `{{LABEL_PAUSED}}` | person{{PAUSE_SETTER}} | On one open issue titled `Loop paused`: while any open issue carries it, the builder takes no new work and merges nothing, and the reviewer starts no new review. Rounds in flight finish. |

`{{LABEL_PASSED}}` and `{{LABEL_CHANGES}}` are mutually exclusive. A reviewer sets **at
most** one of them and removes `{{LABEL_WAITING}}` with whichever it sets. *At most*, not
*exactly*: a reviewer that cannot vouch for what the head now contains labels nothing, and
`{{LABEL_WAITING}}` stays on. Written as *exactly one* the rule reads as an instruction to
pick a label anyway, which is a pass over an unread diff.

Claims: {{CLAIMED_RULE}}

{{BLOCKED_RULE}}

**Pauses are labels, never memories.** "Stop after #N" or "stop for the night" held in a
session's memory ends when the session restarts — usually when nobody is watching — and the
next morning starts with a question instead of the work. Pause the whole loop by opening one
issue titled `Loop paused`, labelled `{{LABEL_PAUSED}}`, with the reason in its body; resume
by closing it. {{HOLD_RULE}} A round already running when a hold or pause lands finishes and
may still label `{{LABEL_PASSED}}`: the merge check refuses it anyway, and a round that stops
half-way leaves worse state than one that finishes.

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
conflict resolution, never `git push origin HEAD:{{BASE_BRANCH}}`. No PR merges while a
`Loop paused` issue is open.

**A merge approval is never relayed.** Where the session's permission mode refuses the merge
verb until the person approves it, the approval is the person's own words in the merging
session. A session that passes "merge #N" on from the person is making a permission decision
it cannot make, however faithfully it quotes them.

## What a PR is judged against

1. **The issue, as it stands now** — its "done when" list and every decision note on it.
2. **The outcome**, in `{{OUTCOME_PATH}}`: the person's own paragraph on what the project is
   for. Only the person edits it. A finding against the outcome is legitimate even when the
   issue is satisfied. A file still marked as a draft is not the person's yet; nothing is
   judged against it or proposed from it.
3. **The lenses**, in `{{LENSES_PATH}}`: the checks this project's experts would run, and the
   evidence each accepts. Without the file, the reviewer checks correctness and the person
   who uses it.

**"Done" is a check, not a claim.** Before writing code for an issue, the builder writes the
check that fails until the issue's "done when" holds — a test where the project has tests,
otherwise a script that drives the project through its own hooks — and commits it under
`{{CHECKS_DIR}}/` in the same PR. `{{TEST_CMD}}` runs everything there; the first PR to add a
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
  answer is the person's to give, in which case the PR gets `{{LABEL_CHANGES}}` and the
  question goes to the person as a decision (above).
- **Follow-up** — real, evidenced, and not this PR's to fix: a leftover on another screen
  size, a bug already on `{{BASE_BRANCH}}`. It does not block the pass. {{FOLLOWUP_FILER}}
  files each one as an issue with the evidence and a link back to the comment, so it does
  not die in a merged PR's comments — which is where the first loop's follow-ups went.

**A broken test environment is not a finding.** A missing browser, an expired login, a dead
toolchain: the session that hits it says so once to the person{{ENV_COORDINATOR}}, names what
it could not check, and carries on with what it can. It slows every round until someone
fixes it, and no round owns it.

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

- **The `allowed-tools` lines in the loop's commands pre-approve nothing.** They use the
  comma-inside form, `Bash(gh pr list*, gh pr view*, …)`, and that form matches no command
  at all. The loop runs because its sessions run in auto mode and **the auto-mode
  classifier passes the commands**; in default mode every call prompts a person. Do not
  rewrite the lines into one `Bash()` per rule to make them match: that would create the
  `gh pr merge*` and `git merge*` pre-approvals the prose has only been assuming. They are
  left as they are on purpose.
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
- **`git push origin HEAD:*` matches nothing either.** `:*` is the trailing-wildcard
  spelling, so the entry reads `git push origin HEAD *` — neither `HEAD:{{BASE_BRANCH}}` nor
  the branch pushes it was put there to allow. What keeps a session off `{{BASE_BRANCH}}` is
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
