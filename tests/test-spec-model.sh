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

tmp="$(mktemp -d)" || exit 1
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
# 11. Inline citation annotation: a requirement whose `*(Cites: ...)*`
# annotation sits on the bullet line (a meta-spec-valid form) keeps its plain
# text and does not emit a self-citation edge. The citation tokens are still
# extracted; the requirement's own id is never one of them.
# ---------------------------------------------------------------------------
inline="$tmp/inline/demo"
mkdir -p "$inline"
cat >"$inline/requirements.md" <<'EOF'
# Inline — Requirements

**Status:** Active
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** The thing SHALL exist. *(Cites: D-1, D-2.)*
EOF
run_m 0 "$inline"
# The text survives even though the citation rode the same line.
rec REQ REQ-A1.1 A live "The thing SHALL exist."
# The citations are still edges...
rec REQCITE REQ-A1.1 D-1
rec REQCITE REQ-A1.1 D-2
# ...but the requirement never cites itself.
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "REQCITE" && $2 == "REQ-A1.1" && $3 == "REQ-A1.1" { f = 1 }
    END { exit(f ? 1 : 0) }' \
  || fail "inline-Cites requirement emitted a self-citation edge"

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

# ---------------------------------------------------------------------------
# 12. Status auto-detection edges (graceful, never a refusal). When
# requirements.md is absent, the first sibling that declares a Status stands
# in; when requirements.md is present but declares no Status, the value is
# reported "(undeclared)" rather than masked or borrowed from a sibling.
# ---------------------------------------------------------------------------
# requirements.md absent: a sibling's Status stands in. design.md here carries
# no Status, so the fallback walks on to tasks.md (the first sibling that
# declares one), proving the loop does not stop at a Status-less sibling.
sfb="$tmp/statusfallback/demo"
mkdir -p "$sfb"
cat >"$sfb/design.md" <<'EOF'
# Fallback — Design

**Format-version:** 1

### D-1: Only decision  (N)

**Decision:** stand up the thing.
EOF
cat >"$sfb/tasks.md" <<'EOF'
# Fallback — Tasks

**Status:** Draft
**Format-version:** 1

## Forward plan

### Task 1 — only

- **Done when:** the thing exists.
EOF
run_m 0 "$sfb"
rec FILE requirements absent
rec BUNDLE demo Draft
# The records from the files that are present still emit.
rec DEC D-1 N
rec TASK 1 "Forward plan"

# requirements.md present but declaring no Status: reported "(undeclared)",
# never borrowed from a sibling (design.md here says Active) and never masked.
undec="$tmp/undeclared/demo"
mkdir -p "$undec"
cat >"$undec/requirements.md" <<'EOF'
# Undeclared — Requirements

**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** The thing SHALL exist.
EOF
cat >"$undec/design.md" <<'EOF'
# Undeclared — Design

**Status:** Active
**Format-version:** 1

### D-1: A decision  (N)

**Decision:** do it.
EOF
run_m 0 "$undec"
rec BUNDLE demo "(undeclared)"
rec REQ REQ-A1.1 A live

# ---------------------------------------------------------------------------
# 13. Task-id grammar edges: a dotted task id (and a dotted dependency token)
# round-trip, and a non-numeric "### Task" heading is skipped (no TASK record)
# without breaking section tracking for the next valid task.
# ---------------------------------------------------------------------------
tid="$tmp/taskids/demo"
mkdir -p "$tid"
cat >"$tid/tasks.md" <<'EOF'
# Task-ids — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 3.5 — dotted

- **Dependencies:** 2.1
- **Done when:** the dotted task exists.

### Task Orphan — not a numeric id

- **Done when:** never modelled.

### Task 4 — after the orphan

- **Done when:** the section survived.
EOF
run_m 0 "$tid"
# Dotted id and dotted dependency token both round-trip.
rec TASK 3.5 "Forward plan" dotted
rec TASKDEP 3.5 2.1
# The non-numeric heading emits no TASK record, and the following valid task
# still carries its section (the section context survived the skipped task).
[ "$(count_tag TASK)" -eq 2 ] \
  || fail "non-numeric task heading should not emit a TASK record: got $(count_tag TASK)"
