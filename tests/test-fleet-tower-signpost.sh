#!/bin/bash
# Tests for scripts/fleet-tower-signpost.sh — the SessionStart
# (`source: "startup"`) crash-recovery signpost for interactively-led towers
# (Task 3: D-4, REQ-A1.6; kickoff risk rows 7 and 22).
#
# Contract under test:
#   - fired at session startup (wired with matcher "startup" in
#     hooks/hooks.json; the script also checks a provided stdin `source`
#     defensively), it scans the fleet home's tower markers for an
#     INTERACTIVE-mode marker whose recorded checkout equals the starting
#     session's project dir;
#   - an orphaned marker (recorded pid POSITIVELY dead per the D-5
#     predicate) surfaces the exact `claude --resume <session-id>` command;
#   - it NEVER auto-resumes (no claude invocation) and NEVER discards the
#     marker (REQ-A1.6: the human chooses);
#   - an alive or unknown pid, an unattended marker (the watchdog's
#     domain), a checkout mismatch, or an absent/empty store stays silent;
#   - a marker whose session-id field fails the UUID shape is NOT surfaced
#     as a resume command (risk row 22: a surfaced command must never carry
#     a token matching no real session);
#   - hook-safety: always exit 0 (a signpost failure must never break
#     session startup).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FTS="$here/../scripts/fleet-tower-signpost.sh"
FTM="$here/../scripts/fleet-tower-marker.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FTS" ] || fail "scripts/fleet-tower-signpost.sh missing or not executable"
[ -x "$FTM" ] || fail "scripts/fleet-tower-marker.sh missing or not executable"

tmp=$(mktemp -d)
alive_pid=""
cleanup() {
  if [ -n "$alive_pid" ]; then
    kill "$alive_pid" 2>/dev/null || true
    wait "$alive_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap 'cleanup' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
checkout="$tmp/checkout"
mkdir -p "$checkout"
other_checkout="$tmp/elsewhere"
mkdir -p "$other_checkout"
bin="$tmp/bin"
mkdir -p "$bin"

uuid="123e4567-e89b-42d3-a456-426614174000"

# A dead pid and an alive pid.
/bin/sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
sleep 300 &
alive_pid=$!

# A canary `claude` on PATH: the signpost must NEVER invoke it (no
# auto-resume).
claude_log="$tmp/claude-called"
cat >"$bin/claude" <<EOF
#!/bin/sh
echo called >>"$claude_log"
EOF
chmod +x "$bin/claude"

run() {
  # run <project-dir> [stdin-json]
  r_dir=$1
  r_stdin="${2:-}"
  printf '%s' "$r_stdin" | PATH="$bin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$home" \
    CLAUDE_PROJECT_DIR="$r_dir" \
    /bin/bash "$FTS"
}

record() {
  # record <mode> <pid> <checkout> [session-id]
  r_sid="${4:-}"
  if [ -n "$r_sid" ]; then
    PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$FTM" record my-spec \
      --mode "$1" --pid "$2" --checkout "$3" --session-id "$r_sid" >/dev/null
  else
    PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$FTM" record my-spec \
      --mode "$1" --pid "$2" --checkout "$3" >/dev/null
  fi
}

# --- silence cases ------------------------------------------------------------

out=$(run "$checkout") || fail "empty store: exit non-zero"
[ -z "$out" ] || fail "empty store must stay silent, got '$out'"
echo "ok: an empty store stays silent"

record unattended "$dead_pid" "$checkout" "$uuid"
out=$(run "$checkout") || fail "unattended marker: exit non-zero"
[ -z "$out" ] || fail "an unattended marker is the watchdog's domain, got '$out'"
echo "ok: an unattended marker stays silent (mode mutual exclusion)"

record interactive "$alive_pid" "$checkout" "$uuid"
out=$(run "$checkout") || fail "alive marker: exit non-zero"
[ -z "$out" ] || fail "an alive tower must not be signposted, got '$out'"
echo "ok: an alive interactive tower stays silent"

record interactive "$dead_pid" "$other_checkout" "$uuid"
out=$(run "$checkout") || fail "checkout mismatch: exit non-zero"
[ -z "$out" ] || fail "a marker for another checkout must stay silent, got '$out'"
echo "ok: a marker for a different checkout stays silent"

# --- the signpost (REQ-A1.6) --------------------------------------------------

record interactive "$dead_pid" "$checkout" "$uuid"
out=$(run "$checkout") || fail "orphaned marker: exit non-zero"
case "$out" in
  *"claude --resume $uuid"*) ;;
  *) fail "the exact resume command must be surfaced, got '$out'" ;;
esac
case "$out" in
  *my-spec*) ;;
  *) fail "the signpost must name the spec, got '$out'" ;;
esac
echo "ok: an orphaned interactive tower surfaces the exact resume command"

# No auto-resume: the canary claude was never invoked.
[ ! -f "$claude_log" ] || fail "the signpost invoked claude (auto-resume is forbidden)"
echo "ok: no auto-resume (claude was never invoked)"

# No auto-discard: the marker survives the signpost.
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$FTM" read my-spec >/dev/null \
  || fail "the marker was discarded by the signpost"
echo "ok: no auto-discard (the marker survives)"

# Running it twice keeps signposting (idempotent, still no discard).
out=$(run "$checkout") || fail "second signpost: exit non-zero"
case "$out" in
  *"claude --resume $uuid"*) ;;
  *) fail "the signpost must persist until the human acts, got '$out'" ;;
esac
echo "ok: the signpost persists until the human acts"

# --- risk row 22: a non-UUID session id is never surfaced ---------------------

# Hand-corrupt the stored session-id field (the helper would refuse it).
row=$(PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$FTM" read my-spec)
printf '%s\n' "$row" | awk -F'\t' -v OFS='\t' '{$4="$(rm -rf ~)"; print}' \
  >"$home/towers/my-spec"
out=$(run "$checkout" 2>/dev/null) || fail "corrupt session id: exit non-zero"
case "$out" in
  *--resume*) fail "a malformed session id must never reach a resume command" ;;
esac
echo "ok: a malformed session id is never surfaced (risk row 22)"

# A marker recorded without a session id ('-') cannot produce a resume
# command either; it stays silent rather than surfacing a broken command.
record interactive "$dead_pid" "$checkout"
out=$(run "$checkout" 2>/dev/null) || fail "sessionless marker: exit non-zero"
case "$out" in
  *--resume*) fail "a sessionless marker must not surface a resume command" ;;
esac
echo "ok: a sessionless marker surfaces no resume command"

# --- defensive source check ---------------------------------------------------

record interactive "$dead_pid" "$checkout" "$uuid"
out=$(run "$checkout" '{"source":"resume","session_id":"x"}') \
  || fail "non-startup source: exit non-zero"
[ -z "$out" ] || fail "a non-startup source must stay silent, got '$out'"
echo "ok: a non-startup source stays silent"

# --- hook safety: an unresolvable home is a silent no-op ----------------------

: >"$tmp/blockfile"
rc=0
out=$(printf '' | PATH="$bin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="" \
  CLAUDE_PLUGIN_DATA="" CLAUDE_DIR="$tmp/blockfile" \
  CLAUDE_PROJECT_DIR="$checkout" /bin/bash "$FTS" 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook must exit 0 on an unresolvable home, got $rc"
[ -z "$out" ] || fail "unresolvable home must stay silent, got '$out'"
echo "ok: an unresolvable home never breaks session startup"

echo "ALL PASS: fleet-tower-signpost"
