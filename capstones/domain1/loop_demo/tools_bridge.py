"""
Provides Anthropic API tool schemas and a dispatch function for loop_demo.py.

Reads the same JSON data files as the MCP server, so the loop demo uses
identical fake data without needing to wire up MCP transport.
"""

import json
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "mcp_server" / "data"


def _load(filename: str):
    with open(DATA_DIR / filename) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Tool implementations (same logic as mcp_server/server.py)
# ---------------------------------------------------------------------------

def lookup_customer(email: str) -> dict:
    for customer in _load("customers.json"):
        if customer["email"].lower() == email.lower():
            return customer
    return {"error": f"No customer found with email: {email}"}


def get_order(order_id: str) -> dict:
    for order in _load("orders.json"):
        if order["order_id"] == order_id:
            return order
    return {"error": f"No order found with ID: {order_id}"}


def list_recent_orders(customer_id: str, limit: int = 5) -> list:
    orders = [o for o in _load("orders.json") if o["customer_id"] == customer_id]
    return orders[-limit:] if len(orders) > limit else orders


def issue_refund(order_id: str, amount_usd: float, reason: str = None, manager_approved: bool = False) -> dict:
    orders = _load("orders.json")
    order = next((o for o in orders if o["order_id"] == order_id), None)
    if not order:
        return {"error": f"No order found with ID: {order_id}"}
    return {
        "refund_id": f"REF-{order_id}-DEMO",
        "order_id": order_id,
        "amount_usd": amount_usd,
        "reason": reason,
        "status": "approved",
        "processed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_TOOLS = {
    "lookup_customer": lookup_customer,
    "get_order": get_order,
    "list_recent_orders": list_recent_orders,
    "issue_refund": issue_refund,
}


def dispatch(tool_name: str, tool_input: dict):
    fn = _TOOLS.get(tool_name)
    if fn is None:
        return {"error": f"Unknown tool: {tool_name}"}
    return fn(**tool_input)


# ---------------------------------------------------------------------------
# Anthropic API tool schemas
# ---------------------------------------------------------------------------

TOOL_SCHEMAS = [
    {
        "name": "lookup_customer",
        "description": "Look up a customer record by email address.",
        "input_schema": {
            "type": "object",
            "properties": {
                "email": {"type": "string", "description": "Customer email address"},
            },
            "required": ["email"],
        },
    },
    {
        "name": "get_order",
        "description": "Get details for a specific order by order ID.",
        "input_schema": {
            "type": "object",
            "properties": {
                "order_id": {"type": "string", "description": "Order ID (e.g. ORD-1001)"},
            },
            "required": ["order_id"],
        },
    },
    {
        "name": "list_recent_orders",
        "description": "List the most recent orders for a customer.",
        "input_schema": {
            "type": "object",
            "properties": {
                "customer_id": {"type": "string", "description": "Customer ID (e.g. CUST-03)"},
                "limit": {"type": "integer", "description": "Max orders to return (default 5)"},
            },
            "required": ["customer_id"],
        },
    },
    {
        "name": "issue_refund",
        "description": "Issue a refund for an order. Requires a reason. Refunds over $500 require manager_approved=true.",
        "input_schema": {
            "type": "object",
            "properties": {
                "order_id": {"type": "string"},
                "amount_usd": {"type": "number"},
                "reason": {"type": "string"},
                "manager_approved": {"type": "boolean"},
            },
            "required": ["order_id", "amount_usd", "reason"],
        },
    },
]
