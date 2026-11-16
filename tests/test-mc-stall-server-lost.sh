#!/bin/bash
# Tests for scripts/mc-stall.sh's tmux-server-lost event: when the tmux
# server a program's sessions were launched on is replaced and every window
# recorded under it is gone, the pass raises one tmux-server-lost event naming
# those sessions instead of a window-gone death per session.
#
# The tmux server is a stub on PATH whose identity (`#{pid}.#{start_time}`)
# and window table are fixture files; no real tmux server is reached.
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-stall-lost.XXXXXX") || exit 1
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

sleep 600 &
live_pid=$!

# The tmux stub: the server runs while $TMUX_STUB/server holds its identity;
# window @N exists while N.name holds its name, its pane pid in N.pid and its
# pane text in N.pane.
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
[ -f "$TMUX_STUB/server" ] || { echo "no server running on /tmp/tmux-stub/default" >&2; exit 1; }
srv=$(cat "$TMUX_STUB/server")
# render <window number or empty> <format>: the format as the server prints it.
render() {
  rn='' rp=''
  [ -z "$1" ] || { rn=$(cat "$TMUX_STUB/$1.name"); rp=$(cat "$TMUX_STUB/$1.pid"); }
  printf '%s\n' "$2" | sed -e "s|#{pid}\.#{start_time}|$srv|g" -e "s|#{window_id}|@$1|g" \
    -e "s|#{window_name}|$rn|g" -e "s|#{pane_pid}|$rp|g" -e 's|#{session_name}|stub|g'
}
case $verb in
  ls) exit 0 ;;
  list-windows)
    for f in "$TMUX_STUB"/*.name; do
      [ -f "$f" ] || continue
      id=${f##*/}
      render "${id%.name}" "${fmt:-#{window_id}}"
    done
    exit 0
    ;;
  display-message)
    if [ -z "$w" ]; then
      render '' "$fmt"
      exit 0
    fi
    [ -f "$TMUX_STUB/$n.name" ] || { echo "can't find window: $w" >&2; exit 1; }
    render "$n" "$fmt"
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

cat >"$tmp/idle.pane" <<'EOF'
⏺ The change is committed on the branch.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF

reg="$fleet/mission-control/sessions"
mkdir -p "$reg"
# row <name> <kind> <window> <server identity | -> [<token>]: a launched tmux
# registry row as the launcher writes it, recording the window and the server
# it was opened on.
row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\t%s\npid\t1\nprogram\talpha\nowner\tmission-control:alpha\nkind\t%s\nscope\ts\nbackend\ttmux\nhandle\t%s\nserver\t%s\nprofile\tworker\ntier\t-\nbrief\t-\nlaunched\t0\n' \
    "$1" "${5:-t}" "$2" "$3" "$4" >"$reg/$1"
}
# window <n> <name>: the stub's window @n, alive, showing an idle pane.
window() {
  printf '%s\n' "$2" >"$tmp/tmux/$1.name"
  printf '%s\n' "$live_pid" >"$tmp/tmux/$1.pid"
  cp "$tmp/idle.pane" "$tmp/tmux/$1.pane"
}
server() { printf '%s\n' "$1" >"$tmp/tmux/server"; }
# reset: an empty registry and window table, so each case scans only its own
# sessions.
reset() {
  rm -f "$reg"/mc-* "$tmp/tmux"/*.name "$tmp/tmux"/*.pid "$tmp/tmux"/*.pane "$tmp/tmux/server"
}

stall() { mc_run mc-stall.sh "$@"; }
state_of() { printf '%s\n' "$OUT" | awk -F '\t' -v n="$1" '$1 == n { print $3; exit }'; }
reason_of() { printf '%s\n' "$OUT" | awk -F '\t' -v n="$1" '$1 == n { print $4; exit }'; }
events() { (mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null); }
count() { events | awk -F '\t' -v k="$1" -v s="${2:-}" '$3 == k && (s == "" || $4 == s) { n++ } END { print n + 0 }'; }
lost_text() { events | awk -F '\t' '$3 == "tmux-server-lost" { t = $5 } END { print t }'; }
dump() { printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "----- events -----" "$(events)" "------------------" >&2; }

# --- the server was replaced and every window is gone ------------------------

reset
row mc-alpha-mission-control-old mission-control @1 100.5000
row mc-alpha-mission-control-new mission-control @2 100.5000
row mc-alpha-worker-a worker @3 100.5000
# The new server reuses window id @1 for an unrelated window.
server 200.6000
window 1 zsh
stall scan --program alpha --now 1000
[ "$RC" = 0 ] && ok "a scan after the server was replaced succeeds" || {
  fail "the scan exited $RC"
  dump
}
[ "$(count tmux-server-lost)" = 1 ] && ok "a replaced server with every window gone raises one tmux-server-lost event" \
  || {
    fail "expected one tmux-server-lost event, got $(count tmux-server-lost)"
    dump
  }
text=$(lost_text)
for n in mc-alpha-mission-control-old mc-alpha-mission-control-new mc-alpha-worker-a; do
  case $text in
    *"$n"*) ok "the tmux-server-lost event names $n" ;;
    *) fail "the tmux-server-lost event does not name $n: $text" ;;
  esac
  [ "$(count stall-dead "$n")" = 0 ] && ok "no per-session stall-dead event for $n" \
    || fail "$n raised its own stall-dead event beside tmux-server-lost"
  [ "$(state_of "$n")" = dead ] && ok "$n reads dead" || {
    fail "$n reads '$(state_of "$n")', not dead"
    dump
  }
  case $(reason_of "$n") in
    *'tmux server'*) ok "$n's reason names the lost server" ;;
    *) fail "$n's reason does not name the lost server: $(reason_of "$n")" ;;
  esac
done
case $text in
  *relaunch*) ok "the tmux-server-lost event says to relaunch the sessions" ;;
  *) fail "the tmux-server-lost event does not say to relaunch: $text" ;;
esac
[ "$(events | awk -F '\t' '$3 == "tmux-server-lost" { print $4; exit }')" = tmux-server ] \
  && ok "the event's subject is the tmux server" || fail "unexpected tmux-server-lost subject"

stall scan --program alpha --now 1100
[ "$(count tmux-server-lost)" = 1 ] && ok "a second scan of the same loss raises no second event" \
  || fail "a held server loss raised $(count tmux-server-lost) events"
[ "$(count stall-dead)" = 0 ] && ok "a second scan raises no per-session death either" \
  || fail "a second scan raised $(count stall-dead) stall-dead events"

# classify alone sees the same loss and raises nothing more.
stall classify --program alpha --now 1200 mc-alpha-worker-a
[ "$RC" = 0 ] && [ "$(state_of mc-alpha-worker-a)" = dead ] && ok "classify reads a session of a lost server dead" \
  || {
    fail "classify after the loss: rc $RC"
    dump
  }
[ "$(count tmux-server-lost)" = 1 ] && [ "$(count stall-dead mc-alpha-worker-a)" = 0 ] \
  && ok "classify raises neither a second tmux-server-lost nor a stall-dead" \
  || fail "classify after the loss raised another event"

# --- the same server with one window gone ------------------------------------

reset
before_lost=$(count tmux-server-lost)
server 200.6000
row mc-alpha-worker-keep worker @4 200.6000
row mc-alpha-worker-gone worker @5 200.6000
window 4 mc-alpha-worker-keep
stall scan --program alpha --now 2000
[ "$(count stall-dead mc-alpha-worker-gone)" = 1 ] && ok "the same server with one window gone keeps the per-session death" \
  || {
    fail "expected a stall-dead for mc-alpha-worker-gone"
    dump
  }
case $(reason_of mc-alpha-worker-gone) in
  *'window @5 gone'*) ok "the death names the gone window" ;;
  *) fail "the death's reason: $(reason_of mc-alpha-worker-gone)" ;;
esac
[ "$(state_of mc-alpha-worker-keep)" = idle ] && ok "the live window on the same server reads idle" \
  || fail "mc-alpha-worker-keep reads '$(state_of mc-alpha-worker-keep)'"
[ "$(count tmux-server-lost)" = "$before_lost" ] && ok "an unchanged server raises no tmux-server-lost" \
  || fail "an unchanged server raised tmux-server-lost"

# Every window gone on an unchanged server is per-session deaths too.
reset
before_lost=$(count tmux-server-lost)
server 200.6000
row mc-alpha-worker-all1 worker @6 200.6000
row mc-alpha-worker-all2 worker @7 200.6000
stall scan --program alpha --now 2100
[ "$(count stall-dead mc-alpha-worker-all1)" = 1 ] && [ "$(count stall-dead mc-alpha-worker-all2)" = 1 ] \
  && [ "$(count tmux-server-lost)" = "$before_lost" ] \
  && ok "every window gone on an unchanged server reads as per-session deaths" \
  || {
    fail "every window gone on an unchanged server"
    dump
  }

# --- a new server with a re-created session --------------------------------

reset
before_lost=$(count tmux-server-lost)
server 300.7000
row mc-alpha-mission-control-relaunched mission-control @1 300.7000
row mc-alpha-worker-orphan worker @8 200.6000
window 1 mc-alpha-mission-control-relaunched
stall scan --program alpha --now 3000
[ "$(state_of mc-alpha-mission-control-relaunched)" = idle ] && ok "a session re-created on the new server reads idle" \
  || {
    fail "the re-created session reads '$(state_of mc-alpha-mission-control-relaunched)'"
    dump
  }
[ "$(count stall-dead mc-alpha-mission-control-relaunched)" = 0 ] && ok "the re-created session raises no death" \
  || fail "the re-created session raised a stall-dead"
if [ "$(count tmux-server-lost)" -gt "$before_lost" ]; then
  case $(lost_text) in
    *mc-alpha-mission-control-relaunched*) fail "tmux-server-lost names the live re-created session: $(lost_text)" ;;
    *) ok "tmux-server-lost leaves the live re-created session out" ;;
  esac
  case $(lost_text) in
    *mc-alpha-worker-orphan*) ok "tmux-server-lost names the session the old server took down" ;;
    *) fail "tmux-server-lost does not name mc-alpha-worker-orphan: $(lost_text)" ;;
  esac
else
  fail "the session left from the replaced server raised no tmux-server-lost"
  dump
fi
[ "$(count stall-dead mc-alpha-worker-orphan)" = 0 ] && ok "the old server's session raises no per-session death" \
  || fail "mc-alpha-worker-orphan raised a stall-dead beside tmux-server-lost"

# A window still carrying the name of a session the old server recorded: the
# loss is unproven, so every session keeps its own classification, and that
# session's pin (its id issued by an earlier server) reads it dead on its own.
reset
before_lost=$(count tmux-server-lost)
server 300.7000
row mc-alpha-worker-stays worker @2 200.6000
row mc-alpha-worker-went worker @9 200.6000
window 2 mc-alpha-worker-stays
stall scan --program alpha --now 3100
[ "$(count tmux-server-lost)" = "$before_lost" ] && ok "a window of the old server still present raises no tmux-server-lost" \
  || fail "tmux-server-lost was raised while a window of the old server is present"
[ "$(state_of mc-alpha-worker-stays)" = dead ] && [ "$(count stall-dead mc-alpha-worker-stays)" = 1 ] \
  && ok "the still-named window reads dead by its own pin, with its own stall-dead" \
  || {
    fail "mc-alpha-worker-stays reads '$(state_of mc-alpha-worker-stays)' with $(count stall-dead mc-alpha-worker-stays) stall-dead"
    dump
  }
[ "$(count stall-dead mc-alpha-worker-went)" = 1 ] && ok "the gone window beside it keeps its per-session death" \
  || {
    fail "mc-alpha-worker-went raised no stall-dead"
    dump
  }

# --- no identity to compare --------------------------------------------------

# A row recorded before launches kept the server identity is classified as
# before.
reset
before_lost=$(count tmux-server-lost)
server 300.7000
row mc-alpha-worker-legacy worker @10 -
stall scan --program alpha --now 4000
[ "$(count stall-dead mc-alpha-worker-legacy)" = 1 ] && [ "$(count tmux-server-lost)" = "$before_lost" ] \
  && ok "a row with no recorded server keeps the per-session death" \
  || {
    fail "a row with no recorded server"
    dump
  }

# A garbled recorded identity proves nothing either: no false server-lost.
reset
before_lost=$(count tmux-server-lost)
server 300.7000
row mc-alpha-worker-garbled worker @12 not-an-identity
stall scan --program alpha --now 4050
[ "$(count stall-dead mc-alpha-worker-garbled)" = 1 ] && [ "$(count tmux-server-lost)" = "$before_lost" ] \
  && ok "a row with a garbled recorded server keeps the per-session death and raises no tmux-server-lost" \
  || {
    fail "a row with a garbled recorded server"
    dump
  }

# An unreachable server proves nothing: unknown, never lost.
reset
before_lost=$(count tmux-server-lost)
row mc-alpha-worker-noserver worker @11 200.6000
stall scan --program alpha --now 4100
[ "$(state_of mc-alpha-worker-noserver)" = unknown ] && [ "$(count tmux-server-lost)" = "$before_lost" ] \
  && ok "an unreachable server reads unknown and raises no tmux-server-lost" \
  || {
    fail "an unreachable server"
    dump
  }

# --- the event class -------------------------------------------------------

[ "$(awk -F '\t' '$1 == "tmux-server-lost" { print $2 }' "$repo_root/config/mc-event-classes.tsv")" = failure ] \
  && ok "tmux-server-lost is an operator-facing failure in the class table" \
  || fail "config/mc-event-classes.tsv has no failure row for tmux-server-lost"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-stall server-lost tests passed"
