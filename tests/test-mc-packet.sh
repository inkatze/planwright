#!/bin/bash
# Tests for the cadence result at consequential moments in
# scripts/mc-packet.sh (mission-control REQ-F1.15).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-packet.sh
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-packet.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
EOF

head=$(printf 'a%.0s' $(seq 1 40))
printf 'ready\t%s\n' "$head" >"$tmp/readiness"
# One step covered, convergence a gap; the audit names only configured points.
printf '# format: 1\nhead\t%s\ncadence\taudited\t%s\ncadence\tcovered\tpre-pr\ncadence\tgap\tconvergence\tincomplete\t-\n' "$head" "$head" >"$tmp/gap"
printf '# format: 1\nhead\t%s\ncadence\taudited\t%s\ncadence\tcovered\tpre-ci\n' "$head" "$head" >"$tmp/clean"
gapline="Cadence: covered pre-pr; gap convergence (no completion record)"
printf '# format: 1\nhead\t%s\ncadence\tunaudited\tnot planwright-run\n' "$head" >"$tmp/unaud"

packet() { # packet <evidence> <moment> [extra...]
  pk_ev=$1
  pk_m=$2
  shift 2
  mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness" \
    --evidence "$pk_ev" --moment "$pk_m" "$@"
}
section_first() { printf '%s\n' "$OUT" | awk '$0 == "Readiness" { getline; print; exit }'; }

for moment in merge-recommendation ready-flip merge-intent; do
  packet "$tmp/gap" "$moment" --level guided
  expect_rc "REQ-F1.15: $moment assembles" 0
  first=$(section_first)
  if [ "$first" = "$gapline" ]; then ok "REQ-F1.15: $moment: the first line names the covered step and the gap"; else fail "REQ-F1.15: $moment: first line is '$first'"; fi
  expect_out "REQ-F1.15: $moment: guided carries the lesson" "Why it matters:"
  expect_out "REQ-F1.15: $moment: guided carries the recommendation" "Recommend:"
  packet "$tmp/gap" "$moment" --level standard
  expect_no_out "REQ-F1.15: $moment: standard has no lesson" "Why it matters:"
  expect_out "REQ-F1.15: $moment: standard has the recommendation" "Recommend:"
  if [ "$(section_first)" = "$gapline" ]; then ok "REQ-F1.15: $moment: standard still has the line"; else fail "REQ-F1.15: $moment: standard lost the line"; fi
  packet "$tmp/gap" "$moment" --level expert
  expect_no_out "REQ-F1.15: $moment: expert has no lesson" "Why it matters:"
  expect_no_out "REQ-F1.15: $moment: expert has no recommendation" "Recommend:"
  if [ "$(section_first)" = "$gapline" ]; then ok "REQ-F1.15: $moment: expert still has the line"; else fail "REQ-F1.15: $moment: expert lost the line"; fi
done

packet "$tmp/gap" ready-flip
expect_rc "REQ-F1.13: no level assembles" 0
expect_out "REQ-F1.13: no level means guided" "Why it matters:"
expect_out "REQ-F1.13: and carries guided's recommendation" "Recommend:"
if [ "$(section_first)" = "$gapline" ]; then ok "REQ-F1.13: and opens with the line"; else fail "REQ-F1.13: no level lost the line"; fi

# Each gap kind the audit prints is said with its step or head.
printf '# format: 1\ncadence\taudited\t%s\ncadence\tgap\tpre-ci\tmissing\tlint\ncadence\tgap\tpre-ci\tfailed\ttest:failed\ncadence\tgap\tpost-pr\tstale\t%s\ncadence\tgap\tconvergence\tmismatch\thead:polish\n' "$head" "$head" >"$tmp/kinds"
packet "$tmp/kinds" ready-flip --level expert
want="Cadence: covered none; gap pre-ci (lint is missing); pre-ci (test recorded failed); post-pr (completed only at $(printf '%.12s' "$head")); convergence (a record does not match its branch (head:polish))"
if [ "$(section_first)" = "$want" ]; then ok "each gap names its step or head"; else fail "the gap kinds read '$(section_first)'"; fi
# A record the step-record truth check refuses names the check, and one the
# session events contradict reads as its detail, in mc-readiness.sh's words.
printf '# format: 1\ncadence\taudited\t%s\ncadence\tgap\tconvergence\tunaudited\tpolish\ncadence\tgap\tpost-pr\tfault\t000003:post-pr:001 cubic-pr: start 2026-11-04T10:04:58Z is off\n' "$head" >"$tmp/truthkinds"
packet "$tmp/truthkinds" ready-flip --level expert
want="Cadence: covered none; gap convergence (polish fails the step-record truth check); post-pr (000003:post-pr:001 cubic-pr: start 2026-11-04T10:04:58Z is off)"
if [ "$(section_first)" = "$want" ]; then ok "an unaudited gap names the truth check and a fault gap reads as its detail"; else fail "the unaudited and fault gaps read '$(section_first)'"; fi
packet "$tmp/clean" ready-flip --level expert
if [ "$(section_first)" = "Cadence: all covered (pre-ci)" ]; then ok "only the points the audit names are covered"; else fail "a clean audit reads '$(section_first)'"; fi

