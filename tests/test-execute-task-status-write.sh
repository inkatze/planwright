#!/bin/bash
# Tests for the /execute-task Status-write contract (specs/orchestration-
# concurrency; REQ-B1.1, D-1). Under the single-writer model the `tasks-pr-sync`
# reconcile is the SOLE writer of `tasks.md` section placement AND the `Status`
# annotation. `/execute-task` must therefore write no `Status` line anywhere —
# not at the pre-implementation step (step 10) and not at PR creation (PR step
# 3). This is a skill-prose change: PR creation is procedure the agent reads,
# not a script, so REQ-B1.1's verification path is a structural guard over
# skills/execute-task/SKILL.md (the same shape as
# tests/test-orchestrate-status-gate.sh).
#
# Why this matters (the regression fenced here): the `tasks-pr-sync` hook is
# fail-soft on a busy lock (a clean no-op; scripts/tasks-pr-sync.sh). If PR
# step 3 wrote `- **Status:** PR #<N> draft` while relying on the hook to have
# already moved the block to `## In progress`, a busy-lock no-op leaves the
# block under `## Forward plan` carrying an in-progress Status — exactly the
# section/status contradiction scripts/check-ledger.sh flags (REQ-E1.1,
# REQ-E1.2). Dropping the Status write eliminates the race at its source: a
# not-yet-reconciled in-flight block with no Status is correct, not corrupt.
#
# Asserted properties:
#   - PR creation step 3 writes NO in-progress `Status` annotation (the
#     `- **Status:** PR #<N> draft` instruction is gone);
#   - step 10 no longer claims the Status is written at PR creation;
#   - the skill positively names placement AND the Status annotation as the
#     reconcile's sole job, citing REQ-B1.1;
#   - the busy-lock-race rationale is documented (fail-soft hook + check-ledger);
#   - PR step 3 still writes the anchor-excluded Last-activity annotation.
#
# Runs standalone: ./tests/test-execute-task-status-write.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/execute-task/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

if [ ! -f "$skill" ]; then
  echo "FAIL: execute-task SKILL.md missing at $skill" >&2
  exit 1
fi

# Flatten newlines and squeeze runs of whitespace so cross-line prose matches
# are stable against rewrapping and indentation at the wrap point.
flat="$(tr '\n' ' ' <"$skill" | tr -s ' ')"

# REQ-B1.1: PR creation step 3 must NOT instruct writing an in-progress
# `Status: PR #<N> draft` annotation. The reconcile is the sole Status writer;
# a Status write here races the fail-soft hook. Fail if the instruction is
# present anywhere in the skill (it occurred only at PR step 3).
if printf '%s' "$flat" | grep -qE 'Status:\*\* PR #<N> draft'; then
  fail "PR step 3 still instructs writing '**Status:** PR #<N> draft' (REQ-B1.1: reconcile is sole Status writer)"
else
  ok "PR creation writes no in-progress Status annotation (REQ-B1.1)"
fi

# REQ-B1.1: step 10's explanation must not claim the Status is written at PR
# creation — that framing made PR step 3 the Status writer, the very behavior
# being removed.
if printf '%s' "$flat" | grep -qE 'Status. annotation is written at PR creation'; then
  fail "step 10 still claims the Status annotation is written at PR creation (REQ-B1.1 supersede)"
else
  ok "step 10 no longer claims the Status is written at PR creation"
fi

# REQ-B1.1: the skill positively names placement AND the Status annotation as
# the reconcile's sole job. Bind to the conjunction so dropping either side is
# caught.
if printf '%s' "$flat" | grep -qE 'placement and the .Status. annotation are the .tasks-pr-sync. reconcile'; then
  ok "skill names placement AND Status as the reconcile's sole job"
else
  fail "skill does not name placement AND the Status annotation as the reconcile's sole job (REQ-B1.1)"
fi

# REQ-B1.1: the sole-job claim cites REQ-B1.1.
if grep -q 'REQ-B1.1' "$skill"; then
  ok "REQ-B1.1 (single-writer) is cited"
else
  fail "REQ-B1.1 (single-writer) is not cited"
fi

# Rationale fence: the busy-lock race is documented — a fail-soft hook on a busy
# lock can leave the block under Forward plan, and check-ledger flags an
# in-progress Status there. This is Copilot's exact concern; keep it legible.
if printf '%s' "$flat" | grep -qE 'fail-soft on a busy lock'; then
  ok "busy-lock fail-soft rationale documented"
else
  fail "busy-lock fail-soft rationale ('fail-soft on a busy lock') missing"
fi
if printf '%s' "$flat" | grep -q 'check-ledger'; then
  ok "check-ledger corruption-guard rationale cited"
else
  fail "check-ledger corruption-guard rationale missing"
fi

# Positive: PR step 3 still writes the anchor-excluded Last-activity annotation
# (dropping the Status must not drop Last activity too).
if printf '%s' "$flat" | grep -qE 'Last activity'; then
  ok "Last-activity annotation still written"
else
  fail "Last-activity annotation no longer written (regression)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all execute-task Status-write contract tests passed"
