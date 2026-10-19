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
#      its own brief and re-registers the worker, pinned to the planwright
#      root dispatch recorded (a recorded root that is gone refuses the
#      relaunch), and at the disable threshold no relaunch happens and the
#      disable surfaces in the decision queue.
#   5. Liveness that cannot be proven dead is never a crash: a live worker, a
#      print-rung flight, and any flight whose completion was pushed (whatever
#      the sweep reads its landing as) are left alone, while a landed one
#      whose dead worker never pushed its completion, queued no decision, and
#      ran under a brief carrying the landed check is counted and relaunched;
#      one whose directory, brief, or queue cannot be read is reported; the
#      operator kill-switch holds the relaunch without losing the count. A
#      completion that cannot keep its landing reference exits 4.
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

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

# The relaunch runs the tmux rung's real launch, so it runs on the launch
# fixture harness: a stub tmux whose sessions run the stub worker, which
# records the directory and argv it started with.
# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"
# shellcheck source=tests/lib/tmux-launch-cases.sh
. "$here/lib/tmux-launch-cases.sh"

SCRIPT="$ROOT/scripts/flight-lifecycle.sh"
STATE="$ROOT/scripts/fleet-state.sh"
ATTN="$ROOT/scripts/fleet-attention.sh"

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-lifecycle.sh missing or not executable" >&2
  exit 1
}

tmp="$TLH_SANDBOX/lifecycle"
mkdir -p "$tmp"
tmp=$(cd "$tmp" && pwd -P)
live_pid=''
# The harness owns the one EXIT trap; this suite's own cleanup runs first.
on_exit() {
  on_exit_status=$?
  [ -z "$live_pid" ] || kill "$live_pid" 2>/dev/null
  tlh_teardown "$on_exit_status"
}
trap on_exit EXIT

export CLAUDE_DIR="$tmp/claude"
# A bin for the forge stub one case installs; empty otherwise, so the checkout
# reads as having no forge.
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"

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

# end_session <flight-id> — end the flight worker's stub session, as its death
# does; the relaunch refuses a name a live session holds.
end_session() {
  "$TLH_BIN/tmux" kill-session -t "=$(expect_session "$repo" "flight-$1")" >/dev/null 2>&1 || :
}

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
rc=$?
chmod 700 "$tmp/fleet"
[ ! -e "$tmp/fleet/flights/$W/landing" ] || fail "a fleet home others can write must not get a landing reference written under it"
grep -q 'no private flight directory' "$tmp/err" || fail "a fleet home others can write is named on stderr (got: $(cat "$tmp/err"))"
# The crash sweep reads a missing landing reference as an unfinished flight,
# so a completion that cannot keep one fails rather than pass for done.
[ "$rc" -eq 4 ] || fail "a completion that cannot keep its landing reference exits 4 (got $rc)"
V=keepfail-aaaaaab8
brief_dir "$V"
# A directory where the temporary landing file goes fails the write for any
# user, root included.
mkdir "$tmp/fleet/flights/$V/landing.tmp"
"$SCRIPT" push completion "$V" --handle "tmux-flight-$V" --landing "record:specs/_flights/$V.md" 2>"$tmp/err"
rc=$?
rmdir "$tmp/fleet/flights/$V/landing.tmp"
[ "$rc" -eq 4 ] || fail "a landing reference that cannot be written fails the completion push with 4 (got $rc)"
grep -q 'could not keep the landing reference' "$tmp/err" || fail "the failed landing write is named (got: $(cat "$tmp/err"))"

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
# The store refuses text outside the printable range (a UTF-8 dash among it),
# so the push refuses it first, as a refused input rather than a store outage.
"$SCRIPT" push awaiting-decision "$G" --handle "$HG" --reason "$(printf 'scope grew \342\200\224 auth')" 2>/dev/null
rc=$?
[ "$rc" -eq 2 ] || fail "a reason the store would refuse is a refused input, exit 2 (got $rc)"
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
  end_session "$C"
  /bin/sh "$STATE" register "$HC" "flight:$C" --backend tmux --state-dir "$repo/.claude/worktrees/flight-$C" \
    --death-handle "process $(dead_pid "$1")" >/dev/null || fail "fixture: could not register a dead worker"
}
supervise() { (cd "$repo" && "$SCRIPT" supervise --repo-root "$repo" --now "$1" 2>"$tmp/err"); }
line() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$C" '$2 == id'; }
# launches — the relaunches so far: new-session calls, which the launch makes
# before it returns, so the count needs no wait.
launches() { calls_matching new-session | grep -c . | tr -d ' '; }

