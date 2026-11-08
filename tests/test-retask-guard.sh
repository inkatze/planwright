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
msg path '/tmp/notes.md has the operator'"'"'s answer.'
msg yes '/yes'
msg leadin 'Lead-in:
/planwright:execute-task x'
msg 'x=y' '/planwright:resume'

out=$(/bin/sh "$GUARD" check "$tmp/plain")
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a plain relay passes the check" || fail "a plain relay: exit $rc, $out"
for c in midslash path yes; do
  out=$(/bin/sh "$GUARD" check "$tmp/$c")
  rc=$?
  [ "$rc" = 0 ] && ok "a slash that is not a skill command passes ($c)" || fail "$c was refused: $out"
done
for c in skill skill-arg marker rules cadence leadin x=y; do
  out=$(/bin/sh "$GUARD" check "$tmp/$c" 2>/dev/null)
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

row() { # row <name> <kind> [<handle>]
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\tp\nkind\t%s\nscope\ts\nbackend\ttmux\nhandle\t%s\nlaunched\t0\n' "$1" "$2" "${3:-@1}" \
    >"$fleet/mission-control/sessions/$1"
}
row mc-p-worker-live worker @3
row mc-p-reviewer-live reviewer
row mc-p-ad-hoc-live ad-hoc
row mc-p-tower-live tower @7
row mc-p-worker-real worker
ln -s "$fleet/mission-control/sessions/mc-p-worker-real" "$fleet/mission-control/sessions/mc-p-worker-link"

out=$(/bin/sh "$GUARD" check "$tmp/skill" --to @7)
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a tower's window handle is not bound" || fail "a tower window handle was refused: exit $rc, $out"
out=$(/bin/sh "$GUARD" check "$tmp/skill" --to @3 2>/dev/null)
[ "$?" = 5 ] && ok "a worker's window handle is bound" || fail "a worker window handle passed: $out"

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
for k in reviewer ad-hoc; do
  hook SendMessage "mc-p-$k-live" "$tmp/skill"
  denied && ok "a launched $k is bound too" || fail "a $k re-task was not denied: $OUT"
done
hook SendMessage some-peer "$tmp/skill"
[ -z "$OUT" ] && ok "a session the launcher does not register is left alone" || fail "an unregistered peer was decided: $OUT"
hook SendMessage mc-p-worker-none "$tmp/skill"
[ -z "$OUT" ] && ok "an mc- name with no registry row is left alone" || fail "an unregistered mc- name was decided: $OUT"
hook SendMessage mc-p-worker-link "$tmp/skill"
[ -z "$OUT" ] && ok "a symlinked registry row is not trusted" || fail "a symlinked row was read: $OUT"
awk 'BEGIN { for (i = 0; i < 4000; i++) print "Background line " i " of a long relay, nothing to act on." }' >"$tmp/big"
printf '/planwright:execute-task other-spec 4\n' >>"$tmp/big"
hook SendMessage mc-p-worker-live "$tmp/big"
denied && ok "an oversize payload is still checked to its end" || fail "an oversize re-task slipped through: $OUT"
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
printf '   [planwright retask-override: indented reason]\n/planwright:polish\n' >"$tmp/override-indent"
hook SendMessage mc-p-worker-live "$tmp/override-indent" 2>/dev/null
[ -z "$OUT" ] && grep -q "${tab}indented reason\$" "$log" && ok "an indented override tag is honoured, logged" \
  || fail "an indented override: out '$OUT', log $(cat "$log")"
chmod 444 "$log"
hook SendMessage mc-p-worker-live "$tmp/override" 2>/dev/null
chmod 644 "$log"
denied && ok "an override that cannot be logged is denied" || fail "an unlogged override passed: $OUT"

if jq -e '[.hooks.PreToolUse[] | select(.matcher == "SendMessage")] | length == 1 and (.[0].hooks | length == 1)
    and (.[0].hooks[0].command | endswith("retask-guard.sh hook"))' "$here/../hooks/hooks.json" >/dev/null; then
  ok "hooks.json wires the hook once, on SendMessage"
else
  fail "hooks.json does not wire exactly one SendMessage hook to retask-guard.sh hook"
fi

printf 'not json' | /bin/sh "$GUARD" hook >"$tmp/garbage.out"
rc=$?
[ "$rc" = 0 ] && [ ! -s "$tmp/garbage.out" ] && ok "an unreadable payload is left to the harness" || fail "garbage payload: $(cat "$tmp/garbage.out")"

if [ "$failures" -gt 0 ]; then
  echo "test-retask-guard: $failures failure(s)" >&2
  exit 1
fi
echo "test-retask-guard: all passed"
