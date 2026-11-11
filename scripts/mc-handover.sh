#!/usr/bin/env bash
# mc-handover.sh — mission control's succession: the handover trigger for a
# session without the mod, the handover file, the launch of a successor
# through the launcher, the successor's self-check against the file, the
# transfer of the program name and the retirement of the predecessor, and
# the operator-asked resume by name.
#
# Emits: markdown
#
# `mc-handover.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-handover
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

# The age past which a mod's lease no longer proves its session live, the
# bound scripts/mc-wake.sh puts on it.
LEASE_FRESH=300
# scripts/mc-event.sh's bound on an event's text.
EVENT_TEXT_MAX=512
# How long a take or resume waits for a retired predecessor's process to
# exit: a session that released can take a moment to end; one the launcher
# retired ends at once.
EXIT_WAIT=30s

help_text() {
  cat <<'HELP'
mc-handover.sh — the succession of a program's mission-control session.

THE PROGRAM NAME is held by exactly one session at a time, recorded in the
holder record <runtime>/holder (the program's runtime directory under the
fleet home): the session's handle, its kind, the generation it took the
name at and, where it can tell, its own process (`--pid`, else
CLAUDE_PID) with an identity fixed for that process's life. A `registry`
holder is a session the launcher started
(scripts/mission-control-launch.sh), live while its registry row exists;
an `attended` holder is the operator's own session, stale only on positive
evidence: a wake lease (<runtime>/leases/<handle>, which the mod restamps)
older than the mod's lease bound. With no readable lease (a session without
the mod) it counts as live, so only the operator's resume moves its name.
The harness's own session name is a display name fixed at launch, so the
name other sessions address is this record, never it.

THE HANDOVER FILE, <home>/handover.tsv in the program home, is what the
predecessor hands its successor, one record per line, tab separated:
  format 1 | program <p> | predecessor <handle> | written <epoch>
  | ledger <last decisions-log id or -> | rules <digest of the loaded rules>
  | item <id>... | session <handle>...
A reader refuses a file whose format it does not know, naming the field.

Usage:
  mc-handover.sh due --program <p> --context <percent|-> --wakes <n>
      --compactions <n>
      the trigger the mod applies, for a session without it, which a
      caller applies only in a launched holder (it reads no holder
      record): the compaction ceiling first, then measured context where
      there is a reading, the completed-wake count otherwise; a knob that
      does not read skips its rule, warned. Prints due<TAB><reason> or
      not-due
  mc-handover.sh holder --program <p> [--now <epoch>]
      holder<TAB><handle><TAB><kind><TAB><since><TAB><generation>
      <TAB>live|stale, or holder<TAB>- with no holder
  mc-handover.sh path --program <p>
      path<TAB>unattended, or, where the holder is a live attended
      session, path<TAB>pane<TAB>tmux when that session runs inside tmux
      (the probe is read-only: TMUX and TMUX_PANE set, tmux answers for
      that pane), so it hands over itself with launch --handover and the
      successor closes only its pane; otherwise
      path<TAB>operator-act<TAB><command>, one operator act, the command
      opening a fresh session that resumes
  mc-handover.sh offer --program <p>
      raise that act as an operator item (event handover-act) for the
      panel; prints offered<TAB><event id>
  mc-handover.sh write --program <p> --session <handle> --picture <file>
      --digest <hex> [--now <epoch>]
      the holder writes the handover file from its held picture
      (`item <id>` and `session <handle>` lines, mc-rules.sh selfcheck's
      grammar) and its loaded rules' digest; the ledger is the newest
      decisions-log entry. Prints handover<TAB><path><TAB><ledger>
  mc-handover.sh launch --program <p> --brief <file> [--handover | --asked]
      [--backend stream-json|tmux] [--cwd <abs-dir>] [--now <epoch>]
      launch the successor through the launcher (kind mission-control,
      scope gen-<generation>-<epoch>-<nonce>), its brief carrying the handover file's
      path. A live holder admits only the operator's ask (--asked) or a
      live handover (--handover: a handover file naming the live
      holder); any other launch is refused naming the holder, and a
      handover launch over an attended holder is admitted inside tmux (the
      predecessor's pane id is recorded for take to close) and refused
      elsewhere (exit 4), where path names the operator act. A
      stale holder is recorded as the predecessor. A tmux successor's
      Remote Control follows mission_control_successor_remote_control:
      off (the default) starts none; on names the successor as itself;
      inherit carries the live predecessor's --remote-control (read from
      its argv; a bare flag names the successor as itself). Argv cannot
      show Remote Control turned on in-session, so a predecessor with no
      flag gives none and a malformed name gives none, an unreadable
      predecessor gives on (it may have had it); each is said on stderr,
      in the successor's brief and on the take line. The
      stream-json rung ignores the knob. Prints successor<TAB><name>
  mc-handover.sh verify --program <p> --session <name> --picture <file>
      --digest <hex> --ledger <id|-> [--durable <file>]
      the successor's self-check: its held picture, rules digest and
      ledger position against the handover file (or, with none, its
      picture against --durable, read by the caller from the stores, and
      its ledger against the decisions log), through mc-rules.sh
      selfcheck. A pass marks the successor verified and prints
      verified<TAB><name><TAB><the self-check line>; a failure raises an
      item (event handover-failed), prints its item lines and leaves the
      predecessor holding the name
  mc-handover.sh release --program <p> --session <handle> [--now <epoch>]
      the holder gives up the name to its verified successor (a registered
      session naming it as predecessor) or else to a resume that asked
      for it; prints released<TAB><handle><TAB><to>. The released session
      then ends itself: the calling session's own panel activation of
      this program is retired for exit (mc-panel.sh retire --exit), its
      mod ending the session once the turn is over, and it prints
      exit<TAB>mod; otherwise exit<TAB>none<TAB><why>
  mc-handover.sh take --program <p> --session <name> [--window <cadence>]
      [--pid <pid>] [--exit-wait <cadence>] [--now <epoch>]
      the verified successor takes the name: it asks a live predecessor
      to release (event handover-requested), waits up to the window
      (mission_control_handover_window) for that release, moves the
      holder record and retires the predecessor's registry row through
      the launcher (one that did not release is retired all the same),
      waits up to --exit-wait (default 30s) for the predecessor's process
      to exit, closes the predecessor's recorded tmux pane (that pane id
      on that socket only, never found by name, printing pane<TAB><id><TAB>closed|held) once the name has moved, then announces
      itself
  mc-handover.sh resume --program <p> --session <handle>
      [--kind attended|registry] --picture <file> --digest <hex>
      --durable <file> [--window <cadence>] [--pid <pid>]
      [--exit-wait <cadence>] [--now <epoch>]
      the operator-asked resume (--kind defaults to attended, the
      operator's own session; registry needs the session's registry
      row): the self-check against --durable, a release request to a live
      holder (event handover-requested), the same wait, transfer,
      retirement, exit wait and announcement, and what changed since the
      operator's last turn
  --pid names the taking session's own process for the holder record, so
  the next take or resume can confirm it exited; it defaults to
  CLAUDE_PID. A predecessor's process is the one its holder record names,
  never the taking session's own process or one of its ancestors; a
  holder record naming none (written by an earlier planwright, or by a
  session that could not tell) leaves nothing to wait for.

