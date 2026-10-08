#!/bin/sh
# Tests for scripts/step-pool.sh — the step pool helper (custom-steps
# REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.6; D-22, D-23, D-24).
#
# Every pool lives under a temporary pools root, and every config layer is a
# fixture except core, which is the shipped config/defaults.yml so the three
# keys' defaults are the ones under test. Slot owners are fixture `sleep`
# processes, so a dead owner is one this file killed.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-pool.sh
# shellcheck disable=SC2016 # bodies handed to `sh -c` are literal shell text
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# The helper refuses a group- or other-writable pool, so fixture directories
# must not inherit a permissive umask from the host.
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SP="$repo_root/scripts/step-pool.sh"
DEFAULTS="$repo_root/config/defaults.yml"
TAB=$(printf '\t')

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
# check <status> <ok-message> <fail-message>
check() {
  if [ "$1" -eq 0 ]; then
    ok "$2"
  else
    fail "$3"
  fi
}
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

[ -x "$SP" ] || {
  echo "FAIL: scripts/step-pool.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-pool.XXXXXX")" && pwd -P)" || exit 1
# Owners start inside command substitutions, so their pids are kept in a file
# the parent shell can read back at exit.
owners="$tmp/owners"
cleanup() {
  [ -f "$owners" ] && while read -r _p; do kill "$_p" 2>/dev/null; done <"$owners"
  rm -rf "$tmp"
}
trap cleanup EXIT

pools="$tmp/pools"
adopter="$tmp/adopter"
repo="$tmp/repo"
other="$tmp/other"
mkdir -p "$adopter" "$repo/.claude" "$other/.claude"
for _r in "$repo" "$other"; do
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$_r"
done
mlocal="$repo/.claude/planwright.local.yml"
tracked="$repo/.claude/planwright.yml"

# sp [<env assignment>...] -- <verb> <args>... — run the helper against the
# fixture layers from the fixture checkout, with no inherited hold mark.
sp() {
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
      "$SP" "$@"
  )
}

# pool_in <checkout> <pools root or ''> <verb> <args>... — run the helper from
# <checkout> as its repository, the pools root left to the default chain under
# a fixture XDG_STATE_HOME when none is given.
pool_in() {
  (
    cd "$1" || exit 99
    unset PLANWRIGHT_STEP_POOL_HOLD PLANWRIGHT_POOL_DIR PLANWRIGHT_CONFIG_STRICT_OVERLAYS PLANWRIGHT_ROOT \
      PLANWRIGHT_REPO_ROOT_CHECKED
    _pi_repo=$1
    _pi_root=$2
    shift 2
    if [ -n "$_pi_root" ]; then
      set -- env "PLANWRIGHT_POOL_DIR=$_pi_root" "$SP" "$@"
    else
      set -- "$SP" "$@"
    fi
    XDG_STATE_HOME="$tmp/xdg" \
      PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
      PLANWRIGHT_REPO_ROOT="$_pi_repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      "$@"
  )
}

# as_owner <script> [<arg>...] — run <script> under `sh -c` with the fixture
# layers exported, so the script's own shell can take a slot for itself.
as_owner() {
  (
    cd "$repo" || exit 99
    unset PLANWRIGHT_STEP_POOL_HOLD PLANWRIGHT_CONFIG_STRICT_OVERLAYS PLANWRIGHT_ROOT PLANWRIGHT_REPO_ROOT_CHECKED
    export PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_POOL_DIR="$pools"
    sh -c "$@"
  )
}

# owner — start a fixture slot owner and print its pid.
owner() {
  sleep 120 >/dev/null 2>&1 &
  _o=$!
  printf '%s\n' "$_o" >>"$owners"
  printf '%s' "$_o"
}

# kill_owner <pid> — end an owner and wait until it is gone.
kill_owner() {
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  _k=0
  while kill -0 "$1" 2>/dev/null && [ "$_k" -lt 50 ]; do
    sleep 0.1
    _k=$((_k + 1))
  done
}

reset() {
  rm -rf "$pools"
  rm -f "$mlocal" "$tracked" "$adopter/planwright.yml"
}

# --- the shipped keys ----------------------------------------------------------
grep -qx 'step_pool_capacity: 1' "$DEFAULTS"
verdict "core default step_pool_capacity is 1" "config/defaults.yml lacks 'step_pool_capacity: 1'"
grep -qx 'step_pool_wait: 60m' "$DEFAULTS"
verdict "core default step_pool_wait is 60m" "config/defaults.yml lacks 'step_pool_wait: 60m'"
grep -qx 'full_suite_pool:' "$DEFAULTS"
verdict "core default full_suite_pool is empty" "config/defaults.yml lacks an empty full_suite_pool"
! grep -q '^step_pool_capacity_' "$DEFAULTS"
verdict "the per-pool capacity family has no core default" "config/defaults.yml sets a step_pool_capacity_<pool> key"

# --- REQ-I1.3: capacity one serializes two callers -----------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
out=$(sp -- take serial "$a" --step build --worktree "$repo")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the first caller takes slot 1" "first take: rc=$rc out='$out'"
out=$(sp -- take serial "$b" --step lint --worktree "$other" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 3 ] && printf '%s\n' "$out" | head -n 1 | grep -q "^expired${TAB}-${TAB}"
verdict "at capacity one the second caller's wait expires" "second take: rc=$rc out='$out'"

# --- REQ-I1.4: the waiter names the live holder, at the start and at expiry -----
grep -F "waiting up to" "$tmp/err" | grep -qF "pid $a (step build, worktree $repo)"
verdict "the wait reports the holder's pid, step, and worktree at its start" \
  "start-of-wait report:" "$tmp/err"
grep -q "passed its 1s bound.*pid $a" "$tmp/err"
verdict "the expired wait names the holder" "expiry report:" "$tmp/err"
printf '%s\n' "$out" | grep -qxF "holder${TAB}1${TAB}$a${TAB}build${TAB}$repo"
verdict "the expired take lists the holder on stdout" "expired stdout: '$out'"
out=$(sp -- report serial)
[ "$out" = "holder${TAB}1${TAB}$a${TAB}build${TAB}$repo" ]
verdict "report lists the live holder" "report: '$out'"

# --- release: only the owner's release frees the slot ---------------------------
out=$(sp -- release serial "$b")
[ "$out" = none ] && [ -n "$(sp -- report serial)" ]
verdict "a release naming another owner frees nothing" "foreign release: '$out'"
out=$(sp -- release serial "$a")
[ "$out" = "released${TAB}1" ]
verdict "the owner's release frees its slot" "owner release: '$out'"
out=$(sp -- take serial "$b" --step lint)
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the waiter then takes the freed slot" "take after release: '$out'"
sp -- release serial "$b" >/dev/null

