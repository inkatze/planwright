#!/bin/bash
# Tests for scripts/orchestrate-relay.sh — the inter-orchestrator coordination
# relay/observe mechanics for /orchestrate and the meta-tower (orchestration-fleet
# Task 7; D-7, REQ-D1.2, REQ-D1.3, REQ-B1.7, REQ-A1.6). This is the scripts-level
# enforcement point behind doctrine/inter-orchestrator-coordination.md: the
# security-critical relay boundary made first-class and testable.
#
# Contract under test:
#   - `validate-handle <backend> <handle>` accepts only a handle matching the
#     declared per-backend grammar and rejects every hostile handle (shell
#     metacharacters, command substitution, whitespace, option injection,
#     over-length) BEFORE the handle is ever used to target a worker
#     (REQ-B1.7: handles parsed for targeting are validated before use). Exit 0
#     valid, exit 2 invalid/hostile/usage. No stdout.
#   - `relay-command <backend> <handle> <message-file>` emits the relay
#     command; for tmux that is this script's own `deliver` by literal path.
#     The message is DATA: the emitted command references the message FILE,
#     never inlines its content, so worker/tower message text is never spliced
#     into the command as code (REQ-B1.7: worker output is data, no
#     eval/expansion path). subagent is harness-native (no screen-scrape
#     surface): empty stdout, exit 0.
#   - `deliver tmux <handle> <message-file>` runs the ATTRIBUTED buffer-paste
#     (`load-buffer`/`paste-buffer`, never `send-keys`, REQ-D1.3): it refuses
#     while the target shows a selection prompt or a staged paste placeholder,
#     pastes one unterminated pointer line carrying a fresh tag, and confirms
#     the tag shows in the pane rather than assuming delivery.
#   - `observe-command <backend> <handle>` emits the capture-pane
#     observe-in-flight read (REQ-D1.3), handle validated first.
#   - Source audit: no `send-keys` and no `eval` path exists anywhere in the
#     script (the "no send-keys impersonation path exists" Done-when check).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RELAY="$here/../scripts/orchestrate-relay.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RELAY" ] || fail "scripts/orchestrate-relay.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# No tmux call here may reach the host's server: tmux honours $TMUX over
# TMUX_TMPDIR, so a test run from inside a tmux pane would otherwise act on
# the operator's live sessions. Section 14 pins its own socket on top of this.
host_sock=${TMUX:-}
host_sock=${host_sock%%,*}
unset TMUX TMUX_PANE
TMUX_TMPDIR="$tmp/tmux-default"
export TMUX_TMPDIR
mkdir -p "$TMUX_TMPDIR"

# rc_of <expected-rc> <label> -- <cmd...>: run the command with output
# suppressed and assert its exit code, without tripping `set -e`.
rc_of() {
  want="$1"
  label="$2"
  shift 3 # drop want, label, and the literal `--`
  rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "$want" ] || fail "$label: expected exit $want, got $rc"
}

# ---------------------------------------------------------------------------
# 1. validate-handle tmux: accept the real tmux target forms.
# ---------------------------------------------------------------------------
for h in "@3" "%5" "3" "main:1" "worker-window" \
  "planwright-orchestration-fleet-task-7" "session:worker.1"; do
  rc_of 0 "validate-handle tmux should accept '$h'" -- "$RELAY" validate-handle tmux "$h"
done
echo "ok: validate-handle tmux accepts the declared target grammar"

# ---------------------------------------------------------------------------
# 2. validate-handle tmux: reject every hostile handle. Each carries a shell
#    metacharacter, whitespace, an option-injection leading dash, a command
#    substitution, or is empty/over-length — none may reach a `-t` target.
# ---------------------------------------------------------------------------
big=$(printf 'a%.0s' $(seq 1 200))
# shellcheck disable=SC2016 # the $(...) and `...` are literal hostile handles, not expansions
for h in "" "-t" "a b" "a;b" "a|b" "a&b" 'a$(id)' 'a`id`' "a>b" "a<b" \
  "a*b" "a?b" 'a"b' "a'b" 'a\b' "a(b)" "a{b}" "a[b]" "a#b" "a!b" "$big"; do
  rc_of 2 "validate-handle tmux must reject hostile handle [$h]" -- \
    "$RELAY" validate-handle tmux "$h"
done
# A literal newline in the handle must also be refused.
rc_of 2 "validate-handle tmux must reject an embedded newline" -- \
  "$RELAY" validate-handle tmux "$(printf 'a\nb')"
