# shellcheck shell=bash
# ready-guard-harness.sh — the shared fixture harness for the ready-guard
# suites (sourced, never executed): a hermetic PATH, a recording `gh` stub
# driven by env, side-effect sentinels, the canonical PR answers, and the
# deny/defer assertions. tests/test-ready-guard.sh (branch by branch) and
# tests/test-merge-currency-matrix.sh (the manifest) both source it, so the
# two cannot drift apart on what "deny" and "defer" mean or on how the GitHub
# surface is stubbed.
#
# Contract the assertions encode:
#   DENY  <=> exit 0 AND stdout carries a permissionDecision of "deny" with a
#             non-empty permissionDecisionReason.
#   DEFER <=> exit 0 AND stdout is empty/whitespace.
#   The hook NEVER exits non-zero and NEVER emits allow or ask.
#
# The `gh` stub RECORDS ITS ARGV to $STATE/argv.log (one CALL line and one CWD
# line per invocation), so a suite can pin the exact query rather than only
# the answer: a stub that would answer the same for a wrong subcommand, a
# wrong PR number, or a wrong repo cannot make a fixture pass vacuously. The
# stub also answers from a file when one sits in its working directory
# ($PWD/view.json for `pr view`, $PWD/behind for the compare call), which is
# how tests/test-ready-guard.sh tells apart WHICH directory a `cd &&` prefix
# made the guard query from.
#
# Usage:
#   HOOK=<path>   # optional; the guard under test, default this checkout's
#   . tests/lib/ready-guard-harness.sh
#
# Sourcing runs setup: it exits the sourcing suite (status 1) when the guard
# script, jq, or a timeout binary is absent, since neither the guard's bounded
# path nor the assertions can run without them; builds the sandbox and stubs;
# installs the ONLY EXIT trap (a suite that sets its own replaces it and leaks
# the sandbox, so keep scratch files under $SANDBOX instead); and calls
# reset_stub_env once so the knobs below are defined under `set -u`.
#
# Knobs a fixture sets in the shell before calling run_hook. The STUB_* five
# are passed through into the stub's environment; RG_SURFACE is passed to the
# guard as its argument, the way hooks/hooks.json passes it:
#   STUB_VIEW_JSON / STUB_VIEW_JSON2   the first / second `gh pr view` answer
#   STUB_VIEW_RC / STUB_VIEW_RC2       their exit codes
#   STUB_COMPARE_OUT / STUB_COMPARE_RC the compare endpoint's behind_by / exit
#   RG_SURFACE                         which matcher fired: bash (default) | mcp
#                                      (not reset by reset_stub_env)
unset CDPATH

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HOOK="${HOOK:-$REPO_ROOT/scripts/ready-guard.sh}"

failures=0
passes=0

pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

if [ ! -f "$HOOK" ]; then
  echo "FAIL: ready-guard script missing at $HOOK" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi
# Probe the bounding binaries ONLY. jq was once in this loop, which set the
# flag on any host with jq and let a host with neither timeout nor gtimeout
# run the whole suite against the guard's "no timeout binary" denial instead
# of stopping here with the reason.
unset HAVE_ANY_TIMEOUT
for t in timeout gtimeout; do
  command -v "$t" >/dev/null 2>&1 && HAVE_ANY_TIMEOUT=1
done
if [ -z "${HAVE_ANY_TIMEOUT:-}" ]; then
  echo "FAIL: neither timeout nor gtimeout is available; the suite cannot exercise the bounded path" >&2
  exit 1
fi

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ready-guard.XXXXXX")" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
STATE="$SANDBOX/state"
WORK="$SANDBOX/work"
mkdir -p "$BIN" "$STATE" "$WORK" "$WORK/sub"

# A hermetic PATH holding ONLY what the guard may use. Absence fixtures delete
# one entry from it, so "jq absent" and "gh absent" are genuinely absent rather
# than shadowed — the ambient PATH is never consulted.
HERMETIC_TOOLS="head tr sleep dirname cat env sed grep"
for t in $HERMETIC_TOOLS; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done
ln -sf "$(command -v jq)" "$BIN/jq"
for t in timeout gtimeout; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done

