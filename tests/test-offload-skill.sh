#!/bin/bash
# Structural guard over the /offload skill and the work-placement doctrine doc
# (execution-backends Task 6; D-1, REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4).
#
# The /offload skill is procedure the agent reads, not a script, so the [test]
# half of the REQ-C verification paths is a structural guard over
# skills/offload/SKILL.md and doctrine/work-placement.md (the same shape as
# tests/test-execute-task-status-gate.sh). The [Gherkin] half (REQ-C1.4's two
# ask scenarios) is recorded specification in the bundle's test-spec, enforced
# by the skill prose asserted here and exercised manually at convergence.
#
# Asserted properties:
#   - doctrine/work-placement.md exists and states BOTH axioms by name:
#     tower-frugality (the inline/offload boundary: pure reasoning over
#     existing context + the operational heartbeat stay inline; large or
#     unpredictable context ingestion offloads) and smallest-sufficient-rung
#     (subagent unless the work must survive the tower, be human-attachable,
#     or run beyond the session), citing D-1 (REQ-C1.2, REQ-C1.3);
#   - skills/offload/SKILL.md exists and cites work-placement — both as a
#     machine-parseable doctrine-manifest line and in body prose (the grep
#     guard the test-spec names for REQ-C1.2/REQ-C1.3);
#   - the skill declares itself the sole home of adaptive backend selection
#     (REQ-C1.1's design-level property, stated so it is auditable);
#   - the ask-never-guess rule is present for both arms: an under-determined
#     petition asks, and a determined-but-unadvertised rung asks — never a
#     silent guess, never a silent dispatch to an insufficient rung
#     (REQ-C1.4);
#   - the report contract is stated: handle plus observe/attach hint, and a
#     failed dispatch is reported, never silently dropped (REQ-C1.5).
#
# Runs standalone: ./tests/test-offload-skill.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/offload/SKILL.md"
doc="$REPO_ROOT/doctrine/work-placement.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

# --- doctrine/work-placement.md ------------------------------------------------

if [ ! -f "$doc" ]; then
  fail "doctrine/work-placement.md missing at $doc"
else
  ok "doctrine/work-placement.md exists"

  if grep -qi 'tower-frugality' "$doc"; then
    ok "work-placement states the tower-frugality axiom by name"
  else
    fail "work-placement does not name the tower-frugality axiom (REQ-C1.2)"
  fi

  if grep -qi 'pure reasoning' "$doc" && grep -qi 'operational heartbeat' "$doc"; then
    ok "tower-frugality states the inline boundary (pure reasoning + operational heartbeat)"
  else
    fail "tower-frugality inline boundary incomplete: needs 'pure reasoning' and 'operational heartbeat' (REQ-C1.2)"
  fi

  if grep -qiE 'large or unpredictable context' "$doc"; then
    ok "tower-frugality states the offload boundary (large or unpredictable context ingestion)"
  else
    fail "tower-frugality offload boundary missing: 'large or unpredictable context' (REQ-C1.2)"
  fi

  if grep -qi 'smallest-sufficient-rung' "$doc"; then
    ok "work-placement states the smallest-sufficient-rung axiom by name"
  else
    fail "work-placement does not name the smallest-sufficient-rung axiom (REQ-C1.3)"
  fi

  if grep -qi 'survive the tower' "$doc" \
    && grep -qi 'human-attachable' "$doc" \
    && grep -qi 'beyond the session' "$doc"; then
    ok "smallest-sufficient-rung states all three escalation predicates"
  else
    fail "smallest-sufficient-rung predicates incomplete: needs 'survive the tower', 'human-attachable', 'beyond the session' (REQ-C1.3)"
  fi

  if grep -q 'D-1' "$doc"; then
    ok "work-placement cites its altitude decision (D-1)"
  else
    fail "work-placement does not cite D-1"
  fi
fi

# --- skills/offload/SKILL.md ---------------------------------------------------

if [ ! -f "$skill" ]; then
  fail "offload SKILL.md missing at $skill"
else
  ok "skills/offload/SKILL.md exists"

  # The grep guard the test-spec names (REQ-C1.2/REQ-C1.3): the skill cites the
  # work-placement doctrine doc, as a manifest line and in body prose.
  if grep -qE '^Doctrine: run-start work-placement$' "$skill"; then
    ok "skill carries the machine-parseable manifest line for work-placement"
  else
    fail "skill missing 'Doctrine: run-start work-placement' manifest line"
  fi

  if [ "$(grep -c 'work-placement' "$skill")" -ge 2 ]; then
    ok "skill cites work-placement in body prose beyond the manifest line"
  else
    fail "skill does not cite work-placement outside the manifest line"
  fi

  if grep -qi 'sole home of adaptive' "$skill"; then
    ok "skill declares itself the sole home of adaptive backend selection (REQ-C1.1)"
  else
    fail "skill does not declare the sole-home-of-adaptive-selection property (REQ-C1.1)"
  fi

  # REQ-C1.4 arm 1: an under-determined petition asks, never a silent guess.
  if grep -qi 'under-determin' "$skill" && grep -qiE 'never (silently )?guess' "$skill"; then
    ok "skill states the under-determined-petition ask (never guess)"
  else
    fail "skill missing the under-determined-petition ask-never-guess rule (REQ-C1.4)"
  fi

  # REQ-C1.4 arm 2: a determined-but-unadvertised rung asks; dispatch to an
  # insufficient rung is never silent.
  if grep -qi 'not advertised' "$skill" && grep -qi 'insufficient rung' "$skill"; then
    ok "skill states the unadvertised-rung ask (no silent insufficient dispatch)"
  else
    fail "skill missing the unadvertised-rung ask arm (REQ-C1.4)"
  fi

  # REQ-C1.5: report handle + observe/attach hint; failure never dropped.
  if grep -qi 'handle' "$skill" && grep -qiE 'observe.*attach|attach.*observe' "$skill"; then
    ok "skill states the handle + observe/attach report contract (REQ-C1.5)"
  else
    fail "skill missing the handle + observe/attach report contract (REQ-C1.5)"
  fi

  if grep -qiE 'never silently (dropped|drops)|never a silent drop' "$skill"; then
    ok "skill states the failed-dispatch never-silently-dropped rule (REQ-C1.5)"
  else
    fail "skill missing the failed-dispatch reporting rule (REQ-C1.5)"
  fi

  if grep -q 'offload-dispatch.sh' "$skill"; then
    ok "skill references the offload dispatch primitive"
  else
    fail "skill does not reference scripts/offload-dispatch.sh"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all offload-skill structural tests passed"
