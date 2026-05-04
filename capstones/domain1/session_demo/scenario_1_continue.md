# Scenario 1 — `--continue` resume

A complex refund case that spans two separate sessions. The first session gathers the facts; a real-world break follows (coffee, a meeting, a night's sleep); the second session picks up with the manager's verdict and closes the case.

**What this demonstrates:** `--continue` loads the full session transcript, giving the resumed session complete context from the prior one — no re-investigation needed.

---

## Setup

Reset the refund log first:
```bash
python3 audit_demo/reset_refunds.py
```

---

## Session 1 — Investigation

Start Claude Code from `capstones/domain1/`:
```bash
claude
```

**Prompt 1.1 — gather the full picture:**
```
I need to investigate a refund request from alice@example.com for order ORD-1002.
She's claiming $612, reason "shipping damaged". Pull the full picture: her customer
record, the order, her recent order history, and her complete refund history. Flag
anything that should affect the decision, but do not issue the refund yet.
```

**Expected behaviour:** Claude calls `lookup_customer`, `get_order`, `list_recent_orders`, and `list_refunds`. It surfaces:
- Alice's `manager_approval_flag` is `false` — escalation required for >$500
- Refund history shows 4 refunds in a 7-day window (March 14–20) totalling $1,212
- 3 of those 4 lacked manager approval

**Prompt 1.2 — close the session cleanly:**
```
I need to step away. Summarise where we are, what's outstanding, and what I should
ask the manager about before approving or denying the refund.
```

**Expected behaviour:** Claude produces a concise recap with the key facts, the policy constraint (>$500, no approval), and suggested questions for the manager.

**Exit the session:** `Ctrl+D` or type `/exit`

Capture the transcript:
```bash
# The output is already in your terminal — scroll up and save it
```

---

## Session 2 — Resolution (resume)

Come back after your break. Run:
```bash
claude --continue
```

Claude Code loads the prior session. You should see the session name / last message displayed.

**Prompt 2.1 — deliver the verdict:**
```
I spoke to the manager. Verdict: approved — the shipping damage claim is
documented in the carrier's report. Please process the refund for ORD-1002,
$612, and confirm.
```

**Expected behaviour:** Claude calls `issue_refund` with `manager_approved=true`. The PreToolUse hook evaluates the call, sees the flag, and allows it. Refund is logged.

**Pass criteria:**
- Claude in session 2 references prior findings ("as we noted earlier, the March cluster…") without calling the tools again for the same data
- `refunds_log.json` gains a new entry for ORD-1002 (beyond the 9 seeded entries)
- The two transcripts share the same session identity (you can verify with `claude --resume` — the picker shows one session, not two)

**Verify the log:**
```bash
python3 -c "
import json
log = json.load(open('mcp_server/data/refunds_log.json'))
print(f'Total entries: {len(log)}')
alice = [r for r in log if r[\"order_id\"] == 'ORD-1002']
print('ORD-1002 refunds:', alice)
"
```

Expected: 10 total entries (9 seed + 1 new ORD-1002 entry).