t=1000000
die_as 1
out=$(supervise "$t") || fail "supervise exited non-zero: $(cat "$tmp/err")"
[ "$(field "$(line "$out")" 1)" = backoff ] \
  || fail "the first crash is counted and the relaunch waits out the backoff (got: $out)"
[ "$(field "$(line "$out")" 3)" = 1 ] || fail "the backoff line reports the crash count (got: $out)"
[ "$(launches)" = 0 ] || fail "nothing relaunches inside the backoff window"

out=$(supervise "$((t + 10))")
[ "$(field "$(line "$out")" 1)" = backoff ] || fail "still inside the backoff window (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/$HC")" = 1 ] \
  || fail "one death is counted once however many sweeps observe it"

first_death=$(/bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h { d = $7 } END { print d }')
regs() { /bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h' | wc -l | tr -d ' '; }
regs_before=$(regs)
out=$(supervise "$((t + 31))")
[ "$(field "$(line "$out")" 1)" = relaunched ] || fail "past the backoff the worker relaunches (got: $out; $(cat "$tmp/err"))"
[ "$(launches)" = 1 ] || fail "the relaunch launched exactly one worker"
tlh_wait_workers 1 || fail "the relaunched worker did not start"
rec=$(tlh_last_worker_record)
tlh_assert_path_eq "the relaunch resumes the flight's own worktree" "$repo/.claude/worktrees/flight-$C" \
  "$(tlh_record_field "$rec" cwd)"
grep '^argv' "$rec" | grep -Fq "Read $tmp/fleet/flights/$C/brief.md and follow it exactly." \
  || fail "the relaunch hands the worker the flight's own brief: $(grep '^argv' "$rec")"
[ "$(regs)" -gt "$regs_before" ] \
  || fail "the relaunched worker is registered under the flight's handle"
/bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h' | tail -n 1 | grep -q "flight:$C" \
  || fail "the relaunched worker's record carries the flight's scope"

# The same death read again after its relaunch (a second sweep that raced the
# first, or a registry the relaunch could not update) is neither counted nor
# relaunched a second time.
same=$first_death
end_session "$C"
/bin/sh "$STATE" register "$HC" "flight:$C" --backend tmux --death-handle "$same" >/dev/null
out=$(supervise "$((t + 35))")
[ -n "$same" ] || fail "fixture: the first death's handle was not found in the registry"
[ "$(field "$(line "$out")" 1)" = waiting ] || fail "an already-relaunched death reads waiting (got: $out)"
[ "$(launches)" = 1 ] || fail "one death is relaunched once, however many sweeps observe it (got: $out)"
[ "$(cut -d' ' -f1 "$tmp/fleet/liveness/crash/$HC")" = 1 ] || fail "a relaunched death is not counted again"

# The relaunch pins the new worker to the root dispatch recorded beside the
# brief, not the sweep's own.
pinned="$tmp/pinned-root"
mkdir -p "$pinned"
cp -R "$ROOT/scripts" "$ROOT/doctrine" "$ROOT/config" "$pinned/"
printf '%s\n' "$pinned" >"$tmp/fleet/flights/$C/root"
die_as 2
out=$(supervise "$((t + 40))")
[ "$(field "$(line "$out")" 1)" = backoff ] || fail "a second death backs off again (got: $out)"
out=$(supervise "$((t + 40 + 61))")
[ "$(field "$(line "$out")" 1)" = relaunched ] || fail "the doubled backoff passes and the worker relaunches (got: $out)"
[ "$(launches)" = 2 ] || fail "two relaunches so far"
tlh_wait_workers 2 || fail "the pinned relaunch's worker did not start"
[ "$(tlh_worker_env "$(tlh_last_worker_record)" PLANWRIGHT_ROOT)" = "$pinned" ] \
  || fail "the relaunch must pin the worker to the recorded root (got: $(tlh_worker_env "$(tlh_last_worker_record)" PLANWRIGHT_ROOT))"
rm -f "$tmp/fleet/flights/$C/root"

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
# landed_flight <id> [record|pr] [checked] — a flight worktree that has
# landed: on the file home (record, the default) its record committed on its
# branch, on the PR home nothing local. `checked` gives its brief the landed
# check flight-lifecycle.sh relaunches a landed flight under.
landed_flight() {
  gitc "$repo" worktree add -q -b "planwright/flight/$1" "$repo/.claude/worktrees/flight-$1" HEAD
  if [ "${2:-record}" = record ]; then
    mkdir -p "$repo/.claude/worktrees/flight-$1/specs/_flights"
    printf '# record\n' >"$repo/.claude/worktrees/flight-$1/specs/_flights/$1.md"
    gitc "$repo/.claude/worktrees/flight-$1" add -A
    gitc "$repo/.claude/worktrees/flight-$1" commit -q -m "chore(flight): land the record"
  fi
  brief_dir "$1"
  if [ "${3:-}" = checked ]; then
    printf 'A relaunched worker runs this landed check before it fires any point.\n' >>"$tmp/fleet/flights/$1/brief.md"
  fi
}

# A finished flight (its worker gone, its landing reference kept) is the
# normal end state until its worktree is removed: on either home it wakes no
# forge read, though the forge-less read cannot see a PR landing.
Z=finished-aaaaaab1
landed_flight "$Z" record checked
printf 'record:specs/_flights/%s.md\n' "$Z" >"$tmp/fleet/flights/$Z/landing"
/bin/sh "$STATE" register "tmux-flight-$Z" "flight:$Z" --backend tmux --death-handle "process $(dead_pid 19)" >/dev/null
Y=finishedpr-aaaaaab2
landed_flight "$Y" pr checked
printf 'pr:https://github.com/acme/widgets/pull/9\n' >"$tmp/fleet/flights/$Y/landing"
/bin/sh "$STATE" register "tmux-flight-$Y" "flight:$Y" --backend tmux --death-handle "process $(dead_pid 23)" >/dev/null
: >"$GH_STUB_LOG"
supervise "$((t + 99999))" >/dev/null || fail "supervise over a disabled flight exited non-zero: $(cat "$tmp/err")"
[ ! -s "$GH_STUB_LOG" ] || fail "a flight waiting on the operator, or a finished one on either home, triggers no forge read (got: $(cat "$GH_STUB_LOG"))"
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
# Its completion was pushed: the landing reference sits beside the brief, and
# its brief carries the landed check, so only the reference keeps it alone.
L=landed-aaaaaaa8
landed_flight "$L" record checked
printf 'record:specs/_flights/%s.md\n' "$L" >"$tmp/fleet/flights/$L/landing"
/bin/sh "$STATE" register "tmux-flight-$L" "flight:$L" --backend tmux --death-handle "process $(dead_pid 9)" >/dev/null
# A landed flight whose worker died before it pushed its completion (no
# landing reference beside the brief) is a crash: its relaunch finishes the
# after-landing work through the brief's landed check.
I=unfinished-aaaaaaa3
landed_flight "$I" record checked
/bin/sh "$STATE" register "tmux-flight-$I" "flight:$I" --backend tmux --death-handle "process $(dead_pid 13)" >/dev/null
# The same, waiting on a decision it queued after landing: the operator rules.
P=parked-aaaaaab9
landed_flight "$P" record checked
"$SCRIPT" push awaiting-decision "$P" --handle "tmux-flight-$P" --reason "the PR is no longer a draft" 2>/dev/null \
  || fail "fixture: could not queue the parked flight's decision"
/bin/sh "$STATE" register "tmux-flight-$P" "flight:$P" --backend tmux --death-handle "process $(dead_pid 15)" >/dev/null
# The same, under a brief written before the landed check existed: its
# relaunch would fire every point again onto the landing.
D=oldbrief-aaaaaab0
landed_flight "$D" record
/bin/sh "$STATE" register "tmux-flight-$D" "flight:$D" --backend tmux --death-handle "process $(dead_pid 17)" >/dev/null
# The same, with a flight directory that cannot be judged private: reported,
# never skipped silently.
U2=unjudged-aaaaab3a
landed_flight "$U2" record checked
/bin/sh "$STATE" register "tmux-flight-$U2" "flight:$U2" --backend tmux --death-handle "process $(dead_pid 25)" >/dev/null
chmod 770 "$tmp/fleet/flights/$U2"
out=$(supervise "$((t + 99999))")
chmod 700 "$tmp/fleet/flights/$U2"
for id in "$A" "$Q" "$L" "$P" "$D" "$Y" "$Z"; do
  [ -z "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$id" '$2 == id')" ] \
    || fail "flight $id is not a provable crash and must be left alone (got: $out)"
  [ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$id" ] || fail "flight $id must not be counted as a crash"
done
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$I" '$2 == id { print $1 }')" = backoff ] \
  || fail "a landed flight that never pushed its completion is a crash, counted and backed off (got: $out)"
case $(printf '%s\n' "$out" | awk -F "$TAB" -v id="$U2" '$2 == id') in
  failed*"no private flight directory"*) ;;
  *) fail "a landed flight whose directory cannot be judged must be reported (got: $out)" ;;
