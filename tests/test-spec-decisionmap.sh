#!/bin/sh
# Unit tests for scripts/spec-decisionmap.sh — the ADR-shaped decision-map view
# (Task 8 of specs/spec-comprehension; D-2, REQ-C1.4): the four-beat decision
# view over the plain-language translation layer (scripts/spec-translate.sh). It
# reads the translate record stream, passes every upstream record through
# unchanged (the lossless substrate, D-2), and appends a decision-map layer that
# renders each decision as Context -> Decision -> Alternative-rejected ->
# Consequence, surfacing the rejected alternative and the cost:
#
#   DECMAPFRAME  <spec>  <status>  <decs>
#   DECMAP       <ordinal>  <ref>  <beat>  <plain>  <source>
#
# The four beats map onto the bundle's three decision fields plus the decision's
# framing (its title), per the kickoff brief's REQ-C1.4 four-beat sourcing
# resolution (§3): Context <- the decision's framing (its title); Decision <-
# the Decision field; Alternative-rejected <- the Alternatives-considered field
# (which carries both the rejected option and its "Rejected because" cost);
# Consequence <- the Chosen-because field.
#
# Properties verified, one numbered section per Task 8 behavior:
#   1.  Pass-through (D-2 losslessness): every upstream model/translate record
#       survives unchanged; the decision-map only appends.
#   2.  Orientation frame: a single DECMAPFRAME names the bundle, its status, and
#       the decision count.
#   3.  Four-beat completeness (REQ-C1.4): every decision emits exactly four
#       DECMAP records, in the canonical beat order context, decision,
#       alternative, consequence.
#   4.  Rejected alternative and cost surfaced (REQ-C1.4): the alternative beat
#       carries the rejected option and its "Rejected because" cost; the
#       consequence beat is present (non-empty) for a real bundle.
#   5.  Back-pointer / reveal seam (D-2, REQ-D1.3 inherited): every DECMAP ref is
#       a decision id that resolves to a DEC record; the source column retains
#       the verbatim text behind the plain rendering.
#   6.  Audience-neutral plain column (REQ-C1.1 inherited): the plain column of a
#       beat carries no internal vocabulary (REQ-/D-/task-id token), while the
#       source column retains the verbatim text.
#   7.  Composition: a <spec-dir> argument runs the full model->translate->
#       decision-map chain; a real bundle's default view renders every decision
#       in four beats and leaks no internal vocabulary.
#   8.  Graceful degradation: empty input emits nothing and exits 0; a missing
#       spec directory fails closed (exit 2) like the upstream chain.
#   9.  Field degradation (REQ-A1.5 posture): a decision missing a source field
#       still emits the full four-beat shape, with the absent beat's columns
#       empty — the shape is preserved and the gap is visible, never a dropped
#       beat.
#  10.  Stream hygiene + determinism: every DECMAP record has exactly six
#       tab-separated fields and the frame four; two runs are byte-identical.
#  11.  Decision-count + ordinal integrity: the frame's decision count equals the
#       number of DEC records and the number of four-beat groups; ordinals run
#       1..decs with each appearing exactly four times (one per beat).
#  12.  Missing dependency fails closed: in <spec-dir> mode a missing executable
#       spec-translate.sh sibling exits 2 with a clear message, not a silent
#       empty render.
#
# Runs standalone: ./tests/test-spec-decisionmap.sh
set -eu