rec TASK 4 "Forward plan" "after the orphan"
lacks Orphan

# ---------------------------------------------------------------------------
# 14. An exists-but-unreadable bundle file degrades the same as absence
# (REQ-A1.5; the kickoff degrade-vs-refuse boundary: a valid path with broken
# content degrades, naming what is missing, rather than halting opaquely). It
# must never crash the awk parse under set -e or leak a raw "can't open file"
# error, and it must be reported absent — "present" means the model can read
# it. Mirrors scripts/spec-anchor.sh and scripts/orchestrate-select.sh, which
# gate reads on -r, not -f. The EXIT trap restores u+rwx so cleanup succeeds.
# ---------------------------------------------------------------------------
# requirements.md present but unreadable: status auto-detection must not crash
# in the command substitution; it falls back to a readable sibling and the file
# is reported absent.
unreq="$tmp/unreadable-req/demo"
make_bundle "$unreq" Active
chmod 000 "$unreq/requirements.md"
run_m 0 "$unreq"
lacks "can't open"
rec FILE requirements absent
# The readable siblings still parse, and the status falls back to one of them.
rec BUNDLE demo Active
[ "$(count_tag DEC)" -gt 0 ] || fail "unreadable requirements.md should not suppress readable siblings"
[ "$(count_tag REQ)" -eq 0 ] || fail "unreadable requirements.md should yield no REQ records"
chmod u+rwx "$unreq/requirements.md"

# A readable requirements.md with an unreadable sibling: the parse gate must
# skip the unreadable sibling instead of crashing mid-stream, and the sibling
# is reported absent (not present-but-unparsed).
unsib="$tmp/unreadable-sibling/demo"
make_bundle "$unsib" Active
chmod 000 "$unsib/design.md"
run_m 0 "$unsib"
lacks "can't open"
rec FILE design absent
rec REQ REQ-A1.1 A live
[ "$(count_tag DEC)" -eq 0 ] || fail "unreadable design.md should yield no DEC records"
chmod u+rwx "$unsib/design.md"

# ---------------------------------------------------------------------------
# 15. Prose dependency-line parsing. Three cases, each mirroring a fix already
# landed in a sibling parser: (a) and (b) mirror the derivation engine
# (scripts/orchestrate-state.sh); (c) mirrors the selector
# (scripts/orchestrate-select.sh) and intentionally diverges from the
# comma-only engine (opportunities.md 2026-06-28 / 2026-07-01, PR #103 / #104):
#   (a) trailing-period tolerance — a prose Dependencies entry commonly ends
#       its final id with a sentence period ("Task 1.", "1.", "3.5."); the id
#       must still emit its TASKDEP edge. Without it a SINGLE-dependency line
#       drops its only edge and the graph diverges from what orchestration
#       derives.
#   (b) no phantom edges — id-shaped digits inside a parenthetical carry clause
#       (e.g. "(REQ-A1.8 / D-9 …)") must NOT be scraped into TASKDEP nodes.
#       Whitespace-tokenize then grammar-validate (the engine's approach):
#       "REQ-A1.8" stays one non-numeric token and is dropped, never digit-
#       scraped into "1.8"/"9". The model has no malformed-deps channel, so a
#       non-conforming token is silently not emitted as an edge.
#   (c) semicolon separators — a prose list separates deps with ';' as well as
#       ',' ("Task 1; Task 4", "Task 5; plus cross-spec …"); ';' must split like
#       ',' so the id is not left as a whole token ("5;") that fails the grammar
#       and drops the edge. The selector honors ';'; the drawn graph (which
#       highlights the selector's critical path, D-6) must not lose that edge
#       (REQ-C1.3). Guards the regression the tokenize-then-validate switch would
#       otherwise introduce.
# ---------------------------------------------------------------------------
deps="$tmp/prosedeps/demo"
mkdir -p "$deps"
cat >"$deps/tasks.md" <<'EOF'
# Prose-deps — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — foundation

- **Done when:** the base exists.
- **Dependencies:** none

### Task 2 — single trailing-period dependency

