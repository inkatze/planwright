#!/bin/bash
# Tests for scripts/flight-lifecycle.sh: liveness that cannot be proven dead
# is never a crash (tower-front-door Task 9; D-8, D-10 · REQ-F1.5): a live
# worker, a print-rung flight, a finished or parked one, an unreadable
# brief or directory, and the operator kill-switch.
#
# Split from tests/test-flight-lifecycle.sh so each file fits the per-file
# test-time budget (a sweep reads every flight in the fixture, so a file
# that holds fewer flights runs faster).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/flight-lifecycle-fixture.sh
. "$(dirname "$0")/lib/flight-lifecycle-fixture.sh"

t=1000000

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
"$SCRIPT" push awaiting-decision "$P" --handle "tmux-flight-$P" --reason not-draft 2>/dev/null \
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

if [ "$fails" -gt 0 ]; then
  echo "test-flight-lifecycle-liveness: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle-liveness: all checks passed"
