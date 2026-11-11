#!/bin/bash
# Tests for scripts/mc-config.sh — the mission-control command's entry
# decision, its two mode knobs, and the program block, duty enablement and
# knob writes the guided first run and an accepted mechanization proposal
# make (mission-control REQ-A1.7, REQ-F1.12, REQ-F1.13, REQ-I1.5,
# REQ-B1.5, REQ-G1.4; D-14, D-18).
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
# The bring-up audit: doctor names every shipped default a layer overrides
# and every inherited mechanism it can see, and writes nothing.
# ---------------------------------------------------------------------------
reset_mc_fixture
# The scratch path may itself name planwright or claude, so the program-path
# match is proven on a repository and a home whose paths name neither.
neutral_home=/mcdoc-neutral-home/alpha
neutral_repo=/mcdoc-neutral-repo/alpha
printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: [%s, %s]\nprogram_alpha_spec_root: %s/specs\nprogram_alpha_home: %s\n' "$repo" "$neutral_repo" "$repo" "$neutral_home" >"$tracked"
mkdir -p "$tmp/cronbin"
cat >"$tmp/cronbin/crontab" <<'EOF'
#!/bin/sh
[ "$1" = -l ] || exit 2
[ -f "$CRON_FIXTURE" ] || { echo "no crontab for fixture" >&2; exit 1; }
cat "$CRON_FIXTURE"
EOF
chmod +x "$tmp/cronbin/crontab"
saved_path=$PATH
PATH="$tmp/cronbin:$PATH"
CRON_FIXTURE="$tmp/crontab.txt"
export PATH CRON_FIXTURE

cfg doctor --program alpha
expect_rc "doctor runs on a program on the shipped defaults" 0
expect_eq "a program on the shipped defaults with no crontab is clean" "clean"

sessions="$fleet/mission-control/sessions"
mkdir -p "$sessions"
session_row() { # session_row <name> <program> <backend>: a launch registry row
  printf 'format\t1\nname\t%s\nprogram\t%s\nkind\tworker\nscope\tx\nbackend\t%s\nlaunched\t1\n' "$1" "$2" "$3" >"$sessions/$1"
}
session_row mc-alpha-worker-1111111111 alpha tmux
session_row mc-alpha-worker-2222222222 alpha stream-json
session_row mc-beta-worker-3333333333 beta tmux
session_row mc-alpha-worker-4444444444 alpha ''
# Shell forms no redaction could model, and schedules short, named or with
# an unknown keyword, each a crontab line, then " ==> "
# and the command word and match the report must read as (a blank standing
# for the tab): never an argument, and a word past the plain characters cut
# where they end.
shapes="$tmp/cron-shapes.txt"
cat >"$shapes" <<'SHAPES'
30 * * * * T=`echo lk-j lk-k` planwright ==> T=<redacted> planwright
31 * * * * T=${X:-lk-l lk-m} planwright ==> T=<redacted> planwright
32 * * * * TOKEN="$(cat "/x lk-n") lk-o" planwright ==> TOKEN=<redacted> planwright
33 * * * * T=$'a\'b lk-p' planwright ==> T=<redacted> planwright
34 * * * * sh -c 'TOKEN='\''lk-q lk-r'\'' planwright' ==> sh planwright
1PLANWRIGHT_TOKEN=lk-s lk-t ==> 1PLANWRIGHT_TOKEN=<redacted> PLANWRIGHT
@PLANWRIGHT_TOKEN=lk-u lk-v ==> <redacted> PLANWRIGHT
35 * * * * \TOKEN=lk-w planwright ==> <redacted> planwright
36 * * * * env "TOKEN"=lk-x TOKEN"="lk-y planwright ==> env planwright
37 * * * * T+=lk-z A[0]=lk-0 planwright ==> T+=<redacted> planwright
0=lk-01 claude ==> 0=<redacted> claude
*=lk-02 planwright ==> <redacted> planwright
39 * * * * T=$(case a in a) echo lk-05 lk-06;; esac) planwright ==> T=<redacted> planwright
  planwright_secret=lk-07 lk-08 ==> planwright_secret=<redacted> planwright
