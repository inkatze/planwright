#!/bin/bash
# Tests for the permission record — the attention store's positive `permission`
# marker (field 9) and the captured command (field 12) the PermissionRequest
# hook stamps, and what the answer channel will and will not do with them
# (tower-comms REQ-E1.8, REQ-E1.10, REQ-H1.1; D-12).
#
# Contract under test:
#   fleet-attention.sh permission <worker> <scope> [<command>]
#       awaiting-input, field 9 = `permission`, fields 10 and 11 reserved with
#       `-`, field 12 = the command text (or `-` when there is none).
#   fleet-attention.sh claim <worker> <instance-id> <label> [--standing <id>]
#       A permission-park is refused without --standing exactly as before; with
#       it, the channel resolves the decision itself and re-runs the match.
#   fleet-liveness.sh hook permission-request
#       Writes that record from the harness payload's tool_input.command.
#
# The rule-covered ACCEPT path is an integration of two scripts and lives in
# tests/test-tower-queue-standing.sh, where the rules are written.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-attention.sh"
FL="$here/../scripts/fleet-liveness.sh"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"
[ -x "$FL" ] || fail "scripts/fleet-liveness.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
store="$home/attention/state"

TAB=$(printf '\t')

fa() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FA" "$@" 2>"$errf"
}

# field <worker> <n> — the worker row's nth field, or the empty string.
field() {
  awk -F "$TAB" -v w="$1" -v n="$2" '($1 "") == (w "") { print (NF >= n ? $n : ""); exit }' "$store"
}

reset() { rm -rf "$home/attention"; }

# --- the record shape -------------------------------------------------------

reset
fa permission w1 spec.task-1 'git status --short' || fail "permission push failed"
[ "$(field w1 3)" = awaiting-input ] || fail "permission: state is not awaiting-input"
[ "$(field w1 9)" = permission ] || fail "permission: field 9 is not the marker (got '$(field w1 9)')"
[ "$(field w1 10)" = - ] || fail "permission: field 10 is not the reserved placeholder"
[ "$(field w1 11)" = - ] || fail "permission: field 11 is not the reserved placeholder"
[ "$(field w1 12)" = 'git status --short' ] || fail "permission: field 12 is not the command (got '$(field w1 12)')"
echo "ok: the permission record carries the marker and the command"

# A prompt whose command the payload did not carry still records the block; the
# absent command is what refuses the match downstream (REQ-E1.8).
reset
fa permission w1 spec.task-1 || fail "permission push with no command failed"
[ "$(field w1 9)" = permission ] || fail "no-command permission: the marker did not land"
[ "$(field w1 12)" = - ] || fail "no-command permission: field 12 is not '-'"
echo "ok: a permission with no command still carries the marker"

# Control bytes would tear the record; the block is still recorded, without the
# command, rather than refused or written.
reset
fa permission w1 spec.task-1 "$(printf 'git status\tls')" || fail "permission push with a tab in the command failed"
[ "$(field w1 9)" = permission ] || fail "torn-command permission: the marker did not land"
[ "$(field w1 12)" = - ] || fail "torn-command permission: the command was written anyway"
echo "ok: a command carrying a control byte is dropped, not written"

# --- the queued-decision guard ---------------------------------------------

# A fork must not clobber a pending permission. Before the marker shipped the
# guard keyed on an EMPTY field 9; the positive marker must not open that door.
reset
fa permission w1 spec.task-1 'git status' || fail "permission push failed"
rc=0
fa fork w1 spec.task-1 'pick one' a 'a|b' iid-1 || rc=$?
[ "$rc" = 3 ] || fail "a fork over a pending permission was not refused (exit $rc)"
[ "$(field w1 9)" = permission ] || fail "a fork overwrote the permission record"
echo "ok: a fork over a pending permission is refused"

# --- the answer channel -----------------------------------------------------

reset
fa permission w1 spec.task-1 'git status' || fail "permission push failed"
rc=0
fa claim w1 - 'approve in the worker session' || rc=$?
[ "$rc" = 3 ] || fail "a permission-park answered with no rule was not refused (exit $rc)"
grep -q 'harness permission gate' "$errf" || fail "the no-rule refusal did not name the permission gate"
[ "$(field w1 11)" = - ] || fail "the refused answer stamped a claim anyway"
echo "ok: a permission-park with no named rule is still refused"

