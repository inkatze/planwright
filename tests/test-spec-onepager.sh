#!/bin/sh
# Unit tests for scripts/spec-onepager.sh — the spec-at-a-glance one-pager view
# (Task 4 of specs/spec-comprehension; D-2, REQ-C1.2): the length-bounded
# narrative view over the plain-language translation layer
# (scripts/spec-translate.sh). It reads the translate record stream, passes
# every upstream record through unchanged (the lossless substrate, D-2), and
# appends a bounded, ranked one-pager layer: an orientation frame plus, per
# selected load-bearing claim, a record carrying the claim's prominence (the
# foregrounded "killer items" vs routine content), its back-pointer, its
# load-bearing score, the plain audience-neutral rendering, and the verbatim
# source.
#
#   ONEPAGERFRAME  <spec>  <status>  <reqs>  <decs>  <tasks>  <shown>  <live>
#   ONEPAGER       <ordinal>  <prominence>  <ref>  <score>  <plain>  <source>
#
# Properties verified, one numbered section per Task 4 behavior:
#   1.  Pass-through (D-2 losslessness): every upstream model/translate record
#       survives unchanged; the one-pager only appends.
#   2.  Orientation frame: a single ONEPAGERFRAME record names the bundle, its
#       status, the element counts, and the shown-of-live bound (no silent
#       truncation — the bound is surfaced).
#   3.  Every claim carries a back-pointer (REQ-C1.2): every ONEPAGER ref is a
#       live REQ id that resolves to a REQ record in the stream.
#   4.  Killer items foregrounded and marked (REQ-C1.2): on a fixture with
#       differential load-bearing scores, the most-referenced claims are marked
#       `killer`, ordered ahead of `routine` content, and the killer set is
#       capped (the small foregrounded set, not the whole list).
#   5.  Length-bounded (REQ-C1.2): on a large real bundle the shown claim set is
#       capped well below the total live requirement count (at-a-glance, not a
#       bullet dump of every requirement).
#   6.  Audience-neutral plain column (REQ-C1.1 / REQ-D1.3 inherited): the plain
#       column of a claim carries no internal vocabulary (REQ-/D-/task-id), while
#       the source column retains the verbatim text — the reveal seam survives.
#   7.  Superseded requirements are not current claims: a superseded REQ never
#       appears as a one-pager claim.
#   8.  Composition: a <spec-dir> argument runs the full model->translate->
#       one-pager chain; a real bundle's default view leaks no internal
#       vocabulary and foregrounds at least one killer item.
#   9.  Graceful degradation: empty input emits nothing and exits 0; a missing
#       spec directory fails closed (exit 2) like the upstream chain.
#  10.  Stream hygiene + determinism: every ONEPAGER record has exactly seven
#       tab-separated fields and the frame eight; two runs are byte-identical.
#  11.  Tie-break stability (REQ-C1.2 ranking): two requirements with equal
#       load-bearing scores keep document order, so the ranking is canonical and
#       deterministic — an unstable sort that reordered ties would be caught.
#  12.  Killer-set correctness on a real bundle (REQ-C1.2): the foregrounded
#       killer set equals the top-scored live requirements computed independently
#       from the same stream, not merely "some items are marked killer."
#  13.  Ordinal integrity: the ONEPAGER ordinals are exactly 1..shown with no
#       gap, duplicate, or reversal; and no killer item carries a zero score (the
#       score >= 1 foregrounding threshold holds, not just the fixture's layout).
#
# Runs standalone: ./tests/test-spec-onepager.sh
set -eu

# Pin the C locale: charset checks and awk ranges must not vary by host locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-onepager.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

# The bounds the script declares (the unquantified at-a-glance bound, manual-
# judged per brief §2; mirrored here so the tests pin the contract).
KILLER_MAX=3
SHOWN_MAX=9

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-onepager.sh missing or not executable"

