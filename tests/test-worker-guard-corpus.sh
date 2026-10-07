#!/bin/bash
# The worker guard's real-prompt corpus, replayed
# (REQ-H1.3, REQ-A1.11): every row of tests/fixtures/worker-guard-corpus.tsv
# runs through scripts/worker-command-guard.sh under each policy value with a
# session record injected. A row of a shipped class must reach its expected
# verdict in every column; a pending class is replayed and reported only.
#
# The harness checks itself first against small synthetic corpora, because a
# replay that never fails reads exactly like a green one: a shipped miss must
# fail, a pending miss must not, and a malformed corpus must refuse to run.
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

T=$(printf '\t')
synthetic() {
  # synthetic <name> <line>...: a corpus declaring the two classes the
  # self-checks use, plus the given lines.
  local f="$SANDBOX/$1.tsv"
  shift
  {
    printf 'class%slive%s1%sshipped%sshipped class\n' "$T" "$T" "$T" "$T"
    printf 'class%slater%s9%spending%spending class\n' "$T" "$T" "$T" "$T"
    printf 'class%sfloor%s5%sshipped%sfloor\n' "$T" "$T" "$T" "$T"
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
if ! corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" 2>/dev/null; then
  pass "sandbox: a box already in use is refused"
else
  fail "sandbox: a box already in use was rebuilt over"
fi

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

f=$(synthetic bad-column "$(row live allow allow allow allow true)")
corpus_replay "$f" fake_guard "1 5" >/dev/null 2>&1
if [ $? -eq 2 ]; then
  pass "self-check: an unknown policy column refuses the replay"
else
  fail "self-check: an unknown policy column was skipped"
fi

# The replay waits for its own hook calls only, never the caller's jobs.
sleep 30 &
bg=$!
start=$SECONDS
corpus_replay "$f" fake_guard 1 >/dev/null 2>&1
took=$((SECONDS - start))
kill "$bg" 2>/dev/null
wait "$bg" 2>/dev/null
if [ "$took" -lt 15 ]; then
  pass "self-check: the replay does not wait on the caller's background jobs"
else
  fail "self-check: the replay waited ${took}s on a caller's background job"
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
# Sanitization: rows carry command shapes only. Absolute paths are limited to
# the system locations a shape needs, and a URL may only name the reserved
# example.invalid host.
leaks=$(grep '^row' "$CORPUS" | grep -E '(/home/|/Users/|/root/|/private/|/var/folders/|~/|@[A-Za-z0-9-]+\.[A-Za-z]|://[^/]*\.(com|org|net|io|dev))' || true)
if [ -z "$leaks" ]; then
  pass "corpus: no user path, home path, email, or real host in any row"
else
  fail "corpus: unsanitized row(s):"
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
  '@@OUTSIDE@@' '/tmp/' '.git' 'githooks/' '.claude/' 'mise.toml' \
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
# glob rules are the permission-matcher suite's to cover.
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
  fail "corpus: refused to replay (malformed corpus or sandbox)"
elif [ "$CORPUS_ROWS" -lt "$CORPUS_MIN_ROWS" ]; then
  fail "corpus: replayed $CORPUS_ROWS rows, below the floor of $CORPUS_MIN_ROWS"
elif [ "$rc" -eq 0 ]; then
  pass "corpus: $CORPUS_ROWS rows replayed, every shipped verdict held ($CORPUS_PENDING pending miss(es) reported)"
else
  fail "corpus: $CORPUS_FAILED shipped verdict(s) missed, $CORPUS_FALSE_ALLOWS of them false-allows"
fi

echo
echo "worker-guard-corpus: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
