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
#   f3: the reap escalates to SIGKILL for a process that ignores SIGTERM, a
#       pathless descendant included once its parent's death reparents it.
#   f4: an unusable process table fails the guard instead of passing it.
#   f5: only the sourcing shell counts as the owner, not a subshell of it.
#   f6: a continuation line, a non-numeric pid, a short line, or a control byte
#       in one process's argv does not void an otherwise readable table.
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

# spawn <path> <script> — start `sh -c <script>` with <path> as its $0, outside
# this shell's job table (no kill report in the log), and wait until it has
# written its own pid to <path>.pid, which every script below does once its
# traps are in place. Called in a substitution, so the caller fails on its
# status: a `fail` here would only leave the subshell.
spawn() {
  (sh -c "$2" "$1" >/dev/null 2>&1 &)
  poll_until --what "$1 to write its pid" -- test -s "$1.pid" || return 1
  cat "$1.pid"
}

# matched <needle> <pid> — the pid is among the needle's matched rows.
matched() {
  fixture_procs "$1" | awk -v p="$2" '$1 == p { f = 1 } END { exit !f }'
}

# f1. The temporary, home, and parent directories come from the environment, so
# each is tried only when no `fixture.*` component makes it a legitimate needle.
mkdir -p "$tmp/sub"
for bad in / "${TMPDIR:-/tmp}/" "$HOME/" "$tmp" "$tmp/missing/" "${tmp%/*}/" ''; do
  case $bad in
    "$tmp" | "$tmp"/*) ;;
    */fixture.*) continue ;;
  esac
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
bystander=$(spawn "$other/bystander" 'echo $$ >"$0.pid"; sleep 300') || fail "f1: the bystander never started"
fixture_reap / 2>/dev/null && fail "f1: fixture_reap reported success on a refused needle"
kill -0 "$bystander" 2>/dev/null || fail "f1: a refused reap still signalled a process"
echo "ok: f1 a needle outside a scratch directory is refused and nothing is signalled"

# f2
holder=$(spawn "$tmp/holder" 'echo $$ >"$0.pid"; sleep 300; :') || fail "f2: the holder never started"
poll_until --what 'the holder to fork its child' -- pgrep -P "$holder" sleep || fail "f2: the holder never forked its child"
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
printf '%s\n' 'trap "" TERM; echo $$ >"$KID"; while :; do sleep 0.1; done' >"$other/kid.sh"
parent=$(spawn "$tmp/parent" "echo \$\$ >\"\$0.pid\"; KID=\"\$0.kid\" sh '$other/kid.sh'; :") \
  || fail "f3: the parent never started"
poll_until --what 'the pathless child to start' -- test -s "$tmp/parent.kid" || fail "f3: the pathless child never started"
kid=$(cat "$tmp/parent.kid")
matched "$tmp/" "$kid" || fail "f3: the pathless child was not matched through its parent"
fixture_reap "$tmp/" || fail "f3: the reap left survivors"
kill -0 "$kid" 2>/dev/null && fail "f3: a TERM-ignoring child outlived the reap once its parent died"
kill -0 "$parent" 2>/dev/null && fail "f3: the parent outlived the reap"
echo "ok: f3 a process ignoring SIGTERM is killed, a reparented descendant included"

# f4
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "PID PPID COMMAND"\n' >"$tmp/bin/ps"
chmod +x "$tmp/bin/ps"
PATH="$tmp/bin:$PATH" fixture_none "$tmp/" 2>/dev/null \
  && fail "f4: fixture_none passed on a table with no pid rows"
PATH="$tmp/bin:$PATH" fixture_procs "$tmp/" >/dev/null 2>&1
[ $? = 2 ] || fail "f4: fixture_procs did not refuse an unusable table"
printf '#!/bin/sh\n:\n' >"$tmp/bin/ps"
PATH="$tmp/bin:$PATH" fixture_procs "$tmp/" >/dev/null 2>&1
[ $? = 2 ] || fail "f4: fixture_procs did not refuse an empty table"
# A short line or a header with no numeric pid and ppid pair is no table either.
printf '#!/bin/sh\nprintf "%%s\\n" "PID PPID COMMAND" "abc def ghi" "42"\n' >"$tmp/bin/ps"
PATH="$tmp/bin:$PATH" fixture_procs "$tmp/" >/dev/null 2>&1
[ $? = 2 ] || fail "f4: fixture_procs did not refuse a table of non-row lines"
echo "ok: f4 an unusable process table fails the guard"

# f5
fixture_is_owner || fail "f5: the sourcing shell is not recognised as the owner"
(fixture_is_owner) && fail "f5: a subshell was taken for the owner"
echo "ok: f5 only the sourcing shell owns the teardown"

# f6: a continuation line, a non-numeric pid, a short line, or a control byte in
# one process's argv must not void an otherwise readable table, and a match on a
# continuation still counts. The pids are past pid_max, so none is a live process
# or the suite's own.
printf '%s\n' \
  'a line before the first row' \
  ' 9000100     1 sh -c job '"$tmp"'/a' \
  'a continuation that names nothing' \
  ' 9000101  9000100 sleep 300' \
  'abc def ghi' \
  '9000103' \
  ' 9000102     1 sh -c job' \
  "$tmp/b is on a continuation line" \
  "$(printf '\001\r') 9000104     1 sh -c ctl $tmp/c" \
  ' 9000105     1' \
  ' 9000106     1 sleep 1' >"$tmp/planted.table"
printf '#!/bin/sh\ncat "%s"\n' "$tmp/planted.table" >"$tmp/bin/ps"
planted_pids=$(PATH="$tmp/bin:$PATH" fixture_procs "$tmp/" 2>"$tmp/planted.err" | awk '{ printf "%s ", $1 }')
[ "$planted_pids" = "9000100 9000101 9000102 9000104 " ] \
  || fail "f6: the planted table matched '$planted_pids', want '9000100 9000101 9000102 9000104 ': $(cat "$tmp/planted.err")"
PATH="$tmp/bin:$PATH" fixture_none "$tmp/" 2>/dev/null && fail "f6: fixture_none passed on a planted live match"
printf '#!/bin/sh\necho " 9000106     1 sleep 1"\n' >"$tmp/bin/ps"
PATH="$tmp/bin:$PATH" fixture_none "$tmp/" || fail "f6: fixture_none failed on a readable table with no match"
echo "ok: f6 one malformed line does not void the process table"

echo "all fixture-procs tests passed"
