"""
Reset household data to the seeded state.

Run this before any verification test that mutates items.json or
completion_log.json. The seed directory (data/seed/) is tracked in git;
the runtime files (data/items.json, data/completion_log.json) are not.

Usage:
    python3 reset_items.py
"""

import shutil
from pathlib import Path

DATA_DIR = Path(__file__).parent / "mcp_server" / "data"
SEED_DIR = DATA_DIR / "seed"

RESET_FILES = ["items.json", "completion_log.json"]


def reset():
    for name in RESET_FILES:
        src = SEED_DIR / name
        dst = DATA_DIR / name
        shutil.copy(src, dst)
        print(f"  reset  {dst.relative_to(Path(__file__).parent)}")
    print("done.")


if __name__ == "__main__":
    reset()
