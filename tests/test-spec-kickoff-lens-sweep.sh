#!/bin/bash
# Structural guard for the /spec-kickoff mid-walk lens and post-lens
# stale-reference sweep (Task 7 of specs/skill-rigor; REQ-B1.4, REQ-B1.5, D-5,
# D-6). Task 7 adds two walkthrough-time verification passes to the kickoff flow:
#   - a delta-scoped lens pass at the point an agent-authored meaning-class edit
#     is applied mid-walk, its disposition recorded in the brief (REQ-B1.4, D-5);
#   - a post-lens stale-reference sweep over the bundle and earlier brief
#     sections whenever any lens pass (mid-walk or terminal) mints or re-scopes a
#     REQ, run before the anchor is computed and before the D-4 recorded-claim
#     re-derivation is finalized (REQ-B1.5, D-6).
#
# This is a skill-prose change: the passes are procedures the agent reads, not a
# script, so the [test] half of REQ-B1.5's verification path is a structural
# guard. Because spec-kickoff/SKILL.md sits against its instruction budget (~3
# words of headroom before a floor-breach), Task 7 follows Task 6's precedent
# (REQ-E1.1 compensating trim by relocation): the heavy mechanics live in
# doctrine/kickoff-verification.md (resolved point-of-use), and the skill body
# keeps only the lean point-of-use references and their triggers. So the
# mechanics assertions below target the doctrine doc; the reference + trigger
# assertions target the skill. The [manual] halves (a planted mid-walk defect is
# caught at application; a seeded stale count is reconciled by the sweep) are
# exercised by the human at review; this test fences the structural properties
# against a regression.
#
# Runs standalone: ./tests/test-spec-kickoff-lens-sweep.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/spec-kickoff/SKILL.md"
gate_doc="$REPO_ROOT/doctrine/kickoff-verification.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

for f in "$skill" "$gate_doc"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# Flatten newlines and squeeze runs of whitespace to a single space so the
# multi-line prose assertions match across markdown line-wraps and the
# indentation that follows them; the raw file is used for single-line and
# citation checks.
flat_skill="$(tr '\n' ' ' <"$skill" | tr -s '[:space:]' ' ')"
flat_doc="$(tr '\n' ' ' <"$gate_doc" | tr -s '[:space:]' ' ')"

# --- Skill body: the lean point-of-use references + triggers (REQ-B1.4, B1.5) ---

# REQ-B1.4: the walkthrough names the mid-walk delta-scoped lens at the point an
# agent-authored meaning-class edit is applied, its disposition brief-recorded.
# Bounded gaps keep the phrases inside one clause so a scattered co-occurrence
# cannot satisfy the match.
if printf '%s' "$flat_skill" | grep -qE 'meaning-class edit.{0,80}mid-walk.{0,40}lens pass'; then
  ok "walkthrough names the mid-walk lens at a meaning-class edit (REQ-B1.4)"
else
  fail "walkthrough does not tie a meaning-class edit to the mid-walk lens pass (REQ-B1.4)"
fi
if printf '%s' "$flat_skill" | grep -qE 'point of application'; then
  ok "walkthrough places the mid-walk lens at the point of application (REQ-B1.4)"
else
  fail "walkthrough does not place the mid-walk lens 'at the point of application' (REQ-B1.4)"
fi
if printf '%s' "$flat_skill" | grep -qE 'disposition recorded in the brief'; then
  ok "the mid-walk lens disposition is recorded in the brief (REQ-B1.4)"
else
  fail "the mid-walk lens disposition is not stated as 'recorded in the brief' (REQ-B1.4)"
fi

# REQ-B1.5: the sign-off names the stale-reference sweep, its minting trigger,
# and its ordering (before the anchor and before the recorded-claim
# re-derivation).
if printf '%s' "$flat_skill" | grep -qE 'stale-reference sweep'; then
  ok "sign-off names the stale-reference sweep (REQ-B1.5)"
else
  fail "sign-off does not name the 'stale-reference sweep' (REQ-B1.5)"
fi
if printf '%s' "$flat_skill" | grep -qE 'mints or re-scopes a REQ|minted or re-scoped a REQ'; then
  ok "the sweep trigger is a lens pass minting/re-scoping a REQ (REQ-B1.5)"
else
  fail "the sweep trigger (a lens pass minting/re-scoping a REQ) is not stated (REQ-B1.5)"
fi
if printf '%s' "$flat_skill" | grep -qE 'before the anchor'; then
  ok "the sweep runs before the anchor is computed (REQ-B1.5, D-6)"
else
  fail "the sweep is not ordered 'before the anchor' (REQ-B1.5, D-6)"
fi
if printf '%s' "$flat_skill" | grep -qE 'before the .{0,40}re-derivation'; then
  ok "the sweep completes before the recorded-claim re-derivation (REQ-B1.5, D-4)"
