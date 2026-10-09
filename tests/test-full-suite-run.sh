#!/bin/sh
# Tests for scripts/full-suite-run.sh — /execute-task's full local suite run,
# pooled through scripts/step-pool.sh when full_suite_pool names a pool
# (custom-steps REQ-I1.5, D-25).
#
# Every pool lives under a temporary pools root and every config layer is a
# fixture; core is the shipped config/defaults.yml unless a case swaps it. The
# "suite" is a fixture script that records its hold mark and pid, flags an
# overlap with another running suite, and either sleeps or holds until the
# test lets it go.
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

defaults=$DEFAULTS

# The fixture suite: <log> <seconds|hold> <code>. It records the hold mark it
# saw and its pid (also into the owners file cleanup kills), flags an overlap
# when another suite is already running, then sleeps <seconds> or, for `hold`,
# waits until <log>.go exists (bounded), and exits <code>.
suite="$tmp/suite.sh"
cat >"$suite" <<'SUITE'
#!/bin/sh
log=$1 mode=$2 code=$3
dir=$(dirname "$log")
running=$dir/running
printf 'mark=%s\n' "${PLANWRIGHT_STEP_POOL_HOLD-<unset>}" >>"$log.mark"
printf 'lc=%s\n' "${LC_ALL-<unset>}" >>"$log.lc"
printf '%s\n' "$$" >>"$dir/owners"
mkdir "$running" 2>/dev/null || printf 'overlap\n' >>"$running.overlap"
printf '%s\n' "$$" >"$log.pid"
if [ "$mode" = hold ]; then
  n=0
  while [ ! -e "$log.go" ] && [ "$n" -lt 600 ]; do
    sleep 0.1
    n=$((n + 1))
  done
else
  sleep "$mode"
fi
rmdir "$running" 2>/dev/null
exit "$code"
SUITE
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
    PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
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
# await <file> — wait (bounded) until <file> is non-empty.
await() {
  _n=0
  while [ ! -s "$1" ] && [ "$_n" -lt 600 ]; do
    sleep 0.1
    _n=$((_n + 1))
  done
  [ -s "$1" ]
}
reset() {
  rm -rf "$pools" "$tmp"/log* "$tmp/running" "$tmp/running.overlap" "$tmp/ran"
  rm -f "$tracked" "$mlocal" "$adopter/planwright.yml"
  defaults=$DEFAULTS
}

# --- unset: unpooled, silent ----------------------------------------------------
reset
fsr -- -- "$suite" "$tmp/log" 0 7 >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 7 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" && [ ! -e "$pools" ] && [ ! -s "$tmp/err" ]
verdict "with full_suite_pool unset the suite runs unpooled, silently, its exit kept" \
  "unset: rc=$rc" "$tmp/err"

# --- a core layer without the key (an older install) counts as unset ------------
reset
grep -v '^full_suite_pool:' "$DEFAULTS" >"$tmp/old-defaults.yml"
defaults="$tmp/old-defaults.yml"
fsr -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" && [ ! -s "$tmp/err" ]
verdict "a key no layer sets runs the suite unpooled, silently" "absent key: rc=$rc" "$tmp/err"

# --- set: the run holds a slot for its own pid, passes the mark, then releases ----
reset
printf 'full_suite_pool: gate\n' >"$tracked"
(fsr -- -- "$suite" "$tmp/log" hold 0 >/dev/null 2>"$tmp/err") &
bg=$!
await "$tmp/log.pid"
held=$(sp report gate)
: >"$tmp/log.go"
wait "$bg"
rc=$?
pid=$(sed -n 's/^mark=gate://p' "$tmp/log.mark")
[ "$rc" -eq 0 ] && [ -n "$pid" ] \
  && printf '%s\n' "$held" | grep -q "^holder${TAB}1${TAB}$pid${TAB}(full-suite)${TAB}"
verdict "a pooled run holds a full-suite slot and hands the suite its hold mark" \
  "pooled: rc=$rc held='$held'" "$tmp/err"
