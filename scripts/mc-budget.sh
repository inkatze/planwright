#!/usr/bin/env bash
# mc-budget.sh — a mission-control program's budget: its limits, what is in
# use against them, the headroom left and the degradation rung.
#
# The limits are mission_control_default_budget with the program's own
# budget map (scripts/mc-program.sh get <p> budget) laid over it key by key:
#   sessions        live sessions
#   polls_per_hour  source polls in the last hour, every snapshot-mode source
#                   counted together
#   context_steps   context steps
#   host_load       host load, percent of the host's processors
#   spend_ceiling   the highest watcher cost class armed (low, medium, high);
#                   spend_<duty> sets one duty's, the duty's hyphens written
#                   as underscores
# Any other key is refused, named.
#
# What is in use: sessions and context_steps as `record` last set them (0
# when never recorded) in <runtime>/in-use, polls from the poll log `poll`
# keeps (<runtime>/polls), host load as measured (the one-minute load
# average over the processor count) or as --load gives it. A store that
# exists but cannot be read fails the call, never counted as zero.
#
# The rung, lowest to highest; the highest that applies wins:
#   normal          every dimension below the ladder's throttle threshold
#   throttle        the most used dimension at or over throttle: every cadence
#                   doubles, at this rung and every one above it
#   pause-watchers  at or over pause_watchers: high-cost watchers stop
#   hold-dispatch   at or over hold_dispatch, or a quota hold
#                   (scripts/quota-hold.sh, the `limited` outcome): medium-cost
#                   watchers stop too, and no session or heavy work is admitted
#   handover        context steps at their limit: the session hands over
#   paused          the fleet daemon pause (scripts/fleet-daemon-gate.sh):
#                   nothing autonomous runs
# The thresholds are mission_control_budget_ladder's percents.
#
# Usage:
#   mc-budget.sh report --program <p> [--now <epoch>] [--load <pct>]
#       compute, write the budget file (<runtime>/budget) and print it:
#         format<TAB>1
#         program<TAB><p>
#         taken<TAB><epoch>
#         rung<TAB><rung><TAB><reason>
#         dimension<TAB><name><TAB><used><TAB><limit><TAB><headroom><TAB><pct>
#         spend<TAB>ceiling<TAB><class>
#         spend<TAB><duty><TAB><class>     one per duty with its own class
#   mc-budget.sh rung --program <p> [--now <epoch>] [--load <pct>]
#       the same computation; prints the rung alone
#   mc-budget.sh admit --program <p> session|heavy [--now <epoch>] [--load <pct>]
#       exit 0 printing `admitted`; exit 1 refused, printing
#       queued<TAB><reason>. Heavy work is scheduled by host load: it waits
#       while host load is at or over the throttle threshold, whatever the
#       session count
#   mc-budget.sh poll --program <p> <source> [--now <epoch>]
#       count one poll of <source> when the hour's polls are under the cap
#       (exit 0); at the cap nothing is counted (exit 4, printing capped)
#   mc-budget.sh record --program <p> sessions|context_steps <n>
#       set what is in use
#   mc-budget.sh ceiling --program <p> <duty>
#       the duty's spend ceiling
#   mc-budget.sh read --program <p>
#       print the budget file as last written; refuses one whose format this
#       script does not know, naming it
#
# Exit codes: 0 done; 1 refused (admit), an invalid budget or ladder, or a
# store that cannot be read or written; 2 usage; 3 the program is not
# configured; 4 capped (poll).
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-budget
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

DIMENSIONS="sessions polls_per_hour context_steps host_load"

usage() {
  mc_usage_fail "usage: mc-budget.sh report|rung --program <p> [--now <epoch>] [--load <pct>] | admit --program <p> session|heavy [--now <epoch>] [--load <pct>] | poll --program <p> <source> [--now <epoch>] | record --program <p> sessions|context_steps <n> | ceiling --program <p> <duty> | read --program <p>"
}

[ $# -ge 1 ] || usage
verb=$1
shift
program=""
now=""
load=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --load)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
        --load) load=$2 ;;
      esac
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
[ -z "$load" ] || mc_valid_uint "$load" || mc_usage_fail "--load takes a whole percent"
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"

valid_class() {
  case $1 in
    low | medium | high) return 0 ;;
  esac
  return 1
}

# load_limits: LIMITS, the default budget with the program's map laid over
# it, every key checked.
load_limits() {
  ll_default=$(mc_knob mission_control_default_budget mc_map) || exit 1
  ll_own=$(/bin/bash "$script_dir/mc-program.sh" get "$program" budget) || exit 1
  LIMITS=$(printf '%s\n%s\n' "$ll_default" "$ll_own" | awk -F '\t' '
    NF == 2 { if (!($1 in v)) o[++n] = $1; v[$1] = $2 }
    END { for (i = 1; i <= n; i++) print o[i] "\t" v[o[i]] }')
  while IFS='	' read -r ll_k ll_v; do
    [ -n "$ll_k" ] || continue
    case " $DIMENSIONS " in
      *" $ll_k "*)
        mc_valid_uint "$ll_v" && [ "$ll_v" -gt 0 ] \
          || mc_fail "budget: $ll_k: '$(sanitize_printable "$ll_v")' is not a positive whole number"
        continue
        ;;
    esac
    case $ll_k in
      spend_ceiling | spend_*)
        valid_class "$ll_v" || mc_fail "budget: $ll_k: '$(sanitize_printable "$ll_v")' is not low, medium or high"
        ;;
      *) mc_fail "budget: unknown key '$(sanitize_printable "$ll_k")'" ;;
    esac
  done <<EOF
