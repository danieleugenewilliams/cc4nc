# Test A - PostToolUse Date Normalisation

## Setup
Start Claude Code from `capstones/domain1/`: `claude`

## Prompt
```
Show me the last 3 orders for alice@example.com
```

## Pass criteria
- Claude responds with dates in a readable format (plain English or ISO 8601)
- No Unix timestamps or `MM/DD/YYYY` format visible in Claude's response
- The raw data in `mcp_server/data/orders.json` is **unchanged** (still has mixed formats)

## Verify the raw data is still messy
```bash
cat mcp_server/data/orders.json | python3 -m json.tool | grep ordered_at
```
You should still see Unix ints and `MM/DD/YYYY` strings - the hook normalises on the fly, it doesn't modify the source data.

## What to look for in Claude Code output
When Claude calls `list_recent_orders`, the hook intercepts it. In verbose mode (`Ctrl+O`) you may see the hook firing. The model receives clean ISO 8601 dates; the tool itself returned chaos.
