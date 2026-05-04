# Domain 1 Capstone — Customer Support Agent

Companion build for the Claude Architect (Foundations) Domain 1 syllabus.

---

## What this demonstrates

| Syllabus requirement | Where it lives |
|---------------------|----------------|
| Multi-tool agent with 5 MCP tools | `mcp_server/server.py` |
| `stop_reason` handling | `loop_demo/loop_demo.py` |
| PostToolUse normalisation hook | `hooks/normalize_dates.py` |
| PreToolUse policy gate hook | `hooks/refund_policy_gate.py` |
| Task decomposition (multi-pass audit) | `audit_demo/` |
| Session state & resumption | `session_demo/` |

---

## Architecture

```
You
 │
 ▼
Claude Code  ──reads──  .claude/agents/support-agent.md  (persona + tool list)
     │
     ├──────────────────────────────────────────────────────────────────┐
     │  .mcp.json → python3 -m mcp_server.server (stdio)               │
     │       ├── lookup_customer(email)                                 │
     │       ├── get_order(order_id)            ← dates are chaos       │
     │       ├── list_recent_orders(customer_id) ← dates are chaos      │
     │       ├── list_refunds(customer_id)                              │
     │       └── issue_refund(order_id, amount, reason, approved)       │
     └──────────────────────────────────────────────────────────────────┘
     │
     ├── PostToolUse hook (get_order, list_recent_orders)
     │       hooks/normalize_dates.py
     │       Replaces raw output → all ordered_at fields become ISO 8601
     │
     └── PreToolUse hook (issue_refund)
             hooks/refund_policy_gate.py
             Blocks if amount > $500 without manager approval, or reason missing

loop_demo/         — exposes the hidden stop_reason loop (Messages API direct)
audit_demo/        — single-pass vs multi-pass audit; attention dilution visible
session_demo/      — three resumption patterns: --continue, --fork, fresh+brief
```

---

## Setup

```bash
pip3 install mcp anthropic
export ANTHROPIC_API_KEY=sk-ant-...

# Seed the refund log before first use
cd capstones/domain1
python3 audit_demo/reset_refunds.py

# Start Claude Code (auto-loads .mcp.json and .claude/settings.json)
claude
```

**Seeded data:** the refund log ships with 9 pre-built entries across 3 customers — Alice has a suspicious 4-refund cluster in March 2025, Bob is clean, Carla has a high refund rate. The seed file lives at `mcp_server/data/refunds_log.seed.json`. Run `reset_refunds.py` before any test that mutates the log.

---

## Part 1 — The agent

The support-agent persona is defined in `.claude/agents/support-agent.md`. It declares which tools the agent can use, the refund policy (enforced by hooks, not prompts), and a note that order dates "always come back in ISO 8601" — which is true only *because* of the PostToolUse hook.

**Try it:**
```
Show me the last 3 orders for alice@example.com
```

---

## Part 2 — PostToolUse hook (the date chaos fix)

`mcp_server/data/orders.json` contains 30 orders across 3 customers in three different date formats:

| Format | Example | Origin |
|--------|---------|--------|
| Unix epoch integer | `1714521600` | Legacy warehouse system |
| MM/DD/YYYY | `"03/15/2025"` | US-regional fulfilment partner |
| ISO 8601 | `"2025-04-02T14:22:00Z"` | Modern order management system |

`hooks/normalize_dates.py` intercepts `get_order` and `list_recent_orders` responses and converts every `ordered_at` field to ISO 8601 before the model sees it. The source file is untouched.

**`additionalContext` vs `updatedMCPToolOutput`:**

| Field | Effect | When to use |
|-------|--------|-------------|
| `additionalContext` | Appends extra info alongside the original | Augmenting — preserving the raw data |
| `updatedMCPToolOutput` | Replaces the output entirely | Normalising — the model should never see the messy version |

This hook uses `updatedMCPToolOutput`.

---

## Part 3 — PreToolUse hook (the refund gate)

`hooks/refund_policy_gate.py` blocks `issue_refund` calls that violate either rule:

1. `amount_usd > 500` without `manager_approved=true`
2. `reason` missing or empty

