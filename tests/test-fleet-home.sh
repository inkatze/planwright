#!/bin/bash
# Tests for tests/lib/fleet-home.sh, the per-case fleet-home pin and the
# inherited-registry leak check the fleet suites use. The inherited home here
# is always a stand-in under this suite's own temp root.
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
    /bin/bash -c '. "$1/lib/fleet-home.sh"; shift; eval "$1"' _ "$here" "$2"
}

# 1. A pin points every arm of the chain under its directory.
# shellcheck disable=SC2016
out=$(run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; printf "%s|%s|%s\n" "$PLANWRIGHT_FLEET_STATE_DIR" "$CLAUDE_PLUGIN_DATA" "$CLAUDE_DIR"')
if [ "$out" = "$tmp/a/fleet|$tmp/a/plugin-data|$tmp/a/claude" ]; then
  pass "a pin points the override, plugin-data, and writer arms at its directory"
else
  fail "a pin left an arm unpinned: $out"
fi

# 2. The inherited registry is the one resolved before the first pin, and a
#    later pin never replaces it with the previous case's fixture.
out=$(run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_pin "'"$tmp"'/b"; fleet_home_inherited')
if [ "$out" = "$tmp/op/registry" ]; then
  pass "the inherited registry survives later pins"
else
  fail "the inherited registry moved to '$out'"
fi

# 3. A record naming the needle in the inherited registry is a leak; one that
#    does not name it, such as a concurrent real dispatch, is not.
mkdir -p "$tmp/op"
printf '1\treal-worker\tscope\t-\ttmux\t/elsewhere/wt\tprocess 1\n' >"$tmp/op/registry"
if run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_leaked "'"$tmp"'/suite-root"'; then
  fail "a registry without the needle read as a leak"
else
  pass "a record that does not name the suite's root is not a leak"
fi
printf '2\theadless-x\tx:3\t-\theadless-oneshot\t%s/suite-root/state-h1/3\tprocess 2\n' "$tmp" >>"$tmp/op/registry"
if run_case "$tmp/op" 'fleet_home_pin "'"$tmp"'/a"; fleet_home_leaked "'"$tmp"'/suite-root"'; then
  pass "a record naming the suite's root is a leak"
else
  fail "a record naming the suite's root was not detected"
fi

# 4. With no inherited home there is nothing to leak into.
# shellcheck disable=SC2016
if env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA CLAUDE_DIR="$tmp/none" \
  /bin/bash -c '. "$1/lib/fleet-home.sh"; fleet_home_pin "$2/a"; fleet_home_leaked "$2"' _ "$here" "$tmp"; then
  fail "an unresolved inherited home read as a leak"
else
  pass "an unresolved inherited home is never a leak"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-fleet-home: $failures failure(s)" >&2
  exit 1
fi
echo "ok: test-fleet-home"
