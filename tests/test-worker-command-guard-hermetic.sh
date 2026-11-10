#!/bin/bash
# The worker-guard suites are hermetic: a suite run from inside a worker
# session (a session record in the environment and a TMPDIR naming the scratch
# root the record trusts) passes exactly as it does from a plain shell with
# TMPDIR=/tmp. Without it, fixtures that land under the session's scratch are
# approved by the scratch arm by design, and a suite reports false-allows that
# are not the guard's fault.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
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
SESSION_TMP=$CORPUS_SCRATCH
SESSION_RECORD=$CORPUS_BOX/state/record.4

# Suites whose rows include unsafe commands the scratch arm would approve if
# it could see the suite's fixtures.
for suite in steps shapes; do
  inside=$(env TMPDIR="$SESSION_TMP" PLANWRIGHT_WORKER_SESSION_RECORD="$SESSION_RECORD" \
    timeout 280 bash "$REPO_ROOT/tests/test-worker-command-guard-$suite.sh" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$suite: passes inside a worker session"
  else
    fail "$suite: exit $rc inside a worker session"
    printf '%s\n' "$inside" | grep '^FAIL:\|^SECURITY' >&2
  fi
done

finish_suite "worker-command-guard-hermetic"
