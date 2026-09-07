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
# failure that must fail CI rather than rot silently. Nothing here asserts a
# sentence the doc's author is free to word; everything asserted is a fact the
# code owns.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-docs.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root="$here/.."
DOC="$root/docs/allocation.md"
LEDGER="$root/scripts/allocation-ledger.sh"
LADDER="$root/scripts/allocation-ladder.sh"
PETITION="$root/scripts/allocation-petition.sh"
CONFIG="$root/config/defaults.yml"
FLEET_DOC="$root/docs/fleet.md"
README="$root/README.md"
REFERENCE="$root/docs/options-reference.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# doc_has <needle> <label>: the doc names a fixed string the code owns.
doc_has() {
  grep -qF -- "$1" "$DOC" || fail "$2 (doc does not name '$1')"
}

# --- 1. the doc exists at all ----------------------------------------------

if [ ! -r "$DOC" ]; then
  echo "FAIL: 1: docs/allocation.md is missing or unreadable" >&2
  echo "$(basename "$0"): 1 failure" >&2
  exit 1
fi
echo "ok: docs/allocation.md exists"

# --- 2. the ledger schema tether -------------------------------------------

# The pinned 15-field schema is documented in allocation-ledger.sh's header as
# numbered `#  <n> <field>` lines. An operator reading a raw row needs every
# field name, so every one the script pins must appear in the doc.
schema_fields=$(sed -n 's/^#[[:space:]]*[0-9][0-9]*[[:space:]]\{1,\}\([a-z_][a-z_]*\)[[:space:]].*$/\1/p' "$LEDGER")
[ -n "$schema_fields" ] || fail "2a: no ledger schema fields parsed out of allocation-ledger.sh"

n_fields=0
for f in $schema_fields; do
  n_fields=$((n_fields + 1))
  doc_has "$f" "2b: ledger schema field '$f' undocumented"
done
[ "$n_fields" -eq 15 ] || fail "2c: expected the 15-field pinned schema, parsed $n_fields"
echo "ok: every pinned ledger schema field is named in the doc ($n_fields fields)"

# --- 3. the outcome and scope enum tether ----------------------------------

# `outcome` is the column an operator reads to answer "what did this row do";
# every legal value must be explained somewhere in the doc.
outcomes=$(sed -n "s/^ALLOC_OUTCOMES='\([^']*\)'.*/\1/p" "$LEDGER")
[ -n "$outcomes" ] || fail "3a: ALLOC_OUTCOMES not parsed out of allocation-ledger.sh"
for o in $outcomes; do
  doc_has "$o" "3b: ledger outcome '$o' undocumented"
done

scopes=$(sed -n "s/^ALLOC_SCOPES='\([^']*\)'.*/\1/p" "$LEDGER")
[ -n "$scopes" ] || fail "3c: ALLOC_SCOPES not parsed out of allocation-ledger.sh"
for s in $scopes; do
  doc_has "$s" "3d: ledger scope '$s' undocumented"
done
echo "ok: every ledger outcome and scope value is named in the doc"

# --- 4. the event-class tether ---------------------------------------------

# The trigger set is a closed allowlist; the doc must not describe a set the
# code does not implement, nor omit one it does.
events=""
for v in ALLOC_EVENTS_UP ALLOC_EVENTS_DOWN ALLOC_EVENTS_INERT; do
  got=$(sed -n "s/^$v='\([^']*\)'.*/\1/p" "$LADDER")
  [ -n "$got" ] || fail "4a: $v not parsed out of allocation-ladder.sh"
  events="$events $got"
done
for e in $events; do
  doc_has "$e" "4b: event class '$e' undocumented"
done
echo "ok: every event class the ladder accepts is named in the doc"

# --- 5. the ladder tether ---------------------------------------------------

# The model ladder's ORDER is the fact operators get wrong, so the doc must
# carry the aliases in the shipped cheap-to-expensive order, not merely mention
# them. The same for the effort enum.
models=$(sed -n "s/^ALLOC_MODELS='\([^']*\)'.*/\1/p" "$LADDER")
efforts=$(sed -n "s/^ALLOC_EFFORTS='\([^']*\)'.*/\1/p" "$LADDER")
[ -n "$models" ] || fail "5a: ALLOC_MODELS not parsed out of allocation-ladder.sh"
[ -n "$efforts" ] || fail "5b: ALLOC_EFFORTS not parsed out of allocation-ladder.sh"

# `haiku sonnet opus fable` -> the `haiku < sonnet < opus < fable` the doc pins.
ladder_order=$(printf '%s\n' "$models" | sed 's/ / < /g')
effort_order=$(printf '%s\n' "$efforts" | sed 's/ / < /g')
doc_has "$ladder_order" "5c: the model ladder order is not stated as the code orders it"
doc_has "$effort_order" "5d: the effort ladder order is not stated as the code orders it"
echo "ok: the doc states both ladder orders exactly as the code orders them"

