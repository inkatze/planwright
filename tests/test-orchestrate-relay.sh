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
#   - `relay-command <backend> <handle> <message-file>` emits the ATTRIBUTED,
#     buffer-paste relay command (tmux `load-buffer`/`paste-buffer`) — never a
#     `send-keys` impersonation path (REQ-D1.3). The message is delivered as
#     DATA: the emitted command references the message FILE, never inlines its
#     content, so worker/tower message text is never spliced into the command as
#     code (REQ-B1.7: worker output is data, no eval/expansion path). subagent
#     is harness-native (no screen-scrape surface): empty stdout, exit 0.
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
# 5. relay-command tmux: emits the attributed buffer-paste command, references
#    the message FILE (never inlines its content), and has NO send-keys path.
# ---------------------------------------------------------------------------
msg="$tmp/relay-msg.txt"
printf 'merge main into your branch and resolve conflicts, please.\n' >"$msg"
out=$("$RELAY" relay-command tmux "@3" "$msg") \
  || fail "relay-command tmux exited non-zero on a valid handle+message"
case "$out" in
  *"tmux load-buffer"*) : ;;
  *) fail "relay-command tmux must use tmux load-buffer (buffer-paste mechanism)" ;;
esac
case "$out" in
  *"tmux paste-buffer"*) : ;;
  *) fail "relay-command tmux must use tmux paste-buffer (buffer-paste mechanism)" ;;
esac
case "$out" in
  *"$msg"*) : ;;
  *) fail "relay-command tmux must reference the message FILE (data, not inlined)" ;;
esac
case "$out" in
  *"@3"*) : ;;
  *) fail "relay-command tmux must target the validated handle" ;;
esac
case "$out" in
  *send-keys*) fail "relay-command tmux must NEVER emit a send-keys path" ;;
  *) : ;;
esac
# Attribution: pin the human-visible, tower-marked header naming the target
# direction — the actual non-impersonation marker (REQ-D1.3), NOT merely the
# internal `planwright-relay` buffer name (a bare `*planwright*relay*` glob would
# pass on the buffer name alone even if the visible header were deleted).
case "$out" in
  *"[planwright tower relay -> @3]"*) : ;;
  *) fail "relay-command tmux must emit the attributed, target-named header ([planwright tower relay -> @3])" ;;
esac
echo "ok: relay-command tmux emits an attributed buffer-paste command, no send-keys"

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
rc_of 2 "relay-command with no message file must be a usage error" -- \
  "$RELAY" relay-command tmux "@3"
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

echo "PASS: test-orchestrate-relay.sh"
