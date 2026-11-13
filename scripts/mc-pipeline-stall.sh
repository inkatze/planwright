#!/usr/bin/env bash
# mc-pipeline-stall.sh — the stalled-pipeline alarm: a program with open draft
# pull requests and no ready flip for a window raises a failure to its
# mission control, naming why each draft is held.
#
# `mc-pipeline-stall.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-pipeline-stall
MAX_READS=40
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

usage() {
  mc_usage_fail "usage: mc-pipeline-stall.sh [watch] [--program <p>] [--now <epoch>]"
}

help_text() {
  cat <<'HELP'
mc-pipeline-stall.sh — the stalled-pipeline alarm: a program with open draft
pull requests and no ready flip for mission_control_stalled_pipeline_window
raises a `pipeline-stalled` event (a failure, so it wakes mission control and
reaches the operator), naming why each draft is held. It changes nothing it
reads.

THE CLOCK. The watcher reads the program's code-state snapshot and keeps
<runtime>/pipeline-stall.tsv: `since<TAB><epoch>`, `raised<TAB><epoch>` and
one `draft<TAB><owner/name>#<n>` per draft the last pass saw. The window
runs from the later of the first pass that saw an open draft and the last
flip it saw, a flip being a draft of the last pass that the snapshot now
lists as not a draft. A pass that sees no draft forgets the clock, so drafts
back after a quiet stretch start a fresh window. Inside the window it
raises nothing.

THE EVENT. Past the window it raises one event, subject pipeline-stalled,
whose text opens with the draft count and the window and then names each
draft's top reason, in this order:
  merge conflict           the snapshot reads it CONFLICTING
  red check <name>         a check on its head finished red
  no CI on its head        no check context at all
  checks pending           a check still running
  flip-gate refusal <w>    the readiness walk refused it: <w> is `ready-guard`
                           for the guard, else `readiness` and the first
                           refusal
  launch hold (usage)      the draft is otherwise clear and a usage hold
                           (scripts/mc-usage.sh held) keeps launches back
  launch hold (host bound) the same, the host-wide bound at its limit
  awaiting a flip          otherwise clear and nothing holds launches
  evidence unread          its readiness evidence could not be collected
The reasons come from scripts/mc-readiness.sh (collect, then walk) over at
most 40 drafts a pass; the rest are counted. The event is raised again each
window while the stall lasts, never on every pass; it is recorded as raised
only once the store holds it, so a refused event is retried.

Usage:
  mc-pipeline-stall.sh [watch] [--program <p>] [--now <epoch>]
      the watcher (also a run with no arguments under the runner, the
      program from PLANWRIGHT_MC_PROGRAM), printing
        raised<TAB>pipeline-stalled<TAB><draft count>
      when it raises. A program with no code-state snapshot, none taken
      yet, or one past twice its cadence raises nothing.

Exit codes: 0 done; 1 a failed read, store, knob or event; 2 usage; 3 the
program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
[ "$verb" = watch ] || usage
program=""
NOW=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now)
          mc_valid_uint "$2" || mc_usage_fail "--now takes an epoch"
          NOW=$2
          ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
[ -n "$NOW" ] || NOW=$(date +%s)
mc_require_program "$program"

ks=$(mc_knob mission_control_stalled_pipeline_window mc_parse_cadence) || exit 1
WINDOW=$(mc_seconds "$ks") || mc_fail "mission_control_stalled_pipeline_window is not a cadence"

mc_code_state "$program" "$NOW"
case $? in
  0) ;;
  1) mc_fail "the source map of program $program does not resolve" ;;
  2) mc_fail "the $MC_CS_SOURCE snapshot cannot be read" ;;
  *) exit 0 ;;
esac
runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
state="$runtime/pipeline-stall.tsv"

# Rows of the snapshot: slug#n for each draft, and for each pull request that
# is not one.
drafts=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "true" { print $2 "#" $3 }')
ready=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "false" { print $2 "#" $3 }')

if [ -z "$drafts" ]; then
  rm -f "$state"
  exit 0
fi

since=""
raised=""
prev=""
if [ -f "$state" ]; then
  since=$(awk -F '\t' '$1 == "since" { print $2; exit }' "$state")
  raised=$(awk -F '\t' '$1 == "raised" { print $2; exit }' "$state")
  prev=$(awk -F '\t' '$1 == "draft" { print $2 }' "$state")
fi
mc_valid_uint "$since" && [ "$since" -le "$NOW" ] || since=""
mc_valid_uint "$raised" && [ "$raised" -le "$NOW" ] || raised=""

flipped=$(printf '%s\n' "$prev" | R=$ready awk 'BEGIN { n = split(ENVIRON["R"], r, "\n"); for (i = 1; i <= n; i++) if (r[i] != "") up[r[i]] = 1 } ($0 in up) { print; exit }')
if [ -n "$flipped" ] || [ -z "$since" ]; then
  since=$NOW
  raised=""
