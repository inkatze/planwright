#!/usr/bin/env bash
# mc-budget.sh — a mission-control program's budget: its limits, what is in
# use against them, the headroom left and the degradation rung.
#
# `mc-budget.sh --help` prints the contract: verbs, outputs, exit codes.
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
  mc_usage_fail "usage: mc-budget.sh report|rung --program <p> [--now <epoch>] [--load <pct>] [--mem <pct>] | admit --program <p> session|heavy [--now <epoch>] [--load <pct>] | reserve --program <p> [--holder <pid>] [--name <session>] [--now <epoch>] [--load <pct>] [--mem <pct>] | release --program <p> <id> | poll --program <p> <source> [--now <epoch>] | record --program <p> sessions|context_steps <n> | ceiling --program <p> <duty> | read --program <p>"
}

help_text() {
  cat <<'HELP'
mc-budget.sh — a mission-control program's budget: its limits, what is in
use against them, the headroom left and the degradation rung.

The limits are mission_control_default_budget with the program's own
budget map (scripts/mc-program.sh get <p> budget) laid over it key by key:
  sessions        live sessions
  polls_per_hour  source polls in the last hour, every snapshot-mode source
                  counted together
  context_steps   context steps
  host_load       host load, percent of the host's processors
  spend_ceiling   the highest watcher cost class armed (low, medium, high);
                  spend_<duty> sets one duty's, the duty's hyphens written
                  as underscores
Any other key is refused, named.

What is in use: sessions and context_steps as `record` last set them (0
when never recorded) in <runtime>/in-use, polls from the poll log `poll`
keeps (<runtime>/polls), host load as measured (the one-minute load
average over the processor count) or as --load gives it. A store that
exists but cannot be read, or an in-use value that is not a whole number,
fails the call, never counted as zero.

The rung, lowest to highest; the highest that applies wins:
  normal          every dimension below the ladder's throttle threshold
  throttle        the most used dimension at or over throttle: every cadence
                  doubles, at this rung and every one above it
  pause-watchers  at or over pause_watchers: high-cost watchers stop
  hold-dispatch   at or over hold_dispatch, a quota hold
                  (scripts/quota-hold.sh, the `limited` outcome, or a quota
                  store that cannot be read), or the usage hold
                  (scripts/mc-usage.sh held, or one that cannot be read):
                  medium-cost watchers stop too, and no session or heavy
                  work is admitted
  handover        context steps at their limit: the session hands over
  paused          the fleet daemon pause (scripts/fleet-daemon-gate.sh), or
                  a gate that cannot be read: nothing autonomous runs
The thresholds are mission_control_budget_ladder's percents.

Usage:
  mc-budget.sh report --program <p> [--now <epoch>] [--load <pct>]
      compute, write the budget file (<runtime>/budget) and print it:
        format<TAB>1
        program<TAB><p>
        taken<TAB><epoch>
        rung<TAB><rung><TAB><reason>
        dimension<TAB><name><TAB><used><TAB><limit><TAB><headroom><TAB><pct>
        admission<TAB><axis|open><TAB><why>   the axis `reserve` would hold a
                                              launch on (a failure to read
                                              it prints `unknown`)
        spend<TAB>ceiling<TAB><class>
        spend<TAB><duty><TAB><class>     one per duty with its own class
  mc-budget.sh rung --program <p> [--now <epoch>] [--load <pct>]
      the same computation; prints the rung alone
  mc-budget.sh admit --program <p> session|heavy [--now <epoch>] [--load <pct>]
      exit 0 printing `admitted`; exit 1 refused, printing
      queued<TAB><reason>. Heavy work is scheduled by host load: it waits
      while host load is at or over the throttle threshold, whatever the
      session count
  mc-budget.sh reserve --program <p> [--holder <pid>] [--name <session>]
                       [--now <epoch>] [--load <pct>] [--mem <pct>]
      host-shared launch admission (mission-control D-41): admit one launch
      and take a reservation for it under the fleet lock, or hold it. Held
      axes, checked in this order, each printed `queued<TAB><axis>: <why>`
      with exit 1:
        paused    the fleet daemon pause
        account   a vendor quota hold, a usage window (session or weekly,
                  the status-line cache, else the stream-json frames) at or
                  over mission_control_usage_hold, or no usage reading at
                  all (an unreadable cache)
        load      host load at or over mission_control_admit_load
        memory    available memory under mission_control_admit_memory
        lock      the fleet lock not taken in about ten seconds
        ceiling   live sessions plus reservations, every program counted,
                  at fleet_max_parallel_units
        sessions  the program's own live sessions plus reservations at its
                  budget's sessions limit
      Load and memory count each reservation and each registered session
      younger than the warm-up (mission_control_admit_warmup) at its share,
      so a lagging reading never admits a burst. Every program's registry
      rows are recounted under the lock; a waiting session holds no slot.
      A reservation whose holder pid (default: the caller's parent) is dead,
      or older than mission_control_admit_timeout, is reclaimed by the next
      admitter, printing `reclaimed<TAB><id><TAB>dead|timeout`; one whose
      --name session has registered is dropped, being counted as that
      session. Admitted: `reserved<TAB><id>` and exit 0. --mem gives the
      available memory percent as --load gives the load. A reservation
      store of an unknown format is refused (exit 1, naming the field).
  mc-budget.sh release --program <p> <id>
      give a reservation back (its launch failed or registered); prints
      `released<TAB><id>`, or `absent<TAB><id>` when none is stored
  mc-budget.sh poll --program <p> <source> [--now <epoch>]
      count one poll of <source> when the hour's polls are under the cap
      (exit 0); at the cap nothing is counted (exit 4, printing capped)
  mc-budget.sh record --program <p> sessions|context_steps <n>
      set what is in use
  mc-budget.sh ceiling --program <p> <duty>
      the duty's spend ceiling
  mc-budget.sh read --program <p>
      print the budget file as last written; refuses one whose format this
      script does not know, naming it

Exit codes: 0 done; 1 refused (admit), an invalid budget or ladder, or a
store that cannot be read or written; 2 usage; 3 the program is not
configured; 4 capped (poll).

Portable bash 3.2 / BSD tooling.
HELP
}
case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
now=""
load=""
mem=""
holder=""
sname=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --load | --mem | --holder | --name)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
        --load) load=$2 ;;
        --mem) mem=$2 ;;
        --holder) holder=$2 ;;
        --name) sname=$2 ;;
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
[ -z "$mem" ] || { mc_valid_uint "$mem" && [ "$mem" -le 100 ]; } || mc_usage_fail "--mem takes a whole percent"
[ -z "$holder" ] || { mc_valid_uint "$holder" && [ "$holder" -gt 0 ]; } || mc_usage_fail "--holder takes a process id"
[ -z "$sname" ] || mc_valid_handle "$sname" || mc_usage_fail "--name takes a session name"
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
      spend_ | spend__* | spend_*[!a-z0-9_]*)
        mc_fail "budget: $(sanitize_printable "$ll_k"): not spend_<duty>, the duty's hyphens written as underscores"
        ;;
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
    [ -z "$iu_v" ] || mc_fail "the in-use record's $1 is not a whole number"
  fi
  printf '0\n'
}