echo "ok: validate-handle tmux rejects hostile handles (metachars, injection, over-length)"

# ---------------------------------------------------------------------------
# 3. validate-handle subagent: a stricter identifier grammar (no tmux id
#    sigils, colons, or slashes).
# ---------------------------------------------------------------------------
for h in "task-7" "worker_1" "unit.3"; do
  rc_of 0 "validate-handle subagent should accept '$h'" -- \
    "$RELAY" validate-handle subagent "$h"
done
# shellcheck disable=SC2016 # 'a$(id)' is a literal hostile handle, not an expansion
for h in "" "a:b" "@3" "%5" "a/b" "-x" "a b" "a;b" 'a$(id)'; do
  rc_of 2 "validate-handle subagent must reject '$h'" -- \
    "$RELAY" validate-handle subagent "$h"
done
echo "ok: validate-handle subagent enforces its stricter identifier grammar"

# ---------------------------------------------------------------------------
# 4. validate-handle: an unknown backend cannot be validated (fail closed).
# ---------------------------------------------------------------------------
rc_of 2 "validate-handle must reject an unknown backend" -- \
  "$RELAY" validate-handle frobnicate "@3"
echo "ok: validate-handle fails closed on an unknown backend"

# ---------------------------------------------------------------------------
# 5. relay-command tmux: emits this script's own `deliver` by literal path,
#    references the message FILE made absolute (never inlines its content),
#    and has NO send-keys path.
# ---------------------------------------------------------------------------
relay_dir=$(cd "$(dirname "$RELAY")" && pwd)
msg="$tmp/relay-msg.txt"
printf 'merge main into your branch and resolve conflicts, please.\n' >"$msg"
out=$("$RELAY" relay-command tmux "@3" "$msg") \
  || fail "relay-command tmux exited non-zero on a valid handle+message"
[ "$out" = "'$relay_dir/orchestrate-relay.sh' deliver tmux '@3' '$msg'" ] \
  || fail "relay-command tmux must emit the literal-path deliver invocation, got: $out"
case "$out" in
  *send-keys* | *"\$"*) fail "relay-command tmux must emit no send-keys path and no variable" ;;
  *) : ;;
esac
(cd "$tmp" && "$RELAY" relay-command tmux "@3" "relay-msg.txt") >"$tmp/rel.out" \
  || fail "relay-command tmux exited non-zero on a relative message path"
grep -qF "'$msg'" "$tmp/rel.out" \
  || fail "relay-command must emit the message path absolute, got: $(cat "$tmp/rel.out")"
echo "ok: relay-command tmux emits the literal-path deliver, message file absolute, no send-keys"

# ---------------------------------------------------------------------------
# 6. relay-command: message text is DATA. A message file full of shell
#    metacharacters must not appear inline in the emitted command — only the
#    file path is referenced, so nothing is ever spliced in as code.
# ---------------------------------------------------------------------------
danger="$tmp/danger-msg.txt"
# shellcheck disable=SC2016 # the substitution syntax is the literal message fixture, not an expansion
printf '%s\n' '$(rm -rf /); `whoami`; rm -rf ~' >"$danger"
out=$("$RELAY" relay-command tmux "@3" "$danger") \
  || fail "relay-command tmux exited non-zero on a metachar-laden message file"
case "$out" in
  *"rm -rf"*) fail "relay-command must NOT inline message content (no eval/expansion path)" ;;
  *) : ;;
esac
case "$out" in
  *"$danger"*) : ;;
  *) fail "relay-command must reference the message file path for a metachar message" ;;
esac
echo "ok: relay-command treats message text as data (file reference, never inlined)"

# ---------------------------------------------------------------------------
# 7. relay-command tmux: a hostile handle is rejected before any command is
#    built, and a missing/nonexistent message file fails closed.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # 'a$(id)' is a literal hostile handle, not an expansion
rc_of 2 "relay-command tmux must reject a hostile handle" -- \
  "$RELAY" relay-command tmux 'a$(id)' "$msg"
rc_of 2 "relay-command tmux must reject a missing message file" -- \
  "$RELAY" relay-command tmux "@3" "$tmp/does-not-exist.txt"
# A message-file PATH containing a single quote is the emission-boundary injection
# case: the path is interpolated into a single-quoted literal in the emitted
# `cat -- '<path>'`, so a `'` in the path would break out. valid_msgfile must
# reject it even though the file exists.
sq_msg="$tmp/msg'quote.txt"
printf 'body\n' >"$sq_msg"
rc_of 2 "relay-command tmux must reject a message-file path containing a single quote" -- \
  "$RELAY" relay-command tmux "@3" "$sq_msg"
