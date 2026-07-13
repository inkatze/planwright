#!/bin/sh
# setup.sh — seed the hermetic work tree for the orchestrate-print-ready fixture
# (prompt-hygiene Task 4; D-12). It builds a self-contained repo carrying a
# minimal, gate-valid `demo` spec bundle with exactly one Ready task and no
# dependencies, plus a signed kickoff brief whose anchor is computed from the
# seeded bundle so /orchestrate's execution freshness gate passes. The repo is
# git-initialised and committed so the gate's "main view" of the four spec files
# matches the working tree. $1 is the work tree; PROMPT_EVAL_PLUGIN_DIR points at
# the planwright plugin whose spec-anchor.sh computes the anchor.
set -eu

work="$1"
plugin="${PROMPT_EVAL_PLUGIN_DIR:?PROMPT_EVAL_PLUGIN_DIR must be set by the runner}"
spec="$work/specs/demo"
mkdir -p "$spec"

cat >"$spec/requirements.md" <<'EOF'
# Demo — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-12
**Format-version:** 1

## REQ-A — Demo

- **REQ-A1.1** The demo task SHALL print a launch command for the ready unit.
  *(Cites: fixture seed.)*
EOF

cat >"$spec/design.md" <<'EOF'
# Demo — Design

**Status:** Ready
**Last reviewed:** 2026-07-12
**Format-version:** 1

## D-1: Keep the fixture minimal  (N)

**Decision:** one Ready task, no dependencies.

**Alternatives considered:** a multi-task graph — rejected as needless for the
print-dispatch scenario.

**Chosen because:** the print backend needs exactly one selectable unit.
EOF

cat >"$spec/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-12
**Format-version:** 1

## Forward plan

### Task 1 — Do the thing

- **Deliverables:** the thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none)

## Out of scope

(none)
EOF

cat >"$spec/test-spec.md" <<'EOF'
# Demo — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-12
**Format-version:** 1

### REQ-A1.1 — Demo [manual]

The printed launch command is observed to name the ready unit.
EOF

# Compute the content anchor from the seeded bundle, then sign the brief with it
# so the freshness gate recomputes to a match.
anchor="$("$plugin/scripts/spec-anchor.sh" "$spec")"

cat >"$spec/kickoff-brief.md" <<EOF
# Demo — Kickoff Brief

- **Spec path:** \`specs/demo/\`
- **Mode:** First activation (Status Draft → Ready on sign-off)

## Sign-off

**Class:** meaning (first activation; additions count as meaning-class).

Minimal lens pass: the bundle validates 0/0; one Ready task, no dependencies,
no citations dangling. The single unit is cleanly selectable and print-safe.

Class: meaning
Lens-pass: recorded above (this section), dispositioned 2026-07-12.
Anchor: \`$anchor\` — computed as
\`scripts/spec-anchor.sh specs/demo\`
EOF

# Git-initialise so the freshness gate's "primary checkout main view" exists and
# matches the working tree. Identity is set locally; no signing (hermetic).
git -C "$work" init -q
git -C "$work" config user.email "eval@planwright.local"
git -C "$work" config user.name "planwright-eval"
git -C "$work" config commit.gpgsign false
git -C "$work" add -A
git -C "$work" commit -q -m "seed demo spec bundle (Ready, one task)"