# recent_polls [keep]: the poll log's lines inside the hour ending now, the
# one predicate the cap and the report both count with; with `keep`, every
# line after the hour began up to five minutes past now, a later one a
# concurrent caller logged included, which is what a rewrite of the log must
# keep.
recent_polls() {
  [ -e "$runtime/polls" ] || return 0
  N=$NOW K=${1:-} awk -F '\t' '$1 ~ /^[0-9]+$/ && $1 > ENVIRON["N"] - 3600 && $1 <= ENVIRON["N"] + (ENVIRON["K"] != "" ? 300 : 0)' "$runtime/polls" \
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

# quota_held: 0 a vendor is held, 1 none is, 2 the store cannot be read,
# which the rung treats as held.
quota_held() {
  qh_out=$(/bin/sh "$script_dir/quota-hold.sh" status 2>/dev/null) || return 2
  printf '%s\n' "$qh_out" | awk -F '\t' '$1 == "vendor" && $3 == "held" { f = 1 } END { exit !f }'
}

# Host-shared launch admission (mission-control D-41, REQ-L1.7).
ROW_FORMAT=1

parse_pct() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100 ] || return 1
  printf '%s\n' "$1"
}
parse_usage_hold() {
  case $1 in
    off) printf 'off\n' ;;
    *) parse_pct "$1" ;;
  esac
}
parse_warmup() {
  pw_map=$(mc_map "$1") || return 1
  [ "$(printf '%s\n' "$pw_map" | awk 'END { print NR }')" -eq 3 ] || return 1
  for pw_k in seconds load memory; do
    mc_valid_uint "$(mc_lookup "$pw_k" "$pw_map")" || return 1
  done
  [ "$(mc_lookup seconds "$pw_map")" -gt 0 ] || return 1
  printf '%s\n' "$pw_map"
}