esac
# A decision queue that cannot be looked into is unread, never absent: the
# parked flight is reported, not relaunched over its decision. Root reads
# through any mode, so the permission case runs only for other users.
if [ "$(id -u)" = 0 ]; then
  echo "skip: running as root, an unsearchable attention directory cannot be staged" >&2
else
  chmod 600 "$tmp/fleet/attention"
  out=$(supervise "$((t + 99999 + 31))")
  chmod 700 "$tmp/fleet/attention"
  case $(printf '%s\n' "$out" | awk -F "$TAB" -v id="$P" '$2 == id') in
    failed*"decision queue could not be read"*) ;;
    *) fail "an unreadable decision queue must be reported, never read as no decision (got: $out)" ;;
  esac
  [ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$P" ] || fail "a parked flight must never be counted over an unreadable queue"
fi
# fail_reads <tool> <pattern> — a stub <tool> first on PATH that exits 2 on
# any call whose arguments carry <pattern> and runs the real one otherwise.
fail_reads() {
  _fr_real=$(command -v "$1")
  printf '#!/bin/sh\ncase "$*" in *"%s"*) exit 2 ;; esac\nexec %s "$@"\n' "$2" "'$_fr_real'" >"$tmp/bin/$1"
  chmod +x "$tmp/bin/$1"
}
# The same for a store read that fails partway, which a permission check
# cannot see: a stub awk fails every decision-queue read, the sweep's and the
# lifecycle's; a landed render does not depend on the sweep's, so the
# lifecycle's is the one reported.
fail_reads awk awaiting-input
out=$(supervise "$((t + 99999 + 41))")
rm -f "$tmp/bin/awk"
case $(printf '%s\n' "$out" | awk -F "$TAB" -v id="$P" '$2 == id') in
  failed*"decision queue could not be read"*) ;;
  *) fail "a failed decision-queue read must be reported, never read as no decision (got: $out)" ;;
