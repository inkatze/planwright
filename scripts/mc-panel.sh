#!/usr/bin/env bash
# mc-panel.sh — the panel mod's data seam: one digest of every store the
# panel draws, the text forms a session without the mod reads, the presence
# marker the mod feeds from prompt events, the activation record that turns
# the mod on in a mission-control session with no setup, and the record of
# the planwright copy the program's session runs.
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
# A config read costs a fork chain per knob, so the health bounds are read
# at most this often and kept in <runtime>/health-bounds between reads.
HEALTH_BOUNDS_TTL=300
# The mod restamps its context reading on its presence timer
# (PRESENCE_EVERY_MS in hooks/mission-control/register.tsx); a reading
# older than this is a mod that stopped.
CONTEXT_FRESH=300
# A stale reading that names no session is taken as gone past this.
CONTEXT_GONE=86400
# The throughput duty measures at most this often whatever its watcher's
# cadence (scripts/mc-throughput.sh's own interval), so its measure goes
# stale only past twice the longer of the two.
THROUGHPUT_INTERVAL=3600
TAB=$(printf '\t')

usage() {
  mc_usage_fail "usage: mc-panel.sh digest|line|health|text|presence|activate|await|lookup|ack|retire|prune|where|floor|session-hook|install|changes ... (mc-panel.sh --help)"
}

help_text() {
  cat <<'HELP'
mc-panel.sh — the panel mod's data seam: one digest of every store the
panel draws, the text forms a session without the mod reads, the presence
marker the mod feeds from prompt events, the activation record that turns
the mod on in a mission-control session with no setup, and the record of
the planwright copy the program's session runs.

The mod (hooks/mission-control/) runs `digest` on its redraw timer and
draws only what it prints; nothing here calls a model or writes a store
but the presence marker, with --target the target's lease, with --context
the context reading, the health line's bounds cache, the install record
with its event, and the activation files below. A store that
cannot be read is said as such, never drawn as empty.

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
  active/<session id>.exit   format, session, written: the exit marker
                             retire --exit leaves the session's own mod
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
        knob<TAB>mascot<TAB>0|1|2            with --knobs: the mascot, off,
                                             a still frame or animated
        knob<TAB>usage-hold<TAB><n>          with --knobs: the usage percent
                                             admission holds launches at,
                                             0 when the stop is off
        flight<TAB><worker><TAB><scope><TAB><backend><TAB>working|waiting|stuck
                                             a fleet registry session seen
                                             live (its process or tmux
                                             window still there), `waiting`
                                             when parked on a question or a
                                             permission prompt,
                                             `stuck` when it stopped
                                             responding; `-` for a field its
                                             record lacks
        finished<TAB><n>                     registry sessions not retired
                                             and not seen live: gone, idle,
                                             ended, done, merged or waiting
                                             on its PR, or with nothing to
                                             watch (rows of a tmux server
                                             that does not answer are in
                                             neither count)
        waiting<TAB><n|->                    the operator queue's items that
                                             wait on the operator: a live
                                             session's question, never one a
                                             gone or unknown session left
                                             behind or mission control's
                                             own; `-` where the backend
                                             surfaces the queue itself
        merge-ready<TAB><n><TAB>all|partial  pull requests ready to merge
                                             (scripts/mc-merge-ready.sh count);
                                             the line names them unless none,
                                             `<n>+` (or `?` for none) when
                                             some could not be judged
        merge-command<TAB><repo><TAB><number><TAB><command>
                                             one per ready pull request in
                                             the merge-ready store: the
                                             checked merge command
        queued<TAB><worker><TAB><question>   one per operator item in the queue,
                                             the question the row asks
        approvals<TAB><n>                    the queue's worker permission
                                             prompts, which mission control
                                             answers (with a number waiting)
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
        host<TAB><load x100|-><TAB><cores|-><TAB><memory available %|->
                                             the one-minute load average
                                             in hundredths, the core count
                                             and the share of memory still
                                             available, `-` for what this
                                             host cannot read
        handover<TAB>available|absent        whether a handover verb is
                                             installed to defer a
                                             compaction for
        holder<TAB>registry|attended|-       the holder record's kind: only
                                             a registry holder (a session
                                             mission control launched) hands
                                             over; `-` with no readable record
        context<TAB><session><TAB><percent|unknown><TAB><host|transcript|->
                                             one per session the runner
                                             recorded a reading for
                                             (scripts/mc-context.sh), with
                                             where it came from; `unknown`
                                             for one it could not read or
                                             that is over an hour old
        unreadable<TAB><store>               a store that could not be read
        health<TAB><check><TAB><n|?><TAB><worst|-><TAB><text>
                                             a health check out of its
                                             bound (n the count past it, the
                                             worst offender named), or `?`
                                             where it cannot tell, the text
                                             saying why; a check may print
                                             one of each, and none prints
                                             when all is well. See HEALTH
        line<TAB><text>                      the line form, last
      Stored text has every control byte dropped.
  mc-panel.sh line --program <p> [--target <t>] [--now <epoch>]
      the line form alone, for a session without the mod; it makes every
      read the digest makes, so it is no per-redraw status line
  mc-panel.sh health --program <p> [--now <epoch>]
      the health line alone, `health: <text>; <text>`, and nothing at all
      when every check is within its bound
  mc-panel.sh presence --program <p> --prompt|--refresh [--target <t>]
                       [--context <percent|-> --threshold <percent|->]
                       [--now <epoch>]
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
      one whose mod died. With --context, the session's measured context
      and the handover threshold it is held to (`-` where it hands over at
      none) go to <runtime>/context, the reading the health line compares
      for every mission control on the host:
        format<TAB>1
        written<TAB><epoch>
        percent<TAB><percent|->
        threshold<TAB><percent|->
        pid<TAB><CLAUDE_PID|->
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

  mc-panel.sh text --program <p> [--target <t>] [--now <epoch>]
      the text panel, for a session where nothing draws the pane:
        mission control <p>
        in flight: <n>               then one indented line per flight
        waiting on you: <n>
        ready to merge: <n>          unless none; `<n> or more` or
                                     `unknown` when some could not be
                                     judged (mc-merge-ready.sh)
        approvals mission control is handling: <n>   when any
        pending wakes: <n>           with --target
        rung: <rung> (<reason>)
        health: <text>; <text>       only when a check is out of bounds
                                     or unknown
        context: <session> <n>% (<source>)   one per recorded reading,
                                     `unknown` where none could be read
      a store that cannot be read is said as unknown, with why
  mc-panel.sh activate --program <p> [--target <t>] [--session <id>]
                       [--pid <pid>] [--now <epoch>]
      write this session's activation record, dropping an earlier
      acknowledgment unless the record names the same program, target and
      process;
      prints activation<TAB><session id>. The session is this one (the
      session-start record for CLAUDE_PID, then CLAUDE_CODE_SESSION_ID);
      --session naming another is refused. The pid defaults to CLAUDE_PID
      when its session-start record names this session, then to a live
      process whose record does, else `-`; a --pid whose record does not
      name this session is refused
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
      remove this session's record, acknowledgment and exit marker, or
      those of a record this host process (CLAUDE_PID) wrote under an
      earlier id; any other --session is refused. Prints
      retired<TAB><session id>
  mc-panel.sh retire --exit --program <p>
      a released mission-control session ending itself, this session
      only: its record of program <p>, once a mod acknowledged it, first
      leaves an exit marker from which that mod stands down and ends the
      session once its turn is over, and prints retired<TAB><session id>
      and exit<TAB>mod. Otherwise prints exit<TAB>none<TAB><why>: with
      no acknowledgment it retires the record and nothing will end the
      session; another program's record, or none, it leaves alone
  mc-panel.sh prune
      remove every record whose pid is no live process (one with no pid
      is kept), every acknowledgment with no record, every exit marker
      no mod read within the hour, and
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

HEALTH. A failsafe for the duties: each check reads the store a duty
keeps and flags only what is at or past its bound, a knob named below.
No model is in the path and nothing is written but the bounds cache,
<runtime>/health-bounds, which holds the bounds for a few minutes so a
redraw reads no config. Mission control sessions themselves are left out
of the worker checks.
  worker-age     a live worker registered for
                 mission_control_health_worker_age or longer
  after-merge    a live worker whose pull request landed: at once where
                 the keeper's landing record (scripts/mc-keeper.sh's
                 keeper-announced) says it held the retire and its ledger
                 (keeper.tsv) has not marked the session retired, or the
                 attention store's `merged` held for
                 mission_control_health_merged_grace or longer
  permissions    a permission prompt pending in the attention store for
                 mission_control_health_permission_wait or longer, its
                 session counted whether it is seen live or not
  mc-stuck       this program's mission control held on its own dialog
                 (scripts/mc-escalate.sh's record) for
                 mission_control_health_stuck_after or longer; unknown when
                 that watcher has not run within twice its cadence plus a
                 minute, or its last run failed
  context        a mission control on this host whose last context reading
                 is at or past its own handover threshold; unknown for one
                 whose reading is stale while its session lives or cannot
                 be told, for at most a day where it names no session
  ci-queue       a CI job whose median queue time reaches
                 mission_control_health_ci_queue_share percent of its median
                 run time and at least mission_control_health_ci_queue_floor
                 (scripts/mc-throughput.sh's measure), and one at or past
                 the floor with no finished run whatever the share; unknown
                 when the measure is older than twice the longer of its
                 watcher's cadence and an hour
  idle           a live session idle for mission_control_health_idle_after
                 or longer
A check whose duty is not armed here and whose store is absent is not
run; one whose store or bound cannot be read is unknown (`?` for its
count), never within bounds.

Exit codes: 0 done; 1 the program list, the presence marker or an
activation file cannot be read or written, a target's lease, the context
reading or the install record cannot be written (its directory a symlink
included), the install
event is refused, the copy's root, version or changelog cannot be read, or
`lookup` finds no record for the session; 2 usage, or an activate or
retire naming another session; 3 the program is not configured; 4 this
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
  pd_dir=$pd_home
  for pd_part in mission-control _panel "$1"; do
    pd_dir=$pd_dir/$pd_part
    [ ! -L "$pd_dir" ] || return 1
    [ -d "$pd_dir" ] || (umask 077 && mkdir -p "$pd_dir") 2>/dev/null || return 1
    # The shared parent keeps whatever mode the runtime scripts gave it.
    [ "$pd_part" != mission-control ] || continue
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

# names_session <file> <id>: <file> is a regular file of this format, not a
# symlink, whose session field is <id>. Every read of an activation, an
# acknowledgment or a session-start record goes through it.
names_session() {
  [ ! -L "$1" ] && mc_format_ok "$1" && [ "$(field_of "$1" session)" = "$2" ]
}

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

# own_session <id> [<record>]: 0 when <id> is this session's, the one
# self_session names, or the one an activation <record> this host process
# (CLAUDE_PID) wrote names, an id a /clear left behind; 1 when it is another
# session's. Exits 4 when this session's id cannot be told.
own_session() {
  os_self=$(self_session) || os_self=''
  [ -z "$os_self" ] || [ "$os_self" != "$1" ] || return 0
  if [ -n "${2:-}" ] && mc_valid_uint "${CLAUDE_PID:-}" && names_session "$2" "$1" \
    && [ "$(field_of "$2" pid)" = "$CLAUDE_PID" ]; then
    return 0
  fi
  [ -n "$os_self" ] || no_session
  return 1
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
root=""
from=""
session=""
pid=""
wait_s=""
ctx_pct=""
ctx_threshold=""
for_exit=0
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now | --root | --from | --session | --pid | --wait | --context | --threshold)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --target) target=$2 ;;
        --now) now=$2 ;;
        --root) root=$2 ;;
        --from) from=$2 ;;
        --session) session=$2 ;;
        --pid) pid=$2 ;;
        --wait) wait_s=$2 ;;
        --context) ctx_pct=$2 ;;
        --threshold) ctx_threshold=$2 ;;
      esac
      shift 2
      ;;
    --knobs)
      with_knobs=1
      shift
      ;;
    --exit)
      for_exit=1
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
[ "$for_exit" -eq 0 ] || [ "$verb" = retire ] || usage
# Each verb takes only its own flags.
only() {
  [ -z "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage
  case " $1 " in *" program "*) [ -n "$program" ] || usage ;; *) [ -z "$program" ] || usage ;; esac
  case " $1 " in *" target "*) ;; *) [ -z "$target" ] || usage ;; esac
  case " $1 " in *" now "*) ;; *) [ -z "$now" ] || usage ;; esac
  case " $1 " in *" session "*) ;; *) [ -z "$session" ] || usage ;; esac
  case " $1 " in *" pid "*) ;; *) [ -z "$pid" ] || usage ;; esac
  case " $1 " in *" wait "*) ;; *) [ -z "$wait_s" ] || usage ;; esac
  [ -z "$root$from$ctx_pct$ctx_threshold" ] || usage
}
case $verb in
  digest | line | health)
    [ -z "$presence_kind$ctx_pct$ctx_threshold" ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s$root$from" ] || usage
    [ "$verb" != health ] || { [ -z "$target" ] && [ "$with_knobs" -eq 0 ]; } || usage
    ;;
  presence)
    [ -n "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s$root$from" ] || usage
    # The context reading and its threshold come as a pair.
    { [ -z "$ctx_pct" ] && [ -z "$ctx_threshold" ]; } || { [ -n "$ctx_pct" ] && [ -n "$ctx_threshold" ]; } || usage
    ;;
  install)
    [ -z "$presence_kind$target$from$ctx_pct$ctx_threshold" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s" ] || usage
    ;;
  changes)
    [ -n "$from" ] && [ -z "$program$presence_kind$target$now$ctx_pct$ctx_threshold" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -z "$session$pid$wait_s" ] || usage
    ;;
  activate) only "program target now session pid" ;;
  text) only "program target now" ;;
  await) only "program session wait" ;;
  lookup) only "session" ;;
  # --exit is the releasing session's own act, so it names no other session.
  retire) if [ "$for_exit" -eq 1 ]; then only "program"; else only "session"; fi ;;
  ack) only "session now" ;;
  prune) only "" ;;
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
[ -z "$target" ] || mc_valid_handle "$target" || mc_usage_fail "invalid target '$(sanitize_printable "$target")'"
[ -z "$session" ] || valid_session "$session" || mc_usage_fail "invalid session id '$(sanitize_printable "$session")'"
[ -z "$pid" ] || mc_valid_uint "$pid" || mc_usage_fail "--pid takes a process id"
if [ -n "$wait_s" ]; then
  mc_valid_uint "$wait_s" && [ "$wait_s" -le "$AWAIT_MAX" ] \
    || mc_usage_fail "--wait takes seconds, at most $AWAIT_MAX"
