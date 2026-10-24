---
name: build-review-loop
description: Set up a builder–reviewer loop on a project — two agent sessions that work a backlog through pull requests while nobody is watching, with GitHub labels as the state machine. Runs a preflight that can refuse, derives the label set from what the repo already has, verifies a test command by running it, then renders the loop's contract and its two watch commands from bundled templates. Use when asked to "set up the review loop", "add a builder-reviewer loop", "make this repo run its own backlog", or to port the loop to a new project. Self-contained: bundles its templates and scripts; needs gh, jq, and a Claude Code harness with Monitor, Agent, PushNotification and TaskStop for the rendered commands.
---

# Build a review loop

Two long-running sessions. A **builder** takes work from the backlog and opens pull
requests. A **reviewer** reads them, fixes what it can, and hands back what it cannot.
Labels are the state machine. Neither session holds both roles.

This skill is self-contained. Everything it needs is in this directory — installed at
`~/.claude/skills/build-review-loop/` for a user install or
`<repo>/.claude/skills/build-review-loop/` for a project install; `<skill-dir>` below means
whichever one you loaded this file from:

```
SKILL.md                     this procedure
scripts/preflight.sh         checks the machine and the repo; prints a verdict
scripts/render.sh            fills the templates; refuses to leave a placeholder
templates/contract.md        the loop's contract (roles, labels, state table, predicate)
templates/reviewer-watch.md  the reviewer's slash command
templates/builder-watch.md   the builder's slash command
reference/invariants.md      the 20 rules the commands are built on, each with its reason
reference/lessons.md         what varied across the repos this was derived from
```

Do not retype the templates from memory. They carry a dozen small corrections that are
invisible until each one bites; every one is annotated with the failure that produced it.
Do not look for a "reference implementation" in another project — there is none this skill
depends on.

The procedure is five steps. Steps 1–3 gather facts and decisions; step 4 renders; step 5
verifies. **Report each step's outcome to the person before moving on.**

---

## Step 1 — Preflight, and be willing to refuse

```bash
bash <skill-dir>/scripts/preflight.sh <repo-path>
```

It checks, in order: `gh` installed and authenticated, `jq` present; a git repo with a
remote `gh` can reach; the labels that exist; open issues; merged PRs (via `gh`, not
`git log --merges` — squash- and rebase-merged PRs leave no merge commit); and a detected
test command. It prints one of three verdicts and exits accordingly:

- **Not applicable** (exit 3) — no git repo or no remote. A folder of documents does not get
  a review loop. Say so plainly and stop; do not offer a degraded version.
- **Needs setup first** (exit 2) — a remote but no PR history, or no command that verifies
  anything. Name the missing pieces and stop. A repo where every commit goes straight to
  the base branch has no place for a reviewer to stand.
- **Ready** (exit 0) — *pending a passing run of the test command.*

**The test command is a hard requirement and it is checked by running it.** The script
detects; it cannot verify. Run what it found and see it pass. Detection is not evidence —
`npm test` on a project whose `package.json` has no `test` script exits non-zero.

**What counts as a test command is "a command that fails on broken code."** A test suite is
the preferred instance, not the only one. A browser game with no suite still has
`node --check js/*.js`, or booting the server and hitting one route. If the script found
nothing, ask the person for such a command — then run it. If there is nothing, the verdict
is *needs setup first*.

If the toolchain is absent on the machine you are running the preflight from, you have not
verified the test command — you have guessed it. Say which of the two you did. The verdict
is *ready* only once someone runs it where the loop will live.

Exit 4 (toolchain missing) is a machine problem, not a repo problem: a missing or
unauthenticated `gh` does not announce itself once the loop is running — every call exits
non-zero, the watch correctly publishes nothing, and you get silence forever over a queue
that looks empty.

## Step 2 — Derive the state model from what the repo already has

