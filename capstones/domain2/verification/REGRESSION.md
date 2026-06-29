# Domain 2 Capstone — Verification Tests

Run `python3 reset_items.py` from the capstone root before any test that mutates data.

Each test maps to the Domain 2 lesson it demonstrates. Pass = behavior matches expected output.
Fail = investigate root cause; do not skip or mark passing until the behavior is correct.

---

## Setup

```bash
cd capstones/domain2
pip install mcp fastmcp          # if not already installed
python3 reset_items.py           # restore seed data
```

Open Claude Code in `capstones/domain2/` so `.mcp.json` and `.claude/settings.json` load.

---

## Test A — Misrouting demo (server_broken.py) | Lesson 2.1

**What it tests:** Near-identical descriptions cause the agent to misroute a date question.

**Setup:** Edit `.mcp.json` to point `args` at `mcp_server/server_broken.py`.

**Prompt:**
```
What household maintenance is coming up this month?
```

**Expected (broken):** Agent calls `find_items(query="maintenance")` — keyword search.
Returns items containing "maintenance" in their name regardless of due date.
HVAC filter (overdue 3 months) and water heater flush (2 months away) appear together
with no date context. The answer is misleading.

**Pass condition:** Agent routes to `find_items`, not `get_items_due`.

**Restore:** Revert `.mcp.json` to `server.py` before running Test B.

---

## Test B — Description fix (server.py) | Lesson 2.1

**What it tests:** Correct descriptions route the same question to the right tool.

**Prompt:**
```
What household maintenance is coming up this month?
```

**Expected (fixed):** Agent calls `get_items_due(days_ahead=30)` or similar.
Returns items sorted by due date with timing context: HVAC filter (overdue since March),
weekly grocery run (July 1), smoke detector (July 6), home office audit (July 15).
Agent describes HVAC as overdue, not just upcoming. The key distinction from Test A is
that the agent chose a date-window tool, not a keyword-search tool.

**Pass condition:** Agent routes to `get_items_due`, not `find_items`.

---

## Test C — Overdue items | Lesson 2.1 + 2.2

**Prompt:**
```
What's overdue?
```

**Expected:** Agent calls `get_items_due(days_ahead=-1)`.
Returns HVAC filter (due 2026-03-15, overdue ~3 months). Agent labels it as overdue
with how long, not just the date string.

**Pass condition:** HVAC filter appears; smoke detector and water heater do not.

---

## Test D — Validation error: bad date format | Lesson 2.2

**Prompt:**
```
Add a new task: clean the gutters, due 07/15/2026, maintenance category.
```

**Expected:** Agent calls `add_item(due_date="07/15/2026", ...)`.
Server returns `{ "isError": true, "errorCategory": "validation", "isRetryable": true }`.
Agent corrects the format to "2026-07-15" and retries. Second call succeeds.

**Pass condition:** Error is caught, format is corrected, item is added on retry.

**Cleanup:** Run `python3 reset_items.py` after this test.

---

## Test E — Validation error: missing recurring_interval_days | Lesson 2.2

**Prompt:**
```
Add a recurring task: water the garden, maintenance, due 2026-07-01, recurring.
```

**Expected:** Agent calls `add_item(recurring=True)` without `recurring_interval_days`.
Server returns validation error. Agent asks for the interval, then retries with the
interval provided.

**Pass condition:** Error returned, agent asks for clarification, retry succeeds.

**Cleanup:** Run `python3 reset_items.py`.

---

## Test F — Transient error: locked data file | Lesson 2.2

**Setup:** Create the lock file.
```bash
touch mcp_server/data/items.json.lock
```

**Prompt:**
```
What's due this week?
```

**Expected:** Server returns `{ "isError": true, "errorCategory": "transient", "isRetryable": true }`.
Agent informs user the data is temporarily locked and suggests retrying.

**Pass condition:** `isError: true`, `errorCategory: "transient"` in response.

**Cleanup:** Remove the lock and verify items load again.
```bash
rm mcp_server/data/items.json.lock
```

---

## Test G — Business rule: recurring item advances, not deleted | Lesson 2.2

