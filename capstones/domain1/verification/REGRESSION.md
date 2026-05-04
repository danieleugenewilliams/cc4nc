# Regression Test Matrix - Domain 1 Capstone

Run all tests after any change to MCP server, data files, hooks, or agents.
Run the full A–L sequence before any Substack publication.

## Reset hygiene

**Before tests B, C, D, H, I, and all session_demo scenarios (J, K, L):**
```bash
python3 audit_demo/reset_refunds.py
```

This copies `mcp_server/data/refunds_log.seed.json` → `refunds_log.json` (9 clean entries).
Without this reset, refunds from a prior test pollute the next one.

---

## Tests A–G - Existing (Claude Code)

Run these from `capstones/domain1/` with `claude` open.

| Test | Prompt | Pass criterion |
|---|---|---|
| **A** PostToolUse normalisation | `Show me the last 3 orders for alice@example.com` | All dates in response are ISO 8601 or plain English. Raw `orders.json` still has mixed formats after the test. |
| **B** PreToolUse - over threshold | `Issue a $750 refund to alice@example.com for ORD-1002. Reason: shipping was damaged.` | Hook fires and returns blocking error. Log unchanged at 9 seed entries. Claude escalates or asks for approval. |
| **C** PreToolUse - missing reason | `Issue a $50 refund to bob@example.com for ORD-2002` (no reason) | Hook blocks. Claude re-asks for reason. Provide "changed mind" - second call succeeds and log gains ORD-2002 entry. |
| **D** PreToolUse - allowed (Carla) | `Issue a $750 refund to carla@example.com for ORD-3001. Reason: defective product.` | Hook allows (Carla has `manager_approval_flag=true`). Log gains ORD-3001 entry **on top of the 9 seeded entries** (total: 10+). |
| **E** Loop demo | `python3 loop_demo/loop_demo.py` | `stop_reason` trace ends in `end_turn`. Answer references **ORD-3001 / $1,200.00 / April 25, 2025**. |
| **F** Loop anti-patterns | `python3 loop_demo/loop_demo_wrong.py` | Each of 3 variants fails in its documented way (premature exit, iteration cap, text-presence exit). None produces a correct final answer. |
| **G** Hook composition | `List Carla's orders, then refund ORD-3003 for $510, reason: late delivery.` | PostToolUse normalises dates; PreToolUse allows refund (Carla has approval flag). Both hooks fire without interference. Log gains ORD-3003 entry. |

---

## Tests H–I - Audit decomposition

Run from `capstones/domain1/` with seeded data.

**Before running:** `python3 audit_demo/reset_refunds.py`

| Test | Command | Pass criterion |
|---|---|---|
| **H** Single-pass dilution | `python3 audit_demo/audit_single_pass.py` | Output misses at least 2 of the 8 ground-truth findings OR shows visibly uneven depth (one customer section ≥3× longer than another). See ground-truth findings below. |
| **I** Multi-pass full coverage | `python3 audit_demo/audit_multipass.py` | All 8 ground-truth findings present in synthesised output. Synthesis section names at least one cross-customer observation not present in any single worker report. |

**Ground-truth findings (8 total):**
- F-A1: Alice - 4 refunds in a 7-day window (cluster, March 14–20)
- F-A2: Alice - $1,212 total refunded
- F-A3: Alice - 3 of 4 cluster refunds lacked manager approval
- F-B1: Bob - 1 refund in 10 orders (~10% rate)
- F-B2: Bob - no clustering or high-value pattern
- F-C1: Carla - 40% refund rate (4/10 orders)
- F-C2: Carla - all 4 refunds high-value, $2,430 total
- F-C3: Carla - multiple different reasons across refunds

**Grep helper:**
```bash
python3 -c "
import sys
transcript = open('audit_demo/transcript_multipass.txt').read().lower()
findings = {
    'F-A1': any(x in transcript for x in ['7-day', '7 day', 'cluster', 'march 14', 'march 1']),
    'F-A2': any(x in transcript for x in ['1,212', '1212']),
    'F-A3': any(x in transcript for x in ['manager approv', 'without approval', 'no approval']),
    'F-B1': any(x in transcript for x in ['10%', '1 refund', 'one refund', '10 percent']),
    'F-B2': any(x in transcript for x in ['no cluster', 'no concern', 'clean', 'low risk']),
    'F-C1': any(x in transcript for x in ['40%', '4/10', '4 refunds', '40 percent']),
    'F-C2': any(x in transcript for x in ['2,430', '2430', 'high-value', 'high value']),
    'F-C3': any(x in transcript for x in ['different reason', 'varied reason', 'multiple reason']),
}
hits = sum(findings.values())
print(f'Findings: {hits}/8')
for f, found in findings.items():
    print(f'  {f}: {\"FOUND\" if found else \"MISSING\"}')
"
```

---

## Tests J–K–L - Session state

Manual tests. Run from `capstones/domain1/`.

| Test | File | Pass criterion |
|---|---|---|
| **J** `--continue` resume | `session_demo/scenario_1_continue.md` | Session 2 references prior findings without re-fetching. `refunds_log.json` gains new ORD-1002 entry. |
| **K** `--fork-session` | `session_demo/scenario_2_fork.md` | Three session files (parent + 2 forks). Parent unchanged. Approved fork logs ORD-1002; denied fork does not. |
| **L** Fresh + brief | `session_demo/scenario_3_fresh_brief.md` | New session ID (unrelated to any prior). Refund processed from brief alone. |

---

## Full run order

```bash
# Start from capstones/domain1/

# Reset
python3 audit_demo/reset_refunds.py

# Automated tests (API key required)
python3 loop_demo/loop_demo.py         # Test E
python3 loop_demo/loop_demo_wrong.py   # Test F

# Reset before audit tests
python3 audit_demo/reset_refunds.py
python3 audit_demo/audit_multipass.py | tee audit_demo/transcript_multipass.txt   # Test I
python3 audit_demo/reset_refunds.py
python3 audit_demo/audit_single_pass.py | tee audit_demo/transcript_single_pass.txt  # Test H
# Run grep helper on both transcripts

# Claude Code tests (open claude in this directory)
# Reset, then run Tests A, B, C, D, G in Claude Code
# Manually run session_demo scenarios J, K, L
```