esac
[ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$P" ] || fail "a parked flight must never be counted over a failed queue read"
# A brief read that fails is reported, never taken for an older brief.
X=unreadbrief-aaaaab3b
landed_flight "$X" record checked
/bin/sh "$STATE" register "tmux-flight-$X" "flight:$X" --backend tmux --death-handle "process $(dead_pid 27)" >/dev/null
fail_reads grep 'runs this landed check'
out=$(supervise "$((t + 99999 + 51))")
rm -f "$tmp/bin/grep"
case $(printf '%s\n' "$out" | awk -F "$TAB" -v id="$X" '$2 == id') in
  failed*"brief could not be read"*) ;;
  *) fail "a failed brief read must be reported, never skipped (got: $out)" ;;
esac
[ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$X" ] || fail "a flight whose brief read failed must never be counted"

# With the reads restored, the unfinished landed flight relaunches past its
# backoff: each stub above failed its reads too, so no earlier pass could.
out=$(supervise "$((t + 99999 + 61))")
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$I" '$2 == id { print $1 }')" = relaunched ] \
  || fail "a landed flight that never pushed its completion is relaunched past the backoff (got: $out)"

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
# A tmux whose next new-session is refused, as a launch that cannot start is.
mkdir -p "$tmp/refuse"
{
  printf '#!/bin/sh\n'
  # shellcheck disable=SC2016 # the written stub expands its own $1
  printf 'if [ "$1" = new-session ] && [ -e %s ]; then\n' "'$tmp/refuse.flag'"
  printf '  rm -f %s\n' "'$tmp/refuse.flag'"
  printf '  echo "stub: the launch was refused" >&2\n  exit 1\nfi\n'
  printf 'exec %s "$@"\n' "'$TLH_BIN/tmux'"
} >"$tmp/refuse/tmux"
chmod +x "$tmp/refuse/tmux"
lineof() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$2" '$2 == id { print $1 }'; }
supervise "$((t + 200000))" >/dev/null
: >"$tmp/refuse.flag"
out=$(PATH="$tmp/refuse:$PATH" supervise "$((t + 200100))")
[ "$(lineof "$out" "$X")" = failed ] || fail "a relaunch that does not start reads failed (got: $out)"
case $(printf '%s\n' "$out" | awk -F "$TAB" -v id="$X" '$2 == id { print $3 }') in
  *"stub: the launch was refused"*) ;;
  *) fail "a relaunch that does not start names why (got: $out)" ;;
