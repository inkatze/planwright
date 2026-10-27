#!/bin/bash
# Tests for scripts/mc-decide.sh — the decided-by-mission-control record and
# its reasons grammar, the calibration ledger and its hit rate, the noted
# repeats the proposal detector reads, and the interruption and settled-share
# measures (mission-control REQ-F1.8, REQ-F1.9, REQ-M1.8).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-decide.sh
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

[ -f "$repo_root/scripts/mc-decide.sh" ] || {
  echo "FAIL: scripts/mc-decide.sh missing" >&2
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
decide() { mc_run mc-decide.sh "$@"; }
field() { printf '%s\n' "$1" | cut -f "$2"; }
# ledger_row <class>: the ledger line for a class, from the last OUT.
ledger_row() { printf '%s\n' "$OUT" | awk -F '\t' -v c="$1" '$1 == "class" && $2 == c'; }
# seg_of <entry id>: the segment file the entry was appended to, read from
# the id so a run crossing a month boundary reads the right one.
seg_of() {
  so=${1#*-}
  so=${so%%-*}
  printf '%s/%s-%s-%s.log\n' "$kb" "${1%%-*}" "${so%??}" "${so#????}"
}

# ---------------------------------------------------------------------------
# REQ-F1.8: a decision the record settles is taken and logged with grounds.
# ---------------------------------------------------------------------------
decide decide --program alpha --class auto-applicable --subject "Stale worktree" \
  --act "reclaimed the merged worker's worktree" --grounds "PR merged, nothing unpushed" --rule r-1
expect_rc "a settled decision is taken" 0
expect_out "it is reported as decided" "decided${tab}decisions-"
d1=$(field "$OUT" 2)
seg=$(cat "$(seg_of "$d1")")
case $seg in
  *"$d1${tab}"*"${tab}Stale worktree${tab}reclaimed the merged worker's worktree${tab}-${tab}settled auto-applicable r-1: PR merged, nothing unpushed${tab}"*)
    ok "the log carries the decided-by-mission-control grounds: reason, class, rules, text"
    ;;
  *) fail "the decisions log lacks the settled entry: $seg" ;;
esac

for r in human-gate fork hard-disqualifier reserved-proposal; do
  decide decide --program alpha --route "$r" --subject "Gate $r" --act "would mark the PR ready" --grounds "owed to the operator"
  expect_rc "a $r decision is queued, not taken" 0
  expect_out "it is reported as an ask with its reason ($r)" "ask${tab}$r${tab}decisions-"
  q1=$(field "$OUT" 3)
done
case $(cat "$(seg_of "$q1")") in
  *"${tab}human-gate - -: owed to the operator${tab}"*) ok "a queued decision is logged with its reason" ;;
  *) fail "the queued decision's reason is not in the log" ;;
esac

decide decide --program alpha --route merge --subject s --act a --grounds g
expect_rc "an unknown route is refused" 2
expect_err "the route grammar is named" "human-gate"
decide decide --program alpha --class bold --subject s --act a --grounds g
expect_rc "an unknown class is refused" 2
expect_err "the class grammar is named" "auto-applicable"
decide decide --program alpha --subject s --act a --grounds g
expect_rc "a decision with neither class nor route is refused" 2
decide decide --program alpha --class hygiene --subject s --act a --grounds g --rule "r 1"
expect_rc "a malformed rule id is refused" 2
decide decide --program alpha --class hygiene --subject s --act a --grounds "two: colons"
expect_rc "grounds may carry a colon" 0

# A shadow duty decides into its would-have log and raises nothing.
decide decide --program alpha --class hygiene --duty gamma-duty --subject "Shadow" --act "would reclaim" --grounds "dry run"
expect_rc "a shadow duty's decision is accepted" 0
expect_out "it is written as a would-have entry" "would-have${tab}would-have-"
if grep -q "${tab}Shadow${tab}" "$(seg_of "$q1")"; then
  fail "a shadow duty's decision reached the decisions log"