# host_mem: available memory as a percent of the total, or --mem's value.
host_mem() {
  if [ -n "$mem" ]; then
    printf '%s\n' "$mem"
    return 0
  fi
  if [ -r /proc/meminfo ]; then
    hm=$(awk '$1 == "MemTotal:" { t = $2 } $1 == "MemAvailable:" { a = $2 }
      END { if (t + 0 > 0 && a != "") printf "%d\n", a * 100 / t; else exit 1 }' /proc/meminfo) || return 1
  else
    hm_total=$(sysctl -n hw.memsize 2>/dev/null) || return 1
    hm=$(vm_stat 2>/dev/null | T=$hm_total awk '
      /page size of/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) ps = $i }
      /^Pages (free|inactive|speculative):/ { gsub(/\./, "", $NF); p += $NF }
      END { if (ps > 0 && ENVIRON["T"] + 0 > 0) printf "%d\n", p * ps * 100 / ENVIRON["T"]; else exit 1 }') || return 1
  fi
  mc_valid_uint "$hm" || return 1
  printf '%s\n' "$hm"
}

# account_held: 0 with WHY set when the account allows no launch: a vendor
# quota hold, a usage window at or over the hold knob, or no reading of
# either window at all (a cache that cannot be read holds, never admits).
account_held() {
  quota_held
  case $? in
    0)
      WHY="a vendor quota hold (limited)"
      return 0
      ;;
    2)
      WHY="the quota store cannot be read"
      return 0
      ;;
  esac
  ah_hold=$(mc_knob mission_control_usage_hold parse_usage_hold) || {
    WHY="mission_control_usage_hold cannot be read"
    return 0
  }
  ah_win=$(/bin/sh "$script_dir/fleet-usage-gate.sh" windows --now "$NOW" 2>/dev/null) || ah_win=""
  ah_frames=$(/bin/sh "$script_dir/claude-frames.sh" read --now "$NOW" 2>/dev/null) || ah_frames=""
  ah_read=$(printf '%s\n%s\n' "$ah_win" "$ah_frames" | awk -F '\t' '
    function ok(p, r) { return p ~ /^[0-9]+([.][0-9]+)?$/ && p + 0 <= 100 && r ~ /^[0-9]+$/ }
    ($1 == "session" || $1 == "weekly") && ok($2, $3) && !($1 in w) { w[$1] = int($2) }
    $1 == "window" && ($2 == "session" || $2 == "weekly") && ok($3, $4) && !($2 in w) { w[$2] = int($3) }
    END { if ("session" in w) print "session " w["session"]; if ("weekly" in w) print "weekly " w["weekly"] }')
  if [ -z "$ah_read" ]; then
    WHY="no usage reading is available (the usage cache cannot be read)"
    return 0
  fi
  [ "$ah_hold" != off ] || return 1
  WHY=$(printf '%s\n' "$ah_read" | H=$ah_hold awk '$2 + 0 >= ENVIRON["H"] + 0 {
    print "the " $1 " usage window is at " $2 "% (the hold is at " ENVIRON["H"] "%)"; exit }')
  [ -n "$WHY" ]
}