- **Done when:** it layers over the base.
- **Dependencies:** Task 1.

### Task 3 — parenthetical carry clause

- **Done when:** it carries the rationale.
- **Dependencies:** Task 2 (see REQ-A1.8 / D-9 for the carry rationale)

### Task 4 — dotted dependency with a trailing period

- **Done when:** the dotted edge survives.
- **Dependencies:** 2.1.

### Task 5 — semicolon-separated multi-dependency

- **Done when:** both upstreams land.
- **Dependencies:** Task 1; Task 4

### Task 6 — semicolon then a prose cross-spec clause

- **Done when:** the semicolon edge survives the prose tail.
- **Dependencies:** Task 5; plus a cross-spec note that is not an id
EOF
run_m 0 "$deps"
# (a) Trailing-period ids still emit their edge — the fail-open case: a single
# dependency ending in a period must not drop to zero edges.
rec TASKDEP 2 1
rec TASKDEP 4 2.1
# (a)+(b) Task 3's only edge is the real "Task 2" dep; the parenthetical
# "REQ-A1.8 / D-9" must not scrape phantom nodes 1.8 or 9.
t3deps=$(printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "TASKDEP" && $2 == "3" { print $3 }' | sort | tr '\n' ' ')
[ "$t3deps" = "2 " ] \
  || fail "Task 3 deps should be exactly {2}, got: {$t3deps} (phantom scrape from the parenthetical?)"
# (c) Semicolons separate deps just like commas: Task 5's "Task 1; Task 4"
# yields BOTH edges, and Task 6's "Task 5; plus …" keeps the 5 edge while the
# prose tail drops. Guards the regression where ';' left the id as a whole token
# ("5;") that failed the grammar and dropped the edge (REQ-C1.3 graph divergence).
rec TASKDEP 5 1
rec TASKDEP 5 4
rec TASKDEP 6 5
# No phantom edges leaked into the overall stream (six real edges only).
[ "$(count_tag TASKDEP)" -eq 6 ] \
  || fail "expected 6 TASKDEP edges, got $(count_tag TASKDEP) (phantom or dropped edge?)"

# ---------------------------------------------------------------------------
# 11. Format-version 2 shape tolerance (invariant-tasks Task 4; REQ-C1.1
#     sweep). The v2 tasks.md keeps every block in a single ## Tasks section
#     with no state annotations; the model's task parser is section-agnostic
#     (the H2 label is carried as data, never matched against the v1 set), so
#     the v2 shape must round-trip: TASK records carrying the "Tasks" section
#     label, the definition TASKFIELDs, and the dependency/citation edges. A
#     reference bullet in a human-payload section is not a task block and must
#     not mint a phantom record.
# ---------------------------------------------------------------------------
v2=$tmp/v2shape/specs/demo
mkdir -p "$v2"
cat >"$v2/requirements.md" <<'EOF'
# V2 — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## REQ-A — group

- **REQ-A1.1** The system SHALL work.
  *(Cites: D-1.)*
EOF
cat >"$v2/tasks.md" <<'EOF'
# V2 — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — first

- **Deliverables:** the first thing.
- **Done when:** it exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — second

- **Deliverables:** the second thing.
- **Done when:** it renders.
- **Dependencies:** 1
- **Citations:** D-1
- **Estimated effort:** 1 day

## Awaiting input

- **Task 2** — parked on a fixture question.

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
run_m 0 "$v2"
rec TASK 1 Tasks first
rec TASK 2 Tasks second
rec TASKDEP 2 1
rec TASKFIELD 1 deliverables "the first thing."
rec TASKFIELD 2 donewhen "it renders."
rec TASKCITE 1 D-1
rec TASKCITE 1 REQ-A1.1
[ "$(count_tag TASK)" -eq 2 ] \
  || fail "v2 shape: expected exactly 2 TASK records, got $(count_tag TASK) (reference bullet minted a phantom task?)"
echo "ok: v2 tasks.md shape round-trips (TASK/TASKDEP/TASKFIELD under ## Tasks; bullets are not tasks)"

echo "PASS: test-spec-model.sh"