else
  ok "a shadow duty's decision stays out of the decisions log"
fi
mc_run mc-event.sh list --program alpha
expect_rc "the attention store reads" 0
expect_eq "a shadow duty's decision raises nothing" ""
decide decide --program alpha --class hygiene --duty beta-duty --subject s --act a --grounds g
expect_rc "a decision for a duty that is off is refused" 1

# ---------------------------------------------------------------------------
# REQ-F1.9: a revoke lowers its class to ask-first; confirmations restore it.
# ---------------------------------------------------------------------------
decide ledger --program alpha
expect_rc "the ledger reads" 0
row=$(ledger_row auto-applicable)
if [ "$(field "$row" 3)" = autonomous ]; then ok "a class with no revoke is autonomous"; else fail "unexpected state: $row"; fi
if [ "$(field "$row" 7)" = 100 ]; then ok "an unrevoked class has a full hit rate"; else fail "unexpected hit rate: $row"; fi
row=$(ledger_row needs-sign-off)
if [ "$(field "$row" 7)" = - ]; then ok "a class with no decision has no hit rate"; else fail "unexpected hit rate: $row"; fi

decide revoke --program alpha "$d1" --grounds "the worktree held a draft"
expect_rc "the operator's revoke is recorded" 0
decide revoke --program alpha "$d1"
expect_rc "a decision is revoked once" 1
decide revoke --program alpha decisions-190001-1
expect_rc "a revoke naming no decision is refused" 1
decide revoke --program alpha "decisions-1$(printf '\033')[31m-1"
expect_rc "an id outside the grammar is refused before any lookup" 2
case $ERR in
  *"$(printf '\033')"*) fail "the refusal echoed an escape byte" ;;
  *) ok "the refusal carries no escape byte" ;;
esac
decide ledger --program alpha
row=$(ledger_row auto-applicable)
if [ "$(field "$row" 3)" = ask-first ]; then ok "a revoke lowers the class to ask-first"; else fail "the class was not lowered: $row"; fi
if [ "$(field "$row" 5)" = 1 ] && [ "$(field "$row" 7)" = 0 ]; then
  ok "the hit rate counts the revoke"
else
  fail "unexpected revoke count or hit rate: $row"
fi

decide decide --program alpha --class auto-applicable --subject "Stale worktree 2" --act "reclaim" --grounds "PR merged"
expect_rc "a decision in a lowered class still records" 0
expect_out "a lowered class asks first" "ask${tab}ask-first${tab}decisions-"
a1=$(field "$OUT" 3)
decide decide --program alpha --class agent-resolvable --subject "Other class" --act "fix" --grounds "tests green"
expect_out "a revoke lowers only its own class" "decided${tab}"

restore=$(awk -F ': ' '$1 == "mission_control_calibration_restore" { print $2 }' "$repo_root/config/defaults.yml")
case $restore in
  "" | *[!0-9]*) fail "mission_control_calibration_restore has no integer default" ;;
esac
printf '%s\n' "mission_control_calibration_restore: 2" >>"$tracked"
decide confirm --program alpha "$a1"
expect_rc "a confirmation is recorded" 0
decide confirm --program alpha "$a1"
expect_rc "a decision is confirmed once" 1
decide ledger --program alpha
row=$(ledger_row auto-applicable)
if [ "$(field "$row" 3)" = ask-first ] && [ "$(field "$row" 6)" = 1 ]; then
  ok "one confirmation short of the run keeps ask-first"
else
  fail "unexpected state after one confirmation: $row"
fi
decide decide --program alpha --class auto-applicable --subject "Stale worktree 3" --act "reclaim" --grounds "PR merged"
a2=$(field "$OUT" 3)
decide confirm --program alpha "$a2"
decide ledger --program alpha
row=$(ledger_row auto-applicable)
if [ "$(field "$row" 3)" = autonomous ]; then ok "the configured run of confirmations restores the class"; else fail "the class was not restored: $row"; fi
decide decide --program alpha --class auto-applicable --subject "Stale worktree 4" --act "reclaim" --grounds "PR merged"
expect_out "a restored class decides again" "decided${tab}"

