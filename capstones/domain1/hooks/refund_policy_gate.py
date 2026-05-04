#!/usr/bin/env python3
"""
PreToolUse hook — enforce refund policy before issue_refund executes.

Two violations are blocked:
  1. amount_usd > 500 without manager_approved=True
  2. reason field missing or empty

Why a hook and not a prompt instruction:
  A prompt instruction has a non-zero failure rate — it can be overridden by
  another prompt, misunderstood, or simply ignored in an edge case. For a
  financial policy that must never be violated, a hook is the only correct
  enforcement mechanism. This hook fires BEFORE the tool executes and cannot
  be bypassed even in --dangerously-skip-permissions mode.

Exit code note:
  exit 0 + structured JSON is the clean path for command hooks that want to
  return a permissionDecision with a reason string.
  exit 2 blocks via stderr (no reason string for the agent to use).
  exit 1 is a non-blocking error — it logs and continues. Never use exit 1
  to block.
"""

import json
import sys


def main():
    payload = json.load(sys.stdin)
    tool_input = payload.get("tool_input", {})

    amount = tool_input.get("amount_usd", 0)
    reason = (tool_input.get("reason") or "").strip()
    approved = tool_input.get("manager_approved", False)

    violations = []

    if amount > 500 and not approved:
        violations.append(
            f"refund of ${amount:.2f} exceeds the $500 threshold — "
            "manager_approved must be True (check the customer's manager_approval_flag)"
        )

    if not reason:
        violations.append(
            "refund is missing a required reason — ask the customer why they want a refund"
        )

    if violations:
        print(json.dumps({
            "systemMessage": "Refund blocked by policy hook.",
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "; ".join(violations),
            },
        }))
        sys.exit(0)

    # Policy satisfied — allow the call
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
        },
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