echo "ok: relay-command tmux fails closed on a hostile handle, missing message file, or unsafe message-file path"

# ---------------------------------------------------------------------------
# 8. relay-command subagent: harness-native — no screen-scrape/send-keys
#    surface at all; empty stdout, exit 0.
# ---------------------------------------------------------------------------
out=$("$RELAY" relay-command subagent "task-7" "$msg") \
  || fail "relay-command subagent should exit 0 (harness-native)"
[ -z "$out" ] || fail "relay-command subagent must emit no shell relay command (stdout empty)"
echo "ok: relay-command subagent is harness-native (no shell relay command)"

# ---------------------------------------------------------------------------
# 9. observe-command tmux: the capture-pane observe-in-flight read, handle
#    validated, no send-keys.
# ---------------------------------------------------------------------------
out=$("$RELAY" observe-command tmux "%5") \
  || fail "observe-command tmux exited non-zero on a valid handle"
case "$out" in
  *"tmux capture-pane"*) : ;;
  *) fail "observe-command tmux must use tmux capture-pane (observe-in-flight)" ;;
esac
case "$out" in
  *"%5"*) : ;;
  *) fail "observe-command tmux must target the validated handle" ;;
esac
case "$out" in
  *send-keys*) fail "observe-command tmux must NEVER emit a send-keys path" ;;
  *) : ;;
esac
rc_of 2 "observe-command tmux must reject a hostile handle" -- \
  "$RELAY" observe-command tmux "a;id"
echo "ok: observe-command tmux emits a handle-validated capture-pane read"

# observe-command subagent: harness-native, like relay — empty stdout, exit 0.
out=$("$RELAY" observe-command subagent "task-7") \
  || fail "observe-command subagent should exit 0 (harness-native)"
[ -z "$out" ] || fail "observe-command subagent must emit no shell command (stdout empty)"
echo "ok: observe-command subagent is harness-native (no shell command)"

# relay/observe fail closed on an UNKNOWN backend — no command is emitted for a
# backend whose steer/observe mechanism is undeclared (never a guessed path).
rc_of 2 "relay-command must fail closed on an unknown backend" -- \
  "$RELAY" relay-command frobnicate "@3" "$msg"
rc_of 2 "observe-command must fail closed on an unknown backend" -- \
  "$RELAY" observe-command frobnicate "@3"
echo "ok: relay/observe fail closed on an unknown backend"

# ---------------------------------------------------------------------------
# 10. Source audit: the EXECUTABLE code contains no send-keys and no eval path —
#     the "no send-keys impersonation path exists" Done-when check made grep-able
#     against the artifact, not just asserted in prose. Comment lines are
#     stripped first so the doc block (which names the prohibition) is not itself
#     read as a violation; the audit targets code, not documentation.
# ---------------------------------------------------------------------------
code="$tmp/relay-code.sh"
grep -v '^[[:space:]]*#' "$RELAY" >"$code" || true
grep -q 'send-keys' "$code" && fail "executable code must contain no send-keys path"
grep -Eq '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)' "$code" \
  && fail "executable code must contain no eval path"
echo "ok: source audit — no send-keys and no eval path in the relay script's code"

# ---------------------------------------------------------------------------
# 11. Fail-closed usage: no subcommand, unknown subcommand, wrong arg count.
# ---------------------------------------------------------------------------
rc_of 2 "no subcommand must be a usage error" -- "$RELAY"
rc_of 2 "unknown subcommand must be a usage error" -- "$RELAY" frobnicate
rc_of 2 "validate-handle with no handle must be a usage error" -- "$RELAY" validate-handle tmux
rc_of 2 "relay-command with no handle must be a usage error" -- "$RELAY" relay-command tmux
rc_of 2 "relay-command with no message file must be a usage error" -- \
  "$RELAY" relay-command tmux "@3"
rc_of 2 "deliver with no handle must be a usage error" -- "$RELAY" deliver tmux
echo "ok: fail-closed usage errors"

# ---------------------------------------------------------------------------
# 12. Echo discipline (doctrine/security-posture.md): every untrusted value a
#     diagnostic echoes — the message-file path ($msg) and the backend name
#     ($backend) — must be run through echo-safety.sh's sanitizer, so an embedded
#     escape/control byte cannot drive the operator's terminal. And the
#     message-file guard must fail closed on an unreadable file and on a path
#     carrying a control byte (both would otherwise reach the emitted command).
# ---------------------------------------------------------------------------
esc=$(printf '\033')

