# Claude Code for Non-Coders

Companion code for [Claude Code for Non-Coders](https://claudecodefornoncoders.substack.com/) — Daniel Williams' newsletter on using coding agents effectively without losing the judgment that makes you valuable.

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

## Quickstart

If you have Claude Code installed, the fastest way to run the Domain 1 capstone is to copy [`prompts/run-domain1-capstone.md`](prompts/run-domain1-capstone.md) and paste it into Claude Code. Claude will clone the repo, install dependencies, and walk you through each demo.

For manual setup, see the capstone README.

## License

MIT. See [`LICENSE`](LICENSE).

---

Daniel Williams advises clients about AI tools, strategy, and human resilience at [automationresilience.com](https://automationresilience.com).
