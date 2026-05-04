"""
Extends loop_demo/tools_bridge.py with the list_refunds tool for audit scripts.

loop_demo/tools_bridge.py is NOT modified — this file imports it and layers
the new tool on top.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "loop_demo"))
import tools_bridge as base


def list_refunds(customer_id: str) -> list:
    orders = base._load("orders.json")
    order_ids = {o["order_id"] for o in orders if o["customer_id"] == customer_id}
    return [r for r in base._load("refunds_log.json") if r["order_id"] in order_ids]


_EXTRA = {"list_refunds": list_refunds}


def dispatch(tool_name: str, tool_input: dict):
    if tool_name in _EXTRA:
        return _EXTRA[tool_name](**tool_input)
    return base.dispatch(tool_name, tool_input)


TOOL_SCHEMAS = base.TOOL_SCHEMAS + [
    {
        "name": "list_refunds",
        "description": "List refund history for a customer (oldest-first). Empty list if no refunds.",
        "input_schema": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "Customer ID (e.g. CUST-01)",
                },
            },
            "required": ["customer_id"],
        },
    },
]
