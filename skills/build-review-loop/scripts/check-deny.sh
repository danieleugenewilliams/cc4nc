#!/usr/bin/env bash
# check-deny.sh — prove the base-branch deny rules refuse the push spellings they claim to.
#
# Usage (from the repo root):
#   bash <skill-dir>/scripts/check-deny.sh [settings-file] [base-branch]
#     settings-file  defaults to .claude/settings.json — the REAL file, read with jq, not a copy
#     base-branch    defaults to main
#   CHECK_DENY_MODEL=<model>   model for the probe sessions (default: haiku)
#   CHECK_DENY_ONLY="1 6"      run only these row numbers. A partial run is a smoke test,
#                              never a verification: it always exits 2 and says so.
#
# How it works. Each row is one spelling of `git push`, handed to a FRESH
# `claude -p --permission-mode default` session that is asked to run it verbatim. The session
# loads the deny rules from your settings file plus a deliberately wide allow
# (`Bash(git push *)`, `Bash(git -C *)`): without the allow, a deny and a plain no-match look
# identical, because `-p` refuses anything unapproved. With it, the only thing that can refuse
# a push is a deny rule. `git` on the probe's PATH is an echo-only fake that writes its argv to
# a log and contacts nothing; the probe runs in an empty temp directory that is not a repo.
#
# Verdicts, per row:
#   deny    PASS only if the session's permission_denials holds a Bash call whose command is
#           the row EXACTLY, and the fake git never saw it. Ran = FAIL (the rule leaks).
#           Neither = FAIL: the session did not run the row verbatim, so it proves nothing.
#   allow   the control. PASS only if the fake git saw it and nothing denied it. If the
#           control fails, the allow did not load or the fake git is not on PATH, and every
#           deny PASS in the same run is meaningless — the run fails.
#   escape  a spelling the four rules are known NOT to catch, recorded rather than chased.
#           Reported, not scored: ESCAPES is the expected answer. Not run verbatim is still FAIL.
#
# Every claude -p reads stdin from /dev/null: an earlier version of this probe let the first
# session eat the rest of the matrix off stdin, ran one row, and printed "all denied". The
# rows live in an array, and the run refuses unless it reports on every one.
#
# Cost: one fresh session per row (10 rows). User settings, plugins and MCP are not loaded.

set -uo pipefail

settings="${1:-.claude/settings.json}"
base="${2:-main}"
model="${CHECK_DENY_MODEL:-haiku}"

die() { echo "check-deny: REFUSED — $*" >&2; exit 3; }

command -v claude >/dev/null || die "claude not on PATH"
command -v jq >/dev/null     || die "jq not on PATH"
[ -f "$settings" ]           || die "no settings file at $settings"
deny=$(jq -ce '.permissions.deny // empty | arrays' "$settings") \
  || die "$settings has no permissions.deny array"

# The four rules: `main` bare or right of a colon, each with or without a trailing flag.
required=(
  "Bash(git push * $base)"
  "Bash(git push * $base *)"
  "Bash(git push *:$base)"
  "Bash(git push *:$base *)"
)
for r in "${required[@]}"; do
  jq -e --arg r "$r" 'index($r) != null' <<<"$deny" >/dev/null \
    || die "$settings is missing deny rule: $r"
done

# expect|command — keep in an array; never feed the matrix through a `while read`.
rows=(
  "deny|git push origin $base"
  "deny|git push origin $base --no-verify"
  "deny|git push origin HEAD:$base"
  "deny|git push origin HEAD:$base --no-verify"
  "deny|git push --force-with-lease origin HEAD:$base"
  "allow|git push origin HEAD:check-deny-probe"
  "deny|git push -u origin $base"
  "escape|git -C . push origin $base"
  "escape|git push origin refs/heads/$base"
  "escape|git push origin HEAD:refs/heads/$base"
)
EXPECTED_ROWS=10
[ "${#rows[@]}" -eq "$EXPECTED_ROWS" ] || die "matrix has ${#rows[@]} rows, expected $EXPECTED_ROWS"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-deny.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/cwd"
log="$work/git.log"
cat > "$work/bin/git" <<EOF
#!/bin/sh
# echo-only fake: records argv, contacts nothing
printf '%s\n' "\$*" >> "$log"
echo "fake git: \$*"
exit 0
EOF
chmod +x "$work/bin/git"

