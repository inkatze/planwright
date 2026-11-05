#!/usr/bin/env bash
# mc-panel.sh — the panel mod's data seam: one digest of every store the
# panel draws, the text forms a session without the mod reads, the presence
# marker the mod feeds from prompt events, and the activation record that
# turns the mod on in a mission-control session with no setup.
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
  mc_usage_fail "usage: mc-panel.sh digest|line|text|presence|activate|await|lookup|ack|retire|prune|where|floor|session-hook ... (mc-panel.sh --help)"
}

help_text() {
  cat <<'HELP'
mc-panel.sh — the panel mod's data seam: one digest of every store the
panel draws, the text forms a session without the mod reads, the presence
marker the mod feeds from prompt events, and the activation record that
turns the mod on in a mission-control session with no setup.

The mod (hooks/mission-control/) runs `digest` on its redraw timer and
draws only what it prints; nothing here calls a model or writes a store
but the presence marker, with --target the target's lease, and the
activation files below. A store that cannot be read is said as such,
never drawn as empty.

ACTIVATION. The mod turns on in a session whose own activation record
exists: the skill's entry and bring-up write it (`activate`), keyed by the
session id the session-start hook captured (`session-hook`), so a session
mission control launches, under another id, never matches it. The mod
looks for the file `where` names on its timer and at turn boundaries,
reads it through `lookup`, and writes its acknowledgment (`ack`); `await`
is the skill's side of that handshake. PLANWRIGHT_MC_PROGRAM=<program>
(and optionally PLANWRIGHT_MC_TARGET=<its wake target>, the program's
name by default) in a session's environment stays a fast path: the mod
reads them once, clears them, and records the activation itself. Under
<fleet-home>/mission-control/_panel/, owner-only, no symlink followed:
  sessions/<host pid>        format, session, written: which session the
                             host process carries, rewritten at every
                             session start (a /clear included)
  active/<session id>        format, program, target, session, pid,
                             written: the activation record
  active/<session id>.ack    format, session, written: the mod's
                             acknowledgment
Fields are key<TAB>value lines; the format line comes first, and a record
of any other format never activates.

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

  mc-panel.sh text --program <p> [--target <t>]
      the text panel, for a session where nothing draws the pane:
        mission control <p>
        in flight: <n>               then one indented line per flight
        waiting: <n>
        pending wakes: <n>           with --target
        rung: <rung> (<reason>)
      a store that cannot be read is said as unknown, with why
  mc-panel.sh activate --program <p> [--target <t>] [--session <id>]
                       [--pid <pid>] [--now <epoch>]
      write this session's activation record, dropping an earlier
      acknowledgment unless the record names the same program and target;
      prints activation<TAB><session id>. The session defaults to this one
      (the session-start record for CLAUDE_PID, then
      CLAUDE_CODE_SESSION_ID), the pid to CLAUDE_PID when its session-start
      record names this session, then to a live process whose record
      does, else `-`
  mc-panel.sh await --program <p> [--session <id>] [--wait <seconds>]
      wait for the mod's acknowledgment of the record, up to the wait
      (default 30, at most 60), and print
        panel<TAB>mod                         acknowledged
      or, followed by the text panel,
        panel<TAB>text<TAB><why>              below the mods floor, no
                                              acknowledgment within the
                                              wait, no session to name, or
                                              an unreadable activation
                                              directory
  mc-panel.sh lookup [--session <id>]
      the record's program<TAB><p> and target<TAB><t> lines; exit 1 when
      the session has none, or one of another format or session
  mc-panel.sh ack [--session <id>] [--now <epoch>]
      write the acknowledgment beside an existing record naming the
      session
  mc-panel.sh retire [--session <id>]
      remove the session's record and acknowledgment; prints
      retired<TAB><session id>
  mc-panel.sh prune [--now <epoch>]
      remove every record whose pid is no live process (one with no pid
      once it is a week old), every acknowledgment with no record, and
      every session-start record whose process is gone; prints
      pruned<TAB><session id> per record
  mc-panel.sh where
      the directory activation records live in; drops session-start
      records whose process is gone
  mc-panel.sh floor
      the lowest Claude Code release the panel mod runs on
  mc-panel.sh session-hook
      the SessionStart hook: reads the hook input on stdin and writes the
      session-start record for CLAUDE_PID; prints nothing, exits 0

Exit codes: 0 done; 1 the program list, the presence marker or an
activation file cannot be read or written, a target's lease cannot be
written (its directory a symlink included), or `lookup` finds no record
for the session; 2 usage; 3 the program is not configured; 4 this
session's id cannot be told.

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

# The lowest Claude Code release whose mods API the panel mod runs on;
# scripts/check-panel-mod.sh gates on the same value through `floor`.
MODS_FLOOR=2.1.287
# Comfortably above the mod's record check interval (RECORD_CHECK_MS in
# hooks/mission-control/register.tsx): the skill's activate and await run in
# one turn, so only that timer finds a new record.
AWAIT_DEFAULT=30
AWAIT_MAX=60
# A record with no process to test is kept this long, then pruned.
PIDLESS_TTL=604800
HOOK_INPUT_MAX=65536

# A session id as the host spells it, checked before it names a file.
valid_session() {
  [ "${#1}" -eq 36 ] || return 1
  case $1 in
    *[!0-9A-Fa-f-]*) return 1 ;;
  esac
}

