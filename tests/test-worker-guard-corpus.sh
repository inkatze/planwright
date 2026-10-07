#!/bin/bash
# The worker guard's real-prompt corpus, replayed
# (REQ-H1.3, REQ-A1.11): every row of tests/fixtures/worker-guard-corpus.tsv
# runs through scripts/worker-command-guard.sh under each policy value with a
# session record injected. A row of a shipped class must reach its expected
# verdict in every column; a pending class's stalls are reported only, and a
# false-allow fails in every class.
#
# The harness checks itself first against small synthetic corpora, because a
# replay that never fails reads exactly like a green one: a shipped miss must
# fail, a pending stall must not, a false-allow always must, and a malformed
# corpus must refuse to run.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/worker-command-guard.sh"
CORPUS="$REPO_ROOT/tests/fixtures/worker-guard-corpus.tsv"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

failures=0
passes=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

SANDBOX="$(mktemp -d)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}

run_guard() { /bin/bash "$HOOK"; }

# A stand-in guard for the self-checks: approves exactly `true`.
fake_guard() {
  case $(jq -r '.tool_input.command') in
    true) printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"t"}}' ;;
  esac
}

T=$CORPUS_TAB
synthetic() {
  # synthetic <name> <line>...: a corpus declaring the shipped, pending,
  # floor, and uncovered classes the self-checks use, plus the given lines.
  local f="$SANDBOX/$1.tsv"
  shift
  {
    printf 'class%slive%s1%sshipped%sshipped class\n' "$T" "$T" "$T" "$T"
    printf 'class%slater%s9%spending%spending class\n' "$T" "$T" "$T" "$T"
    printf 'class%sfloor%s5%sshipped%sfloor\n' "$T" "$T" "$T" "$T"
    printf 'class%suncovered%s5%sshipped%suncovered\n' "$T" "$T" "$T" "$T"
    printf '%s\n' "$@"
  } >"$f"
  printf '%s\n' "$f"
}
row() {
  # row <class> <v1> <v2> <v3> <v4> <command>
  printf 'row%s%s%s%s%s%s%s%s%s%s%s%s' "$T" "$1" "$T" "$2" "$T" "$3" "$T" "$4" "$T" "$5" "$T" "$6"
}

# --- the sandbox ---------------------------------------------------------
# The rows run against what a worker really has: a linked worktree on its
# unit branch, whose base resolves, and records the hook reads its inputs
# from rather than its own environment.
if [ -f "$CORPUS_WORKTREE/.git" ]; then
  pass "sandbox: the worktree is a linked worktree (.git is a file)"
else
  fail "sandbox: the worktree's .git is not a file"
fi
if [ "$(corpus_git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$CORPUS_UNIT_BRANCH" ] \
  && corpus_git rev-parse -q --verify origin/main >/dev/null 2>&1; then
  pass "sandbox: the unit branch is checked out and origin/main resolves"
else
  fail "sandbox: the unit branch or origin/main does not resolve"
fi
# Approves only when the hook's TMPDIR is a real directory other than the
# recorded scratch root.
tmpdir_probe() {
  cat >/dev/null
  if [ -d "$TMPDIR" ] && [ "$TMPDIR" != "$CORPUS_SCRATCH" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  fi
}
if grep -qx "scratch_root=$CORPUS_SCRATCH" "$CORPUS_BOX/state/record.3" \
  && [ "$(corpus_decide tmpdir_probe 3 true)" = allow ]; then
  pass "sandbox: the scratch root comes from the record, not the hook's TMPDIR"
else
  fail "sandbox: the hook's TMPDIR is the recorded scratch root"
fi
if corpus_git rev-parse -q --verify refs/heads/other >/dev/null 2>&1 \
  && corpus_git rev-parse -q --verify origin/other >/dev/null 2>&1 \
  && [ -d "$CORPUS_BOX/other/.git" ]; then
  pass "sandbox: the other branch, origin/other, and the sibling repository the rows name exist"
else
  fail "sandbox: a ref or repository the rows name is missing"
fi
mkdir -p "$SANDBOX/used-box"
: >"$SANDBOX/used-box/stray"
err=$( (corpus_sandbox "$SANDBOX/used-box" "$REPO_ROOT") 2>&1 >/dev/null)
rc=$?
case $rc:$err in
  1:*"not empty"*) pass "sandbox: a box already in use is refused" ;;
  *) fail "sandbox: a box in use was not refused as such (rc=$rc: $err)" ;;