fi
if [ -n "$ctx_pct" ]; then
  [ "$ctx_pct" = - ] || { mc_valid_uint "$ctx_pct" && [ "$ctx_pct" -le 100 ]; } \
    || mc_usage_fail "--context takes a percent from 0 to 100, or -"
  [ "$ctx_threshold" = - ] || { mc_valid_uint "$ctx_threshold" && [ "$ctx_threshold" -ge 1 ] && [ "$ctx_threshold" -le 100 ]; } \
    || mc_usage_fail "--threshold takes a percent from 1 to 100, or -"
fi

# The activation record, its acknowledgment and their sweep: host-wide, one
# record per session id, so a session the program launches (another id)
# never matches one.
case $verb in
  lookup | retire | ack | prune)
    act_dir=$(panel_dir active) || mc_fail "cannot open the activation directory"
    if [ "$verb" != prune ] && [ -z "$session" ]; then
      session=$(self_session) || no_session
    elif [ "$verb" = retire ]; then
      own_session "$session" "$act_dir/$session" \
        || mc_usage_fail "refusing to retire session $session: it is not this session"
    fi
    ;;
esac
case $verb in
  lookup)
    lk=$act_dir/$session
    names_session "$lk" "$session" || exit 1
    lk_p=$(field_of "$lk" program)
    lk_t=$(field_of "$lk" target)
    mc_valid_program "$lk_p" || exit 1
    [ -n "$lk_t" ] && mc_valid_handle "$lk_t" || lk_t=$lk_p
    printf 'program\t%s\ntarget\t%s\n' "$lk_p" "$lk_t"
    exit 0
    ;;
  ack)
    mc_now_arg "$now"
    names_session "$act_dir/$session" "$session" || mc_fail "no activation record for this session"
    [ ! -L "$act_dir/$session.ack" ] || mc_fail "the acknowledgment is a symlink"
    printf 'format\t%s\nsession\t%s\nwritten\t%s\n' "$MC_FORMAT" "$session" "$NOW" \
      | mc_write "$act_dir/$session.ack" || mc_fail "cannot write the acknowledgment"
    exit 0
    ;;
  retire)
    rt_rec=$act_dir/$session
    [ "$for_exit" -eq 0 ] || mc_valid_program "$program" || mc_usage_fail "invalid program '$(sanitize_printable "$program")'"
    if [ "$for_exit" -eq 1 ] && ! { names_session "$rt_rec" "$session" && [ "$(field_of "$rt_rec" program)" = "$program" ]; }; then
      # Another program's panel, or none: nothing here is this release's.
      printf 'exit\tnone\tno panel of program %s is recorded for this session\n' "$program"
      exit 0
    fi
    if [ "$for_exit" -eq 1 ] && names_session "$rt_rec.ack" "$session"; then
      # Written before the record goes: a mod that finds the record gone
      # with no marker stands down without ending the session.
      [ ! -L "$rt_rec.exit" ] || mc_fail "the exit marker is a symlink"
      printf 'format\t%s\nsession\t%s\nwritten\t%s\n' "$MC_FORMAT" "$session" "$(mc_now)" \
        | mc_write "$rt_rec.exit" || mc_fail "cannot write the exit marker"
      # A marker beside a record that stays would end the session later.
      rm -f -- "$rt_rec" "$rt_rec.ack" || {
        rm -f -- "$rt_rec.exit"
        mc_fail "cannot remove the activation record"
      }
      printf 'retired\t%s\nexit\tmod\n' "$session"
      exit 0
    fi
    rm -f -- "$rt_rec" "$rt_rec.ack" "$rt_rec.exit" || mc_fail "cannot remove the activation record"
    printf 'retired\t%s\n' "$session"
    [ "$for_exit" -eq 0 ] || printf 'exit\tnone\t%s\n' "no mod acknowledged this session's panel"
    exit 0
    ;;
  prune)
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
        *.exit)
          # Its mod reads a marker within seconds; an hour-old one belongs
          # to a session that ended some other way.
          [ -z "$(find "$pr_f" -prune -mmin +60 2>/dev/null)" ] || rm -f -- "$pr_f" || pr_rc=1
          continue
          ;;
      esac
      valid_session "$pr_id" || continue
      # Only a regular file is read: a symlink or a FIFO named like a
      # record would send the read elsewhere, or hang the keeper.
      [ ! -L "$pr_f" ] && [ -f "$pr_f" ] || continue
      pr_pid=$(field_of "$pr_f" pid)
      # A record with no process to test is left: its session cannot be
      # told dead, and a standing session's record is never written again.
      mc_valid_uint "$pr_pid" || continue
      pid_alive "$pr_pid" && continue
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
# The usage stop is what the usage-window duty holds launches at: a percent,
# or `off` (no proactive stop) as 0.
parse_usage_hold() {
  case $1 in off) printf '0\n' ;; *) parse_pct "$1" ;; esac
}
# The mascot knob reads animated, still or off as 2, 1 or 0.
parse_mascot() {
  case $1 in animated) printf '2\n' ;; still) printf '1\n' ;; off) printf '0\n' ;; *) return 1 ;; esac
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
  if [ -n "$ctx_pct" ]; then
    # A directory in its place would take the rename into it.
    if [ -L "$runtime/context" ] || { [ -e "$runtime/context" ] && [ ! -f "$runtime/context" ]; }; then
      mc_fail "the context reading is not a file"
    fi
    ctx_pid=${CLAUDE_PID:-}
    mc_valid_uint "$ctx_pid" || ctx_pid=-
    printf 'format\t%s\nwritten\t%s\npercent\t%s\nthreshold\t%s\npid\t%s\n' \
      "$MC_FORMAT" "$NOW" "$ctx_pct" "$ctx_threshold" "$ctx_pid" \
      | mc_write "$runtime/context" || mc_fail "cannot write the context reading"
  fi
  exit 0