take and resume print, in order:
  took<TAB><handle><TAB><predecessor|-><TAB>released|retired|none
      released: the predecessor gave up the name; retired: it did not
      within the window, or was already gone; none: there was none
  retire<TAB><session><TAB>released|partial|attended|gone
  retire<TAB><session><TAB>alive<TAB><pid>
      for the predecessor, then for a pending successor the handover
      left behind: released, the launcher retired its row; partial, it
      retired only part and an item is raised; attended, the operator's
      own session, which has no row and ends itself once it releases
      (release, above); gone, the row was already absent;
      alive, the predecessor's process still ran when the exit wait
      closed (after a partial retire too), so it is not reported retired
      and an item (event handover-predecessor-alive) names the process
      to close. Without a recorded process, released, attended and gone
      do not confirm that the session's process has exited
  changed<TAB>decision<TAB><ts><TAB><subject><TAB><act>     (resume)
  changed<TAB>event<TAB><epoch><TAB><kind><TAB><subject>    (resume)
  changed<TAB>none | changed<TAB>unknown<TAB><store>        (resume)
  announce<TAB><session>      each live session the launcher registered
                              for the program, the event
                              mission-control-announce raised once for all
  line<TAB><the one line the operator sees>
Any verb but offer raising an item that mc-event.sh refuses prints
unraised<TAB><kind><TAB><subject> as well; offer exits 1 instead.

Exit codes: 0 done; 1 refused (a store's format, a failed self-check, a
session that is not the holder or the verified successor, a failed write)
or a launcher failure, and also 1 from a take or resume that has moved the
name when a retirement was only partly done or the predecessor still runs
(partial or alive above); 2 usage or an invalid value; 3 the name is
held (a launch with neither the ask nor a live handover, a successor
already pending, a take or resume beaten to the name) or the program is
not configured; 4 a handover launch over an attended holder outside tmux,
which hands over by the operator's act.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-handover.sh due|holder|path|offer|write|launch|verify|release|take|resume --program <p> ... (mc-handover.sh --help)"
}

scratch=''
# A release request this run wrote, removed if the run ends without the
# name, so a holder never releases to a resume that gave up.
own_request=''
# shellcheck disable=SC2329 # invoked from the EXIT trap
cleanup() {
  if [ -n "$own_request" ] && [ -f "$own_request" ] && [ "$(mc_kv "$own_request" from 2>/dev/null)" = "$session" ]; then
    rm -f "$own_request"
  fi
  pw_lock_release_all
  [ -z "$scratch" ] || rm -f "$scratch"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

say() { printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2; }
need() { [ -n "$2" ] || mc_usage_fail "--$1 is required"; }

# kv_handle <file> <key>: a session handle a record names, or `-`; a value
# outside the handle grammar is refused, since it reaches paths and the
# launcher.
kv_handle() {
  kh=$(mc_kv "$1" "$2")
  [ "$kh" = - ] || mc_valid_handle "$kh" || mc_fail "$(sanitize_printable "$1") names a $2 outside the handle grammar"
  printf '%s\n' "$kh"
}

valid_sha256() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

parse_rc_mode() {
  case $1 in off | inherit | on) printf '%s\n' "$1" ;; *) return 1 ;; esac
}

parse_pct() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100 ] || return 1
  printf '%s\n' "$1"
}

# check_picture <file>: a readable file of `item <id>` and `session <h>`.
check_picture() {
  [ -f "$1" ] && [ -r "$1" ] || mc_usage_fail "$(sanitize_printable "$1") is not a readable file"
  cp_bad=$(awk '!/^[ \t]*$/ && !/^(item|session)[ \t]+[A-Za-z0-9._:-]+$/ { print NR; exit }' <"$1")
  [ -z "$cp_bad" ] || mc_usage_fail "$(sanitize_printable "$1"):$cp_bad: not an 'item <id>' or 'session <handle>' line"
}

# format_refusal <file>: why a store's format is refused, or nothing when it
# is this script's.
format_refusal() {
  mc_format_ok "$1" && return 0
  fr=$(awk -F '\t' 'NR == 1 && $1 == "format" { print $2 }' "$1" 2>/dev/null)
  printf 'refusing %s: its format field is %s, not %s\n' "$(sanitize_printable "$1")" "$(sanitize_printable "${fr:-missing}")" "$MC_FORMAT"
}
store_check() {
  sc_why=$(format_refusal "$1")
  [ -z "$sc_why" ] || mc_fail "$sc_why"
}

runtime_paths() {
  RUNTIME=$(mc_runtime "$program") || mc_fail "the runtime directory of program $program does not resolve"
  FH=$(mc_fleet_home) || mc_fail "the fleet home does not resolve"
  SESSIONS=$FH/mission-control/sessions
  HOLDER=$RUNTIME/holder
  SUCC=$RUNTIME/successor
  RELEASED=$RUNTIME/released
  REQUEST=$RUNTIME/release-request
  LOCK=$RUNTIME/handover.lock
}

