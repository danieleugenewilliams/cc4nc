# Domain 2 Capstone Walkthrough

This file is a prompt. Copy everything below the divider and paste it into a fresh Claude Code session. Claude will clone the repo, install dependencies, and walk you through the household operations agent demos interactively.

---

You are guiding me through the Claude Code for Non-Coders Domain 2 capstone. I just finished reading the Domain 2 Architecture series and want to run the demos for all five lessons.

Work through the steps below in order. After each step, explain what just happened in plain English. Pause only at the explicit `PAUSE` markers.

## Step 1 — Verify prerequisites

Check that `python3` is available. If `git` is available, we will clone the repo. If not, note it and I will need to download it manually.

Check whether `mcp` and `fastmcp` are installed:
```
python3 -c "import mcp; print('mcp ok')" 2>/dev/null || echo "mcp not installed"
```

If not installed, run:
```
pip3 install mcp fastmcp
```

## Step 2 — Get the repo

If `cc4nc` does not already exist:
```
git clone https://github.com/danieleugenewilliams/cc4nc.git cc4nc
```

If it does exist, run `git -C cc4nc pull` to update it.

Change into the capstone directory:
```
cd cc4nc/capstones/domain2
```

## Step 3 — Read the architecture

Read `README.md` so you have full context. Do not summarize it back to me.

## Step 4 — Restore seed data

```
python3 reset_items.py
```

Explain what this does and why we run it first.

## Step 5 — Lesson 2.1 demo: misrouting (broken descriptions)

This is the central lesson. You are going to show me what happens when two tools have descriptions that are too similar.

1. Edit `.mcp.json` and change `mcp_server/server.py` to `mcp_server/server_broken.py` in the `args` field.
2. Show me the broken descriptions in `server_broken.py` side by side with the fixed ones in `server.py`.
3. Explain why near-identical descriptions cause misrouting — the model cannot differentiate the tools from the description alone.

PAUSE — tell me what I'm about to see, then ask me to ask the agent: "What household maintenance is coming up this month?"

After I report what happened (which tool the agent called):
4. Revert `.mcp.json` back to `server.py`.
5. Tell me to ask the same question again and compare the tool choice.

Explain: fix the description before adding routing classifiers or restructuring the architecture. The description is the primary signal.

## Step 6 — Lesson 2.2 demo: error categories

Run each of these scenarios and explain what type of error each one is:

**Transient (retryable):**
```
touch mcp_server/data/items.json.lock
```
Tell me to ask the agent: "What's overdue?" — it should get a transient error. Then:
```
rm mcp_server/data/items.json.lock
```

**Validation (fix input, retry):**
Tell me to ask: "Add a task: clean the gutters, due 07/15/2026, maintenance." The agent should catch the bad date format, correct it to YYYY-MM-DD, and retry.

**Business rule (recurring items advance, not delete):**
Tell me to ask: "Log ITEM-001 as complete." Show me that items.json still has the HVAC filter but with an advanced due date. Run:
```
python3 -c "
import json
items = json.load(open('mcp_server/data/items.json'))
hvac = next(i for i in items if i['id'] == 'ITEM-001')
print('HVAC due date after completion:', hvac['due_date'])
"
```
Reset before continuing: `python3 reset_items.py`

**Permission (escalate, do not retry):**
```
export HOUSEHOLD_CURRENT_USER=member
```
Restart the MCP server and tell me to ask: "Log ITEM-006 as complete." Explain why the member cannot complete an admin's private item.
```
unset HOUSEHOLD_CURRENT_USER
```

## Step 7 — Lesson 2.3 demo: the hook enforcement

This is the "tool_choice is a request; a hook is a guarantee" demonstration.

Tell me to ask the agent: "Add a maintenance item called HVAC filter, due 2026-09-01."

Show me `hooks/check_before_add.py` and explain:
- In the Messages API, `tool_choice: {"type": "tool", "name": "find_items"}` asks the model to call `find_items` first
- The PreToolUse hook in `.claude/settings.json` runs independently, regardless of what the model did
- If the agent skips `find_items` and tries to add a duplicate directly, the hook catches it

Run the hook manually to show how it works:
```
echo '{"tool_input": {"name": "HVAC filter replacement"}}' | python3 hooks/check_before_add.py; echo "exit: $?"
echo '{"tool_input": {"name": "Clean gutters"}}' | python3 hooks/check_before_add.py; echo "exit: $?"
```

Explain exit code 2 vs exit code 0.

## Step 8 — Lesson 2.4 demo: MCP scoping and env vars

Open `.mcp.json` and explain:
- `${HOUSEHOLD_CURRENT_USER:-admin}` — what `:-` means (default if unset)
- `${HOUSEHOLD_DB_PATH:-}` — empty default, server falls back to its own data directory
- Why this is in `.mcp.json` (project scope, shared) not `settings.local.json` (user scope, private)

Show how to switch users:
```
export HOUSEHOLD_CURRENT_USER=member
```

Tell me to ask: "List all my subscriptions." Point out that the gym membership (member's private sub) appears, but it would be hidden from admin-only. Explain the visibility filtering logic in `list_subscriptions`.

```
unset HOUSEHOLD_CURRENT_USER
```

## Step 9 — Lesson 2.5 demo: resources vs tools

Open `resources/maintenance_templates.json` and explain:
- This is an MCP resource, not a tool
- Resources are application-driven and read-only — no model overhead, no side effects
- Use resources for reference data that rarely changes (maintenance schedules)
- Use tools for operations that read or write dynamic data (items.json)

Show the distinction: the agent can read maintenance schedules from the resource without a tool call; it uses `get_items_due` to check what's actually tracked.

## Step 10 — Run the full verification suite

Walk through `verification/REGRESSION.md` and run each test in order. Explain what each test demonstrates before running it. Call out the Domain 3 bridge at Test I: "tool_choice is a request; a hook is a guarantee."

## Done

After all tests pass:
1. Reset to a clean state: `python3 reset_items.py`
2. Show me the build-your-own prompt in `prompts/build-your-own.md`
3. Ask me: "What would you track in your household?"
