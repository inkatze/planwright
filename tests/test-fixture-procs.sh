#!/bin/bash
# Tests for tests/lib/fixture-procs.sh, the reap and no-leak guard the
# stream-json suites tear down with. A guard that cannot fail proves nothing,
# so each property is shown failing or refusing on purpose:
#   f1: a needle that is not a directory strictly inside the temporary
#       directory is refused, and the reap signals nothing on a refusal.
#   f2: a process naming the directory is matched with its descendants, which
#       name no path; an unrelated process is not.
#   f3: the reap escalates to SIGKILL for a process that ignores SIGTERM.
#   f4: an unusable process table fails the guard instead of passing it.
#   f5: only the sourcing shell counts as the owner, not a subshell of it.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fixture-procs.sh
. "$here/lib/fixture-procs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d) || fail "mktemp -d failed: no scratch directory to run in"
other=$(mktemp -d) || fail "mktemp -d failed: no second scratch directory"
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  fixture_reap "$tmp/"
  fixture_reap "$other/"
  rm -rf "$tmp" "$other"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# f1
for bad in / "${TMPDIR:-/tmp}/" "${TMPDIR:-/tmp}" "$HOME/" "$tmp" "$tmp/missing/" ''; do
  fixture_procs "$bad" >/dev/null 2>&1
  [ $? = 2 ] || fail "f1: fixture_procs accepted the needle '$bad'"
  fixture_none "$bad" 2>/dev/null && fail "f1: fixture_none passed on the refused needle '$bad'"
done
sh -c 'sleep 30; :' "$other/holder" &
wait_holder=$!
fixture_reap / 2>/dev/null && fail "f1: fixture_reap reported success on a refused needle"
kill -0 "$wait_holder" 2>/dev/null || fail "f1: a refused reap still signalled a process"
echo "ok: f1 a needle outside the temporary directory is refused and nothing is signalled"

# f2
sh -c 'sleep 30; :' "$tmp/holder" &
holder=$!
sleep 0.3
rows=$(fixture_procs "$tmp/") || fail "f2: fixture_procs failed on a readable table"
printf '%s\n' "$rows" | grep -q "^$holder " || fail "f2: the process naming the directory was not matched: $rows"
child=$(printf '%s\n' "$rows" | awk '$2 == "sleep" { print $1 }')
[ -n "$child" ] || fail "f2: its pathless child was not matched: $rows"
printf '%s\n' "$rows" | grep -q "^$wait_holder " && fail "f2: a process under another directory was matched"
fixture_none "$tmp/" && fail "f2: fixture_none passed with a live match"
fixture_reap "$tmp/" || fail "f2: the reap left survivors"
kill -0 "$child" 2>/dev/null && fail "f2: the pathless child outlived the reap"
fixture_none "$tmp/" || fail "f2: fixture_none failed after a clean reap"
kill -0 "$wait_holder" 2>/dev/null || fail "f2: the reap reached a process under another directory"
echo "ok: f2 a match brings its descendants and nothing else"

# f3
sh -c 'trap "" TERM; while :; do sleep 0.1; done' "$tmp/stubborn" &
stubborn=$!
sleep 0.3
fixture_reap "$tmp/" || fail "f3: the reap left survivors"
wait "$stubborn" 2>/dev/null
kill -0 "$stubborn" 2>/dev/null && fail "f3: a TERM-ignoring process outlived the reap"
echo "ok: f3 a process ignoring SIGTERM is killed"

# f4
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "PID PPID COMMAND"\n' >"$tmp/bin/ps"
chmod +x "$tmp/bin/ps"
PATH="$tmp/bin:$PATH" fixture_none "$tmp/" 2>/dev/null \
  && fail "f4: fixture_none passed on a table with no pid rows"
PATH="$tmp/bin:$PATH" fixture_procs "$tmp/" >/dev/null 2>&1
[ $? = 2 ] || fail "f4: fixture_procs did not refuse an unusable table"
echo "ok: f4 an unusable process table fails the guard"

# f5
fixture_is_owner || fail "f5: the sourcing shell is not recognised as the owner"
(fixture_is_owner) && fail "f5: a subshell was taken for the owner"
echo "ok: f5 only the sourcing shell owns the teardown"

echo "all fixture-procs tests passed"