**Why a hook, not a prompt instruction:** a prompt has a non-zero failure rate. Even emphatic language ("NEVER", "MUST") can fail in edge cases. For a financial policy, a single miss is a real problem. A PreToolUse hook fires before the tool executes and cannot be bypassed — not even with `--dangerously-skip-permissions`.

**Exit code trap:**
- `exit 0` + JSON stdout → structured `permissionDecision`; agent reads the reason and can replan ✓
- `exit 2` → blocks via stderr; no structured reason
- `exit 1` → **non-blocking**; tool still executes

**Try it:**
```
Issue a $750 refund to alice@example.com for ORD-1002. Reason: shipping was damaged.
```
Then explicitly tell Claude to try anyway — the hook fires regardless.

---

## Part 4 — Loop demo (what Claude Code does for you)

```bash
python3 loop_demo/loop_demo.py
```

Watch the `--- stop_reason: ... ---` trace. The loop runs until `stop_reason == "end_turn"`. Text blocks and tool_use blocks can appear in the same response — the loop never checks content types, only `stop_reason`.

```bash
python3 loop_demo/loop_demo_wrong.py
```

Three anti-patterns, each producing premature termination:

| Anti-pattern | What breaks |
|-------------|-------------|
| `if content[0].type == "text": break` | Exits on commentary before the tool runs |
| `for _ in range(N):` hard cap | Cuts off work at an arbitrary turn count |
| `if any(b.type == "text"...): break` | Same as #1, different spelling |

---

## Part 5 — Task decomposition (multi-pass audit)

The same MCP tools that handle one customer's refund request can audit all three customers — but the way you orchestrate that matters.

**Single-pass (attention dilution):**
```bash
python3 audit_demo/audit_single_pass.py
```
All 30 orders + 9 refunds dumped into one prompt. Watch for uneven depth: one customer gets thorough analysis, another gets a sentence. Some of the 8 seeded patterns will be missed.

**Multi-pass (per-customer workers + synthesis):**
```bash
python3 audit_demo/audit_multipass.py
```
Three parallel workers, one per customer. Each uses tools to fetch only its own customer's data. After all three complete, a synthesis call reads only the compressed findings — not the raw data.

```
┌─ Worker A (CUST-01) ─ tool loop ─ findings_a ─┐
├─ Worker B (CUST-02) ─ tool loop ─ findings_b ─┼─► Synthesis ─► Report
└─ Worker C (CUST-03) ─ tool loop ─ findings_c ─┘
```

**Why it works:** each worker gets a full, undiluted context window for one customer. The synthesis sees compressed findings, not raw data — just like the per-file + integration-pass pattern from Lesson 1.6.

The seeded data has 8 ground-truth findings. Multi-pass should surface all 8. Single-pass typically misses 2–3. See `verification/test_audit_decomposition.md` for the full grep-based pass criteria.

---

## Part 6 — Session state (real cases don't finish in one sitting)

Three patterns for resuming work across sessions. All use the same Alice / ORD-1002 investigation as the substrate. Reset the log before each:

```bash
python3 audit_demo/reset_refunds.py
```

### `--continue` (Session 1 → break → Session 2)
`session_demo/scenario_1_continue.md`

Investigate Alice's refund cluster, step away, come back with the manager's verdict. `claude --continue` loads the full prior context — Claude references the March cluster without re-fetching.

### `--fork-session` (divergent paths from same starting point)
`session_demo/scenario_2_fork.md`

Fork the investigation into an "approved" branch and a "denied" branch. The parent session is untouched. Both forks share `refunds_log.json` — the mandatory reset between branches is the lesson: *forks branch conversation history, not the filesystem.*

### Fresh start + summary injection (cross-machine handoff)
`session_demo/scenario_3_fresh_brief.md`

Open a completely fresh session, paste the handoff brief from `scenario_3_fresh_brief.handoff_brief.md`, and Claude picks up from there using only the brief + fresh tool calls. The brief is ~200 words. A full session transcript is thousands of turns. The brief preserves the signal; the transcript preserves the noise.

---

## Part 7 — Verification

See `verification/REGRESSION.md` for the full A–L test matrix with reset hygiene and run order.

Per-concept guides:
- `verification/test_postool_normalisation.md`
- `verification/test_pretool_policy.md`
- `verification/test_loop_demo.md`
- `verification/test_audit_decomposition.md`
- `verification/test_session_resumption.md`