@reboot T=lk-09 /opt/planwright/r ==> T=<redacted> planwright
-*/5 * * * * T=lk-10 /opt/planwright/dash ==> T=<redacted> planwright
41 * * * * [ "$a" = "$b" ] && planwright ==> <redacted> planwright
42 * * * * echo "$(grep "it's" /f)" 'TOKEN=lk-20 lk-21' planwright ==> echo planwright
43 * * * * echo "`echo "'"`" 'K=lk-22 lk-23' planwright ==> echo planwright
44 * * * * bash -c $'echo it\'s; TOKEN=lk-24 lk-25\' planwright' ==> bash planwright
45 * * * * T=$[1 + lk-26] planwright ==> T=<redacted> planwright
46 * * * * planwright # don't 'TOKEN=lk-27 lk-28' ==> planwright planwright
47 * * * * planwright %it's 'TOKEN=lk-29 lk-2a' ==> planwright planwright
48 * * * * T=lk-2b%lk-2c lk-2d planwright ==> T=<redacted> planwright
"PLANWRIGHT_TOKEN=lk-2e"=lk-2f ==> <redacted> PLANWRIGHT
'claude=lk-2g lk-2h'=lk-2i ==> <redacted> claude
0 0 * * curl lk-c1 https://x/planwright ==> <redacted> planwright
0 0 mysql -u root -plk-c2 planwright ==> <redacted> planwright
@bogus lk-c3 planwright ==> <redacted> planwright
0 0 * may lk-c4 planwright ==> <redacted> planwright
*/5 * * * planwright ==> <redacted> planwright
0 0 1 Jan,mar Mon-fri /opt/planwright/named ==> /opt/planwright/named planwright
@weekly /opt/planwright/wk ==> /opt/planwright/wk planwright
0~30 */2 * * * /opt/planwright/rand ==> /opt/planwright/rand planwright
SHAPES
{
  printf '# a comment naming planwright\n'
  printf '*/5 * * * * /opt/hub/w.sh planwright sweep\n'
  printf '0 3 * * * /usr/bin/backup\n'
  printf '*/10 * * * * cd %s && ./sweep.sh\n' "$repo"
  printf '%s\n' "*/15 * * * * PLANWRIGHT_TOKEN=s3cr3t API_KEY='x y' NOTE=\"a b\" /opt/hub/claude-run.sh --key=k3y"
  printf '%s\n' '1 * * * * T="lk-1 lk-2"lk-3 /opt/planwright/a'
  printf '%s\n' '2 * * * * T=lk-4"lk-5 lk-6" /opt/planwright/b'
  printf '%s\n' '3 * * * * T=lk-7\ lk-8 /opt/planwright/c'
  printf '%s\n' '4 * * * * T="lk-9\" lk-a" /opt/planwright/d'
  # shellcheck disable=SC2016 # a literal crontab line, never expanded
  printf '%s\n' '5 * * * * T=$(cat /run/lk-b x) /opt/planwright/e'
  printf '%s\n' "6 * * * * curl -d 'token=lk-c lk-d' /opt/planwright/f"
  printf '%s\n' '7 * * * * /opt/planwright/g T="lk-e lk-f'
  printf '%s\n' 'planwright_token = lk-g lk-h'
  printf '8 * * * * TOKEN\001=lk-i /opt/planwright/h\n'
  printf '9\t*\t*\t*\t*\t/opt/planwright/i\n'
  printf '%s\n' '10 * * * * /opt/hub/Claude-Sweep.sh' '11 * * * * PLANWRIGHT_ROOT=/opt/pw /opt/pw/tick.sh'
  printf '*/20 * * * * %s/tick.sh\n' "$neutral_home"
  printf '*/12 * * * * cd %s && ./x.sh\n' "$neutral_repo"
  printf '%s\n' '*/25 * * * * /MCDOC-NEUTRAL-HOME/alpha/x.sh'
  printf '38 * * * * T=abc\\\033"lk-03 lk-04" /opt/planwright/a\n'
  printf '%s\n' "50 * * * * curl -H 'Authorization: Bearer lk-b1' https://bot:lk-b2@api.example/planwright --token lk-b3 -o /dev/null%lk-b4"
  printf '%s\n' '51 * * * * https://bot:lk-b5@api.example/claude' '52 * * * * /opt/planwright/x%lk-b6' '53 * * * * --token=lk-b7 planwright'
  printf '*/30 * * * * /opt/planwright/both %s/y\n' "$neutral_repo"
  sed 's/ ==> .*//' "$shapes"
} >"$CRON_FIXTURE"
printf 'mission_control_launch_backend: stream-json\nmission_control_stall_window: 30m\nmission_control_tick_cadence: 5m\n' >"$layer"
printf 'program_alpha_duties: [inbox, readiness-check]\n' >>"$tracked"
before=$(sum "$layer")
tracked_before=$(sum "$tracked")
cfg doctor --program alpha
expect_rc "doctor reports findings as data" 0
expect_out "a layer's value away from the shipped one is named with its layer" "override${tab}mission_control_stall_window${tab}adopter${tab}30m${tab}10m"
expect_no_out "a layer restating the shipped value is no override" "mission_control_tick_cadence"
expect_no_out "a layer restating the shipped backend is no override" "override${tab}mission_control_launch_backend"
expect_no_out "the program list is setup, not an override" "mission_control_programs"
expect_out "a shipped default duty the program leaves off is named" "duty-off${tab}session-keeper"
expect_no_out "an enabled duty is not named" "duty-off${tab}inbox"
expect_out "a session launched on another rung than the knob is named" "launch-backend${tab}mc-alpha-worker-1111111111${tab}tmux${tab}stream-json"
expect_no_out "a session on the knob's rung is not named" "mc-alpha-worker-2222222222"
expect_no_out "another program's session is not named" "mc-beta-worker-3333333333"
expect_out "a session whose row names no rung is an unknown launches check" "unknown${tab}launches${tab}mc-alpha-worker-4444444444 names no rung"
expect_no_out "a session whose row names no rung is not read as another rung" "launch-backend${tab}mc-alpha-worker-4444444444"
cron_line() { # cron_line <label> <word> <match>: one report line reads exactly so
  if printf '%s\n' "$OUT" | grep -qxF -- "cron${tab}$2${tab}$3"; then
    ok "$1: $2 $3"
  else
    fail "$1: no report line reads exactly: cron<TAB>$2<TAB>$3"
  fi
}
cron_line "a cron line naming planwright is named by its command word" /opt/hub/w.sh planwright
cron_line "a cron line in a program repository is named by that path" cd "$repo"
cron_line "a cron line naming only the program home is named" "$neutral_home/tick.sh" "$neutral_home"
cron_line "a cron line naming only a program repository is named" cd "$neutral_repo"
expect_no_out "a program path matches only as spelled" "/MCDOC-NEUTRAL-HOME"
cron_line "a leading assignment is the word, its value blanked" 'PLANWRIGHT_TOKEN=<redacted>' PLANWRIGHT
cron_line "a credential the line carries in its arguments is never printed" curl planwright
cron_line "a command word holding a URL password is cut before it" 'https<redacted>' claude
cron_line "a command word running into cron's % is cut there" '/opt/planwright/x<redacted>' planwright
cron_line "a --token word is cut at its =" '--token=<redacted>' planwright
cron_line "a program path wins over a product name on the same line" /opt/planwright/both "$neutral_repo"
# Every report line in the crontab's order, so a line misread, dropped or
# doubled fails even where another line prints the same text.
cron_want=$(
  printf 'cron\t%s\t%s\n' /opt/hub/w.sh planwright cd "$repo" 'PLANWRIGHT_TOKEN=<redacted>' PLANWRIGHT \
    'T=<redacted>' planwright 'T=<redacted>' planwright 'T=<redacted>' planwright \
    'T=<redacted>' planwright 'T=<redacted>' planwright curl planwright \
    /opt/planwright/g planwright planwright_token planwright 'TOKEN=<redacted>' planwright \
    /opt/planwright/i planwright /opt/hub/Claude-Sweep.sh Claude 'PLANWRIGHT_ROOT=<redacted>' PLANWRIGHT \
    "$neutral_home/tick.sh" "$neutral_home" cd "$neutral_repo" 'T=<redacted>' planwright \
    curl planwright 'https<redacted>' claude '/opt/planwright/x<redacted>' planwright \
    '--token=<redacted>' planwright /opt/planwright/both "$neutral_repo"
  sed "s/^.* ==> //; s/ /$tab/; s/^/cron$tab/" "$shapes"
)
cron_got=$(printf '%s\n' "$OUT" | grep "^cron$tab")
if [ "$cron_got" = "$cron_want" ]; then
  ok "each reported cron line reads as its own expected word and match, in order"