# 12a. valid_msgfile hardening: an UNREADABLE regular file is refused (else the
#      emitted `cat -- '<path>'` fails at runtime).
unreadable="$tmp/unreadable-msg.txt"
printf 'body\n' >"$unreadable"
chmod 000 "$unreadable"
rc_of 2 "relay-command tmux must reject an unreadable message file" -- \
  "$RELAY" relay-command tmux "@3" "$unreadable"
chmod 644 "$unreadable"

# 12b. valid_msgfile hardening: an EXISTING message file whose PATH carries a
#      control byte is refused (the path is bound into the emitted command).
esc_path="$tmp/esc${esc}path.txt"
printf 'body\n' >"$esc_path"
[ -f "$esc_path" ] || fail "test setup: could not create control-byte message-file fixture"
rc_of 2 "relay-command tmux must reject a message-file path carrying a control byte" -- \
  "$RELAY" relay-command tmux "@3" "$esc_path"

# 12c. The reject diagnostic must not echo the raw control byte from the path.
#      Uses a MISSING path (rejected on the -f check even on the pre-fix script)
#      so the diagnostic fires regardless, isolating the echo-discipline defect.
esc_missing="$tmp/missing-${esc}-esc.txt"
errout=$("$RELAY" relay-command tmux "@3" "$esc_missing" 2>&1 1>/dev/null || true)
case "$errout" in
  *"$esc"*) fail "relay-command reject diagnostic must not echo a raw control byte from the message-file path" ;;
  *) : ;;
esac

# 12d. The unknown-backend diagnostics (relay and observe) must not echo the raw
#      control byte from $backend, and must still fail closed (exit 2).
bad_backend="frob${esc}nicate"
errout=$("$RELAY" relay-command "$bad_backend" "@3" "$msg" 2>&1 1>/dev/null || true)
case "$errout" in
  *"$esc"*) fail "relay-command unknown-backend diagnostic must not echo a raw control byte from \$backend" ;;
  *) : ;;
esac
rc_of 2 "relay-command must still fail closed on a control-byte backend" -- \
  "$RELAY" relay-command "$bad_backend" "@3" "$msg"
errout=$("$RELAY" observe-command "$bad_backend" "@3" 2>&1 1>/dev/null || true)
case "$errout" in
  *"$esc"*) fail "observe-command unknown-backend diagnostic must not echo a raw control byte from \$backend" ;;
  *) : ;;
esac
rc_of 2 "observe-command must still fail closed on a control-byte backend" -- \
  "$RELAY" observe-command "$bad_backend" "@3"
echo "ok: echo discipline — diagnostics sanitize untrusted paths/backends; msgfile guard rejects unreadable + control-byte paths"

# ---------------------------------------------------------------------------
# 13. deliver tmux, against a recording tmux whose pane is a file: the paste
#     appends the loaded buffer to the pane unless told to drop it.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/fakebin"
cat >"$tmp/fakebin/tmux" <<'EOF'
#!/bin/sh
d=$FAKE_TMUX_DIR
printf '%s\n' "$*" >>"$d/log"
case "$1" in
  capture-pane)
    [ -f "$d/capture-fails" ] && exit 1
    cat "$d/pane"
    ;;
  load-buffer)
    [ -f "$d/load-fails" ] && exit 1
    cat >"$d/buffer"
    ;;
  paste-buffer)
    [ -f "$d/paste-fails" ] && exit 1
    if [ -f "$d/paste-signals" ]; then
      kill -TERM "$PPID"
      exit 1
    fi
    if [ ! -f "$d/paste-drops" ]; then
      cat "$d/buffer" >>"$d/pane"
      printf '\n' >>"$d/pane"
    fi
    cp "$d/buffer" "$d/pasted"
    rm -f "$d/buffer"
    ;;
  delete-buffer) rm -f "$d/buffer" ;;
esac
exit 0
EOF
chmod +x "$tmp/fakebin/tmux"

idle_pane='● Done. Tests pass.

────────────────────────────────────────
❯ 
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents'