# panel_dir <leaf>: <fleet-home>/mission-control/_panel/<leaf>, created
# owner-only; a symlink, another owner or group or world write anywhere on it
# is refused, never narrowed. The leading underscore keeps it out of the
# program namespace beside it.
panel_dir() {
  pd_home=$(mc_fleet_home) || return 1
  pd_dir=$pd_home/mission-control
  for pd_part in _panel "$1"; do
    pd_dir=$pd_dir/$pd_part
    [ ! -L "$pd_dir" ] || return 1
    [ -d "$pd_dir" ] || (umask 077 && mkdir -p "$pd_dir") 2>/dev/null || return 1
    [ -O "$pd_dir" ] || return 1
    [ -z "$(find "$pd_dir" -prune \( -perm -0020 -o -perm -0002 \) 2>/dev/null)" ] || return 1
  done
  printf '%s\n' "$pd_dir"
}

no_session() {
  printf '%s\n' "$prog: this session's id cannot be told (no session-start record, no CLAUDE_CODE_SESSION_ID)" >&2
  exit 4
}

# field_of <file> <key>: the first value of <key> in a key<TAB>value store.
field_of() { K=$2 awk -F '\t' '$1 == ENVIRON["K"] { print $2; exit }' "$1" 2>/dev/null; }

# self_session: this session's id. The session-start hook's record for the
# host process (CLAUDE_PID) first, since it follows a /clear; the host's
# CLAUDE_CODE_SESSION_ID second.
self_session() {
  ss_pid=${CLAUDE_PID:-}
  if mc_valid_uint "$ss_pid" && ss_dir=$(panel_dir sessions) \
    && [ ! -L "$ss_dir/$ss_pid" ] && mc_format_ok "$ss_dir/$ss_pid"; then
    ss_id=$(field_of "$ss_dir/$ss_pid" session)
    if valid_session "$ss_id"; then
      printf '%s\n' "$ss_id"
      return 0
    fi
  fi
  ss_id=${CLAUDE_CODE_SESSION_ID:-}
  valid_session "$ss_id" || return 1
  printf '%s\n' "$ss_id"
}

# pid_alive <pid>: a process by that id exists, whoever owns it.
pid_alive() { kill -0 "$1" 2>/dev/null || ps -p "$1" >/dev/null 2>&1; }

