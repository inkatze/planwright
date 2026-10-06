#!/bin/bash
# Tests for tests/lib/fixture-procs.sh, the reap and no-leak guard the
# stream-json suites tear down with. A guard that cannot fail proves nothing,
# so each property is shown failing or refusing on purpose:
#   f1: a needle with no fixture_scratch marker at or above it is refused, the
#       temporary directory and the home directory included, as is a marker
#       planted in a directory fixture_scratch did not make, and the reap
#       signals nothing on a refusal.
#   f2: a process naming the directory is matched with its descendants, which
#       name no path; a process under another scratch directory is not.
#   f3: the reap escalates to SIGKILL for a process that ignores SIGTERM.
#   f4: an unusable process table fails the guard instead of passing it.
#   f5: only the sourcing shell counts as the owner, not a subshell of it.
# shellcheck disable=SC2016 # the fixtures' scripts are literal sh source, expanded by the child
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

tmp=$(fixture_scratch) || fail "no scratch directory to run in"
other=''
cleanup() {
  trap '' INT TERM
  trap - EXIT
  fixture_is_owner || return 0
  fixture_reap "$tmp/"
  [ -n "$other" ] && fixture_reap "$other/"
  rm -rf "$tmp" ${other:+"$other"}
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
other=$(fixture_scratch) || fail "no second scratch directory"

# wait_until <timeout-tenths> <cmd...> — poll a condition.
wait_until() {
  wu_n=$1
  shift
  wu_i=0
  while [ "$wu_i" -lt "$wu_n" ]; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
    wu_i=$((wu_i + 1))
  done
  return 1
}

# spawn <path> <script> — start `sh -c <script>` with <path> as its $0, outside
# this shell's job table (no kill report in the log), and wait until it has
# written its own pid to <path>.pid, which every script below does once its
# traps are in place. Called in a substitution, so the caller fails on its
# status: a `fail` here would only leave the subshell.
spawn() {
  (sh -c "$2" "$1" >/dev/null 2>&1 &)
  wait_until 100 test -s "$1.pid" || return 1
  cat "$1.pid"
}

# matched <needle> <pid> — the pid is among the needle's matched rows.
matched() {
  fixture_procs "$1" | awk -v p="$2" '$1 == p { f = 1 } END { exit !f }'
}

# f1
mkdir -p "$tmp/sub"
for bad in / "${TMPDIR:-/tmp}/" "$HOME/" "$tmp" "$tmp/missing/" "${tmp%/*}/" ''; do
  fixture_procs "$bad" >/dev/null 2>&1
  [ $? = 2 ] || fail "f1: fixture_procs accepted the needle '$bad'"
  fixture_none "$bad" 2>/dev/null && fail "f1: fixture_none passed on the refused needle '$bad'"
done
fixture_procs "$tmp/sub/" >/dev/null || fail "f1: a directory under the scratch directory was refused"
planted=$(mktemp -d) || fail "no directory to plant a marker in"
: >"$planted/.fixture-procs"
ln -s "$tmp" "$planted/fixture.link"
fixture_procs "$planted/" >/dev/null 2>&1
planted_rc=$?
fixture_procs "$planted/fixture.link/" >/dev/null 2>&1
link_rc=$?
rm -rf "$planted"
[ "$planted_rc" = 2 ] || fail "f1: a marker planted outside a fixture_scratch directory was trusted"
[ "$link_rc" = 2 ] || fail "f1: a symlink named like a scratch directory was trusted"
bystander=$(spawn "$other/bystander" 'echo $$ >"$0.pid"; sleep 30') || fail "f1: the bystander never started"
fixture_reap / 2>/dev/null && fail "f1: fixture_reap reported success on a refused needle"
kill -0 "$bystander" 2>/dev/null || fail "f1: a refused reap still signalled a process"
echo "ok: f1 a needle outside a scratch directory is refused and nothing is signalled"

# f2
holder=$(spawn "$tmp/holder" 'echo $$ >"$0.pid"; sleep 30; :') || fail "f2: the holder never started"
wait_until 100 sh -c 'pgrep -P "$1" sleep' _ "$holder" || fail "f2: the holder never forked its child"
child=$(pgrep -P "$holder" sleep)
matched "$tmp/" "$holder" || fail "f2: the process naming the directory was not matched: $(fixture_report "$tmp/")"
matched "$tmp/" "$child" || fail "f2: its pathless child was not matched: $(fixture_report "$tmp/")"
matched "$tmp/" "$bystander" && fail "f2: a process under another scratch directory was matched"
fixture_none "$tmp/" && fail "f2: fixture_none passed with a live match"
fixture_reap "$tmp/" || fail "f2: the reap left survivors"
kill -0 "$child" 2>/dev/null && fail "f2: the pathless child outlived the reap"
fixture_none "$tmp/" || fail "f2: fixture_none failed after a clean reap"
kill -0 "$bystander" 2>/dev/null || fail "f2: the reap reached a process under another scratch directory"
echo "ok: f2 a match brings its descendants and nothing else"

# f3
stubborn=$(spawn "$tmp/stubborn" 'trap "" TERM; echo $$ >"$0.pid"; while :; do sleep 0.1; done') || fail "f3: the stubborn process never started"
matched "$tmp/" "$stubborn" || fail "f3: the TERM-ignoring process was not matched"
fixture_reap "$tmp/" || fail "f3: the reap left survivors"
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
