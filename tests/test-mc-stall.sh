#!/bin/bash
# Tests for scripts/mc-stall.sh — liveness and stall states for every session
# kind the launcher registers (mission-control REQ-D1.2, REQ-D1.3).
#
# Each state is produced from its own fixture: a registry row as the
# launcher writes it, the session's pid where the rung keeps it (the
# stream-json worker.pid, the tmux pane pid behind a tmux stub), and a
# captured pane. No fixture yields a state from elapsed time alone.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-stall.sh" ] || {
  echo "FAIL: scripts/mc-stall.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-stall.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
live_pid=''
cleanup() {
  [ -z "$live_pid" ] || kill "$live_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
reset_mc_fixture
mkdir -p "$repo/specs"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mc-home/alpha
mission_control_stall_window: 10m
EOF

# A live pid the fixtures can point at, and one that has exited.
sleep 600 &
live_pid=$!
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"

# The tmux stub: window @N exists while $TMUX_STUB/N.name holds its name;
# its pane pid is in N.pid and its pane text in N.pane.
mkdir -p "$tmp/bin" "$tmp/tmux"
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
verb=$1
shift
w='' fmt=''
while [ "$#" -gt 0 ]; do
  case $1 in
    -t) w=$2; shift 2 ;;
    -F | -p | -a) shift ;;
    *) fmt=$1; shift ;;
  esac
done
n=${w#@}
case $verb in
  ls) [ ! -e "$TMUX_STUB/down" ] ;;
  list-windows)
    for f in "$TMUX_STUB"/*.name; do
      [ -f "$f" ] || continue
      id=${f##*/}
      printf '@%s\t%s\n' "${id%.name}" "$(cat "$f")"
    done
    exit 0
    ;;
  display-message)
    [ -f "$TMUX_STUB/$n.name" ] || { echo "can't find window: $w" >&2; exit 1; }
    case $fmt in
      *window_name*) printf '%s\t%s\n' "$(cat "$TMUX_STUB/$n.name")" "$(cat "$TMUX_STUB/$n.pid")" ;;
      *) cat "$TMUX_STUB/$n.pid" ;;
    esac
    ;;
  capture-pane)
    [ -f "$TMUX_STUB/$n.name" ] || { echo "can't find window: $w" >&2; exit 1; }
    cat "$TMUX_STUB/$n.pane"
    ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
TMUX_STUB="$tmp/tmux"
export PATH TMUX_STUB

reg="$fleet/mission-control/sessions"
mkdir -p "$reg"
# row <name> <kind> <backend> <handle> [<state> [<token>]]: a registry row as
# the launcher writes it; a tmux row names its window after the session.
row() {
  printf 'format\t1\nname\t%s\nstate\t%s\ntoken\t%s\npid\t1\nprogram\talpha\nowner\tmission-control:alpha\nkind\t%s\nscope\ts\nbackend\t%s\nhandle\t%s\nprofile\tworker\ntier\t-\nbrief\t-\nlaunched\t0\n' \
    "$1" "${5:-launched}" "${6:-t}" "$2" "$3" "$4" >"$reg/$1"
  [ "$3" != tmux ] || printf '%s\n' "$1" >"$tmp/tmux/${4#@}.name"
}
# window <n> <pid> <pane file>: the stub's window @n's pane.
window() {
  printf '%s\n' "$2" >"$tmp/tmux/$1.pid"
  cp "$3" "$tmp/tmux/$1.pane"
}
# sj <name> <pid | - | none>: the stream-json rung's state directory for
# <name> with worker.pid holding <pid>, with no pidfile (-), or absent (none).
sj() {
  rm -rf "$fleet/streamjson/$1"
  [ "$2" = none ] && return 0
  mkdir -p "$fleet/streamjson/$1"
  [ "$2" = - ] || printf '%s\n' "$2" >"$fleet/streamjson/$1/worker.pid"
}