# fake_deliver <case-dir> <pane-text> [deliver args...]: reset the fake, run
# deliver, leave its stdout/stderr/rc in the case dir. FD_FLAGS names the
# fake's failure switches to set first (capture-fails, paste-drops, ...).
fake_deliver() {
  fd_dir="$tmp/$1"
  rm -rf "$fd_dir"
  mkdir -p "$fd_dir"
  printf '%s\n' "$2" >"$fd_dir/pane"
  : >"$fd_dir/log"
  for fd_flag in ${FD_FLAGS:-}; do
    touch "$fd_dir/$fd_flag"
  done
  shift 2
  fd_rc=0
  FAKE_TMUX_DIR="$fd_dir" PATH="$tmp/fakebin:$PATH" \
    PLANWRIGHT_RELAY_CONFIRM_TRIES="${FD_TRIES:-2}" PLANWRIGHT_RELAY_CONFIRM_SLEEP=0 \
    "$RELAY" deliver tmux "$@" >"$fd_dir/out" 2>"$fd_dir/err" || fd_rc=$?
  printf '%s\n' "$fd_rc" >"$fd_dir/rc"
}
rc_is() { [ "$(cat "$tmp/$1/rc")" = "$2" ] || fail "$3: expected exit $2, got $(cat "$tmp/$1/rc") ($(cat "$tmp/$1/err"))"; }
pasted_nothing() {
  grep -qE '^(load-buffer|paste-buffer)' "$tmp/$1/log" \
    && fail "$2: must paste nothing, tmux saw: $(cat "$tmp/$1/log")"
  return 0
}

# 13a. An idle input box: one unterminated attributed pointer line is pasted,
#      the body never is, and the tag seen in the pane confirms it (exit 0).
multi="$tmp/multi-line.txt"
printf 'line one\nline two\nline three\n' >"$multi"
fake_deliver idle "$idle_pane" "@3" "$multi"
rc_is idle 0 "deliver to an idle pane"
grep -q '^staged @3 (#' "$tmp/idle/out" || fail "deliver must report the staged tag, got: $(cat "$tmp/idle/out")"
tag=$(sed -n 's/^staged @3 (\(#[a-j-]*\)).*/\1/p' "$tmp/idle/out")
[ -n "$tag" ] || fail "could not read a letters-only tag from: $(cat "$tmp/idle/out")"
# The tag leads, so it sits at the start of the input box's first row however
# narrow the pane wraps, and the paste opens with no digit a dialog could take.
printf '%s' "($tag) [planwright tower relay -> @3] read $multi" >"$tmp/expected-paste.txt"
cmp -s "$tmp/idle/pasted" "$tmp/expected-paste.txt" \
  || fail "the pasted payload must be exactly the attributed pointer with its tag and no trailing newline, got: $(od -c "$tmp/idle/pasted" | tail -3)"
grep -q 'line two' "$tmp/idle/pasted" && fail "deliver must never paste the message body"
grep -q 'send-keys' "$tmp/idle/log" && fail "deliver must never call send-keys"
echo "ok: deliver pastes exactly one unterminated attributed pointer line and confirms it by its tag"

# 13b. Buffer name: the load and the paste name the same buffer within one
#      delivery, and two deliveries never share one (tmux buffers are
#      server-global, so a fixed name races across concurrent relays).
bufname_of() { sed -n "s/^$1 -b \([^ ]*\).*/\1/p" "$2"; }
lb1=$(bufname_of load-buffer "$tmp/idle/log")
pb1=$(bufname_of paste-buffer "$tmp/idle/log")
[ -n "$lb1" ] && [ "$lb1" = "$pb1" ] \
  || fail "deliver load and paste must name the same buffer (got '$lb1' vs '$pb1')"
fake_deliver idle2 "$idle_pane" "@3" "$multi"
rc_is idle2 0 "second deliver"
grep -q "^paste-buffer -b $lb1 .* -d\$" "$tmp/idle/log" \
  || fail "a successful paste must delete its buffer (paste-buffer -d), tmux saw: $(cat "$tmp/idle/log")"
lb2=$(bufname_of load-buffer "$tmp/idle2/log")
[ "$lb1" != "$lb2" ] || fail "deliver must use a buffer name unique per invocation (both were '$lb1')"
echo "ok: relay buffer name is unique per invocation and consistent within one"

# 13c. Refuse, pasting nothing, while a selection prompt is open: a permission
#      dialog, a select menu's footer, or the cursor on a numbered option.
perm_pane='  Bash command

    ./tests/test-fleet-liveness.sh

  Do you want to proceed?
  ❯ 1. Yes
    2. Yes, and don'"'"'t ask again for ./tests/ commands in this worktree
    3. No, and tell Claude what to do differently (esc)'
menu_pane='  Which approach?

  ❯ 1. Strict
    2. Lenient

  ↑/↓ to navigate · Enter to select · Esc to cancel'
