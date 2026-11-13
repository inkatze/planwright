#!/bin/bash
# Tests for scripts/flight-lifecycle.sh: the fleet sweep runs the crash policy
# every cycle, the checkout's own knobs govern it, a root record the relaunch
# cannot pin refuses it, and legacy registry rows are read by their columns
# (tower-front-door Task 9; D-8, D-10 · REQ-F1.6; fleet-messaging Task 4).
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

pinned="$tmp/pinned-root"
mkdir -p "$pinned"
cp -R "$ROOT/scripts" "$ROOT/doctrine" "$ROOT/config" "$pinned/"
V=race-aaaaaab4
HV="tmux-flight-$V"
gitc "$repo" worktree add -q -b "planwright/flight/$V" "$repo/.claude/worktrees/flight-$V" HEAD
brief_dir "$V"
vd="process $(dead_pid 19)"
/bin/sh "$STATE" register "$HV" "flight:$V" --backend tmux --death-handle "$vd" >/dev/null
(umask 077 && mkdir "$tmp/fleet/flights/$V/counted.$(printf '%s' "$vd" | cksum | awk '{ print $1 "." $2 }')")
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
HC="tmux-flight-$S"
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
  echo "test-flight-lifecycle-sweep: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle-sweep: all checks passed"