else
  fail "the sweep is not ordered before the recorded-claim re-derivation (REQ-B1.5, D-4)"
fi

# Both skill references point at the doctrine doc that carries the mechanics
# (the Task 6 relocation precedent). The skill must name kickoff-verification at
# both new passes; it already names it once (the terminal ready-flip gate), so
# require strictly more than one occurrence.
kv_count="$(grep -c 'kickoff-verification' "$skill")"
if [ "$kv_count" -ge 3 ]; then
  ok "the skill references kickoff-verification at both new passes (count $kv_count >= 3)"
else
  fail "the skill does not add kickoff-verification references for both new passes (count $kv_count < 3)"
fi

# The new-pass requirement citations are present so the prose traces to contract.
for req in REQ-B1.4 REQ-B1.5; do
  if grep -q "$req" "$skill"; then
    ok "requirement $req is cited in the skill"
  else
    fail "requirement $req is not cited in the skill"
  fi
done

# --- Doctrine doc: the relocated mechanics (REQ-B1.4, REQ-B1.5, D-5, D-6) ---

# Mid-walk lens mechanics: point of application, delta-scoped, brief-recorded
# disposition, erroring pass surfaced, terminal pass unchanged.
if printf '%s' "$flat_doc" | grep -qE 'point of application'; then
  ok "doctrine: mid-walk lens runs at the point of application (REQ-B1.4, D-5)"
else
  fail "doctrine: mid-walk lens is not placed 'at the point of application' (REQ-B1.4, D-5)"
fi
if printf '%s' "$flat_doc" | grep -qE 'delta-scoped'; then
  ok "doctrine: the mid-walk lens is delta-scoped (D-5)"
else
  fail "doctrine: the mid-walk lens is not stated delta-scoped (D-5)"
fi
if printf '%s' "$flat_doc" | grep -qE 'recorded in the brief'; then
  ok "doctrine: the mid-walk lens disposition is recorded in the brief (REQ-B1.4)"
else
  fail "doctrine: the mid-walk lens disposition is not 'recorded in the brief' (REQ-B1.4)"
fi
if printf '%s' "$flat_doc" | grep -qE 'erroring pass.{0,40}surfaced|surfaced, never treated as clean'; then
  ok "doctrine: an erroring mid-walk lens pass is surfaced (REQ-B1.4, D-5)"
else
  fail "doctrine: an erroring mid-walk lens pass is not stated surfaced (REQ-B1.4, D-5)"
fi
if printf '%s' "$flat_doc" | grep -qE 'terminal.{0,40}lens pass.{0,40}unchanged|terminal sign-off.{0,40}unchanged'; then
  ok "doctrine: the terminal sign-off lens pass is unchanged (REQ-B1.4, D-5)"
else
  fail "doctrine: the terminal lens pass is not stated unchanged (REQ-B1.4, D-5)"
fi

# Sweep mechanics: minting trigger, the four target classes, and the two
# orderings (before the anchor; before the D-4 re-derivation is finalized).
if printf '%s' "$flat_doc" | grep -qE 'mints or re-scopes a REQ'; then
  ok "doctrine: the sweep trigger is any lens pass minting/re-scoping a REQ (REQ-B1.5, D-6)"
else
  fail "doctrine: the sweep trigger (minting/re-scoping a REQ) is not stated (REQ-B1.5, D-6)"
fi
for target in 'counts' 'cross-references' 'dependent task and test wording' 'risk-IDs'; do
  if printf '%s' "$flat_doc" | grep -qF "$target"; then
    ok "doctrine: the sweep target '$target' is named (REQ-B1.5)"
  else
    fail "doctrine: the sweep target '$target' is not named (REQ-B1.5)"
  fi
done
if printf '%s' "$flat_doc" | grep -qE 'before the anchor'; then
  ok "doctrine: the sweep runs before the anchor is computed (REQ-B1.5, D-6)"
else
  fail "doctrine: the sweep is not ordered 'before the anchor' (REQ-B1.5, D-6)"
fi
if printf '%s' "$flat_doc" | grep -qE 'before the .{0,60}re-derivation is finalized'; then
  ok "doctrine: the sweep completes before the D-4 re-derivation is finalized (REQ-B1.5, D-4)"
else
  fail "doctrine: the sweep ordering vs the D-4 re-derivation is not stated (REQ-B1.5, D-4)"
fi

# Doctrine citations present.
for ref in REQ-B1.4 REQ-B1.5 D-5 D-6; do
  if grep -q "$ref" "$gate_doc"; then
    ok "doctrine cites $ref"
  else
    fail "doctrine does not cite $ref"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-kickoff lens/sweep structural tests passed"
