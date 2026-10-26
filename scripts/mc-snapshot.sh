#!/usr/bin/env bash
# mc-snapshot.sh — the source snapshot seam: one age-stamped snapshot per
# snapshot-mode source per program, refreshed by the source's adapter, read
# by every duty. No duty polls a source itself.
#
# The program's state-source map (scripts/mc-program.sh get <p> sources)
# names the sources; those in `snapshot` mode are refreshed here. Each needs
# an adapter in the merged snapshot-adapters catalog
# (config/snapshot-adapters.yaml and its overlays, the header there holding
# the entry grammar). A source's cadence is its mission_control_snapshot_cadence
# entry, else the adapter's own.
#
# THE ADAPTER CONTRACT. The seam runs
#   <script> refresh --program <p> --out <file> [--previous <file>]
# with the program's first repository as the working directory. The adapter
# writes the snapshot body to <file>, tab-separated lines of its own shape;
# --previous names the last snapshot, so an adapter can carry forward what
# has not changed. On stdout it may print
#   ratelimit<TAB><remaining><TAB><reset-epoch>
# and the seam holds the source's next read until <reset-epoch> when
# <remaining> is at or under mission_control_ratelimit_floor. Exit 0: the
# body is the new snapshot. Exit 75: the source refused the read for its rate
# limit; nothing is replaced, and the hold applies even with no ratelimit
# line (for the source's cadence). Any other exit: the read failed, the last
# snapshot stays and keeps aging. Stderr is passed through.
#
# A SNAPSHOT is <runtime>/snapshots/<source>:
#   format<TAB>1
#   source<TAB><source>
#   taken<TAB><epoch>
#   <body lines>
# and <runtime>/snapshots/<source>.hold holds the epoch a held source waits
# for.
#
# Usage:
#   mc-snapshot.sh refresh --program <p> [--source <s>] [--now <epoch>]
#       refresh every snapshot-mode source (or one) that is due, printing
#       one line per source:
#         refreshed<TAB><s>            the adapter read it
#         fresh<TAB><s><TAB><age>      younger than its cadence; no read
#         held<TAB><s><TAB><until>     waiting for a rate limit to reset
#         capped<TAB><s>               the budget's polls per hour are spent
#         failed<TAB><s><TAB><exit>    the adapter failed
#         paused                       the fleet daemon pause; nothing read
#       Each read counts one poll against the budget (scripts/mc-budget.sh).
#       Under the budget's throttle rung every cadence doubles.
#   mc-snapshot.sh read --program <p> <source> [--now <epoch>]
#       the snapshot, after one status line:
#         source<TAB><s><TAB>mode<TAB>snapshot<TAB>age<TAB><secs><TAB>cadence<TAB><secs><TAB>fresh|stale
#       stale once its age passes its cadence. Never reads the source.
#   mc-snapshot.sh list --program <p> [--now <epoch>]
#       class<TAB>source<TAB>mode<TAB>age, one line per fact class, age `-`
#       for a record or cited source and for a snapshot not yet taken
#   mc-snapshot.sh adapters
#       id<TAB>script<TAB>cadence per merged catalog entry
#   mc-snapshot.sh check (--program <p> | --defaults)
#       every snapshot-mode source in the program's map (or the shipped
#       default map) has a valid adapter entry; each problem on stderr as
#       <program>: sources: <problem>
#
# Exit codes: 0 done; 1 a failed read, a missing adapter (check), an invalid
# catalog or snapshot, or a store that cannot be written; 2 usage; 3 the
# program is not configured, or no snapshot of the source yet (read).
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-snapshot
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
  mc_usage_fail "usage: mc-snapshot.sh refresh --program <p> [--source <s>] | read --program <p> <source> | list --program <p> | adapters | check (--program <p> | --defaults) [--now <epoch>]"
}

[ $# -ge 1 ] || usage
verb=$1
shift
program=""
source_only=""
now=""
defaults=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --source | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --source) source_only=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --defaults)
      defaults=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
if [ -n "$now" ]; then
  mc_valid_uint "$now" || mc_usage_fail "--now takes an epoch"
else
  now=$(mc_now)
fi
if [ -n "$program" ]; then
  mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
fi
[ -z "$source_only" ] || mc_valid_kebab "$source_only" || mc_usage_fail "invalid source '$(sanitize_printable "$source_only")'"

