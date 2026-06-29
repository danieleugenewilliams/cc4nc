# Household Operations Agent — Domain 2 Capstone

This is the runnable capstone for Domain 2 of the CC4NC Architecture curriculum.
It demonstrates all five Domain 2 lessons in a single household tool you can actually use.

**Series:** [Claude Code for Non-Coders](https://claudecodefornoncoders.substack.com) — paid Architecture track

---

## What it does

Tracks home maintenance schedules, recurring tasks, and subscriptions. Ask it what's
overdue, what's coming up, or log something as done. Multi-user: household-visible
items are shared; private items are scoped to their owner.

This is not a replacement for Notion, Tody, or Rocket Money. Those tools are excellent
for their purpose. This build exists to show the architectural decisions that make an
AI agent reliable — and to give you something useful while doing it.

---

## Domain 2 lesson map

| Lesson | What it demonstrates | Where to look |
|--------|----------------------|---------------|
| **2.1 Tool descriptions** | `find_items` vs `get_items_due` — clear boundaries prevent misrouting | `server.py` lines 50–95 vs `server_broken.py` |
| **2.2 Error categories** | Transient (lock file) · Validation (bad date) · Business (recurring advances) · Permission (private item) | `server.py` — all four returned with `isError`, `errorCategory`, `isRetryable` |
| **2.3 Enforcement** | PreToolUse hook blocks `add_item` if a duplicate exists — regardless of what the model did | `hooks/check_before_add.py` + `.claude/settings.json` |
| **2.4 MCP scoping** | `${HOUSEHOLD_CURRENT_USER:-admin}` in `.mcp.json` — env var expansion, `:-` default syntax | `.mcp.json` |
| **2.5 Exploration** | Grep entry points → Read to trace flows — how this codebase was built | `verification/REGRESSION.md` Test A |

**The Domain 3 bridge:** Test I in REGRESSION.md shows the clearest lesson in the
whole capstone: `tool_choice` (Messages API) asks the model to call `find_items` before
`add_item`. The PreToolUse hook *guarantees* it runs. That distinction — request vs.
guarantee — is the foundation of Domain 3 reliability patterns.

---

## Quickstart

```bash
# 1. Install dependencies
pip install mcp fastmcp

# 2. Open Claude Code in this directory
cd capstones/domain2
claude  # or open in the desktop app

# 3. Ask it something
"What's overdue?"
"What household maintenance is coming up this month?"
"List all my subscriptions"
"Log ITEM-001 as complete"
```

### Switch users

```bash
export HOUSEHOLD_CURRENT_USER=member
# restart Claude Code / MCP server for env var to take effect
```

---

## File structure

```
capstones/domain2/
├── .mcp.json                          # Lesson 2.4 — env var expansion
├── reset_items.py                     # Restore seed data before tests
├── mcp_server/
│   ├── server.py                      # Production — fixed descriptions
│   ├── server_broken.py               # Lesson 2.1 misrouting demo
│   └── data/
│       ├── items.json                 # Runtime (git-ignored)
│       ├── subscriptions.json
│       ├── users.json
│       ├── completion_log.json        # Runtime (git-ignored)
│       └── seed/                      # Tracked — source of truth
├── resources/
│   ├── maintenance_templates.json     # Lesson 2.4 — MCP resource (not a tool)
│   └── subscription_categories.json
├── .claude/
│   ├── settings.json                  # Lesson 2.3 — PreToolUse hook config
│   └── agents/household-agent.md     # Agent persona + tool routing rules
├── hooks/
│   └── check_before_add.py           # Lesson 2.3 — duplicate prevention
├── verification/
│   └── REGRESSION.md                 # 10 tests, one per lesson concept
└── prompts/
    └── build-your-own.md             # Subscriber paste-in prompt
```

---

## Seeded data

**Items (items.json):**
- HVAC filter replacement — overdue ~3 months (due 2026-03-15)
- Smoke detector battery test — due June 28
- Weekly grocery run — due June 23 (recurring weekly)
- Water heater flush — due September 1
- Car oil change — due August 15 (owned by member)
- Home office equipment audit — due July 15 (admin private)

**Subscriptions (subscriptions.json):**
- Gym membership — renews July 5 (member private) — $45/mo
- Netflix — renews July 15 — $22.99/mo
- Cloud backup — renews July 20 — $9.99/mo
- Spotify Family — renews August 1 — $17.99/mo

---

## Running the misrouting demo (Lesson 2.1)

```bash
# 1. Edit .mcp.json — change server.py to server_broken.py in args
# 2. Restart Claude Code
# 3. Ask: "What household maintenance is coming up this month?"
# 4. Watch it call find_items(query="maintenance") instead of get_items_due
# 5. Revert .mcp.json to server.py and ask the same question
```

The descriptions in `server_broken.py`:
```python
def find_items(...):
    """Retrieves household items."""     # <- identical

def get_items_due(...):
    """Retrieves household items."""     # <- identical
```

The fix in `server.py` establishes clear, non-overlapping purpose boundaries. That's
Lesson 2.1: fix the description before adding routing classifiers or splitting tools.

---

## Running verification tests

```bash
python3 reset_items.py   # always run this first
# then follow each test in verification/REGRESSION.md
```

All 10 tests must pass before the article publishes.

---

## Related

- **Othellobot health agent** (free): [claudecodefornoncoders.substack.com](https://claudecodefornoncoders.substack.com)
  Same discipline — local SQLite, skills, MCP bridge, two front doors — applied to
  health and fitness tracking. This capstone is the same pattern applied to household
  operations, and explained through the architecture curriculum lens.
- **Build your own:** `prompts/build-your-own.md` — paste into Claude Code to build a
  customized version for your household from scratch.