stall() { mc_run mc-stall.sh "$@"; }
state_of() { printf '%s\n' "$OUT" | awk -F '\t' -v n="$1" '$1 == n { print $3; exit }'; }
expect_state() { # expect_state <label> <name> <state>
  got=$(state_of "$2")
  if [ "$got" = "$3" ]; then
    ok "$1"
  else
    fail "$1: expected $3, got '${got}'"
    printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
  fi
}
# mc_env replaces the shell it runs in, so the listing runs in a subshell.
events() { (mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null); }
expect_event() { # expect_event <label> <kind> <subject>
  if events | awk -F '\t' -v k="$2" -v s="$3" '$3 == k && $4 == s { f = 1 } END { exit !f }'; then
    ok "$1"
  else
    fail "$1: no $2 event for $3"
    events >&2
  fi
}
event_count() { events | awk -F '\t' -v k="$1" -v s="$2" '$3 == k && $4 == s { n++ } END { print n + 0 }'; }

# --- pane fixtures --------------------------------------------------------

cat >"$tmp/idle.pane" <<'EOF'
⏺ The change is committed on the branch.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/question.pane" <<'EOF'
⏺ Two readings of the Done-when fit the code.
  Should I take the narrower one?

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/selector.pane" <<'EOF'
 Bash command

   git status

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for git status commands
   3. No, and tell Claude what to do differently (esc)
EOF
cat >"$tmp/paste.pane" <<'EOF'
⏺ Ready for the next step.

