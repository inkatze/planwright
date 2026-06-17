#!/bin/sh
# Unit tests for scripts/spec-model.sh — the bundle reader model (Task 2 of
# specs/spec-comprehension): the normalized in-memory substrate every
# downstream view renders from. The model reads the four bundle files and
# emits a deterministic, tagged, tab-separated record stream: bundle and file
# inventory, requirement records, decision records, task records, the
# task-graph dependency edges, and the citation edges that make a decision's
# blast radius (REQ-B1.2) computable. Every record carries its source
# identifier as a back-pointer (D-2, REQ-D1.3), held in its own column and
# separable from the plain text (REQ-C1.1).
#
# Properties verified, one numbered section per Task 2 behavior:
#   1.  A real bundle (bootstrap) round-trips: the model's requirement,
#       decision, and task record counts equal an independent grep of the
#       source files, and every dependency edge in tasks.md is reachable in
#       the model (Done-when: round-trips a real bundle with every REQ,
#       decision, task, and dependency edge reachable).
#   2.  A deterministic fixture: bundle + file inventory, every REQ/decision/
#       task record present and carrying its id, the requirement-group derived
#       from the id, and superseded state marked.
#   3.  Back-pointer separability (REQ-C1.1, REQ-D1.3): a requirement's id is
#       in its own column; the plain-text column carries neither the id token
#       nor the citation annotation (the back-pointer is hidden structure).
#   4.  Citation and dependency edges: REQ->decision, task->decision, and
#       task->requirement citation edges, plus the task-graph dependency edges
#       (REQ-B1.2 substrate; the task graph).
#   5.  A decision's blast radius (REQ-B1.2): the requirements and tasks that
#       cite a given decision are reachable by filtering the citation edges.
#   6.  Decision four-beat substrate (D-2): each decision's Decision,
#       Alternatives considered, and Chosen because fields are exposed, with
#       the rejected alternative preserved.
#   7.  Precision preservation (REQ-C1.7 substrate): normative tokens
#       (SHALL NOT, a threshold) survive verbatim in the model text.
#   8.  Graceful degradation: a partial bundle (a file absent) marks the file
#       absent and still emits the records from the files present; a missing
#       spec directory fails closed with a clear message.
#   9.  Record hygiene: control characters and literal tabs in bundle content
#       cannot break the tab-separated record stream.
#   10. Determinism: two runs over the same bundle produce identical output.
#
# Runs standalone: ./tests/test-spec-model.sh
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by host
# locale collation.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-model.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-model.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_m <expected-exit> <spec-dir> [args...] — run the model over a spec
# directory, capture combined output in $out, and fail the suite if the exit
# code differs.
out=
run_m() {
  rexp=$1
  shift
  rc=0
  out=$("$script" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "expected exit $rexp, got $rc for: $* — output: $out"
}

# has <substring> — assert $out contains the substring.
has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

# lacks <substring> — assert $out does not contain the substring.
lacks() {
  case $out in
    *"$1"*) fail "output unexpectedly contains \"$1\": $out" ;;
  esac
}

# rec <field1> <field2> ... — assert a record whose leading fields match the
# given tab-separated values exists in $out (exact, per column; trailing
# fields beyond those given are unconstrained). Up to five fields.
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

# count_tag <tag> — number of records bearing <tag> in column 1.
count_tag() {
  printf '%s\n' "$out" | awk -F"$tab" -v t="$1" '$1 == t { n++ } END { print n + 0 }'
}

# ---------------------------------------------------------------------------
# A deterministic fixture bundle: two requirement groups (A, B), one
# superseded requirement, two decisions (one new, one carried), two tasks with
# a dependency edge and citation edges, and a test-spec entry per live REQ.
# B1.1 carries normative tokens (SHALL NOT, a threshold) for the verbatim
# check.
# ---------------------------------------------------------------------------
make_bundle() {
  d=$1
  st=${2:-Active}
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Fixture — Requirements

**Status:** $st
**Last reviewed:** 2026-06-17
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

- **REQ-B1.1** The renderer SHALL NOT soften a token below a threshold of
  ≤ 64 characters.
  *(Cites: D-2.)*
EOF
  cat >"$d/design.md" <<EOF
# Fixture — Design

**Status:** $st
**Last reviewed:** 2026-06-17
**Format-version:** 1

### D-1: First decision  (N)

**Decision:** Do the first thing directly.

**Alternatives considered:**
- A heavyweight runtime. Rejected because: it breaks portability.

**Chosen because:** the direct path is portable.

### D-2: Second decision  (C, other-spec D-9)

**Decision:** Layer the second thing over the first.

**Alternatives considered:**
- Rewrite from scratch. Rejected because: rewriting loses traceability.

**Chosen because:** layering keeps the substrate intact.
EOF
  cat >"$d/tasks.md" <<EOF
# Fixture — Tasks

**Status:** $st
**Last reviewed:** 2026-06-17
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
**Last reviewed:** 2026-06-17
**Format-version:** 1

### REQ-A1.1 — produces a thing [test]

Assert the thing is produced.

### REQ-B1.1 — preserves the token [test]

Assert the token survives verbatim.
EOF
}

