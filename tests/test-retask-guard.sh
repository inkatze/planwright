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
msg clear '/clear'
msg clearlater 'First the answer.
/clear is what the operator typed earlier.'

out=$(/bin/sh "$GUARD" check "$tmp/plain")
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a plain relay passes the check" || fail "a plain relay: exit $rc, $out"
for c in midslash path yes clearlater; do
  out=$(/bin/sh "$GUARD" check "$tmp/$c")
  rc=$?
  [ "$rc" = 0 ] && ok "a slash that is not a skill command passes ($c)" || fail "$c was refused: $out"
done
for c in skill skill-arg marker rules cadence leadin x=y clear; do
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
/bin/sh "$GUARD" log --via relay --to 'fleet:w=1/x' --reason "second" --now 101 2>/dev/null
if [ "$(grep -c '^# format: 1$' "$log")" = 1 ] && [ "$(grep -c "^10[01]${tab}" "$log")" = 2 ]; then
  ok "a second override appends under the one format line, any handle a steer or relay takes included"
else
  fail "the second override: $(cat "$log")"
fi
long=$(awk 'BEGIN { while (n++ < 600) printf "r" }')
esc=$(printf '\033')
c1=$(printf '\233')
u1=$(printf '\302\302\233\233')
/bin/sh "$GUARD" log --via steer --to mc-p-worker-a --now 102 \
  --reason "$(printf 'two\nlines\tand %s[31mred %sraw %sutf8 %s' "$esc" "$c1" "$u1" "$long")" 2>/dev/null
row102=$(grep "^102${tab}" "$log")
if [ "$(printf '%s' "$row102" | awk -F '\t' '{ print NF }')" = 4 ] \
  && ! printf '%s' "$row102" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177\200-\237]')" \
  && [ "$(printf '%s' "$row102" | cut -f 4 | awk '{ print length($0) }')" = 500 ]; then
  ok "a reason is logged on one row, control bytes (C1 included) removed, cut to its cap"
else
  fail "the cleaned reason: $(printf '%s' "$row102" | od -c | head -5)"
fi
/bin/sh "$GUARD" log --via steer --to 'a b' --reason why 2>/dev/null
[ "$?" = 2 ] || fail "log accepted a handle with a space"
/bin/sh "$GUARD" log --via steer --to mc-p-worker-a --now soon --reason why 2>/dev/null
[ "$?" = 2 ] || fail "log accepted a non-numeric epoch"
/bin/sh "$GUARD" log --via steer --to mc-p-worker-a --reason "  " 2>/dev/null
rc=$?
[ "$rc" = 2 ] && ok "an override without a reason is refused, as are a bad handle and epoch" || fail "a blank reason was accepted"
rows=$(wc -l <"$log")
/bin/sh "$GUARD" log --check --via steer --to mc-p-worker-a --reason "would log" 2>/dev/null
rc=$?
[ "$rc" = 0 ] && [ "$(wc -l <"$log")" = "$rows" ] && ok "log --check writes no row" || fail "log --check: exit $rc, $(cat "$log")"
chmod 444 "$log"
/bin/sh "$GUARD" log --check --via steer --to mc-p-worker-a --reason "would log" 2>/dev/null
rc=$?
chmod 644 "$log"
[ "$rc" = 2 ] && ok "and fails when the row could not be appended" || fail "log --check passed on an unwritable log"

# --- hook --------------------------------------------------------------------

row() { # row <name> <kind> [<handle>]
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\tp\nkind\t%s\nscope\ts\nbackend\ttmux\nhandle\t%s\nlaunched\t0\n' "$1" "$2" "${3:-@1}" \
    >"$fleet/mission-control/sessions/$1"
}
row mc-p-worker-live worker @3
row mc-p-reviewer-live reviewer
row mc-p-ad-hoc-live ad-hoc
row mc-p-tower-live tower @7
row mc-p-orchestrator-live orchestrator @8
row mc-p-mission-control-live mission-control @9
row mc-p-worker-real worker
ln -s "$fleet/mission-control/sessions/mc-p-worker-real" "$fleet/mission-control/sessions/mc-p-worker-link"

out=$(/bin/sh "$GUARD" check "$tmp/skill" --to @7)
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "a tower's window handle is not bound" || fail "a tower window handle was refused: exit $rc, $out"
out=$(/bin/sh "$GUARD" check "$tmp/skill" --to @3 2>/dev/null)
[ "$?" = 5 ] && ok "a worker's window handle is bound" || fail "a worker window handle passed: $out"
for to in mc-p-orchestrator-live @9 planwright:@7; do
  /bin/sh "$GUARD" check "$tmp/skill" --to "$to" >/dev/null 2>&1 && ok "an orchestrator, mission control or a <session>:@<n> tower handle is not bound ($to)" || fail "$to was refused"
done
mkdir -p "$tmp/bin"
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
[ "$1" = display-message ] && [ "$4" = %42 ] && { echo @7; exit 0; }
exit 1
STUB
chmod +x "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH" /bin/sh "$GUARD" check "$tmp/skill" --to %42 --tmux >/dev/null 2>&1 && ok "with --tmux a tower's pane id resolves to its window" || fail "a tower pane id was refused"
PATH="$tmp/bin:$PATH" /bin/sh "$GUARD" check "$tmp/skill" --to %43 --tmux >/dev/null 2>&1
[ "$?" = 5 ] && ok "and a pane tmux cannot resolve stays bound" || fail "an unresolvable pane passed"
nohome() { env -u CLAUDE_PLUGIN_DATA PLANWRIGHT_FLEET_STATE_DIR= CLAUDE_DIR="$tmp/noclaude" HOME="$tmp/nohome" "$@"; }
nohome /bin/sh "$GUARD" check "$tmp/skill" --to mc-p-tower-live >/dev/null 2>&1
rc=$?
nohome /bin/sh "$GUARD" check "$tmp/plain" --to mc-p-tower-live >/dev/null 2>&1
rc_plain=$?
[ "$rc" = 2 ] && [ "$rc_plain" = 0 ] && ok "an unresolvable fleet home fails a unit-shaped check, never a plain one" \
  || fail "an unresolvable fleet home: unit-shaped exit $rc"