esac

# --- self-checks ---------------------------------------------------------
f=$(synthetic ok "$(row live allow allow allow allow true)" "$(row live defer defer defer defer false)")
if corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FAILED" -eq 0 ] && [ "$CORPUS_ROWS" -eq 2 ]; then
  pass "self-check: a corpus the guard satisfies replays green"
else
  fail "self-check: a satisfied corpus did not replay green (rows=$CORPUS_ROWS failed=$CORPUS_FAILED)"
fi

f=$(synthetic shipped-miss "$(row live allow allow allow allow false)")
if ! corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FAILED" -eq 1 ]; then
  pass "self-check: a shipped row that misses its verdict fails"
else
  fail "self-check: a shipped miss did not fail (failed=$CORPUS_FAILED)"
fi

f=$(synthetic false-allow "$(row live defer defer defer defer true)")
if ! corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FALSE_ALLOWS" -eq 1 ]; then
  pass "self-check: an unexpected allow is counted as a false-allow"
else
  fail "self-check: false-allow not counted (false_allows=$CORPUS_FALSE_ALLOWS)"
fi

f=$(synthetic pending-stall "$(row later allow allow allow allow false)")
if corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FAILED" -eq 0 ] && [ "$CORPUS_PENDING" -eq 1 ]; then
  pass "self-check: a pending class's stalls are reported, not failed"
else
  fail "self-check: pending stall handling wrong (failed=$CORPUS_FAILED pending=$CORPUS_PENDING)"
fi

# A false-allow is never pending: the guard approving what a row expects it
# to defer fails whatever the class state.
f=$(synthetic pending-false-allow "$(row later defer defer defer defer true)")
if ! corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FAILED" -eq 1 ] && [ "$CORPUS_FALSE_ALLOWS" -eq 1 ]; then
  pass "self-check: a pending class's false-allow fails"
else
  fail "self-check: a pending false-allow did not fail (failed=$CORPUS_FAILED false_allows=$CORPUS_FALSE_ALLOWS)"
fi

f=$(synthetic one-column "$(row live defer allow allow allow true)")
if ! corpus_replay "$f" fake_guard >/dev/null 2>&1 && [ "$CORPUS_FAILED" -eq 1 ]; then
  pass "self-check: a miss in a single policy column fails the row"
else
  fail "self-check: a miss in one column went unnoticed (failed=$CORPUS_FAILED)"
fi

# A hook call that dies yields no verdict, which must refuse the replay
# rather than read as a defer and pass every defer-expected row.
dying_guard() {
  cat >/dev/null
  kill -9 "$(sh -c 'echo $PPID')"
}
f=$(synthetic dying "$(row live defer defer defer defer false)")
corpus_replay "$f" dying_guard >/dev/null 2>&1
if [ $? -eq 2 ]; then
  pass "self-check: a hook call that dies refuses the replay"
else
  fail "self-check: a dying hook call did not refuse the replay"
fi

# Each column is compared against its own verdict: a stand-in that approves
# only under the policy carrying both arms must miss in column 4 alone.
both_arms_guard() {
  cat >/dev/null
  if grep -qx 'policy=own-branch scratch' "$PLANWRIGHT_WORKER_SESSION_RECORD"; then
    printf '%s\n' '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  fi
}
f=$(synthetic last-column "$(row live defer defer defer defer true)")
if ! corpus_replay "$f" both_arms_guard >/dev/null 2>&1 && [ "$CORPUS_FALSE_ALLOWS" -eq 1 ]; then
  pass "self-check: a false-allow in the last policy column alone fails"
