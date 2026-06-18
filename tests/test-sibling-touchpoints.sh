#!/bin/bash
# Tests for the sibling discoverability touchpoints (Task 10 of
# specs/spec-comprehension; REQ-F1.2, D-11). `/spec-draft`'s handoff,
# `/spec-kickoff`'s pre-flight, and `/resume` each SHALL surface
# `/spec-walkthrough` as a recommended independent human step, and SHALL NOT
# auto-invoke it.
#
# This is the [test] half of REQ-F1.2's verification path. It is a structural
# guard over the three sibling SKILL.md files:
#   - each file mentions `/spec-walkthrough` (the recommendation is present);
#   - at least one such mention carries a recommendation marker
#     (recommend / suggest / optional / independent / may), so the touchpoint
#     reads as a suggestion rather than a bare cross-reference;
#   - no line mentioning `/spec-walkthrough` carries an invocation directive
#     (invoke / dispatch / auto-invoke / auto-run / chain into / automatically
#     run|invoke|launch) — the never-auto-chain invariant D-11 protects.
#
# The [manual] half (the wording reads as genuinely suggest-only) is exercised
# by the human at review; this test guards the structural property and is a
# regression fence against a future edit slipping in an auto-invocation.
#
# Runs standalone: ./tests/test-sibling-touchpoints.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

# The three sibling skills that must surface the recommendation. The
# `/spec-walkthrough` skill itself is deliberately excluded — it is the command
# being recommended, not a touchpoint.
siblings="spec-draft spec-kickoff resume"

# A recommendation-framing marker (case-insensitive). Presence of one of these
# in the touchpoint is what distinguishes a recommendation from a bare
# reference. Kept to plain alternation (no `\b` word-boundary) to hold the
# portable BSD-tooling floor the rest of the suite observes (REQ-K1.5).
rec_marker='recommend|suggest|optional|independent'

# An agent-directed invocation directive (case-insensitive). None of these may
# appear on a line that mentions `/spec-walkthrough`: the touchpoint recommends,
# the human acts; the skill never runs the command itself. "run" on its own is
# allowed (the human runs it); only the auto-/agent-imperative forms are
# forbidden.
invoke_pattern='invoke|dispatch|auto-?invoke|auto-?run|chain into|automatically (run|invoke|launch)|chains? into'

for s in $siblings; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  if [ ! -f "$f" ]; then
    fail "$s: SKILL.md missing at $f"
    continue
  fi

  # The touchpoint context: every line mentioning the command, on its own
  # boundary (so a hypothetical `/spec-walkthrough-foo` would not satisfy the
  # assertion), plus a ±3-line window. The window spans a wrapped markdown
  # bullet, so the recommendation framing and any invocation directive are
  # caught wherever they fall in the touchpoint, not only on the physical line
  # the command token happens to wrap onto.
  if ! grep -qE '/spec-walkthrough([^a-z-]|$)' "$f"; then
    fail "$s: no /spec-walkthrough recommendation present (REQ-F1.2)"
    continue
  fi
  ok "$s: /spec-walkthrough recommendation present"
  context="$(grep -nE -A3 -B3 '/spec-walkthrough([^a-z-]|$)' "$f")"

  # The touchpoint carries a recommendation marker.
  if printf '%s\n' "$context" | grep -qiE "$rec_marker"; then
    ok "$s: recommendation is framed as a suggestion (marker present)"
  else
    fail "$s: /spec-walkthrough mentioned but no recommendation marker (REQ-F1.2 suggest-only framing)"
  fi

  # The touchpoint carries no invocation directive.
  if bad="$(printf '%s\n' "$context" | grep -iE "$invoke_pattern")"; then
    fail "$s: /spec-walkthrough touchpoint carries an invocation directive (D-11 forbids auto-invoke): $bad"
  else
    ok "$s: no invocation directive in the /spec-walkthrough touchpoint"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all sibling-touchpoint tests passed"
