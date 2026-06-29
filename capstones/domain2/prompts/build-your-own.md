# Build Your Own Household Agent

Paste the prompt below into Claude Code in an empty folder to build a customized
household operations agent for your home. It goes one step at a time and stops to ask
before moving on. You won't read or write any code.

Use this repo as reference: https://github.com/danieleugenewilliams/cc4nc

---

## The prompt

```
You are helping me build a household operations agent for my home using Claude Code. Everything stays local on my machine. I don't write code, so explain each step in plain language and stop when you need input from me.

Use this repository as your reference for how the pieces fit together, but build mine customized to my household rather than copying it as-is:
https://github.com/danieleugenewilliams/cc4nc/tree/main/capstones/domain2

1. Ask me which categories I want to track: home maintenance, recurring tasks like groceries and appointments, subscriptions, or all three.

2. Set up the data based on what I tell you. Ask me for 3 to 5 real items in each category I'm tracking, like my actual furnace filter and my actual subscriptions. Use full dates in YYYY-MM-DD form.

3. Give the agent its tools, and write the description of each one so it clearly says when to use it. The two that matter most: one tool for searching by name or keyword, and a separate tool for timing questions like what's overdue or due soon. Make their descriptions clearly different so the agent never confuses the two.

4. Add a check that runs before anything new is added and blocks a duplicate no matter what. Explain to me what this check is and why it's stronger than just telling the agent to be careful.

5. Give the agent simple routing rules so it sends name or keyword questions to one tool and timing questions to the other.

Go one step at a time. Stop after each step and wait for me to confirm before continuing. When it's all running, show me the three commands I'll use most: "What's overdue?", "What's due this week?", and "List all my subscriptions."
```

---

## Notes for non-coders

**What you're building:** A small program that sits on your computer and talks to
Claude Code. When you ask Claude "what's overdue?", Claude asks the program, the program
reads your household data, and Claude gives you the answer. You never have to open or
edit it yourself.

**What you need installed:**
- Claude Code (claude.ai/code or the desktop app)
- Python 3.9 or later (run `python3 --version` in Terminal to check)
- One library: run `pip install mcp fastmcp` in Terminal

**What stays on your machine:** All of your data lives in plain files in the folder you
create. Nothing is sent to any cloud service. The agent reads and writes those files
directly.

**The one decision that matters most:** Your agent gets two tools that sound alike but
do different jobs. One searches by name or keyword ("show me everything with HVAC in
it"). The other answers timing questions ("what's due in the next 30 days"). If their
descriptions are vague, the agent picks the wrong one and gives you confusing answers.
That is why step 3 is the one to slow down on, and it is the central lesson of the
Domain 2 architecture curriculum.

**Keeping it simple:** This starter version is single-user, built for one household's
shared list. That is all most people need, and it is the easiest thing to run from the
command line or wire up to your phone later. The full reference build in this repo also
shows how to scope what different people can see; add that once the basics are working.

**Enterprise caveat:** This build uses Claude Code (the CLI or desktop app). If you use
Claude through a company-managed deployment, the pieces this relies on may not be
available in your environment. Check with your IT or AI team before proceeding.

**Same discipline, different domain:** If you've read the Othellobot health agent series
(claudecodefornoncoders.substack.com), this is the same pattern applied to household
operations instead of health tracking. One local record, tools with clear descriptions,
a check for the rules that matter. The principles transfer.
