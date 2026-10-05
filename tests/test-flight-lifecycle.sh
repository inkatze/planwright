#!/bin/bash
# Tests for scripts/flight-lifecycle.sh — flight lifecycle pushes into the
# attention store and the crash policy for flight workers (tower-front-door
# Task 9; D-8, D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.5, REQ-F1.6).
#
# Properties verified:
#   1. All three lifecycle pushes (dispatch, awaiting-decision, completion)
#      reach the attention store from the script alone, with no tower session
#      running and nothing polling: each is one invocation that writes the
#      flight worker's row (REQ-F1.2).
#   2. Only the awaiting-decision push is actionable: it lands in the decision
#      queue, while dispatch and completion are status rows the queue
#      suppresses; completion carries the landing reference, a PR link or a
#      record path, and notifies through the notification seam (REQ-F1.1).
#   3. A push never clobbers a queued human decision, and every input is
#      screened before it is written: an off-grammar flight id, a handle that
#      is not the flight's own, a malformed landing, a control byte.
#   4. A killed flight worker follows the fleet crash-loop policy (REQ-F1.5):
#      each positively-dead worker is counted once, the relaunch waits out the
#      backoff, the relaunch resumes the flight's own worktree and branch with
#      its own brief and re-registers the worker, and at the disable threshold
#      no relaunch happens and the disable surfaces in the decision queue.
#   5. Liveness that cannot be proven dead is never a crash: a live worker, a
#      print-rung flight, and a landed one are left alone; the operator
#      kill-switch holds the relaunch without losing the count.
#   6. The fleet sweep runs the crash policy as one of its passes, so a dead
#      flight worker is handled with no tower session in the loop.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT PLANWRIGHT_ROOT PLANWRIGHT_ADOPTER_OVERLAY \
  PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_SKILLS_ROOT \
  PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_TOWER_ID CLAUDE_PROJECT_DIR \
  PLANWRIGHT_REPO_ROOT

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-lifecycle.sh"
STATE="$ROOT/scripts/fleet-state.sh"
ATTN="$ROOT/scripts/fleet-attention.sh"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-lifecycle.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
live_pid=''
cleanup() {
  [ -z "$live_pid" ] || kill "$live_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P)

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Stubs: a `claude` that logs its argv and cwd (the relaunch), a tmux that
# cannot reach a server, and no `gh`, so the checkout reads as having no forge.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'EOF'
#!/bin/sh
if [ -e "$CLAUDE_STUB_FAIL" ]; then
  rm -f "$CLAUDE_STUB_FAIL"
  exit 1
fi
{ printf 'cwd=%s\n' "$(pwd -P)"; printf 'argv=%s\n' "$*"; } >>"$CLAUDE_STUB_LOG"
exit 0
EOF
cat >"$tmp/bin/tmux" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/bin/claude" "$tmp/bin/tmux"
export PATH="$tmp/bin:$PATH"
export CLAUDE_STUB_LOG="$tmp/claude.log"
export CLAUDE_STUB_FAIL="$tmp/claude.fail"
: >"$CLAUDE_STUB_LOG"
export CLAUDE_DIR="$tmp/claude"

repo="$tmp/primary"
mkdir -p "$repo"
gitc "$repo" init -q
printf 'x\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m init
export PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
(umask 077 && mkdir -p "$tmp/fleet/flights")

row() { awk -F "$TAB" -v w="$1" '$1 == w' "$tmp/fleet/attention/state" 2>/dev/null; }
field() { printf '%s\n' "$1" | cut -f"$2"; }

# A flight's fleet-home directory, as dispatch leaves it.
brief_dir() {
  (umask 077 && mkdir -p "$tmp/fleet/flights/$1/record")
  printf '# brief\n' >"$tmp/fleet/flights/$1/brief.md"
  printf '%s\n' "$repo" >"$tmp/fleet/flights/$1/checkout"
}

# --- 1–2. The three pushes reach the store ----------------------------------
F=push-aaaaaaa1
H="tmux-flight-$F"
brief_dir "$F"

"$SCRIPT" push dispatch "$F" --handle "$H" 2>"$tmp/err" || fail "the dispatch push failed: $(cat "$tmp/err")"
r=$(row "$H")
[ "$(field "$r" 2)" = "flight:$F" ] && [ "$(field "$r" 3)" = working ] \
  || fail "the dispatch push writes the worker's row as working (got: $r)"
[ "$("$ATTN" queue --count 2>/dev/null)" = 0 ] || fail "a dispatch push is status, never a queued decision"

"$SCRIPT" push dispatch NOT_AN_ID --handle tmux-flight-NOT_AN_ID 2>/dev/null \
  && fail "an off-grammar flight id must be refused"
P=prin-aaaaaaa2
brief_dir "$P"
"$SCRIPT" push dispatch "$P" --handle "print-flight-$P" 2>"$tmp/err" || fail "the print-rung dispatch push failed: $(cat "$tmp/err")"
[ "$(field "$(row "print-flight-$P")" 3)" = idle ] \
  || fail "a print-rung flight has no process until the operator launches it, so its dispatch row is idle"

"$SCRIPT" push awaiting-decision "$F" --handle "$H" --reason "scope outgrew visual flight: it touches the auth module" 2>"$tmp/err" \
  || fail "the awaiting-decision push failed: $(cat "$tmp/err")"
r=$(row "$H")
[ "$(field "$r" 3)" = awaiting-input ] || fail "the awaiting-decision push queues the worker (got: $r)"
case $(field "$r" 9) in
  *"scope outgrew visual flight"*) ;;
  *) fail "the awaiting-decision row carries the reason (got: $r)" ;;
