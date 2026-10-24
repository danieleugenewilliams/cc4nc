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