else
  fail "the cron report lines differ from the expected ones, in order:"
  printf '%s\n' "$cron_want" >"$tmp/cron-want.txt"
  printf '%s\n' "$cron_got" | diff "$tmp/cron-want.txt" - >&2
fi
for secret in s3cr3t "x y" "a b" k3y lk- Bearer Authorization 'bot:' ./sweep.sh; do
  expect_no_out "a cron line's arguments never reach the report: $secret" "$secret"
done
cron_line "a cron line naming Claude in another case is named as spelled" /opt/hub/Claude-Sweep.sh Claude
cron_line "a cron line naming PLANWRIGHT in capitals is named" 'PLANWRIGHT_ROOT=<redacted>' PLANWRIGHT
expect_no_out "an unrelated cron line is not named" "backup"
expect_no_out "a cron comment is not named" "a comment"
expect_no_out "findings leave out the clean line" "clean"
if [ "$(sum "$layer")" = "$before" ] && [ "$(sum "$tracked")" = "$tracked_before" ]; then
  ok "doctor writes no layer"
else
  fail "doctor changed a layer"
fi

printf 'mission_control_launch_backend: tmux\n' >"$layer"
: >"$CRON_FIXTURE"
cfg doctor --program alpha
expect_out "a layer moving the backend knob is named" "override${tab}mission_control_launch_backend${tab}adopter${tab}tmux${tab}stream-json"
expect_out "launches are judged against the knob in force" "launch-backend${tab}mc-alpha-worker-2222222222${tab}stream-json${tab}tmux"