# --- REQ-I1.1: a slot shared by callers in two different checkouts ---------------
# Both callers use the default per-user root, each from its own checkout, and
# each records its git top level as its worktree.
reset
rm -rf "$tmp/xdg"
printf 'step_pool_wait: 1s\n' >"$mlocal"
printf 'step_pool_wait: 1s\n' >"$other/.claude/planwright.local.yml"
a=$(owner)
b=$(owner)
o1=$(pool_in "$repo" '' take shared "$a" --step build)
o2=$(pool_in "$other" '' take shared "$b" 2>"$tmp/err")
rc=$?
held=$(pool_in "$other" '' report shared)
[ "$o1" = "taken${TAB}1${TAB}0" ] && [ "$rc" -eq 3 ] && [ -L "$tmp/xdg/planwright/step-pools/shared/slot-1" ] \
  && [ "$held" = "holder${TAB}1${TAB}$a${TAB}build${TAB}$repo" ]
verdict "a caller in another checkout waits on the same per-user slot" \
  "other checkout: '$o1' rc=$rc report='$held'" "$tmp/err"
rm -f "$other/.claude/planwright.local.yml"

# --- REQ-I1.3: a per-pool override admits two; hyphens become underscores ------
reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_wide_pool: 2\n' >"$mlocal"
a=$(owner)
b=$(owner)
c=$(owner)
o1=$(sp -- take wide-pool "$a")
o2=$(sp -- take wide-pool "$b")
[ "$o1" = "taken${TAB}1${TAB}0" ] && [ "$o2" = "taken${TAB}2${TAB}0" ]
verdict "a per-pool capacity of two admits two callers" "wide: '$o1' '$o2'"
sp -- take wide-pool "$c" --waited 1 >/dev/null 2>&1
check $(($? == 3 ? 0 : 1)) "the third caller waits past the override" "a third caller was admitted"
o1=$(sp -- take serial "$c" 2>/dev/null)
sp -- take serial "$a" --waited 1 >/dev/null 2>&1
rc=$?
[ "$o1" = "taken${TAB}1${TAB}0" ] && [ "$rc" -eq 3 ]
verdict "another pool keeps the shared capacity of one" "pool 'serial': '$o1' then rc=$rc"
out=$(sp -- report wide-pool | sort)
printf '%s\n' "$out" | grep -q "${TAB}(full-suite)${TAB}"
verdict "a take naming no step records the full-suite marker" "report: '$out'"

# --- REQ-I1.3: a malformed capacity falls back in order, naming the layer -------
reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_mal: two\nstep_pool_capacity: 2\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
o2=$(sp -- take mal "$b" 2>/dev/null)
grep -q 'machine-local layer sets step_pool_capacity_mal.*falling back to step_pool_capacity$' "$tmp/err" \
  && [ "$o2" = "taken${TAB}2${TAB}0" ]
verdict "a malformed per-pool value falls back to step_pool_capacity with a warning naming the layer" \
  "per-pool fallback: '$o2' /" "$tmp/err"
[ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "the fallback costs one warning" "warnings:" "$tmp/err"

reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
printf 'step_pool_capacity: 0\n' >"$tracked"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
sp -- take mal "$b" --waited 1 >/dev/null 2>&1
rc=$?
grep -q 'repo-tracked layer sets step_pool_capacity .*core default 1' "$tmp/err" && [ "$rc" -eq 3 ]
verdict "a malformed shared value falls back to the core default with a warning naming the layer" \
  "shared fallback: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_mal: -1\nstep_pool_capacity: x\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
sp -- take mal "$b" --waited 1 >/dev/null 2>&1
rc=$?
grep -q 'step_pool_capacity_mal' "$tmp/err" && grep -q "machine-local.*'step_pool_capacity'.*core default" "$tmp/err" \
  && [ "$rc" -eq 3 ]
verdict "two malformed values fall back to the core default of one" "double fallback: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nnot a key line\n' >"$mlocal"
a=$(owner)
out=$(sp -- take filebad "$a" 2>"$tmp/err")
[ "$out" = "taken${TAB}1${TAB}0" ] && ! grep -q 'step_pool_capacity_filebad' "$tmp/err"
verdict "a malformed overlay file is not blamed on an unset per-pool key" "file fallback: '$out'" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_empty:\n' >"$mlocal"
a=$(owner)
sp -- take empty "$a" >/dev/null 2>"$tmp/err"
grep -q "machine-local layer sets step_pool_capacity_empty to ''," "$tmp/err"
verdict "an empty per-pool value is named as empty" "empty value:" "$tmp/err"

# --- REQ-I1.4: a malformed wait falls back to the default with a warning --------
reset
printf 'step_pool_wait: soon\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take w "$a" >/dev/null 2>&1
out=$(sp -- take w "$b" --waited 3600 2>"$tmp/err")
rc=$?
[ "$rc" -eq 3 ] && grep -q 'step_pool_wait' "$tmp/err" && grep -q 'passed its 3600s bound' "$tmp/err"
verdict "a malformed wait falls back to 60m with a warning" "malformed wait: rc=$rc /" "$tmp/err"
[ "$(grep -c 'step_pool_wait' "$tmp/err")" -eq 1 ]
verdict "the wait fallback costs one warning" "warnings:" "$tmp/err"
reset
printf 'step_pool_wait: soon\n' >"$tracked"
a=$(owner)
b=$(owner)
sp -- take w "$a" >/dev/null 2>&1
sp -- take w "$b" --waited 3600 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 3 ] && grep -q 'repo-tracked layer sets step_pool_wait' "$tmp/err" && grep -q 'passed its 3600s bound' "$tmp/err" \
  && [ "$(grep -c 'step_pool_wait' "$tmp/err")" -eq 1 ]
verdict "a malformed repo-tracked wait falls back too, with one warning" "tracked wait: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1.1h\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take whole "$a" >/dev/null
sp -- take whole "$b" --waited 3961 >/dev/null 2>"$tmp/err"
grep -q 'passed its 3960s bound' "$tmp/err"
verdict "a whole-second wait is not rounded up a second by float error" "1.1h bound:" "$tmp/err"

# --- REQ-I1.1: bounded repeated calls sum their seconds -------------------------
# The bound sits well past what config reads cost a loaded host, so only the
# summed --waited row reaches it.
reset
printf 'step_pool_wait: 30s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take sum "$a" >/dev/null
out=$(sp -- take sum "$b" --for 1 2>"$tmp/err")
rc=$?
[ "$rc" -eq 4 ] && printf '%s\n' "$out" | grep -q "^waiting${TAB}-${TAB}[1-9]"
verdict "a call capped by --for returns waiting with its seconds" "capped call: rc=$rc out='$out'"
w1=$(printf '%s\n' "$out" | cut -f 3)
out=$(sp -- take sum "$b" --waited "$w1" --for 1 2>"$tmp/err2")
rc=$?
[ "$rc" -eq 4 ] && printf '%s\n' "$out" | grep -q "^waiting${TAB}-${TAB}" && ! grep -q 'waiting up to' "$tmp/err2"
verdict "a continuing call does not repeat the start-of-wait report" "continuation: rc=$rc out='$out'" "$tmp/err2"
out=$(sp -- take sum "$b" --waited 30 --for 1 2>/dev/null)
rc=$?
[ "$rc" -eq 3 ]
verdict "the bound covers the summed wait across calls" "summed bound: rc=$rc out='$out'"
sp -- release sum "$a" >/dev/null
out=$(sp -- take sum "$b" --waited 2 --for 1)
rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "^taken${TAB}1${TAB}2$"
verdict "a continued call that takes reports the summed wait" "continued take: rc=$rc out='$out'"

