#!/usr/bin/env bash
# Render the loop's contract and two watch commands into a target repo.
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
# Optional keys (defaults shown):
#   POLL=120  ACTIVE=3  MERGE_METHOD=merge  CONTRACT_PATH=docs/review-loop.md
#   LABEL_CLAIMED=   (empty = no claimed state; set when builders run in parallel)
#
# Writes: <repo>/<CONTRACT_PATH>, <repo>/.claude/commands/reviewer-watch.md,
#         <repo>/.claude/commands/builder-watch.md. Refuses to leave any {{PLACEHOLDER}}.

set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="${1:?repo path}"; shift
declare -A v=( [POLL]=120 [ACTIVE]=3 [MERGE_METHOD]=merge [CONTRACT_PATH]=docs/review-loop.md [LABEL_CLAIMED]= )
for kv in "$@"; do v["${kv%%=*}"]="${kv#*=}"; done
for k in REPO BASE_BRANCH LABEL_WAITING LABEL_PASSED LABEL_CHANGES TEST_CMD TOOL_GLOBS MERGER; do
  [ -n "${v[$k]:-}" ] || { echo "missing $k" >&2; exit 1; }
done
case "${v[MERGER]}" in builder|person) ;; *) echo "MERGER must be builder or person" >&2; exit 1;; esac

# Prose fragments that depend on a choice, so the templates read cleanly either way.
if [ "${v[MERGER]}" = builder ]; then
  v[MERGER_SENTENCE]="The **builder** merges, on \`mergeable\` and only after the checks below."
  v[MERGEABLE_ACTION]="run the four checks below and merge"
  v[MERGE_TOOL]="gh pr merge*, "
  v[MERGE_PARAGRAPHS]=$(cat <<'P'
Merge with `gh pr merge <n> --repo {{REPO}} --{{MERGE_METHOD}}`, never `--delete-branch` on a
stack, never `--admin`. Say what landed, at which sha. Children the landing staled show up
as `stale` on the next tick. **If `gh pr merge` exits non-zero, stop and say so.** Do not
retry with other flags, resolve nothing, and never reach for
`git push origin HEAD:{{BASE_BRANCH}}`. Leave the labels as they are — the pass is still
true of the head — and notify: a merge that fails is a PR that needs a person.

`gh pr merge*` appears on this command's allowlist, but the comma-inside form that line
uses matches nothing, so the merge is not pre-approved: a person approves it, or in auto
mode the classifier passes it. Do not rewrite the line into one `Bash()` per rule to make it
match — that would pre-approve `gh pr merge*` with `--squash`, `--admin` and
`--delete-branch` (the number comes before the flags and no glob refuses a trailing flag),
and `git merge*` with it. The prose is what keeps those flags out. `git push origin HEAD:*`
matches nothing either; a push to `{{BASE_BRANCH}}` is stopped by the deny rules the
contract lists.
P
)
else
  v[MERGER_SENTENCE]="A **person** merges. The builder's watch says \`mergeable\` and stops there; no session runs \`gh pr merge\`."
  v[MERGEABLE_ACTION]="run the four checks below, then notify the person and stop — do not merge"
  v[MERGE_TOOL]=""
  v[MERGE_PARAGRAPHS]=$(cat <<'P'
Notify the person with the PR number and the sha the checks passed at, and stop. No merge
verb is on this command's allowlist — and that allowlist's comma-inside form pre-approves
nothing anyway. A push to `{{BASE_BRANCH}}` is stopped by the deny rules the contract
lists, not by `git push origin HEAD:*`, which matches nothing.
P
)
fi
if [ -n "${v[LABEL_CLAIMED]}" ]; then
  v[CLAIMED_ROW]="| \`${v[LABEL_CLAIMED]}\` | builder | A builder has taken this item and not yet opened its PR. Durable because builders run in parallel and one session's memory is invisible to another. |"
  v[CLAIMED_RULE]="Before starting an item, label it \`${v[LABEL_CLAIMED]}\`; an item already carrying it belongs to someone else. Remove it when the PR is labelled \`${v[LABEL_WAITING]}\`."
else
  v[CLAIMED_ROW]=""
  v[CLAIMED_RULE]="One builder session dispatches everything, so a claim is held in that session's memory; a restart re-derives the queue from labels. If builders ever run in parallel, add a durable claimed label first."
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
echo
echo "Next: add one pointer line to $repo/CLAUDE.md, e.g."
echo "  - Builder–reviewer loop: see \`${v[CONTRACT_PATH]}\` (roles, labels, merge predicate). Sessions named builder/reviewer run \`/builder-watch\` and \`/reviewer-watch\`."
