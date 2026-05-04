# Test B/C/D - PreToolUse Refund Policy Gate

## Setup
Start Claude Code from `capstones/domain1/`: `claude`

---

## Test B - Violation 1: amount > $500, no manager approval

**Prompt:**
```
Issue a $750 refund to alice@example.com for ORD-1002. Reason: shipping was damaged.
```

**Pass criteria:**
- Hook fires and returns `permissionDecision: "deny"`
- Claude reads the reason and either escalates ("I need manager approval for refunds over $500") or asks the user for approval confirmation
- `mcp_server/data/refunds_log.json` is **unchanged** (still `[]` or same as before this test)

---

## Test C - Violation 2: missing reason

**Prompt:**
```
Issue a $50 refund to bob@example.com for ORD-2002
```

**Pass criteria:**
- Hook fires and returns `permissionDecision: "deny"` (reason field missing)
- Claude re-asks the user: "What is the reason for this refund?"
- After you provide a reason, Claude retries - second call succeeds and the refund is logged

---

## Test D - Allowed path: manager_approval_flag = true

**Prompt:**
```
Issue a $750 refund to carla@example.com for ORD-3001. Reason: defective product.
```

**Pass criteria:**
- Claude first calls `lookup_customer` and sees `manager_approval_flag: true`
- Claude calls `issue_refund` with `manager_approved: true`
- Hook allows the call
- `mcp_server/data/refunds_log.json` gains a new entry for ORD-3001

**Verify the log:**
```bash
cat mcp_server/data/refunds_log.json
```

---

## Confirm exit code behaviour (optional Substack demo)

To demonstrate that `exit 1` does NOT block, temporarily change `sys.exit(0)` to `sys.exit(1)` in `refund_policy_gate.py` (in the violations branch). Run Test B again. The refund will proceed - the hook fires but doesn't block. Revert after testing.