# --- REQ-I1.2: a dead holder's slot is reclaimed --------------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take dead "$a" >/dev/null
kill_owner "$a"
out=$(sp -- take dead "$b")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a dead holder's slot is reclaimed by the next caller" "reclaim: '$out'"

# --- REQ-I1.2: a holder that dies during a wait is reclaimed by the waiter -------
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take midwait "$a" >/dev/null
sp -- take midwait "$b" >"$tmp/out" 2>"$tmp/err" &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill_owner "$a"
wait "$waiter"
rc=$?
out=$(cat "$tmp/out")
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "^taken${TAB}1${TAB}"
verdict "a waiter reclaims a holder that dies during its wait" "mid-wait reclaim: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.1: a slot is reclaimed after its owner exits normally ---------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
b=$(owner)
as_owner '"$1" take exit "$$" >"$2"' sh "$SP" "$tmp/took"
took=$(cat "$tmp/took")
out=$(sp -- take exit "$b")
[ "$took" = "taken${TAB}1${TAB}0" ] && [ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a slot is reclaimed after its owner process exits" "after exit: took='$took' out='$out'"

# --- REQ-I1.2: a child that outlives its owner does not keep the slot -----------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
b=$(owner)
as_owner '"$1" take leak "$$" >"$2"; sleep 120 >/dev/null 2>&1 & echo $! >"$3"' sh "$SP" "$tmp/took" "$tmp/child"
took=$(cat "$tmp/took")
child=$(cat "$tmp/child")
printf '%s\n' "$child" >>"$owners"
[ "$took" = "taken${TAB}1${TAB}0" ] && kill -0 "$child" 2>/dev/null
verdict "the fixture owner took the slot and its child outlives it" "took='$took', or the child exited with its owner"
out=$(sp -- take leak "$b")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a leaked child does not keep its owner's slot" "leaked child: '$out'"

# --- REQ-I1.1: an owner that stops running ends its own wait --------------------
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
a=$(owner)
w=$(owner)
sp -- take gone "$a" >/dev/null
sp -- take gone "$w" >"$tmp/out" 2>"$tmp/err" &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill_owner "$w"
wait "$waiter"
rc=$?
out=$(cat "$tmp/out")
[ "$rc" -eq 2 ] && grep -q "owner $w is not running" "$tmp/err" && [ -z "$out" ] \
  && [ "$(sp -- report gone | grep -c .)" -eq 1 ]
verdict "a take whose owner stops running mid-wait ends at once, holding nothing" \
  "owner gone mid-wait: rc=$rc out='$out'" "$tmp/err"

# --- an interrupted take leaves no scratch file behind ---------------------------
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
mkdir -p "$tmp/scratch"
a=$(owner)
w=$(owner)
sp -- take sig "$a" >/dev/null
(
  cd "$repo" || exit 99
  unset PLANWRIGHT_STEP_POOL_HOLD
  TMPDIR="$tmp/scratch" PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_POOL_DIR="$pools" \
    exec "$SP" take sig "$w" >/dev/null 2>"$tmp/err"
) &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill -TERM "$waiter"
wait "$waiter"
rc=$?
left=$(ls -A "$tmp/scratch")
[ "$rc" -eq 143 ] && [ -z "$left" ]
verdict "a take stopped by TERM exits 143 and removes its scratch file" "TERM: rc=$rc left='$left'" "$tmp/err"

# --- a take that cannot report its slot gives it back -----------------------------
reset
a=$(owner)
sp -- take mute "$a" 1</dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && [ ! -L "$pools/mute/slot-1" ] && grep -q 'could not be written' "$tmp/err" \
  && ! grep -q 'held for owner' "$tmp/err"
verdict "a take whose state line cannot be written exits 2 and gives the slot back" "unwritable stdout: rc=$rc" "$tmp/err"

# --- a take stopped inside the acquire gives back the slot it just linked ------
# The stub stalls the acquire's confirming readlink of slot-1, once, after the
# link exists, so TERM lands before the acquire has returned.
reset
a=$(owner)
stub9="$tmp/stub9"
mkdir -p "$stub9"
real_rl9=$(command -v readlink)
: >"$tmp/gate9"
printf '#!/bin/sh\ncase "$*" in *"/slot-1") if [ -e %s ]; then rm -f %s; echo $$ >%s; exec sleep 30; fi ;; esac\nexec %s "$@"\n' \
  "$tmp/gate9" "$tmp/gate9" "$tmp/stall9" "$real_rl9" >"$stub9/readlink"
chmod +x "$stub9/readlink"
rm -f "$tmp/stall9"
(
  cd "$repo" || exit 99
  unset PLANWRIGHT_STEP_POOL_HOLD PLANWRIGHT_CONFIG_STRICT_OVERLAYS PLANWRIGHT_ROOT PLANWRIGHT_REPO_ROOT_CHECKED
  PATH="$stub9:$PATH" PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_POOL_DIR="$pools" \
    exec "$SP" take inacq "$a" >/dev/null 2>"$tmp/err"
) &
waiter=$!
_n=0
until [ -s "$tmp/stall9" ] || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
[ -L "$pools/inacq/slot-1" ]
verdict "the stalled acquire has linked its slot" "the stub never stalled the acquire" "$tmp/err"
kill -TERM "$waiter"
kill "$(cat "$tmp/stall9")" 2>/dev/null
wait "$waiter"
rc=$?
[ "$rc" -eq 143 ] && [ ! -L "$pools/inacq/slot-1" ]
verdict "a take stopped inside the acquire gives the slot back" "stopped in the acquire: rc=$rc" "$tmp/err"

# --- a take stopped while waiting keeps an earlier take's hold under its pid ----
# The owner already holds slot-1 through a token an earlier take minted under
# the pid this take now runs as, the shape of a recycled helper pid.
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
o=$(owner)
sp -- take samepid "$o" >/dev/null
sp -- release samepid "$o" >/dev/null
(
  cd "$repo" || exit 99
  unset PLANWRIGHT_STEP_POOL_HOLD PLANWRIGHT_CONFIG_STRICT_OVERLAYS PLANWRIGHT_ROOT PLANWRIGHT_REPO_ROOT_CHECKED
  PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_POOL_DIR="$pools" \
    exec sh -c 'ln -s "$1-1000-999999999-$$-1" "$2/slot-1" && exec "$3" take samepid "$1"' \
    sh "$o" "$pools/samepid" "$SP" >/dev/null 2>"$tmp/err"
) &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill -TERM "$waiter"
wait "$waiter"
rc=$?
[ "$rc" -eq 143 ] && [ "$(readlink "$pools/samepid/slot-1" 2>/dev/null)" = "$o-1000-999999999-$waiter-1" ]
verdict "a take stopped while waiting leaves a hold an earlier same-pid take minted" "same-pid hold: rc=$rc" "$tmp/err"

# --- REQ-I1.1: released by its owner after a non-zero exit ----------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
b=$(owner)
as_owner '"$1" take nz "$$" >/dev/null || exit 9
  PLANWRIGHT_STEP_POOL_HOLD="nz:$$" sh -c "exit 7"
  rc=$?
  [ "$("$1" release nz "$$")" = "$(printf "released\t1")" ] || exit 8
  [ -z "$("$1" report nz)" ] || exit 8
  exit "$rc"' sh "$SP"
rc=$?
out=$(sp -- take nz "$b")
[ "$rc" -eq 7 ] && [ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the owner releases its slot after a non-zero exit" "non-zero exit: rc=$rc out='$out'"

# --- REQ-I1.2: the hold mark ----------------------------------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mark "$a" --step suite >/dev/null
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- take mark "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "nested${TAB}-${TAB}0" ] && [ ! -s "$tmp/err" ]
verdict "a take under a live same-pool mark returns at once, without a slot or a warning" \
  "nested take: rc=$rc out='$out'" "$tmp/err"
[ "$(sp -- report mark | grep -c .)" -eq 1 ]
verdict "the nested take took no slot" "the nested take holds a slot"
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- release mark "$b")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = nested ] && [ -n "$(sp -- report mark)" ]
verdict "a nested caller's release is a successful no-op" "nested release: rc=$rc out='$out'"
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- release mark "$a")
[ "$out" = nested ] && [ -n "$(sp -- report mark)" ]
verdict "a release under the mark leaves the owner's hold alone" "release under mark: '$out'"

