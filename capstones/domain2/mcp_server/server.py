"""
Household Operations MCP Server — fixed descriptions (production version).

Domain 2 lesson mapping:
  2.1 — Tool descriptions: find_items vs get_items_due boundaries
  2.2 — Error categories: transient / validation / business / permission
  2.3 — tool_choice: add_item doc warns agent to call find_items first;
         PreToolUse hook in ../.claude/settings.json enforces it
  2.4 — Env var expansion: HOUSEHOLD_CURRENT_USER, HOUSEHOLD_DB_PATH
  2.5 — Grep-then-Read exploration pattern used to build this file

Compare to server_broken.py to see the Lesson 2.1 misrouting demo.
"""

import json
import os
from datetime import datetime, timedelta
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("household-tools")

_db_path_env = os.environ.get("HOUSEHOLD_DB_PATH") or ""
DATA_DIR = Path(_db_path_env) if _db_path_env else Path(__file__).parent / "data"
CURRENT_USER = os.environ.get("HOUSEHOLD_CURRENT_USER", "admin")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _load(filename: str):
    """Load a JSON data file. Returns an error dict if the file is locked."""
    path = DATA_DIR / filename
    lock_path = path.with_suffix(path.suffix + ".lock")
    if lock_path.exists():
        # Lesson 2.2: Transient error — retryable, not a bug in the call
        return {
            "isError": True,
            "errorCategory": "transient",
            "isRetryable": True,
            "content": (
                f"Data file {filename} is temporarily locked by another process. "
                "Retry in a few seconds."
            ),
        }
    with open(path) as f:
        return json.load(f)


def _save(filename: str, data) -> None:
    path = DATA_DIR / filename
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def _current_user():
    users = _load("users.json")
    if isinstance(users, dict) and users.get("isError"):
        return users
    return next((u for u in users if u["id"] == CURRENT_USER), None)


def _can_modify(item: dict, user: dict) -> bool:
    """Admins can modify anything. Members cannot modify private items they don't own."""
    if user["role"] == "admin":
        return True
    if item.get("visibility") == "private" and item.get("owner") != user["id"]:
        return False
    return True


def _next_item_id(items: list) -> str:
    if not items:
        return "ITEM-001"
    nums = [int(i["id"].split("-")[1]) for i in items if i["id"].startswith("ITEM-")]
    return f"ITEM-{max(nums) + 1:03d}" if nums else "ITEM-001"


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@mcp.tool()
def find_items(query: str, category: str | None = None) -> dict | list:
    """Search household items by keyword across name and notes fields.

    Use this tool when you know what you are looking for by name or keyword —
    for example, 'HVAC', 'grocery', or 'car'. Returns all items matching the
    search term regardless of due date.

    Use get_items_due instead when the question is about timing: what needs
    attention soon, what is overdue, or what is coming up in the next N days.

    Args:
        query: Keyword to match in item name and notes (case-insensitive)
        category: Optional filter — 'maintenance', 'recurring', or 'task'
    """
    items = _load("items.json")
    if isinstance(items, dict) and items.get("isError"):
        return items

    results = [
        i for i in items
        if query.lower() in i["name"].lower()
        or query.lower() in (i.get("notes") or "").lower()
    ]
    if category:
        results = [i for i in results if i.get("category") == category]
    return results


@mcp.tool()
def get_items_due(days_ahead: int = 30, category: str | None = None) -> dict | list:
    """Return household items due for attention within a date window.

    Use this tool when the question is about timing — what is overdue, what
    needs attention this week, or what is coming up in the next N days.
    Pass a negative value to get only overdue items (e.g., days_ahead=-1
    returns everything past due as of today).

    Use find_items instead when you are searching by name or keyword and
    timing does not matter.

    Args:
        days_ahead: Days to look ahead from today (negative = overdue only)
        category: Optional filter — 'maintenance', 'recurring', or 'task'
    """
    items = _load("items.json")
    if isinstance(items, dict) and items.get("isError"):
        return items

    today = datetime.now().date().isoformat()
    cutoff = (datetime.now() + timedelta(days=days_ahead)).date().isoformat()

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
    owner: str | None = None,
    recurring: bool = False,
    recurring_interval_days: int | None = None,
    notes: str | None = None,
    visibility: str = "household",
) -> dict:
    """Add a new item to household tracking.

    IMPORTANT: Always call find_items first to check whether a similar item
    already exists before calling add_item. A PreToolUse hook enforces this
    independently, but checking first lets you give the user better information.

    Args:
        name: Item name (required)
        category: One of 'maintenance', 'recurring', or 'task' (required)
        due_date: Due date in YYYY-MM-DD format (required)
        owner: User ID of the owner. Defaults to the current user.
        recurring: Whether this item repeats on a schedule
        recurring_interval_days: Days between recurrences (required if recurring=True)
        notes: Optional free-text notes
        visibility: 'household' (shared with all users) or 'private'
    """
    # --- Lesson 2.2: Validation errors — fix input, then retry ---
    if not name or not name.strip():
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": True,
            "content": "name is required and cannot be empty. Provide a descriptive item name and retry.",
        }

    valid_categories = {"maintenance", "recurring", "task"}
    if category not in valid_categories:
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": True,
            "content": (
                f"category must be one of: {', '.join(sorted(valid_categories))}. "
                f"Got '{category}'. Fix the value and retry."
            ),
        }

    try:
        datetime.strptime(due_date, "%Y-%m-%d")
    except ValueError:
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": True,
            "content": (
                f"due_date must be in YYYY-MM-DD format. Got '{due_date}'. "
                "Fix the format and retry."
            ),
        }

    if recurring and not recurring_interval_days:
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": True,
            "content": (
                "recurring_interval_days is required when recurring is True. "
                "Provide the number of days between recurrences and retry."
            ),
        }

    items = _load("items.json")
    if isinstance(items, dict) and items.get("isError"):
        return items

    item_id = _next_item_id(items)
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
        "created_at": datetime.now().isoformat(),
    }
    items.append(new_item)
    _save("items.json", items)
    return {"success": True, "item": new_item}