esac
[ "$("$ATTN" queue --count 2>/dev/null)" = 1 ] || fail "an awaiting-decision push is one decision-queue item"
"$ATTN" queue 2>/dev/null | grep -q "flight:$F" || fail "the decision queue names the flight"

# A later dispatch push must not clear the queued decision.
"$SCRIPT" push dispatch "$F" --handle "$H" 2>/dev/null
[ "$(field "$(row "$H")" 3)" = awaiting-input ] || fail "a status push must never clobber a queued decision"

G=land-aaaaaaa3
HG="tmux-flight-$G"
brief_dir "$G"
"$SCRIPT" push dispatch "$G" --handle "$HG" 2>/dev/null
"$SCRIPT" push completion "$G" --handle "$HG" --landing "pr:https://github.com/acme/widgets/pull/7" 2>"$tmp/err" \
  || fail "the completion push failed: $(cat "$tmp/err")"
[ "$(field "$(row "$HG")" 3)" = pr-ready ] || fail "a PR landing reads pr-ready in the store"
[ "$(cat "$tmp/fleet/flights/$G/landing" 2>/dev/null)" = "pr:https://github.com/acme/widgets/pull/7" ] \
  || fail "the completion push records the landing reference beside the flight's brief"
[ "$("$ATTN" queue --count 2>/dev/null)" = 1 ] || fail "a completion push is status, never a queued decision"
"$ATTN" render 2>/dev/null | grep -q "flight:$G" || fail "the status render shows the landed flight"

R=file-aaaaaaa4
HR="tmux-flight-$R"
brief_dir "$R"
"$SCRIPT" push completion "$R" --handle "$HR" --landing "record:specs/_flights/$R.md" 2>"$tmp/err" \
  || fail "the record-arm completion push failed: $(cat "$tmp/err")"
[ "$(field "$(row "$HR")" 3)" = "done" ] || fail "a record landing reads done in the store"

# A store that refuses the row still gets the landing kept beside the brief.
O=keep-aaaaaab6
brief_dir "$O"
chmod 500 "$tmp/fleet/attention"
"$SCRIPT" push completion "$O" --handle "tmux-flight-$O" --landing "record:specs/_flights/$O.md" 2>/dev/null
rc=$?
chmod 700 "$tmp/fleet/attention"
[ "$rc" -eq 4 ] || fail "a completion the store refused exits 4 (got $rc)"
[ "$(cat "$tmp/fleet/flights/$O/landing" 2>/dev/null)" = "record:specs/_flights/$O.md" ] \
  || fail "a completion the store refused still keeps its landing reference"

