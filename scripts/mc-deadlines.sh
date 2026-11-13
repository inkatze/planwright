#!/usr/bin/env bash
# mc-deadlines.sh — the deadline-watch duty: dates held in the program's
# record and snapshot stores and dates the operator states drive priority and
# the first turn after silence. No calendar is read.
#
# `mc-deadlines.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-deadlines
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh spec-parse.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-deadlines.sh — the deadline-watch duty: dates held in the program's
record and snapshot stores and dates the operator states drive priority and
the first turn after silence. No calendar is read.

THE SOURCES, by the program's deadlines fact class (scripts/mc-program.sh
get <p> sources):
  record, source specs   a `**Due:** YYYY-MM-DD` line, bulleted or not, in
                         a task block of a bundle's tasks.md under the spec
                         root (the block running to the next H2 or H3)
                         dates the unit <bundle>:task-<id>; the first such
                         line in requirements.md dates the bundle; a Due
                         line inside a code fence is an example and never
                         read, and an unclosed fence fails the read; a bundle
                         named outside the identifier grammar is skipped,
                         and a spec root that is not a directory fails
  snapshot               each `due<TAB><unit><TAB><YYYY-MM-DD>` line of the
                         source's snapshot (scripts/mc-snapshot.sh read)
  cited                  nothing is read; the operator's dates only
and always the operator's stated dates, kept in the program home's
kb/deadline-watch/dates.tsv ("# format: 1", then
unit<TAB>date<TAB>note). An operator's unit takes letters, digits and
. _ = @ : - (at most 128), the event subject grammar. A date that names no
calendar day is refused on add and dropped from a store.

The horizon is mission_control_deadline_horizon: a date at most that many
whole days away is urgent, one already past overdue.

Usage:
  mc-deadlines.sh add --program <p> --unit <unit> --due <YYYY-MM-DD> [--note <text>]
      record a date the operator stated; a later add for the same unit
      replaces it
  mc-deadlines.sh list --program <p> [--now <epoch>]
      deadline<TAB><unit><TAB><date><TAB><days left><TAB><source>
      every known date, earliest first; an operator date wins over a store's
      for the same unit
  mc-deadlines.sh due --program <p> [--now <epoch>]
      the urgent and overdue lines of list: what the first turn after
      silence opens with
  mc-deadlines.sh rank --program <p> [--now <epoch>] <unit>...
      rank<TAB><n><TAB><unit><TAB>overdue|urgent|dated|none<TAB><date|->
      overdue units first, then urgent ones, each earliest first, then the
      rest in the order given
  mc-deadlines.sh watch [--program <p>] [--now <epoch>]
      the duty's watcher (also what a run with no arguments does under the
      runner): one deadline-near event per urgent or overdue unit per day,
      subject the unit (a checksum subject for a store's unit outside the
      grammar), text `<unit> due <date> (<n> days, <source>)`, printing
        announced<TAB>deadline-near<TAB><subject>
      a unit counts as announced for the day only once the program's event
      store holds the event; the program from PLANWRIGHT_MC_PROGRAM when
      --program is absent

Exit codes: 0 done; 1 a store or source that cannot be read or written, an
invalid horizon knob, or an event the store refused; 2 usage; 3 the
program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-deadlines.sh add|list|due|rank|watch --program <p> ...; mc-deadlines.sh --help for each verb"
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
program=""
unit=""
due=""
note="-"
now=""
units=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --unit | --due | --note | --now)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --unit) unit=$2 ;;
        --due) due=$2 ;;
        --note) note=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      mc_valid_text "$1" || mc_usage_fail "a unit takes text with no control byte"
      units+=("$1")
      shift
      ;;
  esac