case $verb in
  floor)
    [ $# -eq 0 ] || usage
    printf '%s\n' "$MODS_FLOOR"
    exit 0
    ;;
  where)
    # Run once per mod load in every session, so it also drops session-start
    # records whose process is gone on hosts no keeper sweeps.
    [ $# -eq 0 ] || usage
    panel_dir active || mc_fail "cannot open the activation directory"
    if wh_sd=$(panel_dir sessions); then
      set +f
      for wh_f in "$wh_sd"/*; do
        wh_k=${wh_f##*/}
        mc_valid_uint "$wh_k" || continue
        pid_alive "$wh_k" || rm -f -- "$wh_f"
      done
      set -f
    fi
    exit 0
    ;;
  session-hook)
    # A SessionStart hook in every session: silent, and never a failure.
    [ $# -eq 0 ] || exit 0
    sh_input=$(head -c "$HOOK_INPUT_MAX" 2>/dev/null) || exit 0
    sh_id=$(printf '%s' "$sh_input" | LC_ALL=C grep -Eo '"session_id"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f-]{36}"' 2>/dev/null \
      | head -n 1 | sed 's/.*"\([0-9A-Fa-f-]*\)"$/\1/')
    sh_pid=${CLAUDE_PID:-}
    valid_session "$sh_id" && mc_valid_uint "$sh_pid" || exit 0
    sh_dir=$(panel_dir sessions) || exit 0
    [ ! -L "$sh_dir/$sh_pid" ] || exit 0
    printf 'format\t%s\nsession\t%s\nwritten\t%s\n' "$MC_FORMAT" "$sh_id" "$(mc_now)" \
      | mc_write "$sh_dir/$sh_pid" 2>/dev/null
    exit 0
    ;;
esac

program=""
target=""
now=""
presence_kind=""
with_knobs=0
session=""
pid=""
wait_s=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now | --session | --pid | --wait)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
        --session) session=$2 ;;
        --pid) pid=$2 ;;
        --wait) wait_s=$2 ;;
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
# Each verb takes only its own flags.
only() {
  [ -z "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage
  case " $1 " in *" program "*) [ -n "$program" ] || usage ;; *) [ -z "$program" ] || usage ;; esac
  case " $1 " in *" target "*) ;; *) [ -z "$target" ] || usage ;; esac
  case " $1 " in *" now "*) ;; *) [ -z "$now" ] || usage ;; esac
  case " $1 " in *" session "*) ;; *) [ -z "$session" ] || usage ;; esac
  case " $1 " in *" pid "*) ;; *) [ -z "$pid" ] || usage ;; esac
  case " $1 " in *" wait "*) ;; *) [ -z "$wait_s" ] || usage ;; esac
}
case $verb in
  digest | line)
    [ -z "$presence_kind" ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s" ] || usage
    ;;
  presence)
    [ -n "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s" ] || usage
    ;;
  activate) only "program target now session pid" ;;
  text) only "program target" ;;
  await) only "program session wait" ;;
  lookup | retire) only "session" ;;
  ack) only "session now" ;;
  prune) only "now" ;;
  *) usage ;;
esac
[ -z "$target" ] || mc_valid_handle "$target" || mc_usage_fail "invalid target '$(sanitize_printable "$target")'"
[ -z "$session" ] || valid_session "$session" || mc_usage_fail "invalid session id '$(sanitize_printable "$session")'"
[ -z "$pid" ] || mc_valid_uint "$pid" || mc_usage_fail "--pid takes a process id"
if [ -n "$wait_s" ]; then
  mc_valid_uint "$wait_s" && [ "$wait_s" -le "$AWAIT_MAX" ] \
    || mc_usage_fail "--wait takes seconds, at most $AWAIT_MAX"
fi

# The activation record, its acknowledgment and their sweep: host-wide, one
# record per session id, so a session the program launches (another id)
# never matches one.
case $verb in
  lookup | retire | ack | prune)
    act_dir=$(panel_dir active) || mc_fail "cannot open the activation directory"
    if [ "$verb" != prune ] && [ -z "$session" ]; then
      session=$(self_session) || no_session
    fi
    ;;
