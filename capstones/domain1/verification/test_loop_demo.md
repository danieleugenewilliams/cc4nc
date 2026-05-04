# Test E/F - Loop Demo (stop_reason handling)

## Setup
From `capstones/domain1/`:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

---

## Test E - Correct loop

```bash
python3 loop_demo/loop_demo.py
```

**Pass criteria:**
- Output shows `--- stop_reason: tool_use ---` at least once (Claude called a tool)
- Output ends with `--- stop_reason: end_turn ---`
- `FINAL ANSWER:` contains a correct response referencing ORD-3001 ($1,200.00, April 25, 2025)
- Loop did NOT exit early on a text block

**Expected output shape:**
```
Prompt: Has CUST-03 placed any orders over $1,000? ...

============================================================

--- stop_reason: tool_use ---
  calling tool: list_recent_orders({"customer_id": "CUST-03"})

--- stop_reason: end_turn ---

FINAL ANSWER:
Yes, CUST-03 placed one order over $1,000: ORD-3001 for $1,200.00, ordered on April 25, 2025.
```

---

## Test F - Anti-pattern demos

```bash
python3 loop_demo/loop_demo_wrong.py
```

**Pass criteria - each variant fails in its documented way:**

| Variant | Expected failure |
|---------|-----------------|
| Anti-pattern 1 | Prints "EXIT: saw a text block" before any tool ran |
| Anti-pattern 2 | Prints "EXIT: hit iteration cap (2)" before `end_turn` |
| Anti-pattern 3 | Prints "EXIT: found a text block" before any tool ran |

No variant should produce a correct final answer. The tool calls either never happen or are cut off mid-way.

---

## Capture transcripts for Substack

```bash
python3 loop_demo/loop_demo.py > loop_demo/transcript_correct.txt 2>&1
python3 loop_demo/loop_demo_wrong.py > loop_demo/transcript_wrong.txt 2>&1
```

These files are referenced in the README as Substack screenshot sources.