fi
mc_now_arg "$now"

# Each read below prints its records; a store it cannot read prints
# `unreadable<TAB><store>` and the digest goes on.
# A count from a store that could not be read is unknown, never a number.
D_FLIGHT='?'
D_WAITING='?'
D_MERGE_READY='?'
D_APPROVALS=0
D_PENDING='?'
D_RUNG=-
D_OLDEST=""
HOME_DIR=""
D_HEALTH=""
# What flights() read, kept for the health checks: every session seen live
# as worker, scope, registered epoch, attention state and its epoch.
H_ALIVE=""
H_REGISTRY_OK=0
H_TMUX_UNKNOWN=0
H_ATTN=""
H_ATTN_OK=0
WATCH_STATUS=""
WATCH_READ=""

knobs() {
  for kn in refresh:mission_control_panel_refresh:mc_parse_cadence \
    tick:mission_control_tick_cadence:mc_parse_cadence \
    reviews-ttl:mission_control_reviews_ttl:mc_parse_cadence \
    handover-context:mission_control_handover_context:parse_pct \
    handover-wakes:mission_control_handover_wakes:parse_positive \
    handover-compactions:mission_control_handover_compactions:parse_positive \
    mascot:mission_control_panel_mascot:parse_mascot \
    usage-hold:mission_control_usage_hold:parse_usage_hold; do
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

# The windows of the tmux server, when a registry row names one. A server
# that is not running has no windows; one that does not answer is unknown,
# and its rows count neither way. It is said unreadable only once a row
# the attention store has not already finished depends on it, so the
# panel's qualified count agrees with this one.
flight_windows() {
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
          *) fl_tmux=0 ;;
        esac
      fi
      ;;
  esac
}

# Each worker's attention state, as worker, state, its epoch and park
# reason. An absent store is an empty one; one that is there but cannot be
# read is unknown.
flight_attention() {
  fl_attn=''
  fl_attn_ok=1
  if fl_root=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null); then
    fl_as=$fl_root/attention/state
    if [ -e "$fl_as" ] || [ -L "$fl_as" ]; then
      if [ -L "$fl_as" ] || [ ! -f "$fl_as" ] \
        || ! fl_attn=$(awk -F '\t' 'NF >= 3 { print $1 "\t" $3 "\t" ($4 == "" ? "-" : $4) "\t" ($9 == "" ? "-" : $9) }' "$fl_as" 2>/dev/null); then
        fl_attn=''
        fl_attn_ok=0
        printf 'unreadable\tattention store\n'
      fi
    fi
  else
    fl_attn_ok=0
    printf 'unreadable\tattention store\n'
  fi
}

# A registry row outlives its session until something retires it, so only
# a session seen live is in flight: its process or tmux window still there,
# and the attention store not saying its work ended. The rest are
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
  # Each open row comes out as worker, scope, backend, death handle and the
  # epoch it was registered at (since its last retirement or relaunch), an
  # empty or missing field as `-` so the tab-split read below keeps its
  # columns.
  fl_open=$(printf '%s\n' "$fl_reg" | awk -F '\t' '
    NF >= 2 {
      if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 }
      # A relaunch under the name carries a new death handle.
      h = (NF >= 7 && $7 != "-") ? $7 : ""
      relaunch = (h != "" && handle[$2] != "" && h != handle[$2])
      if (!($2 in first) || closed[$2] || relaunch) first[$2] = ($1 ~ /^[0-9]+$/) ? $1 : "-"
      if (h != "") handle[$2] = h
      closed[$2] = (NF == 8 && $8 == "closed")
      last[$2] = $0
    }
    END {
      for (i = 1; i <= n; i++) {
        nf = split(last[order[i]], f, "\t")
        if (nf == 8 && f[8] == "closed") continue
        for (j = 1; j <= 7; j++) if (j > nf || f[j] == "") f[j] = "-"
        print f[2] "\t" f[3] "\t" f[5] "\t" f[7] "\t" first[order[i]]
      }
    }')
  flight_windows
  flight_attention
  # Each row classed as live, a pid to probe, done or unknown. A window id
  # is looked up across the server, as a renamed session keeps its windows;
  # the token is also tried as a window name in its session. A session the
  # attention store calls ended in any way is still probed (pidend, liveend,
  # unknownend) for the health checks, and counted finished whatever the
  # probe says.
  fl_class=$(printf '%s\n' "$fl_open" | W=$fl_windows A=$fl_attn T=$fl_tmux awk -F '\t' '
    BEGIN {
      m = split(ENVIRON["W"], wl, "\n")
      for (i = 1; i <= m; i++) if (split(wl[i], x, "\t") == 3) { id[x[2]] = 1; nm[x[1] SUBSEP x[3]] = 1 }
      m = split(ENVIRON["A"], al, "\n")
      for (i = 1; i <= m; i++) if (split(al[i], x, "\t") == 4) { st[x[1]] = x[2]; at[x[1]] = x[3] }
    }
    NF == 5 {
      s = ($1 in st) ? st[$1] : ""
      ended = (s == "idle" || s == "ended" || s == "done" || s == "merged" || s == "pr-ready")
      word = s == "awaiting-input" ? "waiting" : (s == "hung" ? "stuck" : "working")
      tail = $5 "\t" (s == "" ? "-" : s) "\t" (($1 in at) ? at[$1] : "-")
      row = $1 "\t" $2 "\t" $3 "\t" word
      if ($4 ~ /^process [1-9][0-9]*$/) { print (ended ? "pidend" : "pid") "\t" row "\t" substr($4, 9) "\t" tail; next }
      if (split($4, h, " ") == 3 && h[1] == "tmux-window") {
        if (ENVIRON["T"] != "1") { print (ended ? "unknownend" : "unknown"); next }
        seen = (h[3] ~ /^@[0-9]+$/ && (h[3] in id)) || ((h[2] SUBSEP h[3]) in nm)
        print (!seen ? "done" : (ended ? "liveend" : "live") "\t" row "\t-\t" tail)
        next
      }
      print "done"
    }')
  fl_live=''
  fl_done=0
  fl_unknown=0
  fl_unknown_end=0
  while IFS="$TAB" read -r fl_class_of fl_w fl_s fl_b fl_word fl_pid fl_first fl_as fl_at; do
    fl_up=0
    case $fl_class_of in
      live | liveend) fl_up=1 ;;
      pid | pidend) ! { [ "$fl_pid" -gt 1 ] 2>/dev/null && kill -0 "$fl_pid" 2>/dev/null; } || fl_up=1 ;;
      unknown) fl_unknown=$((fl_unknown + 1)) ;;
      unknownend) fl_unknown_end=$((fl_unknown_end + 1)) ;;
    esac
    case $fl_class_of in
      live | pid)
        if [ "$fl_up" -eq 1 ]; then
          fl_live="$fl_live$fl_w$TAB$fl_s$TAB$fl_b$TAB$fl_word
