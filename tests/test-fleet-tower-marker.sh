#!/bin/bash
# Tests for scripts/fleet-tower-marker.sh — the mode-aware tower runtime
# marker store the tower-liveness watchdog (REQ-A1.5) and the interactive
# crash-recovery signpost (REQ-A1.6) both key off (Task 3, D-4).
#
# Contract under test:
#   record <spec> --mode unattended|interactive --pid <pid> --checkout <dir>
#          [--session-id <uuid>] [--tmux-session <name>]
#       Upsert the one marker row for <spec> under the cross-spec fleet home
#       (fleet-state.sh root), serialized through the fleet lock, written
#       via temp+rename so lockless readers never see a torn row.
#   read <spec>    print the row (TSV); exit 1 when absent.
#   clear <spec>   remove the marker; idempotent.
#   Exit codes: 0 success; 1 read-absent; 2 usage / refused hostile input /
#       unresolvable home / fs error (fail closed).
#   Row: <spec>\t<mode>\t<pid>\t<session_id>\t<tmux_session>\t<checkout>\t<epoch>
#       (session_id / tmux_session default to `-` when not provided).
#
# Hostile input is refused BEFORE any write (REQ-F1.1 / risk row 22): spec
# ids against the overlay identifier grammar, pids as bounded positive
# integers, session ids as UUIDs, checkout as an existing absolute dir with
# no control bytes, tmux session names against the death-evidence charset.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FTM="$here/../scripts/fleet-tower-marker.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FTM" ] || fail "scripts/fleet-tower-marker.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
checkout="$tmp/checkout"
mkdir -p "$checkout"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$FTM" "$@"
}

# `read` here is the marker helper's subcommand, not the shell builtin
# (SC2162 pattern-matches the word).
# shellcheck disable=SC2162
read_marker() {
  run read "$@"
}

uuid="123e4567-e89b-42d3-a456-426614174000"

# --- usage / hostile-input refusals -----------------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no args: exit $rc, expected 2"
echo "ok: no args refused"

rc=0
run bogus my-spec >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown subcommand: exit $rc, expected 2"
echo "ok: unknown subcommand refused"

rc=0
run record '../evil' --mode unattended --pid 123 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "traversal spec id: exit $rc, expected 2"
echo "ok: traversal spec id refused"

rc=0
run record 'UPPER' --mode unattended --pid 123 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "uppercase spec id: exit $rc, expected 2"
echo "ok: uppercase spec id refused"

rc=0
run record my-spec --mode sideways --pid 123 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown mode: exit $rc, expected 2"
echo "ok: unknown mode refused"

rc=0
run record my-spec --mode unattended --pid 0123 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "leading-zero pid: exit $rc, expected 2"
echo "ok: leading-zero pid refused"

rc=0
run record my-spec --mode unattended --pid 12x3 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-numeric pid: exit $rc, expected 2"
echo "ok: non-numeric pid refused"

rc=0
run record my-spec --mode unattended --pid 123 --checkout "relative/path" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "relative checkout: exit $rc, expected 2"
echo "ok: relative checkout refused"

rc=0
run record my-spec --mode unattended --pid 123 --checkout "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "nonexistent checkout: exit $rc, expected 2"
echo "ok: nonexistent checkout refused"

rc=0
run record my-spec --mode unattended --pid 123 --checkout "$checkout" \
  --session-id 'not-a-uuid' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed session id: exit $rc, expected 2"
echo "ok: malformed session id refused (risk row 22)"

rc=0
run record my-spec --mode unattended --pid 123 --checkout "$checkout" \
  --tmux-session 'bad name' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "whitespace tmux session: exit $rc, expected 2"
echo "ok: whitespace tmux-session name refused"

# Missing required flags.
rc=0
run record my-spec --mode unattended --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing --pid: exit $rc, expected 2"
echo "ok: missing --pid refused"