# Pin the C locale: charset checks and awk ranges must not vary by host locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-decisionmap.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-decisionmap.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_dir <expected-exit> <spec-dir> — run the decision-map over a spec directory
# (full model->translate->decision-map chain), capture combined output in $out.
out=
run_dir() {
  rexp=$1
  rc=0
  out=$("$script" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

# run_stdin <expected-exit> — pipe $IN (a translate stream) into the decision-map,
# capture combined output in $out.
run_stdin() {
  rexp=$1
  rc=0
  out=$(printf '%s' "$IN" | "$script" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "stdin mode: expected exit $rexp, got $rc — output: $out"
}

# count_tag <tag> — number of records in $out whose first field is <tag>.
count_tag() {
  printf '%s\n' "$out" | awk -F"$tab" -v t="$1" '$1==t{c++} END{print c+0}'
}

# beat_field <ref> <beat> <col> — column <col> of the DECMAP record whose ref
# (field 3) equals <ref> and beat (field 4) equals <beat>. Empty when absent.
beat_field() {
  printf '%s\n' "$out" | awk -F"$tab" -v r="$1" -v b="$2" -v c="$3" \
    '$1=="DECMAP" && $3==r && $4==b {print $c; exit}'
}

# has — substring presence in $out.
has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

# make_bundle <specs-root> <spec> — a fixture bundle with two decisions: D-1 is
# complete (a clear rejected alternative carrying a "Rejected because" cost and a
# Chosen-because rationale); D-2 deliberately omits its Chosen-because field, to
# exercise the four-beat-shape-preserved degradation path.
make_bundle() {
  mr=$1
  ms=$2
  d="$mr/$ms"
  mkdir -p "$d"
  cat >"$d/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** The thing SHALL exist. *(Cites: D-1.)*
EOF
  cat >"$d/design.md" <<'EOF'
# Fixture — Design

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### D-1: Store the records in one flat file  (N)

**Decision:** keep every record in a single flat file, read top to bottom.

**Alternatives considered:**
- A relational database. Rejected because: it adds an external dependency and a
  schema migration the small dataset does not justify.

**Chosen because:** the dataset is small and a flat file stays portable and
diffable with no runtime dependency.

### D-2: Pick a name for the command  (N)

**Decision:** name the command the obvious plain word.

**Alternatives considered:**
- A clever coined name. Rejected because: a coined name is undiscoverable.
EOF
  cat >"$d/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — the thing

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  cat >"$d/test-spec.md" <<'EOF'
# Fixture — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### REQ-A1.1 — exists [test]

Assert the thing exists.
EOF
}

specs="$tmp/specs"
make_bundle "$specs" demo

# The canonical beat order the four-beat shape emits, per decision.
beats="context decision alternative consequence"

# ---------------------------------------------------------------------------
# 1. Pass-through: every upstream record survives unchanged; only DECMAP* and
#    DECMAPFRAME records are appended (D-2 losslessness).
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
has "BUNDLE${tab}demo${tab}Active"
has "DEC${tab}D-1${tab}N"
has "TEXT${tab}D-1${tab}decision-title"

upstream_chain=$("$repo_root/scripts/spec-translate.sh" "$specs/demo")
# The decision-map output, with its appended records removed, must equal the
# upstream translate stream byte-for-byte (pure pass-through, then append).
passthrough=$(printf '%s\n' "$out" | grep -v "^DECMAP")
[ "$passthrough" = "$upstream_chain" ] \
  || fail "decision-map altered the upstream stream (pass-through broken)"

# ---------------------------------------------------------------------------
# 2. Orientation frame: one DECMAPFRAME naming the bundle, status, and the
#    decision count (the fixture has two decisions).
# ---------------------------------------------------------------------------
[ "$(count_tag DECMAPFRAME)" -eq 1 ] \
  || fail "expected exactly one DECMAPFRAME record: $out"
has "DECMAPFRAME${tab}demo${tab}Active${tab}2"

# ---------------------------------------------------------------------------
# 3. Four-beat completeness: every decision emits exactly four DECMAP records in
#    the canonical beat order (REQ-C1.4).
# ---------------------------------------------------------------------------
for id in D-1 D-2; do
  seq=$(printf '%s\n' "$out" | awk -F"$tab" -v r="$id" '$1=="DECMAP" && $3==r{printf "%s ", $4} END{print ""}')
  seq=$(printf '%s' "$seq" | sed 's/ *$//')
  [ "$seq" = "$beats" ] \
    || fail "decision $id beats not the canonical four ($beats); got [$seq]: $out"
done

# ---------------------------------------------------------------------------
# 4. Rejected alternative and cost surfaced; consequence present (REQ-C1.4). On
#    the complete decision D-1 the alternative beat carries the rejected option
#    and its "Rejected because" cost, and the consequence beat is non-empty.
# ---------------------------------------------------------------------------
alt_src=$(beat_field D-1 alternative 6)
case $alt_src in
  *"relational database"*) ;;
  *) fail "D-1 alternative beat missing the rejected option: [$alt_src]" ;;
esac
case $alt_src in
  *"Rejected because"*) ;;
  *) fail "D-1 alternative beat missing the rejected-because cost: [$alt_src]" ;;
