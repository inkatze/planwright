#!/bin/bash
# Tests for docs/allocation.md — the operator-facing allocation-policy guide
# (model-allocation Task 7; D-5, D-8, D-11, D-13; REQ-E1.2, REQ-F1.1, REQ-B1.3,
# REQ-C1.7).
#
# Two of this task's REQs are verified `[design-level]` in test-spec.md, and
# both name THIS doc as the artifact: REQ-B1.3 (the in-session rung's
# inheritance stated as its pinned degradation) and REQ-C1.7's second clause
# (rungs without a worktree have no petition channel). A content check, the
# test-spec says, not existence alone — so those two are asserted as prose here.
#
# The rest of the suite is a TETHER rather than a prose check, in the shape
# check-options-reference.sh already uses for docs/fleet.md's knob table: the
# identifiers an operator reads out of this doc are extracted from the shipped
# scripts and config, and the doc must name every one of them. The doc's whole
# contract is that its six questions are answerable WITHOUT reading source, so a
# schema, enum, path, or default that drifts out from under it is exactly the
# failure that must fail CI rather than rot silently.
#
# TETHERS ARE TABLE-ANCHORED, NOT SUBSTRING. A bare `grep -F ts` over the doc
# matches "its" and "tests" on a hundred lines, so a tether written that way
# passes even if the table it is supposed to guard were deleted outright. Every
# vocabulary this suite guards is rendered as a backticked leading table cell,
# so the assertions look for `| `<token>` |`. Closed enums are additionally
# checked in BOTH directions (set equality against the doc's own table), so a
# value the code retired cannot linger in the guide telling operators to grep
# for something that will never appear.
#
# What is covered here:
#   - the doc exists, and every source this suite parses is readable;
#   - the 15-field ledger schema, by name AND in schema order;
#   - the outcome, scope, event-class, clamp-token, rung, and selection-key
#     vocabularies, with counts pinned so an under-parse cannot pass quietly;
#   - the model and effort ladder ORDERS, not merely their members;
#   - shipped defaults tethered to config/defaults.yml: the four adaptation
#     knobs, the six fleet_* starting-tier values, and the two per-tier cap
#     thresholds the worked clamp example's arithmetic depends on;
#   - the fallback precedence and both sentinels;
#   - the pinned petition path and its refusal details;
#   - the resolver's output fields and the ledger row `inputs` keys;
#   - REQ-B1.3 and REQ-C1.7's design-level content checks;
#   - a named section per Done-when question;
#   - cross-links in both directions, and the link + options guards passing;
#   - every ledger row shown in the doc carrying exactly 15 fields;
#   - the two "not yet wired to a caller" claims, which go stale the moment a
#     caller appears — so a caller appearing fails here and forces the edit.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-docs.sh
#
# `set -u` without `-e`, deliberately: this suite accumulates failures and
# reports them all, the way tests/test-check-options-reference.sh does. Under
# `set -e` a single unguarded non-zero would abort mid-run and hide every later
# check, which is the opposite of what a coverage tether owes its reader.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd) || {
  echo "FAIL: cannot resolve the script directory" >&2
  exit 1
}
root="$here/.."
DOC="$root/docs/allocation.md"
LEDGER="$root/scripts/allocation-ledger.sh"
LADDER="$root/scripts/allocation-ladder.sh"
PETITION="$root/scripts/allocation-petition.sh"
ADAPT="$root/scripts/allocation-adapt.sh"
GATE="$root/scripts/fleet-usage-gate.sh"
CONFIG="$root/config/defaults.yml"
FLEET_DOC="$root/docs/fleet.md"
README="$root/README.md"
REFERENCE="$root/docs/options-reference.md"

failures=0

# The label defaults rather than tripping `set -u`: a helper accidentally called
# without one must still report its failure, not kill the run before the summary.
fail() {
  echo "FAIL: ${1:-unlabelled check}" >&2
  failures=$((failures + 1))
}

