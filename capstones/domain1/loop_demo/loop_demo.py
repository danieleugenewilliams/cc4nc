"""
CORRECT agentic loop — stop_reason is the only termination signal.

Run from capstones/domain1/:
    python3 loop_demo/loop_demo.py

What to watch: the --- stop_reason: ... --- lines printed at every iteration.
The loop runs until stop_reason == "end_turn". Everything else (including text
blocks) is not a termination signal.
"""

import json
import sys
from pathlib import Path

import anthropic

sys.path.insert(0, str(Path(__file__).parent))
from tools_bridge import TOOL_SCHEMAS, dispatch

PROMPT = (
    "Has CUST-03 placed any orders over $1,000? "
    "If so, what was the most recent one and what was the order date?"
)

client = anthropic.Anthropic()

messages = [{"role": "user", "content": PROMPT}]

print(f"Prompt: {PROMPT}\n")
print("=" * 60)

while True:
    response = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=1024,
        tools=TOOL_SCHEMAS,
        messages=messages,
    )

    print(f"\n--- stop_reason: {response.stop_reason} ---")

    # Append the full assistant turn verbatim.
    # Do NOT cherry-pick — the whole content block list must go back.
    messages.append({"role": "assistant", "content": response.content})

    if response.stop_reason == "end_turn":
        # Done. Print the final text response.
        for block in response.content:
            if block.type == "text":
                print(f"\nFINAL ANSWER:\n{block.text}")
        break

    if response.stop_reason == "tool_use":
        # Execute every tool the model requested and collect results.
        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                print(f"  calling tool: {block.name}({json.dumps(block.input)})")
                result = dispatch(block.name, block.input)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": json.dumps(result),
                })

        # Append tool results as a user turn before the next iteration.
        # Without this step the model cannot reason about what the tools returned.
        messages.append({"role": "user", "content": tool_results})
        continue

    # Defensive: surface any stop_reason we haven't handled (max_tokens, etc.)
    print(f"Unhandled stop_reason: {response.stop_reason}")
    break
