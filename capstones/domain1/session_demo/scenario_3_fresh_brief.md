# Scenario 3 - Fresh start + summary injection

A new machine, a new terminal, or just a preference for a clean slate. The prior session's context doesn't need to be loaded - the handoff brief carries everything that matters.

**What this demonstrates:** structured summary injection as the designed approach for cross-session handoffs. The new session starts fresh but informed - no stale tool results, no transcript bloat, and you control exactly what carries forward.

---

## Setup

Reset the refund log:
```bash
python3 audit_demo/reset_refunds.py
```

---

## Step 1 - Open a fresh session

Start Claude Code without `--continue` or `--resume`:
```bash
claude
```

This is a brand-new session with no connection to prior work.

---

## Step 2 - Paste the handoff brief

Open `session_demo/scenario_3_fresh_brief.handoff_brief.md` and copy its full contents. Then type:

```
[paste the handoff brief here]

Take it from here.
```

The brief is at: `capstones/domain1/session_demo/scenario_3_fresh_brief.handoff_brief.md`

---

## Expected behaviour

Claude reads the brief and:
1. Calls `lookup_customer` and `get_order` to re-fetch Alice's details (no prior tool results - must re-fetch)
2. Calls `issue_refund` with `order_id="ORD-1002"`, `amount_usd=612`, `reason="shipping damaged (carrier documented)"`, `manager_approved=true`
3. The PreToolUse hook evaluates the call: amount > $500, approved=true → allowed
4. Refund is logged; Claude confirms

---

## Pass criteria

- This session has a **different session ID** from any scenario 1 or scenario 2 session
- Claude issues the refund using only the brief + fresh tool calls
- `refunds_log.json` gains a new ORD-1002 entry
- Claude does NOT reference "earlier in our conversation" or prior context - it has none

**Verify:**
```bash
python3 -c "
import json
log = json.load(open('mcp_server/data/refunds_log.json'))
new = [r for r in log if r['order_id'] == 'ORD-1002' and 'seed' not in r['refund_id']]
print(f'New ORD-1002 refunds (non-seed): {new}')
"
```

---

## The teaching moment

The brief in `scenario_3_fresh_brief.handoff_brief.md` is the handoff artifact. Compare its length (~200 words) to a full session transcript (hundreds of turns, many kilobytes). The brief preserves the signal; the transcript preserves the noise.

From Lesson 1.7: *"Cross-host session file transfer is possible - copy the `.jsonl` to the exact same path on the new machine, matching the folder name precisely - but the fresh-start-with-injection pattern is more robust and is the recommended approach."*

For the Substack post: show the brief text and the refund confirmation side by side. The brief is the "doctor's handoff note" analogy made real.