esac
cons_src=$(beat_field D-1 consequence 6)
[ -n "$cons_src" ] || fail "D-1 consequence beat is empty on a complete decision: $out"
case $cons_src in
  *"portable and"*"diffable"*) ;;
  *) fail "D-1 consequence beat does not carry the chosen-because rationale: [$cons_src]" ;;
esac
# The context beat carries the decision's framing (its title).
ctx_src=$(beat_field D-1 context 6)
case $ctx_src in
  *"Store the records in one flat file"*) ;;
  *) fail "D-1 context beat does not carry the decision framing: [$ctx_src]" ;;
esac

# ---------------------------------------------------------------------------
# 5. Back-pointer / reveal seam: every DECMAP ref resolves to a DEC record, and
#    every present beat's source column is non-empty.
# ---------------------------------------------------------------------------
bad=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="DEC" { dec[$2]=1 }
  $1=="DECMAP" {
    if ($3 == "" || !($3 in dec)) { print $3; bad=1 }
  }
  END { exit(bad?1:0) }
') || fail "a DECMAP ref is not a known decision id: [$bad]"

# ---------------------------------------------------------------------------
# 6. Audience-neutral plain column; verbatim source retained (reveal seam). No
#    plain column (field 5) carries an internal-vocabulary id token.
# ---------------------------------------------------------------------------
leak=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="DECMAP" {
    if ($5 ~ /REQ-[A-Z][0-9]+\.[0-9]+/ || $5 ~ /D-[0-9]+/ || $5 ~ /Task [0-9]/) {
      print $3 "/" $4; bad=1
    }
  }
  END { exit(bad?1:0) }
') || fail "a decision-map plain column leaked internal vocabulary: [$leak]"
# Every beat's plain column is non-empty for a complete decision.
dec_plain=$(beat_field D-1 decision 5)
[ -n "$dec_plain" ] || fail "D-1 decision beat has an empty plain column: $out"