fix="$tmp/specs/demo"
make_bundle "$fix" Active

# ---------------------------------------------------------------------------
# 2. Bundle + inventory + records, each carrying its id.
# ---------------------------------------------------------------------------
run_m 0 "$fix"

rec BUNDLE demo Active
rec FILE requirements present
rec FILE design present
rec FILE tasks present
rec FILE test-spec present

# Every requirement record present, group derived from the id, superseded
# state marked.
rec REQ REQ-A1.1 A live
rec REQ REQ-A1.2 A live
rec REQ REQ-A1.3 A superseded
rec REQ REQ-B1.1 B live
[ "$(count_tag REQ)" -eq 4 ] || fail "expected 4 REQ records, got $(count_tag REQ)"

# Every decision and task record present, carrying its id.
rec DEC D-1 N
rec DEC D-2 "C, other-spec D-9"
[ "$(count_tag DEC)" -eq 2 ] || fail "expected 2 DEC records, got $(count_tag DEC)"
rec TASK 2 "Forward plan"
rec TASK 1 Completed
[ "$(count_tag TASK)" -eq 2 ] || fail "expected 2 TASK records, got $(count_tag TASK)"

# Test-spec coverage records (the model reads all four files).
rec TEST REQ-A1.1
rec TEST REQ-B1.1

# ---------------------------------------------------------------------------
# 3. Back-pointer separability: the id is in its own column; the plain-text
# column carries neither the id token nor the citation annotation.
# ---------------------------------------------------------------------------
a11_text=$(printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "REQ" && $2 == "REQ-A1.1" { print $5 }')
[ -n "$a11_text" ] || fail "REQ-A1.1 has no text column"
case $a11_text in
  *REQ-A1.1*) fail "REQ-A1.1 text column leaks its id: $a11_text" ;;
  *Cites*) fail "REQ-A1.1 text column leaks the citation annotation: $a11_text" ;;
esac

# ---------------------------------------------------------------------------
# 4. Citation and dependency edges.
# ---------------------------------------------------------------------------
rec REQCITE REQ-A1.1 D-1
rec REQCITE REQ-A1.2 D-1
rec REQCITE REQ-A1.2 D-2
rec REQCITE REQ-B1.1 D-2

# Task-graph dependency edge: Task 2 depends on Task 1; Task 1 has no edge.
rec TASKDEP 2 1
[ "$(count_tag TASKDEP)" -eq 1 ] || fail "expected 1 TASKDEP edge, got $(count_tag TASKDEP)"

# Task citation edges (both decisions and requirements).
rec TASKCITE 1 D-1
rec TASKCITE 1 REQ-A1.1
rec TASKCITE 2 D-2
rec TASKCITE 2 REQ-B1.1

# ---------------------------------------------------------------------------
# 5. A decision's blast radius (REQ-B1.2): everything that cites D-2.
# ---------------------------------------------------------------------------
blast=$(printf '%s\n' "$out" | awk -F"$tab" '
  ($1 == "REQCITE" || $1 == "TASKCITE") && $3 == "D-2" { print $2 }' | sort)
case $blast in
  *REQ-A1.2*) ;;
  *) fail "D-2 blast radius missing REQ-A1.2: $blast" ;;
esac
case $blast in
  *REQ-B1.1*) ;;
  *) fail "D-2 blast radius missing REQ-B1.1: $blast" ;;
esac
# Task 2 cites D-2, so it is in the blast radius too.
printf '%s\n' "$blast" | grep -qx '2' \
  || fail "D-2 blast radius missing Task 2: $blast"

# ---------------------------------------------------------------------------
# 6. Decision four-beat substrate: each decision exposes its three fields,
# with the rejected alternative preserved.
# ---------------------------------------------------------------------------
rec DECFIELD D-1 decision
rec DECFIELD D-1 alternatives
rec DECFIELD D-1 chosen
d1_alt=$(printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "DECFIELD" && $2 == "D-1" && $3 == "alternatives" { print $4 }')
case $d1_alt in
  *"Rejected because"*) ;;
  *) fail "D-1 alternatives field dropped the rejected alternative: $d1_alt" ;;
esac

# Task field substrate: deliverables, done-when, and effort exposed.
rec TASKFIELD 1 effort "half day"
rec TASKFIELD 2 effort "1.5 days"
rec TASKFIELD 1 deliverables
rec TASKFIELD 2 donewhen

# ---------------------------------------------------------------------------
# 7. Precision preservation: normative tokens survive verbatim.
# ---------------------------------------------------------------------------
b11_text=$(printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "REQ" && $2 == "REQ-B1.1" { print $5 }')
case $b11_text in
  *"SHALL NOT"*) ;;
  *) fail "REQ-B1.1 lost the normative token SHALL NOT: $b11_text" ;;
