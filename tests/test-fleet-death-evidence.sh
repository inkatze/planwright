#!/bin/bash
# Tests for scripts/fleet-death-evidence.sh — the thin wrapper exposing the
# backend capability contract's positive-evidence-of-death predicate for reuse
# by every kill/cleanup/restart mechanism in the fleet-autonomy bundle
# (Task 1: D-5, REQ-A1.7; doctrine/backend-capability-contract.md).
#
# The predicate's whole point (the 2026-06-12 incident: a dead tmux socket plus
# a truncated process listing mimicked dead workers that were alive): "dead" is
# reported ONLY when the query mechanism itself is demonstrably healthy AND the
# authoritative listing reports the target gone. Lost observability is
# `unknown`, never `dead`; a timeout or heartbeat age is not admissible
# evidence at all (the CLI has no such input, and the pseudo-class guard
# refuses one explicitly).
#
# Verdict contract (fail-closed for `if fleet-death-evidence.sh ...; then act`):
#   exit 0 = dead (positive evidence; destructive action authorized)
#   exit 1 = alive
#   exit 3 = unknown (lost observability; REFUSE to act)
#   exit 2 = usage / refused input (timeout pseudo-evidence included)
# The verdict word (dead|alive|unknown) is also printed on stdout.
#
# What is covered:
#   - the timeout/silence pseudo-evidence classes are refused (exit 2) — the
#     Done-when unit test: the wrapper refuses to act on a timeout alone;
#   - process class: a live pid is alive, an exited pid is dead, an invalid
#     pid token is refused before any signal is sent;
#   - tmux-window class (fake tmux on PATH): window listed -> alive; server
#     healthy + window absent -> dead; session absent -> dead; server
#     unreachable (the dead-socket scenario) -> unknown; tmux binary absent ->
#     unknown; hostile session/window tokens refused;
#   - the verdict word on stdout matches the exit code.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-death-evidence.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FDE="$here/../scripts/fleet-death-evidence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FDE" ] || fail "scripts/fleet-death-evidence.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# verdict <expected-word> <expected-rc> [args...] — run the wrapper, assert
# both the stdout verdict and the exit code.
verdict() {
  v_word=$1
  v_rc=$2
  shift 2
  rc=0
  out=$(/bin/bash "$FDE" "$@" 2>/dev/null) || rc=$?
  [ "$rc" = "$v_rc" ] || fail "args '$*': exit $rc, expected $v_rc"
  [ "$out" = "$v_word" ] || fail "args '$*': verdict '$out', expected '$v_word'"
}

# 1. Usage: no args, unknown evidence class, wrong arity are refused (exit 2).
rc=0
/bin/bash "$FDE" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no args: exit $rc, expected 2"
rc=0
/bin/bash "$FDE" seance worker-3 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown class: exit $rc, expected 2"
rc=0
/bin/bash "$FDE" process >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "process with no pid: exit $rc, expected 2"
echo "ok: usage errors are refused (exit 2)"

# 2. The pseudo-evidence guard: a timeout / silence / staleness claim is not
#    positive evidence and is refused with a message saying so — the wrapper
#    refuses to act on a timeout alone (Task 1 Done-when).
for pseudo in timeout silence stale heartbeat-age; do
  rc=0
  err=$(/bin/bash "$FDE" "$pseudo" 900 2>&1 >/dev/null) || rc=$?
  [ "$rc" = 2 ] || fail "pseudo-class '$pseudo': exit $rc, expected 2 (refused)"
  case $err in
    *"not positive evidence"*) ;;
    *) fail "pseudo-class '$pseudo': refusal does not explain itself (got: '$err')" ;;
  esac
done
echo "ok: timeout/silence pseudo-evidence is refused, never acted on"

# 3. process: invalid pid tokens are refused before any signal is sent.
for bad in abc -5 0 007 12345678901 1.5 ''; do
  rc=0
  /bin/bash "$FDE" process "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "invalid pid '$bad': exit $rc, expected 2"