tmp="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_dir <expected-exit> <spec-dir> — run the one-pager over a spec directory
# (full model->translate->one-pager chain), capture combined output in $out.
out=
run_dir() {
  rexp=$1
  rc=0
  out=$("$script" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

# run_stdin <expected-exit> — pipe $IN (a translate stream) into the one-pager,
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

# onepager_field <ref> <col> — column <col> of the ONEPAGER record whose ref
# (field 4) equals <ref>. Empty when absent.
onepager_field() {
  printf '%s\n' "$out" | awk -F"$tab" -v r="$1" -v c="$2" \
    '$1=="ONEPAGER" && $4==r {print $c; exit}'
}

# has / lacks — substring presence in $out.
has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

# make_bundle <specs-root> <spec> — a fixture bundle with controlled
# load-bearing scores: REQ-A1.1..A1.4 are cited by a descending number of tasks
# (4,3,2,1 inbound), REQ-B1.1 is cited by none (score 0), and REQ-B1.9 is
# superseded. The killer ranking is therefore deterministic.
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

## REQ-A — load-bearing group

- **REQ-A1.1** The core thing SHALL exist. *(Cites: D-1.)*
- **REQ-A1.2** The second thing SHALL exist. *(Cites: D-1.)*
- **REQ-A1.3** The third thing SHALL exist. *(Cites: D-1.)*
- **REQ-A1.4** The fourth thing SHALL exist. *(Cites: D-1.)*

## REQ-B — routine group

- **REQ-B1.1** An uncited thing SHALL exist. *(Cites: D-2.)*
- **REQ-B1.2** The replacement thing SHALL exist. (supersedes REQ-B1.9)
  *(Cites: D-2.)*
- **REQ-B1.9** The old thing SHALL exist. **Superseded-by: REQ-B1.2** (2026-06-16)
  *(Cites: D-2.)*
EOF
  cat >"$d/design.md" <<'EOF'
# Fixture — Design

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### D-1: First decision  (N)

**Decision:** Do the first thing.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it.

### D-2: Second decision  (N)

**Decision:** Do the second thing.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it too.
EOF
  cat >"$d/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — broadest

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4
- **Estimated effort:** 1 day

### Task 2 — broad

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2, REQ-A1.3
- **Estimated effort:** 1 day

### Task 3 — narrow

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** 2
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 1 day

### Task 4 — narrowest

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** 3
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

# ---------------------------------------------------------------------------
# 1. Pass-through: every upstream record survives unchanged; only ONEPAGER*
#    records are appended (D-2 losslessness).
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
# A model record (BUNDLE) and a translate record (a TEXT requirement) both
# survive into the one-pager output.
has "BUNDLE${tab}demo${tab}Active"
has "TEXT${tab}REQ-A1.1${tab}requirement"

upstream_chain=$("$repo_root/scripts/spec-translate.sh" "$specs/demo")
# The one-pager output, with its appended ONEPAGER* records removed, must equal
# the upstream translate stream byte-for-byte (pure pass-through, then append).
passthrough=$(printf '%s\n' "$out" | grep -v "^ONEPAGER")
[ "$passthrough" = "$upstream_chain" ] \
  || fail "one-pager altered the upstream stream (pass-through broken)"

# ---------------------------------------------------------------------------
# 2. Orientation frame: one ONEPAGERFRAME naming the bundle, status, counts,
#    and the shown-of-live bound.
# ---------------------------------------------------------------------------
[ "$(count_tag ONEPAGERFRAME)" -eq 1 ] \
  || fail "expected exactly one ONEPAGERFRAME record: $out"
# spec=demo status=Active reqs=7 (all, incl the superseded B1.9) decs=2 tasks=4;
# field 8 (live) is 6 (B1.9 excluded) and is asserted via shown/live below.
has "ONEPAGERFRAME${tab}demo${tab}Active${tab}7${tab}2${tab}4"
# live (field 8) = 6 live requirements; shown (field 7) = 6 (all fit the bound).
has "${tab}2${tab}4${tab}6${tab}6"

# ---------------------------------------------------------------------------
# 3. Every claim carries a back-pointer that resolves to a live REQ record.
# ---------------------------------------------------------------------------
bad=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="REQ" && $4=="live" { live[$2]=1 }
  $1=="ONEPAGER" {
    if ($4 == "" || !($4 in live)) { print $4; bad=1 }
  }
  END { exit(bad?1:0) }
') || fail "a ONEPAGER claim has a ref that is not a live REQ: [$bad]"

# ---------------------------------------------------------------------------
# 4. Killer items foregrounded, marked, and capped.
# ---------------------------------------------------------------------------
# A1.1 (score 4), A1.2 (3), A1.3 (2) are the top three -> killer.
[ "$(onepager_field REQ-A1.1 3)" = "killer" ] || fail "REQ-A1.1 not marked killer: $out"
[ "$(onepager_field REQ-A1.2 3)" = "killer" ] || fail "REQ-A1.2 not marked killer: $out"
[ "$(onepager_field REQ-A1.3 3)" = "killer" ] || fail "REQ-A1.3 not marked killer: $out"
# A1.4 (score 1) and B1.1 (score 0) fall below the killer cap -> routine.
[ "$(onepager_field REQ-A1.4 3)" = "routine" ] || fail "REQ-A1.4 not marked routine: $out"
[ "$(onepager_field REQ-B1.1 3)" = "routine" ] || fail "REQ-B1.1 not marked routine: $out"
# The killer set is capped at KILLER_MAX (the small foregrounded set).
killers=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER" && $3=="killer"{c++} END{print c+0}')
[ "$killers" -eq "$KILLER_MAX" ] \
  || fail "expected $KILLER_MAX killer items, got $killers: $out"
# Killer items are ordered ahead of routine content: the max killer ordinal is
# below the min routine ordinal.
order_ok=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="ONEPAGER" && $3=="killer"  { if ($2+0 > maxk) maxk=$2+0 }
  $1=="ONEPAGER" && $3=="routine" { if (minr==0 || $2+0 < minr) minr=$2+0 }
  END { exit((maxk>0 && minr>0 && maxk < minr) ? 0 : 1) }
') && order_ok=1 || order_ok=0
[ "$order_ok" -eq 1 ] || fail "killer items not ordered ahead of routine: $out"
# The score column reflects the inbound-reference count.
[ "$(onepager_field REQ-A1.1 5)" = "4" ] || fail "REQ-A1.1 score not 4: $out"
[ "$(onepager_field REQ-B1.1 5)" = "0" ] || fail "REQ-B1.1 score not 0: $out"

# ---------------------------------------------------------------------------
# 5. Length-bounded on a large real bundle (bootstrap: 91 live REQs).
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/bootstrap"
shown=$(count_tag ONEPAGER)
[ "$shown" -le "$SHOWN_MAX" ] \
  || fail "one-pager not bounded: $shown shown, cap $SHOWN_MAX"
[ "$shown" -lt 91 ] \
  || fail "one-pager dumped every requirement instead of an at-a-glance subset"
# The frame surfaces the shown-of-live bound (no silent truncation).
frame_shown=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGERFRAME"{print $7; exit}')
frame_live=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGERFRAME"{print $8; exit}')
[ "$frame_shown" -eq "$shown" ] || fail "frame shown ($frame_shown) != actual ($shown)"
[ "$frame_live" -gt "$frame_shown" ] \
  || fail "frame did not surface that claims were omitted (live $frame_live, shown $frame_shown)"

# ---------------------------------------------------------------------------
# 6. Audience-neutral plain column; verbatim source retained (reveal seam).
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
# No ONEPAGER plain column (field 6) carries an internal-vocabulary token.
leak=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="ONEPAGER" {
    if ($6 ~ /REQ-[A-Z][0-9]+\.[0-9]+/ || $6 ~ /D-[0-9]+/ || $6 ~ /Task [0-9]/) {
      print $4; bad=1
    }
  }
  END { exit(bad?1:0) }
') || fail "a one-pager plain column leaked internal vocabulary: [$leak]"
# The source column (field 7) is non-empty for every claim (the reveal seam).
emptysrc=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER" && $7==""{print $4; bad=1} END{exit(bad?1:0)}') \
  || fail "a one-pager claim has an empty source column: [$emptysrc]"

# ---------------------------------------------------------------------------
# 7. Superseded requirements are not current claims.
# ---------------------------------------------------------------------------
case $out in
  *"ONEPAGER${tab}"*"${tab}REQ-B1.9${tab}"*) fail "superseded REQ-B1.9 surfaced as a claim: $out" ;;
esac

# ---------------------------------------------------------------------------
# 8. Composition on a real bundle: full chain, no leak, a killer item present.
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/spec-comprehension"
has "ONEPAGERFRAME${tab}spec-comprehension"
realkillers=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER" && $3=="killer"{c++} END{print c+0}')
[ "$realkillers" -ge 1 ] || fail "real bundle surfaced no killer item: $out"
# The default render of a real bundle leaks no internal vocabulary in plain text.
leak=$(printf '%s\n' "$out" | awk -F"$tab" '
  $1=="ONEPAGER" && ($6 ~ /REQ-[A-Z][0-9]+\.[0-9]+/ || $6 ~ /D-[0-9]+/) {print $4; bad=1}
  END { exit(bad?1:0) }
') || fail "real bundle plain column leaked internal vocabulary: [$leak]"

# ---------------------------------------------------------------------------
# 9. Graceful degradation: empty input, missing directory.
# ---------------------------------------------------------------------------
IN=""
run_stdin 0
[ -z "$out" ] || fail "empty input should emit nothing, got: $out"
# A missing spec directory fails closed (propagated from the upstream chain).
run_dir 2 "$specs/does-not-exist"

# ---------------------------------------------------------------------------
# 10. Stream hygiene + determinism.
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
# Every ONEPAGER record has exactly seven tab-separated fields; the frame eight.
printf '%s\n' "$out" | awk -F"$tab" '
  $1=="ONEPAGER"      && NF!=7 { print "ONEPAGER NF="NF; bad=1 }
  $1=="ONEPAGERFRAME" && NF!=8 { print "FRAME NF="NF; bad=1 }
  END { exit(bad?1:0) }
' || fail "a one-pager record has the wrong field count: $out"
# Determinism: two runs over the same bundle are byte-identical.
run1=$("$script" "$specs/demo")
run2=$("$script" "$specs/demo")
[ "$run1" = "$run2" ] || fail "one-pager output is not deterministic"

# ---------------------------------------------------------------------------
# 11. Tie-break stability: equal-score requirements keep document order. Two
# requirements each cited by exactly one task share score 1; the document-
# earlier one must rank first. An unstable sort (shifting on <= instead of <)
# would let the later one overtake — this fixture is the guard against that.
# ---------------------------------------------------------------------------
tiews="$tmp/ties"
mkdir -p "$tiews/specs/demo"
cat >"$tiews/specs/demo/requirements.md" <<'EOF'
# Tie — Requirements

**Status:** Active
**Format-version:** 1

## REQ-A — group

- **REQ-A1.1** The earlier thing SHALL exist. *(Cites: D-1.)*
- **REQ-A1.2** The later thing SHALL exist. *(Cites: D-1.)*
EOF
cat >"$tiews/specs/demo/design.md" <<'EOF'
# Tie — Design

**Status:** Active
**Format-version:** 1

### D-1: A decision  (N)

**Decision:** Decide.

**Alternatives considered:**
- Nothing. Rejected because: nothing.

**Chosen because:** needed.
EOF
cat >"$tiews/specs/demo/tasks.md" <<'EOF'
# Tie — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — cites the earlier

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — cites the later

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.2
- **Estimated effort:** 1 day
EOF
cat >"$tiews/specs/demo/test-spec.md" <<'EOF'
# Tie — Test Spec

**Status:** Active
**Format-version:** 1

### REQ-A1.1 — exists [test]

Assert it exists.
EOF
run_dir 0 "$tiews/specs/demo"
# Both score 1; A1.1 (document-earlier) must take the lower ordinal.
ord_a11=$(onepager_field REQ-A1.1 2)
ord_a12=$(onepager_field REQ-A1.2 2)
[ "$(onepager_field REQ-A1.1 5)" = "1" ] || fail "tie fixture: REQ-A1.1 score not 1: $out"
[ "$(onepager_field REQ-A1.2 5)" = "1" ] || fail "tie fixture: REQ-A1.2 score not 1: $out"
[ -n "$ord_a11" ] && [ -n "$ord_a12" ] && [ "$ord_a11" -lt "$ord_a12" ] \
  || fail "tie-break did not preserve document order (A1.1 ord $ord_a11, A1.2 ord $ord_a12): $out"

# ---------------------------------------------------------------------------
# 12. Killer-set correctness on a real bundle: the marked killer set equals the
# top KILLER_MAX live requirements by load-bearing score, computed independently
# from the same upstream stream. This verifies the foregrounded items are the
# *right* ones, not merely that some items are marked killer.
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/spec-comprehension"
# Independent expectation: rank live REQs by (score desc, document order asc)
# straight from the translate stream the script consumes, take the top KILLER_MAX.
expected=$("$repo_root/scripts/spec-translate.sh" "$repo_root/specs/spec-comprehension" | awk -F"$tab" -v k="$KILLER_MAX" '
  $1=="REQ" && $4=="live" { order[++n]=$2; pos[$2]=n }
  $1=="REQCITE" || $1=="TASKCITE" { s[$3]++ }
  END {
    for (i = 1; i <= n; i++) { id[i] = order[i]; sc[i] = s[order[i]] + 0 }
    for (i = 2; i <= n; i++) {
      ki = id[i]; ks = sc[i]; j = i - 1
      while (j >= 1 && sc[j] < ks) { id[j+1] = id[j]; sc[j+1] = sc[j]; j-- }
      id[j+1] = ki; sc[j+1] = ks
    }
    for (i = 1; i <= k && i <= n; i++) printf "%s\n", id[i]
  }')
# Actual killer refs in one-pager order.
actual=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER" && $3=="killer"{print $4}')
[ "$expected" = "$actual" ] \
  || fail "killer set is not the top-scored claims; expected [$expected] got [$actual]"

# ---------------------------------------------------------------------------
# 13. Ordinal integrity + the killer score threshold.
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
# Ordinals are exactly 1..shown: sorted numerically they form a gapless,
# duplicate-free run starting at 1.
printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER"{print $2}' | sort -n | awk '
  { if ($1 != NR) { print "ordinal " $1 " at position " NR; bad=1 } }
  END { exit(bad?1:0) }
' || fail "ONEPAGER ordinals are not the gapless sequence 1..shown: $out"
# No killer item carries a zero score (the score >= 1 foregrounding threshold).
zerokiller=$(printf '%s\n' "$out" | awk -F"$tab" '$1=="ONEPAGER" && $3=="killer" && $5+0==0{print $4; bad=1} END{exit(bad?1:0)}') \
  || fail "a zero-score requirement was foregrounded as killer: [$zerokiller]"

# ---------------------------------------------------------------------------
# 14. Missing dependency fails closed: in <spec-dir> mode the script resolves
# its sibling spec-translate.sh next to itself; when no executable sibling is
# present it must exit 2 with a clear message (the guard at spec-onepager.sh's
# `[ ! -x "$translate" ]` branch), rather than silently emitting nothing. Run a
# copy of the script from an isolated directory that has no spec-translate.sh
# sibling so the resolution genuinely fails.
# ---------------------------------------------------------------------------
isolate="$tmp/isolated"
mkdir -p "$isolate"
cp "$script" "$isolate/spec-onepager.sh"
chmod +x "$isolate/spec-onepager.sh"
# No spec-translate.sh exists alongside the copy: the guard must fire.
rc=0
out=$("$isolate/spec-onepager.sh" "$specs/demo" 2>&1) || rc=$?
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
out=$("$isolate/spec-onepager.sh" "$specs/demo" 2>&1) || rc=$?
[ "$rc" -eq 2 ] \
  || fail "non-executable translate sibling: expected exit 2, got $rc — output: $out"

echo "PASS: test-spec-onepager.sh"
