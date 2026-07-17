#!/bin/bash
# Tests for scripts/fleet-daemon-gate.sh — the operator kill-switch check
# helper every autonomous daemon mechanism calls BEFORE acting (Task 1: D-15,
# REQ-F1.3).
#
# The `fleet_daemon_pause` knob pauses every autonomous daemon action
# (cleanup, restart, throttle) without disabling fleet operation entirely. The
# gate resolves it through the shared knob resolver (resolve-config-knob.sh,
# D-22/REQ-G1.5) and answers with its exit code:
#   exit 0 = proceed (knob false)
#   exit 1 = paused (knob true) — the caller must short-circuit
#   exit 2 = usage / refused mechanism token
#   exit 4/5 = the resolver hard-failed (malformed team-shared value / broken
#              install) — FAIL CLOSED: any non-zero blocks the daemon action,
#              so a broken shared config pauses the daemon layer rather than
#              running it under unknown configuration (degrade capability,
#              never safety).
#
# What is covered:
#   - unset / false knob proceeds (exit 0, silent);
#   - true knob pauses (exit 1) with a stderr note naming the kill-switch;
#   - the knob resolves through the overlay layers (machine-local flip wins);
#   - a stubbed daemon call short-circuits when the switch is set and acts
#     when it is not (the Task 1 Done-when fixture);
#   - repo-tracked malformed value / file fail closed (exit 4, blocked);
#   - adopter malformed value degrades to the core default (proceed + warn);
#   - a hostile mechanism token is refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-daemon-gate.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FDG="$here/../scripts/fleet-daemon-gate.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FDG" ] || fail "scripts/fleet-daemon-gate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

printf 'fleet_daemon_pause: false\n' >"$core_cfg"

run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FDG" "$@"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# 1. Core default false: proceed, exit 0, nothing on stdout.
reset_layers
rc=0
out=$(run stale-cleanup 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "default: exit $rc, expected 0 (proceed)"
[ -z "$out" ] || fail "default: unexpected stdout '$out'"
echo "ok: the unset/false kill-switch proceeds (exit 0)"

# 2. Switch set true (machine-local, the operator's own lever): paused, exit 1,
#    stderr note naming the kill-switch and the mechanism.
reset_layers
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
err=$(run stale-cleanup 2>&1 >/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "paused: exit $rc, expected 1"
case $err in
  *fleet_daemon_pause*stale-cleanup* | *stale-cleanup*fleet_daemon_pause*) ;;
  *) fail "paused: note does not name the switch and mechanism (got: '$err')" ;;
esac
echo "ok: the set kill-switch pauses (exit 1) and names itself"

# 2b. The mechanism argument is optional.
rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "paused (no mechanism): exit $rc, expected 1"
echo "ok: the mechanism argument is optional"

# 3. The Done-when fixture: a stubbed daemon mechanism composed gate-first is
#    observably short-circuited by the set switch (the acted marker never
#    appears) and acts normally with it unset. This pins the gate's exit-code
#    contract as consumed by a caller; the gate-before-action ORDERING inside
#    real mechanisms is Tasks 2-7's obligation, not assertable here.
stub="$tmp/stub-daemon.sh"
cat >"$stub" <<EOF
#!/bin/sh
# A stub daemon action: gate first, then act (touch the acted marker).
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \\
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \\
  PLANWRIGHT_REPO_ROOT="$repo" \\
  PLANWRIGHT_LOCAL_CONFIG="" \\
  /bin/bash "$FDG" stub-daemon || exit 0
touch "$tmp/acted"
EOF
chmod +x "$stub"
reset_layers
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rm -f "$tmp/acted"
/bin/sh "$stub"
[ ! -e "$tmp/acted" ] || fail "stub daemon acted despite the kill-switch"
reset_layers
/bin/sh "$stub"
[ -e "$tmp/acted" ] || fail "stub daemon did not act with the switch unset"
echo "ok: a stubbed daemon call short-circuits on the set switch and acts when unset"

# 4. Repo-tracked malformed value: fail closed (exit 4 — non-zero blocks).
reset_layers
printf 'fleet_daemon_pause: maybe\n' >"$tracked_cfg"
rc=0
run stale-cleanup >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "repo-tracked malformed value: exit $rc, expected 4 (fail closed)"
echo "ok: a malformed team-shared value fails closed (exit 4)"

# 4b. Structurally malformed repo-tracked file: same fail-closed path.
reset_layers
printf 'fleet_daemon_pause:\n  - true\n' >"$tracked_cfg"
rc=0
run stale-cleanup >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "repo-tracked malformed file: exit $rc, expected 4 (fail closed)"
echo "ok: a structurally malformed team-shared config fails closed (exit 4)"

# 4c. The knob absent from EVERY layer (a core defaults file that omits it —
#     a broken/partial install): the gate must BLOCK, not proceed. The
#     resolver's fallback for this gate is the fail-safe value `true`, so an
#     unresolvable switch pauses the daemon layer (degrade capability, never
#     safety) instead of running it under unknown kill-switch state.
reset_layers
core_omit="$tmp/core-omit.yml"
printf 'max_parallel_units: 3\n' >"$core_omit"
rc=0
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_omit" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$FDG" stale-cleanup 2>&1 >/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "knob absent in every layer: exit $rc, expected 1 (the fallback 'true' lands on the paused arm)"
[ -n "$err" ] || fail "knob absent in every layer: no warning emitted"
echo "ok: a knob absent from every layer blocks the daemon action (fail closed)"

# 4e. Resolver exit 5 (a malformed CORE default — broken install) propagates
#     through the gate's fail-closed pass-through: blocked, never proceed.
core_bad="$tmp/core-bad.yml"
printf 'fleet_daemon_pause: maybe\n' >"$core_bad"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_bad" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$FDG" stale-cleanup >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "malformed core default: exit $rc, expected 5 (blocked, broken install)"
echo "ok: a malformed core default blocks the daemon action (exit 5 propagated)"

# 4d. Broken install: the gate's resolver missing entirely -> exit 5, blocked.
#     A copy of the gate in a dir with no sibling resolver simulates it.
mkdir -p "$tmp/lonely"
cp "$FDG" "$tmp/lonely/fleet-daemon-gate.sh"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$tmp/lonely/fleet-daemon-gate.sh" stale-cleanup >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing resolver: exit $rc, expected 5 (blocked, broken install)"
echo "ok: a missing resolver blocks the daemon action (exit 5)"

# 5. Adopter malformed value: degrades to the core default (proceed) with a
#    warning — the standard REQ-E1.4 by-layer policy via the shared resolver.
reset_layers
printf 'fleet_daemon_pause: maybe\n' >"$adopter_cfg"
rc=0
err=$(run stale-cleanup 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "adopter malformed value: exit $rc, expected 0 (degrade to core false)"
[ -n "$err" ] || fail "adopter malformed value: no warning emitted"
echo "ok: a malformed adopter value degrades to the core default with a warning"

# 6. A hostile mechanism token is refused (exit 2) before it reaches any
#    diagnostic surface.
reset_layers
for bad in 'x;rm' 'a b' '../x'; do
  rc=0
  run "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile mechanism '$bad': exit $rc, expected 2"
done
long_mech=$(printf '%0129d' 0)
rc=0
run "$long_mech" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "over-length mechanism token: exit $rc, expected 2"
rc=0
run stale-cleanup extra >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "two mechanism args: exit $rc, expected 2"
echo "ok: a hostile mechanism token is refused (exit 2)"

echo "ALL PASS: fleet-daemon-gate"
