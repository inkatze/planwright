#!/bin/sh
# Unit tests for scripts/spec-teachback.sh — the teach-back challenge view
# (Task 5 of specs/spec-comprehension; D-3, D-9; REQ-C1.5, REQ-D1.1, REQ-D1.4):
# the claim set a human teaches back, extracted from the bundle's own
# assertions. It reads the plain-language translation stream
# (scripts/spec-translate.sh) and emits the teach-back view — a neutral
# response model, the sections, and one claim per assertion — that both the
# in-artifact checklist (Task 6) and the optional in-session walk (the skill)
# render from the same source:
#
#   RESPONSE  <option>                              (agree | disagree | unsure)
#   SECTION   <section-id>  <order>  <label>
#   CLAIM     <ref>  <section-id>  <ordinal>  <plain>  <source>
#
# Properties verified, one numbered section per Task 5 behavior:
#   1.  Neutral response model (REQ-C1.5/REQ-D1.1, supplies no answer): exactly
#       the agree/disagree/unsure triad, each a bare option with no
#       correct/expected marker — the structure offers a choice, never an answer.
#   2.  Claim extraction (D-3, D-9): every live requirement and every decision
#       yields exactly one claim; a superseded requirement and a task yield none
#       (tasks are the plan, not assertions to teach back).
#   3.  Section by section (REQ-C1.5, Done-when #1): claims carry a section id,
#       every section id resolves to a SECTION record, per-section ordinals run
#       1..k, and the decision section sorts after the requirement sections
#       (reading order).
#   4.  Plain, audience-neutral claims (REQ-C1.1, inherited from translate): no
#       claim's plain column and no section label leaks internal vocabulary.
#   5.  Reveal seam / back-pointer (D-2, REQ-D1.3): the claim ref resolves to a
#       model element and the source column restores the verbatim assertion.
#   6.  No verdict, structurally (REQ-D1.1, REQ-C1.5, REQ-D1.4): the view has no
#       column where an answer could live — CLAIM is exactly six fields, SECTION
#       four, RESPONSE two; nothing the tool adds is a judgement.
#   7.  Same claim set, both paths (Done-when #4): the set of claim refs equals
#       the model's live-requirement and decision id set, and the skill
#       documents the in-session walk reading this one extractor — so the
#       in-artifact and in-session paths cover the same claims by construction.
#   8.  Stream hygiene + determinism: every record has its fixed field count and
#       two runs are byte-identical.
#   9.  Graceful degradation: an empty stream emits nothing and exits 0; a
#       missing spec directory fails closed (exit 2) like the model/translate.
#   10. Composition over real bundles: the full chain over a real bundle groups
#       claims under real section titles, leaks no internal vocabulary, retains
#       the back-pointers, and covers exactly the model's live-req+decision set.
#
# Runs standalone: ./tests/test-spec-teachback.sh
set -eu