cursor_pane='  Pick one
  ❯ 2. Second option
    3. Third option'
for c in perm menu cursor; do
  case "$c" in
    perm) pane=$perm_pane ;;
    menu) pane=$menu_pane ;;
    cursor) pane=$cursor_pane ;;
  esac
  fake_deliver "sel-$c" "$pane" "@3" "$msg"
  rc_is "sel-$c" 3 "deliver over an open selection prompt ($c)"
  pasted_nothing "sel-$c" "deliver over an open selection prompt ($c)"
  grep -q 'selection prompt' "$tmp/sel-$c/err" || fail "the $c refusal must name the selection prompt: $(cat "$tmp/sel-$c/err")"
done
echo "ok: deliver refuses, pasting nothing, while a selection prompt is open"

# 13d. Refuse while a multi-line paste placeholder sits staged in the box, and
#      when the pane cannot be read at all.
fake_deliver staged "$(printf '%s\n' '────' '❯ [Pasted text #1 +4 lines]' '────' '  ⏵⏵ auto mode on')" "@3" "$msg"
rc_is staged 3 "deliver over a staged paste placeholder"
pasted_nothing staged "deliver over a staged paste placeholder"
FD_FLAGS=capture-fails fake_deliver unreadable "$idle_pane" "@3" "$msg"
rc_is unreadable 3 "deliver over an unreadable pane"
pasted_nothing unreadable "deliver over an unreadable pane"
# A blank pane reads fine: unreadable means the capture failed, not that it
# came back empty.
fake_deliver blank "" "@3" "$msg"
rc_is blank 0 "deliver to a blank but readable pane"
echo "ok: deliver refuses a staged placeholder and an unreadable pane, not a blank one"

# 13d2. Refuse while an earlier relay sits unsubmitted in the input box: the
#       paste has no trailing newline, so a second one would join it on one
#       line and one Enter would submit both as a garbled path.
for form in "(#bc-de) [planwright tower relay -> @3] read /tmp/a.txt" \
  "[planwright tower relay -> @3] (#1-1) read /tmp/a.txt"; do
  fake_deliver staged-relay "$(printf '%s\n' '────' "❯ $form" '────' '  ⏵⏵ auto mode on')" "@3" "$msg"
  rc_is staged-relay 3 "deliver over an unsubmitted relay ($form)"
  pasted_nothing staged-relay "deliver over an unsubmitted relay"
  grep -q 'unsubmitted relay' "$tmp/staged-relay/err" || fail "the refusal must name the unsubmitted relay: $(cat "$tmp/staged-relay/err")"
done
# A relay already submitted sits in the transcript, above the input box's top
# rule; only the row right under that rule is the box, so it does not block.
fake_deliver sent-relay "❯ (#bc-de) [planwright tower relay -> @3] read /tmp/a.txt
$idle_pane" "@3" "$msg"
rc_is sent-relay 0 "deliver after a relay already submitted to the transcript"
echo "ok: deliver refuses to join an unsubmitted relay in the input box, not one already sent"