done
[ "$verb" != watch ] || [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
[ "$verb" = rank ] || [ "${#units[@]}" -eq 0 ] || usage
mc_now_arg "$now"
mc_require_program "$program"

valid_date() {
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | awk "$DATE_AWK"' { exit !real($0) }'
}

# real(s): s, a YYYY-MM-DD string, names a day of the calendar.
# shellcheck disable=SC2016 # an awk program
DATE_AWK='function real(s,   y, m, d, md) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$/) return 0
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m < 1 || m > 12 || d < 1) return 0
  md = (m == 2) ? ((y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
  return d <= md
}'

home=$(mc_program_home "$program") || exit 1
store="$home/kb/deadline-watch/dates.tsv"

check_store() {
  [ -e "$store" ] || return 0
  mc_store_ok "$store" || mc_fail "the dates store has a missing or unknown format: $store"
}

# gather: unit<TAB>date<TAB>source for every known date, operator dates
# first so they win.
gather() {
  check_store
  if [ -e "$store" ]; then
    awk -F '\t' 'NR > 1 && NF >= 2 { print $1 "\t" $2 "\toperator" }' "$store" || mc_fail "the dates store cannot be read: $store"
  fi
  ga_src=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || mc_fail "the source map of program $program does not resolve"
  ga_line=$(printf '%s\n' "$ga_src" | awk -F '\t' '$1 == "deadlines" { print $2 "\t" $3 }')
  ga_source=${ga_line%%	*}
  ga_mode=${ga_line#*	}
  case $ga_mode in
    record)
      [ "$ga_source" = specs ] || return 0
      ga_root=$(/bin/bash "$script_dir/mc-program.sh" get "$program" spec_root) || mc_fail "the spec root of program $program does not resolve"
      [ -d "$ga_root" ] || mc_fail "the spec root of program $program is not a directory: $ga_root"
      set +f
      for ga_b in "$ga_root"/*/; do
        ga_b=${ga_b%/}
        ga_n=${ga_b##*/}
        case $ga_n in _* | '*') continue ;; esac
        # A bundle name becomes a unit; one outside the identifier grammar
        # (a tab or newline in it, say) could forge a store line.
        mc_valid_kebab "$ga_n" || continue
        [ -f "$ga_b/tasks.md" ] || continue
        # A task block runs to the next H2 or H3 heading; the task heading
        # grammar and the code-fence skip are the shared spec-parse lib's.
        # shellcheck disable=SC2016 # awk source
        N=$ga_n awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
          /^##[#]? / { t = spec_parse_task_id($0) }
          /^(- )?\*\*Due:\*\* [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ ]*$/ && t != "" { print ENVIRON["N"] ":task-" t "\t" $NF "\trecord:specs" }
          END { spec_parse__fence_eof() }' \
          "$ga_b/tasks.md" || mc_fail "cannot read $ga_b/tasks.md (an unclosed code fence fails it)"
        if [ -f "$ga_b/requirements.md" ]; then
          # shellcheck disable=SC2016 # awk source
          N=$ga_n awk "$spec_parse_awk_fence"'
            /^(- )?\*\*Due:\*\* [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ ]*$/ && !got { print ENVIRON["N"] "\t" $NF "\trecord:specs"; got = 1 }
            END { spec_parse__fence_eof() }' \
            "$ga_b/requirements.md" || mc_fail "cannot read $ga_b/requirements.md (an unclosed code fence fails it)"
        fi
      done
      set -f
      ;;
    snapshot)
      ga_snap=$(/bin/bash "$script_dir/mc-snapshot.sh" read --program "$program" "$ga_source" --now "$NOW")
      case $? in
        0) printf '%s\n' "$ga_snap" | S=$ga_source awk -F '\t' 'NR > 1 && $1 == "due" && NF >= 3 { print $2 "\t" $3 "\tsnapshot:" ENVIRON["S"] }' ;;
        3) ;;
        *) mc_fail "the $ga_source snapshot cannot be read" ;;
      esac
      ;;
  esac
}

today_days() { # whole days since the epoch, UTC
  printf '%s\n' $((NOW / 86400))
}

horizon_days() {
  hd=$(mc_knob mission_control_deadline_horizon mc_parse_cadence) || exit 1
  hd=$(mc_seconds "$hd") || exit 1
  printf '%s\n' $((hd / 86400))
}