Do not propose a label set. Derive one. The most common failure in porting this loop, by a
distance, was label names in the prompts that the repo did not have — it happened on two
of three ports. A reviewer following the repo and a builder following the doc deadlock on
the first handoff, and the worse case runs cleanly right up until the first review that
finds something.

**Ask the person these questions** (use `AskUserQuestion`; the answers change what gets
rendered):

1. **Who merges — the builder, after mechanical checks, or a person?** Default: the
   builder. The checks a session runs (base before child, head equals the passed head) are
   ones a person reading a graph runs less reliably. The cost is that a wrong first-pass
   LGTM moves no hand-back counter and nothing stands between it and the base branch but
   the reviewer's own care. Make that trade explicit.
2. **Will builders ever run in parallel?** If yes, the claim must be a durable label on
   the item, because one session's memory is invisible to another. One repo had a
   complete, tested commit sit unpushed in a worktree for five days while its issue showed
   no sign any work existed.
3. **Merge method** — merge commit, squash, or rebase. Default: whatever
   `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` says the
   repo allows, preferring merge commits if stacks are used.
4. **Poll interval and fan-out cap.** Defaults 120 s and 3. Minutes, not seconds — this is
   a remote API and the queue moves at human speed.

**Then derive the labels.** The three states every loop needs:

| State | Placeholder | Reuse an existing label when… |
|---|---|---|
| waiting for review | `LABEL_WAITING` | one already means "needs a reviewer" |
| review passed | `LABEL_PASSED` | one already means "approved / ready to land" |
| changes requested | `LABEL_CHANGES` | one already means "back to the author" |
| claimed (only if parallel builders) | `LABEL_CLAIMED` | one already means "in progress" |

Read the preflight's label list. Reuse a label only if its existing meaning matches; a
`bug` or `enhancement` label is a category, not a state, and does not qualify. For every
state with no match, **create the label now** and confirm it took:

```bash
gh label create ready-for-review   --repo <owner/name> --color 0e8a16 --description "Waiting for a reviewer"
gh label create ready-to-merge     --repo <owner/name> --color 1d76db --description "Reviewed and clean; authorises a merge"
gh label create changes-requested  --repo <owner/name> --color d93f0b --description "Findings the reviewer could not place; back to the builder"
gh label list --repo <owner/name>
```

Reading `gh label list` and then writing names the list does not contain is the exact
failure this step exists to prevent. Never render a label you have not seen in that list.

**Labels live on the PR** in the templates. That is the right choice when one issue can
spawn several PRs — an issue-level label cannot say which of three stacked PRs to read.
If the person insists on issue-level labels, the templates need adapting (poll
`gh issue list --label …`, resolve the PR via `closingIssuesReferences`, require
`Closes #N` in every PR body and verify it took); say plainly that the bundled commands
were proven in PR mode and the adaptation has not been.

## Step 3 — Write the merge predicate, then attack it

The contract template carries the predicate; read it before rendering and confirm it holds
for this repo. Whoever merges, the predicate must be false for any commit no reviewer has
read. The two-clause version — *passed on, changes-requested off* — has a hole: push a
commit and hand the PR back, and it carries both *passed* and *waiting* at once, so the
unreviewed commit merges. **The third clause is that *waiting for review* is also off.**
The fourth is that the head equals the head the pass was taken at, read from the timeline
and cross-checked against the sha the LGTM names.

Then read the state table and check every state has exactly one way in and one way out
for this repo's choices. Two rules that came out of attacking it:

- **A label meaning "passed" must not outlive the pass.** Withdraw it on a base move or a
  push.
- **Do not clean up labels at merge time.** The passed label on a merged PR is the only
  durable evidence the work was reviewed. Closed PRs sit in no queue.

## Step 4 — Render

```bash
bash <skill-dir>/scripts/render.sh <repo-path> \
  REPO=<owner/name> BASE_BRANCH=<main> \
  LABEL_WAITING=<…> LABEL_PASSED=<…> LABEL_CHANGES=<…> [LABEL_CLAIMED=<…>] \
  TEST_CMD='<the command that passed in step 1>' \
  TOOL_GLOBS='<allowed-tools entries that command needs, e.g. npm*>' \
  MERGER=builder|person [MERGE_METHOD=merge|squash|rebase] [POLL=120] [ACTIVE=3] \
  [CONTRACT_PATH=docs/review-loop.md]
```