$LIMITS
EOF
  for ll_d in $DIMENSIONS spend_ceiling; do
    [ -n "$(mc_lookup "$ll_d" "$LIMITS")" ] || mc_fail "budget: $ll_d is not set (broken install)"
  done
}

load_ladder() {
  LADDER=$(mc_knob mission_control_budget_ladder mc_map) || exit 1
  for la_k in throttle pause_watchers hold_dispatch; do
    la_v=$(mc_lookup "$la_k" "$LADDER")
    mc_valid_uint "$la_v" && [ "$la_v" -gt 0 ] \
      || mc_fail "mission_control_budget_ladder: $la_k: '$(sanitize_printable "$la_v")' is not a positive percent"
  done
  [ "$(mc_lookup throttle "$LADDER")" -le "$(mc_lookup pause_watchers "$LADDER")" ] \
    && [ "$(mc_lookup pause_watchers "$LADDER")" -le "$(mc_lookup hold_dispatch "$LADDER")" ] \
    || mc_fail "mission_control_budget_ladder: the thresholds must not decrease from throttle to hold_dispatch"
}

in_use_of() {
  if [ -e "$runtime/in-use" ]; then
    iu_v=$(K=$1 awk -F '\t' '$1 == ENVIRON["K"] { v = $2 } END { print v }' "$runtime/in-use") \
      || mc_fail "cannot read the in-use record"
    if mc_valid_uint "$iu_v"; then
      printf '%s\n' "$iu_v"
      return 0
    fi
  fi
  printf '0\n'
}

# recent_polls: the poll log's lines inside the hour ending now; the one
# predicate the cap and the report both count with.
recent_polls() {
  [ -e "$runtime/polls" ] || return 0
  N=$NOW awk -F '\t' '$1 ~ /^[0-9]+$/ && $1 > ENVIRON["N"] - 3600 && $1 <= ENVIRON["N"] + 0' "$runtime/polls" \
    || mc_fail "cannot read the poll log"
}

host_load() {
  if [ -n "$load" ]; then
    printf '%s\n' "$load"
    return 0
  fi
  hl_cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
  mc_valid_uint "$hl_cpus" && [ "$hl_cpus" -gt 0 ] || hl_cpus=1
  if [ -r /proc/loadavg ]; then
    hl_avg=$(awk '{ print $1 }' /proc/loadavg)
  else
    hl_avg=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')
  fi
  case $hl_avg in
    "" | *[!0-9.]*) hl_avg=0 ;;
  esac
  A=$hl_avg C=$hl_cpus awk 'BEGIN { printf "%d\n", ENVIRON["A"] * 100 / ENVIRON["C"] }'
}

quota_held() {
  qh_out=$(/bin/sh "$script_dir/quota-hold.sh" status 2>/dev/null) || return 0
  printf '%s\n' "$qh_out" | awk -F '\t' '$1 == "vendor" && $3 == "held" { f = 1 } END { exit !f }'
}

# compute: sets RUNG, REASON, DIMS (name<TAB>used<TAB>limit<TAB>headroom<TAB>pct
# lines), LIMITS, LADDER and HOSTPCT.
compute() {
  load_limits
  load_ladder
  DIMS=""
  top_pct=0
  top_dim=""
  HOSTPCT=0
  steps_used=0
  for d in $DIMENSIONS; do
    case $d in
      sessions | context_steps) used=$(in_use_of "$d") || exit 1 ;;
      polls_per_hour)
        recent=$(recent_polls) || exit 1
        used=$(printf '%s' "$recent" | awk 'END { print NR }')
        ;;
      host_load) used=$(host_load) ;;
    esac
    limit=$(mc_lookup "$d" "$LIMITS")
    headroom=$((limit - used))
    [ "$headroom" -ge 0 ] || headroom=0
    pct=$((used * 100 / limit))
    [ "$d" != host_load ] || HOSTPCT=$pct
    [ "$d" != context_steps ] || steps_used=$used
    DIMS="$DIMS$d	$used	$limit	$headroom	$pct
