# CLAUDE.md — CC4NC Public Repo

This is the public companion repository for [Claude Code for Non-Coders](https://claudecodefornoncoders.substack.com/) by Daniel Williams. It holds the runnable capstone builds referenced in the published articles.

## Repo structure

```
capstones/domain1/   — Domain 1 customer support agent (complete)
capstones/domain2/   — Domain 2 household operations agent (complete)
capstones/domain3/   — Domain 3 self-hosted review gate (measurements pending)
prompts/             — Subscriber paste-in walkthrough prompts
skills/              — Reusable Claude Code skills (copy into ~/.claude/skills/)
```

## Lesson-to-article mapping

Each Tuesday article in the Architecture series maps to one lesson in the CC4NC Academy (`~/Projects/anthropic_academy`). The series index lives at `~/Documents/Newsletters/architecture-series-index.md`.

| Academy lesson | Article | Capstone |
|---|---|---|
| Domains 1.1–1.7 | Tuesday lessons | `capstones/domain1/` |
| Domains 2.1–2.5 | Tuesday lessons | `capstones/domain2/` |
| Domains 3.4–3.6 | Tuesday lessons | `capstones/domain3/` |

When a domain capstone is complete in the academy, the build goes into `capstones/domain*/` here and the subscriber walkthrough prompt goes into `prompts/`.

## Capstone quality standards

- All existing tests must pass before merging new capstone work
- Runtime data files are excluded from version control; only seed files are tracked
- The subscriber prompt in `prompts/` must be self-contained — a reader with no prior context should be able to paste it into Claude Code and run the full walkthrough
- Run the capstone's reset script before any test that mutates data:
  - Domain 1: `python3 capstones/domain1/audit_demo/reset_refunds.py`
  - Domain 2: `python3 capstones/domain2/reset_items.py`

## Series index updates

After each new lesson publishes, update `~/Documents/Newsletters/architecture-series-index.md` with the live Substack URL. The index is pinned and updated every Tuesday after the piece goes live.
