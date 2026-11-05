#!/bin/bash
# Tests for the stream-json fleet's version-independent sweep and its dead
# workers: what `fleet-streamjson.sh alarm-scan`, `pending` and the bare
# invocation do for a worker no current supervisor watches.
#
#   w1: no arguments, or an unknown verb, prints the usage and exits 2 at
#       once, even when a helper the verbs need would block.
#   w2: `pending` marks a positively dead worker's requests as dead, and a
#       worker with no death evidence is listed exactly as before.
#   w3: `alarm-scan` escalates an overdue request of a worker no tick
#       watches (a runtime directory built the way an older launcher left
#       it) and `--once` pushes it once across scans, while a plain scan
#       pushes on every call.
#   w4: `alarm-scan` never escalates a positively dead worker: its pending
#       receipts are closed undeliverable and its request row leaves the
#       decision queue, while a failure item under the same handle stays.
#   w5: two sessions sharing a checkout get distinct TMPDIRs (scratch
#       roots), and one's final close leaves the other's files intact, an
#       old-shape worktree-wide root included.
#
# Hermetic: every fleet home is case-local and built by hand (no worker is
# launched). Runs standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../scripts"
SJ="$S/fleet-streamjson.sh"
FA="$S/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
# Above every host's pid ceiling, so no process can hold it.
dead_pid=999999999

core_cfg="$tmp/core.yml"
pin_cfg="$tmp/pin.yml"
printf 'notification_channel: none\n' >"$core_cfg"
printf 'notification_channel: editor-toast\n' >"$pin_cfg"

# fenv <home> <script> <args...> — a hermetic run against <home>, with the
# notify seam pinned to editor-toast so every push is a line in
# <home>/attention/toasts.
fenv() {
  fe_home=$1
  fe_script=$2
  shift 2
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY \
    PLANWRIGHT_FLEET_STATE_DIR="$fe_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="$pin_cfg" \
    /bin/sh "$fe_script" "$@"
}

# mkreq <worker-dir> <id> <received-epoch> — one pending journal row and its
# envelope, in the shapes the supervisor writes.
mkreq() {
  mkdir -p "$1"
  printf '%s\tpermission\t%s\tpending\n' "$2" "$3" >>"$1/journal"
  printf '{"type":"control_request","request_id":"%s","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git push"},"tool_use_id":"t"}}\n' \
    "$2" >"$1/req-$2.json"
  printf 'demo:task-1\n' >"$1/scope"
}

pushes() {
  if [ -f "$1/attention/toasts" ]; then grep -c . "$1/attention/toasts"; else echo 0; fi
}

id1='aaaa1111-bbbb-cccc-dddd-eeee00000001'
id2='aaaa1111-bbbb-cccc-dddd-eeee00000002'

# ---------------------------------------------------------------------------
# w1: the bare invocation answers from argv alone.
# ---------------------------------------------------------------------------
copy="$tmp/w1scripts"
mkdir -p "$copy"
cp "$SJ" "$copy/fleet-streamjson.sh"
# A helper that never returns: before the fix the bare call sourced it first.
printf '#!/bin/sh\nsleep 30\n' >"$copy/echo-safety.sh"
printf '#!/bin/sh\nsleep 30\n' >"$copy/lock-lib.sh"
for args in "" "no-such-verb"; do
  # shellcheck disable=SC2086 # the empty case is no argument at all
  /bin/sh "$S/bounded-run.sh" 10 /bin/sh "$copy/fleet-streamjson.sh" $args >"$tmp/w1.out" 2>"$tmp/w1.err"
  rc=$?
  [ "$rc" = 2 ] || fail "w1: '$args' must exit 2 at once, got $rc (124 is the bound)"
  grep -q '^usage: fleet-streamjson.sh launch ' "$tmp/w1.err" || fail "w1: '$args' must print the usage, got: $(cat "$tmp/w1.err")"
  [ ! -s "$tmp/w1.out" ] || fail "w1: the usage goes to stderr only"
done
echo "ok: w1 no arguments or an unknown verb prints the usage and exits 2 at once"

