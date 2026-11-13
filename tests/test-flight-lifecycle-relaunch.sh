#!/bin/bash
# Tests for scripts/flight-lifecycle.sh: a relaunch that fails counts as
# another crash, and a death another pass has not recorded yet holds the
# relaunch (tower-front-door Task 9; D-8, D-10 · REQ-F1.5).
#
# Split from tests/test-flight-lifecycle.sh so each file fits the per-file
# test-time budget (a sweep reads every flight in the fixture, so a file
# that holds fewer flights runs faster).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck source=tests/lib/flight-lifecycle-fixture.sh
. "$(dirname "$0")/lib/flight-lifecycle-fixture.sh"

t=1000000

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
crash_denied=0
if hermetic_access_denied w "$tmp/fleet/liveness/crash"; then
  crash_denied=1
  out=$(supervise "$((t + 300000))")
else
  echo "skip: uncounted crash record: the running user still writes $tmp/fleet/liveness/crash under mode 500"
fi
chmod 700 "$tmp/fleet/liveness/crash"
if [ "$crash_denied" = 1 ]; then
  [ "$(lineof "$out" "$W")" = failed ] || fail "a crash that could not be counted reads failed (got: $out)"
  [ "$(launches)" = "$before" ] || fail "an uncounted death is never relaunched"
  out=$(supervise "$((t + 300001))")
  [ "$(lineof "$out" "$W")" = backoff ] || fail "the uncounted death is counted on the next pass (got: $out)"
fi

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

if [ "$fails" -gt 0 ]; then
  echo "test-flight-lifecycle-relaunch: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-lifecycle-relaunch: all checks passed"