# registry_scan <warm seconds>: R_ALL, R_OWN and R_WARM, the live sessions
# every program's registry holds (mission-control sessions and waiting ones
# left out), this program's, and those launched inside the warm-up; R_NAMES,
# every registered name, one per line.
registry_scan() {
  rs_warm=$1
  FH=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
  rs_rows=""
  R_NAMES=""
  if [ -d "$FH/mission-control/sessions" ]; then
    set +f
    set -- "$FH/mission-control/sessions"/mc-*
    set -f
    for rs_f in "$@"; do
      [ -f "$rs_f" ] && [ ! -L "$rs_f" ] || continue
      case ${rs_f##*/} in *.tmp.*) continue ;; esac
      [ -r "$rs_f" ] || mc_fail "cannot read the registry row $(sanitize_printable "${rs_f##*/}")"
      [ "$(mc_kv "$rs_f" format)" = "$ROW_FORMAT" ] || continue
      [ "$(mc_kv "$rs_f" kind)" != mission-control ] || continue
      rs_p=$(mc_kv "$rs_f" program)
      [ -n "$rs_p" ] || continue
      R_NAMES="$R_NAMES${rs_f##*/}
"
      [ -z "$(mc_kv "$rs_f" waiting)" ] || continue
      rs_rows="$rs_rows$rs_p	$(mc_kv "$rs_f" launched)
"
    done
  fi
  rs_out=$(printf '%s' "$rs_rows" | P=$program N=$NOW W=$rs_warm awk -F '\t' '
    NF { a++; if ($1 == ENVIRON["P"]) o++
      if ($2 ~ /^[0-9]+$/ && ENVIRON["N"] - $2 < ENVIRON["W"]) w++ }
    END { print a + 0 " " o + 0 " " w + 0 }')
  R_ALL=${rs_out%% *}
  rs_out=${rs_out#* }
  R_OWN=${rs_out%% *}
  R_WARM=${rs_out#* }
}

# store_read <timeout seconds>: the reservation store's live lines in RES
# (reservation<TAB>id<TAB>program<TAB>holder<TAB>epoch<TAB>name) and the
# reclaimed ones in RECLAIMED (id<TAB>why); returns 1 with STORE_ERR set for
# a store this script cannot read. Needs R_NAMES from registry_scan.
store_read() {
  RES=""
  RECLAIMED=""
  STORE_ERR=""
  [ -e "$ASTORE" ] || return 0
  if ! mc_format_ok "$ASTORE"; then
    STORE_ERR="reservation store: format: unknown format"
    return 1
  fi
  sr_lines=$(awk -F '\t' 'NR > 1' "$ASTORE") || {
    STORE_ERR="cannot read the reservation store"
    return 1
  }
  while IFS='	' read -r sr_k sr_id sr_p sr_pid sr_at sr_name; do
    [ -n "$sr_k" ] || continue
    if [ "$sr_k" != reservation ] || ! mc_valid_uint "$sr_pid" || ! mc_valid_uint "$sr_at"; then
      STORE_ERR="reservation store: a line outside the grammar"
      return 1
    fi
    sr_line="$sr_k	$sr_id	$sr_p	$sr_pid	$sr_at	$sr_name"
    if ! kill -0 "$sr_pid" 2>/dev/null; then
      RECLAIMED="$RECLAIMED$sr_id	dead
"
    elif [ $((NOW - sr_at)) -gt "$1" ]; then
      RECLAIMED="$RECLAIMED$sr_id	timeout
"
    elif [ "$sr_name" != - ] && printf '%s' "$R_NAMES" | N=$sr_name awk '$0 == ENVIRON["N"] { f = 1 } END { exit !f }'; then
      RECLAIMED="$RECLAIMED$sr_id	registered
"
    else
      RES="$RES$sr_line
"
    fi
  done <<EOF
$sr_lines
EOF
}

# admission_knobs: the admission knobs, in ADM_LOAD, ADM_MEM, ADM_WARM_S,
# ADM_WARM_LOAD, ADM_WARM_MEM, ADM_TIMEOUT and ADM_CEILING; exits on a bad one.
admission_knobs() {
  ADM_LOAD=$(mc_knob mission_control_admit_load parse_pct) || exit 1
  ADM_MEM=$(mc_knob mission_control_admit_memory parse_pct) || exit 1
  ak_warm=$(mc_knob mission_control_admit_warmup parse_warmup) || exit 1
  ADM_WARM_S=$(mc_lookup seconds "$ak_warm")
  ADM_WARM_LOAD=$(mc_lookup load "$ak_warm")
  ADM_WARM_MEM=$(mc_lookup memory "$ak_warm")
  ak_to=$(mc_knob mission_control_admit_timeout mc_parse_cadence) || exit 1
  ADM_TIMEOUT=$(mc_seconds "$ak_to") || exit 1
  ADM_CEILING=$(mc_knob fleet_max_parallel_units mc_parse_count) || exit 1
}

# admission_verdict: the axis check shared by `reserve` and the budget's
# admission line. Needs the knobs, load_limits, store_read and registry_scan
# done; sets AXIS (open or the held axis) and WHY.
admission_verdict() {
  AXIS=open
  WHY=""
  av_n=$((R_WARM + $(printf '%s' "$RES" | awk 'NF { n++ } END { print n + 0 }')))
  av_res_all=$(printf '%s' "$RES" | awk 'NF { n++ } END { print n + 0 }')
  av_res_own=$(printf '%s' "$RES" | P=$program awk -F '\t' '$3 == ENVIRON["P"] { n++ } END { print n + 0 }')
  if [ $((R_ALL + av_res_all)) -ge "$ADM_CEILING" ]; then
    AXIS=ceiling
    WHY="$((R_ALL + av_res_all)) sessions and reservations on this host, at fleet_max_parallel_units $ADM_CEILING"
    return 0
  fi
  if [ $((R_OWN + av_res_own)) -ge "$(mc_lookup sessions "$LIMITS")" ]; then
    AXIS=sessions
    WHY="program $program holds $((R_OWN + av_res_own)), at its sessions limit $(mc_lookup sessions "$LIMITS")"
    return 0
  fi
  av_load=$((ADM_PCT + av_n * ADM_WARM_LOAD))
  if [ "$av_load" -ge "$ADM_LOAD" ]; then
    AXIS=load
    WHY="host load at $ADM_PCT% ($av_load% counting $av_n launches still warming up), at or over mission_control_admit_load $ADM_LOAD%"
    return 0
  fi
  av_mem=$((ADM_AVAIL - av_n * ADM_WARM_MEM))
  if [ "$av_mem" -lt "$ADM_MEM" ]; then
    AXIS=memory
    WHY="available memory at $ADM_AVAIL% ($av_mem% counting $av_n launches still warming up), under mission_control_admit_memory $ADM_MEM%"
  fi
  return 0
}

# measure: ADM_PCT and ADM_AVAIL; an unreadable memory figure is a hold.
measure() {
  ADM_PCT=$(host_load)
  ADM_AVAIL=$(host_mem) || ADM_AVAIL=""
}

# admission_line: the budget file's `admission` line, never failing the report.
admission_line() {
  (
    prog=mc-budget
    load_limits
    admission_knobs
    if ! mc_gate mc-budget; then
      printf 'admission\tpaused\tthe fleet daemon pause or gate\n'
      exit 0
    fi
    if account_held; then
      printf 'admission\taccount\t%s\n' "$(printf '%s' "$WHY" | tr '\t\n' '  ')"
      exit 0
    fi
    measure
    if [ -z "$ADM_AVAIL" ]; then
      printf 'admission\tmemory\tavailable memory cannot be read\n'
      exit 0
    fi
    ASTORE=$(mc_fleet_home)/mission-control/admission
    registry_scan "$ADM_WARM_S"
    if ! store_read "$ADM_TIMEOUT"; then
      printf 'admission\tstore\t%s\n' "$STORE_ERR"
      exit 0
    fi
    admission_verdict
    printf 'admission\t%s\t%s\n' "$AXIS" "$(printf '%s' "$WHY" | tr '\t\n' '  ')"
  ) 2>/dev/null || printf 'admission\tunknown\tthe admission state cannot be computed\n'
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
  if [ "$RUNG" != hold-dispatch ]; then
    quota_held
    case $? in
      0)
        RUNG=hold-dispatch
        REASON="a quota hold (limited)"
        ;;
      2)
        RUNG=hold-dispatch
        REASON="the quota store cannot be read"
        ;;
    esac
  fi
  if [ "$RUNG" != hold-dispatch ]; then
    uh_out=$(/bin/bash "$script_dir/mc-usage.sh" held --program "$program" --now "$NOW" 2>/dev/null)
    uh_rc=$?
    # A failure exits 1 as clear does, so clear is only the word itself.
    [ "$uh_rc" -ne 1 ] || [ "$uh_out" = clear ] || uh_rc=2
    case $uh_rc in
      0)
        RUNG=hold-dispatch
        REASON=$(printf '%s\n' "$uh_out" | awk -F '\t' 'NR == 1 {
          if ($2 == "quota") print "a quota hold (limited)"; else print "the " $2 " usage window at " $3 "%" }')
        ;;
      1) ;;
      *)
        RUNG=hold-dispatch
        REASON="the usage hold cannot be read"
        ;;
    esac
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
  printf '%s\n' "$ADMISSION"
  printf 'spend\tceiling\t%s\n' "$(mc_lookup spend_ceiling "$LIMITS")"
  printf '%s\n' "$LIMITS" | awk -F '\t' '$1 ~ /^spend_/ && $1 != "spend_ceiling" {
    d = substr($1, 7); gsub(/_/, "-", d); print "spend\t" d "\t" $2 }'
}