# listing: deadline lines, earliest first; a date that names no calendar
# day is dropped.
listing() {
  ls_raw=$(gather) || exit 1
  [ -n "$ls_raw" ] || return 0
  printf '%s\n' "$ls_raw" | T=$(today_days) awk -F '\t' "$DATE_AWK"'
    function days(s,   y, m, d) {
      y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
      if (m <= 2) { y--; m += 12 }
      return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469
    }
    !real($2) { next }
    $1 in seen { next }
    { seen[$1] = 1; print $2 "\t" "deadline\t" $1 "\t" $2 "\t" (days($2) - ENVIRON["T"]) "\t" $3 }' \
    | sort -t '	' -k1,1 -s | cut -f2-
}

case $verb in
  add)
    [ -n "$unit" ] || mc_usage_fail "--unit names the dated unit"
    mc_valid_handle "$unit" || mc_usage_fail "--unit takes letters, digits and . _ = @ : - only, at most 128"
    valid_date "$due" || mc_usage_fail "--due takes a calendar day, YYYY-MM-DD"
    check_store
    mkdir -p "${store%/*}" || mc_fail "cannot create ${store%/*}"
    trap mc_kb_unlock EXIT
    mc_kb_lock "$program" deadline-watch/dates.tsv
    kept=""
    if [ -e "$store" ]; then
      kept=$(U=$unit awk -F '\t' 'NR > 1 && $1 != ENVIRON["U"]' "$store") || mc_fail "the dates store cannot be read: $store"
    fi
    {
      printf '# format: 1\n'
      [ -z "$kept" ] || printf '%s\n' "$kept"
      printf '%s\t%s\t%s\n' "$unit" "$due" "$note"
    } | mc_write "$store" || mc_fail "cannot write $store"
    printf 'dated\t%s\t%s\n' "$unit" "$due"
    ;;
  list) listing ;;
  due)
    h=$(horizon_days) || exit 1
    dl=$(listing) || exit 1
    [ -z "$dl" ] || printf '%s\n' "$dl" | H=$h awk -F '\t' '$4 + 0 <= ENVIRON["H"] + 0'
    ;;
  rank)
    [ "${#units[@]}" -gt 0 ] || usage
    h=$(horizon_days) || exit 1
    dl=$(listing) || exit 1
    for u in "${units[@]}"; do printf '%s\n' "$u"; done | H=$h DL=$dl awk -F '\t' '
      BEGIN { n = split(ENVIRON["DL"], l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, "\t"); if (f[2] != "") { D[f[2]] = f[3]; L[f[2]] = f[4] } } }
      {
        c = "none"; d = "-"; k = 3
        if ($0 in D) { d = D[$0]; c = "dated"; if (L[$0] + 0 < 0) { c = "overdue"; k = 1 } else if (L[$0] + 0 <= ENVIRON["H"] + 0) { c = "urgent"; k = 2 } }
        key = (k < 3) ? k "\t" d : k "\t" sprintf("%08d", NR)
        print key "\t" $0 "\t" c "\t" d
      }' | sort -t '	' -k1,1n -k2,2 -s | awk -F '\t' '{ print "rank\t" NR "\t" $3 "\t" $4 "\t" $5 }'
    ;;
  watch)
    h=$(horizon_days) || exit 1
    dl=$(listing) || exit 1
    runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
    seen="$runtime/deadlines-announced"
    day=$(today_days)
    rc=0
    live=""
    while IFS='	' read -r w_tag w_unit w_date w_left w_src; do
      [ "$w_tag" = deadline ] && [ "$w_left" -le "$h" ] 2>/dev/null || continue
      live="$live$day	$w_unit	$w_date
"
      w_subject=$w_unit
      mc_valid_handle "$w_subject" || w_subject=$(mc_subject deadline "$w_unit")
      mc_announce "$program" "$seen" "$day	$w_unit	$w_date" deadline-near "$w_subject" \
        "$w_unit due $w_date ($w_left days, $w_src)" || rc=1
    done <<EOF
$dl
EOF
    mc_announce_prune "$seen" "$live" || rc=1
    exit "$rc"
    ;;
  *) usage ;;
esac