# section_ok <label>: print the group's ok line only when the group added no
# failures. Without this a run with a dozen FAILs still prints every `ok:`, and
# the merged stderr/stdout log reads as if the suite both failed and passed.
section_start=0
begin() { section_start=$failures; }
section_ok() {
  if [ "$failures" -eq "$section_start" ]; then echo "ok: $1"; fi
}

# doc_cell <token> <label>: the token is a backticked LEADING table cell in the
# doc — the position the doc defines its vocabularies in. This is the
# discriminating form; see the header note on why substring matching is not.
doc_cell() {
  grep -qF -- "| \`$1\` |" "$DOC" || fail "${2:-doc_cell} (no table row defines \`$1\`)"
}

# doc_code <token> <label>: the token appears inside a backticked code span
# somewhere in the doc. For vocabularies the doc states in prose rather than a
# table (the inert event classes, the rung chain).
doc_code() {
  grep -qF -- "\`$1\`" "$DOC" || fail "${2:-doc_code} (doc does not name \`$1\`)"
}

# doc_has <needle> <label>: plain substring, for multi-word phrases and paths
# that have no code-span or table home.
doc_has() {
  grep -qF -- "$1" "$DOC" || fail "${2:-doc_has} (doc does not contain '$1')"
}

# table_col1 <header-line>: the backticked first cells of the table introduced
# by that exact header row, so an enum can be compared as a SET rather than
# only searched for. Stops at the first blank line after the header.
table_col1() {
  awk -v hdr="$1" '
    index($0, hdr) == 1 { intbl = 1; next }
    intbl && /^$/ { exit }
    intbl && match($0, /^\| `[^`]+`/) {
      cell = substr($0, RSTART + 3, RLENGTH - 3)
      sub(/`$/, "", cell)
      print cell
    }
  ' "$DOC"
}

# count <words>: how many whitespace-separated tokens. Splitting is the point;
# globbing is not, so pathname expansion is off across the split.
count() {
  set -f
  # shellcheck disable=SC2086 # deliberate word splitting: this counts tokens
  set -- $1
  set +f
  echo $#
}

# --- 1. the doc, and every source this suite parses, are readable -----------

if [ ! -r "$DOC" ]; then
  echo "FAIL: 1: docs/allocation.md is missing or unreadable" >&2
  echo "$(basename "$0"): 1 failure(s)" >&2
  exit 1
fi

begin
for f in "$LEDGER" "$LADDER" "$PETITION" "$ADAPT" "$GATE" "$CONFIG" \
  "$FLEET_DOC" "$README" "$REFERENCE"; do
  [ -r "$f" ] || fail "1: source '$f' is missing or unreadable — every tether below reads it"
done
section_ok "the doc and every tethered source are readable"

# --- 2. the ledger schema, by name and IN ORDER ----------------------------

# The pinned 15-field schema is documented in allocation-ledger.sh's header as
# numbered `#  <n> <field>` lines. An operator reading a raw row needs the field
# ORDER, not just the names, so the doc's own schema table is compared as an
# ordered sequence.
begin
code_fields=$(sed -n 's/^#[[:space:]]*[0-9][0-9]*[[:space:]]\{1,\}\([a-z_][a-z_]*\)[[:space:]].*$/\1/p' "$LEDGER")
# shellcheck disable=SC2016 # a sed script, not a shell expansion
doc_fields=$(sed -n 's/^| *[0-9][0-9]* | `\([a-z_]*\)` |.*/\1/p' "$DOC")
n_code=$(count "$code_fields")
[ "$n_code" -eq 15 ] || fail "2a: expected the 15-field pinned schema in allocation-ledger.sh, parsed $n_code"
if [ "$code_fields" != "$doc_fields" ]; then
  fail "2b: the doc's schema table does not match the pinned schema, in order
   code: $(printf '%s' "$code_fields" | tr '\n' ' ')
    doc: $(printf '%s' "$doc_fields" | tr '\n' ' ')"
fi
section_ok "the doc's schema table matches the pinned 15-field schema, in order"

# --- 3. the outcome vocabulary, both directions ----------------------------

