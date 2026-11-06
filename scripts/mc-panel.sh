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
# A tmux server that hangs must not hold the redraw.
TMUX_BOUND=5
TAB=$(printf '\t')

usage() {
  mc_usage_fail "usage: mc-panel.sh digest|line --program <p> [--target <t>] [--knobs] [--now <epoch>] | presence --program <p> --prompt|--refresh [--target <t>] [--now <epoch>]"
}

help_text() {
  cat <<'HELP'
mc-panel.sh — the panel mod's data seam: one digest of every store the
panel draws, the one-line text form a session without the mod reads, and
the presence marker the mod feeds from prompt events.

The mod (hooks/mission-control/) runs `digest` on its redraw timer and
draws only what it prints; nothing here calls a model or writes a store
but the presence marker and, with --target, the target's lease. The mod
is active only in a session started with PLANWRIGHT_MC_PROGRAM=<program>
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
        flight<TAB><worker><TAB><scope><TAB><backend><TAB>working|waiting|stuck
                                             a fleet registry session seen
                                             live (its process or tmux
                                             window still there), `waiting`
                                             when parked on a question,
                                             `stuck` when it stopped
                                             responding; `-` for a field its
                                             record lacks
        finished<TAB><n>                     registry sessions not retired
                                             and not seen live: gone, idle,
                                             ended or done, or with nothing
                                             to watch (rows of a tmux server
                                             that does not answer are in
                                             neither count)
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
        holder<TAB>registry|attended|-       the holder record's kind: only
                                             a registry holder (a session
                                             mission control launched) hands
                                             over; `-` with no readable record
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

Exit codes: 0 done; 1 the program list or the presence marker cannot be
read or written, or a target's lease cannot be written (its directory a
symlink included); 2 usage; 3 the program is not configured.

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
[ -n "$program" ] || usage
case $verb in
  digest | line) [ -z "$presence_kind" ] || usage ;;
  presence) [ -n "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage ;;
  *) usage ;;
esac
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

# A registry row outlives its session until something retires it, so only
# a session seen live is in flight: its process or tmux window still there,
# and the attention store not saying it went idle or ended. The rest are
# counted as finished. Display only: nothing may act on a row this calls
# finished. A pid is probed with the kill builtin, no fork per row (the
# registry runs to hundreds); a pid this user cannot signal is a recycled
# one, since every worker runs as this user, so it reads as gone.
flights() {
  fl_reg=$(/bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null) || {
    printf 'unreadable\tfleet registry\n'
    return 0
  }
  # The last record per worker wins; only an eight-field record whose last
  # field is `closed` is retired, the rule every registry reader applies.
  # Each open row comes out as worker, scope, backend and death handle,
  # an empty or missing field as `-` so the tab-split read below keeps its
  # columns.
  fl_open=$(printf '%s\n' "$fl_reg" | awk -F '\t' '
    NF >= 2 { last[$2] = $0; if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 } }
    END {
      for (i = 1; i <= n; i++) {
        nf = split(last[order[i]], f, "\t")
        if (nf == 8 && f[8] == "closed") continue
        for (j = 1; j <= 7; j++) if (j > nf || f[j] == "") f[j] = "-"
        print f[2] "\t" f[3] "\t" f[5] "\t" f[7]
      }
    }')
  # A server that is not running has no windows; one that does not answer
  # is unknown, and its rows count neither way.
  fl_windows=''
  fl_tmux=1
  case $fl_open in
    *"	tmux-window "*)
      if fl_out=$(/bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" \
        tmux list-windows -a -F '#{session_name}	#{window_id}	#{window_name}' 2>&1); then
        fl_windows=$fl_out
      else
        case $?:$fl_out in
          127:* | *"no server running"* | *"error connecting to"*"No such file or directory"*) ;;
          *)
            fl_tmux=0
            printf 'unreadable\ttmux windows\n'
            ;;
        esac
      fi
      ;;
  esac
  fl_attn=''
  if fl_root=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null); then
    fl_as=$fl_root/attention/state
    if [ -e "$fl_as" ] || [ -L "$fl_as" ]; then
      if [ -L "$fl_as" ] || [ ! -f "$fl_as" ] \
        || ! fl_attn=$(awk -F '\t' 'NF >= 3 { print $1 "\t" $3 }' "$fl_as" 2>/dev/null); then
        fl_attn=''
        printf 'unreadable\tattention store\n'
      fi
    fi
  fi
  # Each row classed as live, a pid to probe, done or unknown. A window id
  # is looked up across the server, as a renamed session keeps its windows.
  fl_class=$(printf '%s\n' "$fl_open" | W=$fl_windows A=$fl_attn T=$fl_tmux awk -F '\t' '
    BEGIN {
      m = split(ENVIRON["W"], wl, "\n")
      for (i = 1; i <= m; i++) if (split(wl[i], x, "\t") == 3) { id[x[2]] = 1; nm[x[1] SUBSEP x[3]] = 1 }
      m = split(ENVIRON["A"], al, "\n")
      for (i = 1; i <= m; i++) if (split(al[i], x, "\t") == 2) st[x[1]] = x[2]
    }
    NF == 4 {
      s = ($1 in st) ? st[$1] : ""
      if (s == "idle" || s == "ended" || s == "done" || s == "merged" || s == "pr-ready") { print "done"; next }
      word = s == "awaiting-input" ? "waiting" : (s == "hung" ? "stuck" : "working")
      row = $1 "\t" $2 "\t" $3 "\t" word
      if ($4 ~ /^process [1-9][0-9]*$/) { print "pid\t" row "\t" substr($4, 9); next }
      if (split($4, h, " ") == 3 && h[1] == "tmux-window") {
        if (ENVIRON["T"] != "1") { print "unknown"; next }
        seen = (h[3] ~ /^@[0-9]+$/) ? (h[3] in id) : ((h[2] SUBSEP h[3]) in nm)
        print (seen ? "live\t" row : "done")
        next
      }
      print "done"
    }')
  fl_live=''
  fl_done=0
  fl_unknown=0
  while IFS="$TAB" read -r fl_class_of fl_w fl_s fl_b fl_word fl_pid; do
    case $fl_class_of in
      live)
        fl_live="$fl_live$fl_w$TAB$fl_s$TAB$fl_b$TAB$fl_word
