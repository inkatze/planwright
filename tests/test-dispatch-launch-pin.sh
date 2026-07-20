#!/bin/bash
# Tests for the ghost-text pin in the dispatch launch primitive
# (fleet-hardening Task 5; D-5, REQ-B1.1, REQ-B1.2, REQ-E1.3).
#
# The worker launch construction applies CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=
# false as a CODE PATH: `fleet-dispatch-env.sh --emit-launch <launch-argv>`
# deterministically constructs the pin-carrying wrapped launch command, so the
# pin is a structural property of dispatch (the wrapper prefix is emitted by the
# primitive), never a SKILL-prose instruction the model must remember to apply.
# The emitted shape is one the worker-command-guard auto-approves (its verb is a
# repo-contained scripts/*.sh, trusted by REQ-A1.10 of worker-permission-
# ergonomics), so the pin-carrying launch never floods the worker with
# permission prompts and never falls back to the 2026-07-19 BARE launch that
# dropped the pin (D-5).
#
# Coverage (mapped to the task Done-when):
#   c1 (REQ-B1.1): the emitted launch, when run, sets the ghost-text var on the
#      LAUNCHED process — the pin is applied by the primitive's construction,
#      asserted without any SKILL-prose step in the path.
#   c2 (REQ-B1.2): the emitted (wrapped) launch command is auto-approved by the
#      worker-command-guard decision path (no permission prompt/flood).
#   c3 (REQ-B1.2 regression): the 2026-07-19 bare-launch shape is NOT the
#      auto-approved path (the guard defers it) — the wrapped shape replaces it.
#   c4 (REQ-E1.3): no model/API call in the launch-construction decision path.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-dispatch-launch-pin.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
FDE="$REPO_ROOT/scripts/fleet-dispatch-env.sh"
GUARD="$REPO_ROOT/scripts/worker-command-guard.sh"
VAR=CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION

failures=0
GOUT=""

pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

[ -x "$FDE" ] || {
  echo "FAIL: $FDE missing or not executable" >&2
  exit 1
}
[ -x "$GUARD" ] || {
  echo "FAIL: $GUARD missing or not executable" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

# run_guard <command>: feed <command> through the worker-command-guard PreToolUse
# decision path with a cwd inside this repo (so a repo-contained script verb
# resolves in-repo) and capture its stdout into GOUT. The guard emits an `allow`
# object for an auto-approved shape and nothing (defer) otherwise.
run_guard() {
  local payload
  payload=$(jq -n --arg c "$1" --arg w "$REPO_ROOT" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $w}')
  GOUT=$(printf '%s' "$payload" | /bin/bash "$GUARD" 2>/dev/null)
}
is_allow() { printf '%s' "$GOUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"'; }
is_defer() { [ -z "$(printf '%s' "$GOUT" | tr -d '[:space:]')" ]; }

# --- c1: the emitted launch pins the var on the launched process (REQ-B1.1) ---
# The constructor emits "<wrapper-abs> <launch words...>". Executing it launches
# the (stand-in) worker THROUGH the wrapper, which pins the var into the
# launched process's environment. `claude` is stood in for by a script that
# prints the value it actually sees, so the assertion is on the LAUNCHED
# process's environment (the test-spec REQ-B1.1 inspection), with no prose step.
c1() {
  local tmp fake emitted out
  tmp=$(mktemp -d) || {
    fail "c1: mktemp failed"
    return
  }
  fake="$tmp/fake-claude.sh"
  cat >"$fake" <<EOF
#!/bin/sh
printf 'seen=%s\n' "\${$VAR-<unset>}"
EOF
  chmod +x "$fake"
  emitted=$("$FDE" --emit-launch "$fake" --worktree task-5 --model opus) || {
    fail "c1: --emit-launch exited nonzero"
    rm -rf "$tmp"
    return
  }
  # Structural: the emitted line begins with the wrapper's own path — the pin
  # prefix is emitted by CODE, not assembled by the model.
  case $emitted in
    "$FDE "*) ;;
    *)
      fail "c1: emitted launch does not begin with the wrapper prefix: $emitted"
      rm -rf "$tmp"
      return
      ;;
  esac
  # End-to-end: running the emitted launch pins the var on the launched process.
  out=$(sh -c "$emitted") || {
    fail "c1: running the emitted launch failed"
    rm -rf "$tmp"
    return
  }
  if printf '%s\n' "$out" | grep -qx "seen=false"; then
    pass "c1: emitted launch pins $VAR=false on the launched process (REQ-B1.1)"
  else
    fail "c1: launched process did not see $VAR=false, got: $out"
  fi
  rm -rf "$tmp"
}

# --- c2: the wrapped launch shape is auto-approved by the guard (REQ-B1.2) -----
c2() {
  local emitted
  emitted=$("$FDE" --emit-launch claude --worktree task-5 --model opus /execute-task 5) || {
    fail "c2: --emit-launch exited nonzero"
    return
  }
  run_guard "$emitted"
  if is_allow; then
    pass "c2: emitted wrapped launch is auto-approved by worker-command-guard (REQ-B1.2)"
  else
    fail "c2: emitted wrapped launch was NOT auto-approved (no flood-free path); guard emitted: '${GOUT:-<defer>}'"
  fi
}

# --- c3: the 2026-07-19 bare-launch shape is NOT the auto-approved path --------
# The bare launch (no wrapper, `--permission-mode auto`) is the fallback that
# dropped the pin. Its verb is `claude` — not an enumerated safe shape — so the
# guard defers it: it is not the path taken; the wrapped shape (c2) is.
c3() {
  run_guard "claude --worktree task-5 --tmux=classic --model opus --permission-mode auto"
  if is_defer; then
    pass "c3: the 2026-07-19 bare-launch shape is not auto-approved — replaced by the wrapped shape (REQ-B1.2)"
  else
    fail "c3: the bare-launch shape was unexpectedly auto-approved: '$GOUT'"
  fi
}

# --- c4: no model/API call in the launch-construction decision path (E1.3) -----
# A source grep asserts the constructor invokes no LLM/model endpoint (the same
# negative-assertion idiom sibling REQ-E1.3 mechanisms use). The launch VERB
# (`claude`) is a caller-supplied argument, never a literal in the constructor,
# so the construction path contains no model/API surface of its own.
c4() {
  local src code
  src="$FDE"
  code=$(grep -vE '^[[:space:]]*#' "$src" || true)
  if printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z_./])claude[[:space:]]' >/dev/null \
    || printf '%s\n' "$code" | grep -niE 'anthropic|/v1/messages|https?://' >/dev/null \
    || printf '%s\n' "$code" | grep -niwE '(curl|wget)' >/dev/null; then
    fail "c4: $src references a model/API/network surface in the launch-construction path (REQ-E1.3)"
  else
    pass "c4: no model/API call in the launch-construction decision path (REQ-E1.3)"
  fi
}

c1
c2
c3
c4

if [ "$failures" -ne 0 ]; then
  echo "test-dispatch-launch-pin: $failures failure(s)" >&2
  exit 1
fi
echo "ok: test-dispatch-launch-pin"
