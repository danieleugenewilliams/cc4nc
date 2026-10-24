#!/usr/bin/env bash
# Render the loop's contract and its watch commands into a target repo.
# Usage:
#   render.sh <repo-path> KEY=VALUE [KEY=VALUE ...]
# Required keys:
#   REPO            owner/name                     e.g. REPO=acme/widgets
#   BASE_BRANCH     branch PRs merge into          e.g. BASE_BRANCH=main
#   LABEL_WAITING   "waiting for review" label     e.g. LABEL_WAITING=ready-for-review
#   LABEL_PASSED    "review passed" label          e.g. LABEL_PASSED=ready-to-merge
#   LABEL_CHANGES   "changes requested" label      e.g. LABEL_CHANGES=changes-requested
#   TEST_CMD        the command that must pass     e.g. TEST_CMD='npm test'
#   TOOL_GLOBS      allowed-tools entries the test command needs, comma-separated
#                   e.g. TOOL_GLOBS='npm*' or TOOL_GLOBS='go*, make*'
#   MERGER          builder | person
#   SESSION_PREFIX  the exact prefix of this loop's session names, e.g. SESSION_PREFIX=agentux
#                   gives agentux-builder, agentux-reviewer, agentux-coordinator. Not derived
#                   from REPO: the running sessions' names are what messages are addressed to,
#                   and a derived prefix (agent-ux) matched none of them on the first loop that
#                   tried it. Read the names off ListAgents before choosing.
# Optional keys (defaults shown):
#   POLL=120  ACTIVE=3  MERGE_METHOD=merge  CONTRACT_PATH=docs/review-loop.md
#   LABEL_CLAIMED=   (empty = no claimed state; set when builders run in parallel)
#   LABEL_BLOCKED=   (empty = no blocked state; set when the repo has a label meaning
#                     "waiting on a decision only a person can make", e.g. needs-a-human)
#   NEW_WORK_LABEL=  (empty = any open issue; set to restrict what the builder takes, e.g. bug)
#   NEW_WORK_REASON= (required with NEW_WORK_LABEL: one sentence saying why, rendered next to the rule)
#   REVIEWER_FIXES=yes  (no = the reviewer posts findings only and never edits the PR;
#                        every finding goes back to the builder as LABEL_CHANGES)
#   COORDINATOR=yes     (no = two sessions only; no coordinator command is rendered)
#                       COORDINATOR=yes requires LABEL_BLOCKED: holds and proposals use it.
#   LABEL_PAUSED=loop-paused        on one open issue: the whole loop takes no new work
#   OUTCOME_PATH=docs/outcome.md    the person's own statement of what the project is for
#   LENSES_PATH=docs/review-lenses.md  what this project is reviewed through
#   CHECKS_DIR=scripts/checks       where the check each issue's "done when" gets is committed
#   STUCK_HOURS=3       the coordinator's "waiting for review with no update" threshold
#
# Writes: <repo>/<CONTRACT_PATH>, <repo>/.claude/commands/reviewer-watch.md,
#         <repo>/.claude/commands/builder-watch.md, and with COORDINATOR=yes
#         <repo>/.claude/commands/coordinator.md. Refuses to leave any {{PLACEHOLDER}}.

set -euo pipefail
# declare -A needs bash 4+. macOS /bin/bash is 3.2 and dies on the first key with an unbound
# variable; say why instead.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "render.sh needs bash 4 or later (this is $BASH_VERSION); run it with a newer bash, e.g. Homebrew's" >&2; exit 1
fi
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="${1:?repo path}"; shift
declare -A v=( [POLL]=120 [ACTIVE]=3 [MERGE_METHOD]=merge [CONTRACT_PATH]=docs/review-loop.md [LABEL_CLAIMED]= [LABEL_BLOCKED]= [REVIEWER_FIXES]=yes [NEW_WORK_LABEL]= [NEW_WORK_REASON]=
               [COORDINATOR]=yes [LABEL_PAUSED]=loop-paused [OUTCOME_PATH]=docs/outcome.md [LENSES_PATH]=docs/review-lenses.md [CHECKS_DIR]=scripts/checks [STUCK_HOURS]=3 )
for kv in "$@"; do v["${kv%%=*}"]="${kv#*=}"; done
for k in REPO BASE_BRANCH LABEL_WAITING LABEL_PASSED LABEL_CHANGES TEST_CMD TOOL_GLOBS MERGER SESSION_PREFIX; do
  [ -n "${v[$k]:-}" ] || { echo "missing $k" >&2; exit 1; }
