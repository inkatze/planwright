#!/bin/bash
# Tests for the cadence result at consequential moments in
# scripts/mc-packet.sh (mission-control REQ-F1.15; D-31).
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
# One step covered, convergence a gap (the other points covered too).
printf '# format: 1\nhead\t%s\ncadence\taudited\t%s\ncadence\tgap\tconvergence\tincomplete\tno completion\n' "$head" "$head" >"$tmp/gap"
printf '# format: 1\nhead\t%s\ncadence\taudited\t%s\n' "$head" "$head" >"$tmp/clean"
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
  case $first in
    *convergence*pre-pr* | *pre-pr*convergence*) ok "REQ-F1.15: $moment: the first line names the covered step and the gap" ;;
    *) fail "REQ-F1.15: $moment: first line is '$first'" ;;
  esac
  expect_out "REQ-F1.15: $moment: guided carries the lesson" "Why it matters:"
  expect_out "REQ-F1.15: $moment: guided carries the recommendation" "Recommend:"
  packet "$tmp/gap" "$moment" --level standard
  expect_no_out "REQ-F1.15: $moment: standard has no lesson" "Why it matters:"
  expect_out "REQ-F1.15: $moment: standard has the recommendation" "Recommend:"
  packet "$tmp/gap" "$moment" --level expert
  expect_no_out "REQ-F1.15: $moment: expert has no lesson" "Why it matters:"
  expect_no_out "REQ-F1.15: $moment: expert has no recommendation" "Recommend:"
  case $(section_first) in *convergence*) ok "REQ-F1.15: $moment: expert still has the line" ;; *) fail "REQ-F1.15: $moment: expert lost the line" ;; esac
done

packet "$tmp/gap" ready-flip
expect_out "REQ-F1.13: no level means guided" "Why it matters:"
packet "$tmp/gap" ready-flip --level bold
expect_rc "an unknown level is refused" 2
packet "$tmp/gap" no-such-moment --level guided
expect_rc "an unknown moment is refused" 2

packet "$tmp/unaud" ready-flip --level guided
expect_out "an unaudited result names its reason" "not planwright-run"
expect_no_out "and carries no lesson" "Why it matters:"
expect_no_out "and no recommendation" "Recommend:"

packet "$tmp/clean" ready-flip --level guided
expect_out "an audited clean result says so" "all covered"
expect_no_out "a clean result carries no lesson" "Why it matters:"

printf 'merge-intent\tguided\tlesson\tonly this\n' >"$tmp/lessons"
packet "$tmp/gap" ready-flip --level guided --lessons "$tmp/lessons"
expect_rc "a moment and level with no text still assembles" 0
case $(section_first) in *convergence*) ok "and still prints the line" ;; *) fail "the line is missing with no lesson text" ;; esac
expect_no_out "and prints no text" "Why it matters:"

# The gate result is identical at every level; no option is marked.
gate() { printf '%s\n' "$OUT" | awk '/^Readiness$/ { on = 1; getline; getline; print; exit }'; }
packet "$tmp/gap" ready-flip --level guided
g1=$(gate)
packet "$tmp/gap" ready-flip --level expert
g2=$(gate)
if [ "$g1" = "ready${tab}$head" ] && [ "$g1" = "$g2" ]; then ok "REQ-F1.15: the gate result is identical at every level"; else fail "the gate line differs: '$g1' vs '$g2'"; fi
packet "$tmp/gap" ready-flip --level guided
expect_no_out "no option carries a default marker" "default"
expect_no_out "no option is pre-selected" "(Recommended)"

# Without a moment the packet is unchanged: the walk is the first line.
mc_run mc-packet.sh assemble --program alpha --unit web#7 --readiness "$tmp/readiness"
if [ "$(section_first)" = "ready${tab}$head" ]; then ok "no moment, no cadence line"; else fail "a packet with no moment changed"; fi

# The rule appears once in the skill.
n=$(grep -c -F 'cadence result' "$repo_root/skills/mission-control/SKILL.md")
if [ "$n" -eq 1 ]; then ok "REQ-F1.15: the skill names the rule once"; else fail "the skill names the rule $n times"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-packet: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-packet: all passed"