# adapters: id<TAB>script<TAB>cadence per merged entry; an entry missing a
# field or breaking its grammar is a `bad<TAB><id><TAB><problem>` line.
adapter_rows() {
  ar_cat=$(/bin/bash "$script_dir/resolve-catalog.sh" snapshot-adapters 2>/dev/null) || return 1
  printf '%s\n' "$ar_cat" | awk '
    function trim(s) { sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s); return s }
    function unq(s) { if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function flush() {
      if (id == "") return
      if (script == "") print "bad\t" id "\tscript: missing"
      else if (cadence == "") print "bad\t" id "\tcadence: missing"
      else if (id !~ /^[a-z0-9][a-z0-9-]*$/) print "bad\t" id "\tid: not kebab"
      else print id "\t" script "\t" cadence
    }
    /^  - id:/ { flush(); id = unq(trim(substr($0, index($0, ":") + 1))); script = ""; cadence = ""; next }
    /^    script:/ { script = unq(trim(substr($0, index($0, ":") + 1))); next }
    /^    cadence:/ { cadence = unq(trim(substr($0, index($0, ":") + 1))); next }
    END { flush() }'
}

# adapter <source>: sets A_SCRIPT and A_CADENCE (seconds); a problem on
# stderr and status 1 when the source has no valid entry.
adapter() {
  ad_row=$(adapter_rows | awk -F '\t' -v s="$1" '$1 == s || ($1 == "bad" && $2 == s) { print; exit }')
  case $ad_row in
    "")
      A_PROBLEM="snapshot source '$1' has no registered adapter"
      return 1
      ;;
    bad*)
      A_PROBLEM="snapshot source '$1': adapter $(printf '%s' "$ad_row" | cut -f3)"
      return 1
      ;;
  esac
  A_SCRIPT=$(printf '%s' "$ad_row" | cut -f2)
  ad_cad=$(printf '%s' "$ad_row" | cut -f3)
  A_CADENCE=$(mc_seconds "$ad_cad") || {
    A_PROBLEM="snapshot source '$1': adapter cadence '$ad_cad' is not a cadence"
    return 1
  }
  return 0
}

# cadence_of <source>: seconds; the knob's entry, else the adapter's.
cadence_of() {
  co_map=$(mc_knob mission_control_snapshot_cadence mc_map) || return 1
  co_v=$(mc_lookup "$1" "$co_map")
  if [ -n "$co_v" ]; then
    mc_seconds "$co_v" || {
      printf '%s\n' "$prog: mission_control_snapshot_cadence: $1: '$(sanitize_printable "$co_v")' is not a cadence" >&2
      return 1
    }
    return 0
  fi
  printf '%s\n' "$A_CADENCE"
}

# snapshot_sources <map rows>: the distinct sources in snapshot mode.
snapshot_sources() {
  printf '%s\n' "$1" | awk -F '\t' '$3 == "snapshot" && !seen[$2]++ { print $2 }'
}

taken_of() {
  [ -f "$1" ] || return 1
  awk -F '\t' 'NR == 1 && ($1 != "format" || $2 != "1") { exit 1 }
    NR == 3 { if ($1 == "taken" && $2 ~ /^[0-9]+$/) { print $2; exit 0 } exit 1 }' "$1"
}

case $verb in
  adapters)
    [ "${#args[@]}" -eq 0 ] && [ -z "$program" ] || usage
    rows=$(adapter_rows) || mc_fail "the snapshot-adapters catalog does not resolve"
    printf '%s\n' "$rows" | mc_clean
    ;;
  check)
    [ "${#args[@]}" -eq 0 ] || usage
    if [ "$defaults" -eq 1 ]; then
      [ -z "$program" ] || usage
      label=mission_control_default_sources
      map=$(/bin/bash "$script_dir/mc-program.sh" default sources) || exit 1
    else
      [ -n "$program" ] || usage
      label=$program
      map=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || exit 1
    fi
    bad=0
    for s in $(snapshot_sources "$map"); do
      if ! adapter "$s"; then
        printf '%s\n' "$prog: $label: sources: $(sanitize_printable "$A_PROBLEM")" >&2
        bad=1
      fi
    done
    exit "$bad"
    ;;
esac

[ -n "$program" ] || usage
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
snapdir="$runtime/snapshots"
mkdir -p "$snapdir" || mc_fail "cannot create the snapshot directory"
map=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || exit 1

case $verb in
  list)
    [ "${#args[@]}" -eq 0 ] || usage
    printf '%s\n' "$map" | while IFS='	' read -r cls src mode; do
      [ -n "$cls" ] || continue
      age=-
      if [ "$mode" = snapshot ] && t=$(taken_of "$snapdir/$src"); then
        age=$((now - t))
      fi
      printf '%s\t%s\t%s\t%s\n' "$cls" "$src" "$mode" "$age"
    done
    ;;
  read)
    [ "${#args[@]}" -eq 1 ] || usage
    src=${args[0]}
    mc_valid_kebab "$src" || mc_usage_fail "invalid source '$(sanitize_printable "$src")'"
    case "