"
        else
          fl_done=$((fl_done + 1))
        fi
        ;;
      done | pidend | liveend | unknownend) fl_done=$((fl_done + 1)) ;;
    esac
    [ "$fl_up" -eq 0 ] || H_ALIVE="$H_ALIVE$fl_w$TAB$fl_s$TAB$fl_first$TAB$fl_as$TAB$fl_at
"
  done <<EOF_ROWS
$fl_class
EOF_ROWS
  H_REGISTRY_OK=1
  H_TMUX_UNKNOWN=$((fl_unknown + fl_unknown_end))
  H_ATTN=$fl_attn
  H_ATTN_OK=$fl_attn_ok
  [ "$fl_unknown" -eq 0 ] || printf 'unreadable\ttmux windows\n'
  fl_rows=$(printf '%s' "$fl_live" | awk 'NF { print "flight\t" $0 }' | mc_clean)
  [ -z "$fl_rows" ] || printf '%s\n' "$fl_rows"
  printf 'finished\t%s\n' "$fl_done"
  D_FLIGHT=$(printf '%s' "$fl_rows" | awk 'NF { n++ } END { print n + 0 }')
  # Rows of a server that did not answer may be live, so the count is a
  # floor; without the attention store an idle session reads live, so it is
  # a ceiling; with both, neither.
  if [ "$fl_unknown" -gt 0 ] && [ "$fl_attn_ok" -eq 0 ]; then
    D_FLIGHT='?'
  elif [ "$fl_unknown" -gt 0 ]; then
    D_FLIGHT="$D_FLIGHT+"
  elif [ "$fl_attn_ok" -eq 0 ]; then
    D_FLIGHT="up to $D_FLIGHT"
  fi
}

# A worker permission prompt is mission control's to answer, so it is said
# apart and never counted as waiting on the operator.
waiting() {
  if ! wt_t=$(/bin/sh "$script_dir/fleet-attention.sh" queue --tally 2>/dev/null); then
    printf 'unreadable\toperator queue\n'
    return 0
  fi
  if [ -z "$wt_t" ]; then
    # The backend surfaces the queue itself and the count is deferred to it.
    printf 'waiting\t-\n'
    return 0
  fi
  wt_n=$(printf '%s\n' "$wt_t" | awk -F '\t' '$1 == "operator" { print $2 }')
  wt_a=$(printf '%s\n' "$wt_t" | awk -F '\t' '$1 == "approvals" { print $2 }')
  if mc_valid_uint "$wt_n" && mc_valid_uint "$wt_a"; then
    D_APPROVALS=$wt_a
    # What mission control can put to the operator is a question from a live
    # session other than its own: a row a gone session left behind, or one
    # from a session the registry does not know, asks nobody. Where the
    # registry or tmux could not be read a row cannot be proved stale, so it
    # stays; the tally above is then the count.
    if wt_items=$(/bin/sh "$script_dir/fleet-attention.sh" queue --items 2>/dev/null | mc_clean_text); then
      wt_rows=$(printf '%s\n' "$wt_items" | LIVE="$fl_live" OWN="$target" PROVE="$([ "$H_REGISTRY_OK" -eq 1 ] && [ "$H_TMUX_UNKNOWN" -eq 0 ] && echo 1 || echo 0)" awk -F "$TAB" '
        BEGIN { n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) { split(l[i], x, "\t"); if (x[1] != "") live[x[1]] = 1 } }
        $1 == "item" {
          if ($2 == ENVIRON["OWN"] || $2 ~ /-mission-control-/) next
          if (ENVIRON["PROVE"] == "1" && !($2 in live)) next
          print "queued\t" $2 "\t" $3
        }')
      wt_n=$(printf '%s' "$wt_rows" | awk 'NF { n++ } END { print n + 0 }')
    else
      wt_rows=""
    fi
    D_WAITING=$wt_n
    printf 'waiting\t%s\napprovals\t%s\n' "$wt_n" "$wt_a"
    [ -z "$wt_rows" ] || printf '%s\n' "$wt_rows"
  else
    printf 'unreadable\toperator queue\n'
  fi
}

merge_ready() {
  mg_all=""
  if mg_row=$(/bin/bash "$script_dir/mc-merge-ready.sh" count --program "$program" 2>/dev/null) \
    && mg_n=${mg_row%%"$TAB"*} && mg_all=${mg_row#*"$TAB"} && mc_valid_uint "$mg_n"; then
    case $mg_all in
      all) D_MERGE_READY=$mg_n ;;
      partial) if [ "$mg_n" -gt 0 ]; then D_MERGE_READY="$mg_n+"; fi ;;
      *) mg_all="" ;;
    esac
  fi
  if [ -n "$mg_all" ]; then
    printf 'merge-ready\t%s\t%s\n' "$mg_n" "$mg_all"
    # The ready ones' checked merge commands, from a store the last judgment
    # wrote as ok and fresh (mc-merge-ready.sh commands prints them).
    if mc_valid_uint "$mg_n" && [ "$mg_n" -gt 0 ] && mg_cmds=$(/bin/bash "$script_dir/mc-merge-ready.sh" commands --program "$program" --now "$NOW" 2>/dev/null); then
      printf '%s\n' "$mg_cmds" | awk -F '\t' '$1 == "ready" && $3 != "" { at = index($2, "#"); print "merge-command\t" substr($2, 1, at - 1) "\t" substr($2, at + 1) "\t" $3 }'
    fi
  else
    printf 'unreadable\tmerge-ready store\n'
  fi
}