"
    if [ "$pct" -gt "$top_pct" ]; then
      top_pct=$pct
      top_dim=$d
    fi
  done
  RUNG=normal
  REASON="every dimension under the throttle threshold"
  if [ "$top_pct" -ge "$(mc_lookup hold_dispatch "$LADDER")" ]; then
    RUNG=hold-dispatch
  elif [ "$top_pct" -ge "$(mc_lookup pause_watchers "$LADDER")" ]; then
    RUNG=pause-watchers
  elif [ "$top_pct" -ge "$(mc_lookup throttle "$LADDER")" ]; then
    RUNG=throttle
  fi
  [ "$RUNG" = normal ] || REASON="$top_dim at $top_pct%"
  if [ "$RUNG" != hold-dispatch ] && quota_held; then
    RUNG=hold-dispatch
    REASON="a quota hold (limited)"
  fi
  if [ "$steps_used" -ge "$(mc_lookup context_steps "$LIMITS")" ]; then
    RUNG=handover
    REASON="context steps at their limit"
  fi
  if ! mc_gate mc-budget; then
    RUNG=paused
    REASON="the fleet daemon pause"
    [ "$MC_GATE_RC" -eq 1 ] || REASON="the fleet daemon gate is blocked (exit $MC_GATE_RC)"
  fi
}

render() {
  printf 'format\t%s\n' "$MC_FORMAT"
  printf 'program\t%s\n' "$program"
  printf 'taken\t%s\n' "$NOW"
  printf 'rung\t%s\t%s\n' "$RUNG" "$REASON"
  printf '%s' "$DIMS" | while IFS= read -r line; do
    [ -n "$line" ] && printf 'dimension\t%s\n' "$line"
  done
  printf 'spend\tceiling\t%s\n' "$(mc_lookup spend_ceiling "$LIMITS")"
  printf '%s\n' "$LIMITS" | awk -F '\t' '$1 ~ /^spend_/ && $1 != "spend_ceiling" {
    d = substr($1, 7); gsub(/_/, "-", d); print "spend\t" d "\t" $2 }'
}

case $verb in
  report)
    [ "${#args[@]}" -eq 0 ] || usage
    compute
    render | mc_write "$runtime/budget" || mc_fail "cannot write the budget file"
    cat "$runtime/budget"
    ;;
  rung)
    [ "${#args[@]}" -eq 0 ] || usage
    compute
    printf '%s\n' "$RUNG"
    ;;
  read)
    [ "${#args[@]}" -eq 0 ] || usage
    [ -f "$runtime/budget" ] || mc_fail "no budget file for '$program' yet (run report)"
    mc_format_ok "$runtime/budget" || mc_fail "budget file: format: unknown format"
    mc_clean <"$runtime/budget"
    ;;
  admit)
    [ "${#args[@]}" -eq 1 ] || usage
    case ${args[0]} in
      session | heavy) ;;
      *) usage ;;
    esac
    compute
    case $RUNG in
      hold-dispatch | handover | paused)
        printf 'queued\t%s (%s)\n' "$RUNG" "$REASON"
        exit 1
        ;;
    esac
    sessions_used=$(in_use_of sessions) || exit 1
    if [ "${args[0]}" = session ] && [ "$sessions_used" -ge "$(mc_lookup sessions "$LIMITS")" ]; then
      printf 'queued\tsessions at their limit\n'
      exit 1
    fi
    if [ "${args[0]}" = heavy ] && [ "$HOSTPCT" -ge "$(mc_lookup throttle "$LADDER")" ]; then
      printf 'queued\thost load at %s%%\n' "$HOSTPCT"
      exit 1
    fi
    printf 'admitted\n'
    ;;
  poll)
    [ "${#args[@]}" -eq 1 ] || usage
    mc_valid_kebab "${args[0]}" || mc_usage_fail "invalid source '$(sanitize_printable "${args[0]}")'"
    load_limits
    cap=$(mc_lookup polls_per_hour "$LIMITS")
    mc_lock || mc_fail "cannot take the fleet lock"
    trap 'mc_unlock' EXIT
    kept=$(recent_polls) || exit 1
    count=$(printf '%s' "$kept" | awk 'END { print NR }')
    if [ "$count" -ge "$cap" ]; then
      printf 'capped\t%s polls in the last hour, the cap is %s\n' "$count" "$cap"
      exit 4
    fi
    {
      [ -z "$kept" ] || printf '%s\n' "$kept"
      printf '%s\t%s\n' "$NOW" "${args[0]}"
    } | mc_write "$runtime/polls" || mc_fail "cannot write the poll log"
    ;;
  record)
    [ "${#args[@]}" -eq 2 ] || usage
    case ${args[0]} in
      sessions | context_steps) ;;
      *) usage ;;
    esac
    mc_valid_uint "${args[1]}" || mc_usage_fail "record takes a whole number"
    mc_lock || mc_fail "cannot take the fleet lock"
    trap 'mc_unlock' EXIT
    mc_upsert "$runtime/in-use" "${args[0]}" "${args[0]}	${args[1]}" \
      || mc_fail "cannot read or write the in-use record"
    ;;
  ceiling)
    [ "${#args[@]}" -eq 1 ] || usage
    mc_valid_kebab "${args[0]}" || mc_usage_fail "invalid duty '$(sanitize_printable "${args[0]}")'"
    load_limits
    own=$(mc_lookup "spend_$(printf '%s' "${args[0]}" | tr - _)" "$LIMITS")
    printf '%s\n' "${own:-$(mc_lookup spend_ceiling "$LIMITS")}"
    ;;
  *) usage ;;
esac