# A rule that resolves to nothing is refused; the channel never falls open on a
# decision it could not read.
rc=0
fa claim w1 - 'approve in the worker session' --standing i00000000 || rc=$?
[ "$rc" = 3 ] || fail "an unresolvable standing decision was not refused (exit $rc)"
[ "$(field w1 11)" = - ] || fail "the refused answer stamped a claim anyway"
echo "ok: a standing decision that resolves to nothing is refused"

# The marker with no command: nothing to match, so nothing is answered.
reset
fa permission w1 spec.task-1 || fail "permission push failed"
rc=0
fa claim w1 - 'approve in the worker session' --standing i00000000 || rc=$?
[ "$rc" = 3 ] || fail "a permission record with no command was not refused (exit $rc)"
grep -q 'no command field' "$errf" || fail "the refusal did not name the missing command field"
echo "ok: a permission record with no command field is refused"

# --standing names a permission answer; a fork is not one.
reset
fa fork w1 spec.task-1 'pick one' a 'a|b' iid-1 || fail "fork push failed"
rc=0
fa claim w1 iid-1 a --standing i00000000 || rc=$?
[ "$rc" = 3 ] || fail "--standing on a fork was not refused (exit $rc)"
grep -q 'not a permission-park' "$errf" || fail "the refusal came from the wrong branch"
[ "$(field w1 11)" = "" ] || fail "--standing on a fork answered it anyway"
echo "ok: --standing on an answerable fork is refused"

# An empty id names nothing; saying so beats telling the caller to pass the
# flag they just passed.
rc=0
fa claim w1 iid-1 a --standing '' || rc=$?
[ "$rc" = 2 ] || fail "an empty --standing was not a usage error (exit $rc)"
echo "ok: an empty --standing is a usage error"

# Only the bare marker. A `permission:<suffix>` shape is one this re-match has
# not been reasoned about, so it refuses rather than guessing.
reset
mkdir -p "$home/attention"
chmod 0700 "$home/attention"
printf 'w1\tspec.task-1\tawaiting-input\t1700000000\tnormal\tQ?\tanswer\tapprove|deny\tpermission:tool-x\t-\t-\tgit status\n' >"$store"
chmod 0600 "$store"
rc=0
fa claim w1 - approve --standing i00000000 || rc=$?
[ "$rc" = 3 ] || fail "a permission:<suffix> record was not refused (exit $rc)"
grep -q 'harness permission gate' "$errf" || fail "the suffixed marker was not refused by the permission branch"
echo "ok: only the bare permission marker is re-matchable"

# An ordinary fork answer is unchanged by all of the above.
reset
fa fork w1 spec.task-1 'pick one' a 'a|b' iid-1 || fail "fork push failed"
fa claim w1 iid-1 b || fail "an ordinary fork answer was refused"
[ "$(field w1 11)" = b ] || fail "the fork answer did not stamp field 11"
echo "ok: an ordinary fork answer still works"

# --- the permission verb's own refusals ------------------------------------

reset
rc=0
fa permission w1 || rc=$?
[ "$rc" = 2 ] || fail "a permission push with no scope was not a usage error (exit $rc)"
rc=0
fa permission 'bad handle' spec.task-1 || rc=$?
[ "$rc" = 2 ] || fail "a malformed worker handle was not refused (exit $rc)"
rc=0
fa permission w1 'bad scope' || rc=$?
[ "$rc" = 2 ] || fail "a malformed scope was not refused (exit $rc)"
[ ! -f "$store" ] || fail "a refused permission push wrote a row"
echo "ok: the permission verb refuses a malformed push without writing"

# --- the hook ---------------------------------------------------------------

fl_hook() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_WORKER_HANDLE=w9 \
    PLANWRIGHT_WORKER_SCOPE=spec.task-1 \
    /bin/sh "$FL" hook permission-request 2>"$errf"
}

reset
fl_hook <"$here/fixtures/hook-payloads/PermissionRequest.json" || fail "the permission-request hook exited non-zero"
[ "$(field w9 9)" = permission ] || fail "the hook did not stamp the permission marker"
[ "$(field w9 12)" = 'git status --short' ] || fail "the hook did not capture the payload command (got '$(field w9 12)')"
echo "ok: the PermissionRequest hook captures the payload's command"