pending() {
  [ -n "$target" ] || return 0
  if pd_rows=$(/bin/bash "$script_dir/mc-event.sh" list --program "$program" --target "$target" --pending 2>/dev/null); then
    D_PENDING=$(printf '%s\n' "$pd_rows" | mc_event_wakes 2>/dev/null | awk 'NF { n++ } END { print n + 0 }')
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
  watch_status || {
    printf 'unreadable\twatchers\n'
    return 0
  }
  wa=$WATCH_STATUS
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

# The host's load and memory for the panel's dials: three cheap reads of
# /proc (a test points MC_PANEL_PROC at a fixture), `-` for any it lacks.
host() {
  hs_proc=${MC_PANEL_PROC:-/proc}
  hs_load=-
  hs_cores=-
  hs_mem=-
  if hs_la=$(cut -d ' ' -f 1 "$hs_proc/loadavg" 2>/dev/null) && [ -n "$hs_la" ]; then
    hs_load=$(printf '%s\n' "$hs_la" | awk '/^[0-9]+(\.[0-9]+)?$/ { printf "%d", $1 * 100 + 0.5; found = 1 } END { if (!found) printf "-" }')
  fi
  hs_cores=$(grep -c '^processor' "$hs_proc/cpuinfo" 2>/dev/null) || hs_cores=-
  [ "$hs_cores" != 0 ] || hs_cores=-
  hs_mem=$(awk '
    $1 == "MemTotal:" { t = $2 }
    $1 == "MemAvailable:" { a = $2 }
    END { if (t > 0 && a != "") printf "%d", a * 100 / t; else printf "-" }' "$hs_proc/meminfo" 2>/dev/null) || hs_mem=-
  [ -n "$hs_mem" ] || hs_mem=-
  printf 'host\t%s\t%s\t%s\n' "$hs_load" "$hs_cores" "$hs_mem"
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

# Each session's context reading, as the runner recorded it
# (scripts/mc-context.sh record): one
# `context<TAB><session><TAB><percent|unknown><TAB><source|->` line each.
# The panel parses no transcript; a record that is a link, does not parse
# or is older than the runner's cadence allows reads unknown.
contexts() {
  cx_dir=$runtime/readings
  [ -d "$cx_dir" ] && [ ! -L "$cx_dir" ] || return 0
  set +f
  for cx_f in "$cx_dir"/*; do
    [ -f "$cx_f" ] && [ ! -L "$cx_f" ] || continue
    cx_n=${cx_f##*/}
    [ "${#cx_n}" -le 64 ] || continue
    case $cx_n in
      *[!a-z0-9-]* | -*) continue ;;
    esac
    cx_p=unknown
    cx_s=-
    if mc_format_ok "$cx_f"; then
      cx_w=$(mc_kv "$cx_f" written)
      cx_v=$(mc_kv "$cx_f" percent)
      cx_src=$(mc_kv "$cx_f" source)
      if mc_valid_uint "$cx_w" && [ "$cx_w" -le $((NOW + 60)) ] && [ "$(age_of "$cx_w")" -le 3600 ] \
        && mc_valid_uint "$cx_v" && [ "$cx_v" -le 100 ]; then
        case $cx_src in
          host | transcript)
            cx_p=$cx_v
            cx_s=$cx_src
            ;;
        esac
      fi
    fi
    printf 'context\t%s\t%s\t%s\n' "$cx_n" "$cx_p" "$cx_s"
  done
  set -f
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

# The health checks' bounds: check name, knob, and how its value reads.
HEALTH_KNOBS="worker-age:mission_control_health_worker_age:cadence
merged-grace:mission_control_health_merged_grace:cadence
permission-wait:mission_control_health_permission_wait:cadence
stuck-after:mission_control_health_stuck_after:cadence
ci-queue-share:mission_control_health_ci_queue_share:pct
ci-queue-floor:mission_control_health_ci_queue_floor:cadence
idle-after:mission_control_health_idle_after:cadence"

# health_bounds: each bound into its H_B_* variable, in seconds or a
# percent, `-` where its knob cannot be read. The cache stands while it is
# fresh and names every bound once; a bound that failed is cached as `-` too,
# so a broken knob costs one read per cache life, not one per redraw.
health_bounds() {
  hb_f=$runtime/health-bounds
  hb_rows=""
  if [ ! -L "$hb_f" ] && mc_format_ok "$hb_f"; then
    hb_w=$(mc_kv "$hb_f" written)
    if mc_valid_uint "$hb_w" && [ "$hb_w" -le "$NOW" ] && [ $((NOW - hb_w)) -lt "$HEALTH_BOUNDS_TTL" ]; then
      hb_rows=$(K=$HEALTH_KNOBS awk -F '\t' '
        BEGIN { n = split(ENVIRON["K"], k, "\n"); for (i = 1; i <= n; i++) { split(k[i], p, ":"); want[p[1]] = 1 } }
        $1 == "bound" && NF == 3 && ($2 in want) && !($2 in got) && ($3 == "-" || ($3 ~ /^[1-9][0-9]*$/ && ($2 != "ci-queue-share" || $3 <= 100))) { got[$2] = $3; c++ }
        END { if (c == n) for (b in got) print b "\t" got[b] }' "$hb_f")
    fi
  fi
  if [ -z "$hb_rows" ]; then
    while IFS=: read -r hb_name hb_knob hb_kind; do
      hb_parse=mc_parse_cadence
      [ "$hb_kind" = cadence ] || hb_parse=parse_pct
      hb_v=-
      if hb_raw=$(mc_knob "$hb_knob" "$hb_parse"); then
        hb_v=$hb_raw
        [ "$hb_kind" != cadence ] || hb_v=$(mc_seconds "$hb_raw") || hb_v=-
      fi
      hb_rows="$hb_rows$hb_name$TAB$hb_v
"
    done <<EOF
$HEALTH_KNOBS
EOF
    # A directory in the cache's place would take the rename into it.
    if [ ! -L "$hb_f" ] && { [ ! -e "$hb_f" ] || [ -f "$hb_f" ]; }; then
      { printf 'format\t%s\nwritten\t%s\n' "$MC_FORMAT" "$NOW" && printf '%s' "$hb_rows" | awk -F '\t' 'NF == 2 { print "bound\t" $0 }'; } \
        | mc_write "$hb_f" 2>/dev/null || :
    fi
  fi
  H_B_WORKER_AGE=-
  H_B_MERGED_GRACE=-
  H_B_PERMISSION_WAIT=-
  H_B_STUCK_AFTER=-
  H_B_CI_QUEUE_SHARE=-
  H_B_CI_QUEUE_FLOOR=-
  H_B_IDLE_AFTER=-
  while IFS="$TAB" read -r hb_name hb_v; do
    case $hb_name in
      worker-age) H_B_WORKER_AGE=$hb_v ;;
      merged-grace) H_B_MERGED_GRACE=$hb_v ;;
      permission-wait) H_B_PERMISSION_WAIT=$hb_v ;;
      stuck-after) H_B_STUCK_AFTER=$hb_v ;;
      ci-queue-share) H_B_CI_QUEUE_SHARE=$hb_v ;;
      ci-queue-floor) H_B_CI_QUEUE_FLOOR=$hb_v ;;
      idle-after) H_B_IDLE_AFTER=$hb_v ;;
    esac
  done <<EOF
$hb_rows
EOF
}

# dur <seconds>: a duration as the panel says one.
dur() {
  if [ "$1" -lt 120 ]; then
    printf '%ss\n' "$1"
  elif [ "$1" -lt 7200 ]; then
    printf '%sm\n' $((($1 + 30) / 60))
  elif [ "$1" -lt 172800 ]; then
    printf '%sh\n' $((($1 + 1800) / 3600))
  else
    printf '%sd\n' $((($1 + 43200) / 86400))
  fi
}

# many <n> <one> <more>: the count with its word.
many() { if [ "$1" = 1 ]; then printf '%s %s\n' "$1" "$2"; else printf '%s %s\n' "$1" "$3"; fi; }

# hflag <check> <count|?> <worst|-> <text>: one health record, its text also
# joined into the health line. Store text can carry a job or worker name a
# remote party chose, so C1 controls go too and the length is capped.
hflag() {
  hf_text=$(printf '%s' "$4" | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-240)
  hf_worst=$(printf '%s' "$3" | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-120)
  printf 'health\t%s\t%s\t%s\t%s\n' "$1" "$2" "$hf_worst" "$hf_text"
  D_HEALTH="${D_HEALTH:+$D_HEALTH; }$hf_text"
}

# watch_status: the watchers' status, read once per run into WATCH_STATUS;
# fails when it cannot be read. No watcher directory is no watcher.
watch_status() {
  if [ -z "$WATCH_READ" ]; then
    WATCH_READ=failed
    WATCH_STATUS=""
    if [ ! -d "$runtime/watchers" ]; then
      WATCH_READ=ok
    elif WATCH_STATUS=$(/bin/bash "$script_dir/mc-watch.sh" status --program "$program" --now "$NOW" 2>/dev/null); then
      WATCH_READ=ok
    fi
  fi
  [ "$WATCH_READ" = ok ]
}

# watcher_of <script>: the armed watcher running that script, as its cadence
# in seconds, the seconds since its last run and that run's exit (each `-`
# before a first run); nothing when none is armed.
watcher_of() {
  [ -n "$WATCH_STATUS" ] || return 0
  printf '%s\n' "$WATCH_STATUS" | S=$1 awk -F '\t' '$1 == "watcher" {
      n = split($3, p, "/"); if (p[n] == ENVIRON["S"]) { print $4 "\t" $7 "\t" $9; exit } }' | {
    IFS="$TAB" read -r wo_c wo_since wo_exit || exit 0
    wo_s=$(mc_seconds "$wo_c") || exit 0
    printf '%s\t%s\t%s\n' "$wo_s" "${wo_since:--}" "${wo_exit:--}"
  }
}