**Prompt:**
```
Log ITEM-001 as complete.
```

**Expected:** `log_completion("ITEM-001")` succeeds. HVAC filter due date advances by 90
days from 2026-03-15 → 2026-06-13. Item is NOT removed from items.json. Completion is
logged in completion_log.json. Response includes `next_due` field.

**Verify:**
```bash
python3 -c "
import json
items = json.load(open('mcp_server/data/items.json'))
hvac = next(i for i in items if i['id'] == 'ITEM-001')
print('due_date:', hvac['due_date'])  # expect 2026-06-13
log = json.load(open('mcp_server/data/completion_log.json'))
print('log entries:', len(log))       # expect 1
"
```

**Pass condition:** `due_date` is 90 days after 2026-03-15; item still present; log has 1 entry.

**Cleanup:** Run `python3 reset_items.py`.

---

## Test H — Permission error: member can't modify admin's private item | Lesson 2.2

**Setup:** Set the current user to member.
```bash
export HOUSEHOLD_CURRENT_USER=member
```
Restart the MCP server (re-open Claude Code or `/mcp restart`).

**Prompt:**
```
Log ITEM-006 as complete.
```
(ITEM-006 is "Home office equipment audit", owned by admin, visibility private)

**Expected:** `log_completion("ITEM-006")` returns `{ "isError": true, "errorCategory": "permission", "isRetryable": false }`.
Agent explains this is a private item owned by admin and suggests switching users.

**Pass condition:** Permission error returned; item is NOT marked complete in items.json.

**Cleanup:**
```bash
unset HOUSEHOLD_CURRENT_USER
```

---

## Test I — Duplicate prevention hook | Lesson 2.3

**Prompt:**
```
Add a maintenance item called HVAC filter, due 2026-09-01.
```

**Expected:** `hooks/check_before_add.py` fires before `add_item`. Hook finds
"HVAC filter replacement" (ITEM-001) in items.json and blocks the call with exit code 2.
Agent receives the block message and informs the user that a similar item already exists.

**Pass condition:** Hook blocks the call; `add_item` is never executed; items.json unchanged.

**What this demonstrates (Lesson 2.3):**
- `tool_choice` in the Messages API asks the model to call `find_items` first — the model can be bypassed
- This PreToolUse hook runs regardless of what the model did or didn't do
- "tool_choice is a request; a hook is a guarantee"

---

## Test J — Subscription visibility by user role | Lesson 2.4

**With admin user (default):**

**Prompt:**
```
List all active subscriptions.
```

**Expected:** All 5 subscriptions appear, including the gym membership (member's private sub)
and home security monitoring (SUB-005, admin's private sub).
Sorted by renewal date: gym (July 5), Netflix (July 15), cloud backup (July 20),
home security (Aug 10), Spotify (Aug 1).

**Pass condition (admin):** 5 subscriptions.

---

**Switch to member user:**
```bash
export HOUSEHOLD_CURRENT_USER=member
```
Restart MCP server.

**Same prompt.**

**Expected:** 4 subscriptions appear — gym (member-owned private), Netflix, cloud backup,
and Spotify (all household-visible). Home security monitoring (SUB-005, admin-private)
is hidden from member.

**Pass condition (member):** 4 subscriptions. SUB-005 must NOT appear.

**Cleanup:**
```bash
unset HOUSEHOLD_CURRENT_USER
```

---

## Summary checklist

| Test | Lesson | Status |
|------|--------|--------|
| A — Misrouting demo (broken server) | 2.1 | ☐ |
| B — Description fix (production server) | 2.1 | ☐ |
| C — Overdue items query | 2.1 + 2.2 | ☐ |
| D — Validation: bad date format + retry | 2.2 | ☐ |
| E — Validation: missing recurring interval | 2.2 | ☐ |
| F — Transient: locked file | 2.2 | ☐ |
| G — Business rule: recurring item advances | 2.2 | ☐ |
| H — Permission: member blocked from admin private item | 2.2 | ☐ |
| I — Duplicate hook blocks add_item | 2.3 | ☐ |
| J — Subscription visibility by role | 2.4 | ☐ |

All 10 must pass before publishing the capstone article.