begin
outcomes=$(sed -n "s/^ALLOC_OUTCOMES='\([^']*\)'.*/\1/p" "$LEDGER")
n_out=$(count "$outcomes")
[ "$n_out" -eq 9 ] || fail "3a: expected 9 ledger outcomes, parsed $n_out — the enum moved"
for o in $outcomes; do
  doc_cell "$o" "3b: ledger outcome '$o' has no row in the doc's outcome table"
done
doc_outcomes=$(table_col1 '| Outcome | Meaning |' | tr '\n' ' ')
for d in $doc_outcomes; do
  case " $outcomes " in
    *" $d "*) ;;
    *) fail "3c: the doc's outcome table lists '$d', which the code does not emit" ;;
  esac
done
section_ok "the doc's outcome table and the code's outcome enum agree, both ways"

# --- 4. the scope vocabulary ------------------------------------------------

begin
scopes=$(sed -n "s/^ALLOC_SCOPES='\([^']*\)'.*/\1/p" "$LEDGER")
n_sc=$(count "$scopes")
[ "$n_sc" -eq 2 ] || fail "4a: expected 2 ledger scopes, parsed $n_sc"
for s in $scopes; do
  doc_code "$s" "4b: ledger scope '$s' undocumented"
done
section_ok "both ledger scopes are documented"

# --- 5. the event-class vocabulary -----------------------------------------

# The trigger set is a closed allowlist; the doc must not describe a set the
# code does not implement, nor omit one it does. The moving classes have a
# table; the inert ones the doc lists in prose.
begin
ev_up=$(sed -n "s/^ALLOC_EVENTS_UP='\([^']*\)'.*/\1/p" "$LADDER")
ev_down=$(sed -n "s/^ALLOC_EVENTS_DOWN='\([^']*\)'.*/\1/p" "$LADDER")
ev_inert=$(sed -n "s/^ALLOC_EVENTS_INERT='\([^']*\)'.*/\1/p" "$LADDER")
n_ev=$(count "$ev_up $ev_down $ev_inert")
[ "$n_ev" -eq 12 ] || fail "5a: expected 12 event classes, parsed $n_ev — the ladder's enums moved"
for e in $ev_up $ev_down; do
  doc_cell "$e" "5b: moving event class '$e' has no row in the doc's event table"
done
for e in $ev_inert; do
  doc_code "$e" "5c: inert event class '$e' undocumented"
done
section_ok "every event class the ladder accepts is documented ($n_ev classes)"

# --- 6. the ladder ORDERS, not merely their members ------------------------

# The model ladder's order is the fact operators get wrong, so the doc must
# carry the aliases in the shipped cheap-to-expensive order.
begin
models=$(sed -n "s/^ALLOC_MODELS='\([^']*\)'.*/\1/p" "$LADDER")
efforts=$(sed -n "s/^ALLOC_EFFORTS='\([^']*\)'.*/\1/p" "$LADDER")
[ "$(count "$models")" -eq 4 ] || fail "6a: expected 4 model aliases, parsed $(count "$models")"
[ "$(count "$efforts")" -eq 3 ] || fail "6b: expected 3 effort levels, parsed $(count "$efforts")"
doc_has "$(printf '%s\n' "$models" | sed 's/ / < /g')" \
  "6c: the model ladder order is not stated as the code orders it"
doc_has "$(printf '%s\n' "$efforts" | sed 's/ / < /g')" \
  "6d: the effort ladder order is not stated as the code orders it"
section_ok "the doc states both ladder orders exactly as the code orders them"

# --- 7. shipped defaults, tethered to config/defaults.yml ------------------

# config_default <knob>: the shipped value, with trailing whitespace stripped
# BEFORE the quote strip (a trailing space would otherwise leave a stray quote).
config_default() {
  sed -n "s/^$1:[[:space:]]*//p" "$CONFIG" | sed 's/[[:space:]]*$//; s/^"//; s/"$//'
}

begin
for knob in allocation_adaptation allocation_adjustment_cap allocation_petition \
  allocation_feedback_threshold; do
  d=$(config_default "$knob")
  [ -n "$d" ] || fail "7a: $knob has no default in config/defaults.yml"
  grep -qF -- "| \`$knob\` | \`$d\` |" "$DOC" \
    || fail "7b: $knob's shipped default (\`$d\`) is not restated in the doc's knob table"