esac
case $b11_text in
  *"≤ 64"*) ;;
  *) fail "REQ-B1.1 lost the threshold ≤ 64: $b11_text" ;;
esac

# ---------------------------------------------------------------------------
# 8. Graceful degradation.
# ---------------------------------------------------------------------------
# A partial bundle: design.md absent. The model marks it absent and still
# emits the records from the files present (no decision records, but the
# requirements and tasks still parse).
partial="$tmp/partial/demo"
make_bundle "$partial" Active
rm "$partial/design.md"
run_m 0 "$partial"
rec FILE design absent
rec REQ REQ-A1.1 A live
[ "$(count_tag DEC)" -eq 0 ] || fail "absent design.md should yield no DEC records"
rec TASK 1 Completed

# A missing spec directory fails closed with a clear message.
run_m 2 "$tmp/does-not-exist"
has "spec-model"

# Empty argument is a usage refusal.
run_m 2 ""

# ---------------------------------------------------------------------------
# 9. Record hygiene: control characters and literal tabs in bundle content
# cannot inject extra columns or break the record stream.
# ---------------------------------------------------------------------------
dirty="$tmp/dirty/demo"
make_bundle "$dirty" Active
# Splice a literal tab and a control byte into a requirement's text.
{
  printf '# Dirty — Requirements\n\n'
  printf '**Status:** Active\n**Format-version:** 1\n\n'
  printf '## REQ-A — group\n\n'
  printf -- '- **REQ-A1.1** A %bvalue%b with a %bcontrol byte.\n' '\t' '\001' ''
  printf '  *(Cites: D-1.)*\n'
} >"$dirty/requirements.md"
run_m 0 "$dirty"
# Exactly one REQ record despite the embedded tab — the tab did not split the
# record into phantom columns or lines.
[ "$(count_tag REQ)" -eq 1 ] || fail "embedded tab broke the record stream: $(count_tag REQ) REQ records"
a11_dirty=$(printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "REQ" && $2 == "REQ-A1.1" { print $5 }')
case $a11_dirty in
  *value*with*) ;;
  *) fail "embedded control characters corrupted the text column: $a11_dirty" ;;
esac

# ---------------------------------------------------------------------------
# 10. Determinism: two runs over the same bundle are byte-identical.
# ---------------------------------------------------------------------------
run1=$("$script" "$fix")
run2=$("$script" "$fix")
[ "$run1" = "$run2" ] || fail "model output is not deterministic across runs"

# ---------------------------------------------------------------------------
# 1. Real-bundle round-trip (bootstrap): the model's record counts equal an
# independent grep of the source, and every dependency edge is reachable.
# This is the Done-when condition exercised against a real bundle.
# ---------------------------------------------------------------------------
boot="$repo_root/specs/bootstrap"
if [ -d "$boot" ]; then
  run_m 0 "$boot"

  want_reqs=$(grep -cE '^- \*\*REQ-[A-Z][0-9]+\.[0-9]+\*\*' "$boot/requirements.md")
  got_reqs=$(count_tag REQ)
  [ "$got_reqs" -eq "$want_reqs" ] \
    || fail "bootstrap REQ round-trip: model has $got_reqs, source has $want_reqs"

  want_decs=$(grep -cE '^### D-[0-9]+:' "$boot/design.md")
  got_decs=$(count_tag DEC)
  [ "$got_decs" -eq "$want_decs" ] \
    || fail "bootstrap decision round-trip: model has $got_decs, source has $want_decs"

  want_tasks=$(grep -cE '^### Task [0-9]+(\.[0-9]+)? ' "$boot/tasks.md")
  got_tasks=$(count_tag TASK)
  [ "$got_tasks" -eq "$want_tasks" ] \
    || fail "bootstrap task round-trip: model has $got_tasks, source has $want_tasks"

  # Every dependency edge is reachable: each non-"none" Dependencies token in
  # tasks.md appears as a TASKDEP edge from its task. Reconstruct the edge set
  # independently and compare against the model's.
  src_edges=$(awk '
    /^### Task / && $3 ~ /^[0-9]+(\.[0-9]+)?$/ { cur = $3; next }
    cur != "" && /^- \*\*Dependencies:\*\*/ {
      s = $0
      sub(/.*\*\*Dependencies:\*\*/, "", s)
      gsub(/[^0-9.]+/, " ", s)
      n = split(s, a, " ")
      for (i = 1; i <= n; i++)
        if (a[i] ~ /^[0-9]+(\.[0-9]+)?$/) print cur "\t" a[i]
      cur = ""
    }
  ' "$boot/tasks.md" | sort)
  model_edges=$(printf '%s\n' "$out" \
    | awk -F"$tab" '$1 == "TASKDEP" { print $2 "\t" $3 }' | sort)
  [ "$src_edges" = "$model_edges" ] \
    || fail "bootstrap dependency-edge round-trip mismatch:
source:
$src_edges
model:
$model_edges"
fi

echo "PASS: test-spec-model.sh"