# --- 6. the adaptation knobs and their shipped defaults --------------------

# The same tether shape check-options-reference.sh applies to docs/fleet.md: a
# default changed in config without the doc edit must fail. The doc restates
# each in a `| `knob` | `default` |` row.
for knob in allocation_adaptation allocation_adjustment_cap allocation_petition \
  allocation_feedback_threshold; do
  default=$(sed -n "s/^$knob:[[:space:]]*//p" "$CONFIG" | sed 's/^"//; s/"$//; s/[[:space:]]*$//')
  [ -n "$default" ] || fail "6a: $knob has no default in config/defaults.yml"
  doc_has "| \`$knob\` | \`$default\` |" "6b: $knob's shipped default is not restated in the doc"
done
echo "ok: every adaptation knob's shipped default is tethered to config/defaults.yml"

# --- 7. the fallback and opt-in sentinels ----------------------------------

# Q6 of the doc's contract: how `fleet_*` relates to `allocation_*`. The two
# sentinels are what make the answer concrete, and both are config values.
grep -q '^allocation_model_execution: unset' "$CONFIG" \
  || fail "7a: the fleet-keyed general knobs no longer ship 'unset' — the doc's fallback story moved"
grep -q '^allocation_model_offload: inherit' "$CONFIG" \
  || fail "7b: the non-fleet surfaces no longer ship 'inherit' — the doc's opt-in story moved"
doc_has 'unset' "7c: the doc does not name the 'unset' sentinel that arms the fleet_* fallback"
doc_has 'inherit' "7d: the doc does not name the 'inherit' sentinel"
doc_has 'fleet_model_execution' "7e: the doc does not name a legacy fallback knob"
grep -qi 'deprecated fallback' "$DOC" \
  || fail "7f: the doc does not call the fleet_* family a deprecated fallback"
echo "ok: the doc carries the fallback precedence and both sentinels"

# --- 8. the petition artifact path -----------------------------------------

# The worker-facing path is pinned in the script; a doc naming a different one
# sends every worker's petition into the void.
sub=$(sed -n 's/^PET_SUBDIR=\(.*\)$/\1/p' "$PETITION")
name=$(sed -n 's/^PET_NAME=\(.*\)$/\1/p' "$PETITION")
[ -n "$sub" ] || fail "8a: PET_SUBDIR not parsed out of allocation-petition.sh"
[ -n "$name" ] || fail "8b: PET_NAME not parsed out of allocation-petition.sh"
doc_has "$sub/$name" "8c: the pinned petition path is not documented"

# Staleness is wrong UNIT or STEP — not attempt — and the two refusal details
# are what an operator reads off an ignored row.
for detail in stale-unit stale-step; do
  grep -qF -- "$detail" "$PETITION" || fail "8d: '$detail' is no longer a refusal detail in the script"
  doc_has "$detail" "8e: refusal detail '$detail' undocumented"
done
echo "ok: the pinned petition path and its staleness details are documented"

# --- 7g. the per-step knobs are named, not just alluded to ------------------

# The doc spends a prerequisite paragraph on per-step tiers. A reader cannot act
# on it without the knob names, so every step knob core ships must appear.
step_knobs=$(sed -n 's/^\(allocation_[a-z]*_step_[a-z_]*\):.*/\1/p' "$CONFIG")
[ -n "$step_knobs" ] || fail "7g: no per-step knobs parsed out of config/defaults.yml"
for k in $step_knobs; do
  doc_has "$k" "7h: per-step knob '$k' is not named in the doc"
done
echo "ok: every shipped per-step knob is named in the doc"

# --- 7i. the restriction rungs the ledger's `rung=` field can carry ---------

# `rung=` appears in the doc's own worked rows; a reader who cannot map its
# values has to leave the page. The ladder is the upstream gate's, so tether to
# it rather than restating it independently.
rung_line=$(grep -m1 -- 'normal -> downshift' "$root/scripts/fleet-usage-gate.sh") \
  || fail "7i: the restriction-rung ladder is no longer stated in fleet-usage-gate.sh"
for rung in normal downshift reduce-concurrency defer-heavy defer-all; do
  case $rung_line in
    *"$rung"*) ;;
    *) fail "7j: '$rung' is no longer on the upstream rung ladder" ;;
  esac
  doc_has "$rung" "7k: restriction rung '$rung' undocumented"
done
echo "ok: every restriction rung the ledger can name is documented"

# --- 8f. the clamp vocabulary ----------------------------------------------

# A clamp is NOT an outcome value — it is read off the `clamps=` member of a
# launch row's `inputs` column. A doc that presented it as an outcome would send
# an operator looking down the wrong column, which is precisely the "answerable
# without reading source" failure this suite exists to prevent. So the doc must
# name the key and every member token the engine can write.
doc_has 'clamps=' "8f: the doc does not name the inputs key a clamp is read from"
for tok in defer-all defer-heavy downshift cap reserved-exempt; do
  grep -qF -- "$tok," "$root/scripts/allocation-adapt.sh" \
    || fail "8g: '$tok' is no longer a clamp token in allocation-adapt.sh"
  doc_has "$tok" "8h: clamp token '$tok' undocumented"
