#!/bin/bash
# Tests for scripts/flight-lifecycle.sh — flight lifecycle pushes into the
# attention store and the crash policy for flight workers (tower-front-door
# Task 9; D-8, D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.5, REQ-F1.6).
#
#
# This file holds properties 1 to 4 (pushes, screening, the crash policy);
# the liveness and sweep properties (5, 6) live in the
# tests/test-flight-lifecycle-*.sh files, split so each file fits the
# per-file test-time budget.
#
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
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck source=tests/lib/flight-lifecycle-fixture.sh
. "$(dirname "$0")/lib/flight-lifecycle-fixture.sh"

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

"$SCRIPT" push awaiting-decision "$F" --handle "$H" --reason hard-pause 2>"$tmp/err" \
  || fail "the awaiting-decision push failed: $(cat "$tmp/err")"
r=$(row "$H")
[ "$(field "$r" 3)" = awaiting-input ] || fail "the awaiting-decision push queues the worker (got: $r)"
case $(field "$r" 9) in
  *"flight-parked: hard-pause"*) ;;
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
"$SCRIPT" push awaiting-decision "$G" --handle "$HG" --reason "" 2>/dev/null \
  && fail "an empty reason must be refused"
# REQ-E1.9: the notification names only the kind of park, never its detail,
# so free text, a control byte, and bytes the store would refuse are all
# refused inputs.
for reason in "scope outgrew visual flight: it touches the auth module" "point not-draft" "hard-pause " HARD-PAUSE \
  "$(printf 'a\033[2Jb')" "$(printf 'scope grew \342\200\224 auth')"; do
  "$SCRIPT" push awaiting-decision "$G" --handle "$HG" --reason "$reason" 2>/dev/null
  rc=$?
  [ "$rc" -eq 2 ] || fail "REQ-E1.9: a reason other than one kind of park must be refused, exit 2 ('$reason', got $rc)"
done
"$SCRIPT" push lunch "$G" --handle "$HG" 2>/dev/null && fail "an unknown event must be refused"

# --- 4. Crash policy ------------------------------------------------------------
C=crash-aaaaaaa5
HC="tmux-flight-$C"
gitc "$repo" worktree add -q -b "planwright/flight/$C" "$repo/.claude/worktrees/flight-$C" HEAD
brief_dir "$C"

line() { printf '%s\n' "$1" | awk -F "$TAB" -v id="$C" '$2 == id'; }

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

if [ "$fails" -gt 0 ]; then
  echo "test-flight-lifecycle: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle: all checks passed"
