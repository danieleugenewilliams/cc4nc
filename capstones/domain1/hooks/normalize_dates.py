#!/usr/bin/env python3
"""
PostToolUse hook — normalise all ordered_at fields to ISO 8601.

The MCP server returns order dates in three different formats depending on
which backend system the order originated from:
  - Unix epoch integers  (e.g. 1714521600)
  - MM/DD/YYYY strings   (e.g. "03/15/2025")
  - ISO 8601 strings     (e.g. "2025-04-02T14:22:00Z")

This hook intercepts the raw tool output and replaces it with a normalised
version before the model sees it. The model always receives ISO 8601.

Why updatedMCPToolOutput (replace) rather than additionalContext (append):
  - The model has no use for the original messy formats alongside the clean ones.
  - Appending both versions adds tokens and introduces ambiguity.
  - Replacing gives one canonical schema everywhere.
"""

import json
import re
import sys
from datetime import datetime, timezone


def to_iso(value) -> str:
    """Convert a date value in any supported format to ISO 8601."""
    if isinstance(value, int):
        return datetime.fromtimestamp(value, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if isinstance(value, str):
        if re.match(r"^\d{2}/\d{2}/\d{4}$", value):
            dt = datetime.strptime(value, "%m/%d/%Y").replace(tzinfo=timezone.utc)
            return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    return value


def normalise(obj):
    """Walk the response and normalise every ordered_at field found."""
    if isinstance(obj, dict):
        return {
            k: (to_iso(v) if k == "ordered_at" else normalise(v))
            for k, v in obj.items()
        }
    if isinstance(obj, list):
        return [normalise(item) for item in obj]
    return obj


def main():
    payload = json.load(sys.stdin)
    tool_response = payload.get("tool_response", {})

    # tool_response may arrive as a JSON string or as an already-parsed object
    if isinstance(tool_response, str):
        try:
            tool_response = json.loads(tool_response)
        except json.JSONDecodeError:
            # Not JSON — pass through unchanged
            sys.exit(0)

    normalised = normalise(tool_response)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedMCPToolOutput": json.dumps(normalised),
        }
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