done
section_ok "every adaptation knob's shipped default is tethered to config/defaults.yml"

# The starting-tier table is what an operator reads to know what they run
# TODAY, and those values come from the legacy family.
begin
for key in execution bookkeeping drain; do
  m=$(config_default "fleet_model_$key")
  e=$(config_default "fleet_effort_$key")
  [ -n "$m" ] && [ -n "$e" ] || fail "7c: fleet_{model,effort}_$key missing from config/defaults.yml"
  grep -qF -- "| \`$key\` | \`$m\` | \`$e\` |" "$DOC" \
    || fail "7d: the shipped starting tier for '$key' (\`$m\`/\`$e\`) is not in the doc's table"
done
section_ok "the shipped starting-tier table is tethered to config/defaults.yml"

# The worked clamp example's arithmetic (fable withdrawn at 58, opus surviving)
# depends on these two thresholds; the doc quotes them, so tether them.
begin
for tier in fable opus; do
  c=$(config_default "fleet_cap_$tier")
  if [ -z "$c" ]; then
    fail "7e: fleet_cap_$tier missing from config/defaults.yml"
  elif ! grep -qF -- "\`$tier\` cap threshold is \`$c\`" "$DOC"; then
    fail "7f: the doc does not state the \`$tier\` cap threshold as \`$c\`, which its worked clamp example depends on"
  fi
done
section_ok "the per-tier cap thresholds the clamp example depends on are tethered"

# --- 8. the fallback precedence and both sentinels -------------------------

begin
grep -q '^allocation_model_execution: unset' "$CONFIG" \
  || fail "8a: the fleet-keyed general knobs no longer ship 'unset' — the doc's fallback story moved"
grep -q '^allocation_model_offload: inherit' "$CONFIG" \
  || fail "8b: the non-fleet surfaces no longer ship 'inherit' — the doc's opt-in story moved"
doc_code 'unset' "8c: the doc does not name the 'unset' sentinel that arms the fleet_* fallback"
doc_code 'inherit' "8d: the doc does not name the 'inherit' sentinel"
doc_code 'fleet_model_execution' "8e: the doc does not name a legacy fallback knob"
grep -qi 'deprecated fallback' "$DOC" \
  || fail "8f: the doc does not call the fleet_* family a deprecated fallback"
section_ok "the doc carries the fallback precedence and both sentinels"

# --- 9. the selection keys --------------------------------------------------

begin
keys=$(sed -n 's/^KEYS="\([^"]*\)".*/\1/p' "$root/scripts/allocation-select.sh")
[ -n "$keys" ] || fail "9a: KEYS not parsed out of allocation-select.sh"
[ "$(count "$keys")" -eq 6 ] || fail "9b: expected 6 selection keys, parsed $(count "$keys")"
for k in $keys; do
  doc_cell "$k" "9c: selection key '$k' has no row in the doc's key table"
done
section_ok "every selection key is documented ($(count "$keys") keys)"

# --- 10. the per-step knobs are named, not just alluded to -----------------

begin
step_knobs=$(sed -n 's/^\(allocation_[a-z]*_step_[a-z_]*\):.*/\1/p' "$CONFIG")
n_step=$(count "$step_knobs")
[ "$n_step" -eq 6 ] || fail "10a: expected 6 per-step knobs in config/defaults.yml, parsed $n_step"
for k in $step_knobs; do
  doc_has "$k" "10b: per-step knob '$k' is not named in the doc"
done
section_ok "every shipped per-step knob is named in the doc ($n_step knobs)"

# --- 11. the restriction rungs, in order -----------------------------------

# `rung=` appears in the doc's worked rows; a reader who cannot map its values
# has to leave the page. Order matters (it is a ladder), so the whole chain is
# compared, with the source's ASCII arrows normalised to the doc's.
begin
n_rung_lines=$(grep -c -- 'normal -> downshift' "$GATE")
[ "$n_rung_lines" -eq 1 ] \
  || fail "11a: expected exactly 1 rung-ladder line in fleet-usage-gate.sh, found $n_rung_lines"
