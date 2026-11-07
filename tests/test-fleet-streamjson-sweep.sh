#!/bin/bash
# Tests for what `fleet-streamjson.sh` does for workers no current supervisor
# watches: the bare invocation (w1), `pending` on a dead worker (w2), the
# `alarm-scan` sweep and its once-per-request push (w3), dead workers settled
# rather than escalated (w4), per-session TMPDIRs a final close never crosses
# (w5), workers that ended normally settled like dead ones (w6), and what is
# not evidence of an end never read as one (w7). Each case's own comment says
# what it pins. Hermetic: every fleet home is case-local and built by hand.
# Runs under /bin/bash (3.2).
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
    PLANWRIGHT_FLEET_SCRATCH_BASE="$tmp/sb" \
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
# The early guard and the dispatch name the same verbs, so a verb added to one
# alone is never refused as unknown before the dispatch can reach it.
guard_verbs=$(awk '/^case \$\{1:-\} in$/ { getline; sub(/\) ;;$/, ""); gsub(/[ |]+/, "\n"); print; exit }' "$SJ" | grep . | sort)
dispatch_verbs=$(awk '/^case \$cmd in$/ { f = 1; next } f && /^esac$/ { exit } f && /^  [a-z_-]+\)/ { sub(/^  /, ""); sub(/\).*/, ""); print }' "$SJ" | sort)
[ -n "$guard_verbs" ] && [ -n "$dispatch_verbs" ] || fail "w1: cannot read the verb lists"
# shellcheck disable=SC2086 # word-split on purpose, one verb per line to one line
[ "$guard_verbs" = "$dispatch_verbs" ] \
  || fail "w1: the early guard and the dispatch must name the same verbs, guard: $(printf '%s ' $guard_verbs)dispatch: $(printf '%s ' $dispatch_verbs)"
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
# The mark is judged by journal state, never by a caller's threshold: a scan
# to which the request is not yet overdue keeps it.
fenv "$home" "$SJ" alarm-scan --now 5180 --threshold 9000 >/dev/null || fail "w3: high-threshold scan exited non-zero"
[ -f "$live/alarmed-$id1" ] || fail "w3: a scan with a higher threshold must not drop the mark"
fenv "$home" "$SJ" alarm-scan --once --now 5240 --threshold 900 >/dev/null || fail "w3: --once after it exited non-zero"
[ "$(pushes "$home")" = 2 ] || fail "w3: --once must not push again after a higher-threshold scan, pushed $(pushes "$home")"
# Answered, the mark goes; asked again, the request is pushed again.
sed "s/${tab}pending\$/${tab}answered${tab}5300/" "$live/journal" >"$tmp/w3.j" && mv "$tmp/w3.j" "$live/journal"
fenv "$home" "$SJ" alarm-scan --once --now 5360 --threshold 900 >/dev/null || fail "w3: scan after the answer exited non-zero"
[ ! -e "$live/alarmed-$id1" ] || fail "w3: an answered request's mark must go"
printf '%s\tpermission\t1000\tpending\n' "$id1" >"$live/journal"
fenv "$home" "$SJ" alarm-scan --once --now 5420 --threshold 900 >/dev/null || fail "w3: scan after the re-ask exited non-zero"
[ "$(pushes "$home")" = 3 ] || fail "w3: a request asked again must be pushed again, pushed $(pushes "$home")"
# A planted link at the mark's path is never written through, and claims nothing.
rm -f "$live/alarmed-$id1"
ln -s "$tmp/w3-target" "$live/alarmed-$id1"
fenv "$home" "$SJ" alarm-scan --once --now 5480 --threshold 900 >/dev/null || fail "w3: scan over a linked mark exited non-zero"
[ ! -e "$tmp/w3-target" ] || fail "w3: the mark was written through a symlink"
[ "$(pushes "$home")" = 3 ] || fail "w3: a linked mark must claim nothing, pushed $(pushes "$home")"
# A link to a fifo would block an open; the scan must neither block nor push.
rm -f "$live/alarmed-$id1"
mkfifo "$tmp/w3-fifo"
ln -s "$tmp/w3-fifo" "$live/alarmed-$id1"
/bin/sh "$S/bounded-run.sh" 10 env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u HOME PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_REPO_ROOT=none PLANWRIGHT_LOCAL_CONFIG="$pin_cfg" \
  /bin/sh "$SJ" alarm-scan --once --now 5540 --threshold 900 >/dev/null 2>&1 \
  || fail "w3: a mark linked to a fifo must not block the scan"