@mcp.tool()
def log_completion(
    item_id: str, completed_by: str | None = None, notes: str | None = None
) -> dict:
    """Mark a household item as completed and log the action.

    For recurring items, advances the due date to the next recurrence rather
    than removing the item. For non-recurring items, marks the item done.

    Args:
        item_id: ID of the item to mark complete (e.g., 'ITEM-001')
        completed_by: User ID of who completed it. Defaults to current user.
        notes: Optional completion notes
    """
    user = _current_user()
    if isinstance(user, dict) and user.get("isError"):
        return user
    if not user:
        # Lesson 2.2: Permission error — escalate, do not retry
        return {
            "isError": True,
            "errorCategory": "permission",
            "isRetryable": False,
            "content": (
                f"Current user '{CURRENT_USER}' not found. "
                "Check the HOUSEHOLD_CURRENT_USER environment variable."
            ),
        }

    items = _load("items.json")
    if isinstance(items, dict) and items.get("isError"):
        return items

    item = next((i for i in items if i["id"] == item_id), None)
    if not item:
        # Lesson 2.2: Validation error — wrong item_id, fix and retry
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": False,
            "content": (
                f"No item found with ID '{item_id}'. "
                "Use find_items or get_items_due to find the correct item ID."
            ),
        }

    if not _can_modify(item, user):
        # Lesson 2.2: Permission error — escalate, do not retry with same user
        return {
            "isError": True,
            "errorCategory": "permission",
            "isRetryable": False,
            "content": (
                f"User '{CURRENT_USER}' cannot modify item '{item_id}'. "
                f"This is a private item owned by '{item['owner']}'. "
                "Only the owner or an admin can log completion."
            ),
        }

    log = _load("completion_log.json")
    if isinstance(log, dict) and log.get("isError"):
        return log

    log_nums = [int(e["id"].split("-")[1]) for e in log if e["id"].startswith("LOG-")]
    log_id = f"LOG-{max(log_nums) + 1:03d}" if log_nums else "LOG-001"

    entry = {
        "id": log_id,
        "item_id": item_id,
        "item_name": item["name"],
        "completed_by": completed_by or CURRENT_USER,
        "completed_at": datetime.now().isoformat(),
        "notes": notes,
    }
    log.append(entry)
    _save("completion_log.json", log)

    if item.get("recurring") and item.get("recurring_interval_days"):
        # Lesson 2.2: Business rule — recurring items advance, never delete
        interval = item["recurring_interval_days"]
        current_due = datetime.strptime(item["due_date"], "%Y-%m-%d")
        next_due = current_due + timedelta(days=interval)
        item["due_date"] = next_due.date().isoformat()
        item["last_completed"] = datetime.now().isoformat()
        _save("items.json", items)
        return {
            "success": True,
            "log_entry": entry,
            "next_due": item["due_date"],
            "message": f"Completion logged. Next occurrence scheduled for {item['due_date']}.",
        }
    else:
        item["status"] = "completed"
        item["completed_at"] = datetime.now().isoformat()
        _save("items.json", items)
        return {
            "success": True,
            "log_entry": entry,
            "message": "Completion logged. Item marked as done.",
        }


@mcp.tool()
def list_subscriptions(status: str = "active") -> dict | list:
    """List household subscriptions with renewal dates and monthly costs.

    Non-admin users see only household-visible subscriptions and their own
    private subscriptions. Admins see everything.

    Results are sorted by renewal date, soonest first.

    Args:
        status: 'active', 'cancelled', or 'all'
    """
    valid_statuses = {"active", "cancelled", "all"}
    if status not in valid_statuses:
        return {
            "isError": True,
            "errorCategory": "validation",
            "isRetryable": True,
            "content": (
                f"status must be one of: {', '.join(sorted(valid_statuses))}. "
                f"Got '{status}'."
            ),
        }

    user = _current_user()
    if isinstance(user, dict) and user.get("isError"):
        return user

    subs = _load("subscriptions.json")
    if isinstance(subs, dict) and subs.get("isError"):
        return subs

    if status != "all":
        subs = [s for s in subs if s.get("status") == status]

    # Lesson 2.2: permission filtering (not an error — empty is a valid answer)
    if user and user["role"] != "admin":
        subs = [
            s for s in subs
            if s.get("visibility") == "household" or s.get("owner") == CURRENT_USER
        ]

    return sorted(subs, key=lambda x: x.get("renewal_date", ""))


if __name__ == "__main__":
    mcp.run()