done
echo "ok: invalid pid tokens are refused (exit 2)"

# 4. process: a live process is alive (exit 1). The trap is widened so an
#    assertion failure cannot leak the sleep child.
sleep 30 &
live_pid=$!
trap 'kill "$live_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
verdict alive 1 process "$live_pid"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
trap 'rm -rf "$tmp"' EXIT
echo "ok: a live process reports alive (exit 1)"

# 4b. process: pid 1 exercises the EPERM disambiguation arm for a non-root
#     runner (kill -0 1 -> EPERM -> targeted ps -p finds it -> alive); a root
#     runner short-circuits at kill -0 with the same verdict.
verdict alive 1 process 1
echo "ok: an existing but unsignalable process reports alive (EPERM arm)"

# 5. process: an exited, reaped process is dead (exit 0) — positive evidence
#    (the pid is queried directly, never a scraped process listing).
/bin/sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
verdict dead 0 process "$dead_pid"
echo "ok: an exited process reports dead (exit 0)"

# 5b. process: when the pid is not signalable AND the targeted ps query itself
#     fails abnormally (neither found nor not-found), the query mechanism is
#     broken — unknown, never dead. A fake ps forces the abnormal exit.
mkdir -p "$tmp/psbin"
printf '#!/bin/sh\nexit 2\n' >"$tmp/psbin/ps"
chmod +x "$tmp/psbin/ps"
rc=0
out=$(PATH="$tmp/psbin:$PATH" /bin/bash "$FDE" process "$dead_pid" 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "broken ps query: exit $rc, expected 3 (unknown)"
[ "$out" = unknown ] || fail "broken ps query: verdict '$out', expected 'unknown'"
echo "ok: a broken ps query reports unknown, never dead"

# --- tmux-window class, against a FAKE tmux on PATH. The fake emulates the
#     three probes the wrapper is allowed to make (server health via `ls`,
#     session presence via `has-session`, window listing via `list-windows`)
#     keyed off a mode file, so every branch is exercised hermetically.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
mode_file="$tmp/tmux-mode"
call_count="$tmp/tmux-calls"
cat >"$fakebin/tmux" <<EOF
#!/bin/sh
mode=\$(cat "$mode_file")
n=\$(cat "$call_count" 2>/dev/null || echo 0)
n=\$((n + 1))
printf '%s\n' "\$n" >"$call_count"
cmd=\$1
case "\$mode" in
  server-down)
    echo "error connecting to /private/tmp/tmux-501/default (No such file or directory)" >&2
    exit 1
    ;;
  server-dies-after-first-call)
    # The 2026-06-12 race, mid-sequence: the first probe (server health)
    # succeeds, every later call finds the server gone.
    if [ "\$n" -gt 1 ]; then
      echo "no server running on /private/tmp/tmux-501/default" >&2
      exit 1
    fi
    ;;
esac
case "\$cmd" in
  ls) exit 0 ;;
  has-session)
    case "\$mode" in
      session-absent) exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  list-windows)
    case "\$mode" in
      window-present) printf '@1\tworker-3\n@2\tother\n' ;;
      window-absent) printf '@2\tother\n' ;;
      listing-fails)
        echo "server exited unexpectedly" >&2
        exit 1
        ;;
      session-absent)
        echo "can't find session" >&2
        exit 1
        ;;
    esac
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$fakebin/tmux"

# run_tmux <mode> [args...] — run the wrapper with the fake tmux frontmost.
# The per-run call counter is reset so call-sequenced modes start fresh.
run_tmux() {
  rt_mode=$1
  shift
  printf '%s\n' "$rt_mode" >"$mode_file"
  printf '0\n' >"$call_count"
  PATH="$fakebin:$PATH" /bin/bash "$FDE" "$@"
}