else
  fail "self-check: a false-allow in the last column went unnoticed"
fi
f=$(synthetic last-column-held "$(row live defer defer defer allow true)")
if corpus_replay "$f" both_arms_guard >/dev/null 2>&1; then
  pass "self-check: each column reads its own session record"
else
  fail "self-check: a column did not read its own session record"
fi

f=$(synthetic bad-column "$(row live allow allow allow allow true)")
for cols in "1 5" " " "1 1"; do
  corpus_replay "$f" fake_guard "$cols" >/dev/null 2>&1
  if [ $? -eq 2 ]; then
    pass "self-check: the column list '$cols' refuses the replay"
  else
    fail "self-check: the column list '$cols' was replayed"
  fi
done

# The replay waits for its own hook calls only, never the caller's jobs.
f=$(synthetic bg-wait "$(row live allow allow allow allow true)")
sleep 30 &
bg=$!
start=$SECONDS
corpus_replay "$f" fake_guard 1 >/dev/null 2>&1
rc=$?
took=$((SECONDS - start))
kill "$bg" 2>/dev/null
wait "$bg" 2>/dev/null
if [ "$rc" -eq 0 ] && [ "$CORPUS_ROWS" -eq 1 ] && [ "$took" -lt 15 ]; then
  pass "self-check: the replay does not wait on the caller's background jobs"
else
  fail "self-check: the background-job replay took ${took}s (rc=$rc, rows=$CORPUS_ROWS)"
fi

# The guard refuses to approve an assignment to a name exported in its own
# environment, so a verdict must not depend on what the caller exports.
f=$(synthetic host-env "$(row live allow allow allow allow 'read name')")
if (
  export name=host
  corpus_replay "$f" run_guard 1 >/dev/null 2>&1
); then
  pass "self-check: a variable the caller exports does not change a verdict"
else
  fail "self-check: a caller-exported variable changed the guard's verdict"
fi

# A placeholder binds to the path verbatim: bash 5.2 expands `&` in a
# pattern-substitution replacement to the matched text.
bound=$(CORPUS_PLUGIN_ROOT='/opt/a&b\c' corpus_bind 'R=@@PLUGIN_ROOT@@; ls @@PLUGIN_ROOT@@')
if [ "$bound" = 'R=/opt/a&b\c; ls /opt/a&b\c' ]; then
  pass "self-check: a placeholder binds a path carrying & and \\ verbatim"
else
  fail "self-check: placeholder binding mangled the path: $bound"
fi

# Nor may an exported function, a readonly export such as SHELLOPTS, or an
# exported caller variable the harness itself reads reach the hook: a
# stand-in approves only when its environment carries none of them and the
# harness's own variables still resolve.
env_probe() {
  cat >/dev/null
  if ! env | grep -qE '^(BASH_FUNC_|SHELLOPTS=|probe_var=|CORPUS_BOX=)' && [ -n "$CORPUS_BOX" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  fi
}
verdict=$(
  # shellcheck disable=SC2329  # exported, never called
  probe_fn() { :; }
  export -f probe_fn
  export SHELLOPTS probe_var=1 CORPUS_BOX
  corpus_decide env_probe 1 true
)
if [ "$verdict" = allow ]; then
  pass "self-check: exported functions and readonly exports do not reach the hook"
else
  fail "self-check: the hook saw the caller's exports (verdict: $verdict)"
fi

# Each malformed corpus must refuse (exit 2) before replaying anything, and
# for its own reason, so one malformation cannot stand in for another.
refuses() {
  local label=$1 reason=$2 f err rc
  shift 2
  f=$(synthetic "refuse-$label" "$@")
  err=$(corpus_replay "$f" fake_guard 2>&1 >/dev/null)
  rc=$?
  case $rc:$err in
    2:*"$reason"*) pass "self-check: refuses $label" ;;
    *) fail "self-check: $label: expected exit 2 naming '$reason', got $rc: $err" ;;
  esac
}
refuses "an undeclared class" "undeclared class" "$(row nosuch allow allow allow allow true)"
refuses "a verdict other than allow or defer" "a verdict is allow or defer" \
  "$(row live allow maybe allow allow true)"