"
        ;;
      pid)
        if [ "$fl_pid" -gt 1 ] 2>/dev/null && kill -0 "$fl_pid" 2>/dev/null; then
          fl_live="$fl_live$fl_w$TAB$fl_s$TAB$fl_b$TAB$fl_word
"
        else
          fl_done=$((fl_done + 1))
        fi
        ;;
      done) fl_done=$((fl_done + 1)) ;;
      unknown) fl_unknown=$((fl_unknown + 1)) ;;
    esac
  done <<EOF_ROWS
$fl_class
EOF_ROWS
  fl_rows=$(printf '%s' "$fl_live" | awk 'NF { print "flight\t" $0 }' | mc_clean)
  [ -z "$fl_rows" ] || printf '%s\n' "$fl_rows"
  printf 'finished\t%s\n' "$fl_done"
  D_FLIGHT=$(printf '%s' "$fl_rows" | awk 'NF { n++ } END { print n + 0 }')
  # Rows of a server that did not answer may be live: at least, never exactly.
  [ "$fl_unknown" -eq 0 ] || D_FLIGHT="$D_FLIGHT+"
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

# The holder record's kind (scripts/mc-handover.sh writes it): a registry
# holder hands over, an attended one compacts.
holder() {
  hd_f=$runtime/holder
  if [ ! -e "$hd_f" ] && [ ! -L "$hd_f" ]; then
    printf 'holder\t-\n'
    return 0
  fi
  hd_kind=''
  if [ ! -L "$hd_f" ] && mc_format_ok "$hd_f"; then
    hd_session=$(mc_kv "$hd_f" session)
    hd_since=$(mc_kv "$hd_f" since)
    hd_gen=$(mc_kv "$hd_f" generation)
    if mc_valid_handle "$hd_session" && mc_valid_uint "$hd_since" && mc_valid_uint "$hd_gen"; then
      hd_kind=$(mc_kv "$hd_f" kind)
    fi
  fi
  case $hd_kind in
    registry | attended) printf 'holder\t%s\n' "$hd_kind" ;;
    *) printf 'unreadable\tholder record\nholder\t-\n' ;;
  esac
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
  holder
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