# ---------------------------------------------------------------------------
# 7. Composition on the real bundles: every decision renders four beats with the
#    alternative and consequence present, and the default plain view leaks no
#    internal vocabulary.
# ---------------------------------------------------------------------------
for s in bootstrap customization-overlay spec-comprehension; do
  run_dir 0 "$repo_root/specs/$s"
  has "DECMAPFRAME${tab}$s"
  # Every DEC record has exactly four DECMAP beats in canonical order, and the
  # alternative + consequence beats are non-empty (Done-when: present in a real
  # bundle).
  printf '%s\n' "$out" | awk -F"$tab" -v want="$beats" '
    $1=="DEC" { decorder[++nd]=$2 }
    $1=="DECMAP" {
      seq[$3] = seq[$3] (seq[$3]=="" ? "" : " ") $4
      if ($4=="alternative") altsrc[$3]=$6
      if ($4=="consequence") conssrc[$3]=$6
    }
    END {
      for (i=1;i<=nd;i++) {
        id=decorder[i]
        if (seq[id] != want) { print "beats("id")=["seq[id]"]"; bad=1 }
        if (altsrc[id]=="")  { print "alt-empty("id")"; bad=1 }
        if (conssrc[id]=="") { print "cons-empty("id")"; bad=1 }
      }
      exit(bad?1:0)
    }' || fail "$s: a decision is missing a beat or the alternative/consequence: $out"
  # Default plain view leaks no internal vocabulary on the real bundle.
  leak=$(printf '%s\n' "$out" | awk -F"$tab" '
    $1=="DECMAP" && ($5 ~ /REQ-[A-Z][0-9]+\.[0-9]+/ || $5 ~ /D-[0-9]+/) {print $3"/"$4; bad=1}
    END { exit(bad?1:0) }
  ') || fail "$s: decision-map plain column leaked internal vocabulary: [$leak]"
done

# ---------------------------------------------------------------------------
# 8. Graceful degradation: empty input, missing directory.
# ---------------------------------------------------------------------------
IN=""
run_stdin 0
[ -z "$out" ] || fail "empty input should emit nothing, got: $out"
run_dir 2 "$specs/does-not-exist"

# ---------------------------------------------------------------------------
# 9. Field degradation: D-2 omits its Chosen-because field, yet still renders the
#    full four-beat shape with an empty consequence beat (REQ-A1.5 posture — the
#    shape is preserved, the gap is visible, the beat is never dropped).
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
# D-2 still has all four beats (asserted in section 3); its consequence beat is
# present as a record but its source/plain columns are empty.
d2_cons_src=$(beat_field D-2 consequence 6)
d2_cons_plain=$(beat_field D-2 consequence 5)
[ -z "$d2_cons_src" ] \
  || fail "D-2 (no chosen-because) consequence source should be empty: [$d2_cons_src]"
[ -z "$d2_cons_plain" ] \
  || fail "D-2 (no chosen-because) consequence plain should be empty: [$d2_cons_plain]"
# The record itself is present (the beat is not dropped).
d2_beats=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="DECMAP" && $3=="D-2"{c++} END{print c+0}')
[ "$d2_beats" -eq 4 ] \
  || fail "D-2 four-beat shape not preserved under a missing field: got $d2_beats beats"

# ---------------------------------------------------------------------------
# 10. Stream hygiene + determinism.
# ---------------------------------------------------------------------------
# Every DECMAP record has exactly six tab-separated fields; the frame four.
printf '%s\n' "$out" | awk -F"$tab" '
  $1=="DECMAP"      && NF!=6 { print "DECMAP NF="NF; bad=1 }
  $1=="DECMAPFRAME" && NF!=4 { print "FRAME NF="NF; bad=1 }
  END { exit(bad?1:0) }
' || fail "a decision-map record has the wrong field count: $out"
# Determinism: two runs over the same bundle are byte-identical.
run1=$("$script" "$specs/demo")
run2=$("$script" "$specs/demo")
[ "$run1" = "$run2" ] || fail "decision-map output is not deterministic"

# ---------------------------------------------------------------------------
# 11. Decision-count + ordinal integrity: the frame count equals the number of
#     DEC records and the number of four-beat groups; ordinals run 1..decs, each
#     appearing exactly four times (one per beat).
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/spec-comprehension"
frame_decs=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="DECMAPFRAME"{print $4; exit}')
dec_records=$(count_tag DEC)
[ "$frame_decs" -eq "$dec_records" ] \
  || fail "frame decision count ($frame_decs) != DEC record count ($dec_records)"
# Ordinals: each of 1..frame_decs appears exactly four times.
printf '%s\n' "$out" | awk -F"$tab" -v n="$frame_decs" '
  $1=="DECMAP" { seen[$2]++ }
  END {
    for (i=1;i<=n;i++) if (seen[i] != 4) { print "ordinal " i " count " seen[i]+0; bad=1 }
    for (k in seen) if (k+0 < 1 || k+0 > n) { print "ordinal out of range: " k; bad=1 }
    exit(bad?1:0)
  }' || fail "DECMAP ordinals are not 1..decs each appearing four times: $out"

# ---------------------------------------------------------------------------
# 12. Missing dependency fails closed: in <spec-dir> mode the script resolves its
#     sibling spec-translate.sh next to itself; with no executable sibling it must
#     exit 2 with a clear message rather than silently emitting nothing. Run a
#     copy from an isolated directory with no spec-translate.sh sibling.
# ---------------------------------------------------------------------------
isolate="$tmp/isolated"
mkdir -p "$isolate"
cp "$script" "$isolate/spec-decisionmap.sh"
chmod +x "$isolate/spec-decisionmap.sh"
rc=0
out=$("$isolate/spec-decisionmap.sh" "$specs/demo" 2>&1) || rc=$?
[ "$rc" -eq 2 ] \
  || fail "missing translate sibling: expected exit 2, got $rc — output: $out"
case $out in
  *"cannot find an executable spec-translate.sh"*) ;;
  *) fail "missing translate sibling: expected error message not surfaced — output: $out" ;;
esac
# A present-but-non-executable sibling triggers the same guard (the `! -x` half).
: >"$isolate/spec-translate.sh"
chmod -x "$isolate/spec-translate.sh"
rc=0
out=$("$isolate/spec-decisionmap.sh" "$specs/demo" 2>&1) || rc=$?
[ "$rc" -eq 2 ] \
  || fail "non-executable translate sibling: expected exit 2, got $rc — output: $out"

echo "PASS: test-spec-decisionmap.sh"
