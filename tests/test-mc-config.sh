#!/bin/bash
# Tests for scripts/mc-config.sh — the mission-control command's entry
# decision, its two mode knobs, and the program block, duty enablement and
# knob writes the guided first run and an accepted mechanization proposal
# make (mission-control REQ-A1.7, REQ-F1.12, REQ-F1.13, REQ-I1.5,
# REQ-B1.5, REQ-G1.4; D-14, D-18). The doctor audit lives in
# tests/test-mc-config-doctor.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-config.sh
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

[ -f "$repo_root/scripts/mc-config.sh" ] || {
  echo "FAIL: scripts/mc-config.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-config.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
cfg() { mc_run mc-config.sh "$@"; }
layer="$adopter/planwright.yml"
sum() { if [ -e "$1" ]; then cksum <"$1"; else echo absent; fi; }
reset_mc_fixture
mkdir -p "$repo/specs"

# ---------------------------------------------------------------------------
# REQ-A1.7: the command's argument rules.
# ---------------------------------------------------------------------------
cfg entry
expect_rc "REQ-A1.7: with no program configured the entry resolves" 0
expect_eq "REQ-A1.7: no program enters the guided first run" "first-run"

printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: [%s]\nprogram_alpha_spec_root: %s/specs\n' "$repo" "$repo" >"$tracked"
cfg entry
expect_eq "REQ-A1.7: one program with no argument resumes it" "resume${tab}alpha"
cfg entry alpha
expect_eq "REQ-A1.7: the named program resumes" "resume${tab}alpha"

printf 'mission_control_programs: [alpha, beta]\nprogram_alpha_repositories: [%s]\nprogram_alpha_spec_root: %s/specs\nprogram_beta_repositories: [%s]\nprogram_beta_spec_root: %s/specs\n' \
  "$repo" "$repo" "$repo" "$repo" >"$tracked"
cfg entry
expect_rc "REQ-A1.7: several programs resolve" 0
expect_eq "REQ-A1.7: several programs ask which, naming each" "ask${tab}alpha
ask${tab}beta"
cfg entry beta
expect_eq "REQ-A1.7: a named program among several resumes" "resume${tab}beta"
cfg entry gamma
expect_rc "a named program that is not configured is refused" 3
expect_err "the refusal names the configured programs" "alpha, beta"
cfg entry 'Bad;Name'
expect_rc "a program name outside the grammar is a usage error" 2
cfg entry alpha beta
expect_rc "a second argument is a usage error" 2
: >"$tracked"

# ---------------------------------------------------------------------------
# REQ-F1.13 and REQ-I1.5: the two mode knobs.
# ---------------------------------------------------------------------------
cfg mode guidance
expect_rc "REQ-F1.13: the guidance knob resolves" 0
expect_eq "REQ-F1.13: a fresh installation is guided" "guided"
cfg mode kickoff
expect_eq "REQ-I1.5: the kickoff mode is relay by default" "relay"
printf 'mission_control_guidance: standard\nmission_control_kickoff_mode: manual\n' >"$tracked"
cfg mode guidance
expect_eq "REQ-F1.13: the knob resolves through the layers" "standard"
cfg mode kickoff
expect_eq "REQ-I1.5: manual resolves through the layers" "manual"
: >"$tracked"
printf 'mission_control_guidance: loud\n' >"$layer"
cfg mode guidance
expect_eq "an invalid adopter guidance degrades to the default" "guided"
expect_err "the invalid value is warned about" "loud"
rm -f "$layer"
cfg mode verbosity
expect_rc "an unknown mode is a usage error" 2

# ---------------------------------------------------------------------------
# REQ-F1.13: the guidance level is remembered per operator, in the layer
# outside every repository.
# ---------------------------------------------------------------------------
cfg knob mission_control_guidance expert
expect_rc "REQ-F1.13: the guidance level is written" 0
expect_eq "the write names the key, the value and the previous value" "wrote${tab}mission_control_guidance${tab}expert${tab}-"
cfg mode guidance
expect_eq "REQ-F1.13: the written level is remembered" "expert"
cfg layer
expect_eq "the layer written is the adopter overlay's file" "$layer"
if grep -q 'mission_control_guidance' "$tracked"; then fail "the repo-tracked layer was written"; else ok "no repository file was written"; fi
cfg knob mission_control_guidance standard
expect_eq "a rewrite reports the value it replaced" "wrote${tab}mission_control_guidance${tab}standard${tab}expert"
if [ "$(grep -c '^mission_control_guidance:' "$layer")" -eq 1 ]; then ok "the key is set once"; else fail "the key is set more than once: $(cat "$layer")"; fi
cfg knob mission_control_guidance chatty
expect_rc "a guidance level outside its set is refused" 2
cfg knob mission_control_kickoff_mode manual
expect_rc "REQ-I1.5: the kickoff mode is written" 0
cfg mode kickoff
expect_eq "REQ-I1.5: manual is remembered" "manual"
cfg restore mission_control_kickoff_mode
expect_rc "a restore with no value removes the key" 0
cfg mode kickoff
expect_eq "the restored kickoff mode is the default again" "relay"
cfg restore mission_control_guidance expert
expect_rc "a restore with a value writes it back" 0
cfg mode guidance
expect_eq "the restored level reads back" "expert"

# REQ-G1.4: nothing outside mission control's own knobs is written.
before=$(sum "$layer")
for key in ready_flip_policy merge_policy mission_control_clipboard mission_control_home_root mission_control_programs \
  mission_control_calibration_restore mission_control_default_duties mission_control_reclaim_files \
  mission_control_budget_ladder mission_control_launch_backend mission_control_no_such_knob 'mission_control_.*'; do
  cfg knob "$key" x
  if [ "$RC" -ne 0 ] && [ "$(sum "$layer")" = "$before" ]; then
    ok "REQ-G1.4: $key is never written as a knob (exit $RC)"
  else
    fail "REQ-G1.4: $key was written as a knob (exit $RC)"
  fi
done
cfg restore ready_flip_policy unit-owner
expect_rc "a restore of a posture key is refused" 2
cfg knob mission_control_tick_cadence soon
expect_rc "a knob value its kind does not parse is refused" 2
cfg knob mission_control_repeat_threshold 0
expect_rc "a count knob takes at least one" 2
cfg restore mission_control_programs '[Bad;Name, alpha]'
expect_rc "a program list restore holds only program names" 2
cfg knob mission_control_tick_cadence "$(printf '5m\nready_flip_policy: unit-owner')"
expect_rc "a value carrying a newline is refused" 2
if [ "$(sum "$layer")" = "$before" ]; then ok "refused values leave the layer as it was"; else fail "a refused value changed the layer"; fi

# A higher layer that shadows the key refuses the write and keeps the file.
printf 'mission_control_tick_cadence: 7m\n' >"$tracked"
cfg knob mission_control_tick_cadence 9m
expect_rc "a write a higher layer shadows is refused" 1
expect_err "the shadowing layer is named" "repo-tracked"
if [ "$(sum "$layer")" = "$before" ]; then ok "the shadowed write left the layer as it was"; else fail "the shadowed write changed the layer"; fi
: >"$tracked"

# A malformed adopter layer is never rewritten.
cp "$layer" "$tmp/layer.keep"
printf 'nested:\n  key: value\n' >>"$layer"
before=$(sum "$layer")
cfg knob mission_control_tick_cadence 9m
expect_rc "a malformed adopter layer refuses the write" 1
expect_err "the malformed layer is named" "malformed"
if [ "$(sum "$layer")" = "$before" ]; then ok "the malformed layer is untouched"; else fail "the malformed layer was rewritten"; fi
cp "$tmp/layer.keep" "$layer"

# A key set oddly, a link in the layer's place, or a layer inside a
# repository is never written.
printf 'mission_control_stall_window : 40m\n' >>"$layer"
before=$(sum "$layer")
cfg knob mission_control_stall_window 30m
expect_rc "a key set with a space before its colon refuses the write" 1
if [ "$(sum "$layer")" = "$before" ]; then ok "the odd key line is kept"; else fail "the odd key line was rewritten"; fi
cp "$tmp/layer.keep" "$layer"
mv "$layer" "$tmp/layer.real"
ln -s "$tmp/no-such-target" "$layer"
cfg knob mission_control_tick_cadence 9m
expect_rc "a dangling link in the layer's place is refused" 1
if [ -L "$layer" ]; then ok "the link is left in place"; else fail "the link was replaced"; fi
rm -f "$layer"
mv "$tmp/layer.real" "$layer"
OUT=$(mc_env env PLANWRIGHT_ADOPTER_OVERLAY="$repo/.claude" /bin/bash "$repo_root/scripts/mc-config.sh" knob mission_control_tick_cadence 9m 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a layer that resolves into a repository is refused" 1
expect_err "the refusal says it is a work tree" "git work tree"
if grep -q mission_control_tick_cadence "$repo/.claude/planwright.yml" 2>/dev/null; then fail "the repository's layer was written"; else ok "the repository's layer is untouched"; fi

# ---------------------------------------------------------------------------
# REQ-F1.12: the first run ends with a program block, a knowledge-base
# skeleton and enabled duties written.
# ---------------------------------------------------------------------------
before=$(sum "$layer")
cfg add alpha --repositories "[$repo]" --spec-root "$tmp/no-such-root"
expect_rc "a program block that does not validate is refused" 1
if [ "$(sum "$layer")" = "$before" ]; then ok "the refused block left the layer as it was"; else fail "the refused block was written"; fi
cfg add alpha --repositories "[$repo]"
expect_rc "a program block without its spec root is a usage error" 2
before=$(sum "$layer")
cfg add alpha --repositories "[$repo]" --spec-root "$repo/specs" --spec-root "$tmp/other"
expect_rc "a field given twice is a usage error" 2
expect_err "the refusal names the repeated flag" "--spec-root"
if [ "$(sum "$layer")" = "$before" ]; then ok "the repeated field left the layer as it was"; else fail "the repeated field was written"; fi

before=$(sum "$layer")
cfg add alpha --repositories "[$repo]" --spec-root "$repo/specs" --sources "{designs: -:record}"
expect_rc "a class with no source and a mode other than cited is refused" 1
if [ "$(sum "$layer")" = "$before" ]; then ok "the refused map left the layer as it was"; else fail "the refused map was written"; fi

# The first run passes the default map back as --sources, so what
# `default sources` prints must round-trip through add.
mc_run mc-program.sh default sources
default_rows=$OUT
default_map=$(printf '%s\n' "$default_rows" | awk -F '\t' 'NF { s = s (s == "" ? "" : ", ") $1 ": " $2 ":" $3 } END { print "{" s "}" }')
cfg add alpha --repositories "[$repo]" --spec-root "$repo/specs" --home "$tmp/mc-home/alpha" --duties "[alpha-duty]" --sources "$default_map"
expect_rc "REQ-F1.12: the program block is written" 0
expect_out "the program joins the program list" "wrote${tab}mission_control_programs${tab}[alpha]${tab}-"
expect_out "its repositories are written" "wrote${tab}program_alpha_repositories${tab}[$repo]${tab}-"
expect_out "its enabled duties are written" "wrote${tab}program_alpha_duties${tab}[alpha-duty]${tab}-"
mc_run mc-program.sh get alpha sources
expect_eq "REQ-H1.4: the default map round-trips through add" "$default_rows"
mc_run mc-program.sh list
expect_eq "REQ-F1.12: the program is configured" "alpha"
mc_run mc-program.sh validate alpha
expect_rc "REQ-F1.12: the written block validates" 0
mc_run mc-kb.sh init --program alpha
expect_rc "REQ-F1.12: the knowledge-base skeleton initializes over the block" 0
if [ -f "$tmp/mc-home/alpha/kb/index.md" ] && [ -d "$tmp/mc-home/alpha/kb/alpha" ]; then
  ok "REQ-F1.12: the skeleton holds the index and the enabled duty's directory"
else
  fail "REQ-F1.12: the skeleton is incomplete"
fi
cfg entry
expect_eq "a configured first run resumes from then on" "resume${tab}alpha"
cfg add alpha --repositories "[$repo]" --spec-root "$repo/specs"
expect_rc "a program already configured is not added again" 1

# Duty enablement.
cfg duty --program alpha enable beta-duty
expect_rc "a duty is enabled" 0
expect_out "enabling rewrites the duty list" "wrote${tab}program_alpha_duties${tab}[alpha-duty, beta-duty]${tab}[alpha-duty]"
cfg duty --program alpha enable beta-duty
expect_rc "enabling an enabled duty changes nothing" 0
expect_eq "an unchanged list is reported, not written" "unchanged${tab}program_alpha_duties${tab}[alpha-duty, beta-duty]"
cfg duty --program alpha enable no-such-duty
expect_rc "a duty the catalog lacks is refused" 1
expect_err "the missing duty is named" "no-such-duty"
cfg duty --program alpha disable alpha-duty
expect_out "a duty is disabled" "wrote${tab}program_alpha_duties${tab}[beta-duty]${tab}[alpha-duty, beta-duty]"
cfg set --program alpha budget "{sessions: 2}"
expect_rc "a program field is set" 0
mc_run mc-program.sh get alpha budget
expect_eq "the set field reads back" "sessions${tab}2"
cfg set --program alpha spec_root "$tmp/no-such-root"
expect_rc "a field that does not validate is refused" 1
cfg set --program alpha nickname x
expect_rc "an unknown field is a usage error" 2
cfg set --program alpha "home duties" x
expect_rc "a field name carrying a space is a usage error" 2
cfg set --program alpha spec_root "$repo/specs # x"
expect_rc "a value the reader would cut at a comment is refused" 1
git -C "$tmp" init -q unlisted
cfg set --program alpha home "$tmp/unlisted/mc-home"
expect_rc "a home inside a git work tree is refused" 1
expect_err "the refusal names the work tree" "git work tree"

# A leftover block of a program no longer listed is never inherited.
printf 'program_beta_home: %s/stale-home\n' "$tmp" >>"$layer"
cfg add beta --repositories "[$repo]" --spec-root "$repo/specs"
expect_rc "a leftover block refuses the add" 1
expect_err "the leftover key is named" "program_beta_home"
grep -v '^program_beta_home:' "$layer" >"$tmp/layer.clean" && cat "$tmp/layer.clean" >"$layer"
cfg set --program gamma budget "{sessions: 2}"
expect_rc "a program that is not configured is refused" 3

# ---------------------------------------------------------------------------
# D-14: an accepted non-rule proposal is applied where mission control may
# write, its undo entry logged citing the rules on its subject; a posture
# knob is handed over, never written.
# ---------------------------------------------------------------------------
kb="$tmp/mc-home/alpha/kb"
mc_run mc-rules.sh add alpha --text "keep the tick slow overnight" --subject "Tick cadence" --source operator --date 2020-01-01
rid=$(printf '%s\n' "$OUT" | sed -n '1s/^rule \(r-[0-9]*\) .*/\1/p')
if [ -n "$rid" ]; then ok "the fixture rule is added"; else fail "the fixture rule was not added: $OUT $ERR"; fi
row() { # row <id> <kind> <mechanism> <where> <state> <subject key>
  printf '%s\t2026-01-01T00:00:00Z\tpat-%s\tmanual\t%s\t-\tdecisions-202601-1\t%s\t%s\t%s\tsrc\tchange it\tc\tc\tc\tc\t%s\t-\t-\n' \
    "$1" "$1" "$6" "$2" "$3" "$4" "$5"
}
{
  printf '# format: 1\n'
  row p-1 knob mission_control_tick_cadence "the config layers" accepted "tick cadence"
  row p-2 duty alpha-duty "the core duties catalog" accepted "duties"
  row p-3 knob ready_flip_policy "the config layers" accepted "flips"
  row p-4 knob mission_control_tick_cadence "the config layers" open "tick cadence"
  row p-5 rule "a rule-store entry" "$tmp/rules.yaml" accepted "rules"
  row p-6 catalog-step polish "the core steps catalog" accepted "polish"
  row p-7 knob program_alpha_budget "the config layers" accepted "budget"
  row p-20 knob mission_control_successor_remote_control "the config layers" accepted "successor remote control"
} >"$kb/proposals.tsv"

cfg apply --program alpha p-1
expect_rc "a knob proposal needs the accepted value" 2
cfg apply --program alpha p-1 --value 10m
expect_rc "D-14: an accepted knob proposal is applied" 0
expect_out "the knob is written" "applied${tab}knob${tab}mission_control_tick_cadence${tab}10m${tab}undo-"
mc_run config-get.sh mission_control_tick_cadence
expect_eq "the applied knob resolves" "10m"
mc_run mc-kb.sh query undo --program alpha --subject "tick cadence"
expect_out "the undo entry cites the rule on its subject" "settled - $rid: applied accepted mechanization proposal p-1"
expect_out "the undo entry carries its reversal" "mc-config.sh"
cfg apply --program alpha p-1 --value 10m
expect_rc "a second apply is a no-op" 0
expect_out "a second apply reports it was already applied" "already${tab}p-1"
mc_run mc-kb.sh query undo --program alpha --subject "tick cadence"
if [ "$(printf '%s\n' "$OUT" | grep -c 'proposal p-1')" -eq 1 ]; then ok "one undo entry per proposal"; else fail "the undo entry was logged twice"; fi
mc_run mc-audit.sh run --program alpha
expect_rc "the self-audit runs" 0
expect_out "the self-audit reports its count" "audit${tab}"
expect_no_out "the self-audit finds no act against the rule" "against-rule"

cfg apply --program alpha p-20 --value sometimes
expect_rc "a successor Remote Control value outside off, inherit and on is refused" 2
cfg apply --program alpha p-20 --value inherit
expect_rc "an accepted successor Remote Control proposal is applied" 0
expect_out "the successor Remote Control knob is written" "applied${tab}knob${tab}mission_control_successor_remote_control${tab}inherit${tab}undo-"
mc_run config-get.sh mission_control_successor_remote_control
expect_eq "the applied successor Remote Control value resolves" "inherit"
cfg apply --program alpha p-2
expect_rc "D-14: an accepted duty proposal is applied" 0
mc_run mc-program.sh get alpha duties
expect_eq "the proposed duty is enabled" "beta-duty
alpha-duty"
cfg apply --program alpha p-7 --value "{sessions: 3}"
expect_rc "D-14: an accepted program-block proposal is applied" 0
mc_run mc-program.sh get alpha budget
expect_eq "the program field is written" "sessions${tab}3"

before=$(sum "$layer")
cfg apply --program alpha p-3 --value unit-owner
expect_rc "a posture knob proposal is handed over" 0
expect_eq "REQ-G1.4: it is handed to the operator ready to apply" "handover-operator${tab}the config layers${tab}change it"
cfg apply --program alpha p-6
expect_eq "a catalog step is a repository change, dispatched" "dispatch${tab}the core steps catalog${tab}change it"
if [ "$(sum "$layer")" = "$before" ]; then ok "REQ-G1.4: nothing was written for either"; else fail "a handed-over change was written"; fi
cfg apply --program alpha p-4 --value 10m
expect_rc "an open proposal is not applied" 1
cfg apply --program alpha p-5
expect_rc "a rule proposal is applied by its accept, not here" 1
cfg apply --program alpha p-9
expect_rc "an unknown proposal is refused" 1
cfg apply --program alpha bogus
expect_rc "a malformed proposal id is a usage error" 2

# The logged reversal restores what the apply replaced.
undo_id=$(
  mc_run mc-kb.sh query undo --program alpha --subject "tick cadence"
  printf '%s\n' "$OUT" | awk -F '\t' '/proposal p-1/ { print $1; exit }'
)
mc_run mc-kb.sh revert --program alpha "$undo_id"
expect_rc "the reversal runs" 0
mc_run config-get.sh --explain mission_control_tick_cadence
expect_eq "the reversal removed the applied knob" "core${tab}5m"

# Applied again after a revert, the change gets an undo entry of its own.
cfg apply --program alpha p-1 --value 10m
expect_rc "a reverted proposal applies again" 0
second=$(printf '%s\n' "$OUT" | cut -f 5)
if [ -n "$second" ] && [ "$second" != "$undo_id" ]; then ok "the re-apply logs a new undo entry"; else fail "the re-apply reused the reverted entry ($second)"; fi
mc_run mc-kb.sh revert --program alpha "$second"
expect_rc "the new entry reverts" 0

# A value the operator set after an apply is what a later apply's undo
# entry restores, never the value from before the first apply.
cfg apply --program alpha p-1 --value 10m
first=$(printf '%s\n' "$OUT" | cut -f 5)
cfg knob mission_control_tick_cadence 20m
cfg apply --program alpha p-1 --value 10m
third=$(printf '%s\n' "$OUT" | cut -f 5)
if [ -n "$third" ] && [ "$third" != "$first" ]; then ok "an apply over a since-replaced value logs a new undo entry"; else fail "the apply reused an entry restoring a replaced value ($third)"; fi
mc_run mc-kb.sh revert --program alpha "$third"
mc_run config-get.sh mission_control_tick_cadence
expect_eq "reverting it restores the operator's value" "20m"
cfg restore mission_control_tick_cadence

# A relative layer path is judged from the working directory.
OUT=$(mc_env env PLANWRIGHT_ADOPTER_OVERLAY=rel/overlay /bin/bash "$repo_root/scripts/mc-config.sh" knob mission_control_tick_cadence 9m 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a relative layer inside the repository is refused" 1
if [ -e "$repo/rel" ]; then fail "the refused write left a directory in the repository"; else ok "nothing was created in the repository"; fi

# A duty's reversal disables that duty alone.
cfg duty --program alpha disable alpha-duty
cfg apply --program alpha p-2
duty_undo=$(printf '%s\n' "$OUT" | cut -f 5)
cfg duty --program alpha enable beta-duty
mc_run mc-kb.sh revert --program alpha "$duty_undo"
expect_rc "the duty reversal runs" 0
mc_run mc-program.sh get alpha duties
expect_eq "reverting one duty keeps a duty enabled after it" "beta-duty"

# A write refused after its checks leaves no undo entry behind.
{
  cat "$kb/proposals.tsv"
  row p-8 knob mission_control_stall_window "the config layers" accepted "stall window"
  row p-10 duty no-such-duty "the core duties catalog" accepted "ghost duty"
} >"$tmp/proposals.next" && cat "$tmp/proposals.next" >"$kb/proposals.tsv"
printf 'mission_control_stall_window: 20m\n' >"$tracked"
cfg apply --program alpha p-8 --value 15m
expect_rc "a shadowed apply is refused" 1
cfg apply --program alpha p-10
expect_rc "an apply naming a duty the catalog lacks is refused" 1
: >"$tracked"
mc_run mc-kb.sh entries undo --program alpha
expect_no_out "no undo entry names the refused knob apply" "proposal p-8"
expect_no_out "no undo entry names the refused duty apply" "proposal p-10"

# A layer whose leading comment says a tool renders it is managed elsewhere:
# every write is handed to the operator as the lines to add at its source,
# exit 4, the file untouched; a marker anywhere but the header is not one.
unmanaged=$(cat "$layer")
{
  printf '# Rendered from a vault by the machine setup; a hand edit here is\n# overwritten on the next run.\n'
  printf '%s\n' "$unmanaged"
} >"$layer"
before=$(sum "$layer")
where="$layer, managed elsewhere: Rendered from a vault by the machine setup; a hand edit here is overwritten on the next run."
cfg knob mission_control_tick_cadence 7m
expect_rc "a write to a managed layer is handed over" 4
expect_eq "the hand-over names the source and the exact line to add" "handover-operator${tab}${where}${tab}mission_control_tick_cadence: 7m"
expect_err "the refusal says nothing was written" "nothing was written"
cfg restore mission_control_guidance
expect_rc "a removal from a managed layer is handed over" 4
expect_eq "the hand-over names the line to remove" "handover-operator${tab}${where}${tab}remove mission_control_guidance"
cfg duty --program alpha disable beta-duty
expect_rc "a duty change to a managed layer is handed over" 4
expect_out "the duty hand-over carries the new list" "${tab}program_alpha_duties: []"
cfg add gamma --repositories "[$repo]" --spec-root "$repo/specs" --duties '[]'
expect_rc "a new program on a managed layer is handed over" 4
expect_out "the program list is one line to add" "${tab}mission_control_programs: [alpha, gamma]"
expect_out "each block key is a line of its own" "${tab}program_gamma_spec_root: $repo/specs"
mc_run mc-kb.sh entries undo --program alpha
undo_before=$OUT
cfg apply --program alpha p-1 --value 8m
expect_rc "an accepted proposal on a managed layer is handed over" 4
expect_eq "the proposal's hand-over is its line" "handover-operator${tab}${where}${tab}mission_control_tick_cadence: 8m"
mc_run mc-kb.sh entries undo --program alpha
if [ "$OUT" = "$undo_before" ]; then ok "a handed-over apply logs no undo entry"; else fail "a handed-over apply logged an undo entry"; fi
if [ "$(sum "$layer")" = "$before" ]; then ok "nothing was written to the managed layer"; else fail "the managed layer was written: $(cat "$layer")"; fi
printf '# DO NOT EDIT: generated.\n%s\n' "$unmanaged" >"$layer"
cfg knob mission_control_tick_cadence 7m
expect_rc "a do-not-edit header is a managed marker too" 4
printf -- '---\n# Site configuration\n\n# Managed by the machine setup.\n%s\n' "$unmanaged" >"$layer"
cfg knob mission_control_tick_cadence 7m
expect_rc "a header paragraph past a blank line or document marker still counts" 4
printf '#  Generated   by\tthe machine setup.\n%s\n' "$unmanaged" >"$layer"
cfg knob mission_control_tick_cadence 7m
expect_rc "a marker phrase spaced out by runs of blanks still counts" 4
printf -- '--- # Managed by the machine setup.\n%s\n' "$unmanaged" >"$layer"
cfg knob mission_control_tick_cadence 7m
expect_rc "a comment on the document marker line is part of the header" 4
{
  printf '# my own notes\n'
  printf '%s\n' "$unmanaged"
  printf '# rendered from nowhere, overwritten never\n'
} >"$layer"
cfg knob mission_control_tick_cadence 7m
expect_rc "a marker past the header is no marker; the write lands" 0
cfg restore mission_control_tick_cadence

# ---------------------------------------------------------------------------
# REQ-A1.10: doctor lists the rules that are prose, unknown or name a closed
# fix, one plain line each, and edits nothing. Fixtures only: a rule store, a
# forge snapshot, observation fragments and a fake gh.
# ---------------------------------------------------------------------------
reset_mc_fixture
ehome="$tmp/enf-home"
printf 'mission_control_programs: [enf]\nprogram_enf_repositories: [%s]\nprogram_enf_spec_root: %s/specs\nprogram_enf_home: %s\n' "$repo" "$repo" "$ehome" >"$tracked"
rule() { # rule <enforcement or ->: add a rule, enforcement optional
  if [ "$1" = - ]; then
    mc_run mc-rules.sh add enf --text "Rule text $2" --subject "enf-$2" --source "operator, fixture" --date 2026-11-10
  else
    mc_run mc-rules.sh add enf --text "Rule text $2" --subject "enf-$2" --source "operator, fixture" --date 2026-11-10 --enforcement "$1"
  fi
}
rule 'prose:a tone, never mechanical' 1
rule - 2
rule 'fix:#11' 3
rule 'fix:#12' 4
rule 'fix:acme/widgets#13' 5
rule 'fix:#99' 6
rule script:mc-rules.sh 7
rule knob:mission_control_stall_window 8
rule hook:ready-guard 9
rule duty:inbox 10
rule default:fleet_max_parallel_units 11
rule fix:obs-consumed-aaaa1111 12
rule fix:obs-open-bbbb2222 13
rule 'prose:replaced later' 14
mc_run mc-rules.sh supersede enf r-14 --text "Rule text 14 again" --source "operator, fixture" --date 2026-11-10 --enforcement knob:mission_control_stall_window
obs="$repo/specs/_observations"
mkdir -p "$obs/entries" "$obs/archive"
printf -- '- 2026-11-10 [planwright] consumed\nConsumed-by: spec x\n' >"$obs/archive/obs-consumed-aaaa1111.md"
printf -- '- 2026-11-10 [planwright] open\n' >"$obs/entries/obs-open-bbbb2222.md"
snapdir="$fleet/mission-control/enf/snapshots"
mkdir -p "$snapdir"
{
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$(date +%s)"
  printf 'pr\tacme/widgets\t11\tabc123\tfalse\tMERGEABLE\tNONE\t0\tNONE\t0\t0\tnone\tmain\tfeat\n'
} >"$snapdir/forge"
mkdir -p "$tmp/ghbin"
cat >"$tmp/ghbin/gh" <<'EOF'
#!/bin/sh
# Fake gh: pr view <n> answers from $GH_FIXTURE ("<n> <STATE>"), else fails.
echo "$*" >>"$GH_LOG"
[ "$1" = pr ] && [ "$2" = view ] || exit 2
n=$3
state=$(awk -v n="$n" '$1 == n { print $2 }' "$GH_FIXTURE")
[ -n "$state" ] || exit 1
echo "$state"
EOF
chmod +x "$tmp/ghbin/gh"
printf '12 MERGED\n13 CLOSED\n' >"$tmp/gh.fixture"
: >"$tmp/gh.log"
saved_path=$PATH
PATH="$tmp/ghbin:$PATH"
GH_FIXTURE="$tmp/gh.fixture"
GH_LOG="$tmp/gh.log"
export PATH GH_FIXTURE GH_LOG

rules_before=$(cksum <"$ehome/rules.yaml")
layer_before=$(cksum <"$tracked")
cfg doctor --program enf
expect_rc "REQ-A1.10: doctor with rules to list still exits 0" 0
expect_out "REQ-A1.10: a prose rule is a line saying what to do" "rule-enforcement${tab}r-1${tab}prose${tab}"
expect_out "REQ-A1.10: the prose line names what to do in plain words" "keep it as prose"
expect_out "REQ-A1.10: a rule with no enforcement is a line" "rule-enforcement${tab}r-2${tab}unknown${tab}"
expect_no_out "REQ-A1.10: a rule naming an open pull request is no line" "rule-enforcement${tab}r-3${tab}"
expect_out "REQ-A1.10: a rule naming a merged pull request is a line" "rule-enforcement${tab}r-4${tab}closed-fix${tab}"
expect_out "REQ-A1.10: a rule naming a closed pull request of a named repository is a line" "rule-enforcement${tab}r-5${tab}closed-fix${tab}"
expect_out "REQ-A1.10: a closed-fix lookup that fails lists the rule as unknown" "rule-enforcement${tab}r-6${tab}unknown${tab}"
for r in 7 8 9 10 11; do
  expect_no_out "REQ-A1.10: a rule naming a script, knob, hook, duty or default is no line (r-$r)" "rule-enforcement${tab}r-$r${tab}"
done
expect_out "REQ-A1.10: a rule naming a consumed observation is a line" "rule-enforcement${tab}r-12${tab}closed-fix${tab}"
expect_no_out "REQ-A1.10: a rule naming an unconsumed observation is no line" "rule-enforcement${tab}r-13${tab}"
expect_no_out "REQ-A1.10: a superseded rule is no line" "rule-enforcement${tab}r-14${tab}"
expect_no_out "REQ-A1.10: its replacement, enforced by a knob, is no line" "rule-enforcement${tab}r-15${tab}"
if grep -q ' 11' "$tmp/gh.log"; then
  fail "REQ-A1.10: a pull request the snapshot holds open was looked up anyway"
else
  ok "REQ-A1.10: a pull request the snapshot holds open needs no lookup"
fi
if [ "$rules_before" = "$(cksum <"$ehome/rules.yaml")" ] && [ "$layer_before" = "$(cksum <"$tracked")" ]; then
  ok "REQ-A1.10: no rule or layer file changes"
else
  fail "REQ-A1.10: doctor changed a rule or layer file"
fi

# The rule-versus-knob flag and this listing are separate sections, so the
# knob disagreement still reports beside them.
rule - 16
mc_run mc-rules.sh add enf --text "Set mission_control_stall_window to 30m." --subject stall --source "operator, fixture" --date 2026-11-10 --enforcement knob:mission_control_stall_window
cfg doctor --program enf
expect_out "REQ-A1.10: a rule disagreeing with its knob is still flagged" "rule-knob${tab}r-17${tab}mission_control_stall_window"
expect_out "REQ-A1.10: the enforcement listing still lists beside it" "rule-enforcement${tab}r-16${tab}unknown${tab}"

# A bare #n names no repository, so with two repositories it is read as
# unknown, never as the open pull request of the same number elsewhere.
mkdir -p "$tmp/second"
printf 'mission_control_programs: [enf]\nprogram_enf_repositories: [%s, %s]\nprogram_enf_spec_root: %s/specs\nprogram_enf_home: %s\n' "$repo" "$tmp/second" "$repo" "$ehome" >"$tracked"
cfg doctor --program enf
expect_out "REQ-A1.10: a bare pull request number in a two-repository program is unknown" "rule-enforcement${tab}r-3${tab}unknown${tab}"
expect_out "REQ-A1.10: a pull request named with its repository is still read there" "rule-enforcement${tab}r-5${tab}closed-fix${tab}"
PATH=$saved_path
export PATH

[ "$failures" -eq 0 ] || {
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
}
echo "all mc-config tests passed"