rc=0
run record my-spec --pid 123 --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing --mode: exit $rc, expected 2"
echo "ok: missing --mode refused"

# --- read on an absent marker ------------------------------------------------

rc=0
read_marker my-spec >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "read absent marker: exit $rc, expected 1"
echo "ok: absent marker reads exit 1"

# --- record + read round trip ------------------------------------------------

run record my-spec --mode unattended --pid 4242 --checkout "$checkout" \
  --session-id "$uuid" --tmux-session planwright-tower-my-spec \
  || fail "record (full) failed"
row=$(read_marker my-spec) || fail "read after record failed"
IFS=$(printf '\t') read -r f_spec f_mode f_pid f_sid f_tmux f_checkout f_epoch <<EOF
$row
EOF
[ "$f_spec" = my-spec ] || fail "row spec '$f_spec'"
[ "$f_mode" = unattended ] || fail "row mode '$f_mode'"
[ "$f_pid" = 4242 ] || fail "row pid '$f_pid'"
[ "$f_sid" = "$uuid" ] || fail "row session id '$f_sid'"
[ "$f_tmux" = planwright-tower-my-spec ] || fail "row tmux session '$f_tmux'"
case "$f_checkout" in
  /*) ;;
  *) fail "row checkout '$f_checkout' not absolute" ;;
esac
case "$f_epoch" in
  '' | *[!0-9]*) fail "row epoch '$f_epoch' not numeric" ;;
esac
echo "ok: record + read round trip preserves every field"

# --- optional fields default to '-' -------------------------------------------

run record other-spec --mode interactive --pid 999 --checkout "$checkout" \
  || fail "record (minimal) failed"
row=$(read_marker other-spec) || fail "read minimal marker failed"
IFS=$(printf '\t') read -r _ f_mode _ f_sid f_tmux _ _ <<EOF
$row
EOF
[ "$f_mode" = interactive ] || fail "minimal row mode '$f_mode'"
[ "$f_sid" = - ] || fail "minimal row session id '$f_sid', expected '-'"
[ "$f_tmux" = - ] || fail "minimal row tmux session '$f_tmux', expected '-'"
echo "ok: optional fields default to '-'"

# --- record is an upsert (one row per spec) -----------------------------------

run record my-spec --mode unattended --pid 5555 --checkout "$checkout" \
  || fail "re-record failed"
row=$(read_marker my-spec) || fail "read after re-record failed"
IFS=$(printf '\t') read -r _ _ f_pid f_sid _ _ _ <<EOF
$row
EOF
[ "$f_pid" = 5555 ] || fail "re-recorded pid '$f_pid'"
[ "$f_sid" = - ] || fail "re-record must replace, not merge: session id '$f_sid'"
lines=$(read_marker my-spec | wc -l | tr -d ' ')
[ "$lines" = 1 ] || fail "marker holds $lines rows, expected 1"
echo "ok: record upserts a single row"

# --- clear --------------------------------------------------------------------

run clear my-spec || fail "clear failed"
rc=0
read_marker my-spec >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "read after clear: exit $rc, expected 1"
run clear my-spec || fail "clear must be idempotent"
echo "ok: clear removes the marker and is idempotent"

# The other spec's marker is untouched by my-spec's clear.
read_marker other-spec >/dev/null || fail "clear must not touch sibling markers"
echo "ok: clear is per-spec"

# --- unwritable home fails closed ---------------------------------------------

# CLAUDE_DIR routed through a regular FILE: the writer-mode home can never be
# created, so a record must refuse (exit 2), never claim success.
: >"$tmp/blockfile"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="" CLAUDE_PLUGIN_DATA="" CLAUDE_DIR="$tmp/blockfile" \
  /bin/bash "$FTM" record my-spec --mode unattended --pid 123 \
  --checkout "$checkout" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unwritable home record: exit $rc, expected 2"
echo "ok: unwritable home fails closed"

echo "ALL PASS: fleet-tower-marker"
