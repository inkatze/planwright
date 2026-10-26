#!/usr/bin/env bash
# mc-panel.sh — the panel mod's data seam: one digest of every store the
# panel draws, the one-line text form a session without the mod reads, and
# the presence marker the mod feeds from prompt events.
#
# `mc-panel.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-panel
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

DECISIONS_SHOWN=3

usage() {
  mc_usage_fail "usage: mc-panel.sh digest|line --program <p> [--target <t>] [--now <epoch>] | presence --program <p> --prompt|--refresh [--now <epoch>]"
}

help_text() {
  cat <<'HELP'
mc-panel.sh — the panel mod's data seam: one digest of every store the
panel draws, the one-line text form a session without the mod reads, and
the presence marker the mod feeds from prompt events.

The mod (hooks/mission-control/) runs `digest` on its redraw timer and
draws only what it prints; nothing here calls a model or writes a store
but the presence marker. A store that cannot be read is said as such,
never drawn as empty.

Usage:
  mc-panel.sh digest --program <p> [--target <t>] [--now <epoch>]
      one record per line, tab separated, in this order:
        format<TAB>1
        program<TAB><p>
        taken<TAB><epoch>
        knob<TAB>refresh|tick<TAB><seconds>   the mod's redraw and tick
                                             cadences
        knob<TAB>handover-context|handover-wakes|handover-compactions<TAB><n>
                                             the handover trigger's
                                             thresholds
        flight<TAB><worker><TAB><scope><TAB><backend>
                                             a live fleet registry session
        waiting<TAB><n>                      the operator queue's items
        pending<TAB><n>                      the target's events not yet
                                             submitted (with --target)
        decision<TAB><time><TAB><subject><TAB><act>
                                             the knowledge base's newest
                                             decisions, newest first
        rung<TAB><rung><TAB><reason>         the budget file's rung, or
                                             `-` before the first budget
        headroom<TAB><dimension><TAB><used><TAB><limit><TAB><percent>
        watcher<TAB><duty><TAB><script><TAB><state><TAB><seconds to next>
                                             a negative next is an expiry
        source<TAB><class><TAB><source><TAB><mode><TAB><age|->
                                             every fact class, `-` for a
                                             class with no source
        kb<TAB><age|->                       the knowledge-base index's age
        measure<TAB><name><TAB><value><TAB><age>
                                             the interruption and
                                             settled-share measures, or
                                             measure - none|unreadable -
        handover<TAB>available|absent        whether a handover verb is
                                             installed to defer a
                                             compaction for
        unreadable<TAB><store>               a store that could not be read
        line<TAB><text>                      the line form, last
      Stored text has every control byte dropped.
  mc-panel.sh line --program <p> [--target <t>] [--now <epoch>]
      the line form alone, for a status line or a session without the mod
  mc-panel.sh presence --program <p> --prompt|--refresh [--now <epoch>]
      write the presence marker the operator queue reads,
      <runtime>/presence:
        format<TAB>1
        producer<TAB>mission-control-panel
        written<TAB><epoch>
        last-prompt<TAB><epoch|->
      --prompt records a prompt event now; --refresh restamps the
      producer and keeps the last prompt, so a marker that stops being
      refreshed means the producer is gone

Exit codes: 0 done; 1 the program list or the presence marker cannot be
read or written; 2 usage; 3 the program is not configured.

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
target=""
now=""
presence_kind=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --prompt | --refresh)
      [ -z "$presence_kind" ] || usage
      presence_kind=${1#--}
      shift
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
case $verb in
  digest | line) [ -z "$presence_kind" ] || usage ;;
  presence) [ -n "$presence_kind" ] && [ -z "$target" ] || usage ;;
  *) usage ;;
esac
[ -z "$target" ] || mc_valid_handle "$target" || mc_usage_fail "invalid target '$(sanitize_printable "$target")'"
mc_now_arg "$now"
mc_require_program "$program"
export PLANWRIGHT_MC_CHECKED="$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"

mc_parse_pct() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100 ] || return 1
  printf '%s\n' "$1"
}

# mtime <file>: its modification epoch, GNU stat first, then BSD.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

clean_field() { printf '%s' "$1" | tr -d '\000-\037\177'; }

