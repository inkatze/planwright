#!/bin/bash
# Tests for the /spec-kickoff terminal spec-PR ready-flip + the bootstrap D-26
# runtime exception (Task 4 of specs/kickoff-lifecycle; REQ-D1.2, REQ-D1.3,
# REQ-D1.5, D-6, D-7). On clean completion /spec-kickoff marks the *spec* PR
# ready as its terminal step, after any configured verification (the
# review_sequence-class mechanism, D-7) has converged; it leaves the PR draft
# when sign-off parked on a fork, when verification did not converge, or when the
# mark_spec_pr_ready_on_kickoff opt-out is set; a flip failure degrades to
# Awaiting input; and it never auto-merges. The runtime half of the bootstrap
# D-26 supersede moves `gh pr ready` from the worker-settings deny block to allow.
#
# Like Task 3's sibling guard (tests/test-spec-kickoff-ready-flip.sh), the
# ready-flip BEHAVIOR is a skill-prose procedure the agent reads, not a script:
# the [test] half of REQ-D1.2 / REQ-D1.3 / REQ-D1.5's verification paths is a
# structural guard over skills/spec-kickoff/SKILL.md plus the static config
# assertions the spec names (worker-settings.json permits `gh pr ready`; the
# opt-out is documented and scripts/check-options-reference.sh passes). The
# [manual] halves (a clean kickoff readies the PR; a parked kickoff leaves it
# draft) are exercised by the human at review.
#
# Asserted properties:
#   - the skill marks the spec PR ready as the terminal step on clean completion
#     (REQ-D1.2), tied to the configurable review_sequence verification, not a
#     hardcoded gauntlet (REQ-D1.5, D-7);
#   - only the spec PR is readied and task PRs stay drafts (REQ-D1.3), gated by
#     the mark_spec_pr_ready_on_kickoff opt-out;
#   - the skill never auto-merges, and a ready-flip failure degrades to Awaiting
#     input rather than retrying into an opaque failure (REQ-D1.2, K1.6/K1.7);
#   - the superseded absolute "never marks the PR ready" claim is gone, replaced
#     by the narrowed "marks only the spec PR ready";
#   - config/worker-settings.json permits `gh pr ready` (allow, not deny) — the
#     runtime half of the bootstrap D-26 supersede (REQ-D1.2);
#   - mark_spec_pr_ready_on_kickoff is in config/defaults.yml, documented in
#     docs/options-reference.md, and scripts/check-options-reference.sh passes
#     (REQ-D1.3).
#
# Runs standalone: ./tests/test-spec-kickoff-pr-ready.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/spec-kickoff/SKILL.md"
worker_settings="$REPO_ROOT/config/worker-settings.json"
defaults="$REPO_ROOT/config/defaults.yml"
reference="$REPO_ROOT/docs/options-reference.md"
options_check="$REPO_ROOT/scripts/check-options-reference.sh"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

for f in "$skill" "$worker_settings" "$defaults" "$reference"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# Flatten newlines and squeeze whitespace so multi-line prose assertions match
# across markdown line-wraps; the raw file is used for single-line/absence checks.
flat="$(tr '\n' ' ' <"$skill" | tr -s '[:space:]' ' ')"

# REQ-D1.2: the flip is the terminal step of clean completion.
if printf '%s' "$flat" | grep -qE '[Mm]ark the spec PR ready \(terminal step'; then
  ok "ready-flip is named as the terminal step (REQ-D1.2)"
else
  fail "skill does not name the spec-PR ready-flip as a terminal step (REQ-D1.2)"
fi

# REQ-D1.5 / D-7: the pre-flip verification is the configurable review_sequence
# mechanism, not a hardcoded gauntlet.
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
if printf '%s' "$flat" | grep -qE 'configurable `review_sequence`-class mechanism'; then
  ok "verification is the configurable review_sequence-class mechanism (REQ-D1.5, D-7)"
