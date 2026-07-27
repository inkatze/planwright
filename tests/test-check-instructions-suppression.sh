#!/bin/bash
# Tests for scripts/check-instructions.sh — the CAPPED CHARGE for permanently
# exempt docs, the pending-diet Task field on the audit surface, derived
# present-offender expectations, and the reverse use-site check
# (instruction-headroom Task 3: REQ-B1.1, REQ-B1.2, REQ-D1.5; Task 4: REQ-D1.2,
# REQ-D1.4; Task 5: REQ-D1.3, D-7). Sections 16–19 of the pre-split file,
# numbering kept.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# The through-line: how a suppression's cost is accounted for rather than
# ignored. A permanently exempt doc is charged at its cap (not its real size) to
# every dependent aggregate, a pending-diet allowance carries its owning Task
# into the audit output, the offender expectations are DERIVED from the
# suppression list rather than a hardcoded name list, and the reverse use-site
# check flags a manifest-named doc that no skill body actually references.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-instructions.sh"

failures=0
assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

# make N words of filler prose (N space-separated tokens) on one line. awk
# keeps this O(n) — a shell concat loop is O(n^2) and times out on big fixtures.
words() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "w "; printf "\n" }'
}

# Build a minimal instruction tree under $1 with the instruction_budget_* knobs
# at their production defaults. Individual tests then add skills/docs/hooks.
scaffold() {
  root="$1"
  mkdir -p "$root/skills" "$root/doctrine" "$root/hooks" "$root/config"
  cat >"$root/config/defaults.yml" <<'EOF'
instruction_budget_skill_warn: 3000
instruction_budget_skill_error: 4250
instruction_budget_doctrine_warn: 2500
instruction_budget_doctrine_error: 4000
instruction_budget_startload_warn: 8000
instruction_budget_startload_error: 10000
instruction_budget_closure_warn: 15000
instruction_budget_closure_error: 20000
instruction_budget_skill_floor: 250
instruction_budget_doctrine_floor: 250
instruction_budget_startload_floor: 500
instruction_budget_closure_floor: 1000
instruction_budget_injected_warn: 200
EOF
  : >"$root/config/instruction-budget-exemptions.txt"
  # An empty hooks.json so the injected-context scan is a clean no-op unless a
  # test registers a hook.
  cat >"$root/hooks/hooks.json" <<'EOF'
{ "hooks": {} }
EOF
}

# make a skill SKILL.md of a given body word-count, with optional manifest lines
# passed as remaining args (each a full "Doctrine: ..." line). No heading is
# written, so a no-manifest SKILL.md's wc -w equals body_words exactly (keeps
# the boundary-threshold fixtures deterministic).
make_skill() {
  root="$1"
  name="$2"
  body_words="$3"
  shift 3
  mkdir -p "$root/skills/$name"
  {
    words "$body_words"
    echo
    for line in "$@"; do
      printf '%s\n' "$line"
    done
  } >"$root/skills/$name/SKILL.md"
}

make_doc() {
  # make_doc <root> <name> <words>; wc -w of the doc equals <words> exactly.
  root="$1"
  name="$2"
  {
    words "$3"
    echo
  } >"$root/doctrine/$name.md"
}
# raise the doctrine per-file budget in a fixture so a large run-start/point-of-use
# doc does not trip its own per-file budget — isolating the start-load/closure
# budget under test. Raising a budget knob above its core default now requires a
# recorded rationale (instruction-headroom REQ-A1.4/D-12), so the raise| entries
# are appended to the exemptions file; callers that also write their own
# exemptions must APPEND (`>>`) after this runs, so both survive.
lift_doctrine_budget() {
  mkdir -p "$1/.claude"
  cat >>"$1/.claude/planwright.local.yml" <<'EOF'
instruction_budget_doctrine_warn: 99999
instruction_budget_doctrine_error: 99999
EOF
  cat >>"$1/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_doctrine_warn|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
raise|instruction_budget_doctrine_error|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
EOF
}