# The slot's lock is a symbolic link; a dead owner's lock
# stays until a later take reclaims it; only a release removes it.
[ ! -L "$pools/gate/slot-1" ]
verdict "the slot is released after the suite ends" "slot-1 left behind (not released)"

# --- the suite runs in the caller's locale, not the script's own --------------------
reset
printf 'full_suite_pool: gate\n' >"$tracked"
fsr LC_ALL=en_US.UTF-8 -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err"
rc_set=$?
(
  unset LC_ALL
  fsr -- -- "$suite" "$tmp/log2" 0 0 >/dev/null 2>>"$tmp/err"
)
rc_unset=$?
[ "$rc_set" -eq 0 ] && [ "$rc_unset" -eq 0 ] && grep -qx 'lc=en_US.UTF-8' "$tmp/log.lc" \
  && grep -qx 'lc=<unset>' "$tmp/log2.lc"
verdict "the suite keeps the caller's LC_ALL, set or unset" \
  "locale: rc=$rc_set/$rc_unset" "$tmp/err"

# --- a failing suite still releases, its exit kept ------------------------------
reset
printf 'full_suite_pool: gate\n' >"$tracked"
fsr -- -- "$suite" "$tmp/log" 0 3 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 3 ] && [ ! -L "$pools/gate/slot-1" ]
verdict "a failing pooled suite keeps its exit and releases the slot" "failing: rc=$rc" "$tmp/err"

# --- a suite exiting 75 is not mistaken for an expired wait -------------------------
reset
printf 'full_suite_pool: gate\n' >"$tracked"
fsr -- -- "$suite" "$tmp/log" 0 75 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 1 ] && grep -q 'itself exited 75' "$tmp/err" && ! grep -q 'wait expired' "$tmp/err"
verdict "a suite's own exit 75 is reported as 1" "suite 75: rc=$rc" "$tmp/err"

# --- a signal to the wrapper waits for the suite, then releases ----------------------
# sig_case <signal> <expected exit> — signal the wrapper while its pooled suite
# holds, check the suite and the slot outlive the signal, then let it finish.
sig_case() {
  reset
  printf 'full_suite_pool: gate\n' >"$tracked"
  (fsr -- -- "$suite" "$tmp/log" hold 0 >/dev/null 2>"$tmp/err") &
  _bg=$!
  await "$tmp/log.pid"
  _wrapper=$(sed -n 's/^mark=gate://p' "$tmp/log.mark")
  _spid=$(cat "$tmp/log.pid")
  kill "-$1" "$_wrapper"
  sleep 1
  _during=gone
  kill -0 "$_spid" 2>/dev/null && kill -0 "$_wrapper" 2>/dev/null && [ -L "$pools/gate/slot-1" ] && _during=held
  : >"$tmp/log.go"
  wait "$_bg"
  _rc=$?
  [ "$_during" = held ] && [ "$_rc" -eq "$2" ] && [ ! -L "$pools/gate/slot-1" ]
}
sig_case TERM 143
verdict "TERM to the wrapper keeps the slot until the suite ends, then exits 143" \
  "TERM: during=$_during rc=$_rc" "$tmp/err"
sig_case HUP 129
verdict "HUP to the wrapper keeps the slot until the suite ends, then exits 129" \
  "HUP: during=$_during rc=$_rc" "$tmp/err"

