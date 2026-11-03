#!/bin/sh
# Tests for scripts/detached-run.sh — the portable detached-run recipe every
# full local suite run /execute-task makes goes through (test-throughput
# REQ-B1.10, D-8, D-22).
#
# Every run lands under a temporary parent directory. The detached command is
# a fixture shell snippet: it exits with a chosen code, holds until the test
# lets it go, or sends SIGHUP to a child and logs the child's status.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-detached-run.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
DR="$repo_root/scripts/detached-run.sh"
TAB=$(printf '\t')
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }

[ -x "$DR" ] || {
  echo "FAIL: scripts/detached-run.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-detached-run.XXXXXX")" && pwd -P)" || exit 1
pids="$tmp/pids"
: >"$pids"
cleanup() {
  while read -r _p; do kill "$_p" 2>/dev/null; done <"$pids"
  rm -rf "$tmp"
}
trap cleanup EXIT

# field <name> <file> — the value of a `<name><TAB><value>` line.
field() { sed -n "s/^$1$TAB//p" "$2" | head -n 1; }

# launch <label> <parent> <command...> — run `start`, leaving its stdout in
# $tmp/<label>.out, its stderr in $tmp/<label>.err and its status in
# launch_rc; a launched runner's pid is recorded for cleanup.
launch() {
  _l=$1
  _parent=$2
  shift 2
  "$DR" start --dir "$_parent" -- "$@" >"$tmp/$_l.out" 2>"$tmp/$_l.err"
  launch_rc=$?
  _pid=$(field pid "$tmp/$_l.out")
  [ -z "$_pid" ] || printf '%s\n' "$_pid" >>"$pids"
}

# status_is <run> <expected> — succeeds when the status verb prints <expected>.
status_is() { [ "$("$DR" status "$1" 2>/dev/null)" = "$2" ]; }

# A command that holds until the file named by its first argument exists.
# shellcheck disable=SC2016 # $1 belongs to the detached shell
hold='while [ ! -e "$1" ]; do sleep 0.1; done'

# --- 1. a finished run reports its code, its log holds the output ----------
p1="$tmp/p1"
mkdir "$p1"
launch fin "$p1" sh -c 'echo fixture-output; exit 3'
run=$(field run "$tmp/fin.out")
if [ "$launch_rc" -eq 0 ] && [ -d "$run" ] && [ -f "$(field log "$tmp/fin.out")" ]; then
  ok "a launch returns 0 with an existing run dir and log"
else
  fail "a launch returns 0 with an existing run dir and log (rc=$launch_rc): $(cat "$tmp/fin.out" "$tmp/fin.err")"
fi
if poll_until --what 'finished 3' status_is "$run" 'finished 3'; then
  ok "status reports finished with the command's code"
else
  fail "status reports finished with the command's code (got '$("$DR" status "$run")')"
fi
if grep -qx fixture-output "$run/log" 2>/dev/null; then
  ok "the log carries the command's output"
else
  fail "the log carries the command's output"
fi

# --- 2. a held run reports running, then finished 0 ------------------------
gate="$tmp/release"
launch held "$p1" sh -c "$hold" held "$gate"
held_run=$(field run "$tmp/held.out")
if [ "$launch_rc" -eq 0 ] && status_is "$held_run" running; then
  ok "status reports running while the command runs"
else
  fail "status reports running while the command runs (rc=$launch_rc, got '$("$DR" status "$held_run")')"
fi
: >"$gate"
if poll_until --what 'finished 0' status_is "$held_run" 'finished 0'; then
  ok "a released run reports finished 0"
else
  fail "a released run reports finished 0 (got '$("$DR" status "$held_run")')"
fi

# --- 3. an earlier run's log survives a new launch -------------------------
launch again "$p1" sh -c 'echo second-run'
again_run=$(field run "$tmp/again.out")
poll_until --what 'second run finished' status_is "$again_run" 'finished 0' || :
if [ "$again_run" != "$run" ] && grep -qx fixture-output "$run/log" 2>/dev/null; then
  ok "a new launch takes a fresh run dir and leaves the earlier log intact"
else
  fail "a new launch takes a fresh run dir and leaves the earlier log intact ($run vs $again_run)"
fi

# --- 4. a runner that cannot start is a failed launch, never a success -----
p4="$tmp/p4"
mkdir "$p4"
PLANWRIGHT_DETACHED_RUN_SH="$tmp/no-such-shell" launch dead "$p4" sh -c 'exit 0'
if [ "$launch_rc" -ne 0 ] && grep -q 'never started' "$tmp/dead.err"; then
  ok "a launch whose runner cannot start reports failure"
else
  fail "a launch whose runner cannot start reports failure (rc=$launch_rc): $(cat "$tmp/dead.out" "$tmp/dead.err")"
fi
dead_run=$(find "$p4" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -n "$dead_run" ] && status_is "$dead_run" never-started; then
  ok "status reports never-started for that run"
else
  fail "status reports never-started for that run (dir '$dead_run', got '$("$DR" status "$dead_run" 2>&1)')"
fi

