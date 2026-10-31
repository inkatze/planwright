# shellcheck shell=bash
# worker-command-guard-harness.sh — the shared harness for the
# worker-command-guard suites (sourced, never executed): the sandbox checkouts
# and plugin roots the fixtures run against, the hook runner, and the
# ALLOW/DEFER assertions. Every tests/test-worker-command-guard*.sh suite
# sources it, so they cannot drift apart on what "allow" and "defer" mean.
#
# Contract the assertions encode:
#   ALLOW  <=> exit 0 AND stdout carries a well-formed
#              "permissionDecision": "allow" object.
#   DEFER  <=> exit 0 AND stdout is empty/whitespace (no decision).
#   The hook NEVER exits non-zero and NEVER emits deny/ask (REQ-A1.2, B1.7).
#
# Sourcing runs setup: it exits the sourcing suite (status 1) when jq or the
# hook is absent, and removes the sandbox on exit. finish_suite prints the
# counts and sets the suite's exit status.
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/worker-command-guard.sh"

failures=0
passes=0
false_allows=0

pass() {
  printf 'ok: %s\n' "$1"
  passes=$((passes + 1))
}
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi
if [ ! -f "$HOOK" ]; then
  printf 'FAIL: hook script missing at %s\n' "$HOOK" >&2
  exit 1
fi

# Default cwd for containment: a scratch repo with a .git marker and a
# scripts/ + tests/ dir so in-repo script/bats paths resolve inside it.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/worker-command-guard-harness.XXXXXX")" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/scripts" "$SANDBOX/tests" "$SANDBOX/sub"
: >"$SANDBOX/.git" # worktree-style .git file marker
: >"$SANDBOX/scripts/ok.sh"
: >"$SANDBOX/scripts/tower-force-push.sh"
ln -f "$SANDBOX/scripts/tower-force-push.sh" "$SANDBOX/scripts/fph.sh"
: >"$SANDBOX/scripts/Tower-Force-Push.sh"
: >"$SANDBOX/tests/ok.bats"
# Symlinked final components pointing OUTSIDE the repo (containment escape).
ln -sf /etc/hosts "$SANDBOX/scripts/evillink.sh"
ln -sf /etc/hosts "$SANDBOX/tests/evillink.bats"

# A simulated INSTALLED planwright root (is_planwright_script's allowance) plus
# the two decoys its containment check must reject: a sibling directory that
# merely shares the root's name PREFIX, and a symlinked leaf pointing outside
# the root. `PLUGIN_CWD` is a separate repo checkout, so a plugin-root path can
# only ever pass via the plugin arm, never via repo containment.
PLUGIN_ROOT="$SANDBOX/install/planwright"
PLUGIN_DECOY="$SANDBOX/install/planwright-evil"
PLUGIN_CWD="$SANDBOX/install/checkout"
mkdir -p "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/tests" "$PLUGIN_DECOY/scripts" \
  "$PLUGIN_CWD" "$SANDBOX/install/outside"
: >"$PLUGIN_CWD/.git"
: >"$PLUGIN_ROOT/scripts/plug.sh"
: >"$PLUGIN_ROOT/scripts/tower-force-push.sh"
ln -f "$PLUGIN_ROOT/scripts/tower-force-push.sh" "$PLUGIN_ROOT/scripts/plug-fph.sh"
: >"$PLUGIN_ROOT/scripts/plug.py"
: >"$PLUGIN_ROOT/tests/plug.sh"
: >"$PLUGIN_ROOT/notscripts.sh"
: >"$PLUGIN_DECOY/scripts/plug.sh"
: >"$SANDBOX/install/outside/evil.sh"
ln -sf "$SANDBOX/install/outside/evil.sh" "$PLUGIN_ROOT/scripts/evillink.sh"

# Extra environment applied to the hook by run_hook. Used only by the
# root-resolution fixtures (PLANWRIGHT_ROOT / CLAUDE_PLUGIN_ROOT / CLAUDE_DIR);
# reset to empty after each so no other fixture inherits it.
HOOK_ENV=()

