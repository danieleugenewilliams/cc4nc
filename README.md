# Claude Code for Non-Coders

Companion code for the [Claude Code for Non-Coders](https://claudecodefornoncoders.substack.com/) newsletter.

Each capstone is a working build that demonstrates the architectural concepts from the [Claude Certified Architect (Foundations)](https://www.anthropic.com) curriculum — written to be readable by anyone, not just engineers.

---

## Domain 1 Capstone — Customer Support Agent

Located in `capstones/domain1/`.

Demonstrates six concepts from Domain 1 (Agentic Architecture & Orchestration):

| Concept | Where |
|---------|-------|
| `stop_reason`-driven agentic loop | `loop_demo/loop_demo.py` |
| PostToolUse normalisation hook | `hooks/normalize_dates.py` |
| PreToolUse policy gate hook | `hooks/refund_policy_gate.py` |
| Multi-tool agent configuration | `.claude/agents/support-agent.md` |
| Multi-pass task decomposition | `audit_demo/` |
| Session state & resumption | `session_demo/` |

### Quick start

```bash
pip install mcp anthropic
export ANTHROPIC_API_KEY=sk-ant-...

cd capstones/domain1
python3 audit_demo/reset_refunds.py   # seed the refund log
claude                                 # start Claude Code
```

### Run the loop demo (no Claude Code needed)

```bash
cd capstones/domain1
python3 loop_demo/loop_demo.py        # correct stop_reason loop
python3 loop_demo/loop_demo_wrong.py  # three anti-patterns
```

See `capstones/domain1/README.md` for the full walkthrough.

---

## Newsletter

[claudecodefornoncoders.substack.com](https://claudecodefornoncoders.substack.com/)

---

## License

MIT — copy, modify, and use freely.