[ "$(pushes "$home")" = 3 ] || fail "w3: a mark linked to a fifo must claim nothing, pushed $(pushes "$home")"
rm -f "$live/alarmed-$id1"
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
# Not settled: a recover in flight (its election held by a live process), a
# worker with one pid still alive, and a runtime directory reached through a
# link.
held="$home/streamjson/sjheld"
mkreq "$held" "$id1" 1000
printf '%s\n' "$dead_pid" >"$held/supervisor.pid"
printf '%s\n' "$dead_pid" >"$held/worker.pid"
ln -s "$$-$(date +%s)-1" "$held/recover.lock"
half="$home/streamjson/sjhalf"
mkreq "$half" "$id1" 1000
printf '%s\n' "$$" >"$half/supervisor.pid"
printf '%s\n' "$dead_pid" >"$half/worker.pid"
victim="$tmp/w4-victim"
mkreq "$victim" "$id1" 1000
printf '%s\n' "$dead_pid" >"$victim/supervisor.pid"
printf '%s\n' "$dead_pid" >"$victim/worker.pid"
ln -s "$victim" "$home/streamjson/sjlinked"
out=$(fenv "$home" "$SJ" alarm-scan --now 5000 --threshold 900) || fail "w4: second alarm-scan exited non-zero"
case $out in *"dead sjheld"* | *"dead sjhalf"* | *"sjlinked"*) fail "w4: settled what it must not, got: $out" ;; esac
for j in "$held/journal" "$half/journal" "$victim/journal"; do
  grep -q "${tab}pending\$" "$j" || fail "w4: $j must stay pending, got: $(cat "$j")"
done
printf '%s\n' "$out" | grep -q "^alarm sjhalf $id1 " || fail "w4: a worker with a live pid is still escalated, got: $out"
[ -L "$held/recover.lock" ] || fail "w4: the settle must leave a live holder's lock alone"
echo "ok: w4 a dead worker's pending request is settled and leaves the queue, never escalated"