# --- a signal during the take ends the wait at once, running no suite ------------------
reset
printf 'full_suite_pool: gate\nstep_pool_wait: 60s\n' >"$tracked"
h=$(owner)
sp take gate "$h" >/dev/null
(fsr -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err") &
bg=$!
_n=0
until grep -q 'waiting up to' "$tmp/err" 2>/dev/null || [ "$_n" -ge 600 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
waiter=$(sp report gate | wc -l)
pkill -TERM -f "full-suite-run.sh -- $suite $tmp/log "
start=$(date +%s)
wait "$bg"
rc=$?
took=$(($(date +%s) - start))
[ "$rc" -eq 143 ] && [ "$took" -le 10 ] && [ ! -e "$tmp/log.pid" ]
verdict "TERM during the take ends the wait at once and runs no suite" \
  "take signal: rc=$rc took=${took}s holders=$waiter" "$tmp/err"
sp release gate "$h" >/dev/null

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
[ "$ra" -eq 0 ] && [ "$rb" -eq 0 ] && [ -s "$tmp/logA.pid" ] && [ -s "$tmp/logB.pid" ] \
  && [ ! -e "$tmp/running.overlap" ]
verdict "two full suites sharing a one-slot pool run one at a time" \
  "overlap or failed run: ra=$ra rb=$rb" "$tmp/running.overlap"

# --- an expired wait runs no suite, names the holders, and takes nothing ---------------
reset
printf 'full_suite_pool: gate\nstep_pool_wait: 1s\n' >"$tracked"
h=$(owner)
sp take gate "$h" --step other-unit --worktree "$tmp/elsewhere" >/dev/null
fsr -- -- "$suite" "$tmp/log" 0 0 >"$tmp/out" 2>"$tmp/err"
rc=$?
after=$(sp report gate)
[ "$rc" -eq 75 ] && [ ! -e "$tmp/log.pid" ] \
  && grep -q '^full-suite-run: wait expired' "$tmp/err" \
  && grep -qF "holder${TAB}1${TAB}$h${TAB}other-unit${TAB}$tmp/elsewhere" "$tmp/out" \
  && [ "$after" = "holder${TAB}1${TAB}$h${TAB}other-unit${TAB}$tmp/elsewhere" ]
verdict "an expired wait exits 75, runs no suite, names the holders, and takes nothing" \
  "expired: rc=$rc after='$after'" "$tmp/err"

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

# --- a malformed pool name warns once and runs unpooled -------------------------------
reset
printf 'full_suite_pool: Bad_Pool\n' >"$tracked"
fsr -- -- "$suite" "$tmp/log" 0 0 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" \
  && [ "$(grep -c 'full_suite_pool' "$tmp/err")" -eq 1 ] && [ ! -e "$pools" ]
verdict "a malformed full_suite_pool warns once and the suite runs unpooled" \
  "malformed: rc=$rc" "$tmp/err"

# --- a failing pool helper warns and runs unpooled -----------------------------------
reset
stub="$tmp/stub"
mkdir -p "$stub"
cp "$FSR" "$stub/full-suite-run.sh"
printf '#!/bin/sh\nprintf "gate\\n"\n' >"$stub/config-get.sh"
printf '#!/bin/sh\nexit 1\n' >"$stub/step-pool.sh"
chmod +x "$stub"/*.sh
(cd "$repo" && unset PLANWRIGHT_STEP_POOL_HOLD && "$stub/full-suite-run.sh" -- "$suite" "$tmp/log" 0 0) >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" \
  && [ "$(grep -c 'pool helper failed' "$tmp/err")" -eq 1 ]
verdict "a failing pool helper warns once and the suite runs unpooled" "helper: rc=$rc" "$tmp/err"

# --- a config read failure warns once and runs unpooled -------------------------------
reset
printf '#!/bin/sh\nexit 4\n' >"$stub/config-get.sh"
(cd "$repo" && unset PLANWRIGHT_STEP_POOL_HOLD && "$stub/full-suite-run.sh" -- "$suite" "$tmp/log" 0 0) >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -qx 'mark=<unset>' "$tmp/log.mark" \
  && [ "$(grep -c 'cannot read full_suite_pool' "$tmp/err")" -eq 1 ]
verdict "a config read failure warns once and the suite runs unpooled" "config: rc=$rc" "$tmp/err"

# --- usage ---------------------------------------------------------------------------
reset
fsr -- >/dev/null 2>&1
rc1=$?
fsr -- touch "$tmp/ran" >/dev/null 2>&1
rc2=$?
fsr -- -- >/dev/null 2>&1
rc3=$?
[ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 2 ] && [ ! -e "$tmp/ran" ]
verdict "a missing -- or command is a usage error that runs nothing" "usage: $rc1 $rc2 $rc3"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all full-suite-run tests passed"