if [ "$verb" = presence ]; then
  pres=$runtime/presence
  mc_lock || mc_fail "cannot take the fleet lock"
  trap 'mc_unlock' EXIT
  last=$NOW
  if [ "$presence_kind" = refresh ]; then
    last=-
    if mc_format_ok "$pres"; then
      last=$(awk -F '\t' '$1 == "last-prompt" { print $2; exit }' "$pres")
      mc_valid_uint "$last" || last=-
    fi
  fi
  printf 'format\t%s\nproducer\tmission-control-panel\nwritten\t%s\nlast-prompt\t%s\n' "$MC_FORMAT" "$NOW" "$last" \
    | mc_write "$pres" || mc_fail "cannot write the presence marker"
  exit 0
fi

# Each read below prints its records; a store it cannot read prints
# `unreadable<TAB><store>` and the digest goes on.
D_FLIGHT=0
D_WAITING=-
D_PENDING=-
D_RUNG=-
D_OLDEST=""

knobs() {
  for kn in refresh:mission_control_panel_refresh:mc_parse_cadence \
    tick:mission_control_tick_cadence:mc_parse_cadence \
    handover-context:mission_control_handover_context:mc_parse_pct \
    handover-wakes:mission_control_handover_wakes:mc_parse_uint \
    handover-compactions:mission_control_handover_compactions:mc_parse_uint; do
    kn_name=${kn%%:*}
    kn_rest=${kn#*:}
    if kn_v=$(mc_knob "${kn_rest%%:*}" "${kn_rest#*:}"); then
      case $kn_name in refresh | tick) kn_v=$(mc_seconds "$kn_v") ;; esac
      printf 'knob\t%s\t%s\n' "$kn_name" "$kn_v"
    else
      printf 'unreadable\tknob %s\n' "${kn_rest%%:*}"
    fi
  done
}

flights() {
  fl_reg=$(/bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null) || {
    printf 'unreadable\tfleet registry\n'
    return 0
  }
  # The last record per worker wins; a closed one is retired.
  FLIGHTS=$(printf '%s\n' "$fl_reg" | awk -F '\t' '
    NF >= 5 { last[$2] = $0; if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 } }
    END {
      for (i = 1; i <= n; i++) {
        split(last[order[i]], f, "\t")
        if (f[8] == "closed") continue
        print "flight\t" f[2] "\t" f[3] "\t" f[5]
      }
    }' | mc_clean)
  [ -z "$FLIGHTS" ] || printf '%s\n' "$FLIGHTS"
  D_FLIGHT=$(printf '%s' "$FLIGHTS" | awk 'NF { n++ } END { print n + 0 }')
}

waiting() {
  if wt_n=$(/bin/sh "$script_dir/fleet-attention.sh" queue --count 2>/dev/null) && mc_valid_uint "$wt_n"; then
    D_WAITING=$wt_n
    printf 'waiting\t%s\n' "$wt_n"
  else
    printf 'unreadable\toperator queue\n'
  fi
}

pending() {
  [ -n "$target" ] || return 0
  if pd_rows=$(/bin/bash "$script_dir/mc-event.sh" list --program "$program" --target "$target" --pending 2>/dev/null); then
    D_PENDING=$(printf '%s' "$pd_rows" | awk 'NF { n++ } END { print n + 0 }')
    printf 'pending\t%s\n' "$D_PENDING"
  else
    printf 'unreadable\tevents\n'
  fi
}

decisions() {
  dc_home=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home 2>/dev/null) || {
    printf 'unreadable\tprogram home\n'
    return 0
  }
  KB=$dc_home/kb
  set +f
  dc_segs=$(ls "$KB"/decisions-[0-9][0-9][0-9][0-9]-[0-9][0-9].log 2>/dev/null)
  set -f
  [ -n "$dc_segs" ] || return 0
  # Segment names sort by month; the last lines of the newest segments are
  # the newest decisions.
  # shellcheck disable=SC2086 # one segment path per word, none holds a space
  dc_rows=$(cat $dc_segs 2>/dev/null) || {
    printf 'unreadable\tdecisions log\n'
    return 0
  }
  printf '%s\n' "$dc_rows" | awk -F '\t' -v max="$DECISIONS_SHOWN" '
    NF >= 4 && $2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { row[++n] = $2 "\t" $3 "\t" $4 }
    END { for (i = n; i > 0 && i > n - max; i--) print "decision\t" row[i] }' | mc_clean
}