if [ "$(id -u)" != 0 ]; then
  chmod 000 "$sessions"
  cfg doctor --program alpha
  chmod 700 "$sessions"
  expect_rc "doctor with an unreadable registry still reports" 0
  expect_out "an unreadable registry is an unknown launches check" "unknown${tab}launches${tab}the launch registry could not be read"
  expect_out "the other checks still report beside an unreadable registry" "override${tab}mission_control_launch_backend${tab}adopter${tab}tmux${tab}stream-json"
fi

tracked_good=$(cat "$tracked")
printf '%s\n' "$tracked_good" | sed 's|^program_alpha_repositories: .*|program_alpha_repositories: relative/repo|' >"$tracked"
printf '*/5 * * * * /opt/hub/w.sh planwright sweep\n*/20 * * * * %s/tick.sh\n' "$neutral_home" >"$CRON_FIXTURE"
cfg doctor --program alpha
expect_out "an unreadable repository list is an unknown cron check" "unknown${tab}cron${tab}"
cron_line "the cron scan still names a line naming planwright" /opt/hub/w.sh planwright
expect_no_out "a path the program could not report is not matched" "$neutral_home/tick.sh"
printf '%s\n' "$tracked_good" >"$tracked"
: >"$CRON_FIXTURE"

printf '%s\n' "$tracked_good" | sed 's|^program_alpha_duties: .*|program_alpha_duties: [inbox, inbox]|' >"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor with an unreadable duty list still reports" 0
expect_out "an unreadable duty list is an unknown duties check, never clean" "unknown${tab}duties${tab}the enabled or default duties could not be read"
expect_no_out "an unreadable duty list names no duty off" "duty-off${tab}"

printf '%s\n' '- not flat' 'mission_control_stall_window: 30m' >"$layer"
printf '%s\n' 'mission_control_tick_cadence: 7m' >>"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor with a malformed adopter layer still reports" 0
expect_out "a malformed adopter layer is an unknown overrides check, never clean" "unknown${tab}overrides${tab}a layer is malformed"
expect_no_out "a skipped layer's value is not reported as in force" "override${tab}mission_control_stall_window"
expect_out "the readable layers' overrides still follow a malformed adopter layer" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"
rm -f "$layer"

printf '%s\n' 'mission_control_stall_window: 30m' >"$layer"
printf '%s\n' 'mission_control_stall_window: 10m' >>"$tracked"
cfg doctor --program alpha
expect_no_out "a higher layer restoring the shipped value leaves no override" "override${tab}mission_control_stall_window"
printf '%s\n' "$tracked_good" 'mission_control_stall_window: 20m' >"$tracked"
cfg doctor --program alpha
expect_out "the override names the layer in force and its value" "override${tab}mission_control_stall_window${tab}repo-tracked${tab}20m${tab}10m"
printf '%s\n' "$tracked_good" >"$tracked"
rm -f "$layer"

printf '%s\n' 'mission_control_kb_index_budget: 0150' >"$layer"
cfg doctor --program alpha
rm -f "$layer"
expect_out "a value equal to the shipped one only as a number is an override" "override${tab}mission_control_kb_index_budget${tab}adopter${tab}0150${tab}150"

