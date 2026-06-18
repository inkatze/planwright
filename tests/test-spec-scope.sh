#!/bin/sh
# Unit tests for scripts/spec-scope.sh — the model-stream scope filter for
# /spec-walkthrough (Task 9 of specs/spec-comprehension; D-11, REQ-B1.1,
# REQ-B1.2). It reduces the bundle reader model (Task 2, scripts/spec-model.sh)
# to a single requested scope: the whole bundle (default, pass-through), one
# source file, one requirement group, the decision set, the task graph, or a
# single decision together with its blast radius (the requirements and tasks
# that cite it). It is the substrate the assembler renders the partial views
# from; the BUNDLE/FILE inventory records always survive so downstream framing
# still resolves the bundle name and status.
#
# Properties verified, one numbered section per Task 9 scope behavior:
#   1.  whole / no selector is a pass-through: every model record survives.
#   2.  file:<name> keeps only that file's records (requirements -> REQ/REQCITE,
#       design -> DEC/DECFIELD, tasks -> TASK*, test-spec -> TEST).
#   3.  reqs:<GROUP> keeps only that group's requirements and their citation
#       edges; other groups, decisions, tasks, and tests are dropped.
#   4.  decisions keeps only the decision set; tasks keeps only the task graph.
#   5.  decision:<id> keeps that decision plus its blast radius — the
#       requirements and tasks that cite it — and nothing that does not cite it.
#       The D-/d- prefix is accepted as well as the bare number.
#   6.  BUNDLE and FILE inventory records always survive, in every scope.
#   7.  Composition: a model stream on stdin filters identically to dir mode.
#   8.  Determinism, read-only, and fail-closed on a missing/ malformed input.
#
# Runs standalone: ./tests/test-spec-scope.sh
set -eu

LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-scope.sh"
model_sh="$here/../scripts/spec-model.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-scope.sh missing or not executable"
[ -x "$model_sh" ] || fail "scripts/spec-model.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_s <expected-exit> <args...> — run the filter in dir mode, capture combined
# output in $out, fail the suite if the exit code differs.
out=
run_s() {
  rexp=$1
  shift
  rc=0
  out=$("$script" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "expected exit $rexp, got $rc for: $* — output: $out"
}

# run_stdin <expected-exit> <model-stream> <args...> — pipe a model stream into
# the filter (the composable pipe), capture combined output in $out.
run_stdin() {
  rexp=$1
  stream=$2
  shift 2
  rc=0
  out=$(printf '%s\n' "$stream" | "$script" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "stdin mode: expected exit $rexp, got $rc for: $* — output: $out"
}

# count_tag <tag> — number of records bearing <tag> in column 1.
count_tag() {
  printf '%s\n' "$out" | awk -F"$tab" -v t="$1" '$1 == t { n++ } END { print n + 0 }'
}

# rec <field1> ... — assert a record whose leading fields match exactly exists.
rec() {
  [ $# -le 5 ] || fail "rec helper supports at most 5 fields: $*"
  printf '%s\n' "$out" | awk -F"$tab" \
    -v n="$#" -v a1="${1:-}" -v a2="${2:-}" -v a3="${3:-}" \
    -v a4="${4:-}" -v a5="${5:-}" '
    {
      v[1] = a1; v[2] = a2; v[3] = a3; v[4] = a4; v[5] = a5
      ok = 1
      for (i = 1; i <= n; i++) if ($i != v[i]) { ok = 0; break }
      if (ok) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' || fail "no record matching [$*] in: $out"
}

# norec <field1> ... — assert NO record whose leading fields match exists.
norec() {
  [ $# -le 5 ] || fail "norec helper supports at most 5 fields: $*"
  if printf '%s\n' "$out" | awk -F"$tab" \
    -v n="$#" -v a1="${1:-}" -v a2="${2:-}" -v a3="${3:-}" \
    -v a4="${4:-}" -v a5="${5:-}" '
    {
      v[1] = a1; v[2] = a2; v[3] = a3; v[4] = a4; v[5] = a5
      ok = 1
      for (i = 1; i <= n; i++) if ($i != v[i]) { ok = 0; break }
      if (ok) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  '; then
    fail "record matching [$*] should have been filtered out, but is present in: $out"
  fi
}

# A fixture bundle: two requirement groups (A, B), a superseded REQ, two
# decisions, two tasks with a dependency edge and citation edges, one tested
# REQ. D-1 is cited by A1.1, A1.2, A1.3, and Task 1; D-2 is cited by A1.2,
# B1.1, and Task 2 — so each decision has a distinct, checkable blast radius.
make_bundle() {
  d=$1
  st=${2:-Active}
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Fixture — Requirements

**Status:** $st
**Last reviewed:** 2026-06-18
**Format-version:** 1

## REQ-A — first group

- **REQ-A1.1** The system SHALL produce a thing.
  *(Cites: D-1.)*
- **REQ-A1.2** The system SHALL link the thing to its origin.
  *(Cites: D-1, D-2.)*
- **REQ-A1.3** The system SHALL do the old thing.
  **Superseded-by: REQ-A1.1**
  *(Cites: D-1.)*

## REQ-B — second group

- **REQ-B1.1** The renderer SHALL NOT soften a token.
  *(Cites: D-2.)*
EOF
  cat >"$d/design.md" <<EOF
# Fixture — Design

**Status:** $st
**Last reviewed:** 2026-06-18
**Format-version:** 1

### D-1: First decision  (N)

**Decision:** Do the first thing directly.

**Alternatives considered:**
- A heavyweight runtime. Rejected because: it breaks portability.

**Chosen because:** the direct path is portable.

### D-2: Second decision  (N)

**Decision:** Layer the second thing over the first.

**Alternatives considered:**
- Rewrite from scratch. Rejected because: rewriting loses traceability.

**Chosen because:** layering keeps the substrate intact.
EOF
  cat >"$d/tasks.md" <<EOF
# Fixture — Tasks

**Status:** $st
**Last reviewed:** 2026-06-18
**Format-version:** 1

## Forward plan

### Task 2 — second

- **Deliverables:** the second thing, layered over the first.
- **Done when:** the second thing renders.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-B1.1
- **Estimated effort:** 1.5 days

## Completed

### Task 1 — first

- **Deliverables:** the first thing.
- **Done when:** the first thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day
EOF
  cat >"$d/test-spec.md" <<EOF
# Fixture — Test Spec

**Status:** $st
**Last reviewed:** 2026-06-18
**Format-version:** 1

### REQ-A1.1 — produces a thing [test]

Assert the thing is produced.
EOF
}

specs="$tmp/specs"
make_bundle "$specs/demo"
demo="$specs/demo"

# ---------------------------------------------------------------------------
# 1. whole / no selector is a pass-through.
# ---------------------------------------------------------------------------
# The filtered whole-bundle stream equals the raw model stream byte-for-byte:
# the default scope reduces nothing.
model_out=$("$model_sh" "$demo")
run_s 0 --scope whole "$demo"
[ "$out" = "$model_out" ] || fail "scope whole is not a byte-identical pass-through of the model"
# No --scope at all behaves the same as whole.
run_s 0 "$demo"
[ "$out" = "$model_out" ] || fail "absent --scope is not a pass-through of the model"

# ---------------------------------------------------------------------------
# 2. file:<name> keeps only that file's records.
# ---------------------------------------------------------------------------
run_s 0 --scope file:requirements "$demo"
rec REQ REQ-A1.1
rec REQ REQ-B1.1
[ "$(count_tag REQCITE)" -ge 1 ] || fail "file:requirements dropped the REQCITE edges"
norec DEC D-1
norec TASK 1
norec TEST REQ-A1.1

run_s 0 --scope file:design "$demo"
rec DEC D-1
rec DEC D-2
[ "$(count_tag DECFIELD)" -ge 1 ] || fail "file:design dropped the DECFIELD rows"
norec REQ REQ-A1.1
norec TASK 1

run_s 0 --scope file:tasks "$demo"
rec TASK 1
rec TASK 2
[ "$(count_tag TASKDEP)" -ge 1 ] || fail "file:tasks dropped the dependency edges"
norec REQ REQ-A1.1
norec DEC D-1

run_s 0 --scope file:test-spec "$demo"
rec TEST REQ-A1.1
# The tested requirement is kept as the verification subject (so a downstream
# view can label it in plain language); an untested requirement is not.
rec REQ REQ-A1.1
norec REQ REQ-B1.1
norec DEC D-1
norec TASK 1

# ---------------------------------------------------------------------------
# 3. reqs:<GROUP> keeps only that group's requirements + their citation edges.
# ---------------------------------------------------------------------------
run_s 0 --scope reqs:A "$demo"
rec REQ REQ-A1.1 A
rec REQ REQ-A1.2 A
rec REQ REQ-A1.3 A
norec REQ REQ-B1.1
# The kept group's citation edges survive; group B's do not.
rec REQCITE REQ-A1.1 D-1
norec REQCITE REQ-B1.1 D-2
norec DEC D-1
norec TASK 1
norec TEST REQ-A1.1

run_s 0 --scope reqs:B "$demo"
rec REQ REQ-B1.1 B
norec REQ REQ-A1.1
rec REQCITE REQ-B1.1 D-2

# ---------------------------------------------------------------------------
# 4. decisions / tasks keep only their respective sets.
# ---------------------------------------------------------------------------
run_s 0 --scope decisions "$demo"
rec DEC D-1
rec DEC D-2
norec REQ REQ-A1.1
norec TASK 1

run_s 0 --scope tasks "$demo"
rec TASK 1
rec TASK 2
[ "$(count_tag TASKDEP)" -ge 1 ] || fail "tasks scope dropped the dependency edges"
norec REQ REQ-A1.1
norec DEC D-1

# ---------------------------------------------------------------------------
# 5. decision:<id> keeps the decision plus its blast radius.
# ---------------------------------------------------------------------------
# D-1's blast radius: REQ-A1.1, REQ-A1.2, REQ-A1.3 (all cite D-1) and Task 1
# (cites D-1). REQ-B1.1 and Task 2 cite only D-2, so they must be filtered out.
run_s 0 --scope decision:1 "$demo"
rec DEC D-1
norec DEC D-2
rec REQ REQ-A1.1
rec REQ REQ-A1.2
rec REQ REQ-A1.3
norec REQ REQ-B1.1
rec TASK 1
norec TASK 2
# The accepted prefix forms resolve to the same decision.
run_s 0 --scope decision:D-1 "$demo"
rec DEC D-1
norec DEC D-2
run_s 0 --scope decision:d-1 "$demo"
rec DEC D-1

# D-2's blast radius: REQ-A1.2, REQ-B1.1 and Task 2; D-1, Task 1 are excluded.
run_s 0 --scope decision:2 "$demo"
rec DEC D-2
norec DEC D-1
rec REQ REQ-A1.2
rec REQ REQ-B1.1
norec REQ REQ-A1.1
rec TASK 2
norec TASK 1

# ---------------------------------------------------------------------------
# 6. BUNDLE and FILE inventory records always survive.
# ---------------------------------------------------------------------------
for sc in whole file:design reqs:A decisions tasks decision:1; do
  run_s 0 --scope "$sc" "$demo"
  rec BUNDLE demo
  [ "$(count_tag FILE)" -ge 1 ] || fail "scope $sc dropped the FILE inventory records"
done

# ---------------------------------------------------------------------------
# 7. Composition: a model stream on stdin filters identically to dir mode.
# ---------------------------------------------------------------------------
dir_out=$("$script" --scope reqs:A "$demo")
run_stdin 0 "$model_out" --scope reqs:A
[ "$out" = "$dir_out" ] || fail "stdin-mode filter differs from dir-mode filter"

# ---------------------------------------------------------------------------
# 8. Determinism, read-only, fail-closed.
# ---------------------------------------------------------------------------
r1=$("$script" --scope decision:1 "$demo")
r2=$("$script" --scope decision:1 "$demo")
[ "$r1" = "$r2" ] || fail "filter output is not deterministic"

# A missing spec directory fails closed (propagated from the model, exit 2).
run_s 2 --scope whole "$specs/does-not-exist"

# A malformed selector is refused (exit 2), never silently treated as whole.
run_s 2 --scope bogus:thing "$demo"
run_s 2 --scope reqs:lowercase "$demo"
run_s 2 --scope decision:notanumber "$demo"

# Read-only: a run in a clean git work tree leaves it clean.
if command -v git >/dev/null 2>&1; then
  gws="$tmp/gitws"
  mkdir -p "$gws/specs"
  make_bundle "$gws/specs/demo"
  (
    cd "$gws"
    git init -q
    git config user.email t@e.x
    git config user.name t
    git add -A
    git -c commit.gpgsign=false commit -qm init
  )
  (cd "$gws" && "$script" --scope decision:1 "specs/demo" >/dev/null)
  status_after=$(cd "$gws" && git status --porcelain)
  [ -z "$status_after" ] || fail "filter was not read-only; git status: $status_after"
fi

# ---------------------------------------------------------------------------
# 9. Composition on a real bundle: the real spec-comprehension bundle filters
#    to a non-empty decision blast radius (D-1 is widely cited).
# ---------------------------------------------------------------------------
run_s 0 --scope decision:1 "$repo_root/specs/spec-comprehension"
rec DEC D-1
[ "$(count_tag REQ)" -ge 1 ] || fail "real bundle: decision:1 surfaced no citing requirement"

echo "PASS: test-spec-scope.sh"