esac
case $verb in
  lookup)
    lk=$act_dir/$session
    [ ! -L "$lk" ] && mc_format_ok "$lk" && [ "$(field_of "$lk" session)" = "$session" ] || exit 1
    lk_p=$(field_of "$lk" program)
    lk_t=$(field_of "$lk" target)
    mc_valid_program "$lk_p" || exit 1
    [ -n "$lk_t" ] && mc_valid_handle "$lk_t" || lk_t=$lk_p
    printf 'program\t%s\ntarget\t%s\n' "$lk_p" "$lk_t"
    exit 0
    ;;
  ack)
    mc_now_arg "$now"
    { [ ! -L "$act_dir/$session" ] && mc_format_ok "$act_dir/$session" \
      && [ "$(field_of "$act_dir/$session" session)" = "$session" ]; } || mc_fail "no activation record for this session"
    [ ! -L "$act_dir/$session.ack" ] || mc_fail "the acknowledgment is a symlink"
    printf 'format\t%s\nsession\t%s\nwritten\t%s\n' "$MC_FORMAT" "$session" "$NOW" \
      | mc_write "$act_dir/$session.ack" || mc_fail "cannot write the acknowledgment"
    exit 0
    ;;
  retire)
    rm -f -- "$act_dir/$session" "$act_dir/$session.ack" || mc_fail "cannot remove the activation record"
    printf 'retired\t%s\n' "$session"
    exit 0
    ;;
  prune)
    mc_now_arg "$now"
    pr_rc=0
    set +f
    for pr_f in "$act_dir"/*; do
      [ -e "$pr_f" ] || [ -L "$pr_f" ] || continue
      pr_id=${pr_f##*/}
      case $pr_id in
        *.ack)
          # An acknowledgment outlives its record only by a crash between
          # the two removals.
          [ -e "$act_dir/${pr_id%.ack}" ] || rm -f -- "$pr_f" || pr_rc=1
          continue
          ;;
      esac
      valid_session "$pr_id" || continue
      # Only a regular file is read: a symlink or a FIFO named like a
      # record would send the read elsewhere, or hang the keeper.
      [ ! -L "$pr_f" ] && [ -f "$pr_f" ] || continue
      pr_pid=$(field_of "$pr_f" pid)
      if mc_valid_uint "$pr_pid"; then
        pid_alive "$pr_pid" && continue
      else
        # No process to test: kept until the TTL, then taken as dead.
        pr_w=$(field_of "$pr_f" written)
        mc_valid_uint "$pr_w" && [ $((NOW - pr_w)) -lt "$PIDLESS_TTL" ] && continue
      fi
      if rm -f -- "$pr_f" "$pr_f.ack"; then
        printf 'pruned\t%s\n' "$pr_id"
      else
        pr_rc=1
      fi
    done
    if pr_sd=$(panel_dir sessions); then
      for pr_f in "$pr_sd"/*; do
        pr_k=${pr_f##*/}
        mc_valid_uint "$pr_k" || continue
        pid_alive "$pr_k" || rm -f -- "$pr_f" || pr_rc=1
      done
    else
      pr_rc=1
    fi
    set -f
    exit "$pr_rc"
    ;;
esac
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

# The text panel: the pane's first rows as plain lines, for a session where
# nothing draws the pane.
text_panel() {
  {
    flights
    waiting
    pending
    budget
  } | P=$program awk -F '\t' '
    $1 == "flight" { f[++n] = "  " $2 "  " $3 "  (" $4 ")" }
    $1 == "waiting" { w = ($2 == "-" ? "shown by the host" : $2) }
    $1 == "pending" { p = $2 }
    $1 == "rung" { r = $2 (($3 == "" || $3 == "-") ? "" : " (" $3 ")") }
    $1 == "unreadable" && $2 == "fleet registry" { fu = 1 }
    $1 == "unreadable" && $2 == "operator queue" { w = "unknown (the queue cannot be read)" }
    $1 == "unreadable" && $2 == "budget" { r = "unknown (the budget cannot be read)" }
    END {
      print "mission control " ENVIRON["P"]
      print "in flight: " (fu ? "unknown (the fleet registry cannot be read)" : n + 0)
      for (i = 1; i <= n; i++) print f[i]
      print "waiting: " (w == "" ? "unknown" : w)
      if (p != "") print "pending wakes: " p
      print "rung: " (r == "" ? "unknown" : r)
    }' | mc_clean_text
}