# Mission control sessions are long-lived by design: never a stale worker.
# They are told by the launcher's name for the kind (session_name in
# scripts/mission-control-launch.sh) and the handover's generation scope,
# never by the words alone, which a worker of the mission-control spec carries.
AWK_MC='function mc(w, s) { return w ~ /^mc-([a-z0-9-]+-)?mission-control-[0-9a-f]+$/ || s ~ /^gen-[0-9]+-[0-9]+-/ }'

# alive_past <state|-> registered|attention <bound>: of the live sessions
# (worker, scope, registered, attention state, its epoch) in that state (`-`
# any) whose registration or attention epoch is at least <bound> old: the
# count, the oldest and its age.
alive_past() {
  ap_f=3
  [ "$2" = registered ] || ap_f=5
  printf '%s' "$H_ALIVE" | N=$NOW S=$1 F=$ap_f B=$3 awk -F '\t' "$AWK_MC"'
    BEGIN { f = ENVIRON["F"] + 0 }
    NF == 5 && !mc($1, $2) && (ENVIRON["S"] == "-" || $4 == ENVIRON["S"]) && $f ~ /^[0-9]+$/ {
      a = ENVIRON["N"] - $f
      if (a >= ENVIRON["B"] + 0) { n++; if (who == "" || a > w) { w = a; who = $1 } }
    }
    END { if (n) print n "\t" who "\t" w }'
}

# A live session behind a tmux server that does not answer may be another
# one past its bound: a count found beside one is a floor, and no count
# beside one is unknown.
tmux_floor() { [ "$H_TMUX_UNKNOWN" -eq 0 ] || printf ' (or more: tmux does not answer)'; }

# unread_store: the store a worker check could not read, the registry first.
unread_store() { if [ "$H_REGISTRY_OK" -ne 1 ]; then printf 'fleet registry'; else printf 'attention store'; fi; }

# live_check <check> <what> <state|-> registered|attention <bound>: the
# shared shape of the worker-age and idle checks.
live_check() {
  if [ "$H_REGISTRY_OK" -ne 1 ] || { [ "$3" != - ] && [ "$H_ATTN_OK" -ne 1 ]; }; then
    hflag "$1" '?' - "$2 unknown (the $(unread_store) cannot be read)"
    return 0
  fi
  if [ "$5" = - ]; then
    hflag "$1" '?' - "$2 unknown (its bound cannot be read)"
    return 0
  fi
  IFS="$TAB" read -r lc_n lc_who lc_age <<EOF
$(alive_past "$3" "$4" "$5")
EOF
  if [ -n "$lc_n" ]; then
    case $1 in
      worker-age) lc_text="$(many "$lc_n" worker workers) live $(dur "$5") or more (oldest $lc_who, $(dur "$lc_age"))" ;;
      *) lc_text="$(many "$lc_n" session sessions) idle $(dur "$5") or more (longest $lc_who, $(dur "$lc_age"))" ;;
    esac
    hflag "$1" "$lc_n" "$lc_who" "$lc_text$(tmux_floor)"
  elif [ "$H_TMUX_UNKNOWN" -gt 0 ]; then
    hflag "$1" '?' - "$2 unknown for $(many "$H_TMUX_UNKNOWN" session sessions) (tmux does not answer)"
  fi
}