else
  fail "skill does not express the pre-flip verification as the review_sequence-class mechanism (REQ-D1.5)"
fi
if printf '%s' "$flat" | grep -qE 'not a hardcoded\*\* core step'; then
  ok "the verification is explicitly not a hardcoded core step (REQ-D1.5, D-7)"
else
  fail "skill does not state the verification is not hardcoded (REQ-D1.5)"
fi

# REQ-D1.3: only the spec PR is readied; task PRs stay drafts.
if printf '%s' "$flat" | grep -qE 'only the spec PR'; then
  ok "only the spec PR is readied (REQ-D1.3)"
else
  fail "skill does not restrict the ready-flip to 'only the spec PR' (REQ-D1.3)"
fi
if printf '%s' "$flat" | grep -qE 'task PRs stay drafts'; then
  ok "task PRs stay drafts (REQ-D1.3)"
else
  fail "skill does not state 'task PRs stay drafts' (REQ-D1.3)"
fi

# REQ-D1.3: the opt-out gates the flip.
if grep -q 'mark_spec_pr_ready_on_kickoff' "$skill"; then
  ok "the mark_spec_pr_ready_on_kickoff opt-out gates the flip (REQ-D1.3)"
else
  fail "skill does not name the mark_spec_pr_ready_on_kickoff opt-out (REQ-D1.3)"
fi

# REQ-D1.2: never auto-merge.
if grep -q 'never auto-merge' "$skill"; then
  ok "the skill never auto-merges (REQ-D1.2)"
else
  fail "skill does not state it never auto-merges (REQ-D1.2)"
fi

# REQ-D1.2 / K1.6/K1.7: a ready-flip failure degrades to Awaiting input.
if printf '%s' "$flat" | grep -qE 'flip itself fails.{0,200}Awaiting input'; then
  ok "a ready-flip failure degrades to Awaiting input (REQ-D1.2, K1.6/K1.7)"
else
  fail "skill does not bind a ready-flip failure to the Awaiting-input degradation (REQ-D1.2)"
fi

# The new requirement/design citations trace the prose to the contract.
for ref in REQ-D1.2 REQ-D1.3 REQ-D1.5 D-6 D-7; do
  if grep -q "$ref" "$skill"; then
    ok "reference $ref is cited"
  else
    fail "reference $ref is not cited"
  fi
done

# Regression fence: the superseded absolute "never marks the PR ready" claim is
# gone, replaced by the narrowed "marks only the spec PR ready".
if printf '%s' "$flat" | grep -qE 'never marks the PR ready'; then
  fail "stale absolute claim 'never marks the PR ready' still present (REQ-D1.2 supersede)"
else
  ok "stale absolute 'never marks the PR ready' claim removed"
fi
if printf '%s' "$flat" | grep -qE 'marks only the spec PR ready'; then
  ok "skill narrows to 'marks only the spec PR ready'"
else
  fail "skill does not narrow the claim to 'marks only the spec PR ready'"
fi

# REQ-D1.2: worker-settings permits the bare `gh pr ready` un-draft (allow),
# no longer deny. Match the exact allow glob with grep -F so the
# `gh pr ready --undo` deny rules below (which also contain the substring
# "gh pr ready") do not make these assertions false-pass / false-fail.
allow_block="$(sed -n '/"allow": \[/,/\]/p' "$worker_settings")"
deny_block="$(sed -n '/"deny": \[/,/\]/p' "$worker_settings")"
if printf '%s' "$allow_block" | grep -qF 'gh pr ready:*'; then
  ok "worker-settings allow block permits the bare 'gh pr ready' un-draft (REQ-D1.2)"
else
  fail "worker-settings allow block does not permit the bare 'gh pr ready' un-draft (REQ-D1.2)"
fi
if printf '%s' "$deny_block" | grep -qF 'gh pr ready:*'; then
  fail "worker-settings deny block still denies the bare 'gh pr ready' un-draft (REQ-D1.2)"