# 13e. Delivery is confirmed, never assumed: a paste that never shows its tag
#      is exit 4, and an earlier relay of the same file still on screen does
#      not pass for this one.
stale_pane="$idle_pane
[planwright tower relay -> @3] (#1-1) read $msg"
FD_TRIES=3 FD_FLAGS=paste-drops fake_deliver dropped "$stale_pane" "@3" "$msg"
rc_is dropped 4 "a paste whose tag never shows"
grep -q 'not confirmed' "$tmp/dropped/err" || fail "the unconfirmed diagnostic must say so: $(cat "$tmp/dropped/err")"
[ "$(grep -c '^capture-pane' "$tmp/dropped/log")" -ge 4 ] \
  || fail "deliver must re-read the pane for each confirmation try"
# The tries knob is bounded so the worst-case wait stays under a minute, short
# of a caller's two-minute command timeout: past the cap, or not an integer,
# it takes the default (one capture before the paste plus one per try).
for knob in 20:21 21:6 x:6 0:6 -1:6; do
  FD_TRIES=${knob%%:*} FD_FLAGS=paste-drops fake_deliver "clamp" "$idle_pane" "@3" "$msg"
  [ "$(grep -c '^capture-pane' "$tmp/clamp/log")" = "${knob##*:}" ] \
    || fail "PLANWRIGHT_RELAY_CONFIRM_TRIES=${knob%%:*} must make ${knob##*:} captures, got $(grep -c '^capture-pane' "$tmp/clamp/log")"
done
FD_FLAGS=paste-fails fake_deliver pastefail "$idle_pane" "@3" "$msg"
rc_is pastefail 4 "a failed paste-buffer"
grep -q '^delete-buffer -b planwright-relay-' "$tmp/pastefail/log" \
  || fail "a failed paste must delete its buffer, tmux saw: $(cat "$tmp/pastefail/log")"
# A deliver killed between the load and the paste must not leave its buffer,
# which holds the relay text, on the shared server.
FD_FLAGS=paste-signals fake_deliver signalled "$idle_pane" "@3" "$msg"
[ "$(cat "$tmp/signalled/rc")" != 0 ] || fail "a signalled deliver must not report success"
grep -q '^delete-buffer -b planwright-relay-' "$tmp/signalled/log" \
  || fail "a signalled deliver must delete its buffer, tmux saw: $(cat "$tmp/signalled/log")"
FD_FLAGS=load-fails fake_deliver loadfail "$idle_pane" "@3" "$msg"
rc_is loadfail 3 "a failed load-buffer"
grep -q '^paste-buffer' "$tmp/loadfail/log" && fail "a failed load must paste nothing"
echo "ok: deliver confirms by a fresh tag and reports an unseen paste as not confirmed"

# 13f. deliver validates like relay-command: tmux only, handle and message
#      file checked before any tmux call.
# shellcheck disable=SC2016 # 'a$(id)' is a literal hostile handle, not an expansion
fake_deliver hostile "$idle_pane" 'a$(id)' "$msg"
rc_is hostile 2 "deliver with a hostile handle"
[ -s "$tmp/hostile/log" ] && fail "deliver must not call tmux for a hostile handle"
fake_deliver nofile "$idle_pane" "@3" "$tmp/does-not-exist.txt"
rc_is nofile 2 "deliver with a missing message file"
rc_of 2 "deliver refuses a non-tmux backend" -- "$RELAY" deliver stream-json "fg-task-7" "$msg"
rc_of 2 "deliver with no message file is a usage error" -- "$RELAY" deliver tmux "@3"
(cd "$tmp" && fake_deliver relpath "$idle_pane" "@3" "relay-msg.txt")
rc_is relpath 0 "deliver with a relative message path"
grep -qF " read $msg" "$tmp/relpath/pasted" \
  || fail "deliver must paste the message path absolute, got: $(cat "$tmp/relpath/pasted")"
echo "ok: deliver validates its backend, handle, and message file before touching tmux"

# 13g. A vocabulary file that sources but lacks the refusal checks fails
#      closed: without them every check would read "no dialog" and paste.
broken="$tmp/broken-install"
mkdir -p "$broken"
cp "$RELAY" "$here/../scripts/echo-safety.sh" "$broken/"
printf '%s\n' '# a vocabulary from an older install, without the refusal checks' >"$broken/fleet-pane-vocabulary.sh"
mkdir -p "$tmp/broken-fake"
printf '%s\n' "$perm_pane" >"$tmp/broken-fake/pane"
: >"$tmp/broken-fake/log"
rc=0
FAKE_TMUX_DIR="$tmp/broken-fake" PATH="$tmp/fakebin:$PATH" \
  "$broken/orchestrate-relay.sh" deliver tmux "@3" "$msg" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a vocabulary without the refusal checks must exit 2, got $rc"
grep -qE '^(load-buffer|paste-buffer)' "$tmp/broken-fake/log" \
  && fail "a vocabulary without the refusal checks must paste nothing"
echo "ok: deliver fails closed when the pane vocabulary lacks its refusal checks"

# ---------------------------------------------------------------------------
# 14. deliver against a real tmux server whose pane runs `cat`: the paste must
#     show up and be confirmed, end to end. Every tmux call here, the test's
#     and deliver's, goes through a wrapper that pins an explicit socket and
#     unsets TMUX: tmux honours $TMUX over TMUX_TMPDIR, so from inside a tmux
#     pane a TMUX_TMPDIR-only "isolation" reaches the host's server, and a
#     kill-server there ends every session on the machine. The socket each
#     call resolves to is checked before deliver runs and before any kill.
# ---------------------------------------------------------------------------
if host_tmux=$(command -v tmux 2>/dev/null); then
  # A short fixed parent keeps the socket path under the Unix socket length
  # limit whatever TMPDIR is.
  iso_dir=$(mktemp -d /tmp/pwrelay.XXXXXX) || fail "could not make the isolated socket directory"
  trap 'rm -rf "$tmp" "$iso_dir"' EXIT
  iso_sock="$iso_dir/sock"
  [ "$iso_sock" != "$host_sock" ] || fail "the isolated socket path equals the host's \$TMUX socket"
  mkdir -p "$tmp/isobin"
  cat >"$tmp/isobin/tmux" <<EOF
#!/bin/sh
exec env -u TMUX -u TMUX_PANE '$host_tmux' -S '$iso_sock' "\$@"
EOF
  chmod +x "$tmp/isobin/tmux"
  iso_tmux="$tmp/isobin/tmux"
  # A failing check below exits through the trap; the wrapper pins the socket,
  # so this kill can only reach the isolated server.
  # The kill fails once the server is gone, so it must not decide the exit status.
  trap '"$iso_tmux" kill-server >/dev/null 2>&1 || :; rm -rf "$tmp" "$iso_dir"' EXIT
  "$iso_tmux" -f /dev/null new-session -d -s relaytest -x 200 -y 30 cat \
    || fail "could not start an isolated tmux server for the end-to-end check"
  resolved=$("$iso_tmux" display-message -p -t relaytest '#{socket_path}') \
    || fail "could not read the isolated server's socket path"
  [ "$resolved" = "$iso_sock" ] && [ "$resolved" != "$host_sock" ] \
    || fail "the end-to-end tmux resolved to $resolved, not the isolated $iso_sock"
  # deliver runs a bare `tmux`, which must find the wrapper first on its PATH.
  resolved=$(PATH="$tmp/isobin:$PATH" tmux display-message -p '#{socket_path}') \
    && [ "$resolved" = "$iso_sock" ] \
    || fail "a bare tmux on deliver's PATH resolved to ${resolved:-nothing}, not the isolated $iso_sock"
  rc=0
  out=$(PATH="$tmp/isobin:$PATH" PLANWRIGHT_RELAY_CONFIRM_TRIES=10 \
    "$RELAY" deliver tmux relaytest "$msg" 2>&1) || rc=$?
  "$iso_tmux" kill-server >/dev/null 2>&1 || :
  [ "$rc" = 0 ] || fail "deliver to a real tmux pane: expected exit 0, got $rc: $out"
  echo "ok: deliver stages and confirms a paste in a real, socket-isolated tmux pane"
else
  echo "skip: tmux not installed, end-to-end deliver check not run"
fi

# ---------------------------------------------------------------------------
# 15. stream-json: the sanctioned unattended steer path. relay-command emits the
#     sibling supervisor's `steer` by its literal path with the message file as
#     data; observe-command emits its `status`; the handle grammar is enforced.
# ---------------------------------------------------------------------------
sj_dir=$(cd "$(dirname "$RELAY")" && pwd)
out=$("$RELAY" relay-command stream-json "fg-task-7" "$msg") \
  || fail "relay-command stream-json exited non-zero on a valid handle+message"
[ "$out" = "'$sj_dir/fleet-streamjson.sh' steer 'fg-task-7' --message-file '$msg'" ] \
  || fail "relay-command stream-json must emit the literal-path steer invocation, got: $out"
case "$out" in
  *send-keys* | *paste-buffer* | *"\$"*) fail "relay-command stream-json must emit no paste, no send-keys, no variable" ;;
  *) : ;;
esac
out=$("$RELAY" observe-command stream-json "fg-task-7") \
  || fail "observe-command stream-json exited non-zero"
[ "$out" = "'$sj_dir/fleet-streamjson.sh' status 'fg-task-7'" ] \
  || fail "observe-command stream-json must emit the literal-path status read, got: $out"
rc_of 0 "validate-handle stream-json accepts the supervisor handle grammar" -- \
  "$RELAY" validate-handle stream-json "worker.v2@host-1"
# shellcheck disable=SC2016 # '$(id)' is a literal hostile handle, not an expansion
for bad in "fg task" "a:b" "x=y" "a/b" "-h" '$(id)' "%1" . ..; do
  rc_of 2 "validate-handle stream-json must reject '$bad'" -- \
    "$RELAY" validate-handle stream-json "$bad"
done
rc_of 2 "relay-command stream-json must reject a missing message file" -- \
  "$RELAY" relay-command stream-json "fg-task-7" "$tmp/does-not-exist.txt"
echo "ok: stream-json relay/observe emit the supervisor's steer/status by literal path; handle grammar enforced"

echo "PASS: test-orchestrate-relay.sh"