done
case "${v[MERGER]}" in builder|person) ;; *) echo "MERGER must be builder or person" >&2; exit 1;; esac
case "${v[REVIEWER_FIXES]}" in yes|no) ;; *) echo "REVIEWER_FIXES must be yes or no" >&2; exit 1;; esac
case "${v[COORDINATOR]}" in yes|no) ;; *) echo "COORDINATOR must be yes or no" >&2; exit 1;; esac
case "${v[STUCK_HOURS]}" in ''|*[!0-9]*) echo "STUCK_HOURS must be a whole number of hours" >&2; exit 1;; esac
if [ "${v[COORDINATOR]}" = yes ] && [ -z "${v[LABEL_BLOCKED]}" ]; then
  echo "COORDINATOR=yes needs LABEL_BLOCKED (e.g. needs-human): the coordinator's holds and proposals are that label" >&2; exit 1
fi
P="${v[SESSION_PREFIX]}"
v[BUILDER_NAME]="$P-builder"; v[REVIEWER_NAME]="$P-reviewer"; v[COORDINATOR_NAME]="$P-coordinator"
v[STUCK_SECONDS]=$(( v[STUCK_HOURS] * 3600 ))
# A filesystem-safe tag for the watches' state files, so two loops on one machine never share one.
v[REPO_TAG]="${v[REPO]//\//-}"

# The sessions, by exact name. The coordinator is optional; what it would do falls to the
# builder (filing follow-ups) or to the person (relaying their own decisions) without it.
if [ "${v[COORDINATOR]}" = yes ]; then
  v[SESSION_LIST]="\`${v[BUILDER_NAME]}\`, \`${v[REVIEWER_NAME]}\` and \`${v[COORDINATOR_NAME]}\`"
  v[COORDINATOR_ROLE]=$(cat <<'P'

A **coordinator** (`{{COORDINATOR_NAME}}`) is the person's line into the loop while it runs.
It records their decisions and scope changes on the issues, holds and pauses work, files
follow-ups, raises the builder's open questions with the person, and reports. It commits
nothing to this repository, reviews nothing, merges nothing, never relays a merge approval,
and never touches `{{LABEL_WAITING}}`, `{{LABEL_PASSED}}` or `{{LABEL_CHANGES}}`. Its command
is `/coordinator`.
P
)
  v[FOLLOWUP_FILER]="\`${v[COORDINATOR_NAME]}\`"
  v[MSG_SENDER]="\`${v[COORDINATOR_NAME]}\`"
  v[NOTE_WRITER]="the coordinator for what reaches it, the builder for a decision given in the builder session"
  v[QUESTION_PING]="then one line to \`${v[COORDINATOR_NAME]}\` naming the issue, if that session is running"
  v[NEAR_MISS_NAMES]="\`${v[COORDINATOR_NAME]}\` or \`${v[REVIEWER_NAME]}\`"
  v[MERGE_WAIT_NOTE]="the coordinator's status leads with them so the wait is visible."
  v[QUESTION_ROUTE]="\`${v[COORDINATOR_NAME]}\` raises it with the person and records the answer on the issue"
else
  v[SESSION_LIST]="\`${v[BUILDER_NAME]}\` and \`${v[REVIEWER_NAME]}\`"
  v[COORDINATOR_ROLE]=""
  v[FOLLOWUP_FILER]="the builder"
  # No coordinator: the Messages sections name only the two sessions that exist.
  v[MSG_SENDER]="another session of this loop"
  v[NOTE_WRITER]="the builder for a decision given in the builder session, or the person for one given anywhere else"
  v[QUESTION_PING]="then notify the person"
  v[NEAR_MISS_NAMES]="\`${v[REVIEWER_NAME]}\`"
  v[MERGE_WAIT_NOTE]="the notification is the only place the wait shows, so send it."
  v[QUESTION_ROUTE]="the session that asked notifies the person, and records the answer on the issue when it comes"
fi

if [ "${v[COORDINATOR]}" = yes ]; then
  v[PAUSE_SETTER]=" or coordinator"
  v[ENV_COORDINATOR]=" and to \`${v[COORDINATOR_NAME]}\`, which keeps it in its status until it is fixed"
else
  v[PAUSE_SETTER]=""
  v[ENV_COORDINATOR]=""
