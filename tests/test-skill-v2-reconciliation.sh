#!/bin/bash
# Tests for the format-version 2 skill reconciliation (specs/invariant-tasks
# Task 7; REQ-E1.2, D-6, D-7, D-8, D-3). Every state-layer-touching skill must
# reference the correct v2 read surface — the render (`scripts/spec-status.sh`,
# `mise run status`) for human-facing status, the derivation engine
# (`scripts/orchestrate-state.sh`) for machine logic, never committed placement
# sections — and every reconciliation must be version-keyed off the bundle's
# declared `Format-version:` with v1 behavior unchanged (D-7). Skills are
# procedure the agent reads, not scripts, so REQ-E1.2's design-level
# verification path is a structural guard over the SKILL.md prose (the same
# shape as tests/test-execute-task-status-write.sh).
#
# Asserted properties, per skill:
#   - /spec-draft authors v2 bundles: the skeleton declares
#     `**Format-version:** 2` with the canonical `**Execution:**` pointer line,
#     task blocks land in a single `## Tasks` section (no unconditional
#     `## Forward plan` skeleton), extend mode keys off the target bundle's
#     declared `Format-version:`, and a bundle materialized from the documented
#     skeleton passes `scripts/spec-validate.sh` cleanly;
#   - /execute-task drops the `Last activity` write on v2 bundles, keeps
#     committed Awaiting-input writes in reference-bullet form, confirms
#     dependencies through the derivation engine on v2, and skips the PR-step
#     annotation on v2;
#   - /resume reads the render for v2 execution status;
#   - /orchestrate's selection describes v2 candidacy via reference bullets,
#     its orphan reconcile parks via an Awaiting-input reference bullet written
#     on the primary checkout's main view, and --bookkeeping's placement
#     reconcile is scoped to v1;
#   - /drain resolves completion atoms through the derivation engine and scopes
#     `commit_on_state_move` to v1;
#   - /spec-kickoff documents Ready as the v2 header's resting state and reads
#     derived execution state for delta/amendment mode selection.
#
# Runs standalone: ./tests/test-skill-v2-reconciliation.sh
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

# flat <file> — newline-flattened, whitespace-squeezed body so cross-line
# prose matches are stable against rewrapping at the wrap point.
flat() {
  tr '\n' ' ' <"$1" | tr -s ' '
}

for s in spec-draft execute-task resume orchestrate drain spec-kickoff; do
  if [ ! -f "$REPO_ROOT/skills/$s/SKILL.md" ]; then
    echo "FAIL: skills/$s/SKILL.md missing" >&2
    exit 1
  fi
done

# --- /spec-draft: authors v2 bundles (REQ-E1.2, D-2, D-5) ---

sd="$(flat "$REPO_ROOT/skills/spec-draft/SKILL.md")"

if printf '%s' "$sd" | grep -qE '\*\*Format-version:\*\* 2'; then
  ok "spec-draft: skeleton declares Format-version: 2"
else
  fail "spec-draft: skeleton does not declare '**Format-version:** 2' (REQ-E1.2: /spec-draft authors v2 bundles)"
fi

if printf '%s' "$sd" | grep -qE '\*\*Execution:\*\* derived — see the status render'; then
  ok "spec-draft: skeleton carries the canonical pointer line (D-5)"
else
  fail "spec-draft: canonical '**Execution:** derived — see the status render' pointer line missing (D-5)"
fi

if printf '%s' "$sd" | grep -qE 'single .## Tasks. section'; then
  ok "spec-draft: task blocks land in a single ## Tasks section (D-2)"
else
  fail "spec-draft: does not instruct a single '## Tasks' section for task blocks (D-2)"
fi

if printf '%s' "$sd" | grep -qE 'All blocks start in .## Forward plan.'; then
  fail "spec-draft: still instructs the unconditional v1 '## Forward plan' skeleton (v2 authoring must not write placement sections)"
else
  ok "spec-draft: no unconditional Forward-plan skeleton"
fi

if printf '%s' "$sd" | grep -qE '[Ee]xtend[^.]{0,160}declared .Format-version:'; then
  ok "spec-draft: extend mode keys off the target bundle's declared Format-version (D-7)"
else
  fail "spec-draft: extend mode is not keyed to the target bundle's declared Format-version: (D-7: v1 bundles keep v1 conventions)"
fi

# --- /spec-draft: the documented skeleton validates as v2 (REQ-E1.2) ---
# Materialize a minimal bundle exactly as the skill's skeleton describes —
# the shared v2 header block (Status Draft, Format-version 2, pointer line)
# and the v2 tasks.md shape (## Tasks plus the three human-payload sections
# with (none yet) placeholders) — and run the real validator over it.

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/skill-v2-recon.XXXXXX")" || exit 1
trap 'rm -rf "$tmpdir"' EXIT
fx="$tmpdir/specs/fixture"
mkdir -p "$fx"

cat >"$fx/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

A fixture bundle drafted per the /spec-draft v2 skeleton.

## Scope

### In scope

- The widget.

### Out of scope

- Everything else.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*

## Changelog

- 2026-07-15 — Initial draft.

## Sources

- the fixture seed.
EOF

cat >"$fx/design.md" <<'EOF'
# Fixture — Design

**Status:** Draft
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Decision log

### D-1: Widgets are good  (N)

**Decision:** Build widgets.

**Alternatives considered:**
- No widgets. Rejected because: nothing would exist.

**Chosen because:** widgets are the fixture's point.
EOF

cat >"$fx/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Build the widget

- **Deliverables:** A widget.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF

cat >"$fx/test-spec.md" <<'EOF'
# Fixture — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

Coverage is a fixture mix.

### REQ-X1.1 — widget exists [test]

