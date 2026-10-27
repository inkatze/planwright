#!/bin/bash
# Tests for scripts/mc-proposals.sh — the repeat detector over the decisions
# log and the mechanization proposal record: a repeat at the threshold mapped
# onto the smallest covering row of the mechanism inventory, in the
# confirmation shape, with its accepted, declined and parked outcomes and a
# settings-kind change handed over, never written (mission-control REQ-B1.5,
# REQ-C1.7, REQ-G1.4, REQ-K1.7).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-proposals.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-proposals.sh" ] || {
  echo "FAIL: scripts/mc-proposals.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-autonomy-fixture.sh
. "$here/lib/mc-autonomy-fixture.sh"

tab=$(printf '\t')
prop() { mc_run mc-proposals.sh "$@"; }
note() { mc_run mc-decide.sh note --program alpha "$@"; }
field() { printf '%s\n' "$1" | cut -f "$2"; }
# pattern_of <subject>: the pattern id scan printed for a subject.
pattern_of() { printf '%s\n' "$OUT" | awk -F '\t' -v s="$1" '$1 == "repeat" && $4 == s { print $2 }'; }

settings="$tmp/claude/settings.json"
printf '{"permissions": {"allow": ["Bash(git status)"]}}\n' >"$settings"
{
  printf '# format: 1\n# refreshed: 1\n# kind\tmechanism\twhere\tsource\n'
  printf 'catalog-step\tpolish\tthe core steps catalog\tscripts/resolve-catalog.sh steps\n'
  printf 'duty\talpha-duty\tthe core duties catalog\tscripts/mc-duties.sh list\n'
  printf 'knob\tmission_control_tick_cadence\tthe config layers\tdocs/options-reference.md\n'
  printf 'permission\tallow: Bash(git status)\t%s\t%s\n' "$settings" "$settings"
  printf 'rule\ta rule-store entry\t%s/rules.yaml\tthe mission-control rule store\n' "$home"
} >"$kb/mechanisms.tsv"
config_sum=$(cksum <"$tracked")$(cksum <"$repo/.claude/catalogs/duties.yaml")

# ---------------------------------------------------------------------------
# REQ-B1.5: two corrections of one shape in the window yield one proposal
# naming a rule entry, in the confirmation shape.
# ---------------------------------------------------------------------------
note --shape correction --subject "Ready flips" --text "stop flipping without the walk"
prop scan --program alpha
expect_rc "scan runs" 0
expect_eq "one correction is not a repeat" ""
note --shape correction --subject "ready  FLIPS" --text "again: walk before the flip"
prop scan --program alpha
expect_out "a second correction on the same subject key is a repeat" "repeat${tab}"
p_flip=$(pattern_of "ready flips")
if [ -n "$p_flip" ]; then ok "the repeat carries its pattern id"; else fail "no pattern for the repeat: $OUT"; fi
expect_out "the repeat counts both entries" "${tab}correction${tab}ready flips${tab}-${tab}2${tab}"

prop propose --program alpha --pattern "$p_flip" \
  --change "walk the readiness check before every ready flip" --cadence "at every ready flip" \
  --intervene "the operator still answers the flip" --cost "none" --off "supersede the rule"
expect_rc "the repeat is proposed" 0
expect_out "a correction maps onto the rule row" "proposal${tab}p-1${tab}rule${tab}a rule-store entry"
prop show --program alpha p-1
expect_rc "the proposal shows" 0
for line in "noticed${tab}correction repeated 2 times: ready flips" "evidence${tab}decisions-" "stop flipping without the walk" \
  "mechanism${tab}rule${tab}a rule-store entry" "change${tab}walk the readiness check" "cadence${tab}at every ready flip" \
  "intervene${tab}the operator still answers" "cost${tab}none" "off${tab}supersede the rule" "decline${tab}"; do
  expect_out "the confirmation shape carries: $line" "$line"
done
prop propose --program alpha --pattern "$p_flip" --change c --cadence c --intervene c --cost c --off c
expect_rc "a pattern already proposed is not proposed again" 1
prop scan --program alpha
expect_rc "scan runs after a proposal" 0
expect_no_out "scan no longer lists a proposed pattern" "ready flips"
prop show --program alpha p-1
expect_no_out "a rule proposal carries no settings handover" "settings${tab}"

# ---------------------------------------------------------------------------
# A manual step a catalog step covers proposes that, not a duty.
# ---------------------------------------------------------------------------
note --shape manual --subject "Polish" --text "ran polish by hand" --target pr-opened
note --shape manual --subject "Polish" --text "ran polish by hand again" --target pr-opened
note --shape manual --subject "Polish" --text "polish after a merge" --target pr-merged
prop scan --program alpha
expect_rc "scan reads the manual steps" 0
expect_out "a manual step after the same event is one pattern of two" "${tab}manual${tab}polish${tab}pr-opened${tab}2${tab}"
expect_no_out "a step after another event is not counted with them" "pr-merged"
p_polish=$(pattern_of polish)
prop propose --program alpha --pattern "$p_polish" --candidate duty:alpha-duty --candidate catalog-step:polish \
  --change "add polish to steps_post_pr" --cadence "after every pull request opens" \
  --intervene "the operator reads the polish record" --cost "one polish session per pull request" --off "drop it from steps_post_pr"