rung_chain=$(grep -m1 -- 'normal -> downshift' "$GATE" \
  | sed 's/^#[[:space:]]*//; s/[[:space:]]*$//')
for rung in normal downshift reduce-concurrency defer-heavy defer-all; do
  case $rung_chain in
    *"$rung"*) ;;
    *) fail "11b: '$rung' is no longer on the upstream rung ladder" ;;
  esac
  doc_code "$rung" "11c: restriction rung '$rung' undocumented"
done
doc_rendered=$(printf '%s\n' "$rung_chain" \
  | sed 's/#//g; s/^ *//; s/ *$//' \
  | awk '{ for (i = 1; i <= NF; i++) if ($i != "->") printf "%s`%s`", (i > 1 ? " → " : ""), $i; print "" }')
doc_has "$doc_rendered" "11d: the doc does not state the rung ladder in upstream order"
section_ok "every restriction rung is documented, in ladder order"

# --- 12. the clamp vocabulary, both directions -----------------------------

# A clamp is NOT an outcome — it is read off the `clamps=` member of a launch
# row's `inputs`. A doc presenting it as an outcome would send an operator down
# the wrong column, which is the "answerable without reading source" failure
# this suite exists to prevent.
begin
doc_code 'clamps=' "12a: the doc does not name the inputs key a clamp is read from"
clamp_tokens='none defer-all defer-heavy downshift cap reserved-exempt'
for tok in defer-all defer-heavy downshift cap reserved-exempt; do
  grep -qF -- "$tok," "$ADAPT" || fail "12b: '$tok' is no longer a clamp token in allocation-adapt.sh"
done
grep -qF -- 'CL_CLAMPS=none' "$ADAPT" || fail "12c: the 'none' clamp sentinel moved in allocation-adapt.sh"
for tok in $clamp_tokens; do
  doc_cell "$tok" "12d: clamp token '$tok' has no row in the doc's clamp table"
done
doc_clamps=$(table_col1 '| Token | What bound |' | tr '\n' ' ')
for d in $doc_clamps; do
  case " $clamp_tokens " in
    *" $d "*) ;;
    *) fail "12e: the doc's clamp table lists '$d', which the engine does not write" ;;
  esac
done
section_ok "the clamp vocabulary agrees with the engine, both ways"

# --- 13. the ledger row `inputs` keys --------------------------------------

# Parsed from the engine's own record/append call sites rather than transcribed
# from the doc, so a key the doc never explains is a failure here.
begin
# The `inputs` column is built as a `;`-joined `k=v` string literal, so the keys
# are harvested from double-quoted literals carrying both an `=` and a `;` —
# not from every shell assignment in the file, which would sweep up locals.
input_keys=$(grep -ho '"[^"]*=[^"]*;[^"]*"' "$ADAPT" "$root/scripts/allocation-apply.sh" \
  | grep -oE '[a-z_][a-z_-]*=' | sort -u)
[ -n "$input_keys" ] || fail "13a: no inputs keys parsed out of the engine"
n_ik=$(count "$input_keys")
[ "$n_ik" -ge 10 ] || fail "13b: only $n_ik inputs keys parsed — the engine's inputs strings moved"
for k in $input_keys; do
  doc_code "$k" "13c: ledger inputs key '$k' is not explained in the doc"
done
section_ok "every ledger inputs key the engine writes is explained in the doc"

# --- 14. the resolver's output fields --------------------------------------

begin
resolve_fields=$(sed -n "s/^[[:space:]]*printf '\([a-z_]*\)\\\\t%s\\\\n'.*/\1/p" "$ADAPT" | sort -u)
n_rf=$(count "$resolve_fields")
[ "$n_rf" -ge 14 ] || fail "14a: expected at least 14 resolver output fields, parsed $n_rf"
for f in $resolve_fields; do
  doc_code "$f" "14b: resolver output field '$f' undocumented"
done
section_ok "the resolver's output fields are documented ($n_rf fields)"

# --- 15. the pinned petition path and its refusal details ------------------