else
  ok "worker-settings deny block no longer denies the bare 'gh pr ready' un-draft (REQ-D1.2)"
fi
# The `gh pr ready --undo` re-draft form stays denied (un-draft only, never
# re-draft) — the permissions hardening from the Copilot iter-3 review.
if printf '%s' "$deny_block" | grep -qF 'gh pr ready --undo'; then
  ok "worker-settings deny block denies the 'gh pr ready --undo' re-draft form"
else
  fail "worker-settings deny block does not deny 'gh pr ready --undo' (re-draft guardrail missing)"
fi

# REQ-D1.3: the option is in the default config.
if grep -qE '^mark_spec_pr_ready_on_kickoff:[[:space:]]*true' "$defaults"; then
  ok "mark_spec_pr_ready_on_kickoff: true is in config/defaults.yml (REQ-D1.3)"
else
  fail "mark_spec_pr_ready_on_kickoff is not a default config option (REQ-D1.3)"
fi

# REQ-D1.3: the option has a reference row.
# shellcheck disable=SC2016 # the backtick is literal markdown, not expansion
if grep -qE '^\|[[:space:]]*`mark_spec_pr_ready_on_kickoff`' "$reference"; then
  ok "mark_spec_pr_ready_on_kickoff has a docs/options-reference.md row (REQ-D1.3)"
else
  fail "mark_spec_pr_ready_on_kickoff has no row in docs/options-reference.md (REQ-D1.3)"
fi

# REQ-D1.3: the options-reference drift check passes with the new option.
# Invoke via /bin/bash (the canonical entrypoint: mise.toml and
# tests/test-check-options-reference.sh run it that way) so the assertion does
# not depend on the executable bit surviving the checkout.
if [ -f "$options_check" ]; then
  if /bin/bash "$options_check" >/dev/null 2>&1; then
    ok "scripts/check-options-reference.sh passes (REQ-D1.3)"
  else
    fail "scripts/check-options-reference.sh fails (REQ-D1.3)"
  fi
else
  fail "scripts/check-options-reference.sh missing"
fi

# ---------------------------------------------------------------------------
# Task 6 (specs/skill-rigor; REQ-B1.1, D-3): the terminal ready-flip gates on
# the head SHA's CI check rollup before `gh pr ready`. REQ-B1.1's verification
# path is [design-level + manual]; these structural assertions fence the
# documented rollup query, positive-green condition, bounded wait, head re-pin,
# refusal arm, and no-PR skip against a regression. The [manual] half (a real
# red CI leaves the PR draft with the remedy surfaced; a green one flips it; a
# mid-wait push refuses the flip) is exercised by the human at review.
# ---------------------------------------------------------------------------

# REQ-B1.1: the rollup is pinned to the head commit's checks, never PR review
# states (an errored/stale review must not masquerade as a completed check).
if printf '%s' "$flat" | grep -qE "head commit's.{0,40}statusCheckRollup"; then
  ok "the ready-flip queries the head commit's statusCheckRollup (REQ-B1.1)"
else
  fail "the ready-flip does not pin the rollup to the head commit's checks (REQ-B1.1)"
fi
if printf '%s' "$flat" | grep -qE 'never PR review states'; then
  ok "the rollup excludes PR review states (REQ-B1.1, D-3)"
else
  fail "the rollup does not exclude PR review states (REQ-B1.1)"
fi

# REQ-B1.1: the positive-green condition — at least one completed check AND
# overall success (an empty rollup is not success).
if printf '%s' "$flat" | grep -qE 'at least one completed check and overall success'; then
  ok "the flip requires at least one completed check and overall success (REQ-B1.1)"
else
  fail "the flip's positive-green condition is not stated (REQ-B1.1)"
fi