case $verb in
  report)
    [ "${#args[@]}" -eq 0 ] || usage
    compute
    ADMISSION=$(admission_line)
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
  reserve)
    [ "${#args[@]}" -eq 0 ] || usage
    [ -n "$holder" ] || holder=$PPID
    held() { # held <axis> <why>: the launch waits
      printf 'queued\t%s: %s\n' "$1" "$2"
      exit 1
    }
    mc_gate mc-budget || held paused "the fleet daemon pause or gate"
    if account_held; then held account "$WHY"; fi
    load_limits
    admission_knobs
    measure
    [ -n "$ADM_AVAIL" ] || held memory "available memory cannot be read"
    [ "$ADM_PCT" -lt "$ADM_LOAD" ] || held load "host load at $ADM_PCT%, at or over mission_control_admit_load $ADM_LOAD%"
    [ "$ADM_AVAIL" -ge "$ADM_MEM" ] || held memory "available memory at $ADM_AVAIL%, under mission_control_admit_memory $ADM_MEM%"
    FH=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
    ASTORE=$FH/mission-control/admission
    mkdir -p "$FH/mission-control" || mc_fail "cannot create the admission store's directory"
    mc_lock || held lock "the fleet lock was not taken in time"
    trap 'mc_unlock' EXIT
    registry_scan "$ADM_WARM_S"
    store_read "$ADM_TIMEOUT" || mc_fail "$STORE_ERR"
    if [ -n "$RECLAIMED" ]; then
      {
        printf 'format\t%s\n' "$MC_FORMAT"
        printf '%s' "$RES"
      } | mc_write "$ASTORE" || mc_fail "cannot write the reservation store"
      printf '%s' "$RECLAIMED" | awk -F '\t' 'NF { print "reclaimed\t" $1 "\t" $2 }'
    fi
    admission_verdict
    [ "$AXIS" = open ] || held "$AXIS" "$WHY"
    rid="r$NOW.$$"
    {
      printf 'format\t%s\n' "$MC_FORMAT"
      printf '%s' "$RES"
      printf 'reservation\t%s\t%s\t%s\t%s\t%s\n' "$rid" "$program" "$holder" "$NOW" "${sname:--}"
    } | mc_write "$ASTORE" || mc_fail "cannot write the reservation store"
    printf 'reserved\t%s\n' "$rid"
    ;;
  release)
    [ "${#args[@]}" -eq 1 ] || usage
    case ${args[0]} in
      r[0-9]*.[0-9]*) ;;
      *) usage ;;
    esac
    case ${args[0]} in
      *[!0-9r.]*) usage ;;
    esac
    FH=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
    ASTORE=$FH/mission-control/admission
    mc_lock || mc_fail "cannot take the fleet lock"
    trap 'mc_unlock' EXIT
    if [ ! -e "$ASTORE" ]; then
      printf 'absent\t%s\n' "${args[0]}"
      exit 0
    fi
    mc_format_ok "$ASTORE" || mc_fail "reservation store: format: unknown format"
    kept=$(awk -F '\t' -v id="${args[0]}" 'NR > 1 && $2 != id' "$ASTORE") || mc_fail "cannot read the reservation store"
    had=$(awk -F '\t' -v id="${args[0]}" 'NR > 1 && $2 == id { n++ } END { print n + 0 }' "$ASTORE")
    {
      printf 'format\t%s\n' "$MC_FORMAT"
      [ -z "$kept" ] || printf '%s\n' "$kept"
    } | mc_write "$ASTORE" || mc_fail "cannot write the reservation store"
    if [ "$had" -gt 0 ]; then
      printf 'released\t%s\n' "${args[0]}"
    else
      printf 'absent\t%s\n' "${args[0]}"
    fi
    ;;
  poll)
    [ "${#args[@]}" -eq 1 ] || usage
    mc_valid_kebab "${args[0]}" || mc_usage_fail "invalid source '$(sanitize_printable "${args[0]}")'"
    load_limits
    cap=$(mc_lookup polls_per_hour "$LIMITS")
    mc_lock || mc_fail "cannot take the fleet lock"
    trap 'mc_unlock' EXIT
    kept=$(recent_polls keep) || exit 1
    count=$(printf '%s\n' "$kept" | N=$NOW awk -F '\t' 'NF && $1 <= ENVIRON["N"] + 0 { n++ } END { print n + 0 }')
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
