#!/bin/bash
# Tests for the /execute-task status gate (kickoff-lifecycle six-status model;
# REQ-C1.1, REQ-C1.3, D-2, D-3). The kickoff-lifecycle bundle inserts a `Ready`
# status between Draft and Active and makes Ready<->Active a DERIVED (not stored)
# distinction: a signed-off executable spec sits at `Status: Ready`, and the
# file stays `Ready` during execution — only the orchestration-concurrency
# reconcile ever writes `Active` (D-2, D-3). `/orchestrate`'s dispatch gate was
# migrated to accept {Ready, Active} (see tests/test-orchestrate-status-gate.sh),
# but `/execute-task`'s step-4 gate was left demanding a stored `Active`, so a
# dispatched task halted pre-flight with "spec not Active" on every Ready spec.
# This test fences the migrated gate against that regression.
#
# Like its orchestrate sibling this is a skill-prose change: `/execute-task`'s
# pre-flight refusal is procedure the agent reads, not a script, so the [test]
# half of the verification path is a structural guard over
# skills/execute-task/SKILL.md (the same shape as
# tests/test-orchestrate-status-gate.sh and tests/test-sibling-touchpoints.sh).
# The [manual] half (the refusal reads clearly to an operator) is exercised by
# the human at review.
#
# Asserted properties:
#   - the gate names "Ready or Active" as the executable set (REQ-C1.1 framing,
#     mirrored so the two dispatch skills agree);
#   - the gate refuses Draft, Done, Retired, and Superseded;
#   - the no-bypass invariant survives the rewording;
#   - the gate ties the Ready state to the derived-not-stored lifecycle model
#     (D-2/D-3), so the six-status alignment with /orchestrate is legible;
#   - the freshness gate composes with Ready — a Ready spec is executable only
#     if its content anchor is execution-valid (REQ-C1.3);
#   - the superseded bare-Active phrasings ("Verify the spec is Active", "status
#     is not Active", the "Spec not Active" stop-condition row) are gone, so no
#     stale bare-Active refusal remains. The token "non-Active" may still appear
#     where it names the bootstrap rule being superseded — that reference is
#     desirable (the supersede stays legible), not a regression.
#
# Runs standalone: ./tests/test-execute-task-status-gate.sh
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

# REQ-C1.1 framing: the step-4 gate POSITIVELY names the executable set as
# "Ready or Active". Bind to the gate header itself, not a bare "Ready or Active"
# substring: the phrase also appears in negative halt-list rows ("Spec not Ready
# or Active"), so a bare substring match would stay green even if step 4 stopped
# explicitly accepting both statuses. This is the positive mirror of the stale
# "Verify the spec is Active" check below: old header absent, new header present.
if grep -qE 'Verify the spec is Ready or Active' "$skill"; then
  ok "gate names the executable set as Ready or Active"
else
  fail "gate does not name 'Ready or Active' as the executable set"
fi

# The four non-executable statuses are explicitly refused, listed together so
# the refusal is unambiguous. Bind to the operative verb "refuse" (not just the
# status names) so an inverted-semantics regression cannot pass. The verb and
# the list wrap across a line in the prose, so flatten newlines to spaces first
# and match the verb-then-list across the wrap.
if tr '\n' ' ' <"$skill" \
  | grep -qE 'refuse[[:space:]]+Draft, Done, Retired,? and Superseded'; then
  ok "gate refuses the statuses Draft/Done/Retired/Superseded"
else
  fail "gate does not state it will 'refuse' Draft, Done, Retired, and Superseded"
fi

# The no-bypass invariant survives the rewording.
if grep -qi 'no bypass flag' "$skill"; then
  ok "no-bypass invariant preserved"
else
  fail "no-bypass invariant ('no bypass flag') missing"
fi

# Six-status alignment: the gate ties the Ready state to the derived-not-stored
# lifecycle model (kickoff-lifecycle D-2/D-3). This is what makes the gate agree
# with /orchestrate rather than re-introducing a stored-Active demand.
if grep -qiE 'derived, not stored|derived .not stored' "$skill" \
  && grep -qE 'D-2' "$skill"; then
  ok "gate ties Ready to the derived-not-stored lifecycle model (D-2/D-3)"
else
  fail "gate does not tie Ready to the derived-not-stored lifecycle model (D-2/D-3)"
fi

# REQ-C1.3: the freshness gate composes with the Ready gate — the prose ties the
# Ready state to the execution freshness gate / execution-valid content anchor,
# and cites REQ-C1.3.
if grep -q 'REQ-C1.3' "$skill"; then
  ok "freshness-composition requirement REQ-C1.3 is cited"
else
  fail "freshness-composition requirement REQ-C1.3 is not cited"
fi
# Bind to the REQ-C1.3 citation itself (it appears only in the composition
# prose), not to a stray co-occurrence of "freshness" elsewhere: the gate prose
# must tie the Ready state to the freshness gate / execution-valid anchor where
# REQ-C1.3 is cited.
if grep -nE -A2 -B2 'REQ-C1\.3' "$skill" \
  | grep -qiE 'freshness|content anchor|execution-valid|compose'; then
  ok "the REQ-C1.3 prose ties the Ready gate to the freshness gate / execution-valid anchor"
else
  fail "REQ-C1.3 is cited but not tied to the freshness gate / execution-valid anchor"
fi

# Regression fence: the superseded bare-Active refusal phrasings are gone.
if grep -q 'Verify the spec is Active' "$skill"; then
  fail "stale gate header 'Verify the spec is Active' still present (six-status supersede)"
else
  ok "stale gate header 'Verify the spec is Active' removed"
fi
if grep -qE 'status is not Active' "$skill"; then
  fail "stale invariant 'status is not Active' still present (six-status supersede)"
else
  ok "stale invariant 'status is not Active' removed"
fi
# The stop-condition row no longer refuses on bare "Spec not Active" (it now
# reads "Spec not Ready or Active"). "non-Active" may still appear where it names
# the superseded bootstrap rule; only the operative bare-Active phrasing is
# forbidden.
if grep -qE 'Spec not Active ' "$skill"; then
  fail "stop-condition row still refuses on bare 'Spec not Active' (six-status supersede)"
else
  ok "stop-condition row reads 'Spec not Ready or Active', not bare 'Spec not Active'"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all execute-task status-gate tests passed"