health_after_merge() {
  if [ "$H_REGISTRY_OK" -ne 1 ] || [ "$H_ATTN_OK" -ne 1 ]; then
    hflag after-merge '?' - "workers after their merge unknown (the $(unread_store) cannot be read)"
    return 0
  fi
  if [ "$H_B_MERGED_GRACE" = - ]; then
    hflag after-merge '?' - "workers after their merge unknown (its bound cannot be read)"
    return 0
  fi
  # The keeper's landing announcements: session, pull request, state and
  # outcome, kept while it tracks the pull request.
  ha_k=$runtime/keeper-announced
  ha_landed=""
  if [ -e "$ha_k" ] || [ -L "$ha_k" ]; then
    if [ -L "$ha_k" ] || [ ! -f "$ha_k" ] \
      || ! ha_landed=$(awk -F '\t' '($3 == "MERGED" || $3 == "CLOSED") && $4 ~ /^held/ { print $1 "\t" tolower($3) }' "$ha_k" 2>/dev/null); then
      hflag after-merge '?' - "workers after their merge unknown (the keeper's landing record cannot be read)"
      return 0
    fi
  fi
  # A landing names a session, not a launch. One the keeper retired is gone,
  # so a live session under its name is a relaunch; one whose retire it held
  # is still that session. A `held` landing also covers a refused worktree
  # reclaim after the retire went through, which only its ledger's
  # `retired` stage tells apart. A keeper landing has no time, so it
  # outranks a dated merge.
  ha_l=$runtime/keeper.tsv
  if [ -n "$ha_landed" ]; then
    if [ -L "$ha_l" ] || [ ! -f "$ha_l" ] || ! mc_store_ok "$ha_l" 2>/dev/null \
      || ! ha_retired=$(awk -F '\t' 'NR > 1 && $5 == "retired" { print $1 }' "$ha_l" 2>/dev/null); then
      hflag after-merge '?' - "workers after their merge unknown (the keeper's ledger cannot be read)"
      return 0
    fi
    ha_landed=$(printf '%s\n' "$ha_landed" | R=$ha_retired awk -F '\t' '
      BEGIN { m = split(ENVIRON["R"], rl, "\n"); for (i = 1; i <= m; i++) gone[rl[i]] = 1 }
      NF == 2 && !($1 in gone)')
  fi
  IFS="$TAB" read -r ha_n ha_who ha_kind ha_what <<EOF
$(printf '%s' "$H_ALIVE" | N=$NOW B=$H_B_MERGED_GRACE L=$ha_landed awk -F '\t' "$AWK_MC"'
    BEGIN { m = split(ENVIRON["L"], ll, "\n"); for (i = 1; i <= m; i++) if (split(ll[i], x, "\t") == 2) landed[x[1]] = x[2] }
    NF == 5 && !mc($1, $2) {
      kind = ""
      if ($1 in landed) { kind = "landed"; a = 1e15; what = landed[$1] }
      else if ($4 == "merged" && $5 ~ /^[0-9]+$/ && ENVIRON["N"] - $5 >= ENVIRON["B"] + 0) { kind = "merged"; a = ENVIRON["N"] - $5; what = a }
      if (kind == "") next
      n++
      if (who == "" || a > w) { w = a; who = $1; wk = kind; ww = what }
    }
    END { if (n) print n "\t" who "\t" wk "\t" ww }')
EOF
  if [ -z "$ha_n" ]; then
    [ "$H_TMUX_UNKNOWN" -eq 0 ] || hflag after-merge '?' - "workers after their merge unknown for $(many "$H_TMUX_UNKNOWN" session sessions) (tmux does not answer)"
    return 0
  fi
  if [ "$ha_kind" = merged ]; then
    ha_what="merged $(dur "$ha_what") ago"
  else
    ha_what="pull request $ha_what"
  fi
  hflag after-merge "$ha_n" "$ha_who" "$(many "$ha_n" worker workers) still live after the pull request landed ($ha_who, $ha_what)$(tmux_floor)"
}

health_permissions() {
  if [ "$H_ATTN_OK" -ne 1 ]; then
    hflag permissions '?' - "permission prompts unknown (the attention store cannot be read)"
    return 0
  fi
  if [ "$H_B_PERMISSION_WAIT" = - ]; then
    hflag permissions '?' - "permission prompts unknown (its bound cannot be read)"
    return 0
  fi
  IFS="$TAB" read -r hp_n hp_who hp_w <<EOF
$(printf '%s\n' "$H_ATTN" | N=$NOW B=$H_B_PERMISSION_WAIT awk -F '\t' '
    NF == 4 && $2 == "awaiting-input" && $4 ~ /^permission/ && $3 ~ /^[0-9]+$/ {
      a = ENVIRON["N"] - $3
      if (a >= ENVIRON["B"] + 0) { n++; if (who == "" || a > w) { w = a; who = $1 } }
    }
    END { if (n) print n "\t" who "\t" w }')
EOF
  [ -n "$hp_n" ] || return 0
  hflag permissions "$hp_n" "$hp_who" "$(many "$hp_n" "permission prompt" "permission prompts") waiting $(dur "$H_B_PERMISSION_WAIT") or more (longest $hp_who, $(dur "$hp_w"))"
}

health_stuck() {
  hs_dir=$runtime/escalate
  hs_f=$hs_dir/self
  hs_there=0
  [ ! -e "$hs_f" ] && [ ! -L "$hs_f" ] || hs_there=1
  if ! watch_status; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (the watchers cannot be read)"
    return 0
  fi
  hs_w=$(watcher_of mc-escalate.sh)
  if [ -z "$hs_w" ]; then
    [ "$hs_there" -eq 0 ] || hflag mc-stuck '?' - "mission control's own dialog unknown (no escalation watcher is armed)"
    return 0
  fi
  IFS="$TAB" read -r hs_cad hs_since hs_exit <<EOF
$hs_w
EOF
  if ! mc_valid_uint "$hs_since"; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (the escalation watcher has not run)"
    return 0
  fi
  if [ "$hs_since" -gt $((2 * hs_cad + 60)) ]; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (the escalation watcher last ran $(dur "$hs_since") ago)"
    return 0
  fi
  # The watcher keeps its record when it cannot read the pane, and says so
  # by its exit.
  if [ "$hs_exit" != 0 ]; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (the escalation watcher's last run failed)"
    return 0
  fi
  [ "$hs_there" -eq 1 ] || return 0
  hs_rec=""
  [ -L "$hs_dir" ] || [ -L "$hs_f" ] || [ ! -f "$hs_f" ] || hs_rec=$(head -n 1 "$hs_f" 2>/dev/null)
  IFS="$TAB" read -r hs_tag hs_first hs_pid _ hs_kind <<EOF
$hs_rec
EOF
  if [ "$hs_tag" != dialog ] || ! mc_valid_uint "$hs_first"; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (the escalation record cannot be read)"
    return 0
  fi
  # A record outlives a session that ended with its dialog open.
  ! mc_valid_uint "$hs_pid" || kill -0 "$hs_pid" 2>/dev/null || return 0
  if [ "$H_B_STUCK_AFTER" = - ]; then
    hflag mc-stuck '?' - "mission control's own dialog unknown (its bound cannot be read)"
    return 0
  fi
  hs_held=$(age_of "$hs_first")
  [ "$hs_held" -ge "$H_B_STUCK_AFTER" ] || return 0
  hs_what=dialog
  [ "$hs_kind" != auto-mode ] || hs_what="auto-mode prompt"
  hflag mc-stuck 1 "$program" "mission control $program held on its own $hs_what for $(dur "$hs_held")"
}

# Every mission control on the host keeps its reading under its own runtime
# directory, a sibling of this one.
health_context() {
  hc_hits=""
  hc_unknown=""
  set +f
  for hc_f in "${runtime%/*}"/*/context; do
    [ -e "$hc_f" ] || [ -L "$hc_f" ] || continue
    hc_p=${hc_f%/context}
    hc_p=${hc_p##*/}
    mc_valid_program "$hc_p" || continue
    hc_rec=""
    if [ ! -L "${hc_f%/context}" ] && [ ! -L "$hc_f" ] && [ -f "$hc_f" ]; then
      hc_rec=$(F=$MC_FORMAT awk -F '\t' '
        NR == 1 && !($1 == "format" && $2 == ENVIRON["F"]) { exit }
        NR == 1 { ok = 1 }
        $1 == "written" { w = $2 } $1 == "percent" { p = $2 } $1 == "threshold" { t = $2 } $1 == "pid" { d = $2 }
        END { if (ok) print w "\t" (p == "" ? "-" : p) "\t" (t == "" ? "-" : t) "\t" (d == "" ? "-" : d) }' "$hc_f" 2>/dev/null)
    fi
    IFS="$TAB" read -r hc_w hc_pct hc_th hc_pid <<EOF
$hc_rec
EOF
    # A stamp past now beyond a minute's skew is a stepped clock, not fresh.
    if ! mc_valid_uint "$hc_w" || [ "$hc_w" -gt $((NOW + 60)) ]; then
      hc_unknown="${hc_unknown:+$hc_unknown, }$hc_p"
      continue
    fi
    hc_age=$(age_of "$hc_w")
    if [ "$hc_age" -gt "$CONTEXT_FRESH" ]; then
      # A reading whose session is gone is no mission control; one whose
      # session lives on, or cannot be told, is unknown until a day passes.
      # Like flights(), a pid this user cannot signal is taken as recycled.
      if mc_valid_uint "$hc_pid"; then
        kill -0 "$hc_pid" 2>/dev/null || continue
      elif [ "$hc_age" -gt "$CONTEXT_GONE" ]; then
        continue
      fi
      hc_unknown="${hc_unknown:+$hc_unknown, }$hc_p"
      continue
    fi
    # A value outside its grammar is a reading that cannot be read. No
    # measured context, or no threshold (a session that compacts rather than
    # hands over), is nothing to compare.
    if { [ "$hc_pid" != - ] && ! mc_valid_uint "$hc_pid"; } \
      || { [ "$hc_pct" != - ] && { ! mc_valid_uint "$hc_pct" || [ "$hc_pct" -gt 100 ]; }; } \
      || { [ "$hc_th" != - ] && { ! mc_valid_uint "$hc_th" || [ "$hc_th" -lt 1 ] || [ "$hc_th" -gt 100 ]; }; }; then
      hc_unknown="${hc_unknown:+$hc_unknown, }$hc_p"
      continue
    fi
    [ "$hc_pct" != - ] && [ "$hc_th" != - ] || continue
    [ "$hc_pct" -ge "$hc_th" ] || continue
    hc_hits="$hc_hits$hc_p$TAB$hc_pct$TAB$hc_th
"
  done
  set -f
  if [ -n "$hc_hits" ]; then
    IFS="$TAB" read -r hc_n hc_who hc_pct hc_th <<EOF
$(printf '%s' "$hc_hits" | awk -F '\t' 'NF == 3 { n++; if (who == "" || $2 - $3 > w) { w = $2 - $3; who = $1; p = $2; t = $3 } } END { print n "\t" who "\t" p "\t" t }')
EOF
    hflag context "$hc_n" "$hc_who" "$(many "$hc_n" "mission control" "mission controls") at or past the handover context ($hc_who $hc_pct% of $hc_th%)"
  fi
  [ -z "$hc_unknown" ] || hflag context '?' - "context unknown for $hc_unknown (no fresh reading from a live session)"
}

health_ci() {
  if ! watch_status; then
    hflag ci-queue '?' - "CI queue times unknown (the watchers cannot be read)"
    return 0
  fi
  hq_w=$(watcher_of mc-throughput.sh)
  hq_cad=$THROUGHPUT_INTERVAL
  if [ -n "$hq_w" ] && [ "${hq_w%%"$TAB"*}" -gt "$hq_cad" ]; then
    hq_cad=${hq_w%%"$TAB"*}
  fi
  if [ -z "$HOME_DIR" ]; then
    hflag ci-queue '?' - "CI queue times unknown (the program home cannot be read)"
    return 0
  fi
  hq_f=$HOME_DIR/kb/throughput/measure.tsv
  if [ ! -e "$hq_f" ] && [ ! -L "$hq_f" ]; then
    [ -z "$hq_w" ] || hflag ci-queue '?' - "CI queue times unknown (no throughput measure yet)"
    return 0
  fi
  if [ -L "$HOME_DIR/kb" ] || [ -L "$HOME_DIR/kb/throughput" ] || [ -L "$hq_f" ] || [ ! -f "$hq_f" ] \
    || [ "$(head -n 1 "$hq_f" 2>/dev/null)" != "# format: 1" ]; then
    hflag ci-queue '?' - "CI queue times unknown (the throughput measure cannot be read)"
    return 0
  fi
  hq_m=$(awk -F '\t' '$1 == "measured" { print $2; exit }' "$hq_f")
  if ! mc_valid_uint "$hq_m" || [ "$hq_m" -gt $((NOW + 60)) ]; then
    hflag ci-queue '?' - "CI queue times unknown (the throughput measure cannot be read)"
    return 0
  fi
  hq_age=$(age_of "$hq_m")
  if [ "$hq_age" -gt $((2 * hq_cad)) ]; then
    hflag ci-queue '?' - "CI queue times unknown (the throughput measure is $(dur "$hq_age") old)"
    return 0
  fi
  hq_src=$(awk -F '\t' '$1 == "source" && $2 == "ci" { print $3 "\t" $4; exit }' "$hq_f")
  if [ "${hq_src%%"$TAB"*}" != ok ]; then
    hq_why=${hq_src#*"$TAB"}
    [ -n "$hq_src" ] && [ -n "$hq_why" ] && [ "$hq_why" != "$hq_src" ] || hq_why="the measure has no CI reading"
    hflag ci-queue '?' - "CI queue times unknown ($hq_why)"
    return 0
  fi
  if [ "$H_B_CI_QUEUE_SHARE" = - ] || [ "$H_B_CI_QUEUE_FLOOR" = - ]; then
    hflag ci-queue '?' - "CI queue times unknown (its share or floor bound cannot be read)"
    return 0
  fi
  # A job past the floor with no finished run is the worst case of all: its
  # share cannot be taken, and it outranks any that can.
  IFS="$TAB" read -r hq_n hq_who hq_q hq_r <<EOF
$(S=$H_B_CI_QUEUE_SHARE F=$H_B_CI_QUEUE_FLOOR awk -F '\t' '
    $1 == "ci" && NF >= 7 && $4 ~ /^[0-9]+$/ && ($7 == "-" || $7 ~ /^[0-9]+$/) {
      q = $4 + 0
      if (q < ENVIRON["F"] + 0) next
      if ($7 == "-") { r = -1 } else { r = $7 + 0; if (q * 100 < ENVIRON["S"] * r) next }
      n++
      if (who == "" || (wr != -1 && (r == -1 || q * wr > wq * r))) { wq = q; wr = r; who = $2 }
    }
    END { if (n) print n "\t" who "\t" wq "\t" wr }' "$hq_f")
EOF
  [ -n "$hq_n" ] || return 0
  if [ "$hq_r" = -1 ]; then
    hq_run="no finished run"
  else
    hq_run="run $(dur "$hq_r")"
  fi
  hflag ci-queue "$hq_n" "$hq_who" "$(many "$hq_n" "CI job" "CI jobs") queued for $H_B_CI_QUEUE_SHARE% or more of their run ($hq_who: queue $(dur "$hq_q"), $hq_run)"
}

# health: every check, after flights() and program_home have read their
# stores; a registry flights() could not read leaves the attention store
# to be read here.
health() {
  D_HEALTH=""
  if [ "$H_REGISTRY_OK" -ne 1 ]; then
    flight_attention >/dev/null
    H_ATTN=$fl_attn
    H_ATTN_OK=$fl_attn_ok
  fi
  health_bounds
  live_check worker-age "worker ages" - registered "$H_B_WORKER_AGE"
  health_after_merge
  health_permissions
  health_stuck
  health_context
  health_ci
  live_check idle "idle sessions" idle attention "$H_B_IDLE_AFTER"
}

the_line() {
  ln_text="mission control $program: $D_FLIGHT in flight, $D_WAITING waiting"
  [ "$D_MERGE_READY" = 0 ] || ln_text="$ln_text, $D_MERGE_READY ready to merge"
  [ -z "$target" ] || ln_text="$ln_text, $D_PENDING pending"
  case $D_APPROVALS in
    0) ;;
    1) ln_text="$ln_text, 1 approval mission control is handling" ;;
    *) ln_text="$ln_text, $D_APPROVALS approvals mission control is handling" ;;
  esac
  ln_text="$ln_text, rung $D_RUNG"
  [ -z "$D_OLDEST" ] || ln_text="$ln_text, $D_OLDEST"
  [ -z "$D_HEALTH" ] || ln_text="$ln_text; health: $D_HEALTH"
  clean_field "$ln_text"
}

# The text panel: the pane's first rows as plain lines, for a session where
# nothing draws the pane.
text_panel() {
  {
    flights
    waiting
    merge_ready
    pending
    budget
    program_home
    health
    contexts
  } | P=$program awk -F '\t' '
    $1 == "context" { x[++nx] = $2 " " ($3 == "unknown" ? "unknown" : $3 "% (" $4 ")") }
    $1 == "flight" { f[++n] = "  " $2 "  " $3 "  (" $4 ")" }
    $1 == "waiting" { w = ($2 == "-" ? "shown by the host" : $2) }
    $1 == "merge-ready" && $3 == "all" { m = $2 + 0 }
    $1 == "merge-ready" && $3 == "partial" { m = ($2 > 0 ? $2 " or more" : "unknown") " (some could not be judged)" }
    $1 == "unreadable" && $2 == "merge-ready store" { m = "unknown (the merge-ready store cannot be read)" }
    $1 == "approvals" { a = $2 }
    $1 == "pending" { p = $2 }
    $1 == "unreadable" && $2 == "events" { p = "unknown (the events cannot be read)" }
    $1 == "rung" { r = $2 (($3 == "" || $3 == "-") ? "" : " (" $3 ")") }
    $1 == "unreadable" && $2 == "fleet registry" { fu = 1 }
    $1 == "unreadable" && $2 == "tmux windows" { tu = 1 }
    $1 == "unreadable" && $2 == "attention store" { au = 1 }
    $1 == "unreadable" && $2 == "operator queue" { w = "unknown (the queue cannot be read)" }
    $1 == "unreadable" && $2 == "budget" { r = "unknown (the budget cannot be read)" }
    $1 == "health" { h = h (h == "" ? "" : "; ") $5 }
    END {
      print "mission control " ENVIRON["P"]
      c = n + 0
      if (fu) c = "unknown (the fleet registry cannot be read)"
      else if (tu && au) c = "unknown (neither tmux nor the attention store can be read)"
      else if (tu) c = c " or more (tmux does not answer)"
      else if (au) c = "up to " c " (the attention store cannot be read)"
      print "in flight: " c
      for (i = 1; i <= n; i++) print f[i]
      print "waiting on you: " (w == "" ? "unknown" : w)
      if (m != "" && m != 0) print "ready to merge: " m
      if (a + 0 > 0) print "approvals mission control is handling: " a
      if (p != "") print "pending wakes: " p
      print "rung: " (r == "" ? "unknown" : r)
      if (h != "") print "health: " h
      for (i = 1; i <= nx; i++) print "context: " x[i]
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
  names_session "$1/$2.ack" "$2"
}

activate() {
  if [ -n "$session" ]; then
    own_session "$session" || mc_usage_fail "refusing to activate session $session: it is not this session"
  else
    session=$(self_session) || no_session
  fi
  [ -n "$target" ] || target=$program
  ac_dir=$(panel_dir active) || mc_fail "cannot open the activation directory"
  ac_sd=$(panel_dir sessions) || ac_sd=""
  if [ -n "$pid" ] && ! { [ -n "$ac_sd" ] && names_session "$ac_sd/$pid" "$session"; }; then
    mc_usage_fail "refusing --pid $pid: no session-start record of that process names this session"
  fi
  # CLAUDE_PID counts only when the session-start record for it names this
  # session; otherwise the live process that record names, else `-`.
  if [ -z "$pid" ] && mc_valid_uint "${CLAUDE_PID:-}" && [ -n "$ac_sd" ] \
    && names_session "$ac_sd/$CLAUDE_PID" "$session"; then
    pid=$CLAUDE_PID
  fi
  if [ -z "$pid" ] && [ -n "$ac_sd" ]; then
    set +f
    for ac_f in "$ac_sd"/*; do
      ac_k=${ac_f##*/}
      if ! { mc_valid_uint "$ac_k" && names_session "$ac_f" "$session" && pid_alive "$ac_k"; }; then
        continue
      fi
      pid=$ac_k
      break
    done
    set -f
  fi
  [ -n "$pid" ] || pid=-
  ac_rec=$ac_dir/$session
  [ ! -L "$ac_rec" ] && [ ! -L "$ac_rec.ack" ] || mc_fail "the activation record is a symlink"
  # The same record from the same live process keeps the mod's
  # acknowledgment; anything else waits for a new one, so an acknowledgment
  # left by a crashed process never answers for a mod that is not loaded.
  if ! { mc_format_ok "$ac_rec" && [ "$(field_of "$ac_rec" program)" = "$program" ] \
    && [ "$(field_of "$ac_rec" target)" = "$target" ] && [ "$(field_of "$ac_rec" session)" = "$session" ] \
    && [ "$pid" != - ] && [ "$(field_of "$ac_rec" pid)" = "$pid" ]; }; then
    rm -f -- "$ac_rec.ack" || mc_fail "cannot clear the old acknowledgment"
  fi
  # A marker left by an earlier release must never end the session this
  # activation starts.
  rm -f -- "$ac_rec.exit" || mc_fail "cannot clear an old exit marker"
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
  merge_ready
  pending
  program_home
  decisions
  budget
  watchers
  sources
  kb
  measures
  reviews
  host
  handover
  holder
  health
  contexts
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
  health)
    flights >/dev/null
    program_home >/dev/null
    health >/dev/null
    [ -z "$D_HEALTH" ] || printf 'health: %s\n' "$D_HEALTH"
    ;;
  activate) activate ;;
  await) await_panel ;;
  text) text_panel ;;
esac
