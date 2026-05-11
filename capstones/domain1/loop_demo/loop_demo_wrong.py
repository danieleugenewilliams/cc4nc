"""
ANTI-PATTERN REFERENCE — do not use this code.

This file demonstrates the three agentic loop bugs that appear on the
Claude Architect exam. Each variant uses the same prompt as loop_demo.py
but terminates early, missing tool calls or capping work prematurely.

Run from capstones/domain1/:
    python3 loop_demo/loop_demo_wrong.py

The script runs all three variants sequentially and shows where each fails.
Compare the output to loop_demo.py — same prompt, different control flow,
dramatically different results.
"""

import json
import sys
from pathlib import Path

import anthropic

sys.path.insert(0, str(Path(__file__).parent))
from tools_bridge import TOOL_SCHEMAS, dispatch
sys.path.insert(0, str(Path(__file__).parent.parent))
from config import MODEL, LOOP_MAX_TOKENS

PROMPT = (
    "Has CUST-03 placed any orders over $1,000? "
    "If so, what was the most recent one and what was the order date?"
)

client = anthropic.Anthropic()


def run_with_label(label: str, loop_fn):
    print(f"\n{'=' * 60}")
    print(f"ANTI-PATTERN: {label}")
    print("=" * 60)
    loop_fn()


# ---------------------------------------------------------------------------
# Anti-pattern 1: checking content block type instead of stop_reason
# This is the most common exam trap. Claude often returns a text block
# ("Let me look that up...") alongside a tool_use block. Checking for text
# causes the loop to exit before the tool ever runs.
# ---------------------------------------------------------------------------

def wrong_1_content_type_check():
    messages = [{"role": "user", "content": PROMPT}]

    response = client.messages.create(
        model=MODEL,
        max_tokens=LOOP_MAX_TOKENS,
        tools=TOOL_SCHEMAS,
        messages=messages,
    )

    print(f"stop_reason was: {response.stop_reason}")
    print(f"content blocks: {[b.type for b in response.content]}")

    # BUG: checking content block type, not stop_reason
    if response.content[0].type == "text":
        print("EXIT: saw a text block — assuming Claude is done.")
        print("(The tool_use block that followed was never executed.)")
        return

    print("(Reached tool_use handling — but only if the first block happened to be tool_use)")


# ---------------------------------------------------------------------------
# Anti-pattern 2: hard-coded iteration cap
# Real tasks are open-ended. A cap of 3 (or 5, or 10) is arbitrary.
# If the task genuinely needs more turns, the cap cuts it off mid-work.
# stop_reason tells you when the model is actually done — no guessing needed.
# ---------------------------------------------------------------------------

def wrong_2_iteration_cap():
    messages = [{"role": "user", "content": PROMPT}]
    MAX_ITERATIONS = 2  # Arbitrary. Will terminate before the task is complete.

    for iteration in range(MAX_ITERATIONS):
        response = client.messages.create(
            model=MODEL,
            max_tokens=LOOP_MAX_TOKENS,
            tools=TOOL_SCHEMAS,
            messages=messages,
        )

        print(f"  iteration {iteration + 1}, stop_reason: {response.stop_reason}")
        messages.append({"role": "assistant", "content": response.content})

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

    # BUG: loop exits after MAX_ITERATIONS regardless of stop_reason.
    print(f"EXIT: hit iteration cap ({MAX_ITERATIONS}). Task may be incomplete.")
    print("      (stop_reason on last response was:", response.stop_reason, ")")


# ---------------------------------------------------------------------------
# Anti-pattern 3: checking for presence of any text block as "done"
# Same root cause as anti-pattern 1, just spelled differently.
# Claude routinely includes a brief commentary text block with a tool_use
# block in the same response. Text ≠ finished.
# ---------------------------------------------------------------------------

def wrong_3_text_presence_check():
    messages = [{"role": "user", "content": PROMPT}]
    iteration = 0

    while True:
        iteration += 1
        response = client.messages.create(
            model=MODEL,
            max_tokens=LOOP_MAX_TOKENS,
            tools=TOOL_SCHEMAS,
            messages=messages,
        )

        print(f"  iteration {iteration}, stop_reason: {response.stop_reason}, "
              f"has text: {any(b.type == 'text' for b in response.content)}")

        # BUG: any text block is treated as termination
        if any(b.type == "text" for b in response.content):
            print("EXIT: found a text block — assuming Claude is done.")
            print("      (tool_use blocks in the same response were ignored.)")
            return

        messages.append({"role": "assistant", "content": response.content})

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


# ---------------------------------------------------------------------------
# Run all three
# ---------------------------------------------------------------------------

print(f"Prompt: {PROMPT}")
print("\nRunning 3 anti-pattern variants. Compare with loop_demo.py output.\n")

run_with_label("content[0].type == 'text' check", wrong_1_content_type_check)
run_with_label("hard-coded iteration cap (MAX=2)", wrong_2_iteration_cap)
run_with_label("any text block = done check", wrong_3_text_presence_check)

print("\n\nAll three anti-patterns demonstrated.")
print("Run loop_demo.py to see the correct behaviour on the same prompt.")