printf '%s\n' 'mission_control_default_duties: [inbox, readiness-check]' >"$layer"
printf '%s\n' "$tracked_good" | sed 's|^program_alpha_duties: .*|program_alpha_duties: [inbox]|' >"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
rm -f "$layer"
expect_out "a default duty is judged against the default list the layers resolve" "duty-off${tab}readiness-check"
expect_no_out "a shipped default duty a layer drops from the list is not named" "duty-off${tab}session-keeper"

printf '%s\n' 'mission_control_launch_backend: bogus' >>"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_out "a launch backend knob that cannot be resolved is an unknown launches check" "unknown${tab}launches${tab}mission_control_launch_backend could not be resolved"
expect_no_out "no session is judged against a knob that cannot be resolved" "launch-backend${tab}"

printf '%s\n' 'mission_control_tick_cadence: 7m' 'mission_control_tick_cadence: 7m' >>"$tracked"
cfg doctor --program alpha
expect_rc "doctor with a knob set twice in the repo-tracked layer still reports" 0
expect_out "a knob set twice is an unknown overrides check" "unknown${tab}overrides${tab}a layer is malformed, unreadable, or sets a knob twice"
expect_out "the overrides a plain read finds still follow it" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"
OUT=$(mc_env env PLANWRIGHT_CONFIG_STRICT_OVERLAYS=1 /bin/bash "$repo_root/scripts/mc-config.sh" doctor --program alpha 2>"$tmp/stderr")
RC=$?
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor run with strict overlays already set still reports" 0
expect_out "the plain read clears an inherited strict setting" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"

grep -v '^mission_control_stall_window:' "$core/config/defaults.yml" >"$tmp/defaults.trimmed"
mv "$tmp/defaults.trimmed" "$core/config/defaults.yml"
printf '%s\n' 'mission_control_stall_window: 30m' >"$layer"
cfg doctor --program alpha
write_core_defaults </dev/null
rm -f "$layer"
expect_out "a knob set with no shipped value read is an unknown overrides check, never clean" "unknown${tab}overrides${tab}mission_control_stall_window is set in adopter"
expect_no_out "a knob with no shipped value read is not compared" "override${tab}mission_control_stall_window"

# ---------------------------------------------------------------------------
# Doctor drift: a standing rule that names a number for a knob it governs,
# and a dated, interim or temporary override in a local layer.
# ---------------------------------------------------------------------------
reset_mc_fixture
drift_home="$tmp/drift-home"
mlocal="$tmp/absent.yml"
printf 'mission_control_programs: [drift]\nprogram_drift_repositories: [%s]\nprogram_drift_spec_root: %s/specs\nprogram_drift_home: %s\n' "$repo" "$repo" "$drift_home" >"$tracked"
rm -f "$mlocal"
cfg doctor --program drift
expect_eq "REQ-A1.9: drift: no rules and no local layer is clean" "clean"

mc_run mc-rules.sh add drift --text "Mission control hands over to a fresh successor every time its context passes 40%." --subject handover --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Keep mission_control_stall_window at 10m." --subject stall --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Hand over the program notes at the end of each week, with 3 sections." --subject notes --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_rc "REQ-A1.9: drift: doctor with rules reports findings as data" 0
expect_out "REQ-A1.9: drift: a rule naming 40% for the handover knob, left at the shipped 70, is a finding with rule, knob and effective value" "rule-knob${tab}r-1${tab}mission_control_handover_context${tab}40${tab}70${tab}core"
expect_out "REQ-A1.9: drift: the finding says it in plain words" "says 40 but mission_control_handover_context is 70"
expect_no_out "REQ-A1.9: drift: a rule naming the knob's own shipped value is no finding" "rule-knob${tab}r-2"
expect_no_out "REQ-A1.9: drift: a rule that merely says hand over, with no context or percent, is no finding" "rule-knob${tab}r-3"
printf 'mission_control_handover_context: 40\n' >"$adopter/planwright.yml"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: once the knob matches the rule the finding is gone" "rule-knob${tab}r-1"
printf 'mission_control_handover_context: 55\n' >"$adopter/planwright.yml"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a knob moved to another value is named with its layer" "rule-knob${tab}r-1${tab}mission_control_handover_context${tab}40${tab}55${tab}adopter"
rm -f "$adopter/planwright.yml"
mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 30m." --subject stall --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a rule naming a knob and a value that differ is a finding" "rule-knob${tab}r-4${tab}mission_control_stall_window${tab}30m${tab}10m${tab}core"

mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 10." --subject stall --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 15." --subject stall --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: a rule naming no unit that matches the knob's number is no finding" "rule-knob${tab}r-5"
expect_out "REQ-A1.9: drift: a rule naming no unit is compared with the knob's number alone" "rule-knob${tab}r-6${tab}mission_control_stall_window${tab}15${tab}10m${tab}core"

cat >"$mlocal" <<'EOT'
# a dated bump, drop it later
fleet_max_parallel_units: 10 # until 2020-11-01
mission_control_tick_cadence: 5m
# interim value while the runner is rebuilt
mission_control_stall_window: 20m
# temporary: reviewed on 2999-01-01
mission_control_repeat_window: 2h
# ordinary note about cadence
mission_control_panel_refresh: 30s
mission_control_event_retention: 14d # keep 14 days
# dropped until 2020-02-02: mission_control_audit_idle_after
EOT
local_before=$(sum "$mlocal")
cfg doctor --program drift
expect_rc "REQ-A1.9: drift: doctor over a local layer with dated overrides reports" 0
expect_out "REQ-A1.9: drift: a trailing comment with a past date is a finding naming file, knob, comment and effective value" "temporary${tab}$mlocal${tab}fleet_max_parallel_units${tab}past date 2020-11-01${tab}a dated bump, drop it later; until 2020-11-01${tab}10"
expect_out "REQ-A1.9: drift: a comment above the knob saying interim is a finding" "temporary${tab}$mlocal${tab}mission_control_stall_window${tab}marker interim${tab}interim value while the runner is rebuilt${tab}20m"
expect_out "REQ-A1.9: drift: a comment naming a knob that was dropped until a past date is a finding" "temporary${tab}$mlocal${tab}mission_control_audit_idle_after${tab}past date 2020-02-02"
expect_no_out "REQ-A1.9: drift: a temporary note whose date is still ahead is no finding" "temporary${tab}$mlocal${tab}mission_control_repeat_window"
expect_no_out "REQ-A1.9: drift: an ordinary value with an ordinary comment is no finding" "temporary${tab}$mlocal${tab}mission_control_panel_refresh"
expect_no_out "REQ-A1.9: drift: an ordinary trailing comment is no finding" "temporary${tab}$mlocal${tab}mission_control_event_retention"
expect_no_out "REQ-A1.9: drift: an uncommented value is no finding" "temporary${tab}$mlocal${tab}mission_control_tick_cadence"
expect_out "REQ-A1.9: drift: the finding explains itself" "review it; doctor never edits the file"
if [ "$(sum "$mlocal")" = "$local_before" ]; then ok "REQ-A1.9: drift: doctor leaves the local layer as it was"; else fail "drift: doctor changed the local layer"; fi
printf 'mission_control_stall_window: 20m # TEMPORARY, see ticket\n' >"$mlocal"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a marker word matches in any case" "marker temporary"
printf 'mission_control_stall_window: 20m # untilted and intermittent\nmission_control_tick_cadence: 5m # retemporary\n' >"$mlocal"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: a marker word inside another word is no finding" "temporary${tab}$mlocal"
printf '# adopter note: until 2020-03-03\nmission_control_stall_window: 20m\n' >"$adopter/planwright.yml"
rm -f "$mlocal"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: the adopter layer file is scanned too" "temporary${tab}$adopter/planwright.yml${tab}mission_control_stall_window"
rm -f "$adopter/planwright.yml" "$mlocal"
printf 'mission_control_stall_window: 20m # interim\n' >"$mlocal"
chmod 000 "$mlocal"
cfg doctor --program drift
chmod 644 "$mlocal"
rm -f "$mlocal"
if [ "$(id -u)" -eq 0 ]; then ok "REQ-A1.9: drift: root reads any file, so the unreadable-layer case is skipped"; else expect_out "drift: an unreadable local layer is an unknown temporary check" "unknown${tab}temporary${tab}$mlocal cannot be read"; fi
tracked_save=$(cat "$tracked")
printf '# temporary until 2020-04-04\nmission_control_stall_window: 20m\n' >>"$tracked"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: the team-shared repo-tracked layer is not scanned" "temporary${tab}"
printf '%s\n' "$tracked_save" >"$tracked"

cfg doctor --program gamma
expect_rc "doctor on a program that is not configured" 3
cfg doctor
expect_rc "doctor without a program is a usage error" 2
PATH=$saved_path
export PATH
rm -rf "$sessions"
rm -f "$layer"

[ "$failures" -eq 0 ] || {
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
}
echo "all mc-config tests passed"
