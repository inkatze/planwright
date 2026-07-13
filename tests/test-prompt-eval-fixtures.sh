#!/bin/bash
# Tests for the /orchestrate eval fixtures under tests/prompt-evals/fixtures
# (prompt-hygiene Task 4; D-12). The fixtures' end-to-end grading is the
# credential-gated [manual] baseline run; what is deterministically checkable
# here — and what this suite asserts — is that each fixture's setup.sh seeds a
# hermetic repo in exactly the state /orchestrate's pre-flight gates expect, so a
# baseline failure is a real behavioral signal, not a broken fixture:
#   * every fixture carries the required files (prompt.txt, assert.jq, setup.sh);
#   * the print-ready fixture seeds a bundle that validates 0/0, whose signed
#     brief's anchor recomputes to a match (so the freshness gate passes);
#   * the refuse-draft fixture seeds a Status: Draft bundle (so the status gate
#     refuses);
#   * each assert.jq is a syntactically valid jq program.
# The plugin's own spec-validate.sh / spec-anchor.sh are the graders, resolved
# via PLANWRIGHT_ROOT, then CLAUDE_PLUGIN_ROOT, then a repo-root fallback (in
# this repo planwright IS the checkout, so its scripts sit at REPO_ROOT).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$REPO_ROOT/tests/prompt-evals/fixtures"

# Resolve the planwright plugin whose scripts grade the seeded bundle.
PLUGIN=""
for cand in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "$REPO_ROOT"; do
  [ -n "$cand" ] || continue
  if [ -x "$cand/scripts/spec-anchor.sh" ] && [ -x "$cand/scripts/spec-validate.sh" ]; then
    PLUGIN="$cand"
    break
  fi
done

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd jq; then
  echo "FAIL: jq required" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PROMPT_EVAL_PLUGIN_DIR="$PLUGIN"

# ---- every fixture is well-formed -------------------------------------------
for d in "$FIX"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  for f in prompt.txt assert.jq setup.sh; do
    if [ -f "$d/$f" ]; then ok "$name has $f"; else fail "$name missing $f"; fi
  done
  # assert.jq must compile: a valid program run over an empty object exits 0
  # (it evaluates to false, but without -e that is still a clean exit); a syntax
  # error exits non-zero.
  if printf '{}' | jq "$(cat "$d/assert.jq")" >/dev/null 2>&1; then
    ok "$name assert.jq compiles"
  else
    fail "$name assert.jq does not compile"
  fi
done

# ---- print-ready seeds a gate-valid, anchored bundle ------------------------
if [ -n "$PLUGIN" ]; then
  w="$TMP/ready"
  mkdir -p "$w"
  if (cd "$w" && sh "$FIX/orchestrate-print-ready/setup.sh" "$w") >"$TMP/ready.log" 2>&1; then
    ok "print-ready setup.sh runs"
  else
    fail "print-ready setup.sh failed"
    cat "$TMP/ready.log" >&2
  fi
  spec="$w/specs/demo"
  # Status Ready
  if grep -q '^\*\*Status:\*\* Ready' "$spec/requirements.md" 2>/dev/null; then
    ok "print-ready bundle is Status: Ready"
  else
    fail "print-ready bundle is not Status: Ready"
  fi
  # Validates 0/0 (errors block execution on an executable spec)
  if out="$("$PLUGIN/scripts/spec-validate.sh" "$spec" 2>&1)"; then
    ok "print-ready bundle validates clean ($out)"
  else
    fail "print-ready bundle does not validate: $out"
  fi
  # The signed brief's anchor recomputes to a match (freshness gate would pass).
  recorded="$(grep -oE '[0-9a-f]{40}' "$spec/kickoff-brief.md" | head -n1)"
  computed="$("$PLUGIN/scripts/spec-anchor.sh" "$spec" 2>/dev/null)"
  if [ -n "$recorded" ] && [ "$recorded" = "$computed" ]; then
    ok "print-ready brief anchor matches the bundle ($computed)"
  else
    fail "print-ready brief anchor '$recorded' != computed '$computed'"
  fi
  # The brief carries a sanctioned sign-off shape the gate reads.
  if grep -q '^Lens-pass:' "$spec/kickoff-brief.md" \
    && grep -q 'spec-anchor.sh specs/demo' "$spec/kickoff-brief.md"; then
    ok "print-ready brief carries Lens-pass + sanctioned anchor command form"
  else
    fail "print-ready brief missing Lens-pass or sanctioned command form"
  fi
else
  fail "could not resolve the planwright plugin to grade the ready bundle"
fi

# ---- refuse-draft seeds a Draft bundle --------------------------------------
w="$TMP/draft"
mkdir -p "$w"
if (cd "$w" && sh "$FIX/orchestrate-refuse-draft/setup.sh" "$w") >"$TMP/draft.log" 2>&1; then
  ok "refuse-draft setup.sh runs"
else
  fail "refuse-draft setup.sh failed"
  cat "$TMP/draft.log" >&2
fi
if grep -q '^\*\*Status:\*\* Draft' "$w/specs/demo/requirements.md" 2>/dev/null; then
  ok "refuse-draft bundle is Status: Draft"
else
  fail "refuse-draft bundle is not Status: Draft"
fi

# ---- each assert.jq actually grades: passing outcome true, failing false -----
# Compile-only would pass a tautological "always false" assert; feed each a
# known-good and known-bad outcome and require the right verdict.
grades() {
  # grades <label> <assert.jq> <outcome-json> <expected: true|false>
  got="$(printf '%s' "$3" | jq -e "$(cat "$2")" >/dev/null 2>&1 && echo true || echo false)"
  if [ "$got" = "$4" ]; then ok "$1"; else fail "$1 (got $got, wanted $4)"; fi
}

PR="$FIX/orchestrate-print-ready/assert.jq"
grades "print-ready assert grades a good outcome true" "$PR" \
  '{"is_error":false,"marker_written":true,"result":"run: claude /execute-task demo task-1"}' true
grades "print-ready assert grades a no-marker outcome false" "$PR" \
  '{"is_error":false,"marker_written":false,"result":"run: claude /execute-task demo task-1"}' false
grades "print-ready assert grades an errored outcome false" "$PR" \
  '{"is_error":true,"marker_written":true,"result":"execute-task demo task-1"}' false
grades "print-ready assert tolerates a null result (false, no jq error)" "$PR" \
  '{"is_error":false,"marker_written":true,"result":null}' false

RD="$FIX/orchestrate-refuse-draft/assert.jq"
grades "refuse-draft assert grades a clean refusal true" "$RD" \
  '{"marker_written":false,"branch_created":false,"result":"refused: spec is Draft, not Ready or Active"}' true
grades "refuse-draft assert grades a dispatch (marker) false" "$RD" \
  '{"marker_written":true,"branch_created":false,"result":"refused: Draft"}' false
grades "refuse-draft assert grades a silent no-op (no refusal text) false" "$RD" \
  '{"marker_written":false,"branch_created":false,"result":"nothing to do"}' false
grades "refuse-draft assert tolerates a null result (false, no jq error)" "$RD" \
  '{"marker_written":false,"branch_created":false,"result":null}' false

if [ "$failures" -ne 0 ]; then
  echo "$failures fixture check(s) failed" >&2
  exit 1
fi
echo "all prompt-eval fixture checks passed"