probe_settings=$(jq -cn --argjson deny "$deny" \
  '{permissions: {allow: ["Bash(git push *)", "Bash(git -C *)"], deny: $deny}}')

only=" ${CHECK_DENY_ONLY:-} "
reported=0; fails=0; skipped=0; changed=0
printf '%-4s %-7s %-10s %s\n' row expect result command
for i in "${!rows[@]}"; do
  n=$((i+1))
  expect="${rows[$i]%%|*}"
  cmd="${rows[$i]#*|}"
  if [ -n "${CHECK_DENY_ONLY:-}" ] && [[ "$only" != *" $n "* ]]; then
    skipped=$((skipped+1)); continue
  fi
  : > "$log"
  prompt="Use the Bash tool to run exactly the command below, verbatim, as one single tool call. Do not quote, prefix, rephrase, chain or retry it. If it is refused, stop and say so.

$cmd"
  out=$(cd "$work/cwd" && PATH="$work/bin:$PATH" GIT_DIR="$work/no-such-repo" \
        claude -p "$prompt" \
          --permission-mode default \
          --setting-sources project \
          --settings "$probe_settings" \
          --strict-mcp-config \
          --tools Bash \
          --model "$model" \
          --output-format json \
          < /dev/null 2>"$work/stderr")
  rc=$?
  result=""
  if [ "$rc" -ne 0 ] || ! jq -e . >/dev/null 2>&1 <<<"$out"; then
    result="FAIL"; why="claude exited $rc or returned no JSON: $(head -c 200 "$work/stderr")"
  else
    denied=$(jq -r --arg c "$cmd" \
      '[.permission_denials[]? | select(.tool_name=="Bash") | .tool_input.command] | index($c) != null' <<<"$out")
    ran=false; grep -Fxq -- "${cmd#git }" "$log" && ran=true
    case "$expect:$denied:$ran" in
      deny:true:false)    result="PASS";    why="denied by rule" ;;
      deny:*:true)        result="FAIL";    why="ran — the deny rules do not catch this" ;;
      deny:*)             result="FAIL";    why="not run verbatim; proves nothing" ;;
      allow:false:true)   result="PASS";    why="control ran — the wide allow loaded, fake git on PATH" ;;
      allow:*)            result="FAIL";    why="control did not run; every deny PASS in this run is void" ;;
      escape:false:true)  result="ESCAPES"; why="as recorded: prompts in default mode, classifier in auto" ;;
      escape:true:false)  result="DENIED";  why="no longer escapes — update the recorded list" ;;
      escape:*)           result="FAIL";    why="not run verbatim; proves nothing" ;;
    esac
  fi
  [ "$result" = FAIL ] && fails=$((fails+1))
  [ "$result" = DENIED ] && changed=$((changed+1))
  reported=$((reported+1))
  printf '%-4s %-7s %-10s %s  (%s)\n' "$n" "$expect" "$result" "$cmd" "$why"
done

if [ $((reported + skipped)) -ne "$EXPECTED_ROWS" ]; then
  echo "check-deny: REFUSED — reported $reported + skipped $skipped of $EXPECTED_ROWS rows" >&2; exit 3
fi
if [ "$skipped" -gt 0 ]; then
  echo "check-deny: PARTIAL — $reported of $EXPECTED_ROWS rows run, $fails failed. This is not a verification."
  exit 2
fi
if [ "$fails" -gt 0 ]; then
  echo "check-deny: FAILED — $fails of $EXPECTED_ROWS rows. Do not claim pushes to $base are denied."
  exit 1
fi
echo "check-deny: OK — all $EXPECTED_ROWS rows reported; every tested spelling of a push to $base was denied and the control ran."
if [ "$changed" -gt 0 ]; then
  echo "check-deny: note — $changed recorded escape(s) are now denied; update the escape list."
else
  echo "check-deny: the three recorded escapes still escape, as recorded."
fi