$(snapshot_sources "$map")
" in
      *"
$src
"*) ;;
      *) mc_fail "'$src' is not a snapshot-mode source of program '$program'" ;;
    esac
    adapter "$src" || mc_fail "$A_PROBLEM"
    cad=$(cadence_of "$src") || exit 1
    [ -f "$snapdir/$src" ] || {
      printf '%s\n' "$prog: no snapshot of '$src' yet" >&2
      exit 3
    }
    t=$(taken_of "$snapdir/$src") || mc_fail "snapshot of '$src': format: unknown format or a malformed header"
    age=$((now - t))
    state=fresh
    [ "$age" -le "$cad" ] || state=stale
    printf 'source\t%s\tmode\tsnapshot\tage\t%s\tcadence\t%s\t%s\n' "$src" "$age" "$cad" "$state"
    tail -n +4 "$snapdir/$src" | mc_clean
    ;;
  refresh)
    [ "${#args[@]}" -eq 0 ] || usage
    if ! /bin/sh "$script_dir/fleet-daemon-gate.sh" mc-snapshot >/dev/null 2>&1; then
      printf 'paused\n'
      exit 0
    fi
    floor=$(mc_knob mission_control_ratelimit_floor mc_is_uint) || exit 1
    factor=1
    rung=$(/bin/bash "$script_dir/mc-budget.sh" rung --program "$program" --now "$now" 2>/dev/null) || rung=normal
    [ "$rung" = normal ] || factor=2
    repo1=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories | head -n 1)
    status=0
    for src in $(snapshot_sources "$map"); do
      [ -z "$source_only" ] || [ "$src" = "$source_only" ] || continue
      if ! adapter "$src"; then
        printf '%s\n' "$prog: $program: sources: $(sanitize_printable "$A_PROBLEM")" >&2
        status=1
        continue
      fi
      cad=$(cadence_of "$src") || {
        status=1
        continue
      }
      cad=$((cad * factor))
      if t=$(taken_of "$snapdir/$src") && [ $((now - t)) -lt "$cad" ]; then
        printf 'fresh\t%s\t%s\n' "$src" $((now - t))
        continue
      fi
      if [ -f "$snapdir/$src.hold" ]; then
        until=$(head -n 1 "$snapdir/$src.hold")
        if mc_valid_uint "$until" && [ "$now" -lt "$until" ]; then
          printf 'held\t%s\t%s\n' "$src" "$until"
          continue
        fi
      fi
      script=$(mc_resolve_script "$A_SCRIPT" "$program") || {
        printf '%s\n' "$prog: $program: sources: adapter script '$(sanitize_printable "$A_SCRIPT")' for '$src' not found" >&2
        status=1
        continue
      }
      if ! /bin/bash "$script_dir/mc-budget.sh" poll --program "$program" "$src" --now "$now" >/dev/null; then
        printf 'capped\t%s\n' "$src"
        continue
      fi
      body=$(mktemp "$snapdir/.$src.body.XXXXXX") || mc_fail "cannot stage a snapshot"
      prev=()
      [ ! -f "$snapdir/$src" ] || prev=(--previous "$snapdir/$src")
      out=$(cd "${repo1:-.}" && PLANWRIGHT_MC_PROGRAM=$program /bin/bash "$script" refresh \
        --program "$program" --out "$body" ${prev[@]+"${prev[@]}"})
      rc=$?
      rl=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "ratelimit" && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { r = $2 "\t" $3 } END { print r }')
      hold=""
      if [ -n "$rl" ] && [ "${rl%%	*}" -le "$floor" ]; then
        hold=${rl#*	}
      elif [ "$rc" -eq 75 ]; then
        hold=$((now + cad))
      fi
      if [ -n "$hold" ]; then
        printf '%s\n' "$hold" | mc_write "$snapdir/$src.hold" || mc_fail "cannot record the hold for '$src'"
      else
        rm -f "$snapdir/$src.hold"
      fi
      case $rc in
        0)
          {
            printf 'format\t%s\nsource\t%s\ntaken\t%s\n' "$MC_FORMAT" "$src" "$now"
            cat "$body"
          } | mc_write "$snapdir/$src" || {
            rm -f "$body"
            mc_fail "cannot write the snapshot of '$src'"
          }
          printf 'refreshed\t%s\n' "$src"
          ;;
        75) printf 'held\t%s\t%s\n' "$src" "$hold" ;;
        *)
          printf 'failed\t%s\t%s\n' "$src" "$rc"
          status=1
          ;;
      esac
      rm -f "$body"
    done
    exit "$status"
    ;;
  *) usage ;;
esac
