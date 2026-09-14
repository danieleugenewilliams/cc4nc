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
