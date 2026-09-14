# Claude Code for Non-Coders

Companion code for [Claude Code for Non-Coders](https://claudecodefornoncoders.substack.com/) - Daniel Williams' newsletter on using coding agents effectively without losing the judgment that makes you valuable.

This repo holds the runnable builds referenced in the published articles.

## Capstones

### Domain 1: Customer Support Agent

A working customer support agent that handles refunds. Demonstrates the architectural pieces covered across Lessons 1.1 through 1.7:

- The `stop_reason` agentic loop (L1.1)
- Multi-tool MCP server with five tools (L1.2 / L1.3 territory)
- PostToolUse data normalization (L1.5)
- PreToolUse policy enforcement (L1.4)
- Multi-pass decomposition for cross-customer audits (L1.6)
- Three patterns for session resumption (L1.7)

See [`capstones/domain1/README.md`](capstones/domain1/README.md) for the full walkthrough.

### Domain 3: The Self-Hosted Review Gate

A code review gate that runs `claude -p --bare` on a machine you own, gated on severity, reporting its real cost. No GitHub Actions, no managed runner. Ties together Lessons 3.4 through 3.6:

- You choose what the gate blocks on (L3.4)
- The gate is a runnable pass/fail check, not "looks done" (L3.5)
- An independent reviewer that does not inherit the context that wrote the code (L3.6)

See [`capstones/domain3/README.md`](capstones/domain3/README.md) for setup, the planted defect, and the stability loop.

## Skills

Reusable Claude Code skills from the newsletter, ready to copy into `~/.claude/skills/`:

- [`build-review-loop`](skills/build-review-loop/): set up a builder–reviewer loop on a repo, two agent sessions working a backlog through pull requests while nobody is watching, with GitHub labels as the state machine.

See [`skills/README.md`](skills/README.md) for install instructions.

## Quickstart

If you have Claude Code installed, the fastest way to run the Domain 1 capstone is to copy [`prompts/run-domain1-capstone.md`](prompts/run-domain1-capstone.md) and paste it into Claude Code. Claude will clone the repo, install dependencies, and walk you through each demo.

For manual setup, see the capstone README.

## License

MIT. See [`LICENSE`](LICENSE).

---

Daniel Williams advises clients about AI tools, strategy, and human resilience at [automationresilience.com](https://automationresilience.com).