# A fleet home others can write keeps nothing beside the brief: whoever can
# write the home can swap its flights directory for one of their own.
W=home-aaaaaab7
brief_dir "$W"
chmod 770 "$tmp/fleet"
"$SCRIPT" push completion "$W" --handle "tmux-flight-$W" --landing "record:specs/_flights/$W.md" 2>"$tmp/err"
chmod 700 "$tmp/fleet"
[ ! -e "$tmp/fleet/flights/$W/landing" ] || fail "a fleet home others can write must not get a landing reference written under it"
grep -q 'no private flight directory' "$tmp/err" || fail "a fleet home others can write is named on stderr (got: $(cat "$tmp/err"))"

# The completion push goes through the notification seam with its landing.
mkdir -p "$tmp/cfg"
printf 'notification_channel: push\n' >"$tmp/cfg/local.yml"
PLANWRIGHT_LOCAL_CONFIG="$tmp/cfg/local.yml" "$SCRIPT" push completion "$R" --handle "$HR" \
  --landing "record:specs/_flights/$R.md" 2>/dev/null
relayed=$("$ATTN" relay 2>/dev/null)
case $relayed in
  *"$R"*"specs/_flights/$R.md"*"planwright/flight/$R"*) ;;
  *) fail "a record landing notifies with the record path and its branch (relayed: $relayed)" ;;
esac

# --- 3. Screening -------------------------------------------------------------
"$SCRIPT" push dispatch "$F" --handle "tmux-flight-other-aaaaaaa9" 2>/dev/null \
  && fail "a handle that is not the flight's own must be refused"
"$SCRIPT" push completion "$G" --handle "$HG" --landing "pr:javascript:alert(1)" 2>/dev/null \
  && fail "a malformed PR landing must be refused"
"$SCRIPT" push completion "$G" --handle "$HG" --landing "record:../../etc/passwd" 2>/dev/null \
  && fail "a record landing outside the flight record directory must be refused"
"$SCRIPT" push completion "$G" --handle "$HG" \
  --landing "pr:https://github.com/acme/widgets/pull/7
visit https://example.invalid/login" 2>/dev/null \
  && fail "a landing that matches only on one of its lines must be refused"
"$SCRIPT" push completion "$G" --handle "$HG" \
  --landing "record:x
/etc/passwd
specs/_flights/$G.md" 2>/dev/null \
  && fail "a multi-line record landing must be refused"
"$SCRIPT" push awaiting-decision "$G" --handle "$HG" --reason "$(printf 'a\033[2Jb')" 2>/dev/null \
  && fail "a reason carrying a control byte must be refused"
"$SCRIPT" push awaiting-decision "$G" --handle "$HG" --reason "" 2>/dev/null \
  && fail "an empty reason must be refused"
"$SCRIPT" push lunch "$G" --handle "$HG" 2>/dev/null && fail "an unknown event must be refused"

# --- 4. Crash policy ------------------------------------------------------------
C=crash-aaaaaaa5
HC="tmux-flight-$C"
gitc "$repo" worktree add -q -b "planwright/flight/$C" "$repo/.claude/worktrees/flight-$C" HEAD
brief_dir "$C"

sleep 3600 &
live_pid=$!
dead_pid() {
  _p=$((99999 - $1))
  while kill -0 "$_p" 2>/dev/null; do _p=$((_p - 7)); done
  printf '%s\n' "$_p"
}
die_as() {
  /bin/sh "$STATE" register "$HC" "flight:$C" --backend tmux --state-dir "$repo/.claude/worktrees/flight-$C" \
    --death-handle "process $(dead_pid "$1")" >/dev/null || fail "fixture: could not register a dead worker"
}
supervise() { (cd "$repo" && "$SCRIPT" supervise --repo-root "$repo" --now "$1" 2>"$tmp/err"); }
line() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$C" '$2 == id'; }
launches() { grep -c '^argv=' "$CLAUDE_STUB_LOG" | tr -d ' '; }

