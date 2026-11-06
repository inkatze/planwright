#!/usr/bin/env bash
# mc-panel.sh — the panel mod's data seam: one digest of every store the
# panel draws, the one-line text form a session without the mod reads, the
# presence marker the mod feeds from prompt events, and the record of the
# planwright copy the program's session runs.
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
  mc_usage_fail "usage: mc-panel.sh digest|line --program <p> [--target <t>] [--knobs] [--now <epoch>] | presence --program <p> --prompt|--refresh [--target <t>] [--now <epoch>] | install --program <p> [--root <dir>] [--now <epoch>] | changes --from <version> [--root <dir>]"
}

help_text() {
  cat <<'HELP'
mc-panel.sh — the panel mod's data seam: one digest of every store the
panel draws, the one-line text form a session without the mod reads, the
presence marker the mod feeds from prompt events, and the record of the
planwright copy the program's session runs.

The mod (hooks/mission-control/) runs `digest` on its redraw timer and
draws only what it prints; nothing here calls a model or writes a store
but the presence marker, with --target the target's lease, and the
install record with its event. The mod is active only in a session
started with PLANWRIGHT_MC_PROGRAM=<program>
in its environment (and optionally PLANWRIGHT_MC_TARGET=<its wake
target>, the program's name by default), which it reads once and clears. A store that cannot be read is said as such,
never drawn as empty.

Usage:
  mc-panel.sh digest --program <p> [--target <t>] [--knobs] [--now <epoch>]
      one record per line, tab separated, in this order:
        format<TAB>1
        program<TAB><p>
        taken<TAB><epoch>
        knob<TAB>refresh|tick|reviews-ttl<TAB><seconds>
                                             with --knobs: the mod's redraw
                                             and tick cadences, and the
                                             reviews snapshot's TTL its check
                                             cadence follows
        knob<TAB>handover-context|handover-wakes|handover-compactions<TAB><n>
                                             with --knobs: the handover
                                             trigger's thresholds
        flight<TAB><worker><TAB><scope><TAB><backend>
                                             a live fleet registry session,
                                             `-` for a field its record lacks
        waiting<TAB><n|->                    the operator queue's items, `-`
                                             where the backend surfaces the
                                             queue itself
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
        kb<TAB><age|->                       the knowledge-base index's age,
                                             `-` before it is written
        measure<TAB><name><TAB><value><TAB><age>
                                             the interruption and
                                             settled-share measures, or
                                             measure - none|unreadable -
        reviews<TAB>ok<TAB><age>             the reviews snapshot
                                             (scripts/mc-reviews.sh) and
                                             its age, or
        reviews<TAB>unavailable<TAB><reason> with no rows following
        review-count<TAB>mine|waiting<TAB><n>  the search's full count
        review-mine<TAB><repo><TAB><number><TAB>draft|ready<TAB><ci>
            <TAB><unresolved><TAB>yes|no<TAB><reviewers><TAB><title>
        review-waiting<TAB><repo><TAB><number><TAB>draft|ready
            <TAB><requester><TAB><seconds since requested><TAB><title>
        handover<TAB>available|absent        whether a handover verb is
                                             installed to defer a
                                             compaction for
        unreadable<TAB><store>               a store that could not be read
        line<TAB><text>                      the line form, last
      Stored text has every control byte dropped.
  mc-panel.sh line --program <p> [--target <t>] [--now <epoch>]
      the line form alone, for a session without the mod; it makes every
      read the digest makes, so it is no per-redraw status line
  mc-panel.sh presence --program <p> --prompt|--refresh [--target <t>] [--now <epoch>]
      write the presence marker, the producer side of the operator queue's
      presence input (no queue verb reads it yet), <runtime>/presence:
        format<TAB>1
        producer<TAB>mission-control-panel
        written<TAB><epoch>
        last-prompt<TAB><epoch|->
      --prompt records a prompt event now; --refresh restamps the
      producer and keeps the last prompt, so a marker that stops being
      refreshed means the producer is gone. With --target, the target's
      own lease, <runtime>/leases/<t> (the epoch written), is restamped
      too: what scripts/mc-wake.sh reads to tell a live `mod` target from
      one whose mod died
  mc-panel.sh install --program <p> [--root <dir>] [--now <epoch>]
      compare the planwright copy at <dir> (this script's own copy by
      default; the mod runs the copy it was loaded from) with the one
      recorded for the program, <runtime>/install, and print
        install<TAB>first|same|changed<TAB><version><TAB><root>[<TAB><was>]
      <was> being the recorded version, on changed only. A first record or
      a change (another version, or the same version at another root)
      raises one event, planwright-recorded or planwright-updated, its
      text naming the version, the root and, on a change of version, the
      changelog entries between the two, cut to the event store's cap.
      The record takes the new copy only once the event is stored, so a
      refused event is raised again by the next check; a record that is
      unreadable, or holds a root or version outside its grammar, is
      replaced as if absent, with a warning on stderr.
  mc-panel.sh changes --from <version> [--root <dir>]
      the CHANGELOG.md entries of the copy at <dir> newer than <version>
      and no newer than the copy's own, newest first, one per line:
        change<TAB><version><TAB><section><TAB><entry>
      the entry as plain printable ASCII, its links dropped; exit 1 with
      no readable changelog

Exit codes: 0 done; 1 the program list or the presence marker cannot be
read or written, a target's lease or the install record cannot be
written (its directory a symlink included), the install event is refused,
or the copy's root, version or changelog cannot be read; 2 usage; 3 the
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
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
target=""
now=""
presence_kind=""
with_knobs=0
root=""
from=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now | --root | --from)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
        --root) root=$2 ;;
        --from) from=$2 ;;
      esac
      shift 2
      ;;
    --knobs)
      with_knobs=1
      shift
      ;;
    --prompt | --refresh)
      [ -z "$presence_kind" ] || usage
      presence_kind=${1#--}
      shift
      ;;
    *) usage ;;
  esac