printf '# format: 1\nscope\tspec-only\t%s\n' "$head" >"$tmp/speconly"
packet "$tmp/speconly" ready-flip --level guided
case $(section_first) in "Cadence: not required"*) ok "a spec-only pull request says the cadence is not required" ;; *) fail "a spec-only pull request reads '$(section_first)'" ;; esac
expect_no_out "and carries no lesson" "Why it matters:"
other=$(printf 'b%.0s' $(seq 1 40))
printf '# format: 1\nscope\tspec-only\t%s\n' "$other" >"$tmp/speconlystale"
packet "$tmp/speconlystale" ready-flip --level guided
case $(section_first) in "Cadence: not audited"*) ok "a spec-only row for another head is not taken as spec-only" ;; *) fail "a stale spec-only row reads '$(section_first)'" ;; esac

printf '# format: 1\ncadence\taudited\t%s\ncadence\tcovered\tpre-pr\n' "$other" >"$tmp/otherhead"
packet "$tmp/otherhead" ready-flip --level guided
case $(section_first) in "Cadence: not audited"*) ok "an audit at another head than the walk's is not audited" ;; *) fail "an audit at another head reads '$(section_first)'" ;; esac
packet "$tmp/gap" ready-flip --level bold
expect_rc "an unknown level is refused" 2
packet "$tmp/gap" no-such-moment --level guided
expect_rc "an unknown moment is refused" 2

mkdir "$tmp/evdir"
packet "$tmp/evdir" ready-flip --level guided
expect_rc "a directory as the evidence is refused" 2
expect_no_out "and assembles no packet" "Packet:"
for opt in --moment --evidence --level --lessons; do
  mc_run mc-packet.sh look --program alpha --unit web#7 --head "$head" "$opt" x
  expect_rc "look refuses $opt" 2
  mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness" "$opt" "$tmp/gap"
  [ "$opt" = --moment ] || expect_rc "assemble refuses $opt without --moment" 2
done

for lv in guided standard; do
  packet "$tmp/unaud" ready-flip --level "$lv"
  if [ "$(section_first)" = "Cadence: not audited: not planwright-run" ]; then ok "$lv: an unaudited result names its reason"; else fail "$lv: unaudited reads '$(section_first)'"; fi
  expect_no_out "$lv: and carries no lesson" "Why it matters:"
  expect_no_out "$lv: and no recommendation" "Recommend:"
done
printf '# format: 1\ncadence\tunaudited\tcheckout missing\ncadence\tgap\tpre-ci\tincomplete\tx\n' >"$tmp/unaudgap"
packet "$tmp/unaudgap" ready-flip --level guided
expect_no_out "an unaudited result with a stray gap row carries no lesson" "Why it matters:"
expect_no_out "nor a recommendation" "Recommend:"

packet "$tmp/clean" ready-flip --level guided
expect_out "an audited clean result says so" "all covered"
expect_no_out "a clean result carries no lesson" "Why it matters:"
printf '# format: 1\ncadence\taudited\t%s\nbodyline\tcadence\tgap\tx\n' "$head" >"$tmp/spoof"
packet "$tmp/spoof" ready-flip --level guided
expect_no_out "a body line shaped like a gap row carries no lesson" "Why it matters:"

printf 'merge-intent\tguided\tlesson\tonly this\n' >"$tmp/lessons"
packet "$tmp/gap" ready-flip --level guided --lessons "$tmp/lessons"
expect_rc "a moment and level with no text still assembles" 0
if [ "$(section_first)" = "$gapline" ]; then ok "and still prints the line"; else fail "the line is missing with no lesson text"; fi
expect_no_out "and prints no text" "Why it matters:"
packet "$tmp/gap" ready-flip --level standard --lessons "$tmp/lessons"
expect_rc "a level with no row at all still assembles" 0
if [ "$(section_first)" = "$gapline" ]; then ok "and still prints the line"; else fail "the line is missing for a level with no row"; fi
expect_no_out "and prints no recommendation" "Recommend:"

# The gate result and every other line are identical at every level; no
# option is marked.
printf 'not-ready\t%s\nfail\tcadence\tconvergence: no completion record\n' "$head" >"$tmp/notready"
for rd in readiness notready; do
  base=""
  for lv in guided standard expert; do
    mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/$rd" \
      --evidence "$tmp/gap" --moment ready-flip --level "$lv"
    rest=$(printf '%s\n' "$OUT" | grep -v -e '^Why it matters: ' -e '^Recommend: ')
    if [ -z "$base" ]; then base=$rest; elif [ "$rest" != "$base" ]; then fail "REQ-F1.15: $rd: $lv changes more than the lesson and recommendation"; fi
    expect_no_out "$rd: $lv: no option carries a default marker" "default"
    expect_no_out "$rd: $lv: no option is pre-selected" "(Recommended)"
  done
  case $base in *"$(cat "$tmp/$rd")"*) ok "REQ-F1.15: $rd: the gate result is identical at every level" ;; *) fail "REQ-F1.15: $rd: the walk is not carried whole" ;; esac
done

# Without a moment the packet is unchanged: the walk is the first line.
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness"
if [ "$(section_first)" = "ready${tab}$head" ]; then ok "no moment, no cadence line"; else fail "a packet with no moment changed"; fi

# The rule appears once in the skill.
# Joined into one line first, so a mention wrapped across lines still counts.
n=$(tr '\n' ' ' <"$repo_root/skills/mission-control/SKILL.md" | tr -s ' ' | grep -o -F 'cadence result' | wc -l | tr -d ' ')
if [ "$n" -eq 1 ]; then ok "REQ-F1.15: the skill names the rule once"; else fail "the skill names the rule $n times"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-packet: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-packet: all passed"
