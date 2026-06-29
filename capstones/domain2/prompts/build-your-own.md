# Build Your Own Household Agent

Paste the prompt below into Claude Code in an empty folder to build a customized
household operations agent for your home. The agent will guide you through each step
and stop to ask before moving on.

Use this repo as reference: https://github.com/danieleugenewilliams/cc4nc

---

## The prompt

```
You are helping me build a household operations agent for my home using Claude Code.
Everything stays local on my machine. I don't write code, so explain each step in plain
language and stop when you need input from me.

Use this repo as your reference for how the pieces fit together, but build mine
customized to my household rather than copying it as-is:
https://github.com/danieleugenewilliams/cc4nc/tree/main/capstones/domain2

1. Ask me who lives in the house and what roles they should have (admin vs. member).
   Then ask me which categories of things I want to track: home maintenance schedules,
   recurring tasks (groceries, appointments), subscriptions, or all three.

2. Set up the JSON data files based on what I tell you. Seed them with real items from
   my house — ask me for 3–5 actual items in each category I'm tracking. Use
   YYYY-MM-DD dates.

3. Build the MCP server (mcp_server/server.py) with descriptions that clearly tell the
   agent when to use each tool. The two most important tools to get right:
   - find_items: for searching by name or keyword, regardless of timing
   - get_items_due: for time-based questions (what's overdue, what's coming up)
   Make them clearly different from each other in the descriptions.

4. Set up the .mcp.json with environment variable expansion so I can switch users
   by setting HOUSEHOLD_CURRENT_USER before opening Claude Code.

5. Create a PreToolUse hook that checks for duplicate items before any add_item call.
   Explain what a hook does and why it's stronger than just telling the agent to check.

6. Create a .claude/agents/household-agent.md persona that routes questions to the
   right tool based on whether the question is about a name/keyword or about timing.

Go one step at a time. Stop after each step and wait for me to confirm before continuing.
When everything is running, show me the three commands I'll use most:
  - "What's overdue?"
  - "What's due this week?"
  - "List all my subscriptions"
```

---

## Notes for non-coders

**What you're building:** A small program that sits on your computer and talks to
Claude Code. When you ask Claude "what's overdue?", Claude asks the program, the
program reads your household data, and Claude formats the answer.

**What you need installed:**
- Claude Code (claude.ai/code or the desktop app)
- Python 3.9 or later (`python3 --version` in Terminal to check)
- The MCP library: run `pip install mcp fastmcp` in Terminal

**What stays on your machine:** All data lives in JSON files in the folder you
create. Nothing is sent to any cloud service. The agent reads and writes those files
directly.

**The one design decision that matters most:** The `find_items` and `get_items_due`
tools sound similar but do completely different jobs. `find_items` is a keyword search
("show me everything with 'HVAC' in the name"). `get_items_due` is a calendar lookup
("show me everything due in the next 30 days"). If their descriptions are vague, the
agent picks the wrong one and gives you confusing answers. This is the central lesson
from the Domain 2 architecture curriculum — and why step 3 above is the most important.

**Enterprise caveat:** This build uses Claude Code (the CLI or desktop app). If you
use Claude via a company-managed deployment, MCP servers and hooks may not be available
in your environment. Check with your IT or AI team before proceeding.

**Same discipline, different domain:** If you've read the Othellobot health agent
series (claudecodefornoncoders.substack.com), this is the same architectural pattern
applied to household operations instead of health tracking. One record, local data,
tools with clear descriptions, hooks for enforcement. The principles transfer.
```