# The `gh` stub. Records every invocation's argv (tab-separated, one line per
# call) so fixtures can pin the QUERY SHAPE, and answers from env so each
# fixture drives its own decision cell. It answers `pr` and `api` only: a wrong
# subcommand exits 3, which the guard must surface as a denial rather than
# silently treat as an answer.
cat >"$BIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf '\t%s' "$a"; done
  printf '\n'
  printf 'CWD\t%s\n' "$PWD"
} >>"$GH_ARGV_LOG"
case "${1:-}" in
  pr)
    if [ -f "$PWD/view.json" ]; then
      cat "$PWD/view.json"
      exit 0
    fi
    n=0
    [ ! -f "$GH_STATE/viewcount" ] || read -r n <"$GH_STATE/viewcount"
    n=$((n + 1))
    printf '%s\n' "$n" >"$GH_STATE/viewcount"
    if [ "$n" = 1 ]; then
      rc=${STUB_VIEW_RC:-0}
      [ "$rc" = 0 ] || exit "$rc"
      printf '%s' "${STUB_VIEW_JSON:-}"
    else
      rc=${STUB_VIEW_RC2:-${STUB_VIEW_RC:-0}}
      [ "$rc" = 0 ] || exit "$rc"
      printf '%s' "${STUB_VIEW_JSON2:-${STUB_VIEW_JSON:-}}"
    fi
    ;;
  api)
    if [ -f "$PWD/behind" ]; then
      cat "$PWD/behind"
      exit 0
    fi
    rc=${STUB_COMPARE_RC:-0}
    [ "$rc" = 0 ] || exit "$rc"
    printf '%s\n' "${STUB_COMPARE_OUT:-0}"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$BIN/gh"

# Side-effect sentinels. `git`, `curl`, `wget`, and `claude` must never run in
# the decision path (REQ-D1.4, D-5): each stub drops a marker file, and the
# assertions require the marker to be absent. They also exit non-zero, so a
# guard that DID call one and depended on its answer would misbehave visibly.
for t in git curl wget claude; do
  cat >"$BIN/$t" <<SENTSTUB
#!/bin/sh
: >"$STATE/sentinel-$t"
exit 97
SENTSTUB
  chmod +x "$BIN/$t"
done

# The canonical `gh pr view` answers. Currency is NOT in the answer: the
# compare endpoint supplies it, so a fixture pairs an answer with its own
# STUB_COMPARE_OUT (0 for current, >0 for behind). SC2034 is waived per
# constant because the suites, not this file, consume them.
#
# A draft, mergeable PR; conforming once paired with behind_by 0.
# shellcheck disable=SC2034
VIEW_CONFORMING='{"baseRefName":"main","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","isDraft":true,"mergeable":"MERGEABLE","url":"https://github.com/acme/widgets/pull/42"}'
# A stale PR. It deliberately ALSO reports `mergeStateStatus CLEAN`: on a base
# without "require up to date" protection that is what GitHub says about a
# behind PR, so an implementation that regressed to keying currency on
# mergeStateStatus would read this as conforming and this fixture would catch it
# (test-spec REQ-C1.1).
# shellcheck disable=SC2034
VIEW_BEHIND='{"baseRefName":"main","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","isDraft":true,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://github.com/acme/widgets/pull/42"}'
# shellcheck disable=SC2034
VIEW_CONFLICTING='{"baseRefName":"main","headRefOid":"cccccccccccccccccccccccccccccccccccccccc","isDraft":true,"mergeable":"CONFLICTING","url":"https://github.com/acme/widgets/pull/42"}'
# shellcheck disable=SC2034
VIEW_UNKNOWN='{"baseRefName":"main","headRefOid":"dddddddddddddddddddddddddddddddddddddddd","isDraft":true,"mergeable":"UNKNOWN","url":"https://github.com/acme/widgets/pull/42"}'
# Already ready. Stale AND conflicting on purpose: REQ-C1.8 requires the no-op
# to defer "regardless of currency/mergeability state".
# shellcheck disable=SC2034
VIEW_ALREADY_READY='{"baseRefName":"main","headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","isDraft":false,"mergeable":"CONFLICTING","url":"https://github.com/acme/widgets/pull/42"}'

# run_hook — drive the guard with a payload. Env overrides for the stub are
# passed through the caller's environment.
#   run_hook <payload-json> [extra-path-removals...]
run_hook() {
  local payload=$1
  shift
  rm -f "$STATE"/sentinel-* "$STATE/viewcount"
  : >"$STATE/argv.log"
  local path="$BIN"
  local removed t
  for removed in "$@"; do
    rm -f "$BIN/$removed"
  done
  OUT="$(printf '%s' "$payload" \
    | env -i PATH="$path" HOME="$SANDBOX" \
      GH_ARGV_LOG="$STATE/argv.log" GH_STATE="$STATE" \
      PLANWRIGHT_READY_GUARD_RETRY_DELAY=0 \
      STUB_VIEW_JSON="${STUB_VIEW_JSON:-}" STUB_VIEW_JSON2="${STUB_VIEW_JSON2:-}" \
      STUB_VIEW_RC="${STUB_VIEW_RC:-0}" STUB_VIEW_RC2="${STUB_VIEW_RC2:-}" \
      STUB_COMPARE_OUT="${STUB_COMPARE_OUT:-0}" STUB_COMPARE_RC="${STUB_COMPARE_RC:-0}" \
      /bin/bash "$HOOK" "${RG_SURFACE:-bash}" 2>/dev/null)"
  CODE=$?
  # Restore anything an absence fixture removed.
  for removed in "$@"; do
    case $removed in
      gh) chmod +x "$BIN/gh" 2>/dev/null || : ;;
      *) t="$(command -v "$removed" 2>/dev/null)" && ln -sf "$t" "$BIN/$removed" ;;
    esac
  done
  if [ -n "${1:-}" ]; then
    for removed in "$@"; do
      [ "$removed" != gh ] || restore_gh_stub
    done
  fi
}