# 6. Window present in a healthy server's listing -> alive.
rc=0
out=$(run_tmux window-present tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "tmux window present: exit $rc, expected 1 (alive)"
[ "$out" = alive ] || fail "tmux window present: verdict '$out', expected 'alive'"
echo "ok: a listed tmux window reports alive"

# 6b. Window-id targets are matched too (the listing carries @id and name).
rc=0
out=$(run_tmux window-present tmux-window planwright @1 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "tmux window by @id: exit $rc, expected 1 (alive)"
echo "ok: a window @id target matches the listing"

# 7. Server healthy, session present, window absent from the authoritative
#    listing -> dead (positive evidence).
rc=0
out=$(run_tmux window-absent tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "tmux window absent: exit $rc, expected 0 (dead)"
[ "$out" = dead ] || fail "tmux window absent: verdict '$out', expected 'dead'"
echo "ok: a window absent from a healthy server's listing reports dead"

# 8. Server healthy, session gone -> dead (the server is authoritative for its
#    own sessions).
rc=0
out=$(run_tmux session-absent tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "tmux session absent: exit $rc, expected 0 (dead)"
[ "$out" = dead ] || fail "tmux session absent: verdict '$out', expected 'dead'"
echo "ok: a session absent from a healthy server reports dead"

# 9. Server unreachable (the 2026-06-12 dead-socket scenario): lost
#    observability is UNKNOWN, never dead.
rc=0
out=$(run_tmux server-down tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "tmux server down: exit $rc, expected 3 (unknown)"
[ "$out" = unknown ] || fail "tmux server down: verdict '$out', expected 'unknown'"
echo "ok: an unreachable tmux server reports unknown, never dead (the 2026-06-12 lesson)"

# 9b. Server dies BETWEEN the health probe and has-session (the mid-sequence
#     race): has-session's failure must not be read as session death — the
#     wrapper re-verifies server health and refuses with unknown.
rc=0
out=$(run_tmux server-dies-after-first-call tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "server death mid-sequence: exit $rc, expected 3 (unknown)"
[ "$out" = unknown ] || fail "server death mid-sequence: verdict '$out', expected 'unknown'"
echo "ok: a server dying between probes reports unknown, never dead"

# 9c. list-windows fails after has-session succeeded (a narrower mid-sequence
#     race): also unknown, never dead.
rc=0
out=$(run_tmux listing-fails tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "listing fails after has-session: exit $rc, expected 3 (unknown)"
[ "$out" = unknown ] || fail "listing fails after has-session: verdict '$out', expected 'unknown'"
echo "ok: a listing failure after a healthy session probe reports unknown"

# 10. tmux binary absent entirely -> unknown (no observability at all). The
#     wrapper's tmux-window arm uses only shell builtins before the tmux
#     probe, so an empty PATH dir is a hermetic tmux-free environment (no
#     reliance on the host's /usr/bin being tmux-free).
mkdir -p "$tmp/empty-bin"
rc=0
out=$(PATH="$tmp/empty-bin" /bin/bash "$FDE" tmux-window planwright worker-3 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "tmux binary absent: exit $rc, expected 3 (unknown)"
[ "$out" = unknown ] || fail "tmux binary absent: verdict '$out', expected 'unknown'"
echo "ok: a missing tmux binary reports unknown"

# 11. Hostile session/window tokens are refused before any tmux call.
# shellcheck disable=SC2016 # the $(x) is a literal hostile token, not an expansion
for bad in 'pw;rm -rf' 'pw$(x)' '-tpw' 'pw pw' ''; do
  rc=0
  run_tmux window-present tmux-window "$bad" worker-3 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile session '$bad': exit $rc, expected 2"
  rc=0
  run_tmux window-present tmux-window planwright "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile window '$bad': exit $rc, expected 2"
done
echo "ok: hostile session/window tokens are refused (exit 2)"

echo "ALL PASS: fleet-death-evidence"
