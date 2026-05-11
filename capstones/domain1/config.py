"""
Shared configuration for all demo scripts in this capstone.
Change MODEL here to update loop_demo, audit_single_pass, and audit_multipass at once.
"""

MODEL = "claude-sonnet-4-6"

# Loop demos: simple 2-turn interactions, 1024 is sufficient
LOOP_MAX_TOKENS = 1024

# Single-pass audit: one large context, needs room for all three customer sections
SINGLE_PASS_MAX_TOKENS = 4096

# Multi-pass workers: one customer each, needs room for tool calls + analysis
WORKER_MAX_TOKENS = 2048

# Multi-pass synthesis: reads compressed worker findings, produces unified report
SYNTHESIS_MAX_TOKENS = 4096
