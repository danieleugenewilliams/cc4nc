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
