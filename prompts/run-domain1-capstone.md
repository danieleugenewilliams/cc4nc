# Prompt: Run the Domain 1 Capstone

Copy everything below this line and paste it into Claude Code.

---

I want to explore the Domain 1 capstone from the Claude Code for Non-Coders newsletter.

Please do the following in order:

1. Clone the repo if it isn't already here:
   `git clone https://github.com/danieleugenewilliams/cc4nc.git`
   Then `cd cc4nc/capstones/domain1`.

2. Install dependencies:
   `pip install mcp anthropic`

3. Seed the refund log:
   `python3 audit_demo/reset_refunds.py`

4. Run the loop demo and show me the output:
   `python3 loop_demo/loop_demo.py`
   Explain what `stop_reason` means and why it matters.

5. Run the anti-pattern demo:
   `python3 loop_demo/loop_demo_wrong.py`
   Explain what went wrong in each of the three variants.

6. Tell me how to start Claude Code for the full agent demo, and what prompts to try first.

Take it one step at a time and explain what's happening at each step as if I've never written a line of code.