t=1000000
die_as 1
out=$(supervise "$t") || fail "supervise exited non-zero: $(cat "$tmp/err")"
[ "$(field "$(line "$out")" 1)" = backoff ] \
  || fail "the first crash is counted and the relaunch waits out the backoff (got: $out)"
[ "$(launches)" = 0 ] || fail "nothing relaunches inside the backoff window"

out=$(supervise "$((t + 10))")
[ "$(field "$(line "$out")" 1)" = backoff ] || fail "still inside the backoff window (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/$HC")" = 1 ] \
  || fail "one death is counted once however many sweeps observe it"

regs() { /bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h' | wc -l | tr -d ' '; }
regs_before=$(regs)
out=$(supervise "$((t + 31))")
[ "$(field "$(line "$out")" 1)" = relaunched ] || fail "past the backoff the worker relaunches (got: $out; $(cat "$tmp/err"))"
[ "$(launches)" = 1 ] || fail "the relaunch launched exactly one worker"
grep -q "^argv=--worktree flight-$C --tmux=classic -- Read $tmp/fleet/flights/$C/brief.md and follow it exactly.\$" "$CLAUDE_STUB_LOG" \
  || fail "the relaunch resumes the flight's own worktree with its own brief: $(cat "$CLAUDE_STUB_LOG")"
grep -q "^cwd=$repo\$" "$CLAUDE_STUB_LOG" || fail "the relaunch runs from the flight's checkout"
[ "$(regs)" -gt "$regs_before" ] \
  || fail "the relaunched worker is registered under the flight's handle"
/bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h' | tail -n 1 | grep -q "flight:$C" \
  || fail "the relaunched worker's record carries the flight's scope"

# The same death read again after its relaunch (a second sweep that raced the
# first, or a registry the relaunch could not update) is neither counted nor
# relaunched a second time.
same=$(/bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h && $7 != "" && $7 != "-" { d = $7 } END { print d }')
/bin/sh "$STATE" register "$HC" "flight:$C" --backend tmux --death-handle "$same" >/dev/null
out=$(supervise "$((t + 35))")
[ -n "$same" ] || fail "fixture: the first death's handle was not found in the registry"
[ "$(field "$(line "$out")" 1)" = waiting ] || fail "an already-relaunched death reads waiting (got: $out)"
[ "$(launches)" = 1 ] || fail "one death is relaunched once, however many sweeps observe it (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/$HC")" = 1 ] || fail "a relaunched death is not counted again"

die_as 2
out=$(supervise "$((t + 40))")
[ "$(field "$(line "$out")" 1)" = backoff ] || fail "a second death backs off again (got: $out)"
out=$(supervise "$((t + 40 + 61))")
[ "$(field "$(line "$out")" 1)" = relaunched ] || fail "the doubled backoff passes and the worker relaunches (got: $out)"
[ "$(launches)" = 2 ] || fail "two relaunches so far"

die_as 3
out=$(supervise "$((t + 500))")
[ "$(field "$(line "$out")" 1)" = disabled ] || fail "the third death reaches the disable threshold (got: $out)"
out=$(supervise "$((t + 99999))")
[ "$(launches)" = 2 ] || fail "a disabled flight worker is never relaunched"
"$ATTN" queue 2>/dev/null | grep -q "$HC" || fail "the disable surfaces in the decision queue"

# A disabled flight waits on the operator, not on a relaunch, so a pass over it
# pays for no forge read.
gitc "$repo" remote add origin https://github.com/acme/widgets.git
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$GH_STUB_LOG"
exit 0
EOF
chmod +x "$tmp/bin/gh"
export GH_STUB_LOG="$tmp/gh.log"
: >"$GH_STUB_LOG"
supervise "$((t + 99999))" >/dev/null || fail "supervise over a disabled flight exited non-zero: $(cat "$tmp/err")"
[ ! -s "$GH_STUB_LOG" ] || fail "a flight waiting on the operator triggers no forge read (got: $(cat "$GH_STUB_LOG"))"
rm -f "$tmp/bin/gh"
gitc "$repo" remote remove origin

# --- 5. No proof of death, no crash ------------------------------------------
A=alive-aaaaaaa6
gitc "$repo" worktree add -q -b "planwright/flight/$A" "$repo/.claude/worktrees/flight-$A" HEAD
brief_dir "$A"
/bin/sh "$STATE" register "tmux-flight-$A" "flight:$A" --backend tmux --death-handle "process $live_pid" >/dev/null
Q=print-aaaaaaa7
gitc "$repo" worktree add -q -b "planwright/flight/$Q" "$repo/.claude/worktrees/flight-$Q" HEAD
brief_dir "$Q"
/bin/sh "$STATE" register "print-flight-$Q" "flight:$Q" --backend print --death-handle none >/dev/null
L=landed-aaaaaaa8
gitc "$repo" worktree add -q -b "planwright/flight/$L" "$repo/.claude/worktrees/flight-$L" HEAD
mkdir -p "$repo/.claude/worktrees/flight-$L/specs/_flights"
printf '# record\n' >"$repo/.claude/worktrees/flight-$L/specs/_flights/$L.md"
gitc "$repo/.claude/worktrees/flight-$L" add -A
gitc "$repo/.claude/worktrees/flight-$L" commit -q -m "chore(flight): land the record"
brief_dir "$L"
/bin/sh "$STATE" register "tmux-flight-$L" "flight:$L" --backend tmux --death-handle "process $(dead_pid 9)" >/dev/null
out=$(supervise "$((t + 99999))")
for id in "$A" "$Q" "$L"; do
  [ -z "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$id" '$2 == id')" ] \
    || fail "flight $id is not a provable crash and must be left alone (got: $out)"
  [ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$id" ] || fail "flight $id must not be counted as a crash"
done

K=paused-aaaaaaa9
gitc "$repo" worktree add -q -b "planwright/flight/$K" "$repo/.claude/worktrees/flight-$K" HEAD
brief_dir "$K"
/bin/sh "$STATE" register "tmux-flight-$K" "flight:$K" --backend tmux --death-handle "process $(dead_pid 11)" >/dev/null
printf 'fleet_daemon_pause: true\n' >"$tmp/cfg/paused.yml"
before=$(launches)
out=$(cd "$repo" && PLANWRIGHT_LOCAL_CONFIG="$tmp/cfg/paused.yml" "$SCRIPT" supervise --repo-root "$repo" --now "$((t + 99999))" 2>/dev/null)
[ "$(launches)" = "$before" ] || fail "the kill-switch holds every relaunch"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$K" '$2 == id { print $1 }')" = held ] \
  || fail "a paused daemon layer reads held, not backoff (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/tmux-flight-$K" 2>/dev/null)" = 1 ] \
  || fail "a paused daemon layer still counts the crash (bookkeeping is never paused)"