done

# The other members of a launch row's `inputs` an operator reads.
for key in 'key=' 'rung=' 'signal=' 'adaptation=' 'trigger='; do
  doc_has "$key" "8i: the doc does not name the '$key' input a ledger row carries"
done
echo "ok: the clamp vocabulary and the launch row's inputs keys are documented"

# --- 8j. the resolver's output fields --------------------------------------

# The doc enumerates what `allocation-adapt.sh resolve` prints so a reader can
# parse it. Those field names are emitted by the engine, so tether them.
resolve_fields=$(sed -n "s/^[[:space:]]*printf '\([a-z_]*\)\\\\t%s\\\\n'.*/\1/p" \
  "$root/scripts/allocation-adapt.sh" | sort -u)
[ -n "$resolve_fields" ] || fail "8j: no resolve output fields parsed out of allocation-adapt.sh"
for f in $resolve_fields; do
  doc_has "$f" "8k: resolver output field '$f' undocumented"
done
echo "ok: the resolver's output fields are documented"

# --- 9. REQ-B1.3 — the in-session rung's inheritance, stated ---------------

# test-spec.md: "verified by a content check that the Task 7 doc states it (not
# existence alone)". The rung inherits the session's model, and that inheritance
# is its PINNED DEGRADATION, not an incidental gap.
grep -qi 'in-session' "$DOC" || fail "9a: the doc does not name the in-session rung"
grep -qi 'pinned degradation' "$DOC" \
  || fail "9b: the doc does not state the in-session rung's inheritance as its pinned degradation"
grep -qi 'tier_control' "$DOC" \
  || fail "9c: the doc does not name the capability column that decides what is applied"
echo "ok: REQ-B1.3 — the in-session inheritance degradation is stated"

# --- 10. REQ-C1.7 — no worktree, no petition channel ----------------------

grep -qi 'no petition channel' "$DOC" \
  || fail "10a: the doc does not state that rungs without a worktree have no petition channel"
grep -qi 'consum' "$DOC" \
  || fail "10b: the doc does not state the single-consumption lifecycle"
echo "ok: REQ-C1.7 — single consumption and the no-worktree degradation are stated"

# --- 11. the six questions have a home ------------------------------------

# `Done when:` pins six questions the doc must answer without source. Each has a
# named section, so a reader can find it and a later edit cannot quietly drop
# one.
for heading in \
  'Turning it on' \
  'The ladder' \
  'Capping how far' \
  'Reading the ledger' \
  'The worker petition' \
  'The feedback loop' \
  'Why the escalation path is fixed'; do
  grep -q "^## .*$heading" "$DOC" || fail "11: the doc has no '## ... $heading' section"
done
echo "ok: every question in the Done-when contract has a named section"

# --- 12. cross-links, both directions -------------------------------------

grep -qF '](allocation.md' "$FLEET_DOC" || fail "12a: docs/fleet.md does not link to the allocation guide"
grep -qF '](docs/allocation.md' "$README" || fail "12b: README.md does not link to the allocation guide"
grep -qF '](allocation.md' "$REFERENCE" \
  || fail "12c: docs/options-reference.md does not link to the allocation guide"
doc_has '](fleet.md' "12d: the allocation guide does not link back to the fleet doc"
doc_has '](options-reference.md' "12e: the allocation guide does not link to the options reference"
doc_has '](overlays.md' "12f: the allocation guide does not link to the overlay model"
echo "ok: the guide is cross-linked with fleet, options-reference, overlays, and the README"

# --- 13. every link and anchor in the new doc resolves ---------------------

# `Done when:` requires the doc-link checks to pass; running the checker over
# the touched files makes that this suite's business too, not only CI's.
if ! out=$(/bin/bash "$root/scripts/check-doc-links.sh" "$DOC" "$FLEET_DOC" "$README" "$REFERENCE" 2>&1); then
  fail "13: check-doc-links failed over the touched docs: $out"
fi
echo "ok: every link and anchor in the touched docs resolves"

# --- 14. the shipped posture is stated as changing nothing ----------------

# D-13 is the fact most easily lost in an operator doc: the mechanism ships
# dark. A doc that reads as though adaptation were on would misprice every
# reader's expectations.
grep -qi 'ships dark\|changes nothing\|no behaviour change\|no behavior change' "$DOC" \
  || fail "14: the doc does not state that the shipped defaults change nothing"
echo "ok: the doc states the opt-in, default-preserving posture"

# --- result ----------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
  echo "$(basename "$0"): $failures failure(s)" >&2
  exit 1
fi
echo "all allocation-docs tests passed"