expect_rc "the covered repeat is proposed" 0
expect_out "the smallest covering row wins over a duty" "${tab}catalog-step${tab}polish"
expect_no_out "the duty is not proposed" "alpha-duty"

# ---------------------------------------------------------------------------
# REQ-K1.7: a repeat no inventory row covers raises no proposal.
# ---------------------------------------------------------------------------
note --shape answer --subject "Rebase or merge" --text merge --target merge
note --shape answer --subject "Rebase or merge" --text merge --target merge
prop scan --program alpha
p_ans=$(pattern_of "rebase or merge")
prop propose --program alpha --pattern "$p_ans" --candidate knob:mission_control_sync_style \
  --change c --cadence c --intervene c --cost c --off c
expect_rc "a candidate absent from the inventory is refused" 1
expect_err "the refusal says no row covers it" "no row of the mechanism inventory"
prop list --program alpha
expect_no_out "no proposal was recorded for the uncovered repeat" "rebase or merge"

prop propose --program alpha --pattern "$p_ans" --candidate rule --change c --cadence c --intervene c --cost c
expect_rc "a proposal without its off switch is refused" 2
prop propose --program alpha --pattern pat-00000000000000000000000000000000 --candidate rule --change c --cadence c --intervene c --cost c --off c
expect_rc "a pattern that is not at the threshold is refused" 1

# ---------------------------------------------------------------------------
# REQ-G1.4: a settings-kind proposal is handed over, every settings file kept.
# ---------------------------------------------------------------------------
sum_before=$(cksum <"$settings")
prop propose --program alpha --pattern "$p_ans" --candidate "permission:allow: Bash(git status)" \
  --change "allow git status for every worker" --cadence "every worker prompt" \
  --intervene "the operator applies the rule" --cost "none" --off "remove the allow rule"
expect_rc "a settings-kind repeat is proposed" 0
p_set=$(field "$OUT" 2)
prop show --program alpha "$p_set"
expect_out "the settings-kind proposal says it is never written" "settings${tab}ready to apply, never written: $settings"
prop accept --program alpha "$p_set"
expect_rc "the settings-kind proposal is accepted" 0
expect_out "the change is handed to the operator ready to apply" "handover-operator${tab}$settings${tab}allow git status for every worker"
if [ "$(cksum <"$settings")" = "$sum_before" ]; then ok "the settings file is untouched"; else fail "accepting rewrote the settings file"; fi
for f in "$tmp/claude/settings.local.json" "$repo/.claude/settings.json" "$repo/.claude/settings.local.json"; do
  if [ -e "$f" ]; then fail "accepting wrote $f"; else ok "no settings file created at ${f#"$tmp"/}"; fi
done

# ---------------------------------------------------------------------------
# Outcomes: accepted applies a rule entry; declined is never re-proposed;
# not now parks with a trigger.
# ---------------------------------------------------------------------------
prop accept --program alpha p-1
expect_rc "the rule proposal is accepted" 0
expect_out "an accepted rule proposal is applied to the rule store" "applied${tab}rule${tab}r-"
mc_run mc-rules.sh active alpha
expect_out "the rule is active" "walk the readiness check before every ready flip"
mc_run mc-kb.sh query undo --program alpha --subject "ready flips"
expect_out "the accepted rule's undo entry is logged with its reversal" "${tab}rule-add${tab}r-"
expect_out "the reversal withdraws the rule" "argv:mc-rules.sh"
prop accept --program alpha p-1
expect_rc "a closed proposal is not accepted twice" 1

prop decline --program alpha p-2
expect_rc "a proposal is declined" 0
note --shape manual --subject "Polish" --text "ran polish by hand a third time" --target pr-opened
prop scan --program alpha
expect_rc "scan runs after a decline" 0
expect_no_out "a declined pattern is not raised again" "polish"
prop propose --program alpha --pattern "$p_polish" --candidate catalog-step:polish --change c --cadence c --intervene c --cost c --off c
expect_rc "a declined pattern is not re-proposed" 1
expect_err "the refusal names the decline" "declined"

note --shape correction --subject "Notify" --text "push when a gate fails"
note --shape correction --subject "Notify" --text "push when a gate fails, again"
prop scan --program alpha
p_note=$(pattern_of notify)
prop propose --program alpha --pattern "$p_note" --change "push on a failed gate" --cadence "every gate" \
  --intervene "none" --cost "one notification" --off "supersede the rule"