sp -- take mark "$a" --waited 1 >/dev/null 2>&1
check $(($? == 3 ? 0 : 1)) "a same-owner take without a mark waits like any caller" \
  "a same-owner take without a mark was admitted"

dead=$(owner)
kill_owner "$dead"
for m in "mark:$dead" "other:$a" "mark:abc" "Mark:$a" "mark:0$a" "mark" "mark:$a:1" ":$a"; do
  sp "PLANWRIGHT_STEP_POOL_HOLD=$m" -- take mark "$b" --waited 1 >/dev/null 2>&1
  check $(($? == 3 ? 0 : 1)) "a mark '$m' is ignored and the caller waits" "mark '$m' admitted the caller"
done

d=$(owner)
e=$(owner)
sp -- take heldmark "$d" >/dev/null
kill_owner "$d"
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=heldmark:$d" -- take heldmark "$e")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a mark naming a holder that has since died is ignored" "dead holder's mark: '$out'"

# --- REQ-I1.2: an unusable pool runs unpooled, naming the cause -----------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
mkdir -p "$pools" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$pools/linked"
out=$(sp -- take linked "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'symbolic link' "$tmp/err" \
  && [ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "a symbolic-link pool directory runs unpooled with one warning" "linked: rc=$rc out='$out'" "$tmp/err"
[ -z "$(ls "$tmp/elsewhere")" ]
verdict "nothing is written through the link" "the link's target was written"

rm -rf "$pools"
ln -s "$tmp/elsewhere" "$pools"
out=$(sp -- take rootlink "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'symbolic link' "$tmp/err"
verdict "a symbolic-link pools root runs unpooled" "root link: '$out'" "$tmp/err"
out=$(sp -- release rootlink "$a" 2>"$tmp/err")
[ "$out" = unpooled ] && grep -q 'symbolic link.*nothing released' "$tmp/err"
verdict "a release on an unusable pool warns, naming the cause" "unusable release: '$out'" "$tmp/err"
rm -f "$pools"

stub="$tmp/stub"
mkdir -p "$stub"
real_ls=$(command -v ls)
printf '#!/bin/sh\nif [ "$*" = "-ldn %s" ]; then echo "drwx------ 2 4242424 0 64 Jan 1 00:00 %s"; exit 0; fi\nexec %s "$@"\n' \
  "$pools/foreign" "$pools/foreign" "$real_ls" >"$stub/ls"
chmod +x "$stub/ls"
sp -- take foreign "$a" >/dev/null 2>&1
sp -- release foreign "$a" >/dev/null 2>&1
out=$(sp "PATH=$stub:$PATH" -- take foreign "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools/foreign is not owned" "$tmp/err"
verdict "a pool directory another user owns runs unpooled" "foreign: rc=$rc out='$out'" "$tmp/err"

mkdir -p "$pools/squat/slot-1"
out=$(sp -- take squat "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'lock' "$tmp/err" \
  && grep -q 'not a lock symlink' "$tmp/err" && [ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "a lock-library error runs unpooled naming the cause" "squat: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.2: no scratch file still runs unpooled, and release needs none -------
reset
a=$(owner)
sp -- take noscratch "$a" >/dev/null
out=$(sp "TMPDIR=$tmp/absent" -- release noscratch "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "released${TAB}1" ]
verdict "release needs no scratch file" "release without TMPDIR: rc=$rc out='$out'" "$tmp/err"
out=$(sp "TMPDIR=$tmp/absent" -- take noscratch "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'scratch file' "$tmp/err" \
  && [ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "a take that cannot create its scratch file runs unpooled with one warning" \
  "take without TMPDIR: rc=$rc out='$out'" "$tmp/err"

# --- release and report: --slot, several slots, stale holder files, no pool -----
reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_multi: 2\n' >"$mlocal"
a=$(owner)
o1=$(sp -- take multi "$a")
o2=$(sp -- take multi "$a")
[ "$o1" = "taken${TAB}1${TAB}0" ] && [ "$o2" = "taken${TAB}2${TAB}0" ]
verdict "an owner may hold two slots of a pool of two" "multi: '$o1' '$o2'"
sp -- release multi "$a" >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a release by an owner of several slots names none and is refused" \
  "a release freed one of several slots unnamed"
printf 'stale-token\tother\t/elsewhere\n' >"$pools/multi/holder-1"
out=$(sp -- report multi)
printf '%s\n' "$out" | grep -qxF "holder${TAB}1${TAB}$a${TAB}?${TAB}?"
verdict "a holder file whose token is not the slot's reads as unknown" "report: '$out'"
out=$(sp -- release multi "$a" --slot 2)
[ "$out" = "released${TAB}2" ] && [ "$(sp -- report multi | cut -f 2)" = 1 ]
verdict "release --slot frees only the named slot" "release --slot: '$out'"
out=$(sp -- report never)
rc=$?
o2=$(sp -- release never "$a")
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$o2" = none ] && [ ! -e "$pools/never" ]
verdict "report and release on an absent pool print nothing and none, creating nothing" \
  "absent pool: rc=$rc report='$out' release='$o2'"
out=$(pool_in "$repo" relative/root take rel "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'must be an absolute path' "$tmp/err"
verdict "a relative pools root runs unpooled naming the cause" "relative root: '$out'" "$tmp/err"

# --- REQ-I1.6: no verb executes a command it is given ---------------------------
reset
a=$(owner)
marker="$tmp/executed"
for args in "take p $a touch $marker" "report p touch $marker" "release p $a touch $marker" \
  "take p $a --step touch $marker" "touch $marker"; do
  # shellcheck disable=SC2086 # the argument list is split on purpose
  sp -- $args >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$marker" ]
  verdict "'$args' is refused and runs nothing" "'$args': rc=$rc, or the marker exists"
done
sp -- take p "$a" --step 'x;touch' >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a step id outside the charset is refused" "a malformed step id was accepted"
sp -- take 'p;touch' "$a" >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a pool name outside the charset is refused" "a malformed pool name was accepted"
dead=$(owner)
kill_owner "$dead"
sp -- take p "$dead" >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a take for an owner that is not running is refused" "a dead owner was given a slot"
[ ! -e "$marker" ]
verdict "no fixture command ran" "the marker exists"

# --- the pools root override sits outside the step-context prefix --------------
# The worker command guard strips PLANWRIGHT_STEP_* assignments from a declared
# line, so the only one of those the helper reads is the hold mark.
reset
a=$(owner)
names=$(grep -o 'PLANWRIGHT_STEP_[A-Z][A-Z_]*' "$SP" | sort -u | tr '\n' ' ')
[ "$names" = "PLANWRIGHT_STEP_POOL_HOLD " ]
verdict "the hold mark is the only PLANWRIGHT_STEP_* variable the helper reads" "names read: $names"
(
  cd "$repo" || exit 99
  unset PLANWRIGHT_POOL_DIR PLANWRIGHT_STEP_POOL_HOLD
  PLANWRIGHT_STEP_POOL_ROOT="$tmp/oldroot" XDG_STATE_HOME="$tmp/xdg7" \
    PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
    "$SP" take renamed "$a" >/dev/null 2>&1
)
[ -L "$tmp/xdg7/planwright/step-pools/renamed/slot-1" ] && [ ! -e "$tmp/oldroot" ]
verdict "a PLANWRIGHT_STEP_-prefixed root is not honoured" "the take used the old override name"

# --- REQ-I1.4: an unreadable holder file reads as an unknown holder, quietly ---
if [ "$(id -u)" = 0 ]; then
  ok "skipped: root reads a mode-000 holder file"
else
  reset
  a=$(owner)
  sp -- take sealed "$a" --step build >/dev/null
  chmod 000 "$pools/sealed/holder-1"
  out=$(sp -- report sealed 2>"$tmp/err")
  chmod 600 "$pools/sealed/holder-1"
  [ "$out" = "holder${TAB}1${TAB}$a${TAB}?${TAB}?" ] && [ ! -s "$tmp/err" ]
  verdict "an unreadable holder file reports an unknown holder with nothing on stderr" "sealed: '$out'" "$tmp/err"
  sp -- release sealed "$a" >/dev/null
fi

# --- REQ-I1.2: a pool another user could write to runs unpooled ----------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
sp -- take shared "$a" >/dev/null 2>&1
sp -- release shared "$a" >/dev/null 2>&1
chmod 770 "$pools/shared"
out=$(sp -- take shared "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] \
  && grep -qF "$pools/shared is writable by group or other users" "$tmp/err" && [ ! -L "$pools/shared/slot-1" ]
verdict "a group-writable pool directory runs unpooled" "group-writable: rc=$rc out='$out'" "$tmp/err"
chmod 707 "$pools/shared"
out=$(sp -- take shared "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools/shared is writable by group or other users" "$tmp/err"
verdict "an other-writable pool directory runs unpooled" "other-writable: '$out'" "$tmp/err"
chmod 700 "$pools/shared"
b=$(owner)
sp -- take shared "$b" >/dev/null 2>&1
chmod 1777 "$pools"
out=$(sp -- take shared "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools is writable by group or other users" "$tmp/err"
verdict "a world-writable pools root runs unpooled, sticky bit or not" "root: '$out'" "$tmp/err"
out=$(sp -- report shared 2>"$tmp/err")
[ -z "$out" ] && grep -q 'writable by group or other users' "$tmp/err"
verdict "report on a world-writable root warns and lists none of its holders" "report: '$out'" "$tmp/err"
chmod 700 "$pools"
sp -- release shared "$b" >/dev/null
out=$(sp -- take shared "$a")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "an owner-only pool is used again once the bits are cleared" "after chmod: '$out'"
sp -- release shared "$a" >/dev/null
reset
out=$(umask 002 && sp -- take loose "$a" 2>"$tmp/err")
[ "$out" = "taken${TAB}1${TAB}0" ] && [ -d "$pools/loose" ] \
  && [ -z "$(find "$pools" "$pools/loose" -prune \( -perm -020 -o -perm -002 \))" ]
verdict "a pool created under a permissive umask is owner-only and usable" "umask 002: '$out'" "$tmp/err"
sp -- release loose "$a" >/dev/null

# --- REQ-I1.2: each unusable-pool cause is named for what it is ----------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
mkdir -p "$pools"
: >"$pools/plainfile"
out=$(sp -- take plainfile "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools/plainfile exists and is not a directory" "$tmp/err"
verdict "an existing non-directory is named as one" "non-directory: '$out'" "$tmp/err"
if [ "$(id -u)" = 0 ]; then
  ok "skipped: a directory root cannot create needs a non-root user"
else
  mkdir -p "$tmp/ro"
  chmod 500 "$tmp/ro"
  out=$(pool_in "$repo" "$tmp/ro/pools" take nocreate "$a" 2>"$tmp/err")
  chmod 700 "$tmp/ro"
  [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$tmp/ro/pools could not be created" "$tmp/err"
  verdict "a directory that cannot be created is named as such" "no create: '$out'" "$tmp/err"
fi
if [ "$(id -u)" = 0 ]; then
  ok "skipped: a pool directory root cannot list needs a non-root user"
else
  sp -- take unlisted "$a" >/dev/null 2>&1
  chmod 300 "$pools/unlisted"
  out=$(sp -- release unlisted "$a" 2>"$tmp/err")
  rout=$(sp -- report unlisted 2>>"$tmp/err")
  chmod 700 "$pools/unlisted"
  [ "$out" = unpooled ] && [ -z "$rout" ] && [ -L "$pools/unlisted/slot-1" ] \
    && [ "$(grep -cF "$pools/unlisted cannot be listed" "$tmp/err")" -eq 2 ]
  verdict "a pool directory that cannot be listed is named as such, its slot never released as none" \
    "unlisted: out='$out' report='$rout'" "$tmp/err"
  sp -- release unlisted "$a" >/dev/null
fi
stub8="$tmp/stub8"
mkdir -p "$stub8"
printf '#!/bin/sh\nexit 1\n' >"$stub8/id"
chmod +x "$stub8/id"
out=$(sp "PATH=$stub8:$PATH" -- take nouid "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'the running user id could not be read' "$tmp/err" \
  && ! grep -q 'not owned' "$tmp/err"
verdict "an unreadable user id is not reported as foreign ownership" "no uid: '$out'" "$tmp/err"
sp -- take noowner "$a" >/dev/null 2>&1
sp -- release noowner "$a" >/dev/null 2>&1
stub8b="$tmp/stub8b"
mkdir -p "$stub8b"
real_ls8=$(command -v ls)
printf '#!/bin/sh\nif [ "$*" = "-ldn %s" ]; then exit 1; fi\nexec %s "$@"\n' "$pools/noowner" "$real_ls8" >"$stub8b/ls"
chmod +x "$stub8b/ls"
out=$(sp "PATH=$stub8b:$PATH" -- take noowner "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools/noowner: its owner and mode could not be read" "$tmp/err" \
  && ! grep -q 'not owned' "$tmp/err"
verdict "an unreadable owner is not reported as foreign ownership" "no owner: '$out'" "$tmp/err"

# --- REQ-I1.2: the holder file never writes outside the pool --------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
mkdir -p "$pools/hlink" "$tmp/outside"
ln -s "$tmp/outside" "$pools/hlink/holder-1"
out=$(sp -- take hlink "$a" --step build)
[ "$out" = "taken${TAB}1${TAB}0" ] && [ -z "$(ls -A "$tmp/outside")" ] \
  && [ ! -L "$pools/hlink/holder-1" ] && [ -f "$pools/hlink/holder-1" ]
verdict "a symbolic-link holder file is replaced, never written through" "symlink holder: '$out'"
sp -- report hlink | grep -q "${TAB}build${TAB}"
verdict "the replaced holder file names the holder" "report: holder not recorded"
sp -- release hlink "$a" >/dev/null
mkdir -p "$pools/hdir/holder-1"
out=$(sp -- take hdir "$a" --step build)
[ "$out" = "taken${TAB}1${TAB}0" ] && [ -z "$(ls -A "$pools/hdir/holder-1")" ] \
  && [ -z "$(find "$pools/hdir" -name '.holder-*')" ]
verdict "a directory squatting the holder file is left alone and no part file remains" "dir holder: '$out'"
sp -- report hdir | grep -q "${TAB}?${TAB}?$"
verdict "a holder that could not be recorded reads as unknown" "the report named a holder it could not have recorded"
sp -- release hdir "$a" >/dev/null

# --- REQ-I1.1: a slot's owner is a process of the running user ------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
# pid 1 is the other user's process here, unless it runs as this user (as root,
# or as a container's entrypoint) or its user cannot be read.
pid1_uid=$(ps -o uid= -p 1 2>/dev/null | tr -d ' ')
if [ -z "$pid1_uid" ] || [ "$pid1_uid" = "$(id -u)" ]; then
  ok "skipped: pid 1 is not a readable process of another user"
else
  sp -- take foreignowner 1 >/dev/null 2>"$tmp/err"
  rc=$?
  [ "$rc" -eq 2 ] && grep -q 'owner 1 is not a process of the running user' "$tmp/err" \
    && [ ! -L "$pools/foreignowner/slot-1" ]
  verdict "a take for another user's process is refused" "foreign owner: rc=$rc" "$tmp/err"
fi
stub4="$tmp/stub4"
mkdir -p "$stub4"
real_ps4=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *uid=*) exit 1 ;; esac\nexec %s "$@"\n' "$real_ps4" >"$stub4/ps"
chmod +x "$stub4/ps"
a=$(owner)
out=$(sp "PATH=$stub4:$PATH" -- take nouser "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] \
  && grep -q "owner $a's user could not be read; running unpooled" "$tmp/err" \
  && [ "$(grep -c . "$tmp/err")" -eq 1 ] && [ ! -L "$pools/nouser/slot-1" ]
verdict "an owner whose user cannot be read runs unpooled with one warning" "unreadable owner user: rc=$rc out='$out'" "$tmp/err"
gone=$(owner)
kill_owner "$gone"
sp "PATH=$stub4:$PATH" -- take nouser "$gone" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q "owner $gone is not running" "$tmp/err"
verdict "an owner that is gone is still refused when no user can be read" "gone owner: rc=$rc" "$tmp/err"
# The owner ends inside the user lookup, after the first running check passed,
# so only the re-check behind an unreadable user can tell it is gone. It is
# started detached, so no shell of this test keeps it as a zombie kill -0 sees.
late=$(sh -c 'sleep 120 >/dev/null 2>&1 & echo $!')
printf '%s\n' "$late" >>"$owners"
stublate="$tmp/stublate"
mkdir -p "$stublate"
printf '#!/bin/sh\ncase "$*" in *uid=*)\n  kill %s 2>/dev/null; k=0\n  while kill -0 %s 2>/dev/null && [ "$k" -lt 50 ]; do sleep 0.1; k=$((k + 1)); done\n  exit 1 ;;\nesac\nexec %s "$@"\n' \
  "$late" "$late" "$real_ps4" >"$stublate/ps"
chmod +x "$stublate/ps"
sp "PATH=$stublate:$PATH" -- take nouser "$late" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q "owner $late is not running" "$tmp/err" && ! grep -q 'running unpooled' "$tmp/err"
verdict "an owner that ends during its user lookup is refused, not run unpooled" "late-gone owner: rc=$rc" "$tmp/err"
# The same, with the owner ending inside the second lookup an unreadable user
# gets, so only a running check after that read can tell it is gone.
late2=$(sh -c 'sleep 120 >/dev/null 2>&1 & echo $!')
printf '%s\n' "$late2" >>"$owners"
stublate2="$tmp/stublate2"
mkdir -p "$stublate2"
printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  [ "$n" -eq 2 ] || exit 1\n  kill %s 2>/dev/null; k=0\n  while kill -0 %s 2>/dev/null && [ "$k" -lt 50 ]; do sleep 0.1; k=$((k + 1)); done\n  exit 1 ;;\nesac\nexec %s "$@"\n' \
  "$stublate2" "$stublate2" "$late2" "$late2" "$real_ps4" >"$stublate2/ps"
chmod +x "$stublate2/ps"
sp "PATH=$stublate2:$PATH" -- take nouser "$late2" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q "owner $late2 is not running" "$tmp/err" && ! grep -q 'running unpooled' "$tmp/err" \
  && [ "$(cat "$stublate2/count")" -eq 2 ]
verdict "an owner that ends during the second user lookup is refused, not run unpooled" "late-gone owner, second lookup: rc=$rc" "$tmp/err"
out=$(sp -- take nouser "$a")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "an owner of the running user is accepted" "own owner: '$out'"
sp -- release nouser "$a" >/dev/null

# --- a worktree path is refused only for control characters ---------------------
# U+20AC is E2 82 AC in UTF-8: its middle byte sits in the C1 range a display
# sanitizer strips, but the path is a valid one.
reset
a=$(owner)
euro=$(printf '\342\202\254')
wt6="$tmp/wt-$euro"
out=$(sp -- take utf "$a" --worktree "$wt6" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "taken${TAB}1${TAB}0" ] && [ "$(cut -f 3 "$pools/utf/holder-1")" = "$wt6" ]
verdict "a UTF-8 --worktree is accepted and recorded as given" "utf-8 worktree: rc=$rc out='$out'" "$tmp/err"
sp -- release utf "$a" >/dev/null
mkdir -p "$wt6"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$wt6"
rm -f "$pools/utf/holder-1"
out=$(pool_in "$wt6" "$pools" take utf "$a" 2>"$tmp/err")
[ "$out" = "taken${TAB}1${TAB}0" ] && [ "$(cut -f 3 "$pools/utf/holder-1")" = "$wt6" ]
verdict "a UTF-8 default worktree is recorded, not read as unprintable" "default worktree not recorded" "$tmp/err"
sp -- release utf "$a" >/dev/null
for bad in "$tmp/tab$TAB/x" "$tmp/del$(printf '\177')/x" "$tmp/esc$(printf '\033')/x"; do
  sp -- take utf "$a" --worktree "$bad" >/dev/null 2>&1
  check $(($? == 2 ? 0 : 1)) "a --worktree carrying a C0 or DEL byte is refused" "a control byte in --worktree was accepted"
done

# --- REQ-I1.1: an owner whose pid passes to another user mid-take is refused ----
# The stub answers the owner's user truthfully for the first lookups, then as
# another user's, the shape of the owner exiting and its pid being reused.
# The bound only has to outlast the take's setup on a loaded host: the refusal
# comes in the first wait round.
reset
printf 'step_pool_wait: 30s\n' >"$mlocal"
stub11="$tmp/stub11"
mkdir -p "$stub11"
real_ps11=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  if [ "$n" -gt "$(cat "%s/truthful")" ]; then echo 4242424; exit 0; fi ;;\nesac\nexec %s "$@"\n' \
  "$stub11" "$stub11" "$stub11" "$real_ps11" >"$stub11/ps"
chmod +x "$stub11/ps"
a=$(owner)
b=$(owner)
sp -- take reuse "$a" >/dev/null
echo 1 >"$stub11/truthful"
rm -f "$stub11/count"
sp "PATH=$stub11:$PATH" -- take reuse "$b" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q "owner $b is not a process of the running user" "$tmp/err" \
  && grep -q "pool reuse is full" "$tmp/err" && [ "$(cat "$stub11/count")" -eq 2 ] \
  && [ "$(sp -- report reuse | cut -f 3)" = "$a" ]
verdict "a wait round refuses an owner now another user's, leaving the holder's slot" "mid-wait reuse: rc=$rc" "$tmp/err"
sp -- release reuse "$a" >/dev/null
echo 1 >"$stub11/truthful"
rm -f "$stub11/count"
out=$(sp "PATH=$stub11:$PATH" -- take reuse "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && grep -q "owner $b is not a process of the running user" "$tmp/err" \
  && [ ! -L "$pools/reuse/slot-1" ] && [ "$(cat "$stub11/count")" -eq 2 ] && ! grep -q 'is full' "$tmp/err"
verdict "an owner found another user's after the acquire is refused and its slot given back" \
  "post-acquire reuse: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.2: a pool directory carrying an ACL runs unpooled -------------------
# An ACL can grant other users write while the mode bits read owner-only; ls
# marks one with a trailing `+` on the mode, which the screen refuses.
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
sp -- take acl "$a" >/dev/null 2>&1
sp -- release acl "$a" >/dev/null 2>&1
stub10="$tmp/stub10"
mkdir -p "$stub10"
real_ls10=$(command -v ls)
printf '#!/bin/sh\nif [ "$*" = "-ldn %s" ]; then echo "drwx------+ 2 %s 0 64 Jan 1 00:00 %s"; exit 0; fi\nexec %s "$@"\n' \
  "$pools/acl" "$(id -u)" "$pools/acl" "$real_ls10" >"$stub10/ls"
chmod +x "$stub10/ls"
out=$(sp "PATH=$stub10:$PATH" -- take acl "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -qF "$pools/acl carries an access control list" "$tmp/err" \
  && [ ! -L "$pools/acl/slot-1" ]
verdict "a pool directory whose mode carries an ACL marker runs unpooled" "acl marker: rc=$rc out='$out'" "$tmp/err"
printf '#!/bin/sh\nif [ "$*" = "-ldn %s" ]; then echo "drwx------@ 2 %s 0 64 Jan 1 00:00 %s"; exit 0; fi\nexec %s "$@"\n' \
  "$pools/acl" "$(id -u)" "$pools/acl" "$real_ls10" >"$stub10/ls"
out=$(sp "PATH=$stub10:$PATH" -- take acl "$a")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "an extended-attribute marker alone does not refuse the pool" "xattr marker: '$out'"
sp -- release acl "$a" >/dev/null
mkdir -p "$pools/realacl"
if chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$pools/realacl" 2>/dev/null; then
  out=$(sp -- take realacl "$a" 2>"$tmp/err")
  rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'carries an access control list' "$tmp/err" \
    && [ ! -L "$pools/realacl/slot-1" ]
  verdict "a real ACL granting other users write runs unpooled" "real acl: '$out'" "$tmp/err"
else
  ok "skipped: this host's chmod sets no ACL"
fi

# --- REQ-I1.2: an ACL hidden behind an extended-attribute marker is found -------
# macOS ls shows `@` in place of `+` when a directory carries both, so the
# screen reads the ACL entries themselves.
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
mkdir -p "$pools/xattracl" "$pools/xattronly"
if command -v xattr >/dev/null 2>&1 && xattr -w org.example.pool 1 "$pools/xattronly" 2>/dev/null \
  && xattr -w org.example.pool 1 "$pools/xattracl" 2>/dev/null \
  && chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$pools/xattracl" 2>/dev/null; then
  out=$(sp -- take xattracl "$a" 2>"$tmp/err")
  rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'carries an access control list' "$tmp/err" \
    && [ ! -L "$pools/xattracl/slot-1" ]
  verdict "an ACL behind an extended-attribute marker runs unpooled" "xattr+acl: rc=$rc out='$out'" "$tmp/err"
  out=$(sp -- take xattronly "$a" 2>"$tmp/err")
  [ "$out" = "taken${TAB}1${TAB}0" ] && [ ! -s "$tmp/err" ]
  verdict "an extended attribute without an ACL is accepted" "xattr only: '$out'" "$tmp/err"
  sp -- release xattronly "$a" >/dev/null
else
  ok "skipped: this host sets no extended attribute with an ACL"
fi

# --- REQ-I1.1: an owner whose user turns unreadable mid-take is refused ---------
# On a host that hides other users' processes, an unreadable user after entry
# is what another user's process reusing the owner's pid looks like.
reset
printf 'step_pool_wait: 30s\n' >"$mlocal"
stub14="$tmp/stub14"
mkdir -p "$stub14"
real_ps14=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  [ "$n" -le 1 ] || exit 1 ;;\nesac\nexec %s "$@"\n' \
  "$stub14" "$stub14" "$real_ps14" >"$stub14/ps"
chmod +x "$stub14/ps"
a=$(owner)
b=$(owner)
sp -- take hidden "$a" >/dev/null
rm -f "$stub14/count"
sp "PATH=$stub14:$PATH" -- take hidden "$b" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q "owner $b's user could not be read during the take" "$tmp/err" \
  && grep -q 'waiting up to' "$tmp/err" && [ "$(sp -- report hidden | cut -f 3)" = "$a" ]
verdict "a wait round refuses an owner whose user turned unreadable, the holder kept" "mid-wait unreadable: rc=$rc" "$tmp/err"
sp -- release hidden "$a" >/dev/null
rm -f "$stub14/count"
out=$(sp "PATH=$stub14:$PATH" -- take hidden "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && grep -q "owner $b's user could not be read during the take" "$tmp/err" \
  && ! grep -q 'waiting up to' "$tmp/err" && [ ! -L "$pools/hidden/slot-1" ]
verdict "an owner whose user turned unreadable after the acquire is refused, its slot given back" \
  "post-acquire unreadable: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.2: a slot a take could not give back is named ----------------------
# The pool directory turns read-only as the post-acquire check refuses, so the
# give-back's unlink fails and the slot stays held.
if [ "$(id -u)" -ne 0 ]; then
  reset
  printf 'step_pool_wait: 1s\n' >"$mlocal"
  stubgb="$tmp/stubgb"
  mkdir -p "$stubgb"
  printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  if [ "$n" -gt 1 ]; then chmod 500 "%s"; exit 1; fi ;;\nesac\nexec %s "$@"\n' \
    "$stubgb" "$stubgb" "$pools/stuck" "$real_ps14" >"$stubgb/ps"
  chmod +x "$stubgb/ps"
  b=$(owner)
  sp "PATH=$stubgb:$PATH" -- take stuck "$b" >/dev/null 2>"$tmp/err"
  rc=$?
  chmod 700 "$pools/stuck" 2>/dev/null
  [ "$rc" -eq 2 ] && [ -L "$pools/stuck/slot-1" ] && grep -q "pool stuck: slot 1 could not be given back" "$tmp/err"
  verdict "a slot the take could not give back is named in a warning" "stuck give-back: rc=$rc" "$tmp/err"
  sp -- release stuck "$b" >/dev/null
  # Unsearchable, the directory hides the slot's link, so the take cannot
  # even read back whose hold it is.
  rm -f "$stubgb/count"
  printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  if [ "$n" -gt 1 ]; then chmod 600 "%s"; exit 1; fi ;;\nesac\nexec %s "$@"\n' \
    "$stubgb" "$stubgb" "$pools/hide" "$real_ps14" >"$stubgb/ps"
  sp "PATH=$stubgb:$PATH" -- take hide "$b" >/dev/null 2>"$tmp/err"
  rc=$?
  chmod 700 "$pools/hide" 2>/dev/null
  [ "$rc" -eq 2 ] && [ -L "$pools/hide/slot-1" ] && grep -q "pool hide: slot 1 could not be read back to give it back" "$tmp/err"
  verdict "a slot the take could not read back is named in a warning" "hidden give-back: rc=$rc" "$tmp/err"
  sp -- release hide "$b" >/dev/null
else
  ok "skipped: root writes into a read-only pool directory"
fi

# --- REQ-I1.2: a nested take stays silent where the owner's user is unreadable --
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
stub15="$tmp/stub15"
mkdir -p "$stub15"
real_ps15=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *uid=*) exit 1 ;; esac\nexec %s "$@"\n' "$real_ps15" >"$stub15/ps"
chmod +x "$stub15/ps"
a=$(owner)
b=$(owner)
sp -- take quiet "$a" >/dev/null
out=$(sp "PATH=$stub15:$PATH" "PLANWRIGHT_STEP_POOL_HOLD=quiet:$a" -- take quiet "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "nested${TAB}-${TAB}0" ] && [ ! -s "$tmp/err" ]
verdict "a nested take under a live mark prints nested and no warning when no user can be read" \
  "nested unreadable: rc=$rc out='$out'" "$tmp/err"
out=$(sp "PATH=$stub15:$PATH" -- take quiet "$b" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q "owner $b's user could not be read; running unpooled" "$tmp/err"
verdict "without a mark the unreadable owner still runs unpooled" "unmarked unreadable: '$out'" "$tmp/err"
sp -- release quiet "$a" >/dev/null

# --- REQ-I1.1: the running user id is read once per take ------------------------
# A first read that fails while a later one succeeds must not skip the owner
# check: the take runs unpooled instead of holding a slot for any pid.
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
stub19="$tmp/stub19"
mkdir -p "$stub19"
real_id19=$(command -v id)
printf '#!/bin/sh\nif [ "$1" = -u ] && [ ! -e "%s/seen" ]; then : >"%s/seen"; exit 1; fi\nexec %s "$@"\n' \
  "$stub19" "$stub19" "$real_id19" >"$stub19/id"
chmod +x "$stub19/id"
if [ "$(id -u)" = 0 ]; then
  ok "skipped: a foreign owner cannot be fixtured as root"
else
  out=$(sp "PATH=$stub19:$PATH" -- take idonce 1 2>"$tmp/err")
  rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && [ ! -L "$pools/idonce/slot-1" ] \
    && grep -q 'running user id could not be read' "$tmp/err"
  verdict "a uid read that fails once runs the take unpooled, never holding for pid 1" "uid once: rc=$rc out='$out'" "$tmp/err"
fi

# --- REQ-I1.1: one transient user lookup failure does not refuse a take ---------
# The stub fails the first wait round's lookup and frees the holder's slot on
# the re-read, so the take succeeds only by reaching a wait round and not
# refusing there, however long its setup runs.
reset
printf 'step_pool_wait: 30s\n' >"$mlocal"
stub20="$tmp/stub20"
mkdir -p "$stub20"
real_ps20=$(command -v ps)
a=$(owner)
b=$(owner)
printf '#!/bin/sh\ncase "$*" in *uid=*)\n  n=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"%s/count"\n  [ "$n" -ne 2 ] || exit 1\n  [ "$n" -ne 3 ] || PATH="%s" "%s" release blip %s >/dev/null ;;\nesac\nexec %s "$@"\n' \
  "$stub20" "$stub20" "$PATH" "$SP" "$a" "$real_ps20" >"$stub20/ps"
chmod +x "$stub20/ps"
sp -- take blip "$a" >/dev/null
out=$(sp "PATH=$stub20:$PATH" -- take blip "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "${out%%"$TAB"*}" = taken ] && ! grep -q 'could not be read during the take' "$tmp/err" \
  && [ "$(cat "$stub20/count")" -ge 3 ]
verdict "a single failed user lookup mid-wait is re-read, not refused" "transient lookup: rc=$rc out='$out'" "$tmp/err"
sp -- release blip "$b" >/dev/null

# --- REQ-I1.2: the helper sits on the shared primitive --------------------------
grep -qF '. "$script_dir/lock-lib.sh"' "$SP"
verdict "the helper sources the lock library" "scripts/step-pool.sh does not source lock-lib.sh"
grep -q '^#   scripts/step-pool.sh' "$repo_root/scripts/lock-lib.sh"
verdict "the lock-holder list names the helper" "lock-lib.sh's holder list omits scripts/step-pool.sh"
mkdir -p "$tmp/scan/scripts" "$tmp/scan/tests" "$tmp/scan/githooks"
cp "$SP" "$tmp/scan/scripts/step-pool.sh"
cp "$here/test-step-pool.sh" "$tmp/scan/tests/test-step-pool.sh"
out=$(/bin/bash "$repo_root/scripts/check-lock-primitive.sh" "$tmp/scan" 2>&1)
verdict "check-lock-primitive reports the helper and its test clean" "check-lock-primitive: $out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all step-pool tests passed"
