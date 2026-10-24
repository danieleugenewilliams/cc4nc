# Evidence Log — Self-Hosted Gate on the Real Health Agent

Real runs of the Domain 3 review gate against the published family health agent
(`github.com/danieleugenewilliams/health-fitness-agent`), captured 2026-07-06.
Auth: subscription (`claude /login`), non-bare (see caveat). Model: session model.
These are the numbers for the Tuesday piece. **Do not round away the honesty
caveats** — review is probabilistic and the piece must say so.

## Headline story: three catches, each on the author's own work

The thesis proves itself recursively — every layer of my own work needed an
independent reviewer:

1. **Real finding (the gate).** Gate over the real `server.py` flagged that the
   dashboard server bound to all interfaces (`HTTPServer(('', PORT), ...)`) with
   no auth, exposing the family health SQLite DB to every host on the LAN.
   Verified real (line 1309). This is code readers were told to clone.
2. **Bug in fix v1 (the gate).** Fix v1 (bind `127.0.0.1` + block `data/`).
   Gate found a **real HIGH bug in the fix**: it checked the un-decoded URL
   path, so `/%64ata/health_tracker.db` bypassed it (SimpleHTTPRequestHandler
   unquotes in `translate_path`). Plus a MEDIUM: `/DATA/` case bypass on macOS.
3. **Bug in fix v2 (a PR review).** Fix v2 (resolved, lowercased path) passed
   the gate 2/2. But a **PR review** then caught that the guard only covered
   `do_GET`; inherited `do_HEAD` still returned `200` with the DB's exact size
   (`Content-Length=33`) and mtime. Verified real. Fixed by moving the guard to
   `send_head()` (the single point `do_GET`/`do_HEAD` funnel through). Fix v3
   passes the gate; GET+HEAD both 403 on every bypass vector.

The lesson lands on the author in real time, three times: verification with
fresh eyes caught what I missed at every layer, including inside two successive
security patches. No single reviewer caught everything — the gate caught 1 & 2,
a separate review caught 3. Independence, stacked.

## Measured outcomes (real runs)

| Scenario | Runs | Gate decision | Cost/run | Latency | Notes |
|---|---|---|---|---|---|
| Whole-file review, real `server.py` | 5 | **BLOCK 5/5** | ~$0.15 (first $0.59 w/ cache-creation) | ~80s | net-exposure finding surfaced 4/5; severity jittered med↔high |
| Focused **bind regression** (real bug, `127.0.0.1`→`''`) | 3 | **BLOCK 3/3, HIGH** | $0.04–0.09 | ~15s | deterministic on a small diff |
| Focused **cross-user leak** (labeled staged, dropped `user_id`) | 3 | **BLOCK 3/3, HIGH** | ~$0.04 | ~15s | deterministic |
| **Fix v1** diff | 1 | BLOCK (HIGH: unquote bypass) | $0.25 | 50s | gate caught bug in the fix |
| **Fix v2** diff (corrected) | 2 | **PASS 0/0/0** | ~$0.15 | ~45s | clean |
| GitHub Actions minutes used | — | — | — | — | **0** (self-hosted) |

## The teaching insight (better than a planted bug)

Review is **probabilistic on a sprawling whole-file scan** (findings and severity
jitter run-to-run) but **deterministic on the small diffs a pre-push hook actually
sees** (bind regression and cross-user leak both blocked 3/3 as HIGH). This is why
the gate belongs at the diff, not the whole codebase — and why the honest framing
is "the gate makes the *decision* stable," not "the model finds the same things
every time."

## Caveats (must survive into the piece — truth rule)

- **Non-bare.** `--bare` (the reproducible-CI mode) doesn't read subscription/
  Keychain OAuth in this environment, so runs used `REVIEW_BARE=0`, which loads
  the repo's CLAUDE.md. Findings were code-focused and accurate, but the ideal
  CI setup is `--bare` + `ANTHROPIC_API_KEY`. Flag this, don't hide it.
- **Cost on subscription** is reported (not $0), ~$0.15 whole-file, pennies per
  diff. If the piece quotes a dollar figure, quote the per-diff number.
- **LAN-refusal not demonstrated** in-sandbox (hostname resolved to loopback);
  the loopback bind is guaranteed by code, not shown as LAN-refused.
- The staged cross-user-leak diff is a **labeled demonstration**, never to be
  implied as a real discovery in shipped code.