fi
if [ -n "${v[LABEL_BLOCKED]}" ]; then
  v[HOLD_RULE]="Hold one item by adding \`${v[LABEL_BLOCKED]}\` to it, with a comment saying it is a hold and why: nothing takes, reviews or merges it until the label comes off. One label for \"waiting on the person\" — a decision, a hold or an unapproved proposal — because four overlapping labels get misread, and the first loop already used its blocked label for all three."
else
  v[HOLD_RULE]="There is no per-item hold without a blocked label; pause the loop, or set \`LABEL_BLOCKED\` and re-render."
fi
if [ -n "${v[LABEL_BLOCKED]}" ]; then
  v[QUESTION_RULE]="is the blocked label, \`${v[LABEL_BLOCKED]}\`, on the issue or PR, with a comment naming the decision and its options in full; ${v[QUESTION_ROUTE]}."
else
  v[QUESTION_RULE]="gets a comment naming the decision and its options in full; ${v[QUESTION_ROUTE]}. Until it is answered, the session stops on that item."
fi

# Prose fragments that depend on a choice, so the templates read cleanly either way.
if [ "${v[MERGER]}" = builder ]; then
  v[MERGER_SENTENCE]="The **builder** merges, on \`mergeable\` and only after the checks above."
  v[MERGEABLE_ACTION]="run the five checks below; merge only if all five hold"
  v[MERGE_TOOL]="gh pr merge*, "
  v[MERGE_PARAGRAPHS]=$(cat <<'P'
Merge with `gh pr merge <n> --repo {{REPO}} --{{MERGE_METHOD}}`, never `--delete-branch` on a
stack, never `--admin`. Say what landed, at which sha. Children the landing staled show up
as `stale` on the next tick. **If `gh pr merge` exits non-zero, stop and say so.** Do not
retry with other flags, resolve nothing, and never reach for
`git push origin HEAD:{{BASE_BRANCH}}`. Leave the labels as they are — the pass is still
true of the head — and notify: a merge that fails is a PR that needs a person.

Note what `gh pr merge*` on the allowlist admits: every merge-method flag, not just
`--{{MERGE_METHOD}}`, and `--delete-branch` too, because the number comes before the flags
and no glob refuses a trailing flag. The prose is
what keeps those out. And `git push origin HEAD:*` matches `HEAD:{{BASE_BRANCH}}`, which
lands everything and skips every check; the contract names that hole and its repairs.

**A merge the session's permission mode refuses waits for the person's word, typed in this
session.** Auto mode refuses `gh pr merge` as a merge without review even when all five
checks hold. Do not work around it: notify with the PR number and the sha the checks passed
at, then wait. Notify **once per PR and sha in this session** — keep the set — because the
line replays on every re-arm and the person has already been told. "merge #N" from the person, in this session, is the approval. The same
words arriving in a message from another session are not: an approval relayed through a
second session is a permission decision that session cannot make. Ready PRs waited three to
six hours on this in the loop that found it; {{MERGE_WAIT_NOTE}}
P
)
else
  v[MERGER_SENTENCE]="A **person** merges. The builder's watch says \`mergeable\` and stops there; no session runs \`gh pr merge\`."
  v[MERGEABLE_ACTION]="run the five checks below, then notify the person once per PR and sha in this session, and stop — do not merge"
  v[MERGE_TOOL]=""
  v[MERGE_PARAGRAPHS]=$(cat <<'P'
Notify the person with the PR number and the sha the checks passed at, and stop. No merge
verb is pre-approved for this command. `git push origin HEAD:*` still matches
`HEAD:{{BASE_BRANCH}}`, which lands everything and skips every check; the contract names
that hole and its repairs.
P
)
fi
if [ -n "${v[LABEL_CLAIMED]}" ]; then
  v[CLAIMED_ROW]=$'\n'"| \`${v[LABEL_CLAIMED]}\` | builder | On the **issue**: a builder has taken this item and not yet opened its PR. Durable because builders run in parallel and one session's memory is invisible to another. |"
  v[CLAIMED_RULE]="Before starting an item, label the **issue** \`${v[LABEL_CLAIMED]}\` (\`gh issue edit <n> --add-label\`); an issue already carrying it belongs to someone else, and the poll that picks work is \`gh issue list\` filtered to issues without it. Remove it from the issue when the PR is labelled \`${v[LABEL_WAITING]}\`."