budget() {
  bg_file=$runtime/budget
  if [ ! -e "$bg_file" ]; then
    printf 'rung\t-\tno budget computed yet\n'
    return 0
  fi
  bg=$(/bin/bash "$script_dir/mc-budget.sh" read --program "$program" 2>/dev/null) || {
    printf 'unreadable\tbudget\n'
    return 0
  }
  printf '%s\n' "$bg" | awk -F '\t' '
    $1 == "rung" { print "rung\t" $2 "\t" $3 }
    $1 == "dimension" { print "headroom\t" $2 "\t" $3 "\t" $4 "\t" $6 }' | mc_clean
  D_RUNG=$(printf '%s\n' "$bg" | awk -F '\t' '$1 == "rung" { print $2; exit }' | mc_clean)
  [ -n "$D_RUNG" ] || D_RUNG=-
}

watchers() {
  [ -d "$runtime/watchers" ] || return 0
  wa=$(/bin/bash "$script_dir/mc-watch.sh" status --program "$program" --now "$NOW" 2>/dev/null) || {
    printf 'unreadable\twatchers\n'
    return 0
  }
  printf '%s\n' "$wa" | awk -F '\t' '$1 == "watcher" { n = split($3, p, "/"); print "watcher\t" $2 "\t" p[n] "\t" $6 "\t" $8 }' | mc_clean
}

sources() {
  so=$(/bin/bash "$script_dir/mc-snapshot.sh" list --program "$program" --now "$NOW" 2>/dev/null) || {
    printf 'unreadable\tsources\n'
    return 0
  }
  printf '%s\n' "$so" | awk -F '\t' 'NF == 4 { print "source\t" $1 "\t" $2 "\t" $3 "\t" $4 }' | mc_clean
  # The line names the oldest snapshot, with its age.
  D_OLDEST=$(printf '%s\n' "$so" | awk -F '\t' '
    NF == 4 && $3 == "snapshot" && $4 ~ /^-?[0-9]+$/ && (best == "" || $4 + 0 > age) { best = $2; age = $4 + 0 }
    END { if (best != "") print best " snapshot " age "s old" }' | mc_clean)
}

kb() {
  kb_age=-
  if [ -n "${KB:-}" ] && [ -f "$KB/index.md" ]; then
    if kb_t=$(mtime "$KB/index.md") && mc_valid_uint "$kb_t"; then
      # An index stamped after now (a stepped clock) reads as fresh.
      kb_age=$((NOW > kb_t ? NOW - kb_t : 0))
    fi
  fi
  printf 'kb\t%s\n' "$kb_age"
}

measures() {
  ms=$runtime/measures
  if [ ! -e "$ms" ]; then
    printf 'measure\t-\tnone\t-\n'
    return 0
  fi
  if ! mc_format_ok "$ms"; then
    printf 'measure\t-\tunreadable\t-\n'
    return 0
  fi
  ms_taken=$(awk -F '\t' '$1 == "taken" { print $2; exit }' "$ms")
  ms_age=-
  ! mc_valid_uint "$ms_taken" || ms_age=$((NOW - ms_taken))
  awk -F '\t' -v age="$ms_age" '
    ($1 == "interruptions_per_hour" || $1 == "settled_share") && $2 ~ /^[0-9]+(\.[0-9]+)?$/ { print "measure\t" $1 "\t" $2 "\t" age }' "$ms"
}

handover() {
  if [ -f "$script_dir/mc-handover.sh" ]; then
    printf 'handover\tavailable\n'
  else
    printf 'handover\tabsent\n'
  fi
}

the_line() {
  ln_text="mission control $program: $D_FLIGHT in flight, $D_WAITING waiting"
  [ -z "$target" ] || ln_text="$ln_text, $D_PENDING pending"
  ln_text="$ln_text, rung $D_RUNG"
  [ -z "$D_OLDEST" ] || ln_text="$ln_text, $D_OLDEST"
  clean_field "$ln_text"
}

digest() {
  printf 'format\t%s\nprogram\t%s\ntaken\t%s\n' "$MC_FORMAT" "$program" "$NOW"
  knobs
  flights
  waiting
  pending
  decisions
  budget
  watchers
  sources
  kb
  measures
  handover
  printf 'line\t%s\n' "$(the_line)"
}

case $verb in
  digest) digest ;;
  line)
    # The same reads, so the line says exactly what the digest would.
    digest >/dev/null
    the_line
    printf '\n'
    ;;
esac