# Derive the present-offender expectations from a suppression list instead of
# hardcoding file names (instruction-headroom REQ-D1.4, D-8). Every `exempt` and
# `pending-diet` entry names a surface that must still appear on the offender
# shortlist, tagged with its suppression; the emitted "<shortlist-target>\t<tag>"
# records track the config that defines the corpus's sanctioned state, so adding
# an exemption grows the expectations with no test edit. The dieted-clean
# absent-checks are structurally underivable and stay an explicit list.
derive_present_offenders() {
  # derive_present_offenders <exemptions-file>
  awk -F '|' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == "exempt" { print $2 "\t[exempt]"; next }
    $1 == "pending-diet" {
      if      ($2 == "file")       print $3 "\t[pending-diet]"
      else if ($2 == "start-load") print "start-load " $3 "\t[pending-diet]"
      else if ($2 == "closure")    print "closure " $3 "\t[pending-diet]"
      next
    }
  ' "$1"
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 16. Capped charge for permanently exempt docs (instruction-headroom Task 3:
#     D-4, REQ-B1.1, REQ-B1.2, REQ-D1.5). An aggregate (start-load / closure)
#     charges a permanently exempt manifest doc at min(actual, its per-file
#     error threshold = the doctrine error threshold), so a dependent pays the
#     budgeted size and never the overage; a non-exempt doc stays fully charged.
#     --audit prints the honest actual beside the charged value on both the
#     capped doc's own per-file line and the dependent aggregate line.
########################################################################
# 16a. cap on BOTH a dependent start-load and closure. capdoc (4500, EXEMPT, over
#      the doctrine per-file error 4000) is charged 4000; fulldoc (4500,
#      NON-exempt, carried transiently by a per-file pending-diet allowance so it
#      does not trip its own per-file error) stays fully charged at 4500. dep
#      front-loads capdoc (run-start) and reaches fulldoc (point-of-use), so its
#      start-load caps and its closure carries one capped + one full doc.
t16="$tmproot/t16"
scaffold "$t16"
make_doc "$t16" capdoc 4500  # exempt, over 4000 -> charged 4000
make_doc "$t16" fulldoc 4500 # non-exempt, over 4000 -> stays 4500 (pending-diet covers its per-file)
make_skill "$t16" dep 100 \
  "Doctrine: run-start capdoc" \
  "Doctrine: point-of-use fulldoc (rare branch)"
make_skill "$t16" plain 100 "Doctrine: run-start fulldoc"
cat >"$t16/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|doctrine/capdoc.md|standing rationale: kept large on purpose
pending-diet|file|doctrine/fulldoc.md|Task 9|non-exempt over-budget doc, dieted later
EOF
depbody=$(wc -w <"$t16/skills/dep/SKILL.md" | tr -d ' ')
plainbody=$(wc -w <"$t16/skills/plain/SKILL.md" | tr -d ' ')
cap=4000
exp_sl=$((depbody + cap))                # start-load charged: body + capped capdoc
exp_sl_actual=$((depbody + 4500))        # start-load actual: body + full capdoc
exp_cl=$((depbody + cap + 4500))         # closure charged: + full non-exempt fulldoc
exp_cl_actual=$((depbody + 4500 + 4500)) # closure actual: full capdoc + full fulldoc
exp_plain=$((plainbody + 4500))          # plain start-load: no exempt doc, full charge

out="$(/bin/bash "$CHECKER" --root "$t16" 2>&1)"
assert_exit "capped-charge fixture keeps the guard green" 0 $?

aud="$(/bin/bash "$CHECKER" --audit --root "$t16" 2>&1)"
# the exempt doc caps the dependent start-load (min(4500,4000)=4000), NOT 4500.
dep_row="$(printf '%s\n' "$aud" | grep -F 'dep start-load=')"
assert_contains "exempt doc caps the dependent start-load at the doctrine error threshold" \
  "dep start-load=$exp_sl " "$dep_row"
assert_contains "capped start-load prints the honest actual beside the charged total" \
  "(actual $exp_sl_actual)" "$dep_row"
assert_contains "closure carries the capped exempt doc plus the full non-exempt doc" \
  "closure=$exp_cl " "$dep_row"
assert_contains "capped closure prints the honest actual beside the charged total" \
  "(actual $exp_cl_actual)" "$dep_row"

# the per-file line for the capped doc shows BOTH actual (words=) and charged=.
cap_row="$(printf '%s\n' "$aud" | grep -F 'doctrine/capdoc.md')"
assert_contains "capped doc per-file line shows the actual word count" "words=4500" "$cap_row"
assert_contains "capped doc per-file line shows the charged word count" "charged=4000" "$cap_row"

# a NON-exempt doc stays fully charged and shows no charged= column.
full_row="$(printf '%s\n' "$aud" | grep -F 'doctrine/fulldoc.md')"
# guard the assert_absent against a vacuous pass: prove the row is present first,
# so "no charged= column" cannot pass merely because the row went missing.
assert_contains "the non-exempt doc's per-file row is present (non-vacuous guard)" \
  "words=4500" "$full_row"
assert_absent "a non-exempt doc's per-file line carries no charged= column" "charged=" "$full_row"
plain_row="$(printf '%s\n' "$aud" | grep -F 'plain start-load=')"
assert_contains "a non-exempt doc is charged in full to a dependent start-load" \
  "plain start-load=$exp_plain " "$plain_row"
assert_absent "an uncapped aggregate line shows no (actual) twin" "(actual" "$plain_row"

# 16b. the cap uses the per-file error threshold as its value: lowering the
#      doctrine error knob lowers the charged cap (the knob drives the cap, not a
#      hardcoded constant). Raising the knob needs a recorded rationale, so this
#      fixture LOWERS it via overlay (a lowered budget needs no raise entry).
t16b="$tmproot/t16b"
scaffold "$t16b"
make_doc "$t16b" capdoc 4500
make_skill "$t16b" dep 100 "Doctrine: run-start capdoc"
cat >"$t16b/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|doctrine/capdoc.md|standing rationale: kept large on purpose
EOF
mkdir -p "$t16b/.claude"
cat >"$t16b/.claude/planwright.local.yml" <<'EOF'
instruction_budget_doctrine_error: 3500
EOF
depbody_b=$(wc -w <"$t16b/skills/dep/SKILL.md" | tr -d ' ')
aud="$(/bin/bash "$CHECKER" --audit --root "$t16b" 2>&1)"
dep_row_b="$(printf '%s\n' "$aud" | grep -F 'dep start-load=')"
assert_contains "the doctrine error knob (not a constant) drives the cap value" \
  "dep start-load=$((depbody_b + 3500)) " "$dep_row_b"
assert_contains "lowered-knob cap still prints the honest actual" \
  "(actual $((depbody_b + 4500)))" "$dep_row_b"

# 16c. an exempt doc AT or UNDER its per-file error threshold charges its actual
#      (min() is a no-op): no cap, no charged= column, no (actual) twin.
t16c="$tmproot/t16c"
scaffold "$t16c"
make_doc "$t16c" smallexempt 1000 # exempt but under 4000 -> min(1000,4000)=1000
make_skill "$t16c" dep 100 "Doctrine: run-start smallexempt"
cat >"$t16c/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|doctrine/smallexempt.md|standing rationale: kept exempt though small
EOF
depbody_c=$(wc -w <"$t16c/skills/dep/SKILL.md" | tr -d ' ')
aud="$(/bin/bash "$CHECKER" --audit --root "$t16c" 2>&1)"
small_row="$(printf '%s\n' "$aud" | grep -F 'doctrine/smallexempt.md')"
# guard the assert_absent against a vacuous pass: prove the row is present first,
# so "no charged= column" cannot pass merely because the row went missing.
assert_contains "the under-threshold exempt doc's per-file row is present (non-vacuous guard)" \
  "words=1000" "$small_row"
assert_absent "an under-threshold exempt doc gets no charged= column" "charged=" "$small_row"
dep_row_c="$(printf '%s\n' "$aud" | grep -F 'dep start-load=')"
assert_contains "an under-threshold exempt doc charges its actual to the aggregate" \
  "dep start-load=$((depbody_c + 1000)) " "$dep_row_c"
assert_absent "an uncapped exempt-but-small aggregate shows no (actual) twin" \
  "(actual" "$dep_row_c"

# 16f. the cap fires on the POINT-OF-USE-only path too (closure branch, not
#      start-load): an exempt over-threshold doc reached only via point-of-use
#      caps the closure while the start-load (which never includes it) is
#      untouched. This isolates the else-branch cap that 16a's run-start doc does
#      not exercise; a mutation dropping the cap there moves only the closure.
t16f="$tmproot/t16f"
scaffold "$t16f"
make_doc "$t16f" pucap 4500 # exempt, over 4000, reached point-of-use only
make_skill "$t16f" puskill 100 "Doctrine: point-of-use pucap (rare branch)"
cat >"$t16f/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|doctrine/pucap.md|standing rationale: kept large on purpose
EOF
pubody=$(wc -w <"$t16f/skills/puskill/SKILL.md" | tr -d ' ')
aud="$(/bin/bash "$CHECKER" --audit --root "$t16f" 2>&1)"
pu_row="$(printf '%s\n' "$aud" | grep -F 'puskill start-load=')"
# start-load carries no point-of-use doc, so it equals the body and shows no cap.
assert_contains "point-of-use-only start-load is uncapped (body only)" \
  "puskill start-load=$pubody " "$pu_row"
# closure caps the exempt point-of-use doc at 4000, printing the actual (body+4500).
assert_contains "point-of-use exempt doc caps the closure at the doctrine threshold" \
  "closure=$((pubody + 4000)) " "$pu_row"
assert_contains "point-of-use capped closure prints the honest actual" \
  "(actual $((pubody + 4500)))" "$pu_row"

# 16d. real-corpus proof (Task 3 Done-when): the orchestrate closure and
#      execute-task start-load charge spec-format.md at its 4,000 per-file error
#      threshold, and the larger actual stays printed beside the charged total.
#      Derived from the guard's own output so it is robust to word-count drift
#      (R4): the overage (actual spec-format words − 4,000) is exactly the gap
#      between each dependent aggregate's charged and actual values. It still
#      assumes spec-format stays run-start for execute-task and point-of-use for
#      orchestrate (true through this spec's tasks); a structural reclassification
#      would fail this loud (the empty-actual guard below), not pass silently.
aud="$(/bin/bash "$CHECKER" --audit 2>&1)"
sf_line="$(printf '%s\n' "$aud" | grep -F 'doctrine/spec-format.md ' | grep -F 'charged=')"
assert_contains "spec-format.md is charged at its 4,000 per-file error threshold" \
  "charged=4000" "$sf_line"
sf_actual="$(printf '%s\n' "$sf_line" | sed -n 's/.*words=\([0-9]*\).*/\1/p')"
overage=$((sf_actual - 4000))
et_line="$(printf '%s\n' "$aud" | grep -F 'execute-task start-load=')"
et_sl="$(printf '%s\n' "$et_line" | sed -n 's/.*start-load=\([0-9]*\).*/\1/p')"
et_sl_actual="$(printf '%s\n' "$et_line" | sed -n 's/.*start-load=[0-9]* ([^)]*) (actual \([0-9]*\)).*/\1/p')"
if [ -n "$et_sl_actual" ] && [ "$((et_sl_actual - et_sl))" -eq "$overage" ]; then
  echo "ok: execute-task start-load charges spec-format at 4,000 (actual − charged == overage)"
else
  echo "FAIL: execute-task start-load charged/actual gap ($et_sl / $et_sl_actual) != spec-format overage ($overage)" >&2
  failures=$((failures + 1))
fi
or_line="$(printf '%s\n' "$aud" | grep -F 'orchestrate start-load=' | grep -F 'closure=')"
or_cl="$(printf '%s\n' "$or_line" | sed -n 's/.*closure=\([0-9]*\).*/\1/p')"
or_cl_actual="$(printf '%s\n' "$or_line" | sed -n 's/.*closure=[0-9]* ([^)]*) (actual \([0-9]*\)).*/\1/p')"
if [ -n "$or_cl_actual" ] && [ "$((or_cl_actual - or_cl))" -eq "$overage" ]; then
  echo "ok: orchestrate closure charges spec-format at 4,000 (actual − charged == overage)"
else
  echo "FAIL: orchestrate closure charged/actual gap ($or_cl / $or_cl_actual) != spec-format overage ($overage)" >&2
  failures=$((failures + 1))
fi

# 16e. content-pin on the rewritten spec-format exemption rationale (REQ-D1.5):
#      the superseded "dominant run-start load" claim and the stale trim-gap
#      figure are gone; the capped-charge law is stated.
exem="$(cat "$REPO_ROOT/config/instruction-budget-exemptions.txt")"
assert_absent "exemption rationale drops the superseded 'dominant run-start load' claim" \
  "dominant run-start load" "$exem"
assert_absent "exemption rationale drops the stale '570-word gap' trim figure" \
  "570-word gap" "$exem"
assert_contains "exemption rationale states the capped-charge law" \
  "capped-charge law" "$exem"

########################################################################
# 17. pending-diet Task field is visible in the audit surface (REQ-D1.2, D-8).
#     The offender shortlist and the ranked per-file report print each
#     pending-diet allowance's Task field, so retagging the allowance's Task
#     changes the asserted output — the signal the suppression-derived test
#     surface (section 0, REQ-D1.4) reads.
########################################################################
# 17a. a START-LOAD allowance's Task field rides its shortlist row, and a retag
#      changes the asserted output.
t17="$tmproot/t17"
scaffold "$t17"
make_doc "$t17" bigdoc 9999
make_skill "$t17" heavy 500 "Doctrine: run-start bigdoc"
lift_doctrine_budget "$t17"
cat >>"$t17/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|start-load|heavy|Task 7|reclassified to point-of-use in Task 7
EOF
aud="$(/bin/bash "$CHECKER" --audit --root "$t17" 2>&1)"
sl="${aud##*Offender shortlist}"
assert_contains "shortlist prints the allowance's Task field" "[Task 7]" "$sl"
heavy_row="$(printf '%s\n' "$sl" | grep -F 'start-load heavy')"
assert_contains "the Task field is on the offender's own shortlist row" "[Task 7]" "$heavy_row"

# Retag the SAME allowance (Task 7 -> Task 8); nothing else changes. The raise
# rationales stay so the lifted doctrine budget keeps its recorded rationale.
cat >"$t17/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_doctrine_warn|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
raise|instruction_budget_doctrine_error|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
pending-diet|start-load|heavy|Task 8|reclassified to point-of-use in Task 8
EOF
aud2="$(/bin/bash "$CHECKER" --audit --root "$t17" 2>&1)"
sl2="${aud2##*Offender shortlist}"
assert_contains "the retagged Task field appears in output" "[Task 8]" "$sl2"
assert_absent "the old Task field is gone after the retag" "[Task 7]" "$sl2"

# 17b. a PER-FILE allowance's Task field rides the ranked per-file report row.
t17b="$tmproot/t17b"
scaffold "$t17b"
make_skill "$t17b" dietme 5000 # over skill error 4250 -> per-file offender
cat >"$t17b/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|file|skills/dietme/SKILL.md|Task 6|body diet pending
EOF
aud="$(/bin/bash "$CHECKER" --audit --root "$t17b" 2>&1)"
ranked="${aud%%Offender shortlist*}" # the ranked report is everything before the shortlist
dietme_row="$(printf '%s\n' "$ranked" | grep -F 'skills/dietme/SKILL.md')"
assert_contains "ranked per-file row carries the pending-diet tag" "[pending-diet]" "$dietme_row"
assert_contains "ranked per-file row carries the allowance Task field" "[Task 6]" "$dietme_row"

# 17c. echo discipline (cross-cutting, REQ-B1.9): the Task field is raw,
#      PR-controllable exemptions-file text, so a control byte in it is stripped
#      before it reaches the audit surface — matching every other echoed value.
t17c="$tmproot/t17c"
scaffold "$t17c"
make_skill "$t17c" dietme 5000
esc="$(printf '\033')"
printf 'pending-diet|file|skills/dietme/SKILL.md|Task%s6|body diet pending\n' "$esc" \
  >"$t17c/config/instruction-budget-exemptions.txt"
aud="$(/bin/bash "$CHECKER" --audit --root "$t17c" 2>&1)"
assert_exit "a control-byte Task field does not fail the guard" 0 $?
assert_contains "the offender still appears in the audit surface" "skills/dietme/SKILL.md" "$aud"
assert_absent "the control byte is stripped from the echoed Task field" "$esc" "$aud"

########################################################################
# 18. Section-0 present-offender expectations are DERIVED from the suppression
#     list, not a hardcoded name list (REQ-D1.4, D-8): adding an exemption to a
#     fixture's config grows the derived set with no test name-list edit.
########################################################################
t18="$tmproot/t18"
scaffold "$t18"
make_skill "$t18" dietme 5000 # an over-threshold offender the guard will list
before="$(derive_present_offenders "$t18/config/instruction-budget-exemptions.txt")"
assert_absent "derived expectations are empty before any exemption is added" \
  "skills/dietme/SKILL.md" "$before"
# Add ONE exemption — the only edit — and the derived expectation set grows.
cat >"$t18/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|file|skills/dietme/SKILL.md|Task 6|body diet pending
EOF
after="$(derive_present_offenders "$t18/config/instruction-budget-exemptions.txt")"
assert_contains "adding an exemption grows the derived expectations (no name-list edit)" \
  "skills/dietme/SKILL.md" "$after"
# The derived expectation matches real guard output: the offender is on the
# shortlist, tagged with the suppression the derivation predicted.
aud="$(/bin/bash "$CHECKER" --audit --root "$t18" 2>&1)"
sl="${aud##*Offender shortlist}"
while IFS="$(printf '\t')" read -r tgt tag; do
  [ -n "$tgt" ] || continue
  row="$(printf '%s\n' "$sl" | grep -F "$tgt" | head -n1)"
  assert_contains "derived offender '$tgt' appears on the fixture shortlist" "$tgt" "$sl"
  assert_contains "derived offender '$tgt' carries its predicted tag $tag" "$tag" "$row"
done <<EOF
$after
EOF

########################################################################
# 19. Reverse use-site check (instruction-headroom Task 5: REQ-D1.3, D-7).
#     Every point-of-use manifest doc must be named in body prose outside the
#     manifest block and fenced code; a miss is a WARNING (never an error),
#     matched as a fixed string over the charset-validated name. A
#     `declared-exception|use-site:<skill>/<doc>|<reason>` entry excuses exactly
#     that use-site warning and nothing else (REQ-D1.6, D-11).
########################################################################
# 19a. missing: a point-of-use doc named nowhere in body prose warns naming the
#      skill and doc, and does NOT fail the guard.
t19a="$tmproot/t19a"
scaffold "$t19a"
make_doc "$t19a" lonelydoc 10
make_skill "$t19a" usmiss 100 \
  "Doctrine: point-of-use lonelydoc (at the widget step)"
out="$(/bin/bash "$CHECKER" --root "$t19a" 2>&1)"
assert_exit "a missing use-site is a warning, not an error" 0 $?
assert_contains "use-site warning fires naming the skill and doc" \
  "use-site:usmiss/lonelydoc" "$out"

# 19b. named: the same doc named at a step in body prose silences the warning.
t19b="$tmproot/t19b"
scaffold "$t19b"
make_doc "$t19b" nameddoc 10
make_skill "$t19b" usnamed 100 \
  "Doctrine: point-of-use nameddoc (at the widget step)" \
  "The nameddoc doc is consulted at the widget step."
out="$(/bin/bash "$CHECKER" --root "$t19b" 2>&1)"
assert_exit "a named use-site keeps the guard green" 0 $?
assert_absent "a point-of-use doc named in body prose emits no use-site warning" \
  "use-site:usnamed/nameddoc" "$out"

# 19c. named only in the manifest line and inside fenced code STILL warns: neither
#      the manifest block nor fenced code counts as a body-prose naming.
t19c="$tmproot/t19c"
scaffold "$t19c"
make_doc "$t19c" fenceddoc 10
make_skill "$t19c" usfenced 100 \
  "Doctrine: point-of-use fenceddoc (at the widget step)" \
  '```' \
  'the fenceddoc doc is only shown here, inside a code fence' \
  '```'
out="$(/bin/bash "$CHECKER" --root "$t19c" 2>&1)"
assert_exit "a manifest/fenced-only naming does not error" 0 $?
assert_contains "a doc named only in the manifest or fenced code still warns" \
  "use-site:usfenced/fenceddoc" "$out"

# 19d. a `use-site:<skill>/<doc>` declared-exception excuses that use-site warning
#      and NOTHING else. The skill body (3900) is also below its per-file
#      restoration target, so a below-target warning fires on a DIFFERENT surface;
#      the use-site exception must silence the use-site warning while leaving the
#      below-target warning untouched. A used exception is not reported stale.
t19d="$tmproot/t19d"
scaffold "$t19d"
make_doc "$t19d" exdoc 10
make_skill "$t19d" usbt 3900 \
  "Doctrine: point-of-use exdoc (at the widget step)"
out="$(/bin/bash "$CHECKER" --root "$t19d" 2>&1)"
assert_contains "baseline: the use-site warning fires" "use-site:usbt/exdoc" "$out"
assert_contains "baseline: a below-target warning fires on the body surface" \
  "below-target: skills/usbt/SKILL.md" "$out"
cat >"$t19d/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|use-site:usbt/exdoc|accepted: exdoc is consulted only via an external cross-reference
EOF
out="$(/bin/bash "$CHECKER" --root "$t19d" 2>&1)"
assert_exit "a matching use-site declared-exception keeps the guard green" 0 $?
assert_absent "the use-site declared-exception silences the use-site warning it names" \
  "use-site:usbt/exdoc" "$out"
assert_contains "the use-site declared-exception does not silence the below-target warning" \
  "below-target: skills/usbt/SKILL.md" "$out"
assert_absent "a USED use-site declared-exception is not reported stale" \
  "declared-exception cleanup" "$out"

# 19e. a skill whose manifest failed to resolve is SKIPPED by the use-site check
#      (its manifest error stands, and no use-site warning is emitted for it).
t19e="$tmproot/t19e"
scaffold "$t19e"
make_skill "$t19e" usbroken 100 \
  "Doctrine: point-of-use nosuchdoc (at the widget step)"
out="$(/bin/bash "$CHECKER" --root "$t19e" 2>&1)"
assert_exit "an unresolvable manifest doc fails the guard" 1 $?
assert_contains "the unresolvable manifest error stands" \
  "unresolvable doctrine reference 'nosuchdoc'" "$out"
assert_absent "a skill with an unresolved manifest emits no use-site warning" \
  "use-site:usbroken/nosuchdoc" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions capped-charge/use-site tests passed"
