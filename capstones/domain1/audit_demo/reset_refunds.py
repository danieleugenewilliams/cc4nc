#!/usr/bin/env python3
"""Reset refunds_log.json to the clean seeded state.

Run this before any verification test that writes to refunds_log.json
(tests B, C, D, and all session_demo scenarios).

Usage:
    python3 audit_demo/reset_refunds.py
"""
import shutil
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "mcp_server" / "data"
seed = DATA_DIR / "refunds_log.seed.json"
live = DATA_DIR / "refunds_log.json"

shutil.copy(seed, live)
print(f"Reset: {live} ← {seed}")