# An escaped quote is the one decode a command text realistically needs.
reset
printf '%s\n' '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"grep -r \"needle\" .","description":"d"}}' >"$tmp/payload"
fl_hook <"$tmp/payload" || fail "the hook exited non-zero on an escaped-quote payload"
[ "$(field w9 12)" = 'grep -r "needle" .' ] || fail "the hook mis-decoded an escaped quote (got '$(field w9 12)')"
echo "ok: an escaped quote in the command decodes"

# A `command` key OUTSIDE tool_input is not the prompt's own.
reset
printf '%s\n' '{"hook_event_name":"PermissionRequest","command":"rm -rf /","tool_input":{"description":"d"}}' >"$tmp/payload"
fl_hook <"$tmp/payload" || fail "the hook exited non-zero on a payload with no tool_input.command"
[ "$(field w9 9)" = permission ] || fail "the hook did not stamp the marker"
[ "$(field w9 12)" = - ] || fail "the hook read a command key outside tool_input (got '$(field w9 12)')"
echo "ok: a command key outside tool_input is not captured"

# A payload with no command at all still records the block.
reset
printf '%s\n' '{"hook_event_name":"PermissionRequest","tool_name":"Read","tool_input":{"file_path":"/x"}}' >"$tmp/payload"
fl_hook <"$tmp/payload" || fail "the hook exited non-zero on a commandless payload"
[ "$(field w9 3)" = awaiting-input ] || fail "the hook did not record the block"
[ "$(field w9 9)" = permission ] || fail "the hook did not stamp the permission marker"
[ "$(field w9 12)" = - ] || fail "the hook invented a command"
echo "ok: a commandless prompt still records the block"

# An escape this cannot decode exactly yields NO command, so the prompt reaches
# the operator rather than being matched against a mis-decoded string.
for payload in \
  '{"tool_input":{"command":"printf \u0041"}}' \
  '{"tool_input":{"command":"printf \n"}}' \
  '{"tool_input":{"command":"printf \t"}}'; do
  reset
  printf '%s\n' "$payload" >"$tmp/payload"
  fl_hook <"$tmp/payload" || fail "the hook exited non-zero on an undecodable payload"
  [ "$(field w9 9)" = permission ] || fail "the hook did not record the block"
  [ "$(field w9 12)" = - ] || fail "the hook decoded an escape it does not handle (got '$(field w9 12)')"
done
echo "ok: an escape the decoder does not handle yields no command"

# A `command` key NESTED inside tool_input is not the prompt's own either.
reset
printf '%s\n' '{"tool_name":"X","tool_input":{"target":"prod","opts":{"command":"git status"}}}' >"$tmp/payload"
fl_hook <"$tmp/payload" || fail "the hook exited non-zero on a nested-command payload"
[ "$(field w9 12)" = - ] || fail "the hook read a command nested below tool_input (got '$(field w9 12)')"
echo "ok: a command key nested below tool_input is not captured"

# A payload a JSON parser would read differently yields NO command. A parser
# keeps the LAST duplicate key; a scan that took the first would show the
# operator one command and approve another.
for payload in \
  '{"tool_input":{"command":"git status","command":"rm -rf /tmp/x"}}' \
  '{"tool_input":{"command":"git status","description":"d","command":"rm -rf /tmp/x"}}' \
  '{"tool_input":{"command":"git status"},"tool_input":{"command":"rm -rf /tmp/x"}}' \
  '{"permission_suggestions":[{"tool_input":{"command":"git status"}}],"tool_input":{"command":"rm -rf /tmp/x"}}'; do
  reset
  printf '%s\n' "$payload" >"$tmp/payload"
  fl_hook <"$tmp/payload" || fail "the hook exited non-zero on an ambiguous payload"
  [ "$(field w9 9)" = permission ] || fail "the hook did not record the block"
  [ "$(field w9 12)" = - ] || fail "the hook read one command from an ambiguous payload (got '$(field w9 12)')"
done
echo "ok: a payload with a duplicate command or tool_input key yields no command"

# The escaped form inside a command text is not a raw key, so a command that
# mentions tool_input still decodes.
reset
printf '%s\n' '{"tool_input":{"command":"grep -r \"tool_input\" ."}}' >"$tmp/payload"
fl_hook <"$tmp/payload" || fail "the hook exited non-zero on a command mentioning tool_input"
[ "$(field w9 12)" = 'grep -r "tool_input" .' ] || fail "a command mentioning tool_input was refused (got '$(field w9 12)')"
echo "ok: a command text that mentions tool_input still decodes"

echo "PASS: $(basename "$0")"
