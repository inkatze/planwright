#!/bin/bash
# Tests for the format-version 3 skill and doc reconciliation
# (specs/invariant-tasks Task 12; REQ-F1.8, REQ-F1.4, D-13, D-14, D-15).
# Skills are procedure the agent reads, so the verification path is a
# structural guard over the SKILL.md prose, the shape of
# tests/test-skill-v2-reconciliation.sh, which keeps pinning the v1 and v2
# arms unchanged.
#
# Asserted properties:
#   - /spec-draft offers the `Repository:` field only when the elicitation
#     surfaces a second repository, declares version 3 only for a bundle in
#     which some task names one, and extend mode gives a version 3 target
#     the version 3 shape; a bundle materialized from that skeleton with one
#     field validates cleanly under a marker-bearing spec root;
#   - /execute-task's dependency check reads each dependency's state from
#     the repository its block names and halts on `repository-unresolved`,
#     naming the alias;
#   - /resume's tasks.md read has a version 3 arm naming each task's
#     repository and the `repository-unresolved` state;
#   - docs/orchestration-state.md describes per-task repositories, names the
#     work-repository registry as the alias's only resolution source, and
#     says where the checkout comes from.
#
# Runs standalone: ./tests/test-skill-v3-reconciliation.sh
# shellcheck disable=SC2016 # the backticks are markdown in the prose patterns, not substitutions
set -u
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
# prose matches are stable against rewrapping.
flat() {
  tr '\n' ' ' <"$1" | tr -s ' '
}

# check <label> <haystack> <ERE> — pass when the ERE matches the haystack.
check() {
  if printf '%s' "$2" | grep -qE "$3"; then
    ok "$1"
  else
    fail "$1 (no match for: $3)"
  fi
}

sd="$(flat "$REPO_ROOT/skills/spec-draft/SKILL.md")"
et="$(flat "$REPO_ROOT/skills/execute-task/SKILL.md")"
rs="$(flat "$REPO_ROOT/skills/resume/SKILL.md")"
doc="$(flat "$REPO_ROOT/docs/orchestration-state.md")"

# --- /spec-draft (REQ-F1.8, D-13, D-14) ---

check "spec-draft: offers the Repository: field when a second repository surfaces" \
  "$sd" 'second repository[^.]{0,200}`Repository:`'
check "spec-draft: declares Format-version 3 only when some task names a repository" \
  "$sd" '\*\*Format-version:\*\* 3[^.]{0,120}only when (some|a) task names a repository'
check "spec-draft: the version 2 default declaration is kept" \
  "$sd" '\*\*Format-version:\*\* 2'
check "spec-draft: the field value is an alias resolved only through the registry" \
  "$sd" 'alias[^.]{0,160}work-repository registry'
check "spec-draft: extend mode gives a version 3 target the version 3 shape" \
  "$sd" 'v3 target[^.;]{0,160}`Repository:`'

# --- /spec-draft: the documented version 3 skeleton validates (REQ-F1.8) ---

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/skill-v3-recon.XXXXXX")" || exit 1
trap 'rm -rf "$tmpdir"' EXIT
printf 'project: fixture\nlayout: 1\n' >"$tmpdir/planwright-spec-root.yml"
fx="$tmpdir/fixture"
mkdir -p "$fx"

header() {
  printf '# Fixture — %s\n\n**Status:** Draft\n**Last reviewed:** 2026-11-01\n' "$1"
  printf '**Format-version:** 3\n**Execution:** derived — see the status render\n'
}

{
  header Requirements
  cat <<'EOF'

## Goal

A fixture bundle drafted per the /spec-draft version 3 skeleton.

## Scope

### In scope

- The widget and its client.

### Out of scope

- Everything else.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*

## Changelog

- 2026-11-01 — Initial draft.

## Sources

- the fixture seed.
EOF
} >"$fx/requirements.md"

{
  header Design
  cat <<'EOF'

## Decision log

### D-1: Widgets are good  (N)

**Decision:** Build widgets.

**Alternatives considered:**
- No widgets. Rejected because: nothing would exist.

**Chosen because:** widgets are the fixture's point.
EOF
} >"$fx/design.md"

{
  header Tasks
  cat <<'EOF'

## Tasks

### Task 1 — Build the widget

- **Deliverables:** A widget.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

### Task 2 — Build the widget client

- **Deliverables:** A widget client.
- **Done when:** The client calls the widget.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-X1.1
- **Repository:** client-app
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
} >"$fx/tasks.md"

{
  header 'Test Spec'
  cat <<'EOF'

Coverage is a fixture mix.

### REQ-X1.1 — widget exists [test]

The widget fixture passes.
EOF
} >"$fx/test-spec.md"

vout="$(cd "$tmpdir" && "$REPO_ROOT/scripts/spec-validate.sh" fixture 2>&1)"
vrc=$?
if [ "$vrc" -eq 0 ] && printf '%s' "$vout" | grep -q '0 error(s), 0 warning(s)'; then
  ok "spec-draft: the version 3 skeleton with one field validates cleanly"
else
  fail "spec-draft: the version 3 skeleton with one field does not validate cleanly (exit $vrc): $vout"
fi

# --- /execute-task: dependency check per repository (REQ-F1.4, D-15) ---

check "execute-task: v3 dependency check reads each dependency's own repository" \
  "$et" 'version 3 bundle[^.]{0,200}repository (its|that) (block|dependency|field) names'
check "execute-task: a repository-unresolved dependency halts naming the alias" \
  "$et" '`repository-unresolved`[^.]{0,120}alias'
check "execute-task: v1 and v2 dependency arms kept" \
  "$et" 'derives Completed via the derivation engine'

# --- /resume: status read names the repository (REQ-F1.4, D-15) ---

check "resume: has a Format-version 3 arm" \
  "$rs" '\*\*Format-version 3:\*\*'
check "resume: v3 arm names each task's repository" \
  "$rs" 'Format-version 3:\*\*[^*]*(alias|repository)'
check "resume: v3 arm names the repository-unresolved state" \
  "$rs" 'Format-version 3:\*\*[^*]*`repository-unresolved`'
check "resume: v2 arm kept" \
  "$rs" '\*\*Format-version 2:\*\*'

# --- docs/orchestration-state.md (REQ-F1.4, D-14, D-15) ---

check "doc: has a format-version 3 section" \
  "$doc" '## Format-version 3'
check "doc: names the registry as the alias's only resolution source" \
  "$doc" '[Oo]nly (resolution source|through the (machine-local )?work-repository registry)'
check "doc: says where the alias's checkout comes from" \
  "$doc" 'checkout[^.]{0,200}registry'
check "doc: names the repository-unresolved state with no fallback" \
  "$doc" '`repository-unresolved`[^.]{0,200}never falls? back'

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all skill v3-reconciliation tests passed"
