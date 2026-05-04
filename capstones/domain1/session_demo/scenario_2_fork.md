# Scenario 2 — `--fork-session` divergent paths

The same investigation, two different manager verdicts. Forking lets you explore both outcomes from the same starting point — without losing either branch.

**What this demonstrates:** `--fork-session` branches the conversation history. The parent session is preserved. Each fork gets its own session ID and continues independently. Crucially: **forks do not isolate the filesystem** — both forks share `refunds_log.json`. This is a teaching moment, not a bug.

---

## Setup

Reset the refund log:
```bash
python3 audit_demo/reset_refunds.py
```

---

## Step 1 — Build the parent session

Run Scenario 1, Session 1 (Prompts 1.1 and 1.2) to the point where Claude has produced its recap and is waiting for the manager verdict. **Do not deliver the verdict. Exit.**

```bash
claude
# [run prompt 1.1 — gather full picture]
# [run prompt 1.2 — ask for recap]
# /exit
```

**Find your session ID.** Open the session picker:
```bash
claude --resume
```

Note the session ID or name shown for the investigation session. You'll need it for both forks. Press `Esc` to exit the picker without resuming.

---

## Step 2 — Approved branch

Fork from the parent session:
```bash
claude --resume <session-id> --fork-session
```

**Prompt A:**
```
The manager approved the refund. The shipping damage is documented in the
carrier's report. Please process the refund for ORD-1002, $612, and confirm.
```

**Expected behaviour:** Claude calls `issue_refund` with `manager_approved=true`. Hook allows. Refund logged.

Exit: `/exit`

---

## Step 3 — Reset log, then denied branch

**Reset the refund log before the denied branch:**
```bash
python3 audit_demo/reset_refunds.py
```

This is the filesystem-isolation lesson made explicit: the approved branch wrote to `refunds_log.json`. Without the reset, the denied branch sees a log that already has the refund — which is confusing. Forks branch conversation history, not the world.

Fork from the **same parent session ID**:
```bash
claude --resume <session-id> --fork-session
```

**Prompt B:**
```
The manager denied the refund. Reason: Alice's account shows 4 refunds in
7 days totalling $1,212 — the March cluster you flagged. This looks like
potential refund abuse and is being escalated to the fraud team.

Draft a polite email to Alice explaining the decision and offering a 15%
store credit instead as a goodwill gesture.
```

**Expected behaviour:** Claude does NOT call `issue_refund`. It drafts the email. `refunds_log.json` is unchanged.

Exit: `/exit`

---

## Pass criteria

- Three distinct `.jsonl` session files in `~/.claude/projects/<folder>/` (parent + 2 forks)
- Parent session is unchanged (verify with session picker — its last message should still be the recap from Step 1)
- After Step 2 (before reset): `refunds_log.json` has 10 entries including a new ORD-1002 entry
- After Step 3: `refunds_log.json` has 9 entries (reset applied, denied fork did not add to it)

**Verify fork count:**
```bash
claude --resume
# Press Ctrl+W to show all worktrees/sessions
# You should see the parent session and two forks grouped together
```

---

## The teaching moment

The reset step between branches is itself the lesson from Lesson 1.7:

> "Fork creates two independent conversation histories. It does not create two independent file systems. When you need filesystem isolation, that's worktrees — a different tool."

For the Substack post: screenshot the session picker showing the three grouped sessions (parent + approved + denied).