begin
sub=$(sed -n 's/^PET_SUBDIR=\(.*\)$/\1/p' "$PETITION")
name=$(sed -n 's/^PET_NAME=\(.*\)$/\1/p' "$PETITION")
if [ -n "$sub" ] && [ -n "$name" ]; then
  doc_has "$sub/$name" "15a: the pinned petition path is not documented"
else
  fail "15b: PET_SUBDIR/PET_NAME not parsed out of allocation-petition.sh"
fi
# Staleness is wrong UNIT or STEP — not attempt — and the refusal details are
# what an operator reads off an ignored row.
for detail in grammar empty oversize control-bytes torn symlink not-regular; do
  grep -qF -- "$detail" "$PETITION" || fail "15c: '$detail' is no longer a refusal detail in the script"
  doc_code "$detail" "15d: petition refusal detail '$detail' undocumented"
done
# Staleness is wrong unit or step — NOT attempt — and the doc states each as the
# `reason=` value an operator reads off the ignored row.
for detail in stale-unit stale-step; do
  grep -qF -- "$detail" "$PETITION" || fail "15e: '$detail' is no longer a refusal detail in the script"
  doc_has "reason=$detail" "15f: petition staleness detail '$detail' is not documented as a reason= value"
done
section_ok "the pinned petition path and every refusal detail are documented"

# --- 16. REQ-B1.3 — the in-session rung's inheritance, stated --------------

# test-spec.md: "verified by a content check that the Task 7 doc states it (not
# existence alone)". The rung inherits the session's model, and that is its
# PINNED DEGRADATION, not an incidental gap.
begin
grep -qi 'in-session' "$DOC" || fail "16a: the doc does not name the in-session rung"
grep -qi 'pinned degradation' "$DOC" \
  || fail "16b: the doc does not state the in-session rung's inheritance as its pinned degradation"
doc_code 'tier_control' "16c: the doc does not name the capability column that decides what is applied"
section_ok "REQ-B1.3 — the in-session inheritance degradation is stated"

# --- 17. REQ-C1.7 — single consumption, and no worktree no channel ---------

# Asserting the CLAIM, not a word stem: a bare `consum` match is satisfied by
# "this policy consumes the usage signal" elsewhere in the doc, which would let
# the whole lifecycle section be deleted with the test still green.
begin
grep -qi 'weighing consumes it' "$DOC" \
  || fail "17a: the doc does not state that weighing consumes the petition"
grep -qi 'at most one rung' "$DOC" \
  || fail "17b: the doc does not state that one petition moves the tier at most once"
doc_code 'orphaned-claim' "17c: the doc does not explain the orphaned-claim reconciliation"
grep -qi 'no petition channel' "$DOC" \
  || fail "17d: the doc does not state that rungs without a worktree have no petition channel"
section_ok "REQ-C1.7 — single consumption and the no-worktree degradation are stated"

# --- 18. every Done-when question has a named section ----------------------

begin
while IFS= read -r heading; do
  grep -qF -- "$heading" "$DOC" || fail "18: the doc has no '$heading' section"
done <<'EOF'
## The knob family, and how `fleet_*` fits
## Turning it on
## The ladder: how a tier moves
## Capping how far a unit may travel
## Reading the ledger
## The worker petition
## The feedback loop
## Why the escalation path is fixed
EOF
section_ok "every question in the Done-when contract has a named section"

# --- 19. cross-links, both directions --------------------------------------

begin
grep -qF '](allocation.md' "$FLEET_DOC" || fail "19a: docs/fleet.md does not link to the allocation guide"
grep -qF '](docs/allocation.md' "$README" || fail "19b: README.md does not link to the allocation guide"
grep -qF '](allocation.md' "$REFERENCE" \
  || fail "19c: docs/options-reference.md does not link to the allocation guide"
doc_has '](fleet.md' "19d: the allocation guide does not link back to the fleet doc"
doc_has '](options-reference.md' "19e: the allocation guide does not link to the options reference"
doc_has '](overlays.md' "19f: the allocation guide does not link to the overlay model"
section_ok "the guide is cross-linked with fleet, options-reference, overlays, and the README"

