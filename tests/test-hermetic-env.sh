#!/bin/bash
# Tests for tests/lib/hermetic-env.sh, the clearing library: the variable
# list and its clearing, the runner's sentinel arms, the per-case fleet-home
# pin and the inherited-registry leak check the fleet suites use, and the
# access probe; and for tests/lib/dead-owner.sh. The inherited home here is
# always a stand-in under this suite's own temp root.
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# run_case <inherited-home> <script>: source the helper in a fresh shell, so
# the remembered inherited home starts unset, then run <script> there. The
# single quotes are deliberate: the child shell expands its own arguments.
# shellcheck disable=SC2016
run_case() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$1" \
    /bin/bash -c '. "$1/lib/hermetic-env.sh"; shift; eval "$1"' _ "$here" "$2"
}

# 1. A pin points every arm of the chain under its directory.
# shellcheck disable=SC2016
out=$(run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; printf "%s|%s|%s\n" "$PLANWRIGHT_FLEET_STATE_DIR" "$CLAUDE_PLUGIN_DATA" "$CLAUDE_DIR"')
if [ "$out" = "$tmp/a/fleet|$tmp/a/plugin-data|$tmp/a/claude" ]; then
  pass "a pin points the override, plugin-data, and writer arms at its directory"
else
  fail "a pin left an arm unpinned: $out"
fi

# 1b. A pin refuses an empty or relative directory, and one it cannot create,
#     and leaves the chain as it found it.
for bad in '' 'relative/home' '/dev/null/home'; do
  # shellcheck disable=SC2016
  if out=$(run_case "$tmp/op" 'fleet_home_pin "'"$bad"'" && echo pinned; printf "%s\n" "$PLANWRIGHT_FLEET_STATE_DIR"'); then :; fi
  if [ "$out" = "$tmp/op" ]; then
    pass "a pin refuses '$bad' and leaves the chain unpinned"
  else
    fail "a pin accepted '$bad': $out"
  fi
done

# 2. The inherited home is the one resolved before the first pin, and a
#    later pin never replaces it with the previous case's fixture.
out=$(run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_pin "'"$tmp"'/b"; fleet_home_inherited')
if [ "$out" = "$tmp/op" ]; then
  pass "the inherited home survives later pins"
else
  fail "the inherited home moved to '$out'"
fi

# 3. A record naming the needle in the inherited registry is a leak; one that
#    does not name it, such as a concurrent real dispatch, is not. Both are
#    written by the fleet's own writer, so the check is held to wherever that
#    writer keeps its records.
register_op() {
  PLANWRIGHT_FLEET_STATE_DIR="$tmp/op" /bin/sh "$here/../scripts/fleet-state.sh" register "$1" "$2" --state-dir "$3" \
    </dev/null >/dev/null 2>&1 || fail "the fleet writer could not register $1 into the stand-in home"
}
register_op real-worker scope /elsewhere/wt
if run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_leaked "'"$tmp"'/suite-root"'; then
  fail "a registry without the needle read as a leak"
else
  pass "a record that does not name the suite's root is not a leak"
fi
register_op headless-x x:3 "$tmp/suite-root/state-h1/3"
if run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_leaked "'"$tmp"'/suite-root"'; then
  pass "a record naming the suite's root is a leak"
else
  fail "a record naming the suite's root was not detected"
fi

# 3b. The leak check reads the inherited home even when no pin ran first, so
#     a suite that checks before (or without) pinning is never a vacuous pass.
if run_case "$tmp/op" 'fleet_home_leaked "'"$tmp"'/suite-root"'; then
  pass "the leak check reads the inherited home without a prior pin"
else
  fail "the leak check passed vacuously because no pin ran first"
fi

# 4. With no inherited home there is nothing to leak into.
# shellcheck disable=SC2016
if env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA CLAUDE_DIR="$tmp/none" \
  /bin/bash -c '. "$1/lib/hermetic-env.sh"; fleet_home_pin "$2/a"; fleet_home_leaked "$2"' _ "$here" "$tmp"; then
  fail "an unresolved inherited home read as a leak"
else
  pass "an unresolved inherited home is never a leak"
fi

# 5. Sourcing clears every cleared variable and leaves the pinned ones; a
#    deferred source clears nothing.
# shellcheck disable=SC2016
decoys=$(/bin/bash -c '. "$1/lib/hermetic-env.sh"; for v in $hermetic_env_cleared $hermetic_env_pinned; do printf "%s=/decoy " "$v"; done' _ "$here")
# shellcheck disable=SC2086,SC2016
out=$(env $decoys /bin/bash -c '. "$1/lib/hermetic-env.sh"; for v in $hermetic_env_cleared; do eval "[ -z \"\${$v+set}\" ]" || printf "kept %s\n" "$v"; done; for v in $hermetic_env_pinned; do eval "[ -n \"\${$v+set}\" ]" || printf "cleared %s\n" "$v"; done' _ "$here")
if [ -z "$out" ]; then
  pass "sourcing clears every cleared variable and leaves the pinned ones"
else
  fail "sourcing got the list wrong: $out"
fi
# shellcheck disable=SC2086,SC2016
out=$(env $decoys /bin/bash -c '_hermetic_env_defer=1; . "$1/lib/hermetic-env.sh"; printf "%s" "${PLANWRIGHT_ROOT-unset}"' _ "$here")
if [ "$out" = /decoy ]; then
  pass "a deferred source clears nothing"
else
  fail "a deferred source cleared PLANWRIGHT_ROOT: '$out'"
fi
# shellcheck disable=SC2016
out=$(env PLANWRIGHT_ROOT=/decoy /bin/sh -c '. "$1/lib/hermetic-env.sh"; printf "%s" "${PLANWRIGHT_ROOT-unset}"' _ "$here")
if [ "$out" = unset ]; then
  pass "the library clears under POSIX sh too"
else
  fail "a POSIX sh source left PLANWRIGHT_ROOT='$out'"
fi

# 6. The names are the cleared and pinned lists, once each.
# shellcheck disable=SC2016
out=$(/bin/bash -c '. "$1/lib/hermetic-env.sh"; hermetic_env_names' _ "$here")
n=$(printf '%s\n' "$out" | grep -c .)
u=$(printf '%s\n' "$out" | sort -u | grep -c .)
case "$out" in
  *PLANWRIGHT_ROOT*PLANWRIGHT_FLEET_STATE_DIR*) ok_order=1 ;;
  *) ok_order=0 ;;
