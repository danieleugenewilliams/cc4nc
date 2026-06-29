#!/usr/bin/env python3
"""
PreToolUse hook: check_before_add

Fires before every add_item call. Independently checks items.json for
similar names and blocks the call if a potential duplicate is found.

Lesson 2.3 — The difference between tool_choice and a hook:
  tool_choice (Messages API): asks the model to call find_items first.
                               The model can ignore it or be bypassed.
  This hook:                   always runs, regardless of what the model did.
                               "tool_choice is a request; a hook is a guarantee."

Exit codes:
  0  → allow (no duplicates found, or file unreadable)
  2  → block (duplicate detected; reason written to stderr)
"""

import json
import os
import sys
from pathlib import Path


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    name = tool_input.get("name", "").lower().strip()

    if not name:
        sys.exit(0)

    db_env = os.environ.get("HOUSEHOLD_DB_PATH") or ""
    data_dir = (
        Path(db_env)
        if db_env
        else Path(__file__).parent.parent / "mcp_server" / "data"
    )
    items_path = data_dir / "items.json"

    try:
        with open(items_path) as f:
            items = json.load(f)
    except Exception:
        sys.exit(0)

    duplicates = [
        i for i in items
        if name in i["name"].lower() or i["name"].lower() in name
    ]

    if duplicates:
        matches = ", ".join(
            f"'{i['name']}' ({i['id']})" for i in duplicates[:3]
        )
        print(
            f"Duplicate check blocked: similar items already exist — {matches}. "
            "If updating an existing item, use log_completion instead. "
            "If this is a genuinely new item, use a more specific name.",
            file=sys.stderr,
        )
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