# below_floor: the host's claude CLI reads, and is older than the mods
# floor. A version that cannot be read is not taken as below it.
below_floor() {
  bf_v=$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }')
  printf '%s\n' "$bf_v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  ! V=$bf_v F=$MODS_FLOOR awk 'BEGIN {
    split(ENVIRON["V"], v, "."); split(ENVIRON["F"], f, ".")
    for (i = 1; i <= 3; i++) { if (v[i] + 0 > f[i] + 0) exit 0; if (v[i] + 0 < f[i] + 0) exit 1 }
    exit 0 }'
}

# acked <dir> <session>: the mod acknowledged this session's record.
acked() {
  [ ! -L "$1/$2.ack" ] && mc_format_ok "$1/$2.ack" && [ "$(field_of "$1/$2.ack" session)" = "$2" ]
}

activate() {
  [ -n "$session" ] || session=$(self_session) || no_session
  [ -n "$target" ] || target=$program
  ac_dir=$(panel_dir active) || mc_fail "cannot open the activation directory"
  ac_sd=$(panel_dir sessions) || ac_sd=""
  # CLAUDE_PID counts only when the session-start record for it names this
  # session; otherwise the live process that record names, else `-`.
  if [ -z "$pid" ] && mc_valid_uint "${CLAUDE_PID:-}" && [ -n "$ac_sd" ] \
    && [ ! -L "$ac_sd/$CLAUDE_PID" ] && [ "$(field_of "$ac_sd/$CLAUDE_PID" session)" = "$session" ]; then
    pid=$CLAUDE_PID
  fi
  if [ -z "$pid" ] && [ -n "$ac_sd" ]; then
    set +f
    for ac_f in "$ac_sd"/*; do
      ac_k=${ac_f##*/}
      mc_valid_uint "$ac_k" && [ ! -L "$ac_f" ] || continue
      { [ "$(field_of "$ac_f" session)" = "$session" ] && pid_alive "$ac_k"; } || continue
      pid=$ac_k
      break
    done
    set -f
  fi
  [ -n "$pid" ] || pid=-
  ac_rec=$ac_dir/$session
  [ ! -L "$ac_rec" ] && [ ! -L "$ac_rec.ack" ] || mc_fail "the activation record is a symlink"
  # A record naming another program or target waits for a new
  # acknowledgment; the same one keeps the live mod's, which acknowledges
  # only when it activates.
  if ! { mc_format_ok "$ac_rec" && [ "$(field_of "$ac_rec" program)" = "$program" ] \
    && [ "$(field_of "$ac_rec" target)" = "$target" ] && [ "$(field_of "$ac_rec" session)" = "$session" ]; }; then
    rm -f -- "$ac_rec.ack" || mc_fail "cannot clear the old acknowledgment"
  fi
  printf 'format\t%s\nprogram\t%s\ntarget\t%s\nsession\t%s\npid\t%s\nwritten\t%s\n' \
    "$MC_FORMAT" "$program" "$target" "$session" "$pid" "$NOW" \
    | mc_write "$ac_rec" || mc_fail "cannot write the activation record"
  printf 'activation\t%s\n' "$session"
}

await_panel() {
  [ -n "$wait_s" ] || wait_s=$AWAIT_DEFAULT
  if below_floor; then
    printf 'panel\ttext\tbelow the mods floor %s\n' "$MODS_FLOOR"
  elif ! { [ -n "$session" ] || session=$(self_session); }; then
    printf 'panel\ttext\tthis session cannot be told\n'
  elif ! aw_dir=$(panel_dir active); then
    printf 'panel\ttext\tthe activation directory cannot be read\n'
  else
    aw_n=0
    while :; do
      if acked "$aw_dir" "$session"; then
        printf 'panel\tmod\n'
        return 0
      fi
      [ "$aw_n" -lt "$wait_s" ] || break
      sleep 1
      aw_n=$((aw_n + 1))
    done
    printf 'panel\ttext\tno acknowledgment within %ss\n' "$wait_s"
  fi
  text_panel
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
  activate) activate ;;
  await) await_panel ;;
  text) text_panel ;;
esac