# Pin the C locale: charset checks and awk ranges must not vary by host locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
teachback="$here/../scripts/spec-teachback.sh"
translate="$here/../scripts/spec-translate.sh"
repo_root=$(cd "$here/.." && pwd)
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$teachback" ] || fail "scripts/spec-teachback.sh missing or not executable"
[ -x "$translate" ] || fail "scripts/spec-translate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# run_stream <expected-exit> — build a translation stream from $MODEL (a model
# record stream) via the real translate layer, pipe it into the teach-back view,
# and capture the combined output in $out. This exercises stdin (composable)
# mode over the real upstream layer, so the fixture stays a simple model stream.
out=
run_stream() {
  rexp=$1
  tstream=$(printf '%s' "$MODEL" | "$translate") \
    || fail "translate failed while building the fixture stream"
  rc=0
  out=$(printf '%s' "$tstream" | "$teachback" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "stream mode: expected exit $rexp, got $rc — output: $out"
}

# run_dir <expected-exit> <spec-dir> — run the teach-back view over a spec
# directory (full model->translate->teachback chain), capture in $out.
run_dir() {
  rexp=$1
  rc=0
  out=$("$teachback" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

# rec <field1> ... — assert a record whose leading fields match the given
# tab-separated values exists in $out (exact per column; trailing fields
# unconstrained). Up to five leading fields.
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

# norec_claim <ref> — assert no CLAIM record carries the given ref.
norec_claim() {
  printf '%s\n' "$out" \
    | awk -F"$tab" -v r="$1" '$1 == "CLAIM" && $2 == r { f = 1 } END { exit(f ? 1 : 0) }' \
    || fail "a CLAIM was emitted for $1, which should not be a teach-back claim"
}

# field <tag> <key> <col> — print column <col> of the first record whose tag and
# second column match.
field() {
  printf '%s\n' "$out" | awk -F"$tab" \
    -v t="$1" -v k="$2" -v c="$3" '$1 == t && $2 == k { print $c; exit }'
}

t() { printf '%s' "$tab"; }

# A model-stream fixture: two requirement groups (one carrying a superseded
# requirement, which is not a current claim), two decisions, and a task (the
# plan, not an assertion). Tab-separated, exactly as scripts/spec-model.sh emits.
MODEL="BUNDLE$(t)demo$(t)Active
FILE$(t)requirements$(t)present
FILE$(t)design$(t)present
REQ$(t)REQ-A1.1$(t)A$(t)live$(t)The renderer SHALL NOT soften a token below ≤ 64 characters, per the design (D-2).
REQ$(t)REQ-A1.2$(t)A$(t)live$(t)The reader MAY restate a claim in their own words.
REQ$(t)REQ-A1.3$(t)A$(t)superseded$(t)The retired rule once governed this, per (D-2).
REQ$(t)REQ-B1.1$(t)B$(t)live$(t)The command SHALL render a whole-bundle view by default.
REQCITE$(t)REQ-A1.1$(t)D-2
DEC$(t)D-1$(t)N$(t)Standalone command, not a kickoff sub-stage
DECFIELD$(t)D-1$(t)decision$(t)The command is a standalone tool run on demand at any stage.
DECFIELD$(t)D-1$(t)alternatives$(t)A kickoff sub-stage. Rejected because: it serves only the pre-sign-off moment.
DECFIELD$(t)D-1$(t)chosen$(t)Standalone serves every stage.
DEC$(t)D-2$(t)N$(t)Plain language is a lossless layered view
DECFIELD$(t)D-2$(t)decision$(t)The plain rendering is a view over the substrate (REQ-C1.7).
DECFIELD$(t)D-2$(t)alternatives$(t)Rewrite the bundle. Rejected because: rewriting loses traceability.
DECFIELD$(t)D-2$(t)chosen$(t)Layering keeps the artifact readable and traceable.
TASK$(t)3$(t)In progress$(t)Plain-language translation layer
TASKFIELD$(t)3$(t)deliverables$(t)the translator and the reveal mapping (D-2).
TASKDEP$(t)3$(t)2
TEST$(t)REQ-A1.1"

run_stream 0

# ---------------------------------------------------------------------------
# 1. Neutral response model: exactly agree/disagree/unsure, no answer marked.
# ---------------------------------------------------------------------------
rec RESPONSE agree
rec RESPONSE disagree
rec RESPONSE unsure
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "RESPONSE" { n++ } END { exit(n == 3 ? 0 : 1) }' \
  || fail "expected exactly three neutral response options (agree/disagree/unsure)"
# Each RESPONSE is a bare option (two fields): no third column could mark one
# correct/expected — the structure offers a choice, never an answer.
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "RESPONSE" && NF != 2 { bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "a RESPONSE record carries more than the bare option — a verdict could hide there"

# ---------------------------------------------------------------------------
# 2. Claim extraction: every live requirement and every decision is one claim;
# a superseded requirement and a task are not claims.
# ---------------------------------------------------------------------------
rec CLAIM REQ-A1.1 req-A
rec CLAIM REQ-A1.2 req-A
rec CLAIM REQ-B1.1 req-B
rec CLAIM D-1 decisions
rec CLAIM D-2 decisions
# A superseded requirement is history, not a current claim.
norec_claim REQ-A1.3
# Tasks are the plan, not assertions to agree/disagree with.
norec_claim task-3
norec_claim 3

# ---------------------------------------------------------------------------
# 3. Section by section: every claim's section resolves to a SECTION record,
# per-section ordinals run 1..k, decisions sort after the requirement sections.
# ---------------------------------------------------------------------------
rec SECTION req-A 1
rec SECTION req-B 2
rec SECTION decisions 3
# Per-section ordinals start at 1 and increase by one in source order.
rec CLAIM REQ-A1.1 req-A 1
rec CLAIM REQ-A1.2 req-A 2
rec CLAIM REQ-B1.1 req-B 1
rec CLAIM D-1 decisions 1
rec CLAIM D-2 decisions 2
# No orphan claim: every CLAIM section id has a SECTION record.
printf '%s\n' "$out" | awk -F"$tab" '
  $1 == "SECTION" { sec[$2] = 1 }
  $1 == "CLAIM" { used[$2 "\t" $3] = $3 }
  END {
    for (k in used) if (!(used[k] in sec)) { print "orphan claim section: " used[k]; bad = 1 }
    exit(bad ? 1 : 0)
  }
' || fail "a CLAIM references a section with no SECTION record"
# The decision section's order exceeds every requirement section's order.
printf '%s\n' "$out" | awk -F"$tab" '
  $1 == "SECTION" && $2 == "decisions" { dord = $3 }
  $1 == "SECTION" && $2 ~ /^req-/ { if ($3 > maxreq) maxreq = $3 }
  END { exit(dord > maxreq ? 0 : 1) }
' || fail "the decision section should sort after the requirement sections"

# ---------------------------------------------------------------------------
# 4. Plain, audience-neutral claims and section labels: no internal vocabulary.
# ---------------------------------------------------------------------------
plain_leaks=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { print $5 }' \
  | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+|REQ-[A-Z]([^A-Za-z0-9]|$)|D-[0-9]+|(requirements|design|tasks|test-spec)\.md|Task [0-9]+' || true)
[ -z "$plain_leaks" ] || fail "a claim's plain column leaks internal vocabulary: $plain_leaks"
label_leaks=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "SECTION" { print $4 }' \
  | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+|(requirements|design|tasks|test-spec)\.md|Task [0-9]+' || true)
[ -z "$label_leaks" ] || fail "a section label leaks internal vocabulary: $label_leaks"

# ---------------------------------------------------------------------------
# 5. Reveal seam: the claim ref resolves to a model element and the source
# column restores the verbatim assertion (the back-pointer is hidden in the
# plain column, preserved in the source — D-2 losslessness).
# ---------------------------------------------------------------------------
a11_plain=$(field CLAIM REQ-A1.1 5)
a11_src=$(field CLAIM REQ-A1.1 6)
case $a11_plain in
  *D-2*) fail "claim plain column leaks the back-pointer D-2: $a11_plain" ;;
esac
case $a11_plain in
  *"SHALL NOT"*) ;;
  *) fail "claim plain column lost the normative token SHALL NOT: $a11_plain" ;;
