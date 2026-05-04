"""
ATTENTION DILUTION DEMO — single-pass audit across all customers.

All orders, refunds, and customer records are loaded into one prompt.
The model is asked to analyse all three customers in a single context.

Watch for:
- Uneven section depth (one customer gets 3x the words another gets)
- Patterns found for one customer but missed for the structurally-identical pattern in another
- Arithmetic errors on totals when the context is long

Compare with audit_multipass.py — same data, different orchestration.

Run from capstones/domain1/:
    python3 audit_demo/audit_single_pass.py
"""

import json
import sys
from pathlib import Path

import anthropic

DATA_DIR = Path(__file__).parent.parent / "mcp_server" / "data"

client = anthropic.Anthropic()


def load(filename: str):
    with open(DATA_DIR / filename) as f:
        return json.load(f)


customers = load("customers.json")
orders = load("orders.json")
refunds = load("refunds_log.json")

PROMPT = f"""You are a refund-audit specialist reviewing all customer accounts.

=== CUSTOMERS (3) ===
{json.dumps(customers, indent=2)}

=== ORDERS (30) ===
{json.dumps(orders, indent=2)}

=== REFUNDS (9) ===
{json.dumps(refunds, indent=2)}

For each customer produce a section with:
  - Refund rate (refunds / orders, as a percentage)
  - Temporal clustering (any window of 7 or fewer days containing 3 or more refunds?)
  - Magnitude (total refunded, average refund value)
  - Policy gaps (refunds over $500 processed without manager_approved=true?)
  - Risk rating: low / medium / high, with one-sentence justification

End with an "Overall observations" section noting any cross-customer patterns.

Use specific order IDs, refund IDs, amounts, and dates as evidence for each finding.
"""

print("Running single-pass audit (all customers, one context)...")
print("=" * 60)

response = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=2048,
    messages=[{"role": "user", "content": PROMPT}],
)

print(response.content[0].text)
print()
print(f"stop_reason: {response.stop_reason}")
print(f"input tokens: {response.usage.input_tokens} | output tokens: {response.usage.output_tokens}")