# --- 5. the suite sees SIGHUP at its default disposition -------------------
# shellcheck disable=SC2016 # $$ and $? belong to the detached shells
launch hup "$p1" sh -c 'sh -c "kill -HUP \$\$; exit 0"; echo "child=$?"'
hup_run=$(field run "$tmp/hup.out")
poll_until --what 'SIGHUP run finished' status_is "$hup_run" 'finished 0' || :
if grep -qx 'child=129' "$hup_run/log" 2>/dev/null; then
  ok "a child sent SIGHUP under the helper exits 129"
else
  fail "a child sent SIGHUP under the helper exits 129 (log: $(cat "$hup_run/log" 2>/dev/null))"
fi

# SIGINT too: a background job started without job control would have it
# ignored.
if command -v bash >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # $$ and $? belong to the detached shells
  launch int "$p1" sh -c 'sh -c "kill -INT \$\$; exit 0"; echo "child=$?"'
  int_run=$(field run "$tmp/int.out")
  poll_until --what 'SIGINT run finished' status_is "$int_run" 'finished 0' || :
  if grep -qx 'child=130' "$int_run/log" 2>/dev/null; then
    ok "a child sent SIGINT under the helper exits 130"
  else
    fail "a child sent SIGINT under the helper exits 130 (log: $(cat "$int_run/log" 2>/dev/null))"
  fi
fi

# The runner itself catches SIGHUP, so a hangup never ends the run.
gate2="$tmp/release2"
launch survive "$p1" sh -c "$hold; echo after-hup" held "$gate2"
survive_run=$(field run "$tmp/survive.out")
kill -HUP "$(field pid "$tmp/survive.out")" 2>/dev/null
: >"$gate2"
if poll_until --what 'run survives SIGHUP' status_is "$survive_run" 'finished 0' \
  && grep -qx after-hup "$survive_run/log"; then
  ok "a SIGHUP to the runner does not end the run"
else
  fail "a SIGHUP to the runner does not end the run (got '$("$DR" status "$survive_run")')"
fi

# A runner killed outright leaves no exit status: died, not running.
gate3="$tmp/release3"
launch killed "$p1" sh -c "$hold" held "$gate3"
killed_run=$(field run "$tmp/killed.out")
killed_pid=$(field pid "$tmp/killed.out")
kill -KILL "$killed_pid" 2>/dev/null
poll_until --what 'killed runner gone' pid_gone "$killed_pid" || :
: >"$gate3"
if status_is "$killed_run" died; then
  ok "status reports died for a runner killed outright"
else
  fail "status reports died for a runner killed outright (got '$("$DR" status "$killed_run")')"
fi

# --- 6. PATH without setsid and nohup, and without bash ------------------
# path_without <dir> <name...> — fill <dir> with links to every command on
# PATH except the named ones, the first of each name winning as a lookup
# would.
path_without() {
  _pw_dir=$1
  shift
  mkdir -p "$_pw_dir" || return 1
  _pw_ifs=$IFS
  IFS=:
  for _pw_d in $PATH; do
    IFS=$_pw_ifs
    [ -d "$_pw_d" ] || continue
    for _pw_f in "$_pw_d"/*; do
      _pw_n=${_pw_f##*/}
      _pw_skip=''
      for _pw_x in "$@"; do
        [ "$_pw_n" = "$_pw_x" ] && _pw_skip=1
      done
      [ -z "$_pw_skip" ] && [ -x "$_pw_f" ] && [ ! -e "$_pw_dir/$_pw_n" ] \
        && ln -s "$_pw_f" "$_pw_dir/$_pw_n"
    done
  done
  IFS=$_pw_ifs
}

path_without "$tmp/bin" setsid nohup
PATH="$tmp/bin" launch bare "$p1" sh -c 'exit 0'
bare_run=$(field run "$tmp/bare.out")
if [ "$launch_rc" -eq 0 ] && poll_until --what 'bare-PATH run finished' status_is "$bare_run" 'finished 0'; then
  ok "the helper launches with neither setsid nor nohup on PATH"
else
  fail "the helper launches with neither setsid nor nohup on PATH (rc=$launch_rc): $(cat "$tmp/bare.err")"
fi

# With no bash the launch still works, warning that SIGINT starts ignored.
path_without "$tmp/nobash" setsid nohup bash
PATH="$tmp/nobash" launch nobash "$p1" sh -c 'exit 0'
nobash_run=$(field run "$tmp/nobash.out")
if [ "$launch_rc" -eq 0 ] && grep -q 'no bash on PATH' "$tmp/nobash.err" \
  && poll_until --what 'no-bash run finished' status_is "$nobash_run" 'finished 0'; then
  ok "with no bash on PATH the helper still launches and warns"
else
  fail "with no bash on PATH the helper still launches and warns (rc=$launch_rc): $(cat "$tmp/nobash.err")"
fi

# --- 7. usage errors --------------------------------------------------------
# usage_rc <status> <message> — passes when <status> is the usage exit, 2.
usage_rc() {
  if [ "$1" -eq 2 ]; then ok "$2"; else fail "$2 (exit $1)"; fi
}
"$DR" >/dev/null 2>&1
usage_rc $? "no verb is a usage error"
"$DR" start --dir "$p1" >/dev/null 2>&1
usage_rc $? "start without a command is a usage error"
"$DR" status "$tmp/not-a-run" >/dev/null 2>&1
usage_rc $? "status on a non-run dir is a usage error"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all detached-run tests passed"
