"""
LESSON 2.1 DEMO — Intentionally broken tool descriptions.

Both find_items and get_items_due carry near-identical descriptions:
"Retrieves household items." The model cannot tell them apart from the
description alone, so it picks based on argument shape — which means it
often gets it wrong.

HOW TO RUN THE DEMO
-------------------
1. Point .mcp.json at this file instead of server.py:
     "args": ["mcp_server/server_broken.py"]

2. Ask the agent: "What household maintenance is coming up this month?"

3. Watch it call find_items(query="maintenance") — keyword search —
   instead of get_items_due(days_ahead=30) — date window search.
   The results look plausible but are wrong: find_items returns items
   that match the word "maintenance" in their name regardless of date,
   so overdue items mix with future ones and items with no due date show.

4. Switch back to server.py. Same question now routes correctly.

WHAT TO LOOK FOR
----------------
The broken descriptions are:
    find_items:     "Retrieves household items."
    get_items_due:  "Retrieves household items."  ← identical

The fix in server.py establishes clear, non-overlapping purpose boundaries:
    find_items:     "Search ... by keyword ... regardless of due date."
    get_items_due:  "Return ... due for attention within a date window."

Lesson: fix tool descriptions before adding routing classifiers or
restructuring your architecture. The description is the primary signal.
"""

import json
import os
from datetime import datetime, timedelta
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("household-tools-broken")

_db_path_env = os.environ.get("HOUSEHOLD_DB_PATH") or ""
DATA_DIR = Path(_db_path_env) if _db_path_env else Path(__file__).parent / "data"
CURRENT_USER = os.environ.get("HOUSEHOLD_CURRENT_USER", "admin")


def _load(filename: str):
    with open(DATA_DIR / filename) as f:
        return json.load(f)


def _save(filename: str, data) -> None:
    with open(DATA_DIR / filename, "w") as f:
        json.dump(data, f, indent=2)


# ---------------------------------------------------------------------------
# BROKEN: identical descriptions — agent misroutes date questions to find_items
# ---------------------------------------------------------------------------

@mcp.tool()
def find_items(query: str, category: str = None) -> list:
    """Retrieves household items."""  # <- BROKEN: no boundary, no use case
    items = _load("items.json")
    results = [
        i for i in items
        if query.lower() in i["name"].lower()
        or query.lower() in (i.get("notes") or "").lower()
    ]
    if category:
        results = [i for i in results if i.get("category") == category]
    return results


@mcp.tool()
def get_items_due(days_ahead: int = 30, category: str = None) -> list:
    """Retrieves household items."""  # <- BROKEN: identical to find_items
    today = datetime.now().date().isoformat()
    cutoff = (datetime.now() + timedelta(days=days_ahead)).date().isoformat()
    items = _load("items.json")
    if days_ahead < 0:
        results = [i for i in items if i.get("due_date", "9999") < today]
    else:
        results = [i for i in items if i.get("due_date", "9999") <= cutoff]
    if category:
        results = [i for i in results if i.get("category") == category]
    return sorted(results, key=lambda x: x.get("due_date", ""))


@mcp.tool()
def add_item(
    name: str,
    category: str,
    due_date: str,
    owner: str = None,
    recurring: bool = False,
    recurring_interval_days: int = None,
    notes: str = None,
    visibility: str = "household",
) -> dict:
    """Adds a new household item."""
    items = _load("items.json")
    nums = [int(i["id"].split("-")[1]) for i in items if i["id"].startswith("ITEM-")]
    item_id = f"ITEM-{max(nums) + 1:03d}" if nums else "ITEM-001"
    new_item = {
        "id": item_id,
        "name": name,
        "category": category,
        "due_date": due_date,
        "owner": owner or CURRENT_USER,
        "visibility": visibility,
        "recurring": recurring,
        "recurring_interval_days": recurring_interval_days,
        "notes": notes,
    }
    items.append(new_item)
    _save("items.json", items)
    return {"success": True, "item": new_item}


@mcp.tool()
def log_completion(item_id: str, completed_by: str = None, notes: str = None) -> dict:
    """Logs a completed household item."""
    items = _load("items.json")
    log = _load("completion_log.json")
    item = next((i for i in items if i["id"] == item_id), None)
    log_nums = [int(e["id"].split("-")[1]) for e in log if e["id"].startswith("LOG-")]
    log_id = f"LOG-{max(log_nums) + 1:03d}" if log_nums else "LOG-001"
    entry = {
        "id": log_id,
        "item_id": item_id,
        "item_name": item["name"] if item else "unknown",
        "completed_by": completed_by or CURRENT_USER,
        "completed_at": datetime.now().isoformat(),
        "notes": notes,
    }
    log.append(entry)
    _save("completion_log.json", log)
    return {"success": True, "log_entry": entry}


@mcp.tool()
def list_subscriptions(status: str = "active") -> list:
    """Lists subscriptions."""
    subs = _load("subscriptions.json")
    if status != "all":
        subs = [s for s in subs if s.get("status") == status]
    return sorted(subs, key=lambda x: x.get("renewal_date", ""))


if __name__ == "__main__":
    mcp.run()