home_path() {
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home 2>/dev/null)
  hp_rc=$?
  case $hp_rc in
    0) ;;
    2 | 3)
      say "the home of program $program does not resolve (mc-program.sh exit $hp_rc)"
      exit "$hp_rc"
      ;;
    *) mc_fail "the home of program $program does not resolve (mc-program.sh exit $hp_rc)" ;;
  esac
  case $HOME_DIR in
    /*) ;;
    *) mc_fail "the program home is not absolute" ;;
  esac
  HANDOVER=$HOME_DIR/handover.tsv
}

row_exists() { [ -f "$SESSIONS/$1" ] && [ ! -L "$SESSIONS/$1" ]; }

# session_live <handle> <kind>: the evidence the holder's kind keeps.
# tmux_probe: 0 when this process runs in a tmux pane that tmux itself
# confirms; read-only, and the pane id is the only identity it trusts.
tmux_probe() {
  [ -n "${TMUX:-}" ] || return 1
  case ${TMUX_PANE:-} in
    %[0-9]*) ;;
    *) return 1 ;;
  esac
  case ${TMUX_PANE#%} in *[!0-9]*) return 1 ;; esac
  command -v tmux >/dev/null 2>&1 || return 1
  tp_sock=${TMUX%%,*}
  case $tp_sock in /*) ;; *) return 1 ;; esac
  [ "$(tmux -S "$tp_sock" display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null </dev/null)" = "$TMUX_PANE" ]
}

# close_pred_pane <pane id or -> <tmux socket or ->: the successor closes the
# predecessor's recorded tmux pane, on the server whose socket was recorded
# with it (a pane id is unique only within one server), after the name
# moved, that pane only.
close_pred_pane() {
  [ "$1" != - ] && [ "$2" != - ] || return 0
  case $2 in /*) ;; *) return 0 ;; esac
  case $1 in %[0-9]*) ;; *) return 0 ;; esac
  case ${1#%} in *[!0-9]*) return 0 ;; esac
  [ "$1" != "${TMUX_PANE:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  [ "$(tmux -S "$2" display-message -p -t "$1" '#{pane_id}' 2>/dev/null </dev/null)" = "$1" ] || return 0
  if tmux -S "$2" kill-pane -t "$1" >/dev/null 2>&1 </dev/null; then
    printf 'pane\t%s\tclosed\n' "$1"
  else
    printf 'pane\t%s\theld\n' "$1"
  fi
}

session_live() {
  case $2 in
    registry) row_exists "$1" ;;
    attended)
      sl_l="$RUNTIME/leases/$1"
      [ ! -L "$RUNTIME/leases" ] && [ -f "$sl_l" ] && [ ! -L "$sl_l" ] || return 0
      sl_at=$(head -n 1 "$sl_l" 2>/dev/null)
      mc_valid_uint "$sl_at" && [ "$sl_at" -le "$NOW" ] || return 0
      [ $((NOW - sl_at)) -lt "$LEASE_FRESH" ]
      ;;
    *) mc_fail "a record names an unknown session kind '$(sanitize_printable "$2")'" ;;
  esac
}

# read_holder: H_SESSION (empty with no holder), H_KIND, H_SINCE, H_GEN,
# H_LIVE (1 or 0), H_PID and H_START (empty when the record names none).
read_holder() {
  H_SESSION='' H_KIND='' H_SINCE='' H_GEN=0 H_LIVE=0 H_PID='' H_START=''
  [ -e "$HOLDER" ] || return 0
  store_check "$HOLDER"
  H_SESSION=$(mc_kv "$HOLDER" session)
  H_KIND=$(mc_kv "$HOLDER" kind)
  H_SINCE=$(mc_kv "$HOLDER" since)
  H_GEN=$(mc_kv "$HOLDER" generation)
  H_PID=$(mc_kv "$HOLDER" pid)
  H_START=$(mc_kv "$HOLDER" pid-start)
  if ! mc_valid_uint "$H_PID" || [ "$H_PID" -le 1 ] || [ -z "$H_START" ]; then H_PID='' H_START=''; fi
  if ! mc_valid_handle "$H_SESSION" || ! mc_valid_uint "$H_GEN" || ! mc_valid_uint "$H_SINCE"; then
    mc_fail "the holder record $(sanitize_printable "$HOLDER") is outside its grammar"
  fi
  if session_live "$H_SESSION" "$H_KIND"; then H_LIVE=1; fi
}

# The script's own EXIT trap releases every lock, so lock-lib's trap, which
# would replace it, is never installed.
lock() {
  pw_lock_acquire "$LOCK" 100 || mc_fail "cannot take the handover lock of program $program"
}
unlock() { pw_lock_release "$LOCK" || :; }

# record <file> <key> <value>...: a store of key<TAB>value lines, written
# whole by rename, owner-only.
record() {
  r_file=$1
  shift
  {
    printf 'format\t%s\n' "$MC_FORMAT"
    while [ $# -ge 2 ]; do
      printf '%s\t%s\n' "$1" "$2"
      shift 2
    done
  } | (umask 077 && mc_write "$r_file") || mc_fail "cannot write $(sanitize_printable "$r_file")"
}

# succ_record <session> <predecessor> <kind> <launched> <mode> <verified>
# [<owner> [<predecessor pane> [<predecessor tmux socket>]]]: the owner is the launch that reserved it,
# until it is verified.
succ_record() {
  record "$SUCC" session "$1" predecessor "$2" predecessor-kind "$3" launched "$4" mode "$5" verified "$6" owner "${7:--}" predecessor-pane "${8:--}" predecessor-tmux "${9:--}" remote-control-note "${10:--}"
}

# require_successor <fail-function>: SUCC names $session; sets S_PRED and
# S_PRED_KIND.
require_successor() {
  [ -f "$SUCC" ] || "$1" successor "$session is not the pending successor of program $program: none is pending"
  rs_why=$(format_refusal "$SUCC")
  [ -z "$rs_why" ] || "$1" format "$rs_why"
  [ "$(mc_kv "$SUCC" session)" = "$session" ] || "$1" successor "$session is not the pending successor of program $program"
  S_PRED=$(kv_handle "$SUCC" predecessor) || exit 1
  S_PRED_KIND=$(mc_kv "$SUCC" predecessor-kind)
  S_PANE=$(mc_kv "$SUCC" predecessor-pane)
  [ -n "$S_PANE" ] || S_PANE=-
  S_TMUX=$(mc_kv "$SUCC" predecessor-tmux)
  [ -n "$S_TMUX" ] || S_TMUX=-
}
refuse() { mc_fail "$2"; }

raise() { # raise <kind> <subject> <text>
  r_text=$(printf '%s' "$3" | mc_clean_text | head -c "$EVENT_TEXT_MAX")
  if ! mc_event emit --program "$program" --now "$NOW" -- "$1" "$2" "$r_text" >/dev/null; then
    say "warning: the $1 item could not be raised"
    printf 'unraised\t%s\t%s\n' "$1" "$2"
  fi
}

# fail_item <aspect> <text>: an operator item for a failed handover; the
# predecessor keeps the name.
fail_item() {
  printf 'item\thandover\t%s\t%s\t%s\n' "$1" "$(sanitize_printable "$2")" "repair it, then rerun the handover"
  raise handover-failed "$session" "$2"
  exit 1
}

last_ledger() {
  ll=$(mc_kb_entries "$program" decisions) || exit 1
  ll=$(printf '%s\n' "$ll" | awk -F '\t' 'NF { id = $1 } END { print id }')
  printf '%s\n' "${ll:--}"
}

# selfcheck <digest> <held> <durable>: mc-rules.sh selfcheck; a failure
# prints its item lines (or, with none, what it said on stderr), raises
# one item and exits.
selfcheck() {
  sc_err=$(mktemp "${TMPDIR:-/tmp}/mc-handover.XXXXXX") || mc_fail "cannot run the self-check"
  SC_OUT=$(/bin/bash "$script_dir/mc-rules.sh" selfcheck "$program" --digest "$1" --held "$2" --durable "$3" 2>"$sc_err")
  sc_rc=$?
  sc_said=$(head -n 1 "$sc_err" | mc_clean)
  rm -f "$sc_err"
  [ "$sc_rc" -ne 0 ] || return 0
  sc_items=$(printf '%s\n' "$SC_OUT" | awk -F '\t' '$1 == "item"' | mc_clean)
  if [ -n "$sc_items" ]; then
    printf '%s\n' "$sc_items"
    sc_first=$(printf '%s\n' "$sc_items" | awk -F '\t' '{ print $4; exit }')
  else
    sc_first=${sc_said:-mc-rules.sh selfcheck exited $sc_rc}
    printf 'item\thandover\tself-check\t%s\t%s\n' "$sc_first" "repair it, then rerun the handover"
  fi
  raise handover-failed "$session" "the self-check failed: $sc_first"
  case $sc_rc in 2 | 3) exit "$sc_rc" ;; esac
  exit 1
}

window_seconds() {
  if [ -n "$window" ]; then
    mc_seconds "$window" || mc_usage_fail "--window takes a cadence (a positive count of s, m, h or d)"
    return 0
  fi
  ws=$(mc_knob mission_control_handover_window mc_parse_cadence) || exit 1
  mc_seconds "$ws"
}

# released_to <from> <to>: the predecessor's release names this taker.
released_to() {
  [ -f "$RELEASED" ] && mc_format_ok "$RELEASED" && [ "$(mc_kv "$RELEASED" session)" = "$1" ] && [ "$(mc_kv "$RELEASED" to)" = "$2" ]
}

# wait_release <from> <kind> <to> <seconds>: 0 once the predecessor has
# released to <to>; 1 when the window closes or the predecessor is gone.
wait_release() {
  wr_end=$(($(mc_now) + $4))
  while :; do
    released_to "$1" "$3" && return 0
    # Liveness is judged at the real clock; NOW keeps the caller's --now,
    # which the holder record is stamped with.
    wr_keep=$NOW
    NOW=$(mc_now)
    wr_now=$NOW
    session_live "$1" "$2"
    wr_live=$?
    NOW=$wr_keep
    [ "$wr_live" -eq 0 ] || return 1
    [ "$wr_now" -lt "$wr_end" ] || return 1
    sleep 1
  done
}

# proc_start <pid>: an identity for the process fixed for its life, or
# nothing: the boot and the start in clock ticks where procfs shows them,
# else ps's start time in UTC, so the caller's time zone never changes it
# and a recycled pid never matches it.
proc_start() {
  if [ -r "/proc/$1/stat" ]; then
    ps_boot=$(head -n 1 /proc/sys/kernel/random/boot_id 2>/dev/null) || ps_boot=''
    B=$ps_boot awk '{ sub(/.*\) /, ""); print "boot:" ENVIRON["B"] ":" $20 }' "/proc/$1/stat" 2>/dev/null
  elif [ ! -d /proc/self ]; then
    TZ=UTC0 ps -p "$1" -o lstart= 2>/dev/null | awk 'NF { $1 = $1; print }'
  fi
}

# proc_alive <pid> <start>: the process the identity was taken from still
# runs and is not a zombie.
proc_alive() {
  [ -n "$2" ] && [ "$(proc_start "$1")" = "$2" ] || return 1
  case $(ps -o stat= -p "$1" 2>/dev/null) in
    *Z*) return 1 ;;
  esac
}

# is_own <pid>: the pid is this process, one of its ancestors or the taker's
# own process, none of which is ever a predecessor's.
is_own() {
  [ "$1" != "$own_pid" ] || return 0
  io_pid=$$
  io_n=0
  while mc_valid_uint "$io_pid" && [ "$io_pid" -gt 1 ] && [ "$io_n" -lt 64 ]; do
    [ "$io_pid" != "$1" ] || return 0
    if [ -r "/proc/$io_pid/stat" ]; then
      io_pid=$(sed 's/.*) //' "/proc/$io_pid/stat" 2>/dev/null | cut -d' ' -f2)
    else
      io_pid=$(ps -o ppid= -p "$io_pid" 2>/dev/null | tr -d ' ')
    fi
    io_n=$((io_n + 1))
  done
  return 1
}

# predecessor_remote_control <pid> <start>: the Remote Control a live process
# was started with, read from its argv before the prompt's `--`: `named <name>`
# for --remote-control <name> or --remote-control=<name>, `bare` for the flag
# with no name, `none`, or `unreadable` when no live process of that identity
# can be read.
predecessor_remote_control() {
  if [ -z "$1" ] || ! proc_alive "$1" "$2"; then
    printf '%s\n' unreadable
    return 0
  fi
  # /proc keeps the argv NUL-separated; without it (macOS) ps joins it with
  # spaces, which splits only a name the session-name grammar already refuses.
  if [ -r "/proc/$1/cmdline" ]; then
    prc_argv=$(tr '\0' '\n' <"/proc/$1/cmdline")
  elif prc_argv=$(ps -ww -o command= -p "$1" 2>/dev/null) && [ -n "$prc_argv" ]; then
    prc_argv=$(printf '%s\n' "$prc_argv" | tr ' ' '\n')
  else
    printf '%s\n' unreadable
    return 0
  fi
  printf '%s\n' "$prc_argv" | awk '
    $0 == "--" { exit }
    seen { found = 1; if (substr($0, 1, 1) == "-") print "bare"; else print "named " $0; exit }
    $0 == "--remote-control" { seen = 1; next }
    index($0, "--remote-control=") == 1 {
      found = 1
      v = substr($0, 19)
      if (v == "") print "bare"; else print "named " v
      exit
    }
    END { if (!found) print (seen ? "bare" : "none") }'
}

# await_exit <pid> <start>: wait up to the exit wait for the process to exit,
# ending at whichever comes first of that many polls (a clock step cannot
# stretch it) and that many seconds (nor can a slow poll); 1 when it still
# runs.
await_exit() {
  ae_n=0
  ae_end=$(($(mc_now) + exit_secs))
  while proc_alive "$1" "$2"; do
    [ "$ae_n" -lt "$exit_secs" ] && [ "$(mc_now)" -lt "$ae_end" ] || return 1
    sleep 1
    ae_n=$((ae_n + 1))
  done
  return 0
}

# retire_row <name> <kind>: retire a session the launcher registered, setting
# RS_STATE to released, gone, attended (no row to retire) or partial, which
# also raises an item.
retire_row() {
  if [ "$2" != registry ]; then
    RS_STATE=attended
  elif ! row_exists "$1"; then
    RS_STATE=gone
  elif /bin/sh "$script_dir/mission-control-launch.sh" retire "$1" >/dev/null 2>&1 </dev/null; then
    RS_STATE=released
  elif ! row_exists "$1"; then
    RS_STATE=gone
  else
    RS_STATE=partial
    raise handover-retire-failed "$1" "$1 could not be retired; retire it by name"
  fi
}

# succeed <to> <kind> <from|-> <from kind> <expected holder> <wait>: the name
# moves to <to> once <from> has released to it or the window has closed,
# only while the holder is still <expected holder> (empty for none); then
# <from>, and any pending successor the move strands, are retired, and the
# process <from>'s holder record names is waited for. RETIRE_OK is 0 when a
# retirement was only partial or that process still runs.
succeed() {
  s_to=$1 s_kind=$2 s_from=$3 s_from_kind=$4 s_expect=$5
  s_how=none
  if [ "$s_from" != - ]; then
    if wait_release "$s_from" "$s_from_kind" "$s_to" "$6"; then s_how=released; else s_how=retired; fi
  fi
  s_own_start=''
  if [ -n "$own_pid" ]; then
    s_own_start=$(proc_start "$own_pid")
    [ -n "$s_own_start" ] || say "warning: process $own_pid is not running, so the holder record names no process for the next take to confirm"
  fi
  lock
  read_holder
  if [ "$H_SESSION" != "$s_expect" ]; then
    unlock
    say "the program name $program was taken by $H_SESSION during the handover"
    exit 3
  fi
  s_pid='' s_start=''
  if [ "$s_from" != - ] && [ "$H_SESSION" = "$s_from" ] && [ -n "$H_PID" ] && ! is_own "$H_PID"; then
    s_pid=$H_PID s_start=$H_START
  fi
  s_stranded=''
  if [ -f "$SUCC" ] && mc_format_ok "$SUCC"; then
    s_stranded=$(kv_handle "$SUCC" session) || exit 1
    [ "$s_stranded" != "$s_to" ] || s_stranded=''
  fi
  if [ -n "$s_own_start" ]; then
    record "$HOLDER" session "$s_to" kind "$s_kind" since "$NOW" generation $((H_GEN + 1)) \
      pid "$own_pid" pid-start "$s_own_start"
  else
    record "$HOLDER" session "$s_to" kind "$s_kind" since "$NOW" generation $((H_GEN + 1))
  fi
  rm -f "$RELEASED" "$REQUEST" "$SUCC" "$HANDOVER"
  unlock
  printf 'took\t%s\t%s\t%s\n' "$s_to" "$s_from" "$s_how"
  RETIRE_OK=1
  s_from_state='' s_stranded_state=''
  if [ "$s_from" != - ]; then
    retire_row "$s_from" "$s_from_kind"
    s_from_state=$RS_STATE
  fi
  if [ -n "$s_stranded" ]; then
    retire_row "$s_stranded" registry
    s_stranded_state=$RS_STATE
  fi
  if [ -n "$s_from_state" ]; then
    if [ -n "$s_pid" ] && ! await_exit "$s_pid" "$s_start"; then
      printf 'retire\t%s\talive\t%s\n' "$s_from" "$s_pid"
      raise handover-predecessor-alive "$s_from" "$s_from was retired from program $program but still runs (process $s_pid); close that session"
      RETIRE_OK=0
    else
      printf 'retire\t%s\t%s\n' "$s_from" "$s_from_state"
    fi
    [ "$s_from_state" != partial ] || RETIRE_OK=0
  fi
  if [ -n "$s_stranded_state" ]; then
    printf 'retire\t%s\t%s\n' "$s_stranded" "$s_stranded_state"
    [ "$s_stranded_state" != partial ] || RETIRE_OK=0
  fi
}

# announce <successor> <predecessor|->: one event every live session's wake
# carries, and the sessions it reaches.
announce() {
  a_text="mission control for $program is now $1"
  [ "$2" = - ] || a_text="$a_text (was $2)"
  raise mission-control-announce "$1" "$a_text"
  a_list=$(/bin/sh "$script_dir/mission-control-launch.sh" list 2>/dev/null </dev/null) || a_list=''
  printf '%s\n' "$a_list" | P=$program S=$1 F=$2 awk -F '\t' '
    NF >= 2 && $2 == ENVIRON["P"] && $1 != ENVIRON["S"] && $1 != ENVIRON["F"] { printf "announce\t%s\n", $1 }' | mc_clean
  printf 'line\thandover: %s\n' "$a_text"
}

# what_changed <since epoch>: the decisions and events after the operator's
# last turn; a store that cannot be read is said as such, never as none.
what_changed() {
  wc_said=0
  if decisions=$(mc_kb entries --program "$program" decisions 2>/dev/null); then
    decisions=$(printf '%s\n' "$decisions" | T=$(mc_iso "$1") awk -F '\t' '
      NF >= 4 && $2 > ENVIRON["T"] { printf "changed\tdecision\t%s\t%s\t%s\n", $2, $3, $4 }' | mc_clean_text)
  else
    decisions=''
    printf 'changed\tunknown\tdecisions\n'
    wc_said=1
  fi
  if events=$(mc_event list --program "$program" --limit 100000 2>/dev/null); then
    # A read that filled its limit may have dropped the newest events: unknown.
    if [ "$(printf '%s\n' "$events" | awk 'NF { n++ } END { print n + 0 }')" -ge 100000 ]; then
      events=''
      printf 'changed\tunknown\tevents\n'
      wc_said=1
    else
      events=$(printf '%s\n' "$events" | T=$1 awk -F '\t' '
        NF >= 4 && $2 > ENVIRON["T"] { printf "changed\tevent\t%s\t%s\t%s\n", $2, $3, $4 }' | mc_clean)
    fi
  else
    events=''
    printf 'changed\tunknown\tevents\n'
    wc_said=1
  fi
  [ -z "$decisions" ] || printf '%s\n' "$decisions"
  [ -z "$events" ] || printf '%s\n' "$events"
  [ -n "$decisions$events" ] || [ "$wc_said" -eq 1 ] || printf 'changed\tnone\n'
}

# compose_brief <brief> <name> <predecessor>: the successor's brief, into
# $scratch.
compose_brief() {
  cb_note="no handover file: verify against the durable stores (--durable)"
  [ ! -f "$HANDOVER" ] || cb_note="the handover file is $(sanitize_printable "$HANDOVER")"
  {
    cat "$1"
    printf '\n## Succession\n\n'
    printf 'You are %s, the successor for program %s (predecessor %s); %s. ' "$2" "$program" "$3" "$cb_note"
    # shellcheck disable=SC2016 # the backticks are markdown in the brief
    printf 'Rebuild from the durable stores, then run `mc-handover.sh verify --program %s --session %s` with your held picture, rules digest and ledger position, and on a pass `mc-handover.sh take --program %s --session %s`.\n' \
      "$program" "$2" "$program" "$2"
    [ -z "${rc_note:-}" ] || printf '\nRemote Control: %s.\n' "$rc_note"
    # shellcheck disable=SC2016 # the backticks are markdown in the brief
    printf '\nplanwright'"'"'s defaults win over the predecessor'"'"'s habits. Inherit only what the stores record; run `mc-config.sh doctor --program %s`; each finding it prints that no operator choice already settles, and each hand-built mechanism it cannot see, becomes an operator item.\n' \
      "$program"
  } >"$scratch"
}

# end_self: the released session's exit line, from retiring its own panel
# activation of this program for exit (never another program's). When that
# fails, a plain retire still stands its mod down, so the released session
# stops acting as mission control even though nothing ends it.
end_self() {
  es_out=$(/bin/bash "$script_dir/mc-panel.sh" retire --exit --program "$program" 2>/dev/null </dev/null)
  es_rc=$?
  case $es_rc in
    0)
      es_line=$(printf '%s\n' "$es_out" | awk -F '\t' '$1 == "exit" { print; exit }' | mc_clean)
      [ -n "$es_line" ] || es_line=$(printf 'exit\tnone\t%s' "mc-panel.sh printed no exit line")
      printf '%s\n' "$es_line"
      return 0
      ;;
    4)
      printf 'exit\tnone\t%s\n' "this session's id cannot be told"
      return 0
      ;;
  esac
  if /bin/bash "$script_dir/mc-panel.sh" retire >/dev/null 2>&1 </dev/null; then
    printf 'exit\tnone\t%s\n' "the exit marker could not be written; the panel stood down"
  else
    printf 'exit\tnone\t%s\n' "the panel's activation could not be retired"
  fi
}

# --------------------------------------------------------------------------

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift
program='' session='' picture='' digest='' ledger='' durable='' brief='' backend='' cwd=''
window='' now='' kind='' mode='' context='' wakes='' compactions='' pid='' exit_wait=''
while [ $# -gt 0 ]; do
  case $1 in
    --program | --session | --picture | --digest | --ledger | --durable | --brief | --backend | --cwd | --window | --now | --kind | --context | --wakes | --compactions | --pid | --exit-wait)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --session) session=$2 ;;
        --picture) picture=$2 ;;
        --digest) digest=$2 ;;
        --ledger) ledger=$2 ;;
        --durable) durable=$2 ;;
        --brief) brief=$2 ;;
        --backend) backend=$2 ;;
        --cwd) cwd=$2 ;;
        --window) window=$2 ;;
        --now) now=$2 ;;
        --kind) kind=$2 ;;
        --context) context=$2 ;;
        --wakes) wakes=$2 ;;
        --compactions) compactions=$2 ;;
        --pid) pid=$2 ;;
        --exit-wait) exit_wait=$2 ;;
      esac
      shift 2
      ;;
    --handover | --asked)
      [ -z "$mode" ] || usage
      mode=${1#--}
      shift
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
[ -z "$session" ] || mc_valid_handle "$session" || mc_usage_fail "invalid session handle '$(sanitize_printable "$session")'"
[ -z "$digest" ] || valid_sha256 "$digest" || mc_usage_fail "--digest takes a SHA-256 in lowercase hex"
[ -z "$ledger" ] || [ "$ledger" = - ] || mc_valid_entry_id decisions "$ledger" || mc_usage_fail "--ledger takes a decisions-log entry id or -"
[ -z "$window" ] || mc_seconds "$window" >/dev/null || mc_usage_fail "--window takes a cadence (a positive count of s, m, h or d)"
exit_secs=$(mc_seconds "${exit_wait:-$EXIT_WAIT}") || mc_usage_fail "--exit-wait takes a cadence (a positive count of s, m, h or d)"
own_pid=''
if [ -n "$pid" ]; then
  mc_valid_uint "$pid" && [ "$pid" -gt 1 ] || mc_usage_fail "--pid takes a process id"
  own_pid=$pid
elif mc_valid_uint "${CLAUDE_PID:-}" && [ "$CLAUDE_PID" -gt 1 ]; then
  own_pid=$CLAUDE_PID
fi
case $backend in
  '' | stream-json | tmux) ;;
  *) mc_usage_fail "--backend is stream-json or tmux" ;;
esac
case $cwd in
  '' | /*) ;;
  *) mc_usage_fail "--cwd must be an absolute path" ;;
esac
mc_require_program "$program"

case $verb in
  due)
    need wakes "$wakes"
    need compactions "$compactions"
    need context "$context"
    mc_valid_uint "$wakes" || mc_usage_fail "--wakes takes a count"
    mc_valid_uint "$compactions" || mc_usage_fail "--compactions takes a count"
    if [ "$context" != - ] && { ! mc_valid_uint "$context" || [ "$context" -gt 100 ]; }; then
      mc_usage_fail "--context takes a percent from 0 to 100, or -"
    fi
    if k=$(mc_knob mission_control_handover_compactions mc_parse_count) && [ "$compactions" -ge "$k" ]; then
      printf 'due\t%s compactions\n' "$compactions"
    elif [ "$context" != - ]; then
      if k=$(mc_knob mission_control_handover_context parse_pct) && [ "$context" -ge "$k" ]; then
        printf 'due\tcontext at %s%%\n' "$context"
      else
        printf 'not-due\n'
      fi
    elif k=$(mc_knob mission_control_handover_wakes mc_parse_count) && [ "$wakes" -ge "$k" ]; then
      printf 'due\t%s wakes\n' "$wakes"
    else
      printf 'not-due\n'
    fi
    ;;
  holder)
    runtime_paths
    read_holder
    if [ -z "$H_SESSION" ]; then
      printf 'holder\t-\n'
    else
      if [ "$H_LIVE" -eq 1 ]; then st=live; else st=stale; fi
      printf 'holder\t%s\t%s\t%s\t%s\t%s\n' "$H_SESSION" "$H_KIND" "$H_SINCE" "$H_GEN" "$st"
    fi
    ;;
  path | offer)
    runtime_paths
    read_holder
    act="claude '/planwright:mission-control $program'"
    if [ "$verb" = path ]; then
      if [ "$H_KIND" = attended ] && [ "$H_LIVE" -eq 1 ]; then
        if tmux_probe; then printf 'path\tpane\ttmux\n'; else printf 'path\toperator-act\t%s\n' "$act"; fi
      else
        printf 'path\tunattended\n'
      fi
      exit 0
    fi
    id=$(mc_event emit --program "$program" --now "$NOW" -- handover-act "$program" "handover due: $act") \
      || mc_fail "the handover act could not be offered"
    printf 'offered\t%s\n' "$id"
    ;;
  write)
    need session "$session"
    need picture "$picture"
    need digest "$digest"
    check_picture "$picture"
    runtime_paths
    home_path
    read_holder
    [ "$H_SESSION" = "$session" ] || mc_fail "$session does not hold the program name $program (the holder is ${H_SESSION:-nobody})"
    led=$(last_ledger) || exit $?
    (umask 077 && mkdir -p "$HOME_DIR") || mc_fail "cannot create the program home"
    {
      printf 'format\t%s\nprogram\t%s\npredecessor\t%s\nwritten\t%s\nledger\t%s\nrules\t%s\n' \
        "$MC_FORMAT" "$program" "$session" "$NOW" "$led" "$digest"
      awk 'NF == 2 { printf "%s\t%s\n", $1, $2 }' <"$picture"
    } | (umask 077 && mc_write "$HANDOVER") || mc_fail "cannot write the handover file"
    printf 'handover\t%s\t%s\n' "$(sanitize_printable "$HANDOVER")" "$led"
    ;;
  launch)
    need brief "$brief"
    [ -f "$brief" ] && [ -r "$brief" ] && [ -s "$brief" ] || mc_usage_fail "--brief must name a readable, non-empty regular file"
    runtime_paths
    home_path
    lock
    read_holder
    if [ -f "$SUCC" ]; then
      store_check "$SUCC"
      pend=$(kv_handle "$SUCC" session) || exit 1
      pend_owner=$(mc_kv "$SUCC" owner)
      in_flight=0
      if [ "$(mc_kv "$SUCC" verified)" = - ] && mc_valid_uint "$pend_owner" && kill -0 "$pend_owner" 2>/dev/null; then
        in_flight=1
      fi
      if [ "$pend" != "$H_SESSION" ] && { row_exists "$pend" || [ "$in_flight" -eq 1 ]; }; then
        say "a successor, $pend, is already pending for program $program"
        exit 3
      fi
    fi
    pred=- pred_kind=- pred_pane='' pred_tmux=''
    [ -z "$H_SESSION" ] || pred=$H_SESSION pred_kind=$H_KIND
    if [ "$H_LIVE" -eq 1 ]; then
      case $mode in
        asked) ;;
        handover)
          if [ "$H_KIND" = attended ]; then
            if tmux_probe; then
              [ -n "$backend" ] || backend=tmux
              if [ "$backend" = tmux ]; then
                pred_pane=$TMUX_PANE pred_tmux=${TMUX%%,*}
              fi
            else
              say "the holder $H_SESSION is the operator's own session, and no tmux pane is available to open its successor beside it; the handover is the operator act mc-handover.sh path names"
              exit 4
            fi
          fi
          [ -f "$HANDOVER" ] || {
            say "the program name $program is held by $H_SESSION, and no handover file is written"
            exit 3
          }
          store_check "$HANDOVER"
          fp=$(mc_kv "$HANDOVER" predecessor)
          [ "$fp" = "$H_SESSION" ] || {
            say "the program name $program is held by $H_SESSION; the handover file names $(sanitize_printable "$fp"), a predecessor already retired"
            exit 3
          }
          ;;
        *)
          say "the program name $program is held by $H_SESSION; a launch needs the operator's ask or a live handover"
          exit 3
          ;;
      esac
    fi
    # A per-launch nonce keeps a relaunch from reusing the name of a successor
    # that died, which a release to it may still name.
    nonce=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ -n "$nonce" ] || mc_fail "cannot draw a nonce for the successor's name"
    scope="gen-$((H_GEN + 1))-$NOW-$nonce"
    name=$(/bin/sh "$script_dir/mission-control-launch.sh" name --program "$program" --kind mission-control --scope "$scope" </dev/null) \
      || mc_fail "the launcher cannot name the successor"
    # Remote Control for the successor follows
    # mission_control_successor_remote_control: off starts none, on always
    # names the successor as itself, inherit carries what the predecessor's
    # own launch recorded in its argv (a bare flag names the successor as
    # itself). An unreadable predecessor, or a name outside the session-name
    # grammar, carries none and says so. The launcher drops it off the tmux
    # rung.
    rc_name=''
    rc_note=''
    rc_mode=$(mc_knob mission_control_successor_remote_control parse_rc_mode) || rc_mode=off
    case $rc_mode in
      on) rc_name=$name ;;
      inherit)
        rc_state=unreadable
        if [ "$H_LIVE" -eq 1 ]; then rc_state=$(predecessor_remote_control "$H_PID" "$H_START"); fi
        case $rc_state in
          none)
            # The argv cannot show Remote Control turned on in-session, so a
            # none is "no flag", not "no Remote Control": say what that costs.
            rc_note="the predecessor was started without --remote-control; if it turned Remote Control on in-session, $name starts without it, so run /remote-control there"
            ;;
          bare) rc_name=$name ;;
          'named '*)
            rc_name=${rc_state#named }
            /bin/sh "$script_dir/orchestrate-relay.sh" validate-handle stream-json-persistent "$rc_name" 2>/dev/null || {
              rc_name=''
              rc_note="the predecessor's --remote-control name is outside the session-name grammar, so Remote Control is not carried to $name and it starts without Remote Control; run /remote-control there"
            }
            ;;
          *)
            if [ -n "$H_SESSION" ]; then
              rc_name=$name
              rc_note="the predecessor's process cannot be read and it may have had Remote Control, so $name is asked to start it"
            fi
            ;;
        esac
        ;;
    esac
    [ -z "$rc_note" ] || say "remote control: $rc_note"
    # The record is reserved before the launch, so a second launch meets it
    # and the launcher's own lock on the name; a failed launch removes it.
    succ_record "$name" "$pred" "$pred_kind" "$NOW" "${mode:-start}" - "$$" "${pred_pane:--}" "${pred_tmux:--}" "${rc_note:--}"
    unlock
    drop_reservation() {
      lock
      if [ -f "$SUCC" ] && [ "$(mc_kv "$SUCC" owner)" = "$$" ] && [ "$(mc_kv "$SUCC" verified)" = - ]; then rm -f "$SUCC"; fi
      unlock
    }
    scratch=$(mktemp "${TMPDIR:-/tmp}/mc-handover.XXXXXX") || {
      drop_reservation
      mc_fail "cannot compose the successor's brief"
    }
    compose_brief "$brief" "$name" "$pred" || {
      drop_reservation
      mc_fail "cannot compose the successor's brief"
    }
    set -- launch --program "$program" --kind mission-control --scope "$scope" --brief "$scratch"
    [ -z "$backend" ] || set -- "$@" --backend "$backend"
    [ -z "$cwd" ] || set -- "$@" --cwd "$cwd"
    [ -z "$rc_name" ] || set -- "$@" --remote-control "$rc_name"
    lout=$(/bin/sh "$script_dir/mission-control-launch.sh" "$@" </dev/null)
    lrc=$?
    if [ "$lrc" -ne 0 ]; then
      drop_reservation
      say "the launcher did not start the successor (mission-control-launch.sh exit $lrc)"
      case $lrc in 2 | 3) exit "$lrc" ;; esac
      exit 1
    fi
    got=$(printf '%s\n' "$lout" | awk -F '\t' '$1 == "launch" && $2 == "name" { print $3; exit }')
    if [ "$got" != "$name" ]; then
      drop_reservation
      ! mc_valid_handle "$got" || retire_row "$got" registry
      mc_fail "the launcher named the successor '$(sanitize_printable "$got")', not $name"
    fi
    printf 'successor\t%s\n' "$name"
    ;;
  verify)
    need session "$session"
    need picture "$picture"
    need digest "$digest"
    need ledger "$ledger"
    check_picture "$picture"
    runtime_paths
    home_path
    require_successor fail_item
    scratch=$(mktemp "${TMPDIR:-/tmp}/mc-handover.XXXXXX") || mc_fail "cannot stage the durable picture"
    if [ -f "$HANDOVER" ]; then
      why=$(format_refusal "$HANDOVER")
      [ -z "$why" ] || fail_item format "$why"
      [ "$(mc_kv "$HANDOVER" program)" = "$program" ] \
        || fail_item file "the handover file is program $(mc_kv "$HANDOVER" program)'s, not $program's"
      [ "$(mc_kv "$HANDOVER" predecessor)" = "$S_PRED" ] \
        || fail_item file "the handover file names $(mc_kv "$HANDOVER" predecessor), not the predecessor $S_PRED"
      f_rules=$(mc_kv "$HANDOVER" rules)
      f_ledger=$(mc_kv "$HANDOVER" ledger)
      [ "$f_rules" = "$digest" ] || fail_item rules "the successor's rules (digest $digest) are not the predecessor's ($f_rules)"
      [ "$f_ledger" = "$ledger" ] || fail_item ledger "the successor's ledger position $ledger is not the predecessor's last entry $f_ledger"
      awk -F '\t' '$1 == "item" || $1 == "session" { printf "%s %s\n", $1, $2 }' "$HANDOVER" >"$scratch" \
        || fail_item stage "cannot stage the handover file's picture"
    elif [ -n "$durable" ]; then
      check_picture "$durable"
      led=$(last_ledger) || exit $?
      [ "$led" = "$ledger" ] || fail_item ledger "the successor's ledger position $ledger is not the decisions log's last entry $led"
      cat "$durable" >"$scratch" || fail_item stage "cannot stage the durable picture"
    else
      fail_item file "no handover file and no --durable picture to check $session against"
    fi
    selfcheck "$digest" "$picture" "$scratch"
    lock
    require_successor refuse
    succ_record "$session" "$S_PRED" "$S_PRED_KIND" "$(mc_kv "$SUCC" launched)" "$(mc_kv "$SUCC" mode)" "$NOW" - "$S_PANE" "$S_TMUX" "$(mc_kv "$SUCC" remote-control-note)"
    unlock
    printf 'verified\t%s\t%s\n' "$session" "$(printf '%s\n' "$SC_OUT" | head -n 1 | mc_clean)"
    ;;
  release)
    need session "$session"
    runtime_paths
    lock
    read_holder
    [ "$H_SESSION" = "$session" ] || mc_fail "$session does not hold the program name $program (the holder is ${H_SESSION:-nobody})"
    to=''
    if [ -f "$SUCC" ]; then
      store_check "$SUCC"
      cand=$(kv_handle "$SUCC" session) || exit 1
      if [ "$(mc_kv "$SUCC" verified)" != - ] && [ "$(mc_kv "$SUCC" predecessor)" = "$session" ] && row_exists "$cand"; then
        to=$cand
      fi
    fi
    if [ -z "$to" ] && [ -f "$REQUEST" ]; then
      store_check "$REQUEST"
      to=$(kv_handle "$REQUEST" from) || exit 1
    fi
    [ -n "$to" ] || mc_fail "no verified successor and no resume asked for the name: releasing would leave program $program with no holder"
    record "$RELEASED" session "$session" to "$to" at "$NOW"
    unlock
    printf 'released\t%s\t%s\n' "$session" "$to"
    end_self
    ;;
  take)
    need session "$session"
    secs=$(window_seconds) || exit $?
    runtime_paths
    home_path
    require_successor refuse
    [ "$(mc_kv "$SUCC" verified)" != - ] || mc_fail "$session has not passed its self-check against the handover file"
    expect=''
    [ "$S_PRED" = - ] || expect=$S_PRED
    take_note=$(mc_kv "$SUCC" remote-control-note)
    if [ "$S_PRED" != - ] && session_live "$S_PRED" "$S_PRED_KIND" && ! released_to "$S_PRED" "$session"; then
      raise handover-requested "$S_PRED" "$session passed its self-check for program $program; release the name"
    fi
    succeed "$session" registry "$S_PRED" "$S_PRED_KIND" "$expect" "$secs"
    close_pred_pane "$S_PANE" "$S_TMUX"
    announce "$session" "$S_PRED"
    [ -z "$take_note" ] || [ "$take_note" = - ] || printf 'line\tRemote Control: %s\n' "$(printf '%s\n' "$take_note" | mc_clean)"
    [ "$RETIRE_OK" -eq 1 ] || exit 1
    ;;
  resume)
    need session "$session"
    need picture "$picture"
    need digest "$digest"
    need durable "$durable"
    kind=${kind:-attended}
    case $kind in
      attended | registry) ;;
      *) mc_usage_fail "--kind is attended or registry" ;;
    esac
    check_picture "$picture"
    check_picture "$durable"
    secs=$(window_seconds) || exit $?
    runtime_paths
    home_path
    [ "$kind" = attended ] || row_exists "$session" || mc_fail "$session has no registry row, so it cannot resume as a registry session"
    selfcheck "$digest" "$picture" "$durable"
    read_holder
    since=$H_SINCE
    if [ -f "$RUNTIME/presence" ] && mc_format_ok "$RUNTIME/presence"; then
      lp=$(mc_kv "$RUNTIME/presence" last-prompt)
      if mc_valid_uint "$lp"; then since=$lp; fi
    fi
    from=- from_kind=-
    if [ -n "$H_SESSION" ] && [ "$H_SESSION" != "$session" ]; then
      from=$H_SESSION from_kind=$H_KIND
      if [ "$H_LIVE" -eq 1 ]; then
        own_request=$REQUEST
        record "$REQUEST" from "$session" at "$NOW"
        raise handover-requested "$H_SESSION" "the operator resumed mission control for $program in $session; release the name"
      fi
    fi
    succeed "$session" "$kind" "$from" "$from_kind" "$H_SESSION" "$secs"
    own_request=''
    what_changed "${since:-0}"
    announce "$session" "$from"
    [ "$RETIRE_OK" -eq 1 ] || exit 1
    ;;
  *) usage ;;
esac