# A relaunch that fails counts as another crash: it backs off, then retries.
X=retry-aaaaaab2
HX="tmux-flight-$X"
gitc "$repo" worktree add -q -b "planwright/flight/$X" "$repo/.claude/worktrees/flight-$X" HEAD
brief_dir "$X"
/bin/sh "$STATE" register "$HX" "flight:$X" --backend tmux --death-handle "process $(dead_pid 15)" >/dev/null
lineof() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$2" '$2 == id { print $1 }'; }
supervise "$((t + 200000))" >/dev/null
: >"$CLAUDE_STUB_FAIL"
out=$(supervise "$((t + 200100))")
[ "$(lineof "$out" "$X")" = failed ] || fail "a relaunch that does not start reads failed (got: $out)"
before=$(launches)
out=$(supervise "$((t + 200101))")
[ "$(lineof "$out" "$X")" = backoff ] || fail "a relaunch that did not start counts as another failure and backs off (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/$HX")" = 2 ] || fail "a failed relaunch is counted toward the disable threshold"
out=$(supervise "$((t + 200200))")
[ "$(lineof "$out" "$X")" = relaunched ] || fail "a failed relaunch is retried once its backoff passes (got: $out)"
[ "$(launches)" = "$((before + 1))" ] || fail "the retried relaunch starts one worker"