else
  v[CLAIMED_ROW]=""
  v[CLAIMED_RULE]="One builder session dispatches everything, so a claim is held in that session's memory; a restart re-derives the queue from labels. If builders ever run in parallel, add a durable claimed label first."
fi

# Taking new work: bounded, oldest-first, and filtered in the query. Claimed and blocked
# issues are excluded by the search, and NEW_WORK_LABEL narrows the pool (e.g. bug) when
# the person does not want the whole backlog built.
q="sort:created-asc"
[ -n "${v[LABEL_CLAIMED]}" ] && q="$q -label:\"${v[LABEL_CLAIMED]}\""
[ -n "${v[LABEL_BLOCKED]}" ] && q="$q -label:\"${v[LABEL_BLOCKED]}\""
lf=""; [ -n "${v[NEW_WORK_LABEL]}" ] && lf=" --label '${v[NEW_WORK_LABEL]}'"
v[NEW_WORK_CMD]="gh issue list --repo ${v[REPO]} --state open --limit 200$lf --search '$q' --json number,title --jq '.[] | \"\\(.number) \\(.title)\"'"
if [ -n "${v[LABEL_CLAIMED]}" ]; then
  v[LABELS_INTRO_EXTRA]=" The exception is the claimed label, \`${v[LABEL_CLAIMED]}\`: it marks an **issue** a builder has taken before any PR exists, and comes off once the PR is labelled."
else
  v[LABELS_INTRO_EXTRA]=""
fi
if [ -n "${v[LABEL_BLOCKED]}" ]; then
  v[LABELS_INTRO_EXTRA]="${v[LABELS_INTRO_EXTRA]} The blocked label, \`${v[LABEL_BLOCKED]}\`, may sit on either the issue or the PR, and blocks from both."
fi

# NEW_WORK_LABEL narrows what the builder takes. The reason has to travel with the rule:
# a filter whose reason lives only in a PR comment is the one the next agent removes.
CLAIM_ASSIGN_NOTE=""
[ -n "${v[LABEL_CLAIMED]}" ] && CLAIM_ASSIGN_NOTE=" A person does not assign work by labelling an issue \`${v[LABEL_CLAIMED]}\` — that label means a builder already holds the issue, and every new-work query skips it, so an issue labelled that way is stranded."
if [ -n "${v[NEW_WORK_LABEL]}" ]; then
  [ -n "${v[NEW_WORK_REASON]:-}" ] || { echo "NEW_WORK_LABEL needs NEW_WORK_REASON (why the builder's scope is narrowed)" >&2; exit 1; }
  v[NEW_WORK_SCOPE]=" **Only issues labelled \`${v[NEW_WORK_LABEL]}\` are taken** — ${v[NEW_WORK_REASON]} Everything else in the backlog is a person's to assign: they tell a builder session to take a specific issue, and the builder claims it as usual, or they widen this scope.${CLAIM_ASSIGN_NOTE}"
  v[NEW_WORK_SCOPE_SHORT]=", restricted to issues labelled \`${v[NEW_WORK_LABEL]}\` (${v[NEW_WORK_REASON]%.})"
else
  v[NEW_WORK_SCOPE]=""
  v[NEW_WORK_SCOPE_SHORT]=""
fi

# The stale/mergeable candidate set: PRs whose only flow label is the passed one.
fl="\"${v[LABEL_WAITING]}\",\"${v[LABEL_PASSED]}\",\"${v[LABEL_CHANGES]}\""
[ -n "${v[LABEL_CLAIMED]}" ] && fl="$fl,\"${v[LABEL_CLAIMED]}\""
[ -n "${v[LABEL_BLOCKED]}" ] && fl="$fl,\"${v[LABEL_BLOCKED]}\""
v[PASSED_ONLY_JQ]="| select([.labels[].name | select(IN($fl))] == [\"${v[LABEL_PASSED]}\"]) "

# The flow labels, named in full. The merge check is "the passed label is the only one of
# these on the PR" — a permitted state, not a list of labels that must be absent. An
# exclusion list silently widens the moment a label is added and nobody revisits it; one
# repo's predicate forgot two labels that way, twice, and would have merged past a gate.
flow="\`${v[LABEL_WAITING]}\`, \`${v[LABEL_PASSED]}\`, \`${v[LABEL_CHANGES]}\`"
[ -n "${v[LABEL_CLAIMED]}" ] && flow="$flow, \`${v[LABEL_CLAIMED]}\`"
[ -n "${v[LABEL_BLOCKED]}" ] && flow="$flow, \`${v[LABEL_BLOCKED]}\`"
v[FLOW_LABELS]="$flow"

