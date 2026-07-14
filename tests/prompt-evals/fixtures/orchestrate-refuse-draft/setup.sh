#!/bin/sh
# setup.sh — seed the hermetic work tree for the orchestrate-refuse-draft fixture
# (prompt-hygiene Task 4; D-12). It builds a repo whose `demo` spec is Status
# Draft — not Ready or Active — so /orchestrate must refuse to dispatch at its
# status gate (pre-flight step 4), before the freshness gate or brief check. No
# kickoff brief is seeded: the refusal fires on status alone, and the absence of
# a brief is not what is under test. $1 is the work tree.
set -eu

work="$1"
spec="$work/specs/demo"
mkdir -p "$spec"

cat >"$spec/requirements.md" <<'EOF'
# Demo — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-12
**Format-version:** 1

## REQ-A — Demo

- **REQ-A1.1** The demo task SHALL do the thing. *(Cites: fixture seed.)*
EOF

cat >"$spec/design.md" <<'EOF'
# Demo — Design

**Status:** Draft
**Last reviewed:** 2026-07-12
**Format-version:** 1

## D-1: Keep the fixture minimal  (N)

**Decision:** one task; the bundle stays Draft to exercise the refusal.

**Alternatives considered:** none material.

**Chosen because:** a Draft spec is the refusal scenario.
EOF

cat >"$spec/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Draft
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

**Status:** Draft
**Last reviewed:** 2026-07-12
**Format-version:** 1

### REQ-A1.1 — Demo [manual]

The thing is observed.
EOF

git -C "$work" init -q
git -C "$work" config user.email "eval@planwright.local"
git -C "$work" config user.name "planwright-eval"
git -C "$work" config commit.gpgsign false
git -C "$work" add -A
git -C "$work" commit -q -m "seed demo spec bundle (Draft)"