fi

save() {
  {
    printf 'since\t%s\n' "$since"
    [ -z "$raised" ] || printf 'raised\t%s\n' "$raised"
    printf '%s\n' "$drafts" | awk 'NF { print "draft\t" $0 }'
  } | mc_write "$state" || mc_fail "cannot write $state"
}
save

[ $((NOW - since)) -ge "$WINDOW" ] || exit 0
[ -z "$raised" ] || [ $((NOW - raised)) -ge "$WINDOW" ] || exit 0

# launch_hold: usage or host bound, or nothing.
launch_hold() {
  if /bin/bash "$script_dir/mc-usage.sh" held --program "$program" >/dev/null 2>&1; then
    printf 'usage\n'
    return 0
  fi
  lh_row=$(/bin/bash "$script_dir/mission-control-launch.sh" bound 2>/dev/null) || return 0
  printf '%s\n' "$lh_row" | awk -F '\t' '$1 == "bound" && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 + 0 >= $2 + 0 { print "host bound" }'
}
HOLD=$(launch_hold)

evf="$runtime/pipeline-stall.evidence"
errf="$runtime/pipeline-stall.err"
trap 'rm -f "$evf" "$errf"' EXIT

# reason <owner/name> <n> <mergeable> <checks>: the draft's top reason.
reason() {
  case $3 in
    CONFLICTING)
      printf 'merge conflict\n'
      return 0
      ;;
  esac
  if ! /bin/bash "$script_dir/mc-readiness.sh" collect --program "$program" --repo "$1" --pr "$2" --out "$evf" >/dev/null 2>"$errf"; then
    if [ "$4" = NONE ]; then
      printf 'no CI on its head\n'
    else
      printf 'evidence unread\n'
    fi
    return 0
  fi
  r_red=$(awk -F '\t' '$1 == "check" && $3 != "SUCCESS" && $3 != "NEUTRAL" && $3 != "SKIPPED" && $3 != "PENDING" && $3 != "QUEUED" && $3 != "IN_PROGRESS" { print $2; exit }' "$evf")
  if [ -n "$r_red" ]; then
    printf 'red check %s\n' "$(printf '%s' "$r_red" | tr '\t\n\r' '   ' | mc_clean_text)"
    return 0
  fi
  if ! awk -F '\t' '$1 == "check" { f = 1 } END { exit !f }' "$evf"; then
    printf 'no CI on its head\n'
    return 0
  fi
  if awk -F '\t' '$1 == "check" && ($3 == "PENDING" || $3 == "QUEUED" || $3 == "IN_PROGRESS") { f = 1 } END { exit !f }' "$evf"; then
    printf 'checks pending\n'
    return 0
  fi
  r_walk=$(/bin/bash "$script_dir/mc-readiness.sh" walk --program "$program" --evidence "$evf" 2>/dev/null)
  case $? in
    0)
      if [ -n "$HOLD" ]; then printf 'launch hold (%s)\n' "$HOLD"; else printf 'awaiting a flip\n'; fi
      return 0
      ;;
    4) ;;
    *)
      printf 'evidence unread\n'
      return 0
      ;;
  esac
  r_fail=$(printf '%s\n' "$r_walk" | awk -F '\t' '$1 == "fail" { print $2 "\t" $3 }')
  r_guard=$(printf '%s\n' "$r_fail" | awk -F '\t' '$1 == "guard" { print $2; exit }')
  if [ -n "$r_guard" ]; then
    printf 'flip-gate refusal ready-guard\n'
  else
    printf 'flip-gate refusal readiness: %s\n' "$(printf '%s\n' "$r_fail" | awk -F '\t' 'NR == 1 { print $1 ": " $2 }' | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-60)"
  fi
}

count=0
read_n=0
skipped=0
lines=""
while IFS='	' read -r p_slug p_n p_mergeable p_checks; do
  [ -n "$p_slug" ] || continue
  count=$((count + 1))
  if [ "$read_n" -ge "$MAX_READS" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  read_n=$((read_n + 1))
  lines="${lines}$p_slug#$p_n $(reason "$p_slug" "$p_n" "$p_mergeable" "$p_checks"); "
done <<EOF
$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "true" { print $2 "\t" $3 "\t" $6 "\t" $9 }')
EOF
[ "$skipped" -eq 0 ] || lines="${lines}+$skipped more unread; "

noun=drafts
[ "$count" -ne 1 ] || noun=draft
head_text="$count $noun, no ready flip in $ks: "
text=$(printf '%s%s' "$head_text" "$lines" | sed 's/; $//' | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-500)
mc_event emit --program "$program" --now "$NOW" -- pipeline-stalled pipeline-stalled "$text" >/dev/null || mc_fail "the pipeline-stalled event was refused"
raised=$NOW
save
printf 'raised\tpipeline-stalled\t%s\n' "$count"