decide revoke --program alpha "$a2"
expect_rc "an asked decision is not revocable as a self-decision" 1
decide confirm --program alpha "$d1"
expect_rc "a revoked decision cannot be confirmed" 1

# ---------------------------------------------------------------------------
# The noted repeats the proposal detector reads.
# ---------------------------------------------------------------------------
decide note --program alpha --shape correction --subject "Ready flips" --text "stop flipping without the walk"
expect_rc "a correction is noted" 0
expect_out "the note prints its entry id" "noted${tab}decisions-"
decide note --program alpha --shape manual --subject "Polish" --text "ran polish by hand" --target pr-opened
expect_rc "a manual step after an event is noted" 0
decide note --program alpha --shape manual --subject "Polish" --text "ran polish by hand"
expect_rc "a manual step names its event" 2
decide note --program alpha --shape habit --subject s --text t
expect_rc "an unknown shape is refused" 2
decide note --program alpha --shape correction --subject s
expect_rc "a note without its text is refused" 2
expect_err "the missing flag is the one named" "--text"

# ---------------------------------------------------------------------------
# REQ-M1.8: interruptions per hour and the settled share, from the log.
# ---------------------------------------------------------------------------
seg_write decisions 2026-01 \
  "decisions-202601-1${tab}2026-01-10T08:00:00Z${tab}a${tab}act${tab}-${tab}settled hygiene -: g${tab}none${tab}-" \
  "decisions-202601-2${tab}2026-01-10T09:00:00Z${tab}b${tab}act${tab}-${tab}settled hygiene -: g${tab}none${tab}-" \
  "decisions-202601-3${tab}2026-01-10T10:00:00Z${tab}c${tab}act${tab}-${tab}settled auto-applicable -: g${tab}none${tab}-" \
  "decisions-202601-4${tab}2026-01-10T11:00:00Z${tab}d${tab}act${tab}-${tab}human-gate - -: g${tab}none${tab}-" \
  "decisions-202601-5${tab}2026-01-10T11:30:00Z${tab}e${tab}act${tab}-${tab}correction - -: noted${tab}none${tab}-" \
  "decisions-202601-6${tab}2026-01-09T01:00:00Z${tab}f${tab}act${tab}-${tab}fork - -: g${tab}none${tab}-"
now=$(iso_epoch 2026-01-10T12:00:00Z)
decide measures --program alpha --now "$now" --window 4h
expect_rc "the measures compute" 0
expect_out "the window is reported in seconds" "window${tab}14400"
expect_out "only decisions inside the window count" "decisions${tab}4"
expect_out "the interruptions are counted" "interruptions${tab}1"
expect_out "interruptions per hour divide by the window" "interruptions-per-hour${tab}0.25"
expect_out "the settled share is the settled part of the decisions" "settled-share${tab}75"
decide measures --program alpha --now "$now" --window 1s
expect_rc "an empty window computes" 0
expect_out "an empty window has no settled share" "settled-share${tab}-"
decide measures --program alpha --now "$now" --window soon
expect_rc "a window that is not a cadence is refused" 2
printf '%s\n' "mission_control_measure_window: 2h" >>"$tracked"
decide measures --program alpha --now "$now"
expect_rc "the window defaults to its knob" 0
expect_out "the default window comes from the knob" "window${tab}7200"
sed 's/^mission_control_calibration_restore: .*/mission_control_calibration_restore: 0/' "$tracked" >"$tmp/t" && mv "$tmp/t" "$tracked"
decide ledger --program alpha
expect_rc "a restore count of zero is refused" 1

decide ledger --program nobody
expect_rc "an unconfigured program is not found" 3

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-decide tests passed"
