#!/bin/bash
# Tests for the /orchestrate status gate (Task 5 of specs/kickoff-lifecycle;
# REQ-C1.1, REQ-C1.3, D-1). The kickoff-lifecycle bundle inserts a `Ready`
# status between Draft and Active and narrows the orchestration gate from
# "act on Active" to "act on Ready or Active". This is a skill-prose change:
# `/orchestrate`'s pre-flight refusal is procedure the agent reads, not a
# script, so the [test] half of REQ-C1.1's verification path is a structural
# guard over skills/orchestrate/SKILL.md (the same shape as
# tests/test-sibling-touchpoints.sh). The [manual] half (the refusal message
# reads clearly to an operator) is exercised by the human at review; this test
# fences the structural properties against a regression.
#
# Asserted properties:
#   - the gate names "Ready or Active" as the executable/dispatchable set
#     (REQ-C1.1: act on Ready or Active);
#   - the gate refuses Draft, Done, Retired, and Superseded (REQ-C1.1);
#   - the no-bypass and no-auto-chain invariants survive the rewording;
#   - the freshness gate composes with Ready — a Ready spec is executable only
#     if its content anchor is execution-valid (REQ-C1.3);
#   - the superseded operative phrasings ("Verify the spec is Active", "status
#     is not Active", the "non-Active, missing validator" halt list) are gone,
#     so no stale bare-Active refusal remains. The token "non-Active" may still
#     appear where it names the bootstrap rule being superseded — that
#     reference is desirable (the supersede stays legible), not a regression.
#
# Runs standalone: ./tests/test-orchestrate-status-gate.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/orchestrate/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

if [ ! -f "$skill" ]; then
  echo "FAIL: orchestrate SKILL.md missing at $skill" >&2
  exit 1
fi

# REQ-C1.1: the executable set is named "Ready or Active".
if grep -qE 'Ready or Active' "$skill"; then
  ok "gate names the executable set as Ready or Active (REQ-C1.1)"
else
  fail "gate does not name 'Ready or Active' as the executable set (REQ-C1.1)"
fi

# REQ-C1.1: the four non-executable statuses are explicitly refused, listed
# together so the refusal message is unambiguous.
if grep -qE 'Draft, Done, Retired,? and Superseded' "$skill"; then
  ok "gate enumerates the refused statuses Draft/Done/Retired/Superseded (REQ-C1.1)"
else
  fail "gate does not enumerate 'Draft, Done, Retired, and Superseded' as refused (REQ-C1.1)"
fi

# REQ-C1.1: the no-bypass invariant survives the rewording.
if grep -qi 'no bypass flag' "$skill"; then
  ok "no-bypass invariant preserved (REQ-C1.1)"
else
  fail "no-bypass invariant ('no bypass flag') missing (REQ-C1.1)"
fi

# REQ-C1.1: the never-auto-chain invariant survives the rewording.
if grep -qiE 'auto-chain' "$skill"; then
  ok "never-auto-chain invariant preserved (REQ-C1.1)"
else
  fail "never-auto-chain invariant missing (REQ-C1.1)"
fi

# REQ-C1.3: the freshness gate composes with the Ready gate. The prose ties the
# Ready state to the execution freshness gate / execution-valid content anchor,
# and cites REQ-C1.3.
if grep -q 'REQ-C1.3' "$skill"; then
  ok "freshness-composition requirement REQ-C1.3 is cited"
else
  fail "freshness-composition requirement REQ-C1.3 is not cited (REQ-C1.3)"
fi
# Bind to the REQ-C1.3 citation itself (it appears only in the composition
# prose), not to a stray co-occurrence of "freshness" in the halt-list
# enumeration: the gate prose must tie the Ready state to the freshness gate /
# execution-valid content anchor where REQ-C1.3 is cited.
if grep -nE -A2 -B2 'REQ-C1\.3' "$skill" \
  | grep -qiE 'freshness|content anchor|execution-valid|compose'; then
  ok "the REQ-C1.3 prose ties the Ready gate to the freshness gate / execution-valid anchor"
else
  fail "REQ-C1.3 is cited but not tied to the freshness gate / execution-valid anchor (REQ-C1.3)"
fi

# Regression fence: the superseded bare-Active refusal phrasings are gone.
if grep -q 'Verify the spec is Active' "$skill"; then
  fail "stale gate header 'Verify the spec is Active' still present (REQ-C1.1 supersede)"
else
  ok "stale gate header 'Verify the spec is Active' removed"
fi
if grep -qE 'status is not Active' "$skill"; then
  fail "stale invariant 'status is not Active' still present (REQ-C1.1 supersede)"
else
  ok "stale invariant 'status is not Active' removed"
fi
# The operative consolidated-halt list no longer refuses on bare "non-Active"
# (it now reads "not Ready or Active"). "non-Active" may still appear where it
# names the superseded bootstrap rule; only the operative halt phrasing is
# forbidden.
if grep -qE 'non-Active, missing validator' "$skill"; then
  fail "operative halt list still refuses on bare 'non-Active' (REQ-C1.1 supersede)"
else
  ok "operative halt list reads 'not Ready or Active', not bare non-Active"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all orchestrate status-gate tests passed"