# --- 20. every ledger row the doc shows carries all 15 fields --------------

# The likeliest rot of all: the schema changes and the worked examples are left
# behind. A row is recognised by its leading sequence number inside a fence.
begin
rows_checked=0
while IFS= read -r line; do
  rows_checked=$((rows_checked + 1))
  n=$(count "$line")
  [ "$n" -eq 15 ] || fail "20a: a worked ledger row in the doc has $n fields, want 15: $line"
done <<EOF
$(sed -n 's/^ *\([0-9][0-9]* \.\.\. .*\)$/\1/p' "$DOC")
EOF
[ "$rows_checked" -ge 3 ] || fail "20b: expected at least 3 worked ledger rows in the doc, found $rows_checked"
section_ok "every worked ledger row in the doc carries all 15 fields ($rows_checked rows)"

# --- 21. the wiring claims track the tree in both directions ---------------

# The doc states that nothing passes a step type. That becomes a lie the moment
# a caller lands, and the options reference already rotted this exact way once,
# so a caller appearing forces the doc edit. The feedback evaluation is the
# other side of the same rule: it now HAS callers and the doc describes them, so
# the rot to catch is the reverse — the wiring going away, or the doc dropping
# the bound that keeps the `disabled` arm from reading as routine.
begin
# Comment lines are excluded: both scripts are referred to by name in sibling
# header prose, which is documentation, not a call site.
live_refs() {
  grep -rn -- "$1" "$root/scripts" "$root/skills" "$root/hooks" 2>/dev/null \
    | grep -v ':[[:space:]]*#' \
    | grep -v "$2" \
    | cut -d: -f1 | sort -u | tr '\n' ' '
}
step_callers=$(live_refs '--step-type' 'allocation-adapt\.sh:')
if [ -n "$step_callers" ]; then
  fail "21a: something now passes --step-type ($step_callers) — docs/allocation.md still says nothing does"
fi
grep -qi 'not yet wired to a caller' "$DOC" \
  || fail "21b: the doc no longer states the unwired posture the --step-type guard protects"

fb_callers=$(live_refs 'allocation-feedback\.sh' 'allocation-feedback\.sh:')
if [ -z "$fb_callers" ]; then
  fail "21c: nothing invokes allocation-feedback.sh — docs/allocation.md describes a wired feedback loop"
fi
doc_has 'crash-record' "21d: the doc does not name the command that reports the disabled terminal state"
doc_has 'conditionally reachable' "21e: the doc no longer bounds the disabled arm's reachability"
section_ok "the --step-type claim still holds and the wired feedback half matches the tree"

# --- 22. the repo's own doc guards pass over the touched files -------------

# `Done when:` requires the doc-link checks to pass; REQ-E1.2 is the
# options-reference rule, so that guard runs here too rather than only in CI.
begin
out=$(/bin/bash "$root/scripts/check-doc-links.sh" "$DOC" "$FLEET_DOC" "$README" "$REFERENCE" 2>&1)
rc=$?
case $rc in
  0) ;;
  1) fail "22a: check-doc-links reports a broken link or anchor:
$out" ;;
  *) fail "22b: check-doc-links itself failed (exit $rc), so links went unverified:
$out" ;;
esac
out=$(/bin/bash "$root/scripts/check-options-reference.sh" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "22c: check-options-reference failed (exit $rc) — REQ-E1.2:
$out"
section_ok "the doc-link and options-reference guards pass over the touched docs"

# --- 23. the shipped posture is stated as changing nothing ----------------

# D-13 is the fact most easily lost in an operator doc: the mechanism ships
# dark. A doc reading as though adaptation were on would misprice every
# reader's expectations.
begin
grep -qiE 'ships dark|changes nothing|no behaviour change|no behavior change' "$DOC" \
  || fail "23: the doc does not state that the shipped defaults change nothing"
section_ok "the doc states the opt-in, default-preserving posture"

# --- result ----------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
  echo "$(basename "$0"): $failures failure(s)" >&2
  exit 1
fi
echo "all allocation-docs tests passed"
