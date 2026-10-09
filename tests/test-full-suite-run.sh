#!/bin/sh
# Tests for scripts/full-suite-run.sh — /execute-task's full local suite run,
# pooled through scripts/step-pool.sh when full_suite_pool names a pool
# (custom-steps REQ-I1.5, D-25).
#
# Every pool lives under a temporary pools root and every config layer is a
# fixture except core, the shipped config/defaults.yml, so the unset default is
# the one under test. The "suite" is a fixture script that records its hold
# mark and appends start and end timestamps.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-full-suite-run.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# The pool helper refuses a group- or other-writable pool.
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
FSR="$repo_root/scripts/full-suite-run.sh"
SP="$repo_root/scripts/step-pool.sh"
DEFAULTS="$repo_root/config/defaults.yml"
TAB=$(printf '\t')

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }
# verdict <ok-message> <fail-message> [<file>] — judged on the status of the
# command before the call; a failure appends <file>'s content. A message must
# not run a command substitution: under bash that resets $? before the
# function reads it.
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2${3:+: $(cat "$3" 2>/dev/null)}"
  fi
}

[ -x "$FSR" ] || {
  echo "FAIL: scripts/full-suite-run.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-full-suite-run.XXXXXX")" && pwd -P)" || exit 1
owners="$tmp/owners"
cleanup() {
  [ -f "$owners" ] && while read -r _p; do kill "$_p" 2>/dev/null; done <"$owners"
  rm -rf "$tmp"
}
trap cleanup EXIT

pools="$tmp/pools"
adopter="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter" "$repo/.claude"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
tracked="$repo/.claude/planwright.yml"
mlocal="$repo/.claude/planwright.local.yml"

# The fixture suite: records the hold mark it saw, marks itself running for
# <seconds> (recording an overlap when another suite already is), and exits
# <code>.
suite="$tmp/suite.sh"
cat >"$suite" <<'EOF'
#!/bin/sh
log=$1 secs=$2 code=$3
running=$(dirname "$log")/running
printf 'mark=%s\n' "${PLANWRIGHT_STEP_POOL_HOLD-<unset>}" >>"$log.mark"
mkdir "$running" 2>/dev/null || printf 'overlap\n' >>"$running.overlap"
printf 'started\n' >>"$log"
sleep "$secs"
rmdir "$running" 2>/dev/null
exit "$code"
EOF
chmod +x "$suite"

# fsr [<env assignment>...] -- <args>... — run the script against the fixture
# layers from the fixture checkout, with no inherited hold mark.
fsr() {
  (
    cd "$repo" || exit 99
    unset PLANWRIGHT_STEP_POOL_HOLD PLANWRIGHT_CONFIG_STRICT_OVERLAYS PLANWRIGHT_ROOT PLANWRIGHT_REPO_ROOT_CHECKED
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
      export "${1?}"
      shift
    done
    [ "${1:-}" = -- ] && shift
    PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      PLANWRIGHT_POOL_DIR="$pools" \
      "$FSR" "$@"
  )
}
sp() {
  (
    cd "$repo" || exit 99
    unset PLANWRIGHT_STEP_POOL_HOLD
    PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_POOL_DIR="$pools" \
      "$SP" "$@"
  )
}
owner() {
  sleep 120 >/dev/null 2>&1 &
  _o=$!
  printf '%s\n' "$_o" >>"$owners"
  printf '%s' "$_o"
}
reset() {
  rm -rf "$pools" "$tmp"/log* "$tmp/running" "$tmp/running.overlap"
  rm -f "$tracked" "$mlocal" "$adopter/planwright.yml"
}

# --- unset: today's behavior, unpooled -----------------------------------------
reset
fsr -- -- "$suite" "$tmp/log" 0 7 >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 7 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" && [ ! -e "$pools" ] && [ ! -s "$tmp/err" ]
verdict "with full_suite_pool unset the suite runs unpooled, silently, its exit kept" \
  "unset: rc=$rc" "$tmp/err"