It writes the contract to `CONTRACT_PATH`, the two commands to `.claude/commands/`, and
refuses to finish if any `{{PLACEHOLDER}}` survives. The substitution covers the
`allowed-tools` frontmatter as well as the body — the `gh api repos/<owner>/<name>/…`
globs there are the one place a missed substitution does not show up in prose, and a wrong
slug there turns the paginated hand-back count into a permission prompt, which invariant 3
then turns into a watch that is silent forever.

Then add **one line** to the repo's `CLAUDE.md` pointing at the contract (the script
prints it). The full contract does not go in `CLAUDE.md`: it loads into every session,
including the ones that have nothing to do with the loop.

Everything that varies between repos is what steps 1–3 determined. If you find yourself
editing a rendered command by hand for something else, that is a bug in the template —
fix the template here, not the copy.

## Step 5 — Verify before declaring done

1. **Labels:** every value you passed as `LABEL_*` appears in
   `gh label list --repo <owner/name> --json name --jq ".[].name"`. Check each one by name.
2. **No placeholders:** `grep -rn '{{' <repo>/.claude/commands/ <repo>/<CONTRACT_PATH>`
   is empty.
3. **The poll runs:** execute one iteration of the reviewer's query line by hand —
   `gh pr list --repo <owner/name> --label <LABEL_WAITING> --state open --limit 100 --json number,headRefOid`
   — and see it exit 0 (an empty array is fine). Same for the builder's two lists and one
   `compare` call if any PR carries the passed label.
4. **The test command** ran and passed in step 1; say so with the output, not from memory.
5. **Resumability** is the acceptance test for the first real round, not something to
   simulate now: clear context mid-queue and see whether the next round proceeds from the
   labels and the PR comment alone. Tell the person that is the test.

Report: the verdict, the label set and which labels were created, the merger choice and
its trade, the test command and its output, the files written, and the holes below.

## What this does not give you

Say these out loud rather than letting them be discovered.

- **`allowed-tools` is pre-approval, not a deny.** A call outside the list prompts a
  person; under bypassed permissions it stops nothing. It removes the silent path.
- **`git push origin HEAD:*` admits `HEAD:<base>`**, which lands everything and skips
  every check. No glob admits arbitrary runtime branch names while excluding the base
  branch. The rendered contract names the hole and the repairs (drop the glob and let
  every push prompt; a `PreToolUse` hook; branch protection on the remote). Choosing is
  the person's.
- **The loop converges; it does not decide.** Nothing here can mechanise "this feature is
  good enough." Three hand-backs is where a person comes in.
- **Session naming is the only role enforcement.** Nothing stops someone opening a session
  named `reviewer` and running `/builder-watch` in it.
- **Reviewing a PR runs the PR.** The reviewer runs the test command in a worktree checked
  out from the branch, and a trusted worktree auto-runs any `.claude/` hook, `.mcp.json`, or
  `CLAUDE.md` the branch carries — under the session's (bypassed) permissions. Where PRs come
  only from your own builder that is your own code; where they can come from anywhere it is
  code execution on the review host, and neither `allowed-tools` nor the session name is in
  front of it. Launch the sessions with `--setting-sources user` so a branch's project config
  cannot auto-run, and if the builder takes untrusted input, gate the merge verb behind a human
  tap or one-shot token, not the session name. The rendered contract carries the full note.
- **Merging is not deploying.** The loop's last state is *merged* — a repo that runs its own
  merged code (a service, a bot, an agent that reads its own config) needs a separate step to
  pull and restart what the change touched, and "merged" reported as "live" is a real hole.
  The loop stops at the merge on purpose; merge→live is the operator's to wire.