p_park=$(field "$OUT" 2)
prop park --program alpha "$p_park" --trigger date:2099-01-01
expect_rc "a proposal is parked with a trigger" 0
mc_run mc-kb.sh followup list --program alpha
expect_out "the parking trigger is a follow-up" "date:2099-01-01"
expect_out "the follow-up names the proposal" "$p_park"
prop park --program alpha "$p_park" --trigger soon
expect_rc "a trigger outside the grammar is refused" 2
prop reopen --program alpha "$p_park"
expect_rc "a parked proposal reopens" 0
prop list --program alpha
expect_out "the reopened proposal is open" "$p_park${tab}open"
mc_run mc-kb.sh followup list --program alpha
expect_no_out "reopening closes the parking follow-up" "${tab}open${tab}re-raise mechanization proposal $p_park "
prop reopen --program alpha "$p_park"
expect_rc "only a parked proposal reopens" 1

# Nothing enables itself: no outcome touched the program block or a catalog.
if [ "$(cksum <"$tracked")$(cksum <"$repo/.claude/catalogs/duties.yaml")" = "$config_sum" ]; then
  ok "the program block and the duty catalog are untouched"
else
  fail "a proposal outcome edited the program block or a catalog"
fi

# ---------------------------------------------------------------------------
# A knob beats a duty; a bare kind names a single row; a recurring ask is a
# repeat too.
# ---------------------------------------------------------------------------
printf 'knob\tmission_control_repeat_window\tthe config layers\tdocs/options-reference.md\n' >>"$kb/mechanisms.tsv"
mc_run mc-decide.sh decide --program alpha --route fork --subject "Which base" --act "asked which base" --grounds "two bases"
mc_run mc-decide.sh decide --program alpha --route fork --subject "Which base" --act "asked again" --grounds "two bases"
prop scan --program alpha
expect_out "a recurring ask is a repeat" "${tab}ask${tab}which base${tab}fork${tab}2${tab}"
p_ask=$(pattern_of "which base")
prop propose --program alpha --pattern "$p_ask" --candidate knob --change c --cadence c --intervene c --cost c --off c
expect_rc "a bare kind with several rows is refused" 2
expect_err "the refusal asks for the mechanism" "knob:<mechanism>"
prop propose --program alpha --pattern "$p_ask" --candidate duty:alpha-duty --candidate knob:mission_control_tick_cadence \
  --change "settle the base by the knob" --cadence "every dispatch" --intervene "the operator sets it" --cost "none" --off "unset it"
expect_rc "the ask is proposed" 0
expect_out "a knob wins over a duty" "${tab}knob${tab}mission_control_tick_cadence"
prop show --program alpha "$(field "$OUT" 2)"
expect_out "the ask's confirmation names the reason it reached the operator" "noticed${tab}ask repeated 2 times: which base, by fork"

printf '%s\n' "mission_control_repeat_threshold: 3" >>"$tracked"
note --shape correction --subject "Three times" --text "one"
note --shape correction --subject "Three times" --text "two"
prop scan --program alpha
expect_rc "scan runs under a raised threshold" 0
expect_no_out "two notes are short of a raised threshold" "three times"
note --shape correction --subject "Three times" --text "three"
prop scan --program alpha
expect_out "the raised threshold is met by three" "${tab}three times${tab}-${tab}3${tab}"
printf '%s\n' "mission_control_repeat_window: 1s" >>"$tracked"
sleep 2
prop scan --program alpha
expect_rc "scan runs under a short window" 0
expect_no_out "notes older than the window do not count" "three times"
sed '/^mission_control_repeat_/d' "$tracked" >"$tmp/t" && mv "$tmp/t" "$tracked"

note --shape answer --subject "Blank" --text x --target " "
expect_rc "a blank answer is refused" 2

# ---------------------------------------------------------------------------
# The window bounds the repeat; the store carries its format.
# ---------------------------------------------------------------------------
seg_write decisions 2026-01 \
  "decisions-202601-1${tab}2026-01-02T00:00:00Z${tab}Old habit${tab}x${tab}-${tab}correction - -: noted${tab}none${tab}-"
note --shape correction --subject "Old habit" --text "x"
prop scan --program alpha
expect_rc "scan runs over an old segment" 0
expect_no_out "a note outside the window does not count" "old habit"

case $(head -n 1 "$kb/proposals.tsv") in
  "# format: 1") ok "the proposal record carries its format field" ;;
  *) fail "the proposal record lacks its format field" ;;
esac
cp "$kb/proposals.tsv" "$tmp/proposals.keep"
{
  printf '# format: 7\n'
  tail -n +2 "$tmp/proposals.keep"
} >"$kb/proposals.tsv"
prop list --program alpha
expect_rc "an unknown format is refused" 1
expect_err "the refused store is named" "proposals.tsv"
cp "$tmp/proposals.keep" "$kb/proposals.tsv"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-proposals tests passed"