if [ -n "${v[LABEL_BLOCKED]}" ]; then
  B="${v[LABEL_BLOCKED]}"
  BLOCKED_BY_COORD=""
  [ "${v[COORDINATOR]}" = yes ] && BLOCKED_BY_COORD=" (or the coordinator, on the person's word, after recording the decision on the issue)"
  # Without a claimed label these clauses have nothing to name; drop them rather than
  # render a stand-in like `a claim` that reads as a label the repo does not have.
  CLAIM_SWAP=""; CLAIM_SKIP_NOTE=""
  if [ -n "${v[LABEL_CLAIMED]}" ]; then
    CLAIM_SWAP=" (replacing \`${v[LABEL_CLAIMED]}\` if the issue carries it)"
    CLAIM_SKIP_NOTE=" The one label a reviewer does not skip is \`${v[LABEL_CLAIMED]}\` next to \`${v[LABEL_WAITING]}\`: that PR was handed off and the claim was left behind, so review it and say so in the comment rather than leave it stalled unseen."
  fi
  v[BLOCKED_ROW]=$'\n'"| \`$B\` | either | Blocked on a decision only a person can make — an open product question, an unratified spec, a release gate. On the issue or the PR. Not reviewable work and not buildable work: both sessions leave it alone until a person removes it${BLOCKED_BY_COORD}. Also a hold, and an unapproved proposal. |"
  v[BLOCKED_TABLE_ROWS]=$'\n'"| any | the work needs a decision, not code | either | adds \`$B\`, says what the decision is, stops |