# A crash-record that counts nothing releases its claim and relaunches nothing.
W=uncnt-aaaaaab3
HW="tmux-flight-$W"
gitc "$repo" worktree add -q -b "planwright/flight/$W" "$repo/.claude/worktrees/flight-$W" HEAD
brief_dir "$W"
/bin/sh "$STATE" register "$HW" "flight:$W" --backend tmux --death-handle "process $(dead_pid 17)" >/dev/null
before=$(launches)
chmod 500 "$tmp/fleet/liveness/crash"
out=$(supervise "$((t + 300000))")
chmod 700 "$tmp/fleet/liveness/crash"
[ "$(lineof "$out" "$W")" = failed ] || fail "a crash that could not be counted reads failed (got: $out)"
[ "$(launches)" = "$before" ] || fail "an uncounted death is never relaunched"
out=$(supervise "$((t + 300001))")
[ "$(lineof "$out" "$W")" = backoff ] || fail "the uncounted death is counted on the next pass (got: $out)"

# Another pass's count that is not yet recorded holds the relaunch.
V=race-aaaaaab4
HV="tmux-flight-$V"
gitc "$repo" worktree add -q -b "planwright/flight/$V" "$repo/.claude/worktrees/flight-$V" HEAD
brief_dir "$V"
vd="process $(dead_pid 19)"
/bin/sh "$STATE" register "$HV" "flight:$V" --backend tmux --death-handle "$vd" >/dev/null
(umask 077 && mkdir "$tmp/fleet/flights/$V/counted.$(printf '%s' "$vd" | cksum | awk '{ print $1 "." $2 }')")
out=$(supervise "$((t + 400000))")
[ "$(lineof "$out" "$V")" = waiting ] || fail "a count another pass has not recorded yet holds the relaunch (got: $out)"
grep -q "flight-$V" "$CLAUDE_STUB_LOG" && fail "no relaunch before the death is recorded"

"$SCRIPT" supervise --repo-root "$repo" --now 1234567890123456 >/dev/null 2>&1
[ $? -eq 2 ] || fail "an epoch the crash policy cannot take is refused up front"

# --- 6. The fleet sweep runs the crash policy every cycle ---------------------
S=swept-aaaaaab1
gitc "$repo" worktree add -q -b "planwright/flight/$S" "$repo/.claude/worktrees/flight-$S" HEAD
brief_dir "$S"
/bin/sh "$STATE" register "tmux-flight-$S" "flight:$S" --backend tmux --death-handle "process $(dead_pid 13)" >/dev/null
"$ROOT/scripts/fleet-sweep.sh" --repo "$repo" >/dev/null 2>"$tmp/sweep.err"
grep -q "flight $V crash policy: waiting" "$tmp/sweep.err" \
  || fail "the fleet sweep warns of a death held waiting, never drops it (stderr: $(cat "$tmp/sweep.err"))"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/tmux-flight-$S" 2>/dev/null)" = 1 ] \
  || fail "a fleet sweep cycle counts a dead flight worker under the crash policy"

# The crash knobs resolve from the flight's checkout, wherever supervise runs.
U=knobs-aaaaaab5
gitc "$repo" worktree add -q -b "planwright/flight/$U" "$repo/.claude/worktrees/flight-$U" HEAD
brief_dir "$U"
/bin/sh "$STATE" register "tmux-flight-$U" "flight:$U" --backend tmux --death-handle "process $(dead_pid 21)" >/dev/null
printf 'fleet_crash_backoff_base_seconds: 1000\n' >"$repo/.claude/planwright.yml"
(cd "$tmp" && "$SCRIPT" supervise --repo-root "$repo" --now "$((t + 500000))" >/dev/null 2>&1)
out=$(cd "$tmp" && "$SCRIPT" supervise --repo-root "$repo" --now "$((t + 500031))" 2>/dev/null)
rm -f "$repo/.claude/planwright.yml"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$U" '$2 == id { print $1 }')" = backoff ] \
  || fail "the checkout's own backoff knob governs its flights from any working directory (got: $out)"

if [ "$fails" -gt 0 ]; then
  echo "test-flight-lifecycle: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle: all checks passed"
