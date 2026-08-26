#!/bin/bash
# Tests for scripts/check-hook-contracts.sh and the payload fixtures beside it
# (fleet-lifecycle-closure Task 2; D-11; REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-K1.1).
#
# The incident these pin: planwright registered a passive tracker on
# `WorktreeCreate`, an event whose silence REFUSES the operation rather than
# waving it through. The tracker read `worktree_path` from a payload carrying
# `name`, echoed nothing, exited 0 — and worktree creation broke on every
# installed machine, explained only on stderr the harness discards.
#
# Two independent things have to hold for that to be unrepeatable, so the file
# is in two halves:
#
#   1. FIXTURE PINS. Each event's own key set, asserted exactly, so a schema
#      divergence fails here instead of in the fleet. The
#      `WorktreeCreate`(`name`) / `WorktreeRemove`(`worktree_path`) asymmetry is
#      asserted in BOTH directions — the back-fill that caused the outage would
#      have tripped the negative half.
#   2. GUARD BEHAVIOUR. The check itself, driven by deliberately broken
#      registrations built in a temp dir. Every named refusal gets a failing
#      fixture and the repo's own wiring must pass, so the guard's scope is
#      pinned in both directions rather than only proven permissive.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GUARD="$REPO_ROOT/scripts/check-hook-contracts.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/hook-payloads"

failures=0
assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  # assert_not_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpectedly contains '$2')" >&2
      printf '%s\n' "$3" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}
