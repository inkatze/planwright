#!/bin/bash
# The worker-guard suites are hermetic: sourced from inside a worker session (a
# session record in the environment and a TMPDIR naming the scratch root the
# record trusts), the shared harness still puts its fixtures outside that
# scratch and gives the hook neither the record nor the scratch TMPDIR. Without
# it, a relative `rm` in a fixture is approved by the scratch arm by design, and
# a suite reports false-allows that are not the guard's fault.
#
# The file runs twice: the outer pass builds the simulated session and re-runs
# this file inside it; the inner pass sees that session in its environment
# before sourcing the harness, and asserts on what the harness leaves.
set -u
unset CDPATH
INH_TMPDIR=${TMPDIR-}
INH_RECORD=${PLANWRIGHT_WORKER_SESSION_RECORD-}
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

if [ -n "${WCG_HERMETIC_INNER:-}" ]; then
  if [ -n "$INH_TMPDIR" ] && [ -n "$INH_RECORD" ]; then
    pass "the inner pass starts inside a simulated worker session"
  else
    fail "the inner pass did not inherit a session"
  fi
  if [ "$TMPDIR" = /tmp ]; then
    pass "TMPDIR is pinned to /tmp"
  else
    fail "TMPDIR is $TMPDIR"
  fi
  if [ -z "${PLANWRIGHT_WORKER_SESSION_RECORD+x}" ]; then
    pass "the inherited session record is dropped"
  else
    fail "the session record leaked"
  fi
  case $SANDBOX in
    "$INH_TMPDIR"/*) fail "the fixture sandbox sits under the session scratch" ;;
    /tmp/* | "$(cd /tmp && pwd -P)"/*) pass "the fixture sandbox sits outside the session scratch" ;;
    *) fail "the fixture sandbox is at $SANDBOX" ;;
  esac
  assert_defer "a relative rm in the fixture sandbox is deferred" "rm -rf x"
  assert_defer "an unsafe segment after a safe one is deferred" "echo ok; rm -rf x"
  finish_suite "worker-command-guard-hermetic (inner)"
fi

# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"
# The session's own scratch lives outside the harness sandbox, as a real
# worker's does.
BOX=$(mktemp -d /tmp/wcg-hermetic.XXXXXX) || exit 1
trap 'rm -rf "$BOX" "$SANDBOX"' EXIT
corpus_sandbox "$BOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
inner=$(env WCG_HERMETIC_INNER=1 TMPDIR="$CORPUS_SCRATCH" \
  PLANWRIGHT_WORKER_SESSION_RECORD="$CORPUS_BOX/state/record.4" bash "$0" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "the harness is hermetic inside a worker session"
else
  fail "the harness is not hermetic inside a worker session (exit $rc)"
  printf '%s\n' "$inner" >&2
fi
finish_suite "worker-command-guard-hermetic"