restore_gh_stub() {
  cp "$SANDBOX/gh.orig" "$BIN/gh"
  chmod +x "$BIN/gh"
}
cp "$BIN/gh" "$SANDBOX/gh.orig"
bash_payload() {
  jq -n --arg c "$1" --arg w "${2:-$WORK}" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'
}

mcp_payload() {
  # <owner> <repo> <pullNumber-json> [<draft-json>]
  if [ "$#" -ge 4 ]; then
    jq -n --arg o "$1" --arg r "$2" --argjson n "$3" --argjson d "$4" \
      '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:$o, repo:$r, pullNumber:$n, draft:$d}}'
  else
    jq -n --arg o "$1" --arg r "$2" --argjson n "$3" \
      '{tool_name:"mcp__github__update_pull_request", tool_input:{owner:$o, repo:$r, pullNumber:$n, title:"t"}}'
  fi
}

is_deny() {
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}
is_empty() { [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; }
reason() {
  printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null
}
# count_lines <pattern> — grep -c exits 1 on zero matches, so the count is
# captured and the status swallowed; a bare `grep -c || echo 0` would print two
# numbers and break every arithmetic comparison downstream.
count_lines() {
  local n
  n=$(grep -c -- "$1" "$STATE/argv.log" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}
gh_calls() { count_lines '^CALL'; }
pr_view_calls() { count_lines $'\tpr\tview'; }

# assert_deny <label> — pins the MISSED-DENY direction.
assert_deny() {
  local label=$1
  if [ "$CODE" != 0 ]; then
    fail "$label: expected exit 0, got $CODE"
    return
  fi
  if printf '%s' "$OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"(allow|ask)"'; then
    fail "$label: emitted allow/ask — the guard must only ever deny or defer"
    return
  fi
  if ! is_deny; then
    fail "$label: expected DENY, got '${OUT:-<empty>}'"
    return
  fi
  if [ -z "$(reason)" ]; then
    fail "$label: denied with an empty reason (REQ-K1.1)"
    return
  fi
  pass "$label"
}

# assert_defer <label> — pins the SPURIOUS-DENY direction.
assert_defer() {
  local label=$1
  if [ "$CODE" != 0 ]; then
    fail "$label: expected exit 0, got $CODE"
    return
  fi
  if ! is_empty; then
    fail "$label: expected DEFER (empty stdout), got '$OUT'"
    return
  fi
  pass "$label"
}

# assert_deny_because <label> <reason-regex> — DENY *and* the specific refusal
# that produced it. Use this wherever more than one branch could plausibly deny
# the same fixture; a bare assert_deny there lets the branch be deleted with the
# suite still green.
assert_deny_because() {
  assert_deny "$1"
  assert_reason_matches "$1 — for the stated reason" "$2"
}

assert_reason_matches() {
  local label=$1 re=$2
  if printf '%s' "$(reason)" | grep -Eqi -- "$re"; then
    pass "$label"
  else
    fail "$label: reason did not match /$re/ — got: $(reason)"
  fi
}

assert_reason_lacks() {
  local label=$1 re=$2
  if printf '%s' "$(reason)" | grep -Eqi -- "$re"; then
    fail "$label: reason should not mention /$re/ — got: $(reason)"
  else
    pass "$label"
  fi
}

assert_queried_in() {
  local label=$1 dir=$2
  local got
  got=$(grep -m1 '^CWD' "$STATE/argv.log" 2>/dev/null | cut -f2)
  if [ "$got" = "$dir" ]; then
    pass "$label"
  else
    fail "$label: the guard queried '$got', expected '$dir'"
  fi
}

assert_no_sentinels() {
  local label=$1 found=''
  local t
  for t in git curl wget claude; do
    [ ! -e "$STATE/sentinel-$t" ] || found="$found $t"
  done
  if [ -n "$found" ]; then
    fail "$label: the decision path invoked$found (REQ-D1.4 / D-5 violation)"
  else
    pass "$label"
  fi
}

reset_stub_env() {
  STUB_VIEW_JSON=''
  STUB_VIEW_JSON2=''
  STUB_VIEW_RC=0
  STUB_VIEW_RC2=''
  STUB_COMPARE_OUT=0
  STUB_COMPARE_RC=0
}
reset_stub_env
