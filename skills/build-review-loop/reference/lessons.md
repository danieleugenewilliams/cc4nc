# What varied across three ports of the loop

Background for whoever maintains this skill. Nothing in the procedure depends on it, and
none of these repos is needed to use the skill. The three were: a daemon-orchestrated repo
(launchd, a chat bot, a Python orchestrator, agents run with permissions bypassed); a
curriculum repo (two markdown slash commands and a `Monitor`, stacked PRs, two test
suites); and a Go repo (215 test files, no `make test` target, issue-level labels).

Everything in the left column looked like an invariant until a second repo disagreed.

| Looked fixed | daemon repo | curriculum repo | Go repo |
|---|---|---|---|
| Where labels live | PR | PR | **issue** |
| The label set | one | three | **five** |
| How a claim is held | dispatch state file | in-session memory | **a durable `in-progress` label** |
| Who merges | a person, hook-enforced | the builder, after checks | a three-way predicate |
| Orchestration | daemon + bot + IPC | two markdown commands | two markdown commands |

**Labels the repo did not have** broke two of three ports. On the curriculum repo, two
drafts ran on label names that had never existed; the worse one would have run cleanly
until the first review that found something. On the Go repo the doc named two labels
while the repo had three different ones, so a reviewer following the repo and a builder
following the doc would have deadlocked on the first handoff — and someone had already
created labels to match the doc before they were deleted again. That is why step 2 reads
the list, creates what is missing, and re-reads.

**Issue-level labels need a link to the PR.** The Go repo labelled issues and merged PRs
with nothing connecting them: a reviewer polling labelled issues could not see an unlinked
PR, and the PR that documented this gap demonstrated it on itself — no label, no linked
issue, while its own body claimed it was labelled and waiting.

**The claimed state is the one people leave out.** On the Go repo an unlabelled issue
meant three different things — never started, assigned, or finished but unpushed — and a
complete, tested commit sat unpushed in a worktree for five days.

**The merge predicate's third clause** (waiting-for-review must also be off) was found in
review on the Go repo after the two-clause version shipped.

**The per-PR cap does not bound a loop** — the daemon repo's spiral was nine separate PRs,
each resetting its own counter. The curriculum repo, which stacks, was worse exposed: one
merge staled every child, each re-entered the queue.

**The toolchain check** exists because the preflight was once run on a machine with
`node`, `npm`, `python3` and `jq` but neither `gh` nor `go`. Every repo check passed and
the loop could not have run on any of them.

**Hand-back counts un-paginated** read 2 on a PR whose true count was 5.

**Thirteen abandoned worktrees** accumulated in the curriculum repo before anyone read
`git worktree list`.

# What three weeks of running it taught (Oct 2026)

From the three sessions of one loop — builder, reviewer, coordinator — on a browser game repo
(one big HTML file, a progress tracker, players who are not the owner), PRs #95–#131, plus the
memories of four other repos running the loop. The coordinator role was drafted from the
desktop app on Oct 23; this is what the sessions that would run it said about the draft,
each point tied to an incident.

**Exact names were right, and deriving them was wrong.** The draft built the prefix from the
repo name (`agent-ux`); the sessions were `agentux-*`. The coordinator had messaged the other
two under three names that week — `coordinator`, `agentux-coordinator`, and a typo — and the
draft's "ignore any other name" would have dropped the handoff of the assets the next
feature was built from. Hence a required `SESSION_PREFIX`, each session checking its own
name, and near-misses reported rather than dropped.

**Decisions were the near-loss.** Five decisions reached the builder only by message. Where
the coordinator had posted first, re-reading was cheap and worked. Decisions also landed in
three places (issue notes, PR bodies, relayed comments); one relayed option letter was read
as its opposite, and the reviewer could not tell a relayed decision from the person's own
comment because every session posts as the person's login. Hence one place, quoted options,
and an attribution line on everything posted on someone's behalf.

**The person is several people.** The players asked; the owner decided. A note that says
"from the person" loses the approval.

**Merges waited on the person, and nothing said so.** Auto mode refuses `gh pr merge` until
the person types "merge #N" in the builder session; ready PRs waited three to six hours.
A coordinator relaying "merge #N" would be laundering a permission decision, so the fix is
visibility — "waiting on you" first in every status — not a relay.

**The watches expire every half hour**, and the draft's `persistent: true` does not exist in
this harness. The reviewer re-armed about seventy times in two days. The builder's re-arm
re-announced every waiting merge each time; the coordinator's "first tick publishes nothing"
would have lost every merge that landed between expiry and re-arm. Hence `$SEEN` files, and
an explicit re-arm section in every command.

**A two-hour "stuck" alarm fired on a healthy review.** #131's review took 2 h 6 m; big
reviews run one to two hours. Three hours, and ask whether the reviewer is busy first.

**A crew of three reviewers would have cost three times as much and caught nothing more.**
Single rounds already ran 116k–209k tokens and up to two hours, mostly driving a browser.
Every real defect came from correctness plus device measurement — a comment that swallowed a
`push()`, a restore that replayed cheers, 9-pixel weapon slots, a 32-pixel button. Hence one
reviewer with the lenses as a checklist, and a second only where the lenses say so.

**Follow-ups died in comments.** Leftover overlaps on one screen size, an overflow already on
main: both "LGTM plus a note", neither filed. Hence a third finding kind and a filer.

**Checks lived in scratchpads.** The builder's harnesses were re-copied each slice and never
committed; a later slice broke an earlier slice's check and nobody noticed. Hence `CHECKS_DIR`.

**The blocked label was already doing three jobs.** The builder used `needs-human` for "wait
for the players' choices" and for "wait for the owner's pick" — a hold and a proposal.
Adding `on-hold` and `proposed` beside it would have given four labels for "waiting on the
person". One label, and the comment says which kind of wait.

**The coordinator made things, too.** It built 3D models the next feature used, in a
scratchpad that would have been cleared, and one differed from its issue's spec — which only
the builder noticed. Hence: durable place, checked against the spec, before an issue points
to it.

**Nobody owned the test environment.** A missing headless browser slowed every review for a
week and failed a 5-minute test cap. It is not a finding on any PR; it is a status line until
someone fixes it.