| \`$B\` | the person decides and removes it | person${BLOCKED_BY_COORD} | the state it was in before |"
  v[BLOCKED_RULE]="Blocks: when the work turns out to need a decision rather than code, add \`$B\`${CLAIM_SWAP}, say in a comment what the decision is, and stop. Do not guess and keep building. The builder takes no issue carrying it, the reviewer skips a PR carrying it, and the merge check refuses it on the PR **or** on any issue the PR closes. Only a person takes it off${BLOCKED_BY_COORD}."
  v[BLOCKED_TAKE_RULE]=" Skip any issue carrying \`$B\`: it is waiting on a person, not on capacity."
  v[SKIP_BLOCKED_JQ]="| select(any(.labels[].name; . == \"$B\") | not) "
  v[SKIP_BLOCKED_NOTE]="- **PRs carrying \`$B\` are filtered out of the queue.** They wait on a decision, not a review.${CLAIM_SKIP_NOTE}"
else
  v[BLOCKED_ROW]=""
  v[BLOCKED_TABLE_ROWS]=""
  v[BLOCKED_RULE]=""
  v[BLOCKED_TAKE_RULE]=""
  v[SKIP_BLOCKED_JQ]=""
  v[SKIP_BLOCKED_NOTE]=""
fi

# With a claimed or blocked label, flow labels can sit on the issue too, so the merge check
# reads the closed issues as a permitted state as well: they carry none. Refusing only the
# blocked label there is an exclusion list of one — it merges "passed, then more work
# assigned" (passed on the PR, the claim back on the issue).
if [ -n "${v[LABEL_CLAIMED]}${v[LABEL_BLOCKED]}" ]; then
  if [ -n "${v[LABEL_CLAIMED]}" ]; then
    ISSUE_CLAUSE_WHY=" The claim comes off the issue at handoff, so a flow label there is new work assigned after the pass or a gate filed on the issue; either way, not mergeable."
  else
    ISSUE_CLAUSE_WHY=" A flow label there is a gate filed on the issue after the pass; not mergeable."
  fi
  v[BLOCKED_ISSUE_CLAUSE]=" And no issue the PR closes carries **any** flow label — read them with \`gh pr view <n> --json closingIssuesReferences\` and \`gh issue view\`.${ISSUE_CLAUSE_WHY}"
else
  v[BLOCKED_ISSUE_CLAUSE]=""
fi

if [ "${v[REVIEWER_FIXES]}" = yes ]; then
  v[REVIEWER_SUMMARY]="reads each PR, fixes what it can, and hands back what it cannot."
  v[CHANGES_MEANING]="Findings the reviewer could not place here. Back to the builder."
  v[CHANGES_TRANSITION]="review finds work only the builder can place"
  v[REVIEWER_WRITE_TOOLS]="git add*, git commit*, git push origin HEAD:*, "
  v[HANDBACK_INTRO]="the reviewer could not place a finding."
  v[REVIEWER_CLAIM_REASON]="It is this round's own fix push showing up as a fresh event. The window between pushing a fix and swapping the label is minutes, against a poll measured in minutes, so this is the common path."
  v[REVIEWER_CONTRACT_SECTION]=$(cat <<'P'
Polls `gh pr list --label {{LABEL_WAITING}}`. Reviews, reproduces each finding before
believing it — *review findings are claims* — fixes what this PR introduced, verifies the
fix, runs `{{TEST_CMD}}`, and posts **one comment on that PR** with only that PR's findings
and what it changed. Then labels: `{{LABEL_PASSED}}` with **LGTM `<sha>`** on the first
line if nothing is outstanding; `{{LABEL_CHANGES}}` with the findings listed if something
is. **The LGTM names the head it vouches for** — the sha re-read just before labelling,
which is the reviewer's own fix commit if it pushed one. An LGTM naming no sha is a pass
nobody can act on.

The reviewer verifies its own fixes, and that is deliberate. The alternative is a fourth
state and a second round trip to bless a typo. Its repairs are covered by the *verify* it
already owes, and the comment naming them is on the PR before anything merges.

`{{LABEL_CHANGES}}` does not mean *the review failed*. It means *there is work here only
the builder can put in the right place*: a decision that is a person's, or a repair that
belongs in an earlier PR.
P
)
  v[TWO_SESSIONS]=$(cat <<'P'
A branch checks out once. The reviewer works in a **detached** worktree at the sha it
reviewed (`git worktree add --detach`), pushes with `git push origin HEAD:<branch>`, and
removes the worktree when its comment is posted. The builder fetches before touching a
branch it has handed off. Neither commits into the other's tree, and neither force-pushes:
the commit that would go is the other session's.
P
)
  v[REVIEWER_COMMENT_TAIL]=" and what it changed"
  v[REVIEWER_PUSH_NOTE]=" Push with \`git push origin HEAD:<branch>\`, which needs no local branch and never touches the builder's tree."
  v[REVIEWER_STEP5]=$(cat <<'P'
5. Fix what this PR introduced, verify the fix, and run `{{TEST_CMD}}`. **Record the head
   it expects to see at step 7**: `git rev-parse HEAD | cut -c1-7` after its own push if it
   pushed, otherwise the sha from the event line. `cut`, not `--short=7`: `--short` is a
   *minimum* width and git widens it when seven characters are ambiguous locally, so it
   would compare eight characters against the `[0:7]` step 7 asks GitHub for and match
   nothing.

   A **rejected** push is step 7's condition arriving early: the builder pushed during the
   review. Never `--force` — the commit that would go is the builder's. Leave the push
   undone and take step 7's refusal.
P
)
  v[REVIEWER_STEP7_NOTE]=$(cat <<'P'
   Compare against **step 5's recorded head, not the event line**. A review that found
   something fixed and pushed, so on that path the head has always moved, by the reviewer's
   own commit; comparing to the event line would refuse to label every review that did
   work.
P
)
  v[REVIEWER_PUSH_HOLE]=$(cat <<'P'
One route is still pre-approved: `git push origin HEAD:*` matches `HEAD:{{BASE_BRANCH}}`.
No glob admits runtime branch names while excluding the base branch. The contract names
this hole and the repairs; do not read this section as saying it is closed.
P
)
else
  v[REVIEWER_SUMMARY]="reads each PR and hands back every finding. It never edits what it reviews."
  v[CHANGES_MEANING]="The review found something unresolved. Back to the builder, who places every fix."
  v[CHANGES_TRANSITION]="review finds anything unresolved"
  v[REVIEWER_WRITE_TOOLS]=""
  v[HANDBACK_INTRO]="the reviewer found something. By contract it fixed nothing, so every finding is yours to place."
  v[REVIEWER_CLAIM_REASON]="This reviewer pushes nothing, so a second event for a PR under review is the builder pushing while the round runs. The round's step 7 sees the moved head and refuses to label, and the re-read on release dispatches the new head — a second concurrent round would only race the first to the comment."
  v[REVIEWER_CONTRACT_SECTION]=$(cat <<'P'
Polls `gh pr list --label {{LABEL_WAITING}}`. Reviews, reproduces each finding before
believing it — *review findings are claims* — runs `{{TEST_CMD}}` against the head it read,
and posts **one comment on that PR** with only that PR's findings. Then labels:
`{{LABEL_PASSED}}` with **LGTM `<sha>`** on the first line if there are no findings;
`{{LABEL_CHANGES}}` with the findings listed if there are any. **The LGTM names the head it
vouches for** — the sha it read, re-read just before labelling. An LGTM naming no sha is a
pass nobody can act on.

**The reviewer never fixes what it is reviewing** — not a typo, not the reviewed document
itself. A session that reviews and then edits is both roles at once, which is the thing
this loop exists to prevent, and its push races the builder's own branch. That costs a
round trip for a one-character fix, and the round trip is the price of a second opinion
that stays a second opinion.

When a later round fails a PR that an earlier round passed, the reviewer also takes
`{{LABEL_PASSED}}` off. Leaving it on puts two verdicts on one PR, and one of them is false.
P
)
  v[TWO_SESSIONS]=$(cat <<'P'
A branch checks out once. The reviewer reads in a **detached** worktree at the sha it
reviewed (`git worktree add --detach`), runs the verification command there, and removes
the worktree when its comment is posted. It commits nothing and pushes nothing, so the
branch has one writer: the builder.
P
)
  v[REVIEWER_PUSH_NOTE]=" It never pushes: this reviewer places no fixes."
  v[REVIEWER_STEP5]=$(cat <<'P'
5. Run `{{TEST_CMD}}` in the worktree. **Fix nothing** — not a typo, not a comment. Every
   finding goes into the comment for the builder to place. **Record the head it expects to
   see at step 7**: the sha from the event line, since this round pushes nothing.
P
)
  v[REVIEWER_STEP7_NOTE]="   This round pushed nothing, so the recorded head is the event line's sha."
  v[REVIEWER_COMMENT_TAIL]=""
  v[REVIEWER_PUSH_HOLE]="No push is pre-approved either: this reviewer places no fixes, so \`git push\`, \`git add\` and \`git commit\` are left off the list. A call to one prompts a person — which is the point, since it would be the reviewer editing what it reviews."
fi

render() {  # $1 template, $2 output
  local out="$2" tmp; tmp="$(mktemp)"
  cp "$1" "$tmp"
  # {{INVARIANTS}} pulls in the reference file verbatim.
  if grep -q '{{INVARIANTS}}' "$tmp"; then
    awk -v f="$here/reference/invariants.md" '/\{\{INVARIANTS\}\}/{while((getline l<f)>0)print l;next}1' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
  fi
  for pass in 1 2; do for k in "${!v[@]}"; do
    # perl for literal replacement: values may contain / & | etc.
    K="$k" V="${v[$k]}" perl -pi -e 's/\{\{\Q$ENV{K}\E\}\}/$ENV{V}/g' "$tmp"
  done; done
  if grep -n '{{[A-Z_]*}}' "$tmp"; then echo "unfilled placeholders in $1 (above)" >&2; rm -f "$tmp"; exit 1; fi
  mkdir -p "$(dirname "$out")"; mv "$tmp" "$out"; echo "wrote $out"
}

render "$here/templates/contract.md"       "$repo/${v[CONTRACT_PATH]}"
render "$here/templates/reviewer-watch.md" "$repo/.claude/commands/reviewer-watch.md"
render "$here/templates/builder-watch.md"  "$repo/.claude/commands/builder-watch.md"
if [ "${v[COORDINATOR]}" = yes ]; then
  render "$here/templates/coordinator.md"  "$repo/.claude/commands/coordinator.md"
  runs="Sessions named exactly \`${v[BUILDER_NAME]}\`, \`${v[REVIEWER_NAME]}\` and \`${v[COORDINATOR_NAME]}\` run \`/builder-watch\`, \`/reviewer-watch\` and \`/coordinator\`."
else
  runs="Sessions named exactly \`${v[BUILDER_NAME]}\` and \`${v[REVIEWER_NAME]}\` run \`/builder-watch\` and \`/reviewer-watch\`."
fi
echo
echo "Next: add one pointer line to $repo/CLAUDE.md, e.g."
echo "  - Builder–reviewer loop: see \`${v[CONTRACT_PATH]}\` (roles, labels, merge predicate). $runs"