The widget fixture passes.
EOF

vout="$(cd "$tmpdir" && "$REPO_ROOT/scripts/spec-validate.sh" specs/fixture 2>&1)"
vrc=$?
if [ "$vrc" -eq 0 ] && printf '%s' "$vout" | grep -q '0 error(s), 0 warning(s)'; then
  ok "spec-draft: the documented v2 skeleton validates cleanly (exit 0, no findings)"
else
  fail "spec-draft: the documented v2 skeleton does not validate cleanly (exit $vrc): $vout"
fi

# --- /execute-task: v2 state-write reconciliation (REQ-E1.2, D-7, D-3) ---

et="$(flat "$REPO_ROOT/skills/execute-task/SKILL.md")"

if printf '%s' "$et" | grep -qE 'format-version 2 bundle this step writes nothing'; then
  ok "execute-task: drops the Last-activity write on v2 bundles"
else
  fail "execute-task: does not drop the Last-activity write on v2 bundles (REQ-E1.2: 'format-version 2 bundle this step writes nothing')"
fi

if printf '%s' "$et" | grep -qE 'committed reference bullet'; then
  ok "execute-task: Awaiting-input writes stay committed in reference-bullet form (D-3)"
else
  fail "execute-task: Awaiting-input bullet form missing ('committed reference bullet', D-3)"
fi

if printf '%s' "$et" | grep -qE 'orchestrate-state\.sh'; then
  ok "execute-task: v2 dependency completion reads the derivation engine"
else
  fail "execute-task: does not name the derivation engine (scripts/orchestrate-state.sh) for v2 dependency checks (D-6)"
fi

if printf '%s' "$et" | grep -qE 'no annotation exists to write'; then
  ok "execute-task: PR-creation annotation step is skipped on v2"
else
  fail "execute-task: PR-creation annotation step not version-keyed ('no annotation exists to write' on v2 missing)"
fi

# v1 behavior unchanged: the v1 Last-activity write survives (the sibling
# guard test-execute-task-status-write.sh pins its exact sentence; assert
# presence here so this file fails standalone too).
if printf '%s' "$et" | grep -qE 'Update only the task block.s .- \*\*Last activity:\*\* <today>'; then
  ok "execute-task: v1 Last-activity write preserved (v1 behavior unchanged)"
else
  fail "execute-task: v1 Last-activity write sentence missing (REQ-E1.2: v1 behavior must be unchanged)"
fi

# --- /resume: human-facing status reads the render (REQ-E1.2, D-6) ---

rs="$(flat "$REPO_ROOT/skills/resume/SKILL.md")"

if printf '%s' "$rs" | grep -qE 'mise run status|spec-status\.sh'; then
  ok "resume: reads the render for v2 execution status"
else
  fail "resume: does not reference the render (mise run status / scripts/spec-status.sh) for v2 status (D-6)"
fi

if printf '%s' "$rs" | grep -qE '[Ff]ormat-version'; then
  ok "resume: tasks.md read is version-keyed"
else
  fail "resume: tasks.md read is not version-keyed on Format-version: (D-7)"
fi

# --- /orchestrate: selection, orphan park, bookkeeping (REQ-E1.2, D-8) ---

oc="$(flat "$REPO_ROOT/skills/orchestrate/SKILL.md")"

if printf '%s' "$oc" | grep -qE 'reference bullet'; then
  ok "orchestrate: v2 parked-ness described via reference bullets (D-8)"
else
  fail "orchestrate: selection does not describe v2 parked-ness via reference bullets (D-8)"
fi

if printf '%s' "$oc" | grep -qE 'Awaiting-input reference bullet[^.]{0,160}main view'; then
  ok "orchestrate: orphan reconcile parks via an Awaiting-input reference bullet on the main view"
else
  fail "orchestrate: orphan reconcile does not park via an Awaiting-input reference bullet written on the primary checkout's main view (REQ-E1.2, REQ-B1.4)"
fi

if printf '%s' "$oc" | grep -qE 'no placement to reconcile'; then
  ok "orchestrate: --bookkeeping placement reconcile scoped to v1"
else
  fail "orchestrate: --bookkeeping placement reconcile not scoped to v1 ('no placement to reconcile' on v2 missing)"
fi

# --- /drain: gate atoms via the derivation engine (REQ-E1.2, D-8) ---

dr="$(flat "$REPO_ROOT/skills/drain/SKILL.md")"

if printf '%s' "$dr" | grep -qE 'derivation engine'; then
  ok "drain: completion atoms resolve through the derivation engine"
else
  fail "drain: does not name the derivation engine for task-completion atoms (D-8)"
fi

if printf '%s' "$dr" | grep -qE 'commit_on_state_move[^.]{0,200}(v1|version 1)'; then
  ok "drain: commit_on_state_move scoped to v1 bundles"
else
  fail "drain: commit_on_state_move is not scoped to v1 (v2 edits are human-payload bullet writes)"
fi

# --- /spec-kickoff: resting state + derived mode selection (REQ-E1.2) ---

sk="$(flat "$REPO_ROOT/skills/spec-kickoff/SKILL.md")"

if printf '%s' "$sk" | grep -qE 'resting state'; then
  ok "spec-kickoff: Ready documented as the v2 header's resting state"
else
  fail "spec-kickoff: Draft→Ready flip not documented as the header's resting state on v2 (REQ-E1.2)"
fi

if printf '%s' "$sk" | grep -qE 'rests at Ready[^.]{0,240}(derivation|render)'; then
  ok "spec-kickoff: delta/amendment mode selection reads derived execution state on v2"
else
  fail "spec-kickoff: mode selection does not read derived execution state on a v2 bundle whose stored header rests at Ready (D-6)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all skill v2-reconciliation tests passed"