done
case $verb in
  digest | line) [ -z "$presence_kind" ] && [ -z "$root$from" ] || usage ;;
  presence) [ -n "$presence_kind" ] && [ "$with_knobs" -eq 0 ] && [ -z "$root$from" ] || usage ;;
  install) [ -z "$presence_kind$target$from" ] && [ "$with_knobs" -eq 0 ] || usage ;;
  changes)
    [ -n "$from" ] && [ -z "$program$presence_kind$target$now" ] && [ "$with_knobs" -eq 0 ] || usage
    ;;
  *) usage ;;
esac

# valid_version <v>: three dot-separated numbers.
valid_version() {
  case $1 in
    *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
    *.*.*) return 0 ;;
  esac
  return 1
}
# version_newer <a> <b>: whether version <a> is newer than <b>.
version_newer() {
  A=$1 B=$2 awk 'BEGIN {
    split(ENVIRON["A"], x, "."); split(ENVIRON["B"], y, ".")
    for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) exit !(x[i] + 0 > y[i] + 0)
    exit 1 }'
}
[ -z "$from" ] || valid_version "$from" || mc_usage_fail "invalid version '$(sanitize_printable "$from")'"

# load_copy: the planwright copy at --root, else this script's own: its
# canonical root and version.
load_copy() {
  [ -n "$root" ] || root=$script_dir/..
  case $root in /*) ;; *) mc_usage_fail "--root must be an absolute path" ;; esac
  root=$(cd -P -- "$root" 2>/dev/null && pwd -P) || mc_fail "the planwright root is no directory: $(sanitize_printable "$root")"
  case $root in *[[:cntrl:]]*) mc_fail "the planwright root carries a control byte" ;; esac
  lc_manifest=$root/.claude-plugin/plugin.json
  version=""
  if command -v jq >/dev/null 2>&1; then
    version=$(jq -r '.version // empty | strings' "$lc_manifest" 2>/dev/null) || version=""
  fi
  if [ -z "$version" ]; then
    version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$lc_manifest" 2>/dev/null | head -n 1)
  fi
  valid_version "$version" || mc_fail "no version can be read at $lc_manifest"
}

# changes_since <from>: the changelog entries newer than <from>, no newer
# than the copy's own version, as `changes` prints them; fails with no
# readable changelog. Entries are kept to printable ASCII, so a cut text
# never splits a character.
changes_since() {
  [ -f "$root/CHANGELOG.md" ] && [ -r "$root/CHANGELOG.md" ] || return 1
  FROM=$1 TO=$version awk '
    function newer(a, b,   x, y, i) {
      split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) return x[i] + 0 > y[i] + 0
      return 0
    }
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
      v = $2; gsub(/[][]/, "", v); sub(/\(.*/, "", v)
      keep = newer(v, ENVIRON["FROM"]) && !newer(v, ENVIRON["TO"]); section = ""; next
    }
    /^## / { keep = 0; next }
    /^### / { section = substr($0, 5); next }
    keep && /^\* / {
      e = substr($0, 3)
      gsub(/\*\*/, "", e)
      gsub(/ \(\[[0-9a-f]+\]\([^)]*\)\)/, "", e)
      while (match(e, /\[[^]]*\]\([^)]*\)/)) {
        l = substr(e, RSTART, RLENGTH); sub(/\]\(.*/, "", l); sub(/^\[/, "", l)
        e = substr(e, 1, RSTART - 1) l substr(e, RSTART + RLENGTH)
      }
      gsub(/[^ -~]/, "", e); gsub(/[^ -~]/, "", section)
      print "change\t" v "\t" section "\t" e
    }' "$root/CHANGELOG.md"
}

