# Tests H & I - Audit Decomposition (Lesson 1.6)

## Setup
```bash
python3 audit_demo/reset_refunds.py
```

---

## Test H - Single-pass audit (attention dilution)

```bash
python3 audit_demo/audit_single_pass.py | tee audit_demo/transcript_single_pass.txt
```

**What to look for:**
- Uneven section lengths - does Alice get 3× the analysis Bob does (or vice versa)?
- Missing findings - are any of the 8 ground-truth patterns absent?
- Arithmetic errors - does it miscalculate Alice's $1,212 total or Carla's $2,430?
- Inconsistency - does it flag a pattern for one customer but miss the structurally similar pattern in another?

**Pass criterion:** output misses at least 2 of 8 findings, OR one customer's section is visibly much longer or shorter than the others.

Note: single-pass results vary run-to-run. If it happens to find everything once, run again or review section depth instead of finding count.

---

## Test I - Multi-pass audit (per-customer workers + synthesis)

```bash
python3 audit_demo/reset_refunds.py
python3 audit_demo/audit_multipass.py | tee audit_demo/transcript_multipass.txt
```

**What to look for:**
- "Worker complete: CUST-XX" lines showing parallel execution
- Each customer gets comparable analysis depth
- All 8 ground-truth findings in the synthesised output
- Cross-customer observations in the synthesis that weren't in any single worker output (e.g. "Alice and Carla both show patterns suggesting…")

**Pass criterion:** all 8 findings present; synthesis contains cross-customer insight.

**Automated finding check:**

Note: keywords for F-B2 and F-C3 were extended for claude-sonnet-4-6 phrasing.
If switching models, re-run and check for MISSING findings before updating keywords.

```bash
python3 -c "
transcript = open('audit_demo/transcript_multipass.txt').read().lower()
findings = {
    'F-A1 Alice cluster':         any(x in transcript for x in ['7-day', 'cluster', 'march 1']),
    'F-A2 Alice magnitude':       any(x in transcript for x in ['1,212', '1212']),
    'F-A3 Alice approval gap':    any(x in transcript for x in ['manager approv', 'without approval']),
    'F-B1 Bob rate':              any(x in transcript for x in ['10%', '1 refund', '10 percent']),
    'F-B2 Bob clean':             any(x in transcript for x in ['no cluster', 'no temporal', 'clean', 'low risk', 'no concern', 'watchlist']),
    'F-C1 Carla rate':            any(x in transcript for x in ['40%', '4/10', '40 percent']),
    'F-C2 Carla magnitude':       any(x in transcript for x in ['2,430', '2430', 'high-value', 'high value']),
    'F-C3 Carla reasons':         any(x in transcript for x in ['different reason', 'varied', 'multiple reason', 'defective', 'wrong item', 'fulfillment']),
}
hits = sum(findings.values())
print(f'{hits}/8 findings detected')
for name, found in findings.items():
    status = 'FOUND' if found else 'MISSING'
    print(f'  {status}: {name}')
"
```

---

## The teaching moment (for Substack)

> "I asked Claude to audit three customers' refund patterns in one prompt. It found five of the eight patterns I'd planted in the data. Split into three focused passes - one per customer, then a synthesis - it found all eight. And in the synthesis section, it spotted a cross-customer pattern I hadn't even flagged as a finding."

Side-by-side comparison: token counts (single-pass often uses fewer input tokens but misses more); finding counts; section depth. This is the attention-dilution principle from Lesson 1.6 made visible in real output.