refuses "a row with a missing column" "seven tab-separated fields" \
  "row${T}live${T}allow${T}allow${T}allow${T}true"
refuses "an untabbed row" "unknown record kind" "row live allow allow allow allow true"
refuses "a floor row that allows under some value" "defers under every policy value" \
  "$(row floor defer defer allow allow true)"
refuses "an uncovered row that allows under some value" "defers under every policy value" \
  "$(row uncovered defer allow defer allow true)"
refuses "a row with an empty command" "a row carries a command" \
  "row${T}live${T}allow${T}allow${T}allow${T}allow${T}"
refuses "a malformed class name" "malformed class name" "class${T}Bad_Name${T}1${T}shipped${T}x"
refuses "a class with no task number" "names the task" "class${T}notask${T}x${T}shipped${T}x"
refuses "an arm that narrows the empty policy" "allowed under the empty policy" \
  "$(row live allow defer allow allow true)"
refuses "both arms narrowing one arm" "allowed under one arm" \
  "$(row live defer allow defer defer true)"
refuses "an unknown record kind" "unknown record kind: rows" \
  "rows${T}live${T}allow${T}allow${T}allow${T}allow${T}true"
refuses "a class state other than shipped or pending" "shipped or pending" \
  "class${T}odd${T}1${T}landed${T}x"
refuses "a class declared twice" "declared twice" "class${T}live${T}1${T}shipped${T}again"
refuses "a corpus with no rows" "no rows"
refuses "an unknown placeholder" "unknown placeholder" \
  "$(row live defer defer defer defer 'touch @@OUTSDE@@/x')"
refuses "a lowercase placeholder" "unknown placeholder" \
  "$(row live defer defer defer defer 'touch @@Outside@@/x')"
refuses "a malformed placeholder" "unknown placeholder" \
  "$(row live defer defer defer defer 'touch @@OUTSIDE@/x')"

# The legacy PreToolUse spelling `decision: approve` still approves, so it
# reads as an allow.
legacy_guard() {
  cat >/dev/null
  printf '%s\n' '{"decision":"approve","reason":"t"}'
}
f=$(synthetic legacy "$(row live defer defer defer defer true)")
if ! corpus_replay "$f" legacy_guard 1 >/dev/null 2>&1 && [ "$CORPUS_FALSE_ALLOWS" -eq 1 ]; then
  pass "self-check: the legacy decision: approve spelling reads as an allow"
else
  fail "self-check: decision: approve was read as a defer"
fi