if [ "$verb" = changes ]; then
  load_copy
  changes_since "$from" || mc_fail "no changelog can be read at $root/CHANGELOG.md"
  exit 0
fi
[ -n "$program" ] || usage
[ -z "$target" ] || mc_valid_handle "$target" || mc_usage_fail "invalid target '$(sanitize_printable "$target")'"
mc_require_program "$program"
export PLANWRIGHT_MC_CHECKED="$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"

parse_pct() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100 ] || return 1
  printf '%s\n' "$1"
}
# A ceiling of 0 would raise the handover at once, so 0 is refused.
parse_positive() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] || return 1
  printf '%s\n' "$1"
}

# mtime <file>: its modification epoch, GNU stat first, then BSD.
# shell-gnu-only-flag: BSD stat -f is the fallback when GNU stat -c fails
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# age_of <epoch>: seconds since it, a stamp after now (a stepped clock)
# reading as 0.
age_of() { printf '%s\n' $((NOW > $1 ? NOW - $1 : 0)); }

clean_field() { printf '%s' "$1" | tr -d '\000-\037\177'; }

if [ "$verb" = install ]; then
  load_copy
  rec=$runtime/install
  mc_lock || mc_fail "cannot take the fleet lock"
  # The new record is written beside the old before the event is stored and
  # moved over it after, so a record that cannot be written stores no event.
  rec_tmp=""
  trap 'mc_unlock; [ -z "$rec_tmp" ] || rm -f "$rec_tmp"' EXIT
  mc_now_arg "$now"
  [ -L "$rec" ] || [ ! -d "$rec" ] || mc_fail "the install record is a directory: $rec"
  was_root=""
  was_version=""
  if [ -e "$rec" ] || [ -L "$rec" ]; then
    if [ ! -L "$rec" ] && mc_format_ok "$rec"; then
      was_root=$(awk -F '\t' '$1 == "root" { print $2; exit }' "$rec")
      was_version=$(awk -F '\t' '$1 == "version" { print $2; exit }' "$rec")
    fi
    # A record this script did not write is replaced, never trusted.
    case $was_root in /*) ;; *) was_root="" ;; esac
    case $was_root in *[[:cntrl:]]*) was_root="" ;; esac
    if [ -z "$was_root" ] || ! valid_version "$was_version"; then
      printf '%s\n' "$prog: the install record is unreadable and is replaced: $rec" >&2
      was_root=""
      was_version=""
    fi
  fi
  if [ "$was_root" = "$root" ] && [ "$was_version" = "$version" ]; then
    printf 'install\tsame\t%s\t%s\n' "$version" "$root"
    exit 0
  fi
  rec_tmp=$(mktemp -- "$rec.XXXXXX") || mc_fail "cannot write the install record"
  printf 'format\t%s\nroot\t%s\nversion\t%s\nrecorded\t%s\n' "$MC_FORMAT" "$root" "$version" "$NOW" >"$rec_tmp" \
    || mc_fail "cannot write the install record"
  if [ -z "$was_version" ]; then
    state=first
    kind=planwright-recorded
    text="planwright $version is at $root; no earlier version is on record for this program"
  else
    state=changed
    kind=planwright-updated
    if [ "$was_version" = "$version" ]; then
      text="planwright $version moved to $root from $was_root"
    elif version_newer "$version" "$was_version"; then
      text="planwright updated to $version from $was_version, now at $root"
    else
      text="planwright changed to $version from $was_version (an older version), now at $root"
    fi
    if [ "$was_version" != "$version" ]; then
      entries=$(changes_since "$was_version" | awk -F '\t' '{ printf "%s%s", (NR > 1 ? "; " : ""), $4 }')
      [ -z "$entries" ] || text="$text. Changes: $entries"
    fi
  fi
  # Cut short of mc-event.sh's text cap, saying so.
  if [ "${#text}" -gt 500 ]; then
    text="$(printf '%s' "$text" | cut -c1-497)..."
  fi
  mc_event emit --program "$program" --now "$NOW" -- "$kind" "$program" "$text" >/dev/null \
    || mc_fail "the $kind event could not be stored"
  # mv onto a link to a directory would land inside it, so the link goes.
  if [ -L "$rec" ]; then
    rm -f -- "$rec" || mc_fail "the $kind event is stored but the install record could not be written"
  fi
  mv -f -- "$rec_tmp" "$rec" || mc_fail "the $kind event is stored but the install record could not be written"
  rec_tmp=""
  if [ "$state" = first ]; then
    printf 'install\tfirst\t%s\t%s\n' "$version" "$root"
  else
    printf 'install\tchanged\t%s\t%s\t%s\n' "$version" "$root" "$was_version"
  fi
  exit 0
fi

if [ "$verb" = presence ]; then
  pres=$runtime/presence
  mc_lock || mc_fail "cannot take the fleet lock"
  trap 'mc_unlock' EXIT
  # Stamped once the lock is held, so a write that waited behind a later
  # one never moves the marker back in time.
  mc_now_arg "$now"
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
  if [ -n "$target" ]; then
    # A symlinked lease directory would send the lease, and the relay's read
    # of it, somewhere else.
    [ ! -L "$runtime/leases" ] || mc_fail "the lease directory is a symlink"
    mkdir -p "$runtime/leases" || mc_fail "cannot create the lease directory"
    printf '%s\n' "$NOW" | mc_write "$runtime/leases/$target" || mc_fail "cannot write the lease for '$target'"
  fi
  exit 0
fi
mc_now_arg "$now"

# Each read below prints its records; a store it cannot read prints
# `unreadable<TAB><store>` and the digest goes on.
# A count from a store that could not be read is unknown, never a number.
D_FLIGHT='?'
D_WAITING='?'
D_PENDING='?'
D_RUNG=-
D_OLDEST=""
HOME_DIR=""

knobs() {
  for kn in refresh:mission_control_panel_refresh:mc_parse_cadence \
    tick:mission_control_tick_cadence:mc_parse_cadence \
    reviews-ttl:mission_control_reviews_ttl:mc_parse_cadence \
    handover-context:mission_control_handover_context:parse_pct \
    handover-wakes:mission_control_handover_wakes:parse_positive \
    handover-compactions:mission_control_handover_compactions:parse_positive; do
    kn_name=${kn%%:*}
    kn_rest=${kn#*:}
    if kn_v=$(mc_knob "${kn_rest%%:*}" "${kn_rest#*:}"); then
      case $kn_name in refresh | tick | reviews-ttl) kn_v=$(mc_seconds "$kn_v") ;; esac
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
  # The last record per worker wins; only an eight-field record whose last
  # field is `closed` is retired, the rule every registry reader applies.
  fl_rows=$(printf '%s\n' "$fl_reg" | awk -F '\t' '
    NF >= 2 { last[$2] = $0; if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 } }
    END {
      for (i = 1; i <= n; i++) {
        nf = split(last[order[i]], f, "\t")
        if (nf == 8 && f[8] == "closed") continue
        print "flight\t" f[2] "\t" (nf >= 3 ? f[3] : "-") "\t" (nf >= 5 ? f[5] : "-")
      }
    }' | mc_clean)
  [ -z "$fl_rows" ] || printf '%s\n' "$fl_rows"
  D_FLIGHT=$(printf '%s' "$fl_rows" | awk 'NF { n++ } END { print n + 0 }')
}

waiting() {
  if ! wt_n=$(/bin/sh "$script_dir/fleet-attention.sh" queue --count 2>/dev/null); then
    printf 'unreadable\toperator queue\n'
  elif [ -z "$wt_n" ]; then
    # The backend surfaces the queue itself and the count is deferred to it.
    printf 'waiting\t-\n'
  elif mc_valid_uint "$wt_n"; then
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

program_home() {
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home 2>/dev/null) || {
    HOME_DIR=""
    printf 'unreadable\tprogram home\n'
  }
}

decisions() {
  [ -n "$HOME_DIR" ] || return 0
  dc_kb=$HOME_DIR/kb
  [ ! -L "$dc_kb" ] || {
    printf 'unreadable\tdecisions log\n'
    return 0
  }
  # Segment names sort by month, so the newest decisions are at the end of
  # the newest segments; only the last two are read.
  dc_segs=""
  set +f
  for dc_f in "$dc_kb"/decisions-[0-9][0-9][0-9][0-9]-[0-9][0-9].log; do
    [ -e "$dc_f" ] || [ -L "$dc_f" ] || continue
    dc_segs="$dc_segs$dc_f
"
  done
  set -f
  [ -n "$dc_segs" ] || return 0
  dc_rows=""
  while IFS= read -r dc_f; do
    [ -n "$dc_f" ] || continue
    if [ -L "$dc_f" ] || [ "$(head -n 1 "$dc_f" 2>/dev/null)" != "# format: 1" ]; then
      printf 'unreadable\tdecisions log\n'
      return 0
    fi
    dc_rows="$dc_rows$(tail -n "$DECISIONS_SHOWN" "$dc_f")
"
  done <<EOF
$(printf '%s' "$dc_segs" | tail -n 2)
EOF
  printf '%s' "$dc_rows" | awk -F '\t' -v max="$DECISIONS_SHOWN" '
    NF >= 4 && $2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { row[++n] = $2 "\t" $3 "\t" $4 }
    END { for (i = n; i > 0 && i > n - max; i--) print "decision\t" row[i] }' | mc_clean
}

budget() {
  bg_file=$runtime/budget
  if [ -L "$bg_file" ]; then
    printf 'unreadable\tbudget\n'
    return 0
  fi
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
  # Soonest (or most overdue) first, so a panel showing only the first few
  # never hides an expiry.
  printf '%s\n' "$wa" | awk -F '\t' '$1 == "watcher" {
      n = split($3, p, "/")
      key = ($8 ~ /^-?[0-9]+$/) ? $8 + 0 : 999999999999
      printf "%015d\twatcher\t%s\t%s\t%s\t%s\n", key + 500000000000, $2, p[n], $6, $8
    }' | sort | cut -f2- | mc_clean
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
  if [ -z "$HOME_DIR" ]; then
    printf 'unreadable\tknowledge base\n'
    return 0
  fi
  if [ -L "$HOME_DIR/kb" ] || { [ -e "$HOME_DIR/kb" ] && { ! [ -r "$HOME_DIR/kb" ] || ! [ -x "$HOME_DIR/kb" ]; }; }; then
    printf 'unreadable\tknowledge base\n'
  elif [ ! -e "$HOME_DIR/kb/index.md" ]; then
    printf 'kb\t-\n'
  elif kb_t=$(mtime "$HOME_DIR/kb/index.md") && mc_valid_uint "$kb_t"; then
    printf 'kb\t%s\n' "$(age_of "$kb_t")"
  else
    printf 'unreadable\tknowledge base\n'
  fi
}

measures() {
  ms=$runtime/measures
  if [ -L "$ms" ]; then
    printf 'measure\t-\tunreadable\t-\n'
    return 0
  fi
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
  ! mc_valid_uint "$ms_taken" || ms_age=$(age_of "$ms_taken")
  ms_rows=$(awk -F '\t' -v age="$ms_age" '
    ($1 == "interruptions_per_hour" || $1 == "settled_share") && $2 ~ /^[0-9]+(\.[0-9]+)?$/ { print "measure\t" $1 "\t" $2 "\t" age }' "$ms")
  if [ -n "$ms_rows" ]; then
    printf '%s\n' "$ms_rows"
  else
    printf 'measure\t-\tnone\t-\n'
  fi
}

# The reviews snapshot scripts/mc-reviews.sh writes, its ages taken from
# now; anything but a well-formed snapshot is unavailable, with the reason.
reviews() {
  rv=$runtime/reviews
  if [ ! -e "$rv" ] && [ ! -L "$rv" ]; then
    printf 'reviews\tunavailable\tno snapshot yet\n'
    return 0
  fi
  if [ -L "$rv" ] || ! mc_format_ok "$rv"; then
    printf 'reviews\tunavailable\tthe snapshot is unreadable\n'
    return 0
  fi
  N=$NOW awk -F '\t' '
    $1 == "taken" && $2 ~ /^[0-9]+$/ { taken = $2 + 0; has_taken = 1 }
    $1 == "state" && !has_state { state = $2; reason = $3; has_state = 1 }
    $1 == "count" && ($2 == "mine" || $2 == "waiting") && $3 ~ /^[0-9]+$/ { count[++c] = "review-count\t" $2 "\t" $3 }
    $1 == "mine" && NF >= 9 { mine[++m] = "review-mine\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9 }
    $1 == "waiting" && NF >= 7 && $6 ~ /^[0-9]+$/ {
      age = ENVIRON["N"] - $6; if (age < 0) age = 0
      waiting[++w] = "review-waiting\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" age "\t" $7
    }
    END {
      if (!has_taken || (state != "ok" && state != "unavailable")) {
        print "reviews\tunavailable\tthe snapshot is unreadable"; exit
      }
      if (state == "unavailable") { print "reviews\tunavailable\t" (reason == "" ? "no reason given" : reason); exit }
      age = ENVIRON["N"] - taken; if (age < 0) age = 0
      print "reviews\tok\t" age
      for (i = 1; i <= c; i++) print count[i]
      for (i = 1; i <= m; i++) print mine[i]
      for (i = 1; i <= w; i++) print waiting[i]
    }' "$rv" | mc_clean_text
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
  [ "$with_knobs" -eq 0 ] || knobs
  flights
  waiting
  pending
  program_home
  decisions
  budget
  watchers
  sources
  kb
  measures
  reviews
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
