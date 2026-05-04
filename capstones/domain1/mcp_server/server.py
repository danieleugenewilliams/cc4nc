import json
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.fastmcp import FastMCP

DATA_DIR = Path(__file__).parent / "data"

mcp = FastMCP("support-tools")


def _load(filename: str):
    with open(DATA_DIR / filename) as f:
        return json.load(f)


@mcp.tool()
def lookup_customer(email: str) -> dict:
    """Look up a customer record by email address."""
    for customer in _load("customers.json"):
        if customer["email"].lower() == email.lower():
            return customer
    return {"error": f"No customer found with email: {email}"}


@mcp.tool()
def get_order(order_id: str) -> dict:
    """Get details for a specific order by order ID."""
    for order in _load("orders.json"):
        if order["order_id"] == order_id:
            return order
    return {"error": f"No order found with ID: {order_id}"}


@mcp.tool()
def list_recent_orders(customer_id: str, limit: int = 5) -> list:
    """List the most recent orders for a customer (default: last 5)."""
    orders = [o for o in _load("orders.json") if o["customer_id"] == customer_id]
    return orders[-limit:] if len(orders) > limit else orders


@mcp.tool()
def list_refunds(customer_id: str) -> list:
    """List refund history for a customer (oldest-first). Empty list if none."""
    orders = _load("orders.json")
    customer_order_ids = {o["order_id"] for o in orders if o["customer_id"] == customer_id}
    return [r for r in _load("refunds_log.json") if r["order_id"] in customer_order_ids]


@mcp.tool()
def issue_refund(
    order_id: str,
    amount_usd: float,
    reason: str = None,
    manager_approved: bool = False,
) -> dict:
    """
    Issue a refund for an order.

    Policy (enforced by PreToolUse hook — this tool does not re-check):
    - Refunds over $500 require manager_approved=True.
    - A reason is always required.
    """
    orders = _load("orders.json")
    order = next((o for o in orders if o["order_id"] == order_id), None)
    if not order:
        return {"error": f"No order found with ID: {order_id}"}

    refund = {
        "refund_id": f"REF-{order_id}-{int(datetime.now(timezone.utc).timestamp())}",
        "order_id": order_id,
        "amount_usd": amount_usd,
        "reason": reason,
        "manager_approved": manager_approved,
        "status": "approved",
        "processed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    log_path = DATA_DIR / "refunds_log.json"
    log = _load("refunds_log.json")
    log.append(refund)
    with open(log_path, "w") as f:
        json.dump(log, f, indent=2)

    return refund


if __name__ == "__main__":
    mcp.run()