# ---------------------------------------------------------------------------
# w5: two sessions launched from one checkout get distinct TMPDIRs, and
#     retiring one (its final close) leaves the other's files intact.
# ---------------------------------------------------------------------------
home="$tmp/h5"
wt="$tmp/wt5"
mkdir -p "$home" "$wt"
mkdir -m 700 "$tmp/sb"
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
hreal=$(cd "$home" && pwd -P)
for r in "$ra" "$rb"; do
  case $r/ in
    "$hreal"/*) fail "w5: a session's root lies under the fleet home: $r" ;;
    "$(cd "$tmp/sb" && pwd -P)"/*) ;;
    *) fail "w5: a session's root lies outside the scratch base: $r" ;;
  esac
done
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
# The earlier layout under the fleet home: a worktree-wide root from before
# roots were per session, which a session's root inside it still uses, is left
# for the worktree reclaim.
wkey=$(printf '%s' "$(cd "$wt" && pwd -P)" | git hash-object --stdin)
wroot=$hreal/scratch/$wkey
lsess=$wroot/$(printf '%s' mc-alpha-worker-bbbb | git hash-object --stdin)
mkdir -p "$lsess" "$home/streamjson/old-shape" "$home/streamjson/old-sess"
: >"$lsess/b-file"
printf '%s\n' "$lsess" >"$home/streamjson/old-sess/scratch-root"
printf '%s\n' "$wroot" >"$home/streamjson/old-shape/scratch-root"
fenv "$home" "$SJ" stop old-shape --final >/dev/null || fail "w5: the old-shape final close exited non-zero"
[ -f "$lsess/b-file" ] || fail "w5: an old-shape final close must not take a root another session still uses"
[ ! -e "$home/streamjson/old-shape/scratch-root" ] || fail "w5: the old-shape close still drops its own pointer"
# Each session's record is its own, named by worktree and handle.
(cd "$wt" && fenv "$home" "$S/worker-session-record.sh" write "$wt" --session mc-alpha-worker-bbbb --scratch) >"$tmp/w5.rec" 2>/dev/null
[ "$(basename "$(cat "$tmp/w5.rec")")" = "$wkey-$(printf '%s' mc-alpha-worker-bbbb | git hash-object --stdin).record" ] \
  || fail "w5: the session record is not named by worktree and handle: $(cat "$tmp/w5.rec")"
for bad in "--session -x" "--session a/b" "--session ok 0123456789abcdef0123" "0123456789abcdef0123 --session ok"; do
  # shellcheck disable=SC2086 # the words are separate arguments on purpose
  (cd "$wt" && fenv "$home" "$S/worker-session-record.sh" write "$wt" $bad --scratch) >/dev/null 2>&1
  [ $? -eq 2 ] || fail "w5: worker-session-record must refuse '$bad' with exit 2"
done
# The close every rung shares: a worktree-wide root holding a session's root
# stays even with no pointer naming it (the headless rung's case), and a
# session pointer under a linked worktree root is refused, nothing removed.
release() { # release <unit-dir> <pointer>
  printf '%s\n' "$2" >"$1/scratch-root"
  (
    script_dir=$S
    # shellcheck source=scripts/fleet-stop-lib.sh
    . "$S/fleet-stop-lib.sh"
    stop_scratch_root_release "$1" "$home"
  )
}
unit="$tmp/w5-unit"
mkdir -p "$unit"
# The session's own pointer is set aside so only its directory keeps the root.
mv "$home/streamjson/old-sess/scratch-root" "$tmp/w5-bbbb-pointer"
release "$unit" "$wroot" || fail "w5: a root in use must release its pointer cleanly"
[ -f "$lsess/b-file" ] && [ ! -e "$unit/scratch-root" ] || fail "w5: a root holding a session's root must stay, its pointer gone"
mv "$tmp/w5-bbbb-pointer" "$home/streamjson/old-sess/scratch-root"
# A short worktree-wide root goes with its close, and only it: a directory
# inside it named like a session's does not keep it, since short session roots
# never nest.
sroot=$(PLANWRIGHT_FLEET_SCRATCH_BASE="$tmp/sb" /bin/sh "$S/fleet-scratch.sh" make "$home" "$wkey") \
  || fail "w5: no short worktree root"
mkdir -p "$sroot/$(printf 'd%.0s' $(seq 40))"
release "$unit" "$sroot" && [ ! -e "$sroot" ] && [ -f "$rb/b-file" ] \
  || fail "w5: a short worktree root must be removed by its close, and only it"
# With no session inside, another runtime directory recording the same root
# keeps it; once nobody else records it, the last close removes it.
shared=$(cd "$home" && pwd -P)/scratch/$(printf 'c%.0s' $(seq 40))
mkdir -p "$shared/old-file" "$home/streamjson/old-two"
printf '%s\n' "$shared" >"$home/streamjson/old-two/scratch-root"
release "$unit" "$shared" && [ -d "$shared/old-file" ] || fail "w5: a root another worker records must stay"
rm -f "$home/streamjson/old-two/scratch-root"
release "$unit" "$shared" && [ ! -e "$shared" ] || fail "w5: a root nobody else uses must be removed by the last close"
# A linked scratch record directory disables a session's scratch arm before
# anything is created or removed inside it.
lwt="$tmp/wt5l"
mkdir -p "$lwt" "$tmp/w5-elsewhere" "$tmp/h5l"
git -C "$lwt" init -q
ln -s "$tmp/w5-elsewhere" "$tmp/h5l/scratch"
(cd "$lwt" && fenv "$tmp/h5l" "$S/worker-session-record.sh" write "$lwt" --session s1 --fresh-scratch) >"$tmp/w5l.rec" 2>"$tmp/w5l.err" \
  || fail "w5: the record must still be written without a scratch arm"
! grep -q '^scratch_root=' "$(cat "$tmp/w5l.rec")" && grep -q 'scratch root is unusable' "$tmp/w5l.err" \
  && [ -z "$(ls -A "$tmp/w5-elsewhere")" ] \
  || fail "w5: a linked scratch record directory must leave the session without a scratch root, nothing created through it"
outside="$tmp/w5-outside"
mkdir -p "$outside/$(printf 'f%.0s' $(seq 40))/keep"
ln -s "$outside" "$hreal/scratch/$(printf 'e%.0s' $(seq 40))"
! release "$unit" "$hreal/scratch/$(printf 'e%.0s' $(seq 40))/$(printf 'f%.0s' $(seq 40))" \
  || fail "w5: a session pointer under a linked worktree root must be refused"
[ -d "$outside/$(printf 'f%.0s' $(seq 40))/keep" ] || fail "w5: the refused pointer removed something outside the fleet home"
echo "ok: w5 sessions sharing a checkout get distinct TMPDIRs, and retiring one leaves the other's intact"

# ---------------------------------------------------------------------------
# w6: a worker whose supervisor exited normally (both pid files removed, a
#     result written) is as gone as a dead one: what it left pending is
#     settled, never escalated, and `pending` marks it dead. A missing result,
#     or a pid file still standing, is not that evidence.
# ---------------------------------------------------------------------------
home="$tmp/h6"
ended="$home/streamjson/sjended"
mkreq "$ended" "$id1" 1000
printf 'result\tsuccess\t1100\tfalse\n' >"$ended/result"
fenv "$home" "$FA" decide sjended demo:task-1 \
  "OVERDUE permission request tool Bash req aaaa1111 - answer via fleet-streamjson.sh answer" deny "allow|deny" high \
  || fail "w6: cannot seed the stale row"
out=$(fenv "$home" "$SJ" pending sjended) || fail "w6: pending exited non-zero"
printf '%s\n' "$out" | awk -v h="== sjended $id1 Bash" '$0 == h { getline; print; exit }' \
  | grep -q '^-- worker dead: ' || fail "w6: the ended worker's request must be marked dead, got: $out"
# Not ended: no result yet (a launch before its pid files land), a result
# still being written, and a result beside live pids (a persistent worker
# between turns).
bare="$home/streamjson/sjbare"
mkreq "$bare" "$id1" 1000
torn="$home/streamjson/sjtorn"
mkreq "$torn" "$id1" 1000
printf 'result\tsuccess' >"$torn/result"
turn="$home/streamjson/sjturn"
mkreq "$turn" "$id1" 1000
printf 'result\tsuccess\t1100\tfalse\n' >"$turn/result"
printf '%s\n' "$$" >"$turn/supervisor.pid"
printf '%s\n' "$$" >"$turn/worker.pid"
# A launch in flight passes through the same shape (an old result, its pid
# files not yet written), so its election, held by a live process, holds the
# settle off.
launching="$home/streamjson/sjlaunching"
mkreq "$launching" "$id1" 1000
printf 'result\tsuccess\t1100\tfalse\n' >"$launching/result"
ln -s "$$-$(date +%s)-1" "$launching/launch.lock"
# A relaunch's own stop leaves the same shape before its recover runs; the
# settle taking the recover election there would refuse that recover.
relaunching="$home/streamjson/sjrelaunching"
mkreq "$relaunching" "$id1" 1000
printf 'result\tsuccess\t1100\tfalse\n' >"$relaunching/result"
ln -s "$$-$(date +%s)-1" "$relaunching/relaunch.lock"
out=$(fenv "$home" "$SJ" alarm-scan --once --now 5000 --threshold 900) || fail "w6: alarm-scan exited non-zero"
case $out in *sjlaunching*) fail "w6: a worker with a launch in flight was settled or escalated, got: $out" ;; esac
grep -q "${tab}pending\$" "$launching/journal" || fail "w6: a launch in flight must leave the request pending"
[ -L "$launching/launch.lock" ] || fail "w6: the settle must leave a live launch's election alone"
case $out in *sjrelaunching*) fail "w6: a worker with a relaunch in flight was settled or escalated, got: $out" ;; esac
grep -q "${tab}pending\$" "$relaunching/journal" || fail "w6: a relaunch in flight must leave the request pending"
[ ! -e "$relaunching/recover.lock" ] && [ ! -L "$relaunching/recover.lock" ] || fail "w6: the settle must not take the recover election under a live relaunch"
printf '%s\n' "$out" | grep -qx 'dead sjended 1' || fail "w6: the ended worker must be settled, got: $out"
case $out in *"alarm sjended"*) fail "w6: an ended worker must never be escalated, got: $out" ;; esac
case $(fenv "$home" "$FA" queue) in *sjended*) fail "w6: the ended worker's request row must leave the queue" ;; esac
grep -q "^$id1${tab}permission${tab}1000${tab}undeliverable${tab}" "$ended/journal" \
  || fail "w6: the ended worker's receipt must be closed undeliverable, got: $(cat "$ended/journal")"
case $out in *"dead sjbare"* | *"dead sjtorn"* | *"dead sjturn"*) fail "w6: settled what it must not, got: $out" ;; esac
for w in sjbare sjtorn sjturn; do
  printf '%s\n' "$out" | grep -q "^alarm $w $id1 " || fail "w6: $w must still be escalated, got: $out"
done
[ "$(pushes "$home")" = 3 ] || fail "w6: only the workers not known to be gone are pushed, pushed $(pushes "$home")"
echo "ok: w6 an ended worker's pending request is settled like a dead one's, never escalated"

# ---------------------------------------------------------------------------
# w7: what is not positive evidence of an end is never read as one. A pid
#     file that records no pid is not a dead pid, whatever the other file
#     says, and a `result` that is not a regular file is not a result record;
#     reading one (a fifo) must not hang the machine-wide sweep either.
# ---------------------------------------------------------------------------
home="$tmp/h7"
garbled="$home/streamjson/sjgarbled"
mkreq "$garbled" "$id1" 1000
printf '%s\n' "$dead_pid" >"$garbled/supervisor.pid"
printf 'not-a-pid\n' >"$garbled/worker.pid"
piped="$home/streamjson/sjpiped"
mkreq "$piped" "$id1" 1000
mkfifo "$piped/result"
(fenv "$home" "$SJ" alarm-scan --once --now 5000 --threshold 900 >"$tmp/w7.out" 2>&1) &
w7_pid=$!
n=0
while kill -0 "$w7_pid" 2>/dev/null && [ "$n" -lt 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
if kill -0 "$w7_pid" 2>/dev/null; then
  kill "$w7_pid" 2>/dev/null
  : >"$piped/result" &
  fail "w7: alarm-scan hung reading a result that is a fifo"
fi
wait "$w7_pid" || fail "w7: alarm-scan exited non-zero, got: $(cat "$tmp/w7.out")"
out=$(cat "$tmp/w7.out")
case $out in *"dead sjgarbled"* | *"dead sjpiped"*) fail "w7: settled what it must not, got: $out" ;; esac
for w in sjgarbled sjpiped; do
  grep -q "${tab}pending\$" "$home/streamjson/$w/journal" || fail "w7: $w must stay pending"
  printf '%s\n' "$out" | grep -q "^alarm $w $id1 " || fail "w7: $w must still be escalated, got: $out"
done
echo "ok: w7 a garbled pid file or a non-regular result is never read as the worker's end"
