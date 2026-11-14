#!/bin/sh
# Tests for scripts/detached-run.sh — the portable detached-run recipe every
# full local suite run /execute-task makes goes through (test-throughput
# REQ-B1.10, D-8, D-22).
#
# Every run lands under a temporary parent directory. The detached command is
# a fixture shell snippet: it exits with a chosen code, holds until the test
# lets it go, or signals a child and logs the child's status.
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
# Each run leads its own process group, out of reach of a signal to this
# file's group, so cleanup signals every recorded group.
cleanup() {
  while read -r _p; do
    kill -s TERM -- "-$_p" 2>/dev/null
  done <"$pids"
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# field <name> <file> — the value of a `<name><TAB><value>` line.
field() { sed -n "s/^$1$TAB//p" "$2" | head -n 1; }

# launch [--env <VAR=value>] <label> <parent> <command...> — run `start`,
# leaving its stdout in $tmp/<label>.out, its stderr in $tmp/<label>.err and
# its status in launch_rc; a launched runner's pid is recorded for cleanup.
# The environment goes through env(1): bash 3.2 in POSIX mode keeps a prefix
# assignment to a function call after the call returns.
launch() {
  _env=''
  if [ "$1" = --env ]; then
    _env=$2
    shift 2
  fi
  _l=$1
  _parent=$2
  shift 2
  if [ -n "$_env" ]; then
    env "$_env" "$DR" start --dir "$_parent" -- "$@" >"$tmp/$_l.out" 2>"$tmp/$_l.err"
  else
    "$DR" start --dir "$_parent" -- "$@" >"$tmp/$_l.out" 2>"$tmp/$_l.err"
  fi
  launch_rc=$?
  _pid=$(field pid "$tmp/$_l.out")
  [ -z "$_pid" ] || printf '%s\n' "$_pid" >>"$pids"
}

# status_is <run> <expected> — succeeds when the status verb prints <expected>.
status_is() { [ "$("$DR" status "$1" 2>/dev/null)" = "$2" ]; }

# A command that holds until the file named by its first argument exists, or
# its directory is gone (cleanup).
# shellcheck disable=SC2016 # $1 belongs to the detached shell
hold='while [ ! -e "$1" ] && [ -d "${1%/*}" ]; do sleep 0.1; done'

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

# --- 2. a held run reports running, however its dir is spelled -------------
gate="$tmp/release"
launch held "$p1" sh -c "$hold" held "$gate"
held_run=$(field run "$tmp/held.out")
if [ "$launch_rc" -eq 0 ] && status_is "$held_run" running; then
  ok "status reports running while the command runs"
else
  fail "status reports running while the command runs (rc=$launch_rc, got '$("$DR" status "$held_run")')"
fi
if status_is "$held_run/" running && (cd "$p1" && status_is "./${held_run##*/}" running); then
  ok "status reports running for a trailing-slash or relative run dir"
else
  fail "status reports running for a trailing-slash or relative run dir"
fi
if [ "$(COLUMNS=40 "$DR" status "$held_run" 2>/dev/null)" = running ]; then
  ok "status reports running when ps would truncate to a narrow width"
else
  fail "status reports running when ps would truncate to a narrow width"
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
launch --env PLANWRIGHT_DETACHED_RUN_SH="$tmp/no-such-shell" dead "$p4" sh -c 'exit 0'
if [ "$launch_rc" -eq 4 ] && grep -q 'never started' "$tmp/dead.err" \
  && grep -q '^detached-run: runner: ' "$tmp/dead.err"; then
  ok "a launch whose runner cannot start reports failure, with the runner's reason"
else
  fail "a launch whose runner cannot start reports failure (rc=$launch_rc): $(cat "$tmp/dead.out" "$tmp/dead.err")"
fi
dead_run=$(find "$p4" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -n "$dead_run" ] && status_is "$dead_run" never-started; then
  ok "status reports never-started for that run"
else
  fail "status reports never-started for that run (dir '$dead_run', got '$("$DR" status "$dead_run" 2>&1)')"
fi

# slow_shell <path> <child-pid-file> — a runner shell that never signals its
# start: it leaves a child behind, records the child's pid, and sleeps.
slow_shell() {
  printf '#!/bin/sh\nsleep 600 &\necho $! >"%s"\nexec sleep 600\n' "$2" >"$1"
  chmod +x "$1"
}

# A runner alive but silent past the start wait is stopped with its whole
# process group, and the launch fails.
slow="$tmp/slow-shell"
slow_shell "$slow" "$tmp/slow-child"
p4b="$tmp/p4b"
mkdir "$p4b"
env PLANWRIGHT_DETACHED_RUN_SH="$slow" PLANWRIGHT_DETACHED_RUN_START_WAIT=3 \
  "$DR" start --dir "$p4b" -- true >"$tmp/slow.out" 2>"$tmp/slow.err"
slow_rc=$?
slow_run=$(sed -n 's/.*; run \(.*\)$/\1/p' "$tmp/slow.err" | head -n 1)
slow_pid=$(cat "$slow_run/pid" 2>/dev/null)
[ -z "$slow_pid" ] || printf '%s\n' "$slow_pid" >>"$pids"
slow_child=$(cat "$tmp/slow-child" 2>/dev/null)
if [ "$slow_rc" -eq 4 ] && grep -q 'no signal in 3s' "$tmp/slow.err" && [ -n "$slow_child" ] \
  && poll_until --what 'silent runner and its child stopped' pid_gone "$slow_pid" "$slow_child"; then
  ok "a runner silent past the start wait is stopped with its child and the launch fails"
else
  fail "a runner silent past the start wait is stopped and the launch fails (rc=$slow_rc): $(cat "$tmp/slow.err")"
fi

# A start stopped while it waits stops the run, and fails.
slow2="$tmp/slow-shell2"
slow_shell "$slow2" "$tmp/slow2-child"
p4c="$tmp/p4c"
mkdir "$p4c"
env PLANWRIGHT_DETACHED_RUN_SH="$slow2" PLANWRIGHT_DETACHED_RUN_START_WAIT=60 \
  "$DR" start --dir "$p4c" -- true >"$tmp/intr.out" 2>"$tmp/intr.err" &
intr_launcher=$!
# pid_recorded — the waiting start has recorded its runner's pid and the
# runner its child's.
pid_recorded() {
  _pr=$(find "$p4c" -mindepth 2 -maxdepth 2 -name pid | head -n 1)
  [ -s "$_pr" ] && [ -s "$tmp/slow2-child" ]
}
poll_until --what 'interrupted start recorded its runner' pid_recorded || :
intr_pid=$(cat "$(find "$p4c" -mindepth 2 -maxdepth 2 -name pid | head -n 1)" 2>/dev/null)
intr_child=$(cat "$tmp/slow2-child" 2>/dev/null)
[ -z "$intr_pid" ] || printf '%s\n' "$intr_pid" >>"$pids"
kill -s TERM "$intr_launcher" 2>/dev/null
wait "$intr_launcher"
intr_rc=$?
if [ "$intr_rc" -eq 4 ] && grep -q 'start interrupted' "$tmp/intr.err" && [ -n "$intr_child" ] \
  && poll_until --what 'interrupted run stopped' pid_gone "$intr_pid" "$intr_child"; then
  ok "a start stopped while it waits stops the run and fails"
else
  fail "a start stopped while it waits stops the run and fails (rc=$intr_rc): $(cat "$tmp/intr.err")"
fi

# A start wait that is not a plain count of seconds in range is a usage error
# that launches nothing.
p4d="$tmp/p4d"
mkdir "$p4d"
for w in 08 0 abc 100000 99999999999999999999; do
  env PLANWRIGHT_DETACHED_RUN_START_WAIT="$w" "$DR" start --dir "$p4d" -- true >/dev/null 2>"$tmp/wait.err"
  wait_rc=$?
  if [ "$wait_rc" -eq 2 ] && [ -z "$(find "$p4d" -mindepth 1)" ] \
    && grep -q 'START_WAIT must be 1 to 99999' "$tmp/wait.err"; then
    ok "a start wait of '$w' is a usage error that launches nothing"
  else
    fail "a start wait of '$w' is a usage error that launches nothing (rc=$wait_rc)"
  fi
done

launch --env PLANWRIGHT_DETACHED_RUN_START_WAIT=99999 maxwait "$p1" true
if [ "$launch_rc" -eq 0 ]; then
  ok "a start wait of 99999 is accepted"
else
  fail "a start wait of 99999 is accepted (rc=$launch_rc): $(cat "$tmp/maxwait.err")"
fi

# A runner that signals its start without opening its log is stopped, with
# its child, and the launch fails.
nolog="$tmp/nolog-shell"
# shellcheck disable=SC2016 # $3 and $! belong to the fixture runner
printf '#!/bin/sh\nsleep 600 &\necho $! >"%s"\n: >"$3/started"\nexec sleep 600\n' "$tmp/nolog-child" >"$nolog"
chmod +x "$nolog"
p4e="$tmp/p4e"
mkdir "$p4e"
env PLANWRIGHT_DETACHED_RUN_SH="$nolog" "$DR" start --dir "$p4e" -- true >"$tmp/nolog.out" 2>"$tmp/nolog.err"
nolog_rc=$?
nolog_pid=$(cat "$(find "$p4e" -mindepth 2 -maxdepth 2 -name pid | head -n 1)" 2>/dev/null)
[ -z "$nolog_pid" ] || printf '%s\n' "$nolog_pid" >>"$pids"
# nolog_child_gone — the child, once its pid is on record, is gone.
nolog_child_gone() {
  [ -s "$tmp/nolog-child" ] && pid_gone "$(cat "$tmp/nolog-child")"
}
if [ "$nolog_rc" -eq 4 ] && grep -q 'log is missing; stopped it' "$tmp/nolog.err" \
  && poll_until --what 'log-less runner stopped' pid_gone "$nolog_pid" \
  && poll_until --what 'log-less runner child stopped' nolog_child_gone; then
  ok "a runner that starts without its log is stopped and the launch fails"
else
  fail "a runner that starts without its log is stopped and the launch fails (rc=$nolog_rc): $(cat "$tmp/nolog.err")"
fi

# run-inner never writes into a dir that is not a fresh run: one never
# launched, or one whose runner already started.
used="$tmp/used-run"
mkdir "$used"
: >"$used/launched"
: >"$used/started"
for d in "$p4d" "$used"; do
  "$DR" run-inner "$d" -- true >/dev/null 2>"$tmp/inner.err"
  inner_rc=$?
  if [ "$inner_rc" -eq 2 ] && grep -q 'not a fresh run directory' "$tmp/inner.err" && [ ! -e "$d/log" ]; then
    ok "run-inner refuses ${d##*/}, not a fresh run"
  else
    fail "run-inner refuses ${d##*/}, not a fresh run (rc=$inner_rc)"
  fi
done

# A BASH_ENV that prints, even with no newline, never corrupts the recorded
# pid, and still reaches the run.
benv="$tmp/bash-env"
echo 'printf junk' >"$benv"
# shellcheck disable=SC2016 # $BASH_ENV belongs to the detached shell
launch --env BASH_ENV="$benv" benv "$p1" sh -c 'echo "be=$BASH_ENV"'
benv_run=$(field run "$tmp/benv.out")
if [ "$launch_rc" -eq 0 ] && poll_until --what 'BASH_ENV run finished' status_is "$benv_run" 'finished 0' \
  && grep -qx "be=$benv" "$benv_run/log"; then
  ok "a printing BASH_ENV does not break the launch and reaches the run"
else
  fail "a printing BASH_ENV does not break the launch and reaches the run (rc=$launch_rc): $(cat "$tmp/benv.err")"
fi

"$DR" run-inner "$used" >/dev/null 2>"$tmp/inner.err"
inner_rc=$?
if [ "$inner_rc" -eq 2 ] && grep -q 'expected <run-dir> -- <command>' "$tmp/inner.err"; then
  ok "run-inner without -- and a command is refused"
else
  fail "run-inner without -- and a command is refused (rc=$inner_rc)"
fi

# --- 5. the suite sees default signal dispositions and the caller's locale -
# The caller's descriptors past stderr never reach the run, so no pipe the
# caller waits on stays open; dash cannot open one past 9, so bash does.
if command -v bash >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # expanded by the inner bash
  bash -c 'exec 5>"$1/fd5" 12>"$1/fd12"; exec "$2" start --dir "$3" -- sh -c "ls /dev/fd"' \
    fds "$tmp" "$DR" "$p1" >"$tmp/fds.out" 2>"$tmp/fds.err"
  fds_run=$(field run "$tmp/fds.out")
  [ -z "$(field pid "$tmp/fds.out")" ] || field pid "$tmp/fds.out" >>"$pids"
  poll_until --what 'fd run finished' status_is "$fds_run" 'finished 0' || :
  if [ -s "$fds_run/log" ] && ! grep -qx -e 5 -e 12 "$fds_run/log"; then
    ok "the caller's descriptors past stderr are closed in the run"
  else
    fail "the caller's descriptors past stderr are closed in the run (log: $(tr '\n' ' ' <"$fds_run/log" 2>/dev/null))"
  fi
fi

# shellcheck disable=SC2016 # $$ and $? belong to the detached shells
launch hup "$p1" sh -c 'sh -c "kill -HUP \$\$; exit 0"; echo "child=$?"'
hup_run=$(field run "$tmp/hup.out")
poll_until --what 'SIGHUP run finished' status_is "$hup_run" 'finished 0' || :
if grep -qx 'child=129' "$hup_run/log" 2>/dev/null; then
  ok "a child sent SIGHUP under the helper exits 129"
else
  fail "a child sent SIGHUP under the helper exits 129 (log: $(cat "$hup_run/log" 2>/dev/null))"
fi

# SIGINT and SIGQUIT too: a background job started without job control would
# have them ignored.
if command -v bash >/dev/null 2>&1; then
  # The wrapper traps INT: bash 3.2 (macOS sh) otherwise kills itself when its
  # foreground child dies of SIGINT, so the status line would never print. A
  # trap on a signal ignored at entry has no effect, so an ignored INT still
  # reaches the child and fails the test.
  # shellcheck disable=SC2016 # $$ and $? belong to the detached shells
  launch int "$p1" sh -c 'trap : INT; sh -c "kill -INT \$\$; exit 0"; echo "child=$?"'
  int_run=$(field run "$tmp/int.out")
  poll_until --what 'SIGINT run finished' status_is "$int_run" 'finished 0' || :
  if grep -qx 'child=130' "$int_run/log" 2>/dev/null; then
    ok "a child sent SIGINT under the helper exits 130"
  else
    fail "a child sent SIGINT under the helper exits 130 (log: $(cat "$int_run/log" 2>/dev/null))"
  fi
  # shellcheck disable=SC2016 # $$ and $? belong to the detached shells
  launch quit "$p1" sh -c 'sh -c "kill -QUIT \$\$; exit 0"; echo "child=$?"'
  quit_run=$(field run "$tmp/quit.out")
  poll_until --what 'SIGQUIT run finished' status_is "$quit_run" 'finished 0' || :
  if grep -qx 'child=131' "$quit_run/log" 2>/dev/null; then
    ok "a child sent SIGQUIT under the helper exits 131"
  else
    fail "a child sent SIGQUIT under the helper exits 131 (log: $(cat "$quit_run/log" 2>/dev/null))"
  fi
fi

# shellcheck disable=SC2016 # $LC_ALL belongs to the detached shell
launch --env LC_ALL=POSIX locale "$p1" sh -c 'echo "lc=$LC_ALL"'
locale_run=$(field run "$tmp/locale.out")
poll_until --what 'locale run finished' status_is "$locale_run" 'finished 0' || :
if grep -qx 'lc=POSIX' "$locale_run/log" 2>/dev/null; then
  ok "the command runs in the caller's locale"
else
  fail "the command runs in the caller's locale (log: $(cat "$locale_run/log" 2>/dev/null))"
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
kill -KILL "$(field pid "$tmp/killed.out")" 2>/dev/null
if poll_until --what 'killed runner reads died' status_is "$killed_run" died; then
  ok "status reports died for a runner killed outright"
else
  fail "status reports died for a runner killed outright (got '$("$DR" status "$killed_run")')"
fi
: >"$gate3"

# --- 6. PATH without setsid and nohup, and without bash ------------------
# path_of <dir> <name...> — a PATH directory holding only the named commands.
path_of() {
  _po_dir=$1
  shift
  mkdir -p "$_po_dir" || return 1
  for _po_n in "$@"; do
    _po_f=$(command -v "$_po_n") || _po_f=''
    case $_po_f in
      /*) ln -s "$_po_f" "$_po_dir/$_po_n" ;;
      *) fail "path_of: no '$_po_n' command on PATH" ;;
    esac
  done
}
needed='sh mktemp date cat sed head dirname basename ps sleep mv env'
# shellcheck disable=SC2086 # word-split on purpose
path_of "$tmp/bin" $needed bash
launch --env PATH="$tmp/bin" bare "$p1" sh -c 'exit 0'
bare_run=$(field run "$tmp/bare.out")
if [ "$launch_rc" -eq 0 ] && ! env PATH="$tmp/bin" sh -c 'command -v setsid || command -v nohup' >/dev/null \
  && poll_until --what 'bare-PATH run finished' status_is "$bare_run" 'finished 0'; then
  ok "the helper launches with neither setsid nor nohup on PATH"
else
  fail "the helper launches with neither setsid nor nohup on PATH (rc=$launch_rc): $(cat "$tmp/bare.err")"
fi

# With no bash the launch refuses with exit 4 and makes no run directory.
# shellcheck disable=SC2086 # word-split on purpose
path_of "$tmp/nobash" $needed
nobash_parent="$tmp/nobash-parent"
mkdir -p "$nobash_parent"
launch --env PATH="$tmp/nobash" nobash "$nobash_parent" sh -c 'exit 0'
if [ "$launch_rc" -eq 4 ] && grep -q 'no bash on PATH' "$tmp/nobash.err" \
  && [ ! -s "$tmp/nobash.out" ] && [ -z "$(ls -A "$nobash_parent")" ]; then
  ok "with no bash on PATH start refuses with exit 4 and makes no run"
else
  fail "with no bash on PATH start refuses with exit 4 and makes no run (rc=$launch_rc): $(cat "$tmp/nobash.err")"
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
"$DR" start --dir '' -- true >/dev/null 2>&1
usage_rc $? "start with an empty --dir is a usage error"
"$DR" status "$tmp/not-a-run" >/dev/null 2>&1
usage_rc $? "status on a non-run dir is a usage error"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all detached-run tests passed"