hook() { # hook <tool> <to> <message-file>: the hook's stdout in OUT, exit in RC
  payload=$(jq -nc --arg t "$1" --arg to "$2" --rawfile m "$3" \
    '{session_id:"s",hook_event_name:"PreToolUse",tool_name:$t,tool_input:{to:$to,message:$m}}')
  OUT=$(printf '%s' "$payload" | /bin/sh "$GUARD" hook)
  RC=$?
}
denied() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }
# silent: left to the harness. A non-zero exit would itself block the call.
silent() { [ "$RC" = 0 ] && [ -z "$OUT" ]; }

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
silent && ok "a plain relay to the worker is left to the harness" || fail "a plain relay was decided: $OUT"
for k in tower orchestrator mission-control; do
  hook SendMessage "mc-p-$k-live" "$tmp/skill"
  silent && ok "a $k is not bound by the worker rule" || fail "a $k message was decided: exit $RC, $OUT"
done
for k in reviewer ad-hoc; do
  hook SendMessage "mc-p-$k-live" "$tmp/skill"
  denied && ok "a launched $k is bound too" || fail "a $k re-task was not denied: $OUT"
done
hook SendMessage some-peer "$tmp/skill"
silent && ok "a session the launcher does not register is left alone" || fail "an unregistered peer was decided: $OUT"
hook SendMessage mc-p-worker-none "$tmp/skill"
silent && ok "an mc- name with no registry row is left alone" || fail "an unregistered mc- name was decided: $OUT"
hook SendMessage mc-p-worker-link "$tmp/skill"
silent && ok "a symlinked registry row is not trusted" || fail "a symlinked row was read: $OUT"
hook SendMessage 'mc-../sessions/mc-p-worker-live' "$tmp/skill"
silent && ok "a name reaching outside the registry is left alone" || fail "a path-shaped name was read: $OUT"
awk 'BEGIN { for (i = 0; i < 4000; i++) print "Background line " i " of a long relay, nothing to act on." }' >"$tmp/big"
printf '/planwright:execute-task other-spec 4\n' >>"$tmp/big"
hook SendMessage mc-p-worker-live "$tmp/big"
denied && ok "an oversize payload is still checked to its end" || fail "an oversize re-task slipped through: $OUT"
hook Bash mc-p-worker-live "$tmp/skill"
silent && ok "another tool is left alone" || fail "a Bash payload was decided: $OUT"

: >"$log"
printf '[planwright retask-override: the operator asked for this follow-up]\n/planwright:polish\n' >"$tmp/override"
hook SendMessage mc-p-worker-live "$tmp/override" 2>"$tmp/hook.err"
if silent && grep -q "${tab}send-message${tab}mc-p-worker-live${tab}the operator asked for this follow-up\$" "$log"; then
  ok "the override tag lets the message through, logged"
else
  fail "the override: out '$OUT', log $(cat "$log")"
fi
printf '[planwright retask-override: ]\n/planwright:polish\n' >"$tmp/override-blank"
hook SendMessage mc-p-worker-live "$tmp/override-blank"
denied && ok "an override tag without a reason is still denied" || fail "a blank override passed: $OUT"
case $OUT in *"needs a reason"*) ok "and the denial names the missing reason" ;; *) fail "the blank-reason denial: $OUT" ;; esac
printf '[planwright retask-override: wipe and reuse]\n/clear\n' >"$tmp/override-clear"
hook SendMessage mc-p-worker-live "$tmp/override-clear" 2>/dev/null
silent && grep -q "${tab}wipe and reuse\$" "$log" && ok "the tag line is not part of what is checked: a /clear under it is logged" \
  || fail "the tag line was checked as the message: out '$OUT', log $(cat "$log")"
printf '   [planwright retask-override: indented reason]\n/planwright:polish\n' >"$tmp/override-indent"
hook SendMessage mc-p-worker-live "$tmp/override-indent" 2>/dev/null
silent && grep -q "${tab}indented reason\$" "$log" && ok "an indented override tag is honoured, logged" \
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
# A broken install and a host without jq fail open: the hook never blocks.
mkdir -p "$tmp/broken" "$tmp/nojq"
cp "$GUARD" "$tmp/broken/retask-guard.sh"
payload=$(jq -nc --rawfile m "$tmp/skill" '{tool_name:"SendMessage",tool_input:{to:"mc-p-worker-live",message:$m}}')
OUT=$(printf '%s' "$payload" | /bin/sh "$tmp/broken/retask-guard.sh" hook 2>&1)
RC=$?
silent && ok "a broken install leaves SendMessage alone" || fail "a broken install decided: exit $RC, $OUT"
for t in dirname cat awk; do ln -s "$(command -v "$t")" "$tmp/nojq/$t"; done
OUT=$(printf '%s' "$payload" | PATH="$tmp/nojq" /bin/sh "$GUARD" hook 2>&1)
RC=$?
silent && ok "without jq the hook stays silent" || fail "a jq-less hook decided: exit $RC, $OUT"

if [ "$failures" -gt 0 ]; then
  echo "test-retask-guard: $failures failure(s)" >&2
  exit 1
fi
echo "test-retask-guard: all passed"