# write_record <file> <worktree-root> [policy] [unit-branch]: a session record
# as the launcher writes it (scripts/worker-session-record.sh), for a fixture
# to hand the hook through HOOK_ENV as PLANWRIGHT_WORKER_SESSION_RECORD.
write_record() {
  printf '%s\n' "policy=${3-}" "unit_branch=${4:-planwright/demo/task-1}" \
    "worktree_root=$2" "pr_base=origin/main" "worker_base_merge=allow" >"$1"
}

# run_hook <command> [tool_name] [cwd] -> sets OUT and CODE
run_hook() {
  local cmd="$1"
  local tool="${2:-Bash}"
  local cwd="${3:-$SANDBOX}"
  local payload
  payload="$(jq -n --arg c "$cmd" --arg t "$tool" --arg w "$cwd" \
    '{tool_name:$t, tool_input:{command:$c}, cwd:$w}')"
  # HOME and CLAUDE_DIR pinned away from the developer's machine: the hook's
  # <claude-dir> arms would otherwise read the real plugin record and cache,
  # and a verdict would depend on what is installed on the host running the
  # suite. A fixture that needs them sets them through HOOK_ENV, which wins.
  OUT="$(printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" \
    ${HOOK_ENV[@]+"${HOOK_ENV[@]}"} /bin/bash "$HOOK" 2>/dev/null)"
  CODE=$?
}

# The predicates match in the shell, with no launch per hook call. They keep
# the line-at-a-time grep they replaced: the space class leaves out the
# newline, so a decision never matches across a line break.
_wcg_sp=$' \t\r\f\v'
_wcg_allow_re="\"permissionDecision\"[$_wcg_sp]*:[$_wcg_sp]*\"allow\""
_wcg_deny_ask_re="\"permissionDecision\"[$_wcg_sp]*:[$_wcg_sp]*\"(deny|ask)\""

# is_allow: OUT carries a well-formed allow decision.
is_allow() {
  [[ $OUT =~ $_wcg_allow_re ]]
}
# is_empty: OUT is empty or whitespace only.
is_empty() {
  case $OUT in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}
# has_deny_or_ask: OUT ever emits deny/ask (must NEVER happen).
has_deny_or_ask() {
  [[ $OUT =~ $_wcg_deny_ask_re ]]
}

# Every assertion also enforces the universal invariants: exit 0, never
# deny/ask (REQ-A1.2, B1.7).
check_invariants() {
  local label="$1"
  if [ "$CODE" -ne 0 ]; then
    fail "$label — exit was $CODE, must be 0 (REQ-B1.7)"
    return 1
  fi
  if has_deny_or_ask; then
    fail "$label — emitted deny/ask, hook is allow-only (REQ-A1.2)"
    return 1
  fi
  return 0
}

# assert_allow <label> <command> [tool] [cwd]
assert_allow() {
  local label="$1"
  run_hook "$2" "${3:-Bash}" "${4:-$SANDBOX}"
  check_invariants "$label" || return
  if is_allow; then
    pass "$label"
  else
    fail "$label — expected ALLOW, got defer/other"
  fi
}

# assert_defer <label> <command> [tool] [cwd]
assert_defer() {
  local label="$1"
  run_hook "$2" "${3:-Bash}" "${4:-$SANDBOX}"
  check_invariants "$label" || return
  if is_empty; then
    pass "$label"
  else
    if is_allow; then
      fail "$label — FALSE-ALLOW: expected DEFER, hook approved it"
      false_allows=$((false_allows + 1))
    else
      fail "$label — expected DEFER (empty), got non-empty non-allow output"
    fi
  fi
}

# finish_suite <name>: print the counts and exit nonzero on any failure.
finish_suite() {
  echo
  echo "=================================================="
  printf '%s suite: %s passed, %s failed, false-allows: %s\n' "$1" "$passes" "$failures" "$false_allows"
  echo "=================================================="
  if [ "$false_allows" -gt 0 ]; then
    printf 'SECURITY FAILURE: %s false-allow(s) — the zero-false-allow bar is violated.\n' "$false_allows" >&2
  fi
  [ "$failures" -eq 0 ] || exit 1
  exit 0
}
