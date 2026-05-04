# Tests J, K, L - Session State & Resumption (Lesson 1.7)

All three tests use the same Alice / ORD-1002 investigation as the substrate.
Reset the refund log before each scenario.

---

## Test J - `--continue` resume (Scenario 1)

Full walkthrough: `session_demo/scenario_1_continue.md`

**Quick reference:**
1. `python3 audit_demo/reset_refunds.py`
2. `claude` → investigate Alice / ORD-1002 → get recap → exit
3. `claude --continue` → deliver manager verdict → refund issued

**Pass:**
- Session 2 uses prior context without re-fetching (`list_refunds` not called again)
- `refunds_log.json` has 10+ entries (9 seed + 1 new ORD-1002)
- Single session identity across both halves

**Teaching moment:** Session 2 references the March cluster from Session 1's tool calls - Claude has the full prior context. No re-investigation needed. This is `--continue` as "picking up mid-sentence."

---

## Test K - `--fork-session` (Scenario 2)

Full walkthrough: `session_demo/scenario_2_fork.md`

**Quick reference:**
1. `python3 audit_demo/reset_refunds.py`
2. Build parent session (same as Test J Session 1)
3. Approved fork: `claude --resume <id> --fork-session` → manager approved → refund issued
4. `python3 audit_demo/reset_refunds.py` (reset before denied branch)
5. Denied fork: `claude --resume <id> --fork-session` (same parent ID) → manager denied → email drafted

**Pass:**
- Three distinct session files
- Parent unchanged
- Approved fork: log has ORD-1002 entry; denied fork: log at 9 seed entries

**Teaching moment:** the reset step between branches *is* the lesson. Both forks share `refunds_log.json`. Forks branch conversation, not filesystem. The claude --resume picker shows the three sessions grouped - parent with two children.

---

## Test L - Fresh start + summary injection (Scenario 3)

Full walkthrough: `session_demo/scenario_3_fresh_brief.md`

**Quick reference:**
1. `python3 audit_demo/reset_refunds.py`
2. `claude` (fresh, no flags) → paste `scenario_3_fresh_brief.handoff_brief.md` + "Take it from here."
3. Claude re-fetches, issues refund

**Pass:**
- New session ID (unrelated to any prior session)
- Claude issues refund via `issue_refund` with `manager_approved=true`
- Log gains new ORD-1002 entry
- Claude does NOT claim to remember a prior conversation - it has none

**Teaching moment:** compare the handoff brief (200 words) to a full session transcript (thousands of words). The brief carries everything that matters. This is "the doctor's handoff note" pattern - compressed signal, no noise. Recommended for cross-machine handoffs.