# REQ-B1.1 / D-3: the wait is bounded by the kickoff_ready_ci_wait config knob.
if printf '%s' "$flat" | grep -qE 'kickoff_ready_ci_wait'; then
  ok "the CI wait is bounded by the kickoff_ready_ci_wait knob (REQ-B1.1, D-3)"
else
  fail "the CI gate does not reference the kickoff_ready_ci_wait wait bound (REQ-B1.1)"
fi

# REQ-B1.1 (risk R3): head identity is re-confirmed immediately before the flip;
# a head that moved during the wait refuses it.
if printf '%s' "$flat" | grep -qE 'Re-confirm head identity'; then
  ok "head identity is re-confirmed before the flip (REQ-B1.1, R3)"
else
  fail "the skill does not re-confirm head identity before the flip (REQ-B1.1)"
fi
if printf '%s' "$flat" | grep -qE 'moved .{0,40}refuses the flip'; then
  ok "a head that moved during the wait refuses the flip (REQ-B1.1, R3)"
else
  fail "a moved head is not bound to refusing the flip (REQ-B1.1)"
fi

# REQ-B1.1: the refusal arm leaves the PR draft and records the pending
# ready-flip in Awaiting input as the re-entry point, naming only the neutral
# failure class (full remedy detail stays operator-facing, D-3).
if printf '%s' "$flat" | grep -qE 'red, empty, unresolved, a query failure, an expired wait, or a moved head'; then
  ok "the refusal arm enumerates every failure class (REQ-B1.1)"
else
  fail "the refusal arm does not enumerate the failure classes (REQ-B1.1)"
fi
if printf '%s' "$flat" | grep -qE 'pending ready-flip in .{0,40}Awaiting.{0,20}input.{0,80}re-entry'; then
  ok "the refusal arm records the pending flip in Awaiting input as the re-entry point (REQ-B1.1)"
else
  fail "the refusal arm does not record the pending flip as an Awaiting-input re-entry (REQ-B1.1)"
fi
if printf '%s' "$flat" | grep -qE 'neutral failure class only'; then
  ok "the Awaiting-input entry names only the neutral failure class (REQ-B1.1, D-3 hygiene)"
else
  fail "the Awaiting-input entry does not restrict to the neutral failure class (REQ-B1.1)"
fi

# REQ-B1.1: the gate skips cleanly when the upstream no-remote/no-PR arm fired.
if printf '%s' "$flat" | grep -qE 'no-remote/no-PR degradation arm .{0,40}already fired'; then
  ok "the CI gate skips cleanly when the no-remote/no-PR arm already fired (REQ-B1.1)"
else
  fail "the CI gate does not skip when the no-remote/no-PR arm already fired (REQ-B1.1)"
fi

# REQ-B1.1 / D-3 citations trace the new prose to the contract.
for ref in REQ-B1.1 D-3; do
  if grep -q "$ref" "$skill"; then
    ok "reference $ref is cited"
  else
    fail "reference $ref is not cited"
  fi
done

# REQ-B1.1 / D-3: the wait-bound knob is registered in the default config with a
# reference row (bootstrap D-43/REQ-K1.8; the check-options-reference run above
# also covers the pairing).
if grep -qE '^kickoff_ready_ci_wait:[[:space:]]*10m' "$defaults"; then
  ok "kickoff_ready_ci_wait: 10m is in config/defaults.yml (REQ-B1.1)"
else
  fail "kickoff_ready_ci_wait is not a default config option (REQ-B1.1)"
fi
# shellcheck disable=SC2016 # the backtick is literal markdown, not expansion
if grep -qE '^\|[[:space:]]*`kickoff_ready_ci_wait`' "$reference"; then
  ok "kickoff_ready_ci_wait has a docs/options-reference.md row (REQ-B1.1)"
else
  fail "kickoff_ready_ci_wait has no row in docs/options-reference.md (REQ-B1.1)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-kickoff spec-PR ready-flip tests passed"