# ---------------------------------------------------------------------------
# w2: pending shows a dead worker's requests as dead.
# ---------------------------------------------------------------------------
home="$tmp/h2"
dead="$home/streamjson/sjdead"
mkreq "$dead" "$id1" 1700000000
printf '%s\n' "$dead_pid" >"$dead/supervisor.pid"
printf '%s\n' "$dead_pid" >"$dead/worker.pid"
mkreq "$home/streamjson/sjquiet" "$id2" 1700000000
out=$(fenv "$home" "$SJ" pending) || fail "w2: pending exited non-zero"
printf '%s\n' "$out" | awk -v h="== sjdead $id1 Bash" '$0 == h { getline; print; exit }' \
  | grep -q '^-- worker dead: ' || fail "w2: the dead worker's request must be marked dead under its header, got: $out"
printf '%s\n' "$out" | awk -v h="== sjquiet $id2 Bash" '$0 == h { getline; print; exit }' \
  | grep -qx '| git push' || fail "w2: a worker with no death evidence must list as before, got: $out"
echo "ok: w2 pending marks a positively dead worker's requests dead and leaves the rest alone"

# ---------------------------------------------------------------------------
# w3: an overdue request of a worker nothing else watches reaches the queue
#     and is pushed; --once pushes it once.
# ---------------------------------------------------------------------------
home="$tmp/h3"
live="$home/streamjson/sjold"
mkreq "$live" "$id1" 1000
# Live pids, as an older supervisor without a tick would leave them.
printf '%s\n' "$$" >"$live/supervisor.pid"
printf '%s\n' "$$" >"$live/worker.pid"
out=$(fenv "$home" "$SJ" alarm-scan --once --now 5000 --threshold 900) || fail "w3: alarm-scan --once exited non-zero"
printf '%s\n' "$out" | grep -qx "alarm sjold $id1 4000" || fail "w3: expected the alarm line, got: $out"
q=$(fenv "$home" "$FA" queue)
printf '%s\n' "$q" | grep -q '^- \[high\] demo:task-1  (sjold' || fail "w3: the overdue request must be a high queue item, got: $q"
printf '%s\n' "$q" | grep -q 'OVERDUE permission request tool Bash' || fail "w3: the item must say it is overdue, got: $q"
[ "$(pushes "$home")" = 1 ] || fail "w3: the first --once scan must push once, pushed $(pushes "$home")"
fenv "$home" "$SJ" alarm-scan --once --now 5060 --threshold 900 >/dev/null || fail "w3: second --once scan exited non-zero"
[ "$(pushes "$home")" = 1 ] || fail "w3: a later --once scan must not push again, pushed $(pushes "$home")"
fenv "$home" "$SJ" alarm-scan --now 5120 --threshold 900 >/dev/null || fail "w3: plain scan exited non-zero"
[ "$(pushes "$home")" = 2 ] || fail "w3: a plain scan pushes on every call, pushed $(pushes "$home")"
grep -q "^$id1${tab}permission${tab}1000${tab}pending" "$live/journal" || fail "w3: escalation must never settle the request"
echo "ok: w3 an overdue request no tick watches reaches the queue high and --once pushes it once"

# ---------------------------------------------------------------------------
# w4: a dead worker's pending request is settled, never escalated.
# ---------------------------------------------------------------------------
home="$tmp/h4"
dead="$home/streamjson/sjgone"
mkreq "$dead" "$id1" 1000
printf '%s\n' "$dead_pid" >"$dead/supervisor.pid"
printf '%s\n' "$dead_pid" >"$dead/worker.pid"
# The row an earlier scan left: an OVERDUE request, the stale entry itself.
fenv "$home" "$FA" decide sjgone demo:task-1 \
  "OVERDUE permission request tool Bash req aaaa1111 - answer via fleet-streamjson.sh answer" deny "allow|deny" high \
  || fail "w4: cannot seed the stale row"
# A failure item under another dead worker's handle is the operator's.
fail_w="$home/streamjson/sjfailed"
mkreq "$fail_w" "$id2" 1000
printf '%s\n' "$dead_pid" >"$fail_w/supervisor.pid"
printf '%s\n' "$dead_pid" >"$fail_w/worker.pid"
fenv "$home" "$FA" decide sjfailed demo:task-2 "stream-json worker sjfailed died" acknowledge "acknowledge|investigate" high \
  || fail "w4: cannot seed the failure item"