esac
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
calls_matching new-session | grep -q "flight-$V" && fail "no relaunch before the death is recorded"

# A record mark left by an earlier holder of the claim is not this holder's: a
# pass that released its count and another that took it since must not read the
# old mark as the new count recorded.
X=race-aaaaaab5
HX="tmux-flight-$X"
gitc "$repo" worktree add -q -b "planwright/flight/$X" "$repo/.claude/worktrees/flight-$X" HEAD
brief_dir "$X"
xd="process $(dead_pid 20)"
/bin/sh "$STATE" register "$HX" "flight:$X" --backend tmux --death-handle "$xd" >/dev/null
xc="$tmp/fleet/flights/$X/counted.$(printf '%s' "$xd" | cksum | awk '{ print $1 "." $2 }')"
ln -s "detached-$$-2-1-1-2" "$xc"
(umask 077 && printf '%s\n' "detached-$$-1-1-1-1" >"$xc.recorded")
out=$(supervise "$((t + 400001))")
[ "$(lineof "$out" "$X")" = waiting ] || fail "an earlier holder's record mark reads as the current count recorded (got: $out)"
calls_matching new-session | grep -q "flight-$X" && fail "no relaunch on an earlier holder's record mark"

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

# A root record the relaunch cannot pin to refuses it, rather than pinning
# whichever root resolves next: a recorded root that is no longer an install,
# named as the install's fault, and a record that is not a regular file
# holding one printable absolute path, named as the record's. Every case dies
# at once and one pair of sweeps handles them all.
bad_records='gone relative empty symlink ctl multiline'
n_case=0
# shellcheck disable=SC2086 # the record shapes are split on purpose
for bad in $bad_records; do
  n_case=$((n_case + 1))
  B="rec$n_case-aaaaaac$n_case"
  gitc "$repo" worktree add -q -b "planwright/flight/$B" "$repo/.claude/worktrees/flight-$B" HEAD
  brief_dir "$B"
  case $bad in
    gone) printf '%s\n' "$tmp/no-such-root" >"$tmp/fleet/flights/$B/root" ;;
    relative) printf 'pinned-root\n' >"$tmp/fleet/flights/$B/root" ;;
    empty) : >"$tmp/fleet/flights/$B/root" ;;
    symlink)
      printf '%s\n' "$pinned" >"$tmp/pinned-root.record"
      ln -s "$tmp/pinned-root.record" "$tmp/fleet/flights/$B/root"
      ;;
    ctl) printf '%s\001\n' "$pinned" >"$tmp/fleet/flights/$B/root" ;;
    multiline) printf '%s\n%s\n' "$pinned" "$pinned" >"$tmp/fleet/flights/$B/root" ;;
  esac
  /bin/sh "$STATE" register "tmux-flight-$B" "flight:$B" --backend tmux --state-dir "$repo/.claude/worktrees/flight-$B" \
    --death-handle "process $(dead_pid "$((20 + n_case))")" >/dev/null || fail "fixture: could not register a dead worker"
