#!/bin/bash
# Tests for /spec-kickoff's terminal re-anchor (Task 6 of specs/anchor-integrity;
# REQ-C1.4, D-5). Sign-off writes the anchor last, but anything that edits
# anchored content AFTER that record is written — a review or panel fix on the
# spec PR, a late correction before the push — leaves the recorded anchor
# describing text that is no longer in the bundle. Pushing then ships a stale
# anchor in the spec PR and its squash, and the next worker halts on a freshness
# mismatch nobody caused. This task closes that window with a terminal recompute
# as the final pre-push step.
#
# Like its siblings this is a skill-prose change: the finishing ritual is
# procedure the agent reads, not a script, so the mechanical half of REQ-C1.4's
# verification path is a structural guard over skills/spec-kickoff/SKILL.md (the
# same shape as tests/test-spec-kickoff-ready-flip.sh and
# tests/test-execute-task-status-gate.sh). The [manual] half — the next kickoff
# run whose spec PR receives post-sign-off fixes — is exercised by the human,
# with the REQ-D1.1 anchor-freshness guard as the mechanical backstop.
#
# Asserted properties:
#   - the finishing ritual names a terminal re-anchor step and cites REQ-C1.4;
#   - its trigger is anchored content edited after the sign-off record was
#     written, naming post-sign-off fixes on the spec PR as covered;
#   - the recompute and re-record are the FINAL PRE-PUSH step, both by wording
#     and by position: the step precedes the push command in the file;
#   - the lane is expression-only; a meaning-class post-sign-off edit re-enters
#     the sign-off flow before any record is written (meaning-class anchor
#     writership is not widened by this step);
#   - a failing recompute halts the push, so the prior anchor never ships as if
#     fresh.
#
# Runs standalone: ./tests/test-spec-kickoff-terminal-reanchor.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/spec-kickoff/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

if [ ! -f "$skill" ]; then
  echo "FAIL: spec-kickoff SKILL.md missing at $skill" >&2
  exit 1
fi

# Flatten newlines and squeeze whitespace runs to a single space so the prose
# assertions match across markdown line-wraps and the indentation that follows
# them; the raw file is used for the positional check below.
flat="$(tr '\n' ' ' <"$skill" | tr -s '[:space:]' ' ')"

# The step exists and is named, so the handoff and later readers have something
# to point at. Bind to the step label rather than a bare "recompute", which the
# pre-flight freshness comparison and sign-off step 5 also use.
if printf '%s' "$flat" | grep -qE '[Tt]erminal re-anchor'; then
  ok "the finishing ritual names a terminal re-anchor step"
else
  fail "no 'terminal re-anchor' step in the finishing ritual (REQ-C1.4)"
fi

# The contract citation, so the prose traces back to the requirement.
if grep -q 'REQ-C1.4' "$skill"; then
  ok "requirement REQ-C1.4 is cited"
else
  fail "requirement REQ-C1.4 is not cited"
fi

# The trigger is an edit to anchored content AFTER the sign-off record was
# written. Bind the two halves inside one sentence with a bounded gap (the
# {0,N} width is sized just past the live wording, in C-locale bytes, so a
# multi-byte em-dash counts as its UTF-8 length): wide enough for the prose,
# tight enough that a cross-sentence co-occurrence cannot satisfy it.
if printf '%s' "$flat" \
  | grep -qE '[Aa]nchored content.{0,80}after the sign-off record was written'; then
  ok "the trigger is anchored content edited after the sign-off record was written"
else
  fail "the trigger is not bound to anchored content edited after the sign-off record (REQ-C1.4)"
fi

# Post-sign-off fixes on the spec PR are the motivating case and are named, so a
# reader does not read the trigger as covering only edits made before the first
# push.
if printf '%s' "$flat" | grep -qE 'post-sign-off review or panel fixes on the spec PR'; then
  ok "post-sign-off fixes on the spec PR are named as covered"
else
  fail "post-sign-off fixes on the spec PR are not named as covered by the trigger"
fi

# The recompute and re-record are the final PRE-PUSH step: both actions are
# stated (a recompute that is not re-recorded still ships the stale anchor), and
# they are placed before the push.
if printf '%s' "$flat" | grep -qE 're-record.{0,60}final pre-push step'; then
  ok "the recompute is re-recorded as the final pre-push step"
else
  fail "the step does not state a re-record as the final pre-push step (REQ-C1.4)"
fi

# Positional mirror of the wording above: the step must physically precede the
# push command in the file, so an agent reading top-to-bottom reaches it before
# pushing. Compare the first line of each; a step that drifted below the push
# would still match the wording checks but ship the stale anchor.
reanchor_line="$(grep -nE -m1 '[Tt]erminal re-anchor' "$skill" | cut -d: -f1)"
push_line="$(grep -nE -m1 'git push -u origin planwright/' "$skill" | cut -d: -f1)"
if [ -n "$reanchor_line" ] && [ -n "$push_line" ] \
  && [ "$reanchor_line" -lt "$push_line" ]; then
  ok "the terminal re-anchor step precedes the push command (line $reanchor_line < $push_line)"
else
  fail "the terminal re-anchor step does not precede the push command (re-anchor=${reanchor_line:-none}, push=${push_line:-none})"
fi

# The lane is expression-only, and a meaning-class post-sign-off edit re-enters
# the sign-off flow before any record is written. This is what keeps
# meaning-class anchor writership on the walked-and-signed path (REQ-C1.3's
# writership rule) instead of letting the terminal step re-sign meaning.
if printf '%s' "$flat" | grep -qE '[Ee]xpression-only edits only'; then
  ok "the terminal re-anchor lane is expression-only"
else
  fail "the terminal re-anchor step does not scope itself to expression-only edits (REQ-C1.4)"
fi
if printf '%s' "$flat" \
  | grep -qE 'meaning-class post-sign-off edit re-enters the sign-off flow'; then
  ok "a meaning-class post-sign-off edit re-enters the sign-off flow"
else
  fail "a meaning-class post-sign-off edit is not routed back into the sign-off flow (REQ-C1.4)"
fi

# A failing recompute halts the push. Bind the failure to the halt so an
# inverted-semantics regression (warn and push anyway) cannot pass.
if printf '%s' "$flat" | grep -qE 'failing recompute halts the push'; then
  ok "a failing recompute halts the push"
else
  fail "a failing recompute is not stated to halt the push (REQ-C1.4)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-kickoff terminal re-anchor tests passed"
