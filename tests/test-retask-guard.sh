#!/bin/bash
# Tests for scripts/retask-guard.sh: a live repository-changing session is
# never handed a new unit of work. check refuses a unit-shaped message and
# passes a plain relay; the SendMessage hook denies one bound for a launched
# worker, lets every other recipient and tool through, and honours the
# logged override; log records every override.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-retask-guard.sh
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
GUARD="$here/../scripts/retask-guard.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to build the hook payloads" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-retask-guard.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')
fleet="$tmp/fleet"
export PLANWRIGHT_FLEET_STATE_DIR="$fleet"
mkdir -p "$fleet/mission-control/sessions"

# --- check -------------------------------------------------------------------

msg() { printf '%s\n' "$2" >"$tmp/$1"; }
msg plain 'The operator says: take the narrower reading and carry on.'
msg skill '/planwright:execute-task other-spec 4'
msg skill-arg '  /planwright:resume'
msg marker 'Next:
<!-- mission-control launch: mc-p-worker-1 (kind worker, scope s, program p) -->'
msg rules '<!-- mc-rules begin: program p, format 1, scope program, digest x -->'
msg cadence 'Do this.

## Verification cadence
'
msg midslash 'Run it, then /planwright:polish when you are done.'

out=$(/bin/sh "$GUARD" check "$tmp/plain")
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a plain relay passes the check" || fail "a plain relay: exit $rc, $out"
out=$(/bin/sh "$GUARD" check "$tmp/midslash")
rc=$?
[ "$rc" = 0 ] && ok "a skill named mid-sentence is not a unit's opening line" || fail "a mid-sentence skill was refused: $out"
for c in skill skill-arg marker rules cadence; do
  out=$(/bin/sh "$GUARD" check "$tmp/$c")
  rc=$?
  case $out in
    "retask$tab"*) [ "$rc" = 5 ] && ok "a unit-shaped message ($c) is refused" || fail "$c: exit $rc" ;;
    *) fail "$c: a unit-shaped message passed: exit $rc, '$out'" ;;
  esac
done
/bin/sh "$GUARD" check "$tmp/missing" 2>/dev/null
rc=$?
[ "$rc" = 2 ] && ok "a missing message file is a usage error" || fail "a missing message file did not exit 2"

# --- log ---------------------------------------------------------------------

err=$(/bin/sh "$GUARD" log --via steer --to mc-p-worker-a --reason "the operator asked" --now 100 2>&1)
log="$fleet/mission-control/retasks.log"
if [ "$(head -n 1 "$log")" = "# format: 1" ] && grep -q "^100${tab}steer${tab}mc-p-worker-a${tab}the operator asked\$" "$log"; then
  ok "an override is logged with its route, session and reason"
else
  fail "the override log: $(cat "$log" 2>&1)"
fi
case $err in *WARNING*mc-p-worker-a*) ok "and warned loudly" ;; *) fail "no warning: $err" ;; esac
/bin/sh "$GUARD" log --via steer --to mc-p-worker-a --reason "  " 2>/dev/null
rc=$?
[ "$rc" = 2 ] && ok "an override without a reason is refused" || fail "a blank reason was accepted"

# --- hook --------------------------------------------------------------------

row() { # row <name> <kind>
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\tp\nkind\t%s\nscope\ts\nbackend\ttmux\nlaunched\t0\n' "$1" "$2" \
    >"$fleet/mission-control/sessions/$1"
}
row mc-p-worker-live worker
row mc-p-tower-live tower

hook() { # hook <tool> <to> <message-file>: the hook's stdout in OUT, exit in RC
  payload=$(jq -nc --arg t "$1" --arg to "$2" --rawfile m "$3" \
    '{session_id:"s",hook_event_name:"PreToolUse",tool_name:$t,tool_input:{to:$to,message:$m}}')
  OUT=$(printf '%s' "$payload" | /bin/sh "$GUARD" hook)
  RC=$?
}
denied() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

hook SendMessage mc-p-worker-live "$tmp/skill"
if [ "$RC" = 0 ] && denied; then
  ok "a SendMessage handing a launched worker a new unit is denied"
else
  fail "the re-task SendMessage was not denied: exit $RC, $OUT"
fi
case $OUT in *"re-tasking a live session is refused"*"[planwright retask-override:"*) ok "the denial names the fresh launch and the override" ;; *) fail "the denial text: $OUT" ;; esac
hook SendMessage "mc-p-worker-live [d75dac]" "$tmp/marker"
denied && ok "a listing's [ref] suffix does not hide the worker" || fail "a [ref]-suffixed name slipped through: $OUT"
hook SendMessage mc-p-worker-live "$tmp/plain"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "a plain relay to the worker is left to the harness" || fail "a plain relay was decided: $OUT"
hook SendMessage mc-p-tower-live "$tmp/skill"
[ -z "$OUT" ] && ok "a tower is not bound by the worker rule" || fail "a tower message was decided: $OUT"
hook SendMessage some-peer "$tmp/skill"
[ -z "$OUT" ] && ok "a session the launcher does not register is left alone" || fail "an unregistered peer was decided: $OUT"
hook Bash mc-p-worker-live "$tmp/skill"
[ -z "$OUT" ] && ok "another tool is left alone" || fail "a Bash payload was decided: $OUT"

: >"$log"
printf '[planwright retask-override: the operator asked for this follow-up]\n/planwright:polish\n' >"$tmp/override"
hook SendMessage mc-p-worker-live "$tmp/override" 2>"$tmp/hook.err"
if [ -z "$OUT" ] && grep -q "${tab}send-message${tab}mc-p-worker-live${tab}the operator asked for this follow-up\$" "$log"; then
  ok "the override tag lets the message through, logged"
else
  fail "the override: out '$OUT', log $(cat "$log")"
fi
printf '[planwright retask-override: ]\n/planwright:polish\n' >"$tmp/override-blank"
hook SendMessage mc-p-worker-live "$tmp/override-blank"
denied && ok "an override tag without a reason is still denied" || fail "a blank override passed: $OUT"

printf 'not json' | /bin/sh "$GUARD" hook >"$tmp/garbage.out"
rc=$?
[ "$rc" = 0 ] && [ ! -s "$tmp/garbage.out" ] && ok "an unreadable payload is left to the harness" || fail "garbage payload: $(cat "$tmp/garbage.out")"

if [ "$failures" -gt 0 ]; then
  echo "test-retask-guard: $failures failure(s)" >&2
  exit 1
fi
echo "test-retask-guard: all passed"