out=$(fenv "$home" "$SJ" alarm-scan --now 5000 --threshold 900) || fail "w4: alarm-scan exited non-zero"
printf '%s\n' "$out" | grep -qx 'dead sjgone 1' || fail "w4: the dead worker must be settled, got: $out"
case $out in *"alarm sjgone"*) fail "w4: a dead worker must never be escalated, got: $out" ;; esac
[ "$(pushes "$home")" = 0 ] || fail "w4: nothing is pushed for a dead worker, pushed $(pushes "$home")"
q=$(fenv "$home" "$FA" queue)
case $q in *sjgone*) fail "w4: the dead worker's request row must leave the queue, got: $q" ;; esac
printf '%s\n' "$q" | grep -q 'sjfailed' || fail "w4: a failure item must stay, got: $q"
grep -q "^$id1${tab}permission${tab}1000${tab}undeliverable${tab}" "$dead/journal" \
  || fail "w4: the dead worker's receipt must be closed undeliverable, got: $(cat "$dead/journal")"
out=$(fenv "$home" "$SJ" pending sjgone) || fail "w4: pending exited non-zero"
[ -z "$out" ] || fail "w4: nothing stays pending once settled, got: $out"
[ ! -L "$dead/launch.lock" ] && [ ! -L "$dead/recover.lock" ] || fail "w4: the settle must drop the locks it took"
echo "ok: w4 a dead worker's pending request is settled and leaves the queue, never escalated"

# ---------------------------------------------------------------------------
# w5: two sessions launched from one checkout get distinct TMPDIRs, and
#     retiring one (its final close) leaves the other's files intact.
# ---------------------------------------------------------------------------
home="$tmp/h5"
wt="$tmp/wt5"
mkdir -p "$home" "$wt"
git -C "$wt" init -q || fail "w5: cannot create the checkout"
record() { # record <handle>: the scratch root its session record names
  (cd "$wt" && fenv "$home" "$S/worker-session-record.sh" write "$wt" --session "$1" --scratch) >"$tmp/w5.rec" 2>/dev/null \
    || fail "w5: the session record for $1 was not written"
  sed -n 's/^scratch_root=//p' "$(cat "$tmp/w5.rec")"
}
ra=$(record mc-alpha-worker-aaaa)
rb=$(record mc-alpha-worker-bbbb)
[ -n "$ra" ] && [ -n "$rb" ] && [ "$ra" != "$rb" ] && [ -d "$ra" ] && [ -d "$rb" ] \
  || fail "w5: two sessions must get distinct existing scratch roots, got '$ra' and '$rb'"
[ "${ra%/*}" = "${rb%/*}" ] || fail "w5: both roots belong under the worktree's own root"
[ "$(record mc-alpha-worker-aaaa)" = "$ra" ] || fail "w5: a relaunch of a session must find its own root again"
for h in aaaa bbbb; do
  mkdir -p "$home/streamjson/mc-alpha-worker-$h"
done
printf '%s\n' "$ra" >"$home/streamjson/mc-alpha-worker-aaaa/scratch-root"
printf '%s\n' "$rb" >"$home/streamjson/mc-alpha-worker-bbbb/scratch-root"
: >"$ra/a-file"
: >"$rb/b-file"
out=$(fenv "$home" "$SJ" stop mc-alpha-worker-aaaa --final) || fail "w5: the final close exited non-zero: $out"
[ ! -e "$ra" ] || fail "w5: the retired session's TMPDIR must go"
[ -f "$rb/b-file" ] || fail "w5: retiring one session must leave the other's files intact"
# A worktree-wide root from before roots were per session, which another
# worker still records, is left for the worktree reclaim.
wroot=${ra%/*}
mkdir -p "$home/streamjson/old-shape"
printf '%s\n' "$wroot" >"$home/streamjson/old-shape/scratch-root"
fenv "$home" "$SJ" stop old-shape --final >/dev/null || fail "w5: the old-shape final close exited non-zero"
[ -f "$rb/b-file" ] || fail "w5: an old-shape final close must not take a root another session still uses"
[ ! -e "$home/streamjson/old-shape/scratch-root" ] || fail "w5: the old-shape close still drops its own pointer"
echo "ok: w5 sessions sharing a checkout get distinct TMPDIRs, and retiring one leaves the other's intact"