esac
if [ "$n" -gt 0 ] && [ "$n" -eq "$u" ] && [ "$ok_order" -eq 1 ]; then
  pass "hermetic_env_names prints each cleared and pinned variable once"
else
  fail "hermetic_env_names printed a wrong list: $out"
fi

# 7. The runner's sentinel arms: the override always, the other arms only when
#    set; a write under any arm is detected, and an untouched home is not.
# shellcheck disable=SC2016
out=$(env -u CLAUDE_DIR CLAUDE_PLUGIN_DATA=/real PLANWRIGHT_FLEET_STATE_DIR=/real \
  /bin/bash -c '. "$1/lib/hermetic-env.sh"; hermetic_env_sentinel "$2/s"; printf "%s|%s|%s" "$PLANWRIGHT_FLEET_STATE_DIR" "$CLAUDE_PLUGIN_DATA" "${CLAUDE_DIR-unset}"' _ "$here" "$tmp")
if [ "$out" = "$tmp/s/fleet|$tmp/s/plugin-data|unset" ]; then
  pass "the sentinel pins the override always and the other arms only when set"
else
  fail "the sentinel pinned the wrong arms: $out"
fi
# shellcheck disable=SC2016
out=$(env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
  /bin/bash -c '. "$1/lib/hermetic-env.sh"; hermetic_env_sentinel "$2/s0"; printf "%s" "$PLANWRIGHT_FLEET_STATE_DIR"' _ "$here" "$tmp")
if [ "$out" = "$tmp/s0/fleet" ]; then
  pass "the sentinel pins the override even when it was unset"
else
  fail "an unset override was not pinned: $out"
fi
for arm in fleet plugin-data claude; do
  mkdir -p "$tmp/w-$arm/$arm"
  # shellcheck disable=SC2016
  if /bin/bash -c '. "$1/lib/hermetic-env.sh"; hermetic_env_sentinel_written "$2"' _ "$here" "$tmp/w-$arm"; then
    :
  else
    fail "a write under the $arm arm went undetected"
  fi
done
mkdir -p "$tmp/w-none"
# shellcheck disable=SC2016
if /bin/bash -c '. "$1/lib/hermetic-env.sh"; hermetic_env_sentinel_written "$2"' _ "$here" "$tmp/w-none"; then
  fail "an untouched sentinel home read as written"
else
  pass "a write under any sentinel arm is detected and an untouched home is not"
fi

# 8. The access probe: a readable file is not denied, a missing one is, and an
#    unknown access kind is a usage error.
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
printf 'x\n' >"$tmp/readable"
if hermetic_access_denied r "$tmp/readable" || hermetic_access_denied w "$tmp/readable"; then
  fail "a readable, writable file read as denied"
else
  pass "a file the user can read and write is not denied"
fi
if hermetic_access_denied r "$tmp/absent"; then
  pass "a path the user cannot read is denied"
else
  fail "a missing path read as accessible"
fi
rc=0
hermetic_access_denied x "$tmp/readable" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "an unknown access kind is a usage error"
else
  fail "an unknown access kind returned $rc"
fi

# 9. dead_owner_pid names no process and sits above the host's pid_max.
# shellcheck source=tests/lib/dead-owner.sh
. "$here/lib/dead-owner.sh"
dp=$(dead_owner_pid) || fail "dead_owner_pid failed"
case "$dp" in
  '' | *[!0-9]*) fail "dead_owner_pid printed a non-number: '$dp'" ;;
  *)
    if kill -0 "$dp" 2>/dev/null; then
      fail "dead_owner_pid $dp names a live process"
    elif [ -r /proc/sys/kernel/pid_max ] && [ "$dp" -le "$(cat /proc/sys/kernel/pid_max)" ]; then
      fail "dead_owner_pid $dp is inside this host's pid range"
    else
      pass "dead_owner_pid prints a PID no process holds, above the host's range"
    fi
    ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "test-hermetic-env: $failures failure(s)" >&2
  exit 1
fi
echo "ok: test-hermetic-env"