esac
case $a11_src in
  *D-2*) ;;
  *) fail "claim source column dropped the back-pointer D-2: $a11_src" ;;
esac

# ---------------------------------------------------------------------------
# 6. No verdict, structurally: there is no column for an answer. CLAIM is six
# fields, SECTION four, RESPONSE two — nothing the tool adds is a judgement.
# ---------------------------------------------------------------------------
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "CLAIM" && NF != 6 { bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "a CLAIM record does not have exactly six fields"
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "SECTION" && NF != 4 { bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "a SECTION record does not have exactly four fields"
# The view emits only the three view records; it never passes a substrate
# record through where a downstream verdict could be confused for content.
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 != "RESPONSE" && $1 != "SECTION" && $1 != "CLAIM" { print; bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "the teach-back view emitted an unexpected record type"

# ---------------------------------------------------------------------------
# 7. Same claim set, both paths: the claim refs equal the model's live-req +
# decision id set; the skill documents the in-session walk reading this one
# extractor, so both paths cover the same claims by construction.
# ---------------------------------------------------------------------------
expected=$(printf '%s\n' "$MODEL" | awk -F"$tab" '
  $1 == "REQ" && $4 == "live" { print $2 }
  $1 == "DEC" { print $2 }
' | sort)
got=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { print $2 }' | sort)
[ "$expected" = "$got" ] \
  || fail "claim set differs from the model live-req+decision set: expected [$expected] got [$got]"
skill="$repo_root/skills/spec-walkthrough/SKILL.md"
[ -f "$skill" ] || fail "skills/spec-walkthrough/SKILL.md is missing"
grep -q 'spec-teachback' "$skill" \
  || fail "SKILL.md does not document the in-session walk reading spec-teachback (same-claim-set contract)"

# ---------------------------------------------------------------------------
# 8. Determinism.
# ---------------------------------------------------------------------------
tstream=$(printf '%s' "$MODEL" | "$translate")
run1=$(printf '%s' "$tstream" | "$teachback")
run2=$(printf '%s' "$tstream" | "$teachback")
[ "$run1" = "$run2" ] || fail "teach-back output is not deterministic"

# ---------------------------------------------------------------------------
# 9. Graceful degradation.
# ---------------------------------------------------------------------------
out=$(printf '%s' "" | "$teachback" 2>&1) || fail "empty stream should exit 0"
[ -z "$out" ] || fail "empty stream should emit nothing, got: $out"
# A missing spec directory fails closed (mirrors the model and translate).
run_dir 2 "$tmp/does-not-exist"

# ---------------------------------------------------------------------------
# 10. Composition over real bundles: claims group under real section titles,
# leak no internal vocabulary, retain the back-pointers, and cover exactly the
# model's live-req + decision id set.
# ---------------------------------------------------------------------------
for spec in spec-comprehension bootstrap; do
  bundle="$repo_root/specs/$spec"
  [ -d "$bundle" ] || continue
  run_dir 0 "$bundle"

  # There are sections and claims.
  printf '%s\n' "$out" | awk -F"$tab" '$1 == "SECTION" { s = 1 } END { exit(s ? 0 : 1) }' \
    || fail "$spec produced no SECTION records"
  printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { c = 1 } END { exit(c ? 0 : 1) }' \
    || fail "$spec produced no CLAIM records"

  # Real section titles came through (dir mode reads the group headings): the
  # first requirement group's plain heading title appears as a SECTION label,
  # not a bare group letter.
  printf '%s\n' "$out" \
    | awk -F"$tab" '$1 == "SECTION" && $4 != "" && $4 !~ /^[A-Z]$/ { rich = 1 } END { exit(rich ? 0 : 1) }' \
    || fail "$spec section labels are bare keys, not the plain heading titles"

  # No claim plain column or section label leaks internal vocabulary.
  real_leaks=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { print $5 } $1 == "SECTION" { print $4 }' \
    | grep -oE 'REQ-[A-Z][0-9]+\.[0-9]+|REQ-[A-Z]([^A-Za-z0-9]|$)|D-[0-9]+|(requirements|design|tasks|test-spec)\.md|Task [0-9]+(\.[0-9]+)?' || true)
  [ -z "$real_leaks" ] || fail "$spec teach-back leaks internal vocabulary: $real_leaks"

  # The reveal layer is non-empty: at least one source column retains an id.
  has_id=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { print $6 }' \
    | grep -cE 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+' || true)
  [ "${has_id:-0}" -gt 0 ] || fail "$spec teach-back retains no back-pointers in the source column"

  # The claim set equals the model's live-requirement + decision id set.
  expected=$("$here/../scripts/spec-model.sh" "$bundle" | awk -F"$tab" '
    $1 == "REQ" && $4 == "live" { print $2 }
    $1 == "DEC" { print $2 }
  ' | sort)
  got=$(printf '%s\n' "$out" | awk -F"$tab" '$1 == "CLAIM" { print $2 }' | sort)
  [ "$expected" = "$got" ] \
    || fail "$spec claim set differs from the model live-req+decision set"
done

# ---------------------------------------------------------------------------
# 11. Verbatim claim text (REQ-D1.1/REQ-C1.5, the independence firewall): the
# view copies each claim's plain and source columns from the upstream
# translation unchanged — it injects no content of its own, so no verdict,
# score, or decoration can ride in the claim text. Every CLAIM's plain/source
# must equal the upstream TEXT record's plain/source for that element.
# ---------------------------------------------------------------------------
tstream=$(printf '%s' "$MODEL" | "$translate")
tbout=$(printf '%s' "$tstream" | "$teachback")
printf '%s\n@@@SEP@@@\n%s\n' "$tstream" "$tbout" | awk -F"$tab" '
  $0 == "@@@SEP@@@" { sep = 1; next }
  !sep && $1 == "TEXT" && $3 == "requirement" { plain["REQ:" $2] = $4; src["REQ:" $2] = $5 }
  !sep && $1 == "TEXT" && $3 == "decision-decision" {
    b = $2; sub(/#.*/, "", b); plain["DEC:" b] = $4; src["DEC:" b] = $5
  }
  sep && $1 == "CLAIM" {
    key = ($2 ~ /^D-/) ? "DEC:" $2 : "REQ:" $2
    if ($5 != plain[key]) { print "plain mismatch: " $2; bad = 1 }
    if ($6 != src[key]) { print "source mismatch: " $2; bad = 1 }
  }
  END { exit(bad ? 1 : 0) }
' || fail "a CLAIM column is not a verbatim copy of the upstream translation (the view injected content into a claim)"

# ---------------------------------------------------------------------------
# 12. Decisions sort last, structurally (Done-when #1 reading order): even when
# a decision claim is seen before any requirement in the stream, the decision
# section still sorts after every requirement section. Fed directly to the view
# (not through translate, which always emits requirements first) so the view's
# own ordering is what is under test.
# ---------------------------------------------------------------------------
DSTREAM="TEXT$(t)D-1#decision$(t)decision-decision$(t)A decided thing$(t)A decided thing (D-1)
REQ$(t)REQ-A1.1$(t)A$(t)live$(t)A requirement
TEXT$(t)REQ-A1.1$(t)requirement$(t)A requirement$(t)A requirement"
out=$(printf '%s' "$DSTREAM" | "$teachback" 2>&1) || fail "direct-stream teach-back failed"
rec CLAIM REQ-A1.1 req-A 1
rec CLAIM D-1 decisions 1
printf '%s\n' "$out" | awk -F"$tab" '
  $1 == "SECTION" && $2 == "decisions" { dord = $3 }
  $1 == "SECTION" && $2 ~ /^req-/ { if ($3 > maxreq) maxreq = $3 }
  END { exit(dord > maxreq ? 0 : 1) }
' || fail "a decision seen before any requirement must still sort the decisions section last"

# ---------------------------------------------------------------------------
# 13. A requirement group with no live requirements yields no section and no
# claims (all-superseded edge): the section registers only when a live claim
# files under it.
# ---------------------------------------------------------------------------
MODEL="BUNDLE$(t)demo$(t)Active
FILE$(t)requirements$(t)present
REQ$(t)REQ-A1.1$(t)A$(t)live$(t)A live requirement.
REQ$(t)REQ-C1.1$(t)C$(t)superseded$(t)A retired requirement.
REQ$(t)REQ-C1.2$(t)C$(t)superseded$(t)Another retired requirement."
run_stream 0
rec SECTION req-A 1
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "SECTION" && $2 == "req-C" { f = 1 } END { exit(f ? 1 : 0) }' \
  || fail "an all-superseded requirement group should produce no section"
norec_claim REQ-C1.1
norec_claim REQ-C1.2

# ---------------------------------------------------------------------------
# 14. Field-count integrity with empty claim text: a claim whose plain and
# source are empty still emits a six-field CLAIM record (the trailing tabs are
# present), so the "no column for a verdict" structural guarantee holds even at
# the empty edge.
# ---------------------------------------------------------------------------
ESTREAM="REQ$(t)REQ-A1.1$(t)A$(t)live$(t)x
TEXT$(t)REQ-A1.1$(t)requirement$(t)$(t)"
out=$(printf '%s' "$ESTREAM" | "$teachback" 2>&1) || fail "empty-text direct stream failed"
rec CLAIM REQ-A1.1 req-A 1
printf '%s\n' "$out" \
  | awk -F"$tab" '$1 == "CLAIM" && NF != 6 { bad = 1 } END { exit(bad ? 1 : 0) }' \
  || fail "a CLAIM with empty plain/source does not have six fields"

echo "PASS: test-spec-teachback.sh"