# --- set: the run holds a slot for its own pid and passes the hold mark ----------
reset
printf 'full_suite_pool: gate\n' >"$tracked"
(fsr -- -- "$suite" "$tmp/log" 2 0 >"$tmp/out" 2>"$tmp/err") &
bg=$!
_n=0
while [ ! -s "$tmp/log" ] && [ "$_n" -lt 50 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
held=$(sp report gate)
wait "$bg"
rc=$?
pid=$(sed -n 's/^mark=gate://p' "$tmp/log.mark")
[ "$rc" -eq 0 ] && [ -n "$pid" ] \
  && printf '%s\n' "$held" | grep -q "^holder${TAB}1${TAB}$pid${TAB}(full-suite)${TAB}"
verdict "a pooled run holds a full-suite slot and hands the suite its hold mark" \
  "pooled: rc=$rc held='$held'" "$tmp/log.mark"
held=$(sp report gate)
[ -z "$held" ]
verdict "the slot is released after the suite ends" "still held: $held"

# --- a failing suite still releases, its exit kept ------------------------------
reset
printf 'full_suite_pool: gate\n' >"$tracked"
fsr -- -- "$suite" "$tmp/log" 0 3 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 3 ] && [ -z "$(sp report gate)" ]
verdict "a failing pooled suite keeps its exit and releases the slot" "failing: rc=$rc" "$tmp/err"

# --- two runs sharing the pool never overlap -------------------------------------
reset
printf 'full_suite_pool: gate\nstep_pool_capacity_gate: 1\n' >"$tracked"
(fsr -- -- "$suite" "$tmp/logA" 1 0 >/dev/null 2>&1) &
a=$!
(fsr -- -- "$suite" "$tmp/logB" 1 0 >/dev/null 2>&1) &
b=$!
wait "$a"
ra=$?
wait "$b"
rb=$?
[ "$ra" -eq 0 ] && [ "$rb" -eq 0 ] && [ -s "$tmp/logA" ] && [ -s "$tmp/logB" ] \
  && [ ! -e "$tmp/running.overlap" ]
verdict "two full suites sharing a one-slot pool run one at a time" \
  "overlap or failed run: ra=$ra rb=$rb" "$tmp/running.overlap"

# --- an expired wait runs no suite and names the holders --------------------------
reset
printf 'full_suite_pool: gate\nstep_pool_wait: 1s\n' >"$tracked"
h=$(owner)
sp take gate "$h" --step other-unit --worktree "$tmp/elsewhere" >/dev/null
fsr -- -- "$suite" "$tmp/log" 0 0 >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 75 ] && [ ! -e "$tmp/log" ] \
  && grep -q '^full-suite-run: wait expired' "$tmp/err" \
  && grep -qF "holder${TAB}1${TAB}$h${TAB}other-unit${TAB}$tmp/elsewhere" "$tmp/out"
verdict "an expired wait exits 75, runs no suite, and names the holders" \
  "expired: rc=$rc" "$tmp/err"

# --- nested inside the same pool's live hold: no wait, the mark passed on ------------
reset
printf 'full_suite_pool: gate\nstep_pool_wait: 1s\n' >"$tracked"
h=$(owner)
sp take gate "$h" >/dev/null
fsr "PLANWRIGHT_STEP_POOL_HOLD=gate:$h" -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx "mark=gate:$h" "$tmp/log.mark"
verdict "a run inside the pool's own hold takes nothing and passes the mark on" \
  "nested: rc=$rc" "$tmp/err"
sp release gate "$h" >/dev/null

# --- a malformed pool name warns and runs unpooled -----------------------------------
reset
printf 'full_suite_pool: Bad_Pool\n' >"$tracked"
fsr -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" \
  && grep -q 'full_suite_pool' "$tmp/err" && [ ! -e "$pools" ]
verdict "a malformed full_suite_pool warns once and the suite runs unpooled" \
  "malformed: rc=$rc" "$tmp/err"

# --- usage ---------------------------------------------------------------------------
reset
fsr -- >/dev/null 2>&1
rc1=$?
fsr -- "$suite" >/dev/null 2>&1
rc2=$?
fsr -- -- >/dev/null 2>&1
rc3=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 2 ] && [ ! -e "$tmp/log" ]
verdict "a missing -- or command is a usage error that runs nothing" "usage: $rc1 $rc2 $rc3"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all full-suite-run tests passed"
