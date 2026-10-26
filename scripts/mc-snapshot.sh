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
# with the program's first repository as the working directory and
# PLANWRIGHT_MC_PROGRAM=<p> in the environment. The adapter writes the
# snapshot body to <file>, tab-separated lines of its own shape; --previous
# names the last snapshot, so an adapter can carry forward what has not
# changed. On stdout it may print
#   ratelimit<TAB><remaining><TAB><reset-epoch>
# and the seam holds the source's next read until <reset-epoch> when
# <remaining> is at or under mission_control_ratelimit_floor. Exit 0: the
# body is the new snapshot. Exit 75: the source refused the read for its rate
# limit; nothing is replaced, and with no reset at or under the floor the
# hold lasts the source's cadence. Any other exit: the read failed, the last snapshot stays
# and keeps aging. Every hold is clamped to the later of the cadence and an
# hour, and a reset already past is ignored. The adapter's stderr is passed
# through with control bytes stripped.
#
# A SNAPSHOT is <runtime>/snapshots/<source>:
#   format<TAB>1
#   source<TAB><source>
#   taken<TAB><epoch>
#   <body lines>
# and <runtime>/snapshots/<source>.hold holds the epoch a held source waits
# for. Refreshes are serialized by the runner's pass (scripts/mc-watch.sh);
# a refresh run by hand beside a live runner may read a source twice.
#
# Usage:
#   mc-snapshot.sh refresh --program <p> [--source <s>] [--now <epoch>] [--rung <rung>]
#       refresh every snapshot-mode source (or one) that is due, printing
#       one line per source:
#         refreshed<TAB><s>            the adapter read it
#         fresh<TAB><s><TAB><age>      younger than its cadence; no read
#         held<TAB><s><TAB><until>     waiting for a rate limit to reset
#         capped<TAB><s>               the budget's polls per hour are spent
#         failed<TAB><s><TAB><exit>    the adapter failed (`poll` when the
#                                      poll count did)
#       or a problem on stderr, with no line, for a source with no usable
#       adapter or an invalid cadence entry (exit 1);
#       or `paused` under the fleet daemon pause (`blocked<TAB><exit>` when
#       the gate itself is broken), with nothing read. Each read counts one
#       poll against the budget (scripts/mc-budget.sh). At any budget rung
#       above normal every cadence doubles; --rung passes the rung in (the
#       runner's, just computed) instead of computing it again.
#   mc-snapshot.sh read --program <p> <source> [--now <epoch>]
#       the snapshot, after one status line:
#         source<TAB><s><TAB>mode<TAB>snapshot<TAB>age<TAB><secs><TAB>cadence<TAB><secs><TAB>fresh|stale
#       stale once its age passes its configured cadence. Never reads the
#       source.
#   mc-snapshot.sh list --program <p> [--now <epoch>]
#       class<TAB>source<TAB>mode<TAB>age, one line per fact class, age `-`
#       for a record or cited source and for a snapshot not yet taken
#   mc-snapshot.sh adapters
#       id<TAB>script<TAB>cadence per valid merged entry, and
#       bad<TAB><id><TAB><problem> per invalid one
#   mc-snapshot.sh check (--program <p> | --defaults)
#       every snapshot-mode source in the program's map (or the shipped
#       default map) has an adapter entry with an id, a summary, a script
#       path of the catalog's grammar and a cadence (whether the script
#       exists is refresh's question); each problem on stderr as
#       mc-snapshot: <program>: sources: <problem>, the label being
#       mission_control_default_sources under --defaults
#
# Exit codes: 0 done; 1 a failed read, a missing adapter (check), an invalid
# catalog or snapshot, a store that cannot be written, or a blocked daemon
# gate; 2 usage; 3 the program is not configured, or no snapshot of the
# source yet (read).
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
  mc_usage_fail "usage: mc-snapshot.sh refresh --program <p> [--source <s>] [--now <epoch>] [--rung <rung>] | read --program <p> <source> [--now <epoch>] | list --program <p> [--now <epoch>] | adapters | check (--program <p> | --defaults)"
}

[ $# -ge 1 ] || usage
verb=$1
shift
program=""
source_only=""
now=""
rung=""
defaults=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --source | --now | --rung)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --source) source_only=$2 ;;
        --now) now=$2 ;;
        --rung) rung=$2 ;;
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
mc_now_arg "$now"
[ -z "$source_only" ] || mc_valid_kebab "$source_only" || mc_usage_fail "invalid source '$(sanitize_printable "$source_only")'"
[ -z "$rung" ] || mc_valid_kebab "$rung" || mc_usage_fail "invalid rung '$(sanitize_printable "$rung")'"