# --- the corpus file -----------------------------------------------------
# Sanitization: the whole file (comments and class records too) carries
# command shapes only. leaks_in prints each line naming a machine or home
# path, an email or scp-style host, an IPv4 address, a host other than the
# reserved example.invalid, a repository slug other than o/r, or a token
# shape; it exits non-zero if it cannot scan. Single-pattern rules run in
# grep (not every awk supports intervals), in text mode so a NUL byte cannot
# turn the file binary; rules that judge each match run in awk.
leaks_in() {
  local by_grep by_awk rc
  by_grep=$(grep -anE '/(home|Users|root|private|var|opt|mnt|srv|Volumes|media|nix|run/user|workspace|data|usr/local)/|(^|[[:space:]=:"'\''(])~[A-Za-z0-9_/]|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]|[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:|[A-Za-z0-9-]+\.(com|org|net|io|dev|ai|co|internal|corp)([^A-Za-z0-9-]|$)|(^|[^0-9.])[0-9]{1,3}(\.[0-9]{1,3}){3}([^0-9.]|$)|(^|[^A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})' "$1")
  rc=$?
  [ "$rc" -le 1 ] || return 2
  by_awk=$(awk '
    {
      bad = 0
      t = $0
      while (match(t, /:\/\/[^\/ \t"'\'']*/)) {
        if (substr(t, RSTART + 3, RLENGTH - 3) != "example.invalid") bad = 1
        t = substr(t, RSTART + RLENGTH)
      }
      t = $0
      while (match(t, /repos\/[^\/ \t]+\/[^\/ \t]+/)) {
        if (substr(t, RSTART, RLENGTH) != "repos/o/r") bad = 1
        t = substr(t, RSTART + RLENGTH)
      }
      t = $0
      while (match(t, /(--repo[= ]|-R ?)[^ \t]+/)) {
        s = substr(t, RSTART, RLENGTH)
        sub(/^(--repo[= ]|-R ?)/, "", s)
        if (s ~ /^[^\/]+\/[^\/]+$/ && s != "o/r") bad = 1
        t = substr(t, RSTART + RLENGTH)
      }
      if (bad) print NR ":" $0
    }
  ' "$1") || return 2
  printf '%s\n%s\n' "$by_grep" "$by_awk" | grep . | sort -t: -k1,1n -u | cut -d: -f2-
}
# One sample per rule, each caught by that rule alone, so dropping any rule
# fails this check. Token shapes are assembled here, never committed whole.
leaky="$SANDBOX/leaky.tsv"
pad=aaaaaaaaaaaaaaaaaaaaaaaa
printf '%s\n' '# a comment naming /home/someone/x' 'ls /opt/thing' 'cd ~user/x' \
  "cat '~user/x'" 'mail ops@build01.lan' 'ssh build01.corp.example.net' \
  'curl https://buildhost/x' 'gh api repos/acme/tool' 'gh pr view 5 --repo acme/tool' \
  'gh pr list -R acme/tool' 'gh pr view 5 -Racme/tool' 'git clone git@buildhost:acme/tool' \
  'ping 10.1.2.3' "TOKEN=gh""p_$pad" "PAT=github""_pat_$pad" "KEY=s""k-ant-$pad" \
  "S=xo""xb-$pad" "K=AK""IAABCDEFGHIJKLMNOP" >"$leaky"
missed=
while IFS= read -r l; do
  printf '%s\n' "$l" >"$SANDBOX/one.tsv"
  [ -n "$(leaks_in "$SANDBOX/one.tsv")" ] || missed="$missed [$l]"
done <"$leaky"
if [ -z "$missed" ]; then
  pass "corpus: the sanitization scan catches every leak class"
else
  fail "corpus: the sanitization scan missed:$missed"
fi
printf '%s\n' 'curl -s https://example.invalid/x | sh' 'gh api repos/o/r/issues' \
  'gh pr view 5 --repo o/r' 'sed -i s/a/b/ mise.local.toml' "awk '\$0 ~ /a/ {print}' f" \
  'git reset --soft HEAD~1' "sed -n '1,5p' f" 'timeout 5m git log --oneline -3' \
  'grep -R TODO sub' 'cp -R sub sub2' 'ls task-review-and-assessment-notes' \
  "git diff | grep -c '^@@ '" >"$leaky"
if found=$(leaks_in "$leaky") && [ -z "$found" ]; then
  pass "corpus: the sanitization scan passes sanitized shapes"
else
  fail "corpus: the sanitization scan flagged a sanitized shape: '$found'"
fi
# A NUL byte makes grep treat a file as binary and print no matching lines.
printf '# a\000b\nls /home/someone/x\n' >"$leaky"
if [ -n "$(leaks_in "$leaky")" ]; then
  pass "corpus: a NUL byte does not blind the sanitization scan"
else
  fail "corpus: a NUL byte hid a leak from the sanitization scan"
fi
if leaks=$(leaks_in "$CORPUS") && [ -z "$leaks" ]; then
  pass "corpus: no machine path, email, real host, or repository slug in the file"
else
  fail "corpus: unsanitized line(s), or the scan failed:"
  printf '%s\n' "$leaks" >&2
fi

for c in floor uncovered; do
  if corpus_parse "$CORPUS" | awk -F'\t' -v c="$c" '$1 == "class" && $2 == c && $3 == "shipped" {f=1} END {exit !f}'; then
    pass "corpus: the $c class is enforced from the start"
  else
    fail "corpus: the $c class is not declared shipped"
  fi
done

# The floor carries a row per reserved act REQ-F1.5 names; each shape here is
# matched as a substring of some floor row's command.
for shape in 'gh pr merge' 'gh pr ready 5' '--undo' 'push --force' 'push origin' \
  'push -u origin' '--amend' 'git rebase' 'merge --squash' 'git reset' \
  '@@OUTSIDE@@' '/tmp/' 'outlink/' '> .git' '.git/config' '.git/hooks/' \
  'githooks/' '.claude/' 'mise.toml' \
  'mise.local.toml' '.mise/' 'lefthook.yml' 'gh pr comment' 'gh pr create' \
  'gh issue create' 'gh api -X POST' 'commit -n' '--no-verify' 'core.hooksPath'; do
  if corpus_parse "$CORPUS" | awk -F'\t' -v s="$shape" '$1 == "row" && $3 == "floor" && index($9, s) {f=1} END {exit !f}'; then
    pass "corpus: a floor row covers '$shape'"
  else
    fail "corpus: no floor row covers '$shape'"
  fi
done

# Every `prefix:*` rule of the worker profile's deny block has a floor row it
# matches, so the deny outcome is asserted against the actual block
# (REQ-A1.11) rather than assumed from Claude Code's evaluation order. The
# glob rules are only sampled by curated floor rows: nothing here generates a
# matching command per glob rule, and the permission-matcher suite models
# Claude Code's matcher without running the guard.
floor_cmds=$(corpus_parse "$CORPUS" | awk -F'\t' '$1 == "row" && $3 == "floor" {print $9}')
prefixes=$(jq -r '.permissions.deny[] | select(test("^Bash\\(.*:\\*\\)$")) | sub("^Bash\\(";"") | sub(":\\*\\)$";"")' \
  "$REPO_ROOT/config/worker-settings.json")
[ -n "$prefixes" ] || fail "corpus: no prefix rule read from the deny block"
while IFS= read -r prefix; do
  [ -n "$prefix" ] || continue
  hit=0
  while IFS= read -r c; do
    case $c in "$prefix" | "$prefix "*) hit=1 ;; esac
  done <<EOF
$floor_cmds
EOF
  if [ "$hit" -eq 1 ]; then
    pass "corpus: a floor row matches deny rule '$prefix:*'"
  else
    fail "corpus: no floor row matches deny rule '$prefix:*'"
  fi
done <<EOF
$prefixes
EOF

# --- the replay ----------------------------------------------------------
corpus_replay "$CORPUS" run_guard
rc=$?
if [ "$rc" -eq 2 ]; then
  fail "corpus: refused to replay (malformed corpus, unusable sandbox, or a failed hook call)"
elif [ "$CORPUS_ROWS" -lt "$CORPUS_MIN_ROWS" ]; then
  fail "corpus: replayed $CORPUS_ROWS rows, below the minimum of $CORPUS_MIN_ROWS"
elif [ "$rc" -eq 0 ]; then
  pass "corpus: $CORPUS_ROWS rows replayed, none failed ($CORPUS_PENDING pending stall(s) reported)"
else
  fail "corpus: $CORPUS_FAILED row(s) failed, $CORPUS_FALSE_ALLOWS of them false-allows"
fi

echo
echo "worker-guard-corpus: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