done
supervise "$((t + 900000))" >/dev/null
out=$(supervise "$((t + 900000 + 31))")
n_case=0
# shellcheck disable=SC2086 # the record shapes are split on purpose
for bad in $bad_records; do
  n_case=$((n_case + 1))
  B="rec$n_case-aaaaaac$n_case"
  g=$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$B" '$2 == id')
  [ "$(field "$g" 1)" = failed ] || fail "a $bad root record must fail the relaunch (got: $out)"
  if [ "$bad" = gone ]; then
    want="recorded planwright root is not an install any more"
  else
    want="root record is unreadable or malformed"
  fi
  case $(field "$g" 3) in
    *"$want"*"git worktree remove"*) ;;
    *) fail "a $bad root record must refuse with '$want' and the recovery (got: $g)" ;;
  esac
  calls_matching new-session | grep -q "flight-$B" && fail "a $bad root record must launch nothing"
done

# --- Registry arity (fleet-messaging Task 4) -------------------------------------
# The crash count reads the death handle by position: the writer's rows are nine
# columns (the session name and inbox appended), and a seven-column row written
# before them still counts its crash.
[ -n "$(/bin/sh "$STATE" registry 2>/dev/null | awk -F "$TAB" -v h="$HC" '$2 == h && NF == 9')" ] \
  || fail "fixture: the writer laid down no nine-column registry row"
O7=oldseven-aaaaaad7
gitc "$repo" worktree add -q -b "planwright/flight/$O7" "$repo/.claude/worktrees/flight-$O7" HEAD
brief_dir "$O7"
printf '100\ttmux-flight-%s\tflight:%s\t-\ttmux\t%s\tprocess %s\n' "$O7" "$O7" \
  "$repo/.claude/worktrees/flight-$O7" "$(dead_pid 40)" >>"$tmp/fleet/registry"
out=$(supervise "$((t + 2000000))")
g=$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$O7" '$2 == id')
[ "$(field "$g" 1)" = backoff ] && [ "$(field "$g" 3)" = 1 ] \
  || fail "a seven-column registry row counts its crash by its death handle (got: $out)"
# A three-column row (before the owner) carries no death handle: the sweep
# reads its liveness unknown, so supervise counts no crash and says nothing.
O3=oldthree-aaaaaad3
gitc "$repo" worktree add -q -b "planwright/flight/$O3" "$repo/.claude/worktrees/flight-$O3" HEAD
brief_dir "$O3"
printf '101\ttmux-flight-%s\tflight:%s\n' "$O3" "$O3" >>"$tmp/fleet/registry"
out=$(supervise "$((t + 2000000 + 5))")
[ -z "$(printf '%s\n' "$out" | awk -F "$TAB" -v id="$O3" '$2 == id')" ] \
  || fail "a three-column registry row was supervised as a death (got: $out)"
[ ! -e "$tmp/fleet/liveness/crash/tmux-flight-$O3" ] || fail "a three-column registry row counted a crash"

if [ "$fails" -gt 0 ]; then
  echo "test-flight-lifecycle: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle: all checks passed"