# load_adapters: ADAPTERS, id<TAB>script<TAB>cadence per valid merged entry
# and a `bad<TAB><id><TAB><problem>` line per invalid one.
load_adapters() {
  la_cat=$(/bin/bash "$script_dir/resolve-catalog.sh" snapshot-adapters 2>/dev/null) \
    || mc_fail "the snapshot-adapters catalog does not resolve"
  ADAPTERS=$(printf '%s\n' "$la_cat" | awk '
    function trim(s) { sub(/^[ ]+/, "", s); sub(/[ ]+$/, "", s); return s }
    function unq(s) { if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function flush() {
      if (id == "") return
      if (id !~ /^[a-z0-9][a-z0-9-]*$/) print "bad\t" id "\tid: not kebab"
      else if (summary == "") print "bad\t" id "\tsummary: missing"
      else if (script == "") print "bad\t" id "\tscript: missing"
      else if (script ~ /^[\/-]/ || script ~ /[^A-Za-z0-9._\/-]/ || script ~ /(^|\/)\.\.(\/|$)/) print "bad\t" id "\tscript: not a relative path of the catalog grammar"
      else if (cadence == "") print "bad\t" id "\tcadence: missing"
      else print id "\t" script "\t" cadence
    }
    /^  - id:/ { flush(); id = unq(trim(substr($0, index($0, ":") + 1))); summary = ""; script = ""; cadence = ""; next }
    /^    summary:/ { summary = unq(trim(substr($0, index($0, ":") + 1))); next }
    /^    script:/ { script = unq(trim(substr($0, index($0, ":") + 1))); next }
    /^    cadence:/ { cadence = unq(trim(substr($0, index($0, ":") + 1))); next }
    END { flush() }')
}

# adapter <source>: sets A_SCRIPT and A_CADENCE (seconds), or A_PROBLEM and
# status 1 when the source has no valid entry.
adapter() {
  ad_row=$(printf '%s\n' "$ADAPTERS" | S=$1 awk -F '\t' '$1 == ENVIRON["S"] || ($1 == "bad" && $2 == ENVIRON["S"]) { print; exit }')
  case $ad_row in
    "")
      A_PROBLEM="snapshot source '$1' has no registered adapter"
      return 1
      ;;
    "bad	"*)
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
  co_v=$(mc_lookup "$1" "$CADENCES")
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

# taken_of <file>: the snapshot's epoch; fails on a missing or malformed
# header and on an epoch after now, which a stepped clock or an edited file
# leaves and which would otherwise read as fresh until the clock caught up.
taken_of() {
  mc_format_ok "$1" || return 1
  to_t=$(awk -F '\t' 'NR == 3 && $1 == "taken" { print $2; ok = 1; exit } END { exit !ok }' "$1") || return 1
  mc_valid_uint "$to_t" && [ "$to_t" -le "$NOW" ] || return 1
  printf '%s\n' "$to_t"
}

case $verb in
  adapters)
    [ "${#args[@]}" -eq 0 ] && [ -z "$program" ] || usage
    load_adapters
    printf '%s\n' "$ADAPTERS" | mc_clean
    exit 0
    ;;
  check)
    [ "${#args[@]}" -eq 0 ] || usage
    if [ "$defaults" -eq 1 ]; then
      [ -z "$program" ] || usage
      label=mission_control_default_sources
      map=$(/bin/bash "$script_dir/mc-program.sh" default sources) || exit 1
    else
      [ -n "$program" ] || usage
      mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
      label=$program
      map=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || exit 1
    fi
    load_adapters
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
        age=$((NOW - t))
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
    load_adapters
    adapter "$src" || mc_fail "$A_PROBLEM"
    CADENCES=$(mc_knob mission_control_snapshot_cadence mc_map) || exit 1
    cad=$(cadence_of "$src") || exit 1
    [ -f "$snapdir/$src" ] || {
      printf '%s\n' "$prog: no snapshot of '$src' yet" >&2
      exit 3
    }
    t=$(taken_of "$snapdir/$src") || mc_fail "snapshot of '$src': format: unknown format or a malformed header"
    age=$((NOW - t))
    state=fresh
    [ "$age" -le "$cad" ] || state=stale
    printf 'source\t%s\tmode\tsnapshot\tage\t%s\tcadence\t%s\t%s\n' "$src" "$age" "$cad" "$state"
    tail -n +4 "$snapdir/$src" | mc_clean
    ;;
  refresh)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-snapshot
    floor=$(mc_knob mission_control_ratelimit_floor mc_parse_uint) || exit 1
    CADENCES=$(mc_knob mission_control_snapshot_cadence mc_map) || exit 1
    load_adapters
    if [ -z "$rung" ]; then
      # A rung that cannot be computed is read as pressure, not as headroom.
      rung=$(/bin/bash "$script_dir/mc-budget.sh" rung --program "$program" --now "$NOW") || rung=unknown
    fi
    factor=$(mc_cadence_factor "$rung")
    repo1=""
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
      if t=$(taken_of "$snapdir/$src") && [ $((NOW - t)) -lt "$cad" ]; then
        printf 'fresh\t%s\t%s\n' "$src" $((NOW - t))
        continue
      fi
      if [ -f "$snapdir/$src.hold" ]; then
        hold_until=$(head -n 1 "$snapdir/$src.hold")
        # A stored hold is clamped on read as well as on write.
        hold_max=$((NOW + (cad > 3600 ? cad : 3600)))
        if mc_valid_uint "$hold_until" && [ "$hold_until" -gt "$hold_max" ]; then
          hold_until=$hold_max
          # Written back, or a clamp taken from now would hold it forever.
          printf '%s\n' "$hold_until" | mc_write "$snapdir/$src.hold" || mc_fail "cannot record the hold for '$src'"
        fi
        if mc_valid_uint "$hold_until" && [ "$NOW" -lt "$hold_until" ]; then
          printf 'held\t%s\t%s\n' "$src" "$hold_until"
          continue
        fi
      fi
      script=$(mc_resolve_script "$A_SCRIPT" "$program") || {
        printf '%s\n' "$prog: $program: sources: adapter script '$(sanitize_printable "$A_SCRIPT")' for '$src' not found" >&2
        status=1
        continue
      }
      if [ -z "$repo1" ]; then
        repos=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories) || exit 1
        repo1=$(printf '%s\n' "$repos" | head -n 1)
        [ -d "$repo1" ] || mc_fail "the program's first repository is not a directory"
      fi
      /bin/bash "$script_dir/mc-budget.sh" poll --program "$program" "$src" --now "$NOW" >/dev/null
      case $? in
        0) ;;
        4)
          printf 'capped\t%s\n' "$src"
          continue
          ;;
        *)
          printf 'failed\t%s\tpoll\n' "$src"
          status=1
          continue
          ;;
      esac
      body=$(mktemp "$snapdir/.$src.body.XXXXXX") || mc_fail "cannot stage a snapshot"
      errs=$(mktemp "$snapdir/.$src.err.XXXXXX") || {
        rm -f "$body"
        mc_fail "cannot stage a snapshot"
      }
      prev=()
      [ ! -f "$snapdir/$src" ] || prev=(--previous "$snapdir/$src")
      out=$(cd "$repo1" && PLANWRIGHT_MC_PROGRAM=$program /bin/bash "$script" refresh \
        --program "$program" --out "$body" ${prev[@]+"${prev[@]}"} 2>"$errs")
      rc=$?
      mc_clean <"$errs" >&2
      rm -f "$errs"
      # A reset is taken only when it is a plausible epoch: in the future and
      # short enough for shell arithmetic.
      rl=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "ratelimit" && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && length($2) <= 12 && length($3) <= 12 { r = $2 "\t" $3 } END { print r }')
      longest=$((cad > 3600 ? cad : 3600))
      hold=""
      if [ -n "$rl" ] && [ "${rl%%	*}" -le "$floor" ] && [ "${rl#*	}" -gt "$NOW" ]; then
        hold=${rl#*	}
      elif [ "$rc" -eq 75 ]; then
        hold=$((NOW + cad))
      fi
      if [ -n "$hold" ] && [ "$hold" -gt $((NOW + longest)) ]; then
        hold=$((NOW + longest))
      fi
      if [ -n "$hold" ]; then
        printf '%s\n' "$hold" | mc_write "$snapdir/$src.hold" || {
          rm -f "$body"
          mc_fail "cannot record the hold for '$src'"
        }
      else
        rm -f "$snapdir/$src.hold"
      fi
      case $rc in
        0)
          {
            printf 'format\t%s\nsource\t%s\ntaken\t%s\n' "$MC_FORMAT" "$src" "$NOW"
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