────────────────────────────────────────
❯ [Pasted text #1 +12 lines]
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/background.pane" <<'EOF'
⏺ Launched the lens agents in the background.

────────────────────────────────────────
❯
────────────────────────────────────────
  Waiting for 2 background agents… (ctrl+b to manage)
EOF
busy_pane() { # busy_pane <file> <seconds> <work line>
  cat >"$1" <<EOF
⏺ $3

✻ Thinking… ($2s · ↓ 1.2k tokens · esc to interrupt)

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
}

# --- liveness: the recorded pid and process state (REQ-D1.2) --------------

row mc-alpha-worker-dead worker stream-json mc-alpha-worker-dead
sj mc-alpha-worker-dead "$dead_pid"
stall classify --program alpha --now 1000 --pane "$tmp/idle.pane" mc-alpha-worker-dead
expect_rc "classify a session whose recorded pid has exited" 0
expect_state "a stable pane with a dead pid reads dead" mc-alpha-worker-dead dead
expect_event "the dead state emits an attention event" stall-dead mc-alpha-worker-dead

row mc-alpha-worker-ended worker stream-json mc-alpha-worker-ended
sj mc-alpha-worker-ended -
stall classify --program alpha --now 1000 mc-alpha-worker-ended
expect_state "a supervisor that removed its pidfiles reads dead" mc-alpha-worker-ended dead

busy_pane "$tmp/busy-dead.pane" 4 "Writing the fix."
row mc-alpha-ad-hoc-panedead ad-hoc tmux @8
window 8 "$dead_pid" "$tmp/busy-dead.pane"
stall classify --program alpha --now 1000 mc-alpha-ad-hoc-panedead
expect_state "a dead pane process reads dead whatever the pane shows" mc-alpha-ad-hoc-panedead dead

row mc-alpha-tower-gone tower tmux @9
window 9 "$live_pid" "$tmp/idle.pane"
rm -f "$tmp/tmux/9.name"
stall classify --program alpha --now 1000 mc-alpha-tower-gone
expect_state "a window gone from the server reads dead" mc-alpha-tower-gone dead
expect_out "the dead state names the window" "window @9 gone"

row mc-alpha-reviewer-down reviewer tmux @16
window 16 "$live_pid" "$tmp/idle.pane"
: >"$tmp/tmux/down"
stall classify --program alpha --now 1000 mc-alpha-reviewer-down
rm -f "$tmp/tmux/down"
expect_state "an unreachable tmux server reads unknown, never dead" mc-alpha-reviewer-down unknown

row mc-alpha-orchestrator-sup orchestrator stream-json mc-alpha-orchestrator-sup
sj mc-alpha-orchestrator-sup -
printf '%s\n' "$live_pid" >"$fleet/streamjson/mc-alpha-orchestrator-sup/supervisor.pid"
stall classify --program alpha --now 1000 mc-alpha-orchestrator-sup
expect_state "a live supervisor between workers reads live" mc-alpha-orchestrator-sup live

row mc-alpha-worker-reused worker tmux @10
window 10 "$live_pid" "$tmp/idle.pane"
printf 'someone-else\n' >"$tmp/tmux/10.name"
stall classify --program alpha --now 1000 mc-alpha-worker-reused
expect_state "a window id now naming another window reads unknown" mc-alpha-worker-reused unknown

row mc-alpha-reviewer-nopid reviewer stream-json mc-alpha-reviewer-nopid
sj mc-alpha-reviewer-nopid none
busy_pane "$tmp/b1.pane" 3 "Reading the diff."
busy_pane "$tmp/b2.pane" 9 "Reading the tests."
stall classify --program alpha --now 1000 --pane "$tmp/b1.pane" mc-alpha-reviewer-nopid
stall classify --program alpha --now 1030 --pane "$tmp/b2.pane" mc-alpha-reviewer-nopid
expect_state "a changing pane with no pid reads unknown" mc-alpha-reviewer-nopid unknown
expect_out "the unknown state names the changing pane" "pane-changing"
expect_event "the unknown state emits an attention event" stall-unknown mc-alpha-reviewer-nopid

row mc-alpha-tower-live tower stream-json mc-alpha-tower-live
sj mc-alpha-tower-live "$live_pid"
stall classify --program alpha --now 1000 mc-alpha-tower-live
stall classify --program alpha --now 999999 mc-alpha-tower-live
expect_state "a live pid with no pane and long silence reads live, never stalled" mc-alpha-tower-live live

# --- stall states, every kind (REQ-D1.3) -----------------------------------

row mc-alpha-orchestrator-sel orchestrator tmux @1
window 1 "$live_pid" "$tmp/selector.pane"
stall classify --program alpha --now 1000 mc-alpha-orchestrator-sel
expect_state "an open dialog reads open-selector" mc-alpha-orchestrator-sel open-selector
expect_event "open-selector emits an attention event" stall-open-selector mc-alpha-orchestrator-sel

row mc-alpha-ad-hoc-paste ad-hoc tmux @2
window 2 "$live_pid" "$tmp/paste.pane"
stall classify --program alpha --now 1000 mc-alpha-ad-hoc-paste
expect_state "a staged paste in the input box reads unsubmitted-prompt" mc-alpha-ad-hoc-paste unsubmitted-prompt
expect_event "unsubmitted-prompt emits an attention event" stall-unsubmitted-prompt mc-alpha-ad-hoc-paste

row mc-alpha-worker-bg worker tmux @3
window 3 "$live_pid" "$tmp/background.pane"
stall classify --program alpha --now 1000 mc-alpha-worker-bg
expect_state "a finished turn with background agents reads turn-ended-background" mc-alpha-worker-bg turn-ended-background
expect_event "turn-ended-background emits an attention event" stall-turn-ended-background mc-alpha-worker-bg

row mc-alpha-tower-q tower tmux @4
window 4 "$live_pid" "$tmp/question.pane"
stall classify --program alpha --now 1000 mc-alpha-tower-q
expect_state "an idle pane ending on a question reads idle-question" mc-alpha-tower-q idle-question
expect_event "idle-question emits an attention event" stall-idle-question mc-alpha-tower-q

row mc-alpha-reviewer-busy reviewer tmux @5
busy_pane "$tmp/busy-a.pane" 12 "Running the suite."
busy_pane "$tmp/busy-b.pane" 310 "Running the suite."
busy_pane "$tmp/busy-c.pane" 612 "Running the suite."
window 5 "$live_pid" "$tmp/busy-a.pane"
stall classify --program alpha --now 1000 mc-alpha-reviewer-busy
expect_state "a busy pane on first sight reads working" mc-alpha-reviewer-busy working
window 5 "$live_pid" "$tmp/busy-b.pane"
stall classify --program alpha --now 1300 mc-alpha-reviewer-busy
expect_state "a busy pane unchanged inside the stall window reads working" mc-alpha-reviewer-busy working
window 5 "$live_pid" "$tmp/busy-c.pane"
stall classify --program alpha --now 1600 mc-alpha-reviewer-busy
expect_state "a busy pane unchanged past the stall window reads busy-unchanged" mc-alpha-reviewer-busy busy-unchanged
expect_event "busy-unchanged emits an attention event" stall-busy-unchanged mc-alpha-reviewer-busy
stall classify --program alpha --now 1700 mc-alpha-reviewer-busy
n=$(event_count stall-busy-unchanged mc-alpha-reviewer-busy)
[ "$n" = 1 ] && ok "a state held across passes emits one event" || fail "a held state emitted $n events"

row mc-alpha-worker-moving worker tmux @6
busy_pane "$tmp/m1.pane" 5 "Editing the script."
busy_pane "$tmp/m2.pane" 900 "Editing the test."
window 6 "$live_pid" "$tmp/m1.pane"
stall classify --program alpha --now 1000 mc-alpha-worker-moving
window 6 "$live_pid" "$tmp/m2.pane"
stall classify --program alpha --now 5000 mc-alpha-worker-moving
expect_state "a busy pane whose work changed reads working however long it ran" mc-alpha-worker-moving working

# --- never from elapsed time alone ----------------------------------------

row mc-alpha-ad-hoc-idle ad-hoc tmux @7
window 7 "$live_pid" "$tmp/idle.pane"
stall classify --program alpha --now 1000 mc-alpha-ad-hoc-idle
stall classify --program alpha --now 99999 mc-alpha-ad-hoc-idle
expect_state "an idle pane unchanged for many windows reads idle, not stalled" mc-alpha-ad-hoc-idle idle
[ "$(event_count stall-busy-unchanged mc-alpha-ad-hoc-idle)" = 0 ] && ok "an unchanged idle pane emits no stall event" \
  || fail "an unchanged idle pane emitted a stall event"

# --- each state only on its own signal ---------------------------------------

spin_pane() { # spin_pane <file> <seconds>: a spinner line with no interrupt hint
  cat >"$1" <<EOF
⏺ Compiling the fixtures.

✻ Herding… ($2s)

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
}
spin_pane "$tmp/spin-a.pane" 3
spin_pane "$tmp/spin-b.pane" 700
row mc-alpha-ad-hoc-spin ad-hoc tmux @17
window 17 "$live_pid" "$tmp/spin-a.pane"
stall classify --program alpha --now 1000 mc-alpha-ad-hoc-spin
expect_state "a spinner word alone reads busy" mc-alpha-ad-hoc-spin working
window 17 "$live_pid" "$tmp/spin-b.pane"
stall classify --program alpha --now 1700 mc-alpha-ad-hoc-spin
expect_state "a ticking spinner over unchanged work reads busy-unchanged" mc-alpha-ad-hoc-spin busy-unchanged

cat >"$tmp/busy-bg.pane" <<'EOF'
⏺ Running the lens agents.

✻ Thinking… (40s · esc to interrupt)
  Waiting for 2 background agents… (ctrl+b to manage)
────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
row mc-alpha-worker-busybg worker tmux @11
window 11 "$live_pid" "$tmp/busy-bg.pane"
stall classify --program alpha --now 1000 mc-alpha-worker-busybg
expect_state "a main turn still running beside background agents reads working" mc-alpha-worker-busybg working

cat >"$tmp/busy-q.pane" <<'EOF'
⏺ Should I also update the docs?

✻ Thinking… (4s · esc to interrupt)

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
row mc-alpha-reviewer-busyq reviewer tmux @12
window 12 "$live_pid" "$tmp/busy-q.pane"
stall classify --program alpha --now 1000 mc-alpha-reviewer-busyq
expect_state "a question above a busy footer reads working, not idle-question" mc-alpha-reviewer-busyq working

cat >"$tmp/answered.pane" <<'EOF'
⏺ Should I push the branch?
⏺ Pushed; the PR is open as a draft.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
row mc-alpha-tower-answered tower tmux @13
window 13 "$live_pid" "$tmp/answered.pane"
stall classify --program alpha --now 1000 mc-alpha-tower-answered
expect_state "an earlier question followed by a statement reads idle" mc-alpha-tower-answered idle

cat >"$tmp/oneline-q.pane" <<'EOF'
⏺ Shall I push the branch?

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
row mc-alpha-ad-hoc-oneq ad-hoc tmux @14
window 14 "$live_pid" "$tmp/oneline-q.pane"
stall classify --program alpha --now 1000 mc-alpha-ad-hoc-oneq
expect_state "a one-line reply ending on a question reads idle-question" mc-alpha-ad-hoc-oneq idle-question

# --- a relaunch starts a fresh sample ------------------------------------------

row mc-alpha-worker-again worker stream-json mc-alpha-worker-again launched first
sj mc-alpha-worker-again "$dead_pid"
stall classify --program alpha --now 1000 mc-alpha-worker-again
row mc-alpha-worker-again worker stream-json mc-alpha-worker-again launched second
stall classify --program alpha --now 1100 mc-alpha-worker-again
[ "$(event_count stall-dead mc-alpha-worker-again)" = 2 ] && ok "a relaunched session that dies again raises its own event" \
  || fail "a relaunch under the same name inherited the old sample's state"

# --- scan: every registered session of the program -------------------------

row mc-alpha-worker-launching worker tmux @15 launching
window 15 "$live_pid" "$tmp/selector.pane"

stall scan --program alpha --now 2000
expect_rc "scan the program's sessions" 0
for n in mc-alpha-worker-dead mc-alpha-orchestrator-sel mc-alpha-ad-hoc-paste mc-alpha-worker-bg mc-alpha-tower-q mc-alpha-reviewer-busy mc-alpha-ad-hoc-idle mc-alpha-tower-live; do
  [ -n "$(state_of "$n")" ] && ok "scan classifies $n" || fail "scan left out $n"
done
expect_no_out "scan leaves a launch still in flight alone" "mc-alpha-worker-launching"
stall classify --program alpha --now 2000 mc-alpha-worker-launching
expect_rc "classify refuses a launch still in flight" 3
printf 'format\t1\nname\tmc-beta-worker-x\nstate\tlaunched\nprogram\tbeta\nkind\tworker\nbackend\ttmux\nhandle\t@9\n' >"$reg/mc-beta-worker-x"
stall scan --program alpha --now 2000
expect_no_out "scan leaves another program's sessions out" "mc-beta-worker-x"

# --- refusals ---------------------------------------------------------------

stall classify --program alpha --now 1000 mc-alpha-absent
expect_rc "an unregistered session is refused" 3
stall classify --program alpha --now 1000 'mc-../x'
expect_rc "a malformed session name is refused" 2
printf 'format\t9\nname\tmc-alpha-worker-fmt\n' >"$reg/mc-alpha-worker-fmt"
stall classify --program alpha --now 1000 mc-alpha-worker-fmt
expect_rc "a row of an unknown format is refused" 2
expect_err "the refusal names the format field" "format"
stall classify --program gamma --now 1000 mc-alpha-worker-dead
expect_rc "an unconfigured program is refused" 3
chmod 300 "$reg"
stall scan --program alpha --now 3000
chmod 700 "$reg"
expect_rc "an unreadable registry fails the scan rather than reading as empty" 1

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-stall tests passed"
