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
TAB=$(printf '\t')

usage() {
  mc_usage_fail "usage: mc-panel.sh digest|line|text|presence|activate|await|lookup|ack|retire|prune|where|floor|session-hook|install|changes ... (mc-panel.sh --help)"
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
but the presence marker, with --target the target's lease, the install
record with its event, and the activation files below. A store that
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
                                             ended, done, merged or waiting
                                             on its PR, or with nothing to
                                             watch (rows of a tmux server
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
      acknowledgment unless the record names the same program, target and
      process;
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
  mc-panel.sh prune
      remove every record whose pid is no live process (one with no pid
      is kept), every acknowledgment with no record, and
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
activation file cannot be read or written, a target's lease or the install
record cannot be written (its directory a symlink included), the install
event is refused, the copy's root, version or changelog cannot be read, or
`lookup` finds no record for the session; 2 usage; 3 the program is not
configured; 4 this session's id cannot be told.

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
while [ $# -gt 0 ]; do
  case $1 in
    --program | --target | --now | --root | --from | --session | --pid | --wait)
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
  [ -z "$root$from" ] || usage
}
case $verb in
  digest | line)
    [ -z "$presence_kind" ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s$root$from" ] || usage
    ;;
  presence)
    [ -n "$presence_kind" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s$root$from" ] || usage
    ;;
  install)
    [ -z "$presence_kind$target$from" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -n "$program" ] && [ -z "$session$pid$wait_s" ] || usage
    ;;
  changes)
    [ -n "$from" ] && [ -z "$program$presence_kind$target$now" ] && [ "$with_knobs" -eq 0 ] || usage
    [ -z "$session$pid$wait_s" ] || usage
    ;;
  activate) only "program target now session pid" ;;
  text) only "program target" ;;
  await) only "program session wait" ;;
  lookup | retire) only "session" ;;
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
    rm -f -- "$act_dir/$session" "$act_dir/$session.ack" || mc_fail "cannot remove the activation record"
    printf 'retired\t%s\n' "$session"
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

# The windows of the tmux server, when a registry row names one. A server
# that is not running has no windows; one that does not answer is unknown,
# and its rows count neither way.
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
          *)
            fl_tmux=0
            printf 'unreadable\ttmux windows\n'
            ;;
        esac
      fi
      ;;
  esac
}

# Each worker's attention state, as worker and state. An absent store is
# an empty one; one that is there but cannot be read is unknown.
flight_attention() {
  fl_attn=''
  fl_attn_ok=1
  if fl_root=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null); then
    fl_as=$fl_root/attention/state
    if [ -e "$fl_as" ] || [ -L "$fl_as" ]; then
      if [ -L "$fl_as" ] || [ ! -f "$fl_as" ] \
        || ! fl_attn=$(awk -F '\t' 'NF >= 3 { print $1 "\t" $3 }' "$fl_as" 2>/dev/null); then
        fl_attn=''
        fl_attn_ok=0
        printf 'unreadable\tattention store\n'
      fi
    fi
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
  flight_windows
  flight_attention
  # Each row classed as live, a pid to probe, done or unknown. A window id
  # is looked up across the server, as a renamed session keeps its windows;
  # the token is also tried as a window name in its session.
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
        seen = (h[3] ~ /^@[0-9]+$/ && (h[3] in id)) || ((h[2] SUBSEP h[3]) in nm)
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
    $1 == "unreadable" && $2 == "events" { p = "unknown (the events cannot be read)" }
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
  names_session "$1/$2.ack" "$2"
}

activate() {
  [ -n "$session" ] || session=$(self_session) || no_session
  [ -n "$target" ] || target=$program
  ac_dir=$(panel_dir active) || mc_fail "cannot open the activation directory"
  ac_sd=$(panel_dir sessions) || ac_sd=""
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
  activate) activate ;;
  await) await_panel ;;
  text) text_panel ;;
esac
