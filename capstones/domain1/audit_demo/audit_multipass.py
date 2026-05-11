"""
MULTI-PASS AUDIT — focused per-customer passes + integration synthesis.

Three parallel workers each audit one customer using the tools API
(stop_reason-driven loop, same pattern as loop_demo.py).
Each worker sees only its own customer's data.

After all three complete, a synthesis call reads only the compressed findings
— not the raw orders/refunds — and produces the final report.

Architecture:
    ┌─ Worker A (CUST-01) ─ tool loop ─ findings_a ─┐
    ├─ Worker B (CUST-02) ─ tool loop ─ findings_b ─┼─► Synthesis ─► Report
    └─ Worker C (CUST-03) ─ tool loop ─ findings_c ─┘

Run from capstones/domain1/:
    python3 audit_demo/audit_multipass.py
"""

import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import anthropic

sys.path.insert(0, str(Path(__file__).parent.parent))
from config import MODEL, WORKER_MAX_TOKENS, SYNTHESIS_MAX_TOKENS

sys.path.insert(0, str(Path(__file__).parent))
from audit_tools_bridge import TOOL_SCHEMAS, dispatch

client = anthropic.Anthropic()

WORKER_PROMPT = """You are auditing a single customer for refund patterns or abuse signals.
Use the available tools to gather this customer's data:
  - lookup_customer — get their account details
  - list_recent_orders — get their order history (use limit=10 to get all)
  - list_refunds — get their refund history

Then produce a structured audit section with:
  - Refund rate (refunds / orders, as a percentage)
  - Temporal clustering (any window of 7 or fewer days containing 3 or more refunds?)
  - Magnitude (total refunded, average refund value)
  - Policy gaps (refunds over $500 processed without manager_approved=true?)
  - Risk rating: low / medium / high, with one-sentence justification

Use specific order IDs, refund IDs, amounts, and dates as evidence.

Customer to audit: {customer_id} (email: {email})
"""

SYNTHESIS_PROMPT = """You have received three independent customer audit reports.
Produce a unified final report:

1. Per-customer summary (one paragraph each — preserve key findings and risk ratings)
2. Cross-customer observations (patterns visible only when comparing accounts —
   e.g. is one customer materially different? any systemic policy gaps?)
3. Recommended actions, in priority order

=== Audit A (CUST-01 / Alice Chen) ===
{findings_a}

=== Audit B (CUST-02 / Bob Patel) ===
{findings_b}

=== Audit C (CUST-03 / Carla Diaz) ===
{findings_c}
"""

CUSTOMERS = [
    {"customer_id": "CUST-01", "email": "alice@example.com"},
    {"customer_id": "CUST-02", "email": "bob@example.com"},
    {"customer_id": "CUST-03", "email": "carla@example.com"},
]


def run_worker(customer_id: str, email: str) -> tuple[str, int, int]:
    """Agentic loop for one customer — identical stop_reason pattern to loop_demo.py."""
    messages = [
        {
            "role": "user",
            "content": WORKER_PROMPT.format(customer_id=customer_id, email=email),
        }
    ]
    final_text = ""
    total_input = 0
    total_output = 0

    while True:
        response = client.messages.create(
            model=MODEL,
            max_tokens=WORKER_MAX_TOKENS,
            tools=TOOL_SCHEMAS,
            messages=messages,
        )

        messages.append({"role": "assistant", "content": response.content})
        total_input += response.usage.input_tokens
        total_output += response.usage.output_tokens

        # Capture any text produced in this turn (fallback if end_turn has none)
        for block in response.content:
            if block.type == "text" and block.text.strip():
                final_text = block.text

        if response.stop_reason == "end_turn":
            break

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    result = dispatch(block.name, block.input)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result),
                    })
            messages.append({"role": "user", "content": tool_results})
            continue

        break

    return final_text, total_input, total_output


def main():
    print("Running multi-pass audit (3 parallel workers + synthesis)...")
    print("=" * 60)

    findings = {}
    worker_input_tokens = 0
    worker_output_tokens = 0

    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {
            executor.submit(run_worker, c["customer_id"], c["email"]): c["customer_id"]
            for c in CUSTOMERS
        }
        for future in as_completed(futures):
            cid = futures[future]
            text, inp, out = future.result()
            findings[cid] = text
            worker_input_tokens += inp
            worker_output_tokens += out
            print(f"  Worker complete: {cid}")

    print()
    print("All workers done. Running synthesis...")
    print("-" * 60)

    synthesis_response = client.messages.create(
        model=MODEL,
        max_tokens=SYNTHESIS_MAX_TOKENS,
        messages=[
            {
                "role": "user",
                "content": SYNTHESIS_PROMPT.format(
                    findings_a=findings["CUST-01"],
                    findings_b=findings["CUST-02"],
                    findings_c=findings["CUST-03"],
                ),
            }
        ],
    )

    synth_input = synthesis_response.usage.input_tokens
    synth_output = synthesis_response.usage.output_tokens
    total_input = worker_input_tokens + synth_input
    total_output = worker_output_tokens + synth_output

    print()
    print(synthesis_response.content[0].text)
    print()
    print(f"workers input tokens: {worker_input_tokens} | workers output tokens: {worker_output_tokens}")
    print(f"synthesis input tokens: {synth_input} | synthesis output tokens: {synth_output}")
    print(f"total input tokens: {total_input} | total output tokens: {total_output}")


if __name__ == "__main__":
    main()
