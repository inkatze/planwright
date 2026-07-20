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
#   c5 (usage): --emit-launch with no launch argv is a usage error (exit 2).
#   c6 (REQ-B1.1): the emitted launch is boundary-safe — a spaced wrapper path
#      and a metacharacter dispatch token survive re-splitting (no broken launch,
#      no injection), matching the exec path's `exec "$@"` argument safety.
#   c7 (REQ-B1.2): a bare-name (PATH) invocation emits the wrapper's real
#      location, not a cwd-relative fabrication, so the emitted verb stays the
#      guard-trusted scripts/*.sh path.
#   c8 (REQ-B1.2): a single-quote / newline launch token is refused (exit 2)
#      rather than emitted in a form the worker-command-guard tokenizer defers on.
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
printf 'args=%s\n' "\$*"
EOF
  chmod +x "$fake"
  emitted=$("$FDE" --emit-launch "$fake" --worktree task-5 --model opus) || {
    fail "c1: --emit-launch exited nonzero"
    rm -rf "$tmp"
    return
  }
  # End-to-end: running the emitted launch pins the var on the launched process
  # and delivers the dispatch tokens in order (the wrapper prefix is emitted by
  # CODE, not assembled by the model). Asserted on behaviour, not on the exact
  # quoting style, so the check survives a change in how tokens are quoted.
  out=$(sh -c "$emitted") || {
    fail "c1: running the emitted launch failed"
    rm -rf "$tmp"
    return
  }
  if ! printf '%s\n' "$out" | grep -qx "seen=false"; then
    fail "c1: launched process did not see $VAR=false, got: $out"
    rm -rf "$tmp"
    return
  fi
  if printf '%s\n' "$out" | grep -qx "args=--worktree task-5 --model opus"; then
    pass "c1: emitted launch pins $VAR=false and delivers the dispatch tokens in order (REQ-B1.1)"
  else
    fail "c1: launched process did not receive the dispatch tokens in order, got: $out"
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

# --- c5: --emit-launch with no launch argv is a usage error (exit 2) ----------
# Guards the `[ "$#" -ge 1 ] || usage` branch: a no-argv construction is a usage
# error, never a silent emit of the bare wrapper path (which would be an empty,
# pinless launch).
c5() {
  local code=0
  "$FDE" --emit-launch >/dev/null 2>&1 || code=$?
  if [ "$code" -eq 2 ]; then
    pass "c5: --emit-launch with no launch argv is a usage error (exit 2)"
  else
    fail "c5: --emit-launch with no argv should exit 2 (usage), got $code"
  fi
}

# --- c6: the emitted launch is boundary-safe (spaces + metacharacters) --------
# Shell-quoting the emitted tokens preserves the argument-boundary safety the
# exec path gets from `exec "$@"`: a wrapper path in a directory whose name
# contains a space, and a dispatch token carrying a shell metacharacter, both
# survive re-splitting by the backend that runs the line — no broken launch, no
# injection. Guards against a regression to a naive space-joined emit.
c6() {
  local tmp dir fake emitted out
  tmp=$(mktemp -d) || {
    fail "c6: mktemp failed"
    return
  }
  dir="$tmp/a b" # a space in the launch-target path
  mkdir -p "$dir"
  fake="$dir/fake claude.sh"
  cat >"$fake" <<EOF
#!/bin/sh
printf 'seen=%s\n' "\${$VAR-<unset>}"
printf 'arg1=%s\n' "\${1-<none>}"
EOF
  chmod +x "$fake"
  # A launch token carrying a shell metacharacter; a naive unquoted emit would
  # split or execute it when the line is run.
  emitted=$("$FDE" --emit-launch "$fake" 'x;touch PWNED') || {
    fail "c6: --emit-launch exited nonzero"
    rm -rf "$tmp"
    return
  }
  out=$(cd "$tmp" && sh -c "$emitted") || {
    fail "c6: running the emitted launch failed: $emitted"
    rm -rf "$tmp"
    return
  }
  if [ -e "$tmp/PWNED" ]; then
    fail "c6: a metacharacter token was executed by the shell (injection): $emitted"
  elif printf '%s\n' "$out" | grep -qx "seen=false" \
    && printf '%s\n' "$out" | grep -qx "arg1=x;touch PWNED"; then
    pass "c6: emitted launch is boundary-safe across spaces and metacharacters (REQ-B1.1)"
  else
    fail "c6: spaced-path / metacharacter token was not delivered intact, got: $out"
  fi
  rm -rf "$tmp"
}

# --- c7: a bare-name (PATH) invocation emits the wrapper's real location ------
# When the wrapper is invoked by bare name resolved through PATH, `$0` has no
# slash and `dirname` is `.`; a naive absolutization would emit a CWD-relative
# "/<cwd>/<name>" verb (broken, and not the guard-trusted scripts/*.sh path).
# The construction must resolve the bare name via PATH to its real location.
c7() {
  local tmp emitted
  tmp=$(mktemp -d) || {
    fail "c7: mktemp failed"
    return
  }
  # Invoke by bare name from an UNRELATED cwd, with the wrapper's dir on PATH.
  emitted=$(cd "$tmp" && PATH="$REPO_ROOT/scripts:$PATH" fleet-dispatch-env.sh --emit-launch claude --model opus) || {
    fail "c7: bare-name --emit-launch failed"
    rm -rf "$tmp"
    return
  }
  # The emitted (shell-quoted) verb must be the wrapper's real path, not a
  # cwd-relative fabrication.
  case $emitted in
    "'$FDE'"*) pass "c7: bare-name PATH invocation emits the real wrapper path, not a cwd-relative one (REQ-B1.2)" ;;
    *) fail "c7: bare-name invocation emitted the wrong verb (want prefix '$FDE'): $emitted" ;;
  esac
  rm -rf "$tmp"
}

# --- c8: a single-quote / newline token is refused, not emitted deferring -----
# The only single-quoted escape for an embedded single quote is the `'\''` form,
# whose backslash the worker-command-guard tokenizer DEFERS on — so such a token
# could never be part of a guard-auto-approved launch. --emit-launch refuses it
# (exit 2) up front rather than emitting a shape the guard silently declines; a
# newline (which cannot sit in a single-line launch) is refused the same way.
# Neither is a valid dispatch token.
c8() {
  local code out
  code=0
  out=$("$FDE" --emit-launch claude --foo "a'b" 2>/dev/null) || code=$?
  if [ "$code" -eq 2 ] && [ -z "$out" ]; then
    pass "c8: a single-quote launch token is refused (exit 2), not emitted guard-deferring (REQ-B1.2)"
  else
    fail "c8: single-quote token: expected exit 2 and no stdout, got exit $code out='$out'"
  fi
  code=0
  "$FDE" --emit-launch claude "$(printf 'a\nb')" >/dev/null 2>&1 || code=$?
  if [ "$code" -eq 2 ]; then
    pass "c8b: a newline launch token is refused (exit 2)"
  else
    fail "c8b: newline token: expected exit 2, got exit $code"
  fi
}

c1
c2
c3
c4
c5
c6
c7
c8

if [ "$failures" -ne 0 ]; then
  echo "test-dispatch-launch-pin: $failures failure(s)" >&2
  exit 1
fi
echo "ok: test-dispatch-launch-pin"