assert_absent() {
  # assert_absent <label> <path> — the marker file a hook writes when it sees
  # something it should not have been handed.
  if [ ! -e "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (marker $2 was created)" >&2
    failures=$((failures + 1))
  fi
}
assert_eq() {
  # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1" >&2
    echo "  expected: $2" >&2
    echo "  actual:   $3" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$GUARD" ]; then
  echo "FAIL: guard script missing at $GUARD" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq is not on PATH; these tests parse JSON fixtures with it"
  exit 0
fi

TMP=$(mktemp -d) || {
  echo "FAIL: mktemp -d" >&2
  exit 1
}
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---------------------------------------------------------------------------
# 1. Fixture pins — each event's own keys, exactly.
# ---------------------------------------------------------------------------
# Event-specific keys only: the shared envelope (session_id, transcript_path,
# cwd, permission_mode, hook_event_name) is asserted once, separately, so a
# change to one event's payload names that event in the failure rather than
# every row at once.
own_keys() {
  # own_keys <event> — the fixture's keys minus the shared envelope, sorted.
  jq -r '
    del(.session_id, .transcript_path, .cwd, .permission_mode, .hook_event_name)
    | keys_unsorted | sort | join(",")
  ' "$FIXTURES/$1.json" 2>/dev/null
}

# Read out of the CLI payload construction sites, identical across 2.1.226 /
# 2.1.237 / 2.1.239 / 2.1.241. See the fixture README for the derivation
# command; re-run it when a fixture below stops matching.
assert_eq "PreToolUse own keys" \
  "tool_input,tool_name,tool_use_id" "$(own_keys PreToolUse)"
assert_eq "PostToolUse own keys" \
  "duration_ms,tool_input,tool_name,tool_response,tool_use_id" "$(own_keys PostToolUse)"
assert_eq "SessionStart own keys" \
  "agent_type,model,session_title,source" "$(own_keys SessionStart)"
assert_eq "SessionEnd own keys" \
  "reason" "$(own_keys SessionEnd)"
assert_eq "Stop own keys" \
  "last_assistant_message,stop_hook_active" "$(own_keys Stop)"
assert_eq "StopFailure own keys" \
  "error,error_details,last_assistant_message" "$(own_keys StopFailure)"
assert_eq "Notification own keys" \
  "message,notification_type,title" "$(own_keys Notification)"
assert_eq "PermissionRequest own keys" \
  "permission_suggestions,tool_input,tool_name" "$(own_keys PermissionRequest)"

# The asymmetry the outage was built on, asserted in both directions.
assert_eq "WorktreeCreate own keys are exactly {name}" \
  "name" "$(own_keys WorktreeCreate)"
assert_eq "WorktreeRemove own keys are exactly {worktree_path}" \
  "worktree_path" "$(own_keys WorktreeRemove)"
assert_eq "WorktreeCreate carries no worktree_path (the back-fill that broke creation)" \
  "null" "$(jq -r '.worktree_path // "null"' "$FIXTURES/WorktreeCreate.json")"
assert_eq "WorktreeRemove carries no name" \
  "null" "$(jq -r '.name // "null"' "$FIXTURES/WorktreeRemove.json")"

# Every fixture carries the shared envelope and self-identifies, so a fixture
# can be piped into a handler as-is.
for f in "$FIXTURES"/*.json; do
  ev=$(basename "$f" .json)
  got=$(jq -r '[.session_id, .transcript_path, .cwd, .permission_mode] | map(select(. != null)) | length' "$f" 2>/dev/null)
  assert_eq "$ev fixture carries the 4-field shared envelope" "4" "$got"
  assert_eq "$ev fixture self-identifies via hook_event_name" \
    "$ev" "$(jq -r '.hook_event_name // ""' "$f")"
done

# ---------------------------------------------------------------------------
# 2. Guard behaviour.
# ---------------------------------------------------------------------------

# The repo's own wiring must pass. This is the assertion that would have failed
# while `WorktreeCreate` was registered to a passive tracker.
out=$("$GUARD" 2>&1)
rc=$?
assert_exit "repo's own registrations and fixtures pass" 0 "$rc"
assert_contains "a passing run says so" "hook-contracts" "$out"

# planwright registers hooks in three places, not one: the plugin-global
# hooks.json plus the worker and tower settings fragments, which each wire a
# PreToolUse command guard. A guard that read only hooks.json would report
# clean over two thirds of the surface it claims to cover.
assert_contains "the plugin-global registration file is checked" "hooks/hooks.json" "$out"
assert_contains "the worker settings fragment is checked" "worker-settings.json" "$out"
assert_contains "the tower settings fragment is checked" "tower-settings.json" "$out"

# Helper: write a hooks.json registering one event at one command.
write_hooks() {
  # write_hooks <path> <event> <command>
  jq -n --arg e "$2" --arg c "$3" \
    '{hooks: {($e): [{hooks: [{type: "command", command: $c}]}]}}' >"$1"
}

# -- REQ-H1.2, the outage rule: a silence-refuses event registered to a hook
#    that is not declared its implementer. This is the exact shape that broke
#    worktree creation fleet-wide.
mkdir -p "$TMP/outage"
cat >"$TMP/outage/tracker.sh" <<'SH'
#!/bin/sh
# A passive tracker: reads stdin, records nothing anyone can see, exits 0.
cat >/dev/null 2>&1
exit 0
SH
chmod +x "$TMP/outage/tracker.sh"
write_hooks "$TMP/outage/hooks.json" WorktreeCreate "$TMP/outage/tracker.sh"
out=$("$GUARD" --hooks "$TMP/outage/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "registering WorktreeCreate to a passive hook is refused" 1 "$rc"
assert_contains "the refusal names the event" "WorktreeCreate" "$out"
assert_contains "the refusal explains that silence refuses the operation" "silence" "$out"

# -- REQ-H1.2, first clause: a decision-control hook that exits 0 without
#    producing its event's required output. The deliberately broken fixture the
#    test-spec asks for.
mkdir -p "$TMP/silent"
cat >"$TMP/silent/silent-guard.sh" <<'SH'
#!/bin/sh
cat >/dev/null 2>&1
exit 0
SH
chmod +x "$TMP/silent/silent-guard.sh"
write_hooks "$TMP/silent/hooks.json" WorktreeCreate "$TMP/silent/silent-guard.sh"
out=$("$GUARD" --hooks "$TMP/silent/hooks.json" --fixtures "$FIXTURES" \
  --implementer WorktreeCreate 2>&1)
rc=$?
assert_exit "a declared implementer that emits nothing is flagged" 1 "$rc"
assert_contains "the finding names the missing output" "no worktree path" "$out"

# -- and the same hook, corrected, passes: the guard is not merely refusing
#    everything on that event.
mkdir -p "$TMP/creator"
cat >"$TMP/creator/creator.sh" <<'SH'
#!/bin/sh
in=$(cat 2>/dev/null)
name=$(printf '%s' "$in" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$name" ] || exit 0
printf '%s\n' "/tmp/worktrees/$name"
exit 0
SH
chmod +x "$TMP/creator/creator.sh"
write_hooks "$TMP/creator/hooks.json" WorktreeCreate "$TMP/creator/creator.sh"
out=$("$GUARD" --hooks "$TMP/creator/hooks.json" --fixtures "$FIXTURES" \
  --implementer WorktreeCreate 2>&1)
rc=$?
assert_exit "a declared implementer that emits a path passes" 0 "$rc"

# -- a decision hook emitting JSON that names the WRONG event. Silent
#    misrouting: the harness ignores the block and the author believes it fired.
mkdir -p "$TMP/misnamed"
cat >"$TMP/misnamed/misnamed.sh" <<'SH'
#!/bin/sh
cat >/dev/null 2>&1
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","permissionDecision":"deny","permissionDecisionReason":"nope"}}'
exit 0
SH
chmod +x "$TMP/misnamed/misnamed.sh"
write_hooks "$TMP/misnamed/hooks.json" PreToolUse "$TMP/misnamed/misnamed.sh"
out=$("$GUARD" --hooks "$TMP/misnamed/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "decision JSON naming the wrong event is flagged" 1 "$rc"
assert_contains "the finding names the mismatch" "hookEventName" "$out"

# -- a decision hook emitting output that is not JSON at all.
mkdir -p "$TMP/garbage"
cat >"$TMP/garbage/garbage.sh" <<'SH'
#!/bin/sh
cat >/dev/null 2>&1
printf '%s\n' 'refusing: something went wrong'
exit 0
SH
chmod +x "$TMP/garbage/garbage.sh"
write_hooks "$TMP/garbage/hooks.json" PreToolUse "$TMP/garbage/garbage.sh"
out=$("$GUARD" --hooks "$TMP/garbage/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "non-JSON output on a decision event is flagged" 1 "$rc"

# -- the hook is run AS REGISTERED, arguments included. Every liveness hook is
#    registered as `fleet-liveness.sh hook <event>`; a guard that ran the bare
#    script would be checking an invocation the harness never makes, and would
#    report clean over a handler it never actually exercised.
mkdir -p "$TMP/args"
cat >"$TMP/args/argecho.sh" <<'SH'
#!/bin/sh
cat >/dev/null 2>&1
# Emits a well-formed PreToolUse decision only when handed its registered
# argument; otherwise it names the wrong event and the guard must flag it.
if [ "${1:-}" = "expected-arg" ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse"}}'
else
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"WRONG-no-args-passed"}}'
fi
exit 0
SH
chmod +x "$TMP/args/argecho.sh"
write_hooks "$TMP/args/hooks.json" PreToolUse "$TMP/args/argecho.sh expected-arg"
out=$("$GUARD" --hooks "$TMP/args/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "the hook is run with its registered arguments" 0 "$rc"
assert_not_contains "the argument actually reached the hook" "WRONG-no-args-passed" "$out"

# -- running a hook must not mutate live fleet state. The guard runs inside
#    `mise run check`, which runs inside dispatched workers, where
#    PLANWRIGHT_WORKER_HANDLE/SCOPE are set — so an un-neutralised run would
#    have real handlers push liveness transitions for the worker running CI,
#    corrupting the attention surface the operator reads.
mkdir -p "$TMP/env"
cat >"$TMP/env/leak.sh" <<SH
#!/bin/sh
cat >/dev/null 2>&1
[ -n "\${PLANWRIGHT_WORKER_HANDLE:-}" ] && : >"$TMP/env/saw-handle"
[ -n "\${PLANWRIGHT_WORKER_SCOPE:-}" ] && : >"$TMP/env/saw-scope"
case "\${PLANWRIGHT_FLEET_STATE_DIR:-}" in
  "" ) : >"$TMP/env/saw-shared-state" ;;
esac
exit 0
SH
chmod +x "$TMP/env/leak.sh"
write_hooks "$TMP/env/hooks.json" PreToolUse "$TMP/env/leak.sh"
PLANWRIGHT_WORKER_HANDLE=exec-test-1 PLANWRIGHT_WORKER_SCOPE=demo:1 \
  "$GUARD" --hooks "$TMP/env/hooks.json" --fixtures "$FIXTURES" >/dev/null 2>&1
assert_absent "the worker handle is not passed through to a hook the guard runs" \
  "$TMP/env/saw-handle"
assert_absent "the worker scope is not passed through to a hook the guard runs" \
  "$TMP/env/saw-scope"
assert_absent "hooks the guard runs are pointed at a scratch fleet state dir" \
  "$TMP/env/saw-shared-state"

# -- REQ-H1.1: a registered event with no fixture cannot be checked, so the
#    guard refuses rather than passing it.
mkdir -p "$TMP/nofixture"
mkdir -p "$TMP/nofixture/fixtures"
cp "$FIXTURES/PreToolUse.json" "$TMP/nofixture/fixtures/"
write_hooks "$TMP/nofixture/hooks.json" Stop "$TMP/silent/silent-guard.sh"
out=$("$GUARD" --hooks "$TMP/nofixture/hooks.json" --fixtures "$TMP/nofixture/fixtures" 2>&1)
rc=$?
assert_exit "a registered event with no payload fixture is refused" 1 "$rc"
assert_contains "the finding names the missing fixture" "fixture" "$out"

# -- fail closed on an event the contract table does not model: an unknown
#    event's silence semantics are exactly what cannot be assumed.
mkdir -p "$TMP/unknown"
write_hooks "$TMP/unknown/hooks.json" TeammateIdle "$TMP/silent/silent-guard.sh"
out=$("$GUARD" --hooks "$TMP/unknown/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "an unmodelled event fails closed" 1 "$rc"
assert_contains "the finding names the unmodelled event" "TeammateIdle" "$out"

# -- fail closed on input the guard cannot read, rather than passing vacuously.
printf '%s\n' '{ not json' >"$TMP/broken.json"
out=$("$GUARD" --hooks "$TMP/broken.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "an unparseable hooks.json fails closed" 2 "$rc"
out=$("$GUARD" --hooks "$TMP/does-not-exist.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "a missing hooks.json fails closed" 2 "$rc"
out=$("$GUARD" --hooks "$REPO_ROOT/hooks/hooks.json" --fixtures "$TMP/no-such-dir" 2>&1)
rc=$?
assert_exit "a missing fixture directory fails closed" 2 "$rc"

# -- a registered command whose script is absent: the harness would report a
#    hook failure with no way to tell a typo from a deleted file.
mkdir -p "$TMP/absent"
write_hooks "$TMP/absent/hooks.json" Stop "$TMP/absent/not-here.sh"
out=$("$GUARD" --hooks "$TMP/absent/hooks.json" --fixtures "$FIXTURES" 2>&1)
rc=$?
assert_exit "a registered command that does not exist is flagged" 1 "$rc"

# ---------------------------------------------------------------------------
# 3. REQ-H1.3 / REQ-K1.1 — refusals are legible.
# ---------------------------------------------------------------------------
# Every finding the guard emits has to name what could not be established and
# what to do about it. A bare "FAIL" reproduces the diagnosis cost that made
# the original outage take a binary inspection to root-cause.
out=$("$GUARD" --hooks "$TMP/outage/hooks.json" --fixtures "$FIXTURES" 2>&1)
assert_contains "a finding carries a remedy" "remedy:" "$out"
assert_not_contains "findings are not bare failure markers" "FAIL: unknown" "$out"

# ---------------------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
  echo "PASS: check-hook-contracts"
  exit 0
fi
echo "FAIL: $failures assertion(s) failed" >&2
exit 1
