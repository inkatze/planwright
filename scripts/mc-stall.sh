#!/usr/bin/env bash
# mc-stall.sh — liveness and stall states for every session the
# mission-control launcher registers, whatever its kind.
#
# `mc-stall.sh --help` prints the contract: verbs, states, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-stall
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh fleet-pane-vocabulary.sh lock-lib.sh tmux-identity-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$script_dir/fleet-pane-vocabulary.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2
# shellcheck source=scripts/tmux-identity-lib.sh
. "$script_dir/tmux-identity-lib.sh" || exit 2

ROW_FORMAT=1
PANE_LINES=20
TMUX_BOUND=10
FOOTER_LINES=8

help_text() {
  cat <<'HELP'
mc-stall.sh — liveness and stall states for every session the
mission-control launcher (scripts/mission-control-launch.sh) registers, of
any kind.

Usage:
  mc-stall.sh classify --program <p> [--now <epoch>] [--pane <file>] <name>
      classify one registered session. --pane reads the pane text from a
      file instead of capturing the session's tmux window.
  mc-stall.sh scan --program <p> [--now <epoch>]
      classify every launched session the program's registry rows name.
  mc-stall.sh orphans
      list every stream-json process of this user's that nothing can
      reach any more, and every tail -f /dev/null or sleep infinity holder
      init has adopted, whatever fleet home or program started it. Read-only:
      it never signals one, and stopping one is the operator's call.

Liveness is positive evidence from the session's rung, through
scripts/fleet-death-evidence.sh, never pane text or elapsed time:
  tmux         the window the launch recorded, which must still carry the
               session's name and, where the launch recorded it, come from
               the same tmux server, then the process in its pane
  stream-json  the worker's pid the supervisor records (worker.pid, else
               supervisor.pid), counted dead when the start recorded
               beside it no longer matches the process holding that pid;
               a state directory holding neither pidfile
               is a supervisor that has exited, since it removes both
The states, first match wins:
  dead                   the predicate reports the window or process gone,
                         a window recorded with its tmux server now comes
                         from another server or carries another name, its
                         tmux server was lost (below: one tmux-server-lost
                         event, no stall-dead of its own), or a stream-json
                         state directory holds neither pidfile
  unknown                no liveness evidence either way (no state
                         directory, an unreadable pidfile, an unreachable
                         or unresponsive tmux server, a window recorded
                         without its server whose id now names another
                         window); the reason says whether the pane
                         is absent, on its first sample, changing or stable
  open-selector          a dialog or select menu is open in the pane; the
                         reason names a permission prompt as one
  operator-question      a mission control's own dialog that is not a
                         permission prompt, so a question it has put to the
                         operator; it emits no event, since the operator is
                         the one it waits on. Any other session's dialog, and
                         a mission control's permission prompt, stay
                         open-selector. The kind comes from the registry row
  unsubmitted-prompt     the input box holds a staged paste
  turn-ended-background  the main turn ended with background agents running
  idle-question          the session is idle and its last line above the
                         input box is a question
  busy-unchanged         a busy session whose pane, spinner lines aside, has
                         not changed across samples spanning the stall window
                         (mission_control_stall_window)
  working                busy, and the pane changed inside the window
  idle                   at the prompt with no question
  live                   alive, and the pane shows none of the above (or the
                         rung has no pane: a stream-json session)
Elapsed time counts only for busy-unchanged, and only beside a positive busy
marker and a pane unchanged since an earlier sample.

Each pass keeps one sample per session (the launch it belongs to, the pane's
hash, when it last changed or, with no pane, when it entered its state, the
state, when the sample was taken) under the program's runtime
directory, behind a per-session lock. Entering any state from dead to
busy-unchanged emits one event, kind stall-<state>, subject the session name
(scripts/mc-event.sh); a state held across passes emits no second one, and a
relaunch under the same name starts a fresh sample.

A tmux server that is replaced (a crash, a restart) takes every window with
it. When the running server's identity differs from the one tmux rows
recorded, and the window of every such row is gone (absent, or its id now
naming another window), the pass emits a tmux-server-lost event, subject
tmux-server, naming the sessions no earlier event for that server named and
asking for their relaunch (a text past the event store's limit is cut and
points at scan). Every lost session reads dead with no event of its own, and
only the newly named ones carry the event's id; a later replacement of the
server is a new loss. classify makes the same check when the session it
classifies is a tmux one recorded on another server, so classifying one lost
session raises the event for all of them. A session of the replaced server
whose window still carries its name proves no loss, so every session keeps
its own classification; a session launched on the running server, or a row
with no recorded server, is classified as always.

Output, one line per session, tab separated:
  <name> <kind> <state> <reason> <event id or ->

An orphan is a fleet-streamjson.sh supervisor (its `_supervise <worker>
<dir>` argv) whose state directory is gone, whose state directory records
another supervisor, or whose working directory is gone; or a stream-json
`claude -p` naming its worker (`--name`) whose parent is no fleet-streamjson.sh
launch, recover, relaunch or supervisor. Such a worker's row also says whether
the fleet home holds a record of it and whether its working directory is gone.
A supervised worker is named in its supervisor's row instead, and a process
with the supervisor's argv whose parent is that supervisor is one of its own
forks, never listed. A directory that records no supervisor yet
belongs to one starting or exiting, so that alone lists nothing. A holder is
a `tail -f /dev/null` or `sleep infinity` (spelled so, the row prefilter
matching nothing else) that init has adopted: its parent is pid 1, or, where
there is a procfs, a process named systemd, init or launchd. The command or
test that started it is usually gone and nothing will end it, but a service
manager that runs one on purpose is listed too, so the listing says what it
read and leaves the call to the operator. Its worker column reads `-`, and it
is listed by its parent alone, never by its working directory. One whose
parent still runs is its parent's, never listed. orphans prints, tab
separated:
  orphan <pid> <start> <supervisor|claude|holder> <worker> <reason>
where <start>, which tells the process from a later one given the same pid,
is its procfs start tick as t<ticks> (field 22 of /proc/<pid>/stat) where
there is a procfs, else ps's lstart with its spaces turned to dashes. Where
there is a procfs the listing reads it, not ps.

Exit codes: 0 classified, or the orphans listed; 1 the registry, a sample or
a lock could not be read or written, an event could not be emitted, the
stall-window knob or the fleet home does not resolve, the process table
cannot be read; a scan classifies every other session first;
2 usage, a malformed name or a registry row of an unknown format; 3 the
program is not configured, or no launched row names the session (none, a
launch still in flight, or a row naming another session).
HELP
}

usage() {
  mc_usage_fail "usage: mc-stall.sh classify --program <p> [--now <epoch>] [--pane <file>] <name> | scan --program <p> [--now <epoch>] | orphans"
}

valid_name() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    mc-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
}

# valid_window <id>: a tmux window id, @ and digits only, as the launcher
# records it.
valid_window() {
  case $1 in
    @[0-9]*) ;;
    *) return 1 ;;
  esac
  case ${1#@} in
    *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# read_row <row>: set R_<field> from one read of a registry row.
read_row() {
  R_format='' R_name='' R_state='' R_program='' R_kind='' R_backend='' R_handle='' R_server='' R_launched='' R_token=''
  rr_out=$(awk -F '\t' '
    $1 ~ /^(format|name|state|program|kind|backend|handle|server|launched|token)$/ && !($1 in seen) {
      seen[$1] = 1; v = substr($0, length($1) + 2); gsub(/[^[:print:]]/, "", v); print $1 "\t" v
    }' "$1" 2>/dev/null) || return 1
  while IFS='	' read -r rr_k rr_v; do
    case $rr_k in
      format) R_format=$rr_v ;;
      name) R_name=$rr_v ;;
      state) R_state=$rr_v ;;
      program) R_program=$rr_v ;;
      kind) R_kind=$rr_v ;;
      backend) R_backend=$rr_v ;;
      handle) R_handle=$rr_v ;;
      server) R_server=$rr_v ;;
      launched) R_launched=$rr_v ;;
      token) R_token=$rr_v ;;
    esac
  done <<EOF
$rr_out
EOF
}

# bounded <cmd...>: run a tmux-reaching command under a wall-clock bound, so a
# wedged server cannot hold a pass (and a session's lock) open.
bounded() { /bin/sh "$script_dir/bounded-run.sh" "$TMUX_BOUND" "$@"; }

# death <class> <args...>: dead, alive or unknown from the fleet predicate.
death() {
  d_out=$(bounded /bin/sh "$script_dir/fleet-death-evidence.sh" "$@" 2>/dev/null </dev/null)
  case $d_out in
    dead | alive) printf '%s\n' "$d_out" ;;
    *) printf 'unknown\n' ;;
  esac
}

# liveness <name> <backend> <handle> [<server>]: set L_STATE (dead, alive
# or unknown) and L_REASON. A window recorded with the tmux server that
# issued it is gone once that server, its id or its name differ; one
# recorded without its server is live only while it still carries the
# session's name.
liveness() {
  L_STATE=unknown L_REASON='no liveness evidence'
  lv_start=''
  case $2 in
    tmux)
      valid_window "$3" || {
        L_REASON='no window recorded'
        return 0
      }
      lv_pin=''
      if tmux_valid_server "${4:-}" && tmux_valid_name "$1"; then
        lv_pin="$4/$3/$1"
        lv_death=$(death tmux-window "$PROGRAM" "$3" "$4" "$1")
      else
        lv_death=$(death tmux-window "$PROGRAM" "$3")
      fi
      case $lv_death in
        dead)
          L_STATE=dead L_REASON="window $3 gone"
          [ -z "$lv_pin" ] || L_REASON="window $3 gone, or no longer the one its tmux server issued for $1"
          return 0
          ;;
        unknown)
          L_REASON='tmux server unreachable'
          return 0
          ;;
      esac
      # The pane pid first and the window name last: no tab, which tmux
      # prints as `_` under LC_ALL=C, and a name may hold anything.
      lv_line=$(bounded tmux display-message -p -t "$3" "#{pane_pid} $TMUX_SERVER_FORMAT/#{window_id}/#{window_name}" 2>/dev/null) || {
        L_REASON="window $3 unreadable"
        return 0
      }
      lv_pid=${lv_line%% *}
      lv_now=${lv_line#* }
      lv_id=${lv_now#*/}
      lv_name=${lv_id#*/}
      lv_id=${lv_id%%/*}
      if [ "$lv_id" != "$3" ]; then
        L_REASON="window $3 unreadable"
        return 0
      fi
      if [ -n "$lv_pin" ] && [ "$lv_now" != "$lv_pin" ]; then
        L_STATE=dead L_REASON="window $3 is no longer the one its tmux server issued for $1"
        return 0
      fi
      if [ "$lv_name" != "$1" ]; then
        L_REASON="window $3 names another window"
        return 0
      fi
      ;;
    stream-json)
      mc_valid_handle "$3" || {
        L_REASON='no handle recorded'
        return 0
      }
      lv_dir="$FLEET_HOME/streamjson/$3"
      if [ ! -d "$lv_dir" ] || [ -L "$lv_dir" ]; then
        L_REASON='no state directory'
        return 0
      fi
      lv_pid=''
      lv_start=''
      for lv_f in worker.pid supervisor.pid; do
        if [ -f "$lv_dir/$lv_f" ] && [ ! -L "$lv_dir/$lv_f" ]; then
          lv_pid=$(head -n 1 "$lv_dir/$lv_f" 2>/dev/null) || lv_pid=''
          # The start the launch recorded beside the pid; a launch from before
          # it recorded none, and the pid alone is read as it always was.
          lv_sf="$lv_dir/${lv_f%.pid}.start"
          if [ -f "$lv_sf" ] && [ ! -L "$lv_sf" ]; then
            lv_start=$(head -n 1 "$lv_sf" 2>/dev/null) || lv_start=''
          fi
          break
        fi
      done
      if [ -z "$lv_pid" ]; then
        if [ ! -e "$lv_dir/worker.pid" ] && [ ! -L "$lv_dir/worker.pid" ] \
          && [ ! -e "$lv_dir/supervisor.pid" ] && [ ! -L "$lv_dir/supervisor.pid" ]; then
          L_STATE=dead L_REASON='the supervisor removed its pidfiles'
        fi
        return 0
      fi
      ;;
    *)
      L_REASON='unknown backend'
      return 0
      ;;
  esac
  mc_valid_uint "$lv_pid" && [ "$lv_pid" -gt 0 ] || {
    L_REASON='unreadable pid'
    return 0
  }
  case $(death process "$lv_pid" ${lv_start:+"$lv_start"}) in
    dead) L_STATE=dead L_REASON="pid $lv_pid gone" ;;
    alive) L_STATE=alive L_REASON="pid $lv_pid alive" ;;
    *) L_REASON="pid $lv_pid unreadable" ;;
  esac
}

# capture <backend> <handle>: the visible pane of a tmux session.
capture() {
  [ "$1" = tmux ] && valid_window "$2" || return 1
  bounded tmux capture-pane -p -t "$2" 2>/dev/null
}

# trim_pane: the last PANE_LINES lines up to the last non-blank one, so a
# saved capture and a live one read the same.
trim_pane() {
  awk 'NF { last = NR } { l[NR] = $0 } END { for (i = 1; i <= last; i++) print l[i] }' | tail -n "$PANE_LINES"
}

# pane_hash <pane>: the hash of the pane with every line carrying a busy
# marker or spinner word dropped, so a spinner's ticking timer is no change.
pane_hash() {
  pw_words=$(busy_markers && spinner_words)
  printf '%s\n' "$1" | W=$pw_words awk '
    BEGIN { n = split(ENVIRON["W"], w, "\n") }
    { l = tolower($0); for (i = 1; i <= n; i++) if (w[i] != "" && index(l, w[i])) next; print }' | mc_sha256
}

# question_above_input <pane>: the last non-blank line above the input box
# ends in a question mark. The input box is found positively, by its prompt
# glyph, so a pane with no input box carries no question. Glyphs are matched
# as whole strings: under LC_ALL=C a bracket class would match single bytes.
question_above_input() {
  printf '%s\n' "$1" | P="$(input_prompt_prefixes)" B="$(input_box_borders)" awk '
    function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function starts(s, list, n,   i) { for (i = 1; i <= n; i++) if (list[i] != "" && index(s, list[i]) == 1) return 1; return 0 }
    function prompt(s,   i) {
      for (i = 1; i <= np; i++) if (pr[i] != "" && (s == pr[i] || index(s, pr[i] " ") == 1)) return 1
      return 0
    }
    BEGIN { np = split(ENVIRON["P"], pr, "\n"); nb = split(ENVIRON["B"], bo, "\n") }
    { l[NR] = strip($0) }
    END {
      p = 0
      for (i = NR; i > 0; i--) if (prompt(l[i])) { p = i; break }
      if (!p) exit 1
      for (i = p - 1; i > 0; i--) {
        if (l[i] == "" || starts(l[i], bo, nb)) continue
        exit !(l[i] ~ /\?$/)
      }
      exit 1
    }'
}

# server_lost [<server>]: when the running tmux server replaced the one the
# program's tmux rows recorded and every window recorded under a replaced
# server is gone, set LOST_NAMES (one session per line, each line ending in a
# newline) and LOST_NOW (the running server), and emit one tmux-server-lost
# event, its id in LOST_EVENT, naming only the sessions in LOST_NEW: those no
# earlier event for this server named. Anything unproven (no server, an
# unreadable window, a window still carrying its session's name) leaves
# LOST_NAMES empty. <server>, a classified session's own recorded server,
# skips the registry walk when it is the running one. Returns 1 on a store
# failure: LOST_NAMES stays empty when the event was not emitted, so each
# session raises its own death, and is set once it was.
server_lost() {
  LOST_NAMES='' LOST_NEW='' LOST_NOW='' LOST_EVENT=-
  [ -d "$REG" ] || return 0
  sl_now=$(bounded tmux display-message -p "$TMUX_SERVER_FORMAT" 2>/dev/null </dev/null) || return 0
  tmux_valid_server "$sl_now" || return 0
  [ "${1:-}" != "$sl_now" ] || return 0
  sl_names=''
  set +f
  set -- "$REG"/mc-*
  set -f
  for sl_row in "$@"; do
    case ${sl_row##*/} in *.tmp.*) continue ;; esac
    valid_name "${sl_row##*/}" || continue
    row_ok "$sl_row" || continue
    [ "$R_state" = launched ] && [ "$R_backend" = tmux ] && [ "$R_name" = "${sl_row##*/}" ] || continue
    if ! valid_window "$R_handle" || ! tmux_valid_server "$R_server"; then continue; fi
    [ "$R_server" != "$sl_now" ] || continue
    if sl_out=$(bounded tmux display-message -p -t "$R_handle" "$TMUX_SERVER_FORMAT/#{window_id}/#{window_name}" 2>&1 </dev/null); then
      sl_rest=${sl_out#*/}
      # A window still carrying the session's name leaves the loss unproven,
      # whatever its pin now reads.
      if [ "${sl_rest%%/*}" = "$R_handle" ] && [ "${sl_rest#*/}" = "$R_name" ]; then return 0; fi
    else
      case $sl_out in
        *"can't find"*) ;;
        *) return 0 ;;
      esac
    fi
    sl_names="$sl_names$R_name
"
  done
  [ -n "$sl_names" ] || return 0

  sl_lock="$STALL_DIR/.lock.tmux-server"
  sl_file="$STALL_DIR/.tmux-server-lost"
  pw_lock_acquire "$sl_lock" || {
    printf '%s\n' "$prog: cannot take the tmux-server lock" >&2
    return 1
  }
  sl_seen=''
  if [ -f "$sl_file" ] && [ ! -L "$sl_file" ] && [ "$(head -n 1 "$sl_file" 2>/dev/null)" = "$sl_now" ]; then
    sl_seen=$(tail -n +2 "$sl_file" 2>/dev/null) || sl_seen=''
  fi
  sl_new=$(printf '%s' "$sl_names" | S=$sl_seen awk 'BEGIN { n = split(ENVIRON["S"], s, "\n"); for (i = 1; i <= n; i++) seen[s[i]] = 1 } NF && !($0 in seen)')
  if [ -n "$sl_new" ]; then
    [ -n "$NOW_RAW" ] || NOW=$(mc_now)
    sl_list=$(printf '%s\n' "$sl_new" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')
    sl_text="the tmux server was replaced (now $sl_now) and took down the windows of $sl_list; relaunch them"
    # mc-event.sh refuses text over 512 bytes; the program name is in the
    # tail, so the cut is sized from it.
    if [ "${#sl_text}" -gt 512 ]; then
      sl_tail="... (the rest: mc-stall.sh scan --program $PROGRAM); relaunch them"
      sl_text="$(printf '%s' "$sl_text" | cut -c "1-$((512 - ${#sl_tail}))")$sl_tail"
    fi
    LOST_EVENT=$(mc_event emit --program "$PROGRAM" --now "$NOW" -- tmux-server-lost tmux-server "$sl_text") || {
      pw_lock_release "$sl_lock" || :
      LOST_EVENT=-
      printf '%s\n' "$prog: the tmux-server-lost event was not emitted" >&2
      return 1
    }
    if ! printf '%s\n%s%s\n' "$sl_now" "${sl_seen:+$sl_seen
}" "$sl_new" | mc_write "$sl_file"; then
      pw_lock_release "$sl_lock" || :
      printf '%s\n' "$prog: cannot keep the tmux-server-lost record" >&2
      # The event is out, so no session raises its own death beside it.
      LOST_NAMES=$sl_names LOST_NEW=$sl_new LOST_NOW=$sl_now
      return 1
    fi
  fi
  LOST_NAMES=$sl_names LOST_NEW=$sl_new LOST_NOW=$sl_now
  pw_lock_release "$sl_lock"
  if [ "$?" = 2 ]; then
    printf '%s\n' "$prog: cannot release the tmux-server lock" >&2
    return 1
  fi
}

# in_lines <name> <lines>: both sides are wrapped in newlines so a name
# matches a whole line, never a prefix of a longer name.
in_lines() {
  case "
$2
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# classify_one <row-file>: print the session's line, keep its sample, emit
# an event on entering a stall state. Returns 1 on a store failure.
classify_one() {
  c_name=${1##*/}
  read_row "$1" || {
    if [ ! -e "$1" ]; then
      printf '%s\n' "$prog: the registry row $c_name is gone; skipped" >&2
      return 3
    fi
    printf '%s\n' "$prog: cannot read the registry row $c_name" >&2
    return 1
  }
  if [ "$R_name" != "$c_name" ]; then
    printf '%s\n' "$prog: the registry row $c_name names another session or is gone; skipped" >&2
    return 3
  fi
  c_kind=$R_kind
  mc_valid_kebab "$c_kind" || c_kind=-
  # A row relaunched on the running server since the loss was proven is no
  # longer lost.
  c_lost=0
  if in_lines "$c_name" "$LOST_NAMES" && tmux_valid_server "$R_server" && [ "$R_server" != "$LOST_NOW" ]; then
    c_lost=1
  fi
  c_launch="${R_launched:--}:${R_token:--}"
  case $c_launch in
    *[!A-Za-z0-9:.-]*) c_launch=- ;;
  esac

  c_sample="$STALL_DIR/$c_name"
  c_lock="$STALL_DIR/.lock.$c_name"
  pw_lock_acquire "$c_lock" || {
    printf '%s\n' "$prog: cannot take the sample lock for $c_name" >&2
    return 1
  }
  # The pane and the clock are read under the lock, so a pass that waited
  # never decides from a capture older than the sample it replaces.
  [ -n "$NOW_RAW" ] || NOW=$(mc_now)
  c_pane=''
  c_have_pane=0
  if [ -n "$PANE_FILE" ]; then
    c_pane=$(trim_pane <"$PANE_FILE") || {
      printf '%s\n' "$prog: cannot read the pane file" >&2
      pw_lock_release "$c_lock" || :
      return 1
    }
    c_have_pane=1
  elif [ "$c_lost" = 0 ] && c_cap=$(capture "$R_backend" "$R_handle"); then
    c_pane=$(printf '%s\n' "$c_cap" | trim_pane)
    c_have_pane=1
  fi

  c_prev_launch='' c_prev_hash='' c_prev_since='' c_prev_state=''
  if [ -f "$c_sample" ] && [ ! -L "$c_sample" ]; then
    IFS="	" read -r c_prev_launch c_prev_hash c_prev_since c_prev_state _ <"$c_sample" || :
    if [ "$c_prev_launch" != "$c_launch" ] || ! mc_valid_uint "$c_prev_since"; then
      c_prev_hash='' c_prev_state=''
    fi
  fi
  c_hash=-
  c_since=$NOW
  if [ "$c_have_pane" = 1 ]; then
    c_hash=$(pane_hash "$c_pane") || {
      pw_lock_release "$c_lock" || :
      printf '%s\n' "$prog: no SHA-256 tool to sample the pane" >&2
      return 1
    }
    [ "$c_hash" != "$c_prev_hash" ] || c_since=$c_prev_since
  fi

  if [ "$c_lost" = 1 ]; then
    L_STATE=dead L_REASON="tmux server lost: window $R_handle went with server $R_server (now $LOST_NOW)"
  else
    liveness "$c_name" "$R_backend" "$R_handle" "$R_server"
  fi

  c_footer=$(printf '%s\n' "$c_pane" | tail -n "$FOOTER_LINES")
  c_footer_lc=$(printf '%s' "$c_footer" | tr '[:upper:]' '[:lower:]')

  if [ "$L_STATE" = dead ]; then
    c_state=dead c_reason=$L_REASON
  elif [ "$L_STATE" = unknown ]; then
    c_state=unknown
    if [ "$c_have_pane" = 0 ]; then
      c_reason="$L_REASON, no pane"
    elif [ -z "$c_prev_hash" ]; then
      c_reason="$L_REASON, pane-first-sample"
    elif [ "$c_hash" != "$c_prev_hash" ]; then
      c_reason="$L_REASON, pane-changing"
    else
      c_reason="$L_REASON, pane-stable"
    fi
  elif [ "$c_have_pane" = 0 ]; then
    c_state=live c_reason="$L_REASON, no pane"
  elif [ "$c_kind" = mission-control ] && selection_prompt_present "$c_pane" && ! permission_prompt_present "$c_pane"; then
    c_state=operator-question c_reason='mission control awaiting the operator'
  elif permission_prompt_present "$c_pane"; then
    c_state=open-selector c_reason='waiting on a permission prompt'
  elif selection_prompt_present "$c_pane"; then
    c_state=open-selector c_reason='dialog signature in the pane'
  elif staged_paste_present "$c_pane"; then
    c_state=unsubmitted-prompt c_reason='staged paste in the input box'
  else
    c_main_busy=0 c_bg=0
    printf '%s\n' "$(main_turn_markers)" "$(spinner_words)" | contains_any "$c_footer_lc" && c_main_busy=1
    printf '%s\n' "$(background_markers)" | contains_any "$c_footer_lc" && c_bg=1
    c_anchor=0
    printf '%s\n' "$(prompt_anchors)" | contains_any "$c_footer_lc" && c_anchor=1
    if [ "$c_main_busy" = 0 ] && [ "$c_bg" = 1 ]; then
      c_state=turn-ended-background c_reason='background agents running after the turn'
    elif [ "$c_main_busy" = 1 ]; then
      if [ -n "$c_prev_hash" ] && [ "$c_hash" = "$c_prev_hash" ] && [ $((NOW - c_since)) -ge "$STALL_SECONDS" ]; then
        c_state=busy-unchanged c_reason="busy, pane unchanged since $c_since"
      else
        c_state=working c_reason='busy'
      fi
    elif [ "$c_anchor" = 1 ] && question_above_input "$c_pane"; then
      c_state=idle-question c_reason='question above the input box'
    elif [ "$c_anchor" = 1 ]; then
      c_state=idle c_reason='at the prompt'
    else
      c_state=live c_reason="$L_REASON, pane indeterminate"
    fi
  fi

  # With no pane there is no hash to carry the time by: the time the session
  # entered this state is kept while the state holds.
  if [ "$c_have_pane" = 0 ] && [ "$c_state" = "$c_prev_state" ] && mc_valid_uint "$c_prev_since"; then
    c_since=$c_prev_since
  fi

  c_event=-
  case $c_state in
    working | idle | live | operator-question) ;;
    *)
      if [ "$c_lost" = 1 ]; then
        if in_lines "$c_name" "$LOST_NEW"; then c_event=$LOST_EVENT; fi
      elif [ "$c_state" != "$c_prev_state" ]; then
        c_event=$(mc_event emit --program "$PROGRAM" --now "$NOW" -- "stall-$c_state" "$c_name" "$c_kind: $c_reason") || {
          pw_lock_release "$c_lock" || :
          printf '%s\n' "$prog: the stall-$c_state event for $c_name was not emitted" >&2
          return 1
        }
      fi
      ;;
  esac

  if ! printf '%s\t%s\t%s\t%s\t%s\n' "$c_launch" "$c_hash" "$c_since" "$c_state" "$NOW" | mc_write "$c_sample"; then
    pw_lock_release "$c_lock" || :
    printf '%s\n' "$prog: cannot keep the sample for $c_name" >&2
    return 1
  fi
  pw_lock_release "$c_lock"
  if [ "$?" = 2 ]; then
    printf '%s\n' "$prog: cannot release the sample lock for $c_name" >&2
    return 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$c_name" "$c_kind" "$c_state" "$(sanitize_printable "$c_reason")" "$c_event"
}

# row_ok <row>: 0 a readable row of the known format for this program; 1
# not a row; 2 an unknown format; 3 another program's; 4 unreadable.
row_ok() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  read_row "$1" || return 4
  [ "$R_format" = "$ROW_FORMAT" ] || return 2
  [ "$R_program" = "$PROGRAM" ] || return 3
}

# The procfs the listing reads, or nothing where there is none (macOS), when
# ps answers instead. PLANWRIGHT_MC_PROC_ROOT moves it, so a test can stand
# in a host with a table of its own, an empty one included.
resolve_proc_root() {
  if [ -n "${PLANWRIGHT_MC_PROC_ROOT:-}" ]; then
    case $PLANWRIGHT_MC_PROC_ROOT in
      /*) ;;
      *) mc_fail "PLANWRIGHT_MC_PROC_ROOT must be an absolute path" ;;
    esac
    printf '%s\n' "$PLANWRIGHT_MC_PROC_ROOT"
  elif [ -r /proc/self/stat ]; then
    printf '%s\n' /proc
  fi
}

# proc_cwd <pid>: the process's working directory as here:<path>, or
# gone:<path> once it was removed; nothing when it cannot be read.
proc_cwd() {
  if [ -n "${PROC_ROOT:-}" ]; then
    pc_dir=$(readlink "$PROC_ROOT/$1/cwd" 2>/dev/null) || return 0
  elif command -v lsof >/dev/null 2>&1; then
    pc_dir=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
  else
    return 0
  fi
  [ -n "$pc_dir" ] || return 0
  if [ -d "$pc_dir" ]; then
    printf 'here:%s\n' "$pc_dir"
  else
    printf 'gone:%s\n' "${pc_dir% (deleted)}"
  fi
}

# proc_rows: this user's process rows that name the launcher, the
# stream-json shape, /dev/null or infinity (the holder candidates), as
# `<pid> <ppid> <start> <argv...>` with <start> one
# token: from procfs where there is one, since busybox's ps cuts argv short
# and has no start time, each row read with builtins alone, as a busy host
# has many; elsewhere from ps, its lstart joined by dashes. A procfs start is
# the kernel's start tick, written t<ticks>.
proc_rows() {
  if [ -n "${PROC_ROOT:-}" ]; then
    set +f
    pr_hits=$(grep -l -e fleet-streamjson.sh -e stream-json -e /dev/null -e infinity "$PROC_ROOT"/[0-9]*/cmdline 2>/dev/null)
    set -f
    while IFS= read -r pr_f; do
      [ -n "$pr_f" ] || continue
      pr_d=${pr_f%/cmdline}
      [ -O "$pr_d" ] || continue
      IFS= read -r pr_stat 2>/dev/null <"$pr_d/stat" || continue
      # The fields after the command name; the start tick is the 20th.
      # shellcheck disable=SC2086
      set -- ${pr_stat##*") "}
      [ "$#" -ge 20 ] || continue
      pr_ppid=$2
      shift 19
      # One line per row: a control character inside an element would
      # otherwise start a row of its own.
      pr_args=''
      while IFS= read -r -d '' pr_a || [ -n "$pr_a" ]; do
        pr_args="$pr_args ${pr_a//[[:cntrl:]]/ }"
      done 2>/dev/null <"$pr_f"
      [ -n "$pr_args" ] || continue
      printf '%s %s t%s%s\n' "${pr_d##*/}" "$pr_ppid" "$1" "$pr_args"
    done <<EOF
$pr_hits
EOF
    return 0
  fi
  pr_table=$(ps -U "$(id -u)" -ww -o pid= -o ppid= -o lstart= -o args=) || return 1
  printf '%s\n' "$pr_table" | awk 'NF >= 8 {
    s = $3; for (k = 4; k <= 7; k++) s = s "-" $k
    printf "%s %s %s", $1, $2, s; for (k = 8; k <= NF; k++) printf " %s", $k; print ""
  }'
}

# stream_json_procs: this user's candidates from the process table, one per
# line, tab separated: `S <pid> <start> <worker> <dir> <worker pids>` for a
# supervisor, `C <pid> <start> <worker> <ppid>` for a stream-json worker no
# fleet-streamjson.sh launch, recover, relaunch or supervisor parents, and
# `H <pid> <start> - <ppid>` for a holder (tail -f /dev/null, sleep
# infinity), whatever its parent. A
# supervisor's own forks keep its `_supervise` argv for a moment (a
# subshell, the worker before its exec), so a candidate whose parent is a
# supervisor is that supervisor's, never its own row; and `launch
# --foreground` supervises from the launch process.
# The argv arrives joined with spaces, so a state directory whose path holds
# one is read short and reads as gone.
stream_json_procs() {
  sjp_table=$(proc_rows) || return 1
  printf '%s\n' "$sjp_table" | awk '
    function base(s) { sub(/.*\//, "", s); return s }
    NF >= 4 {
      pid = $1; ppid = $2; start = $3
      parent[pid] = ppid
      # A holder: tail -f /dev/null or sleep infinity, run directly or as a
      # script by a shell (a stand-in names its own). hold_cmd in
      # noop-padding-guard.sh refuses the same two commands; keep them in
      # step, bar the spellings of infinity the row prefilter cannot match.
      hi = (base($4) ~ /^(sh|bash|dash|zsh)$/) ? 5 : 4
      if (hi <= NF && base($hi) == "tail") {
        hf = 0; hz = 0; hp = 0
        for (i = hi + 1; i <= NF; i++) {
          if ($i ~ /^--pid(=|$)/) hp = 1
          else if ($i == "--follow" || $i ~ /^--follow=/) hf = 1
          else if ($i !~ /^--/ && $i ~ /^-[A-Za-z]*[fF]/) hf = 1
          if ($i == "/dev/null") hz = 1
        }
        if (hf && hz && !hp) { hold[pid] = start "\t-\t" ppid; horder[++h] = pid }
      } else if (hi <= NF && base($hi) == "sleep" && $(hi + 1) == "infinity" && hi + 1 == NF) {
        hold[pid] = start "\t-\t" ppid; horder[++h] = pid
      }
      for (i = 4; i < NF; i++) if (base($i) == "fleet-streamjson.sh" && $(i + 1) ~ /^(launch|recover|relaunch|_supervise)$/) { fsj[pid] = 1; break }
      for (i = 4; i < NF; i++) {
        if (base($i) == "fleet-streamjson.sh" && $(i + 1) == "_supervise" && i + 3 <= NF) {
          sup[pid] = start "\t" $(i + 2) "\t" $(i + 3); order[++n] = pid
          next
        }
      }
      shape = 0; name = ""
      for (i = 4; i < NF; i++) {
        if (base($i) == "claude" && $(i + 1) == "-p") shape = 1
        if (shape && $i == "--input-format" && $(i + 1) == "stream-json") shape = 2
        if ($i == "--name") name = $(i + 1)
      }
      if (shape == 2 && name != "") { cl[pid] = start "\t" name "\t" ppid; corder[++m] = pid }
    }
    END {
      for (k = 1; k <= m; k++) {
        p = corder[k]; q = parent[p]
        # A shell that forks before it runs a backgrounded command (bash 3.2)
        # leaves a fork of the supervisor between it and its worker.
        for (hop = 0; hop < 8 && (q in sup) && (parent[q] in sup); hop++) q = parent[q]
        if (q in sup) kids[q] = kids[q] (kids[q] == "" ? "" : ",") p
      }
      for (k = 1; k <= n; k++) { p = order[k]; if (!(parent[p] in sup)) print "S\t" p "\t" sup[p] "\t" (kids[p] == "" ? "-" : kids[p]) }
      for (k = 1; k <= m; k++) { p = corder[k]; if (!(parent[p] in fsj)) print "C\t" p "\t" cl[p] }
      for (k = 1; k <= h; k++) { p = horder[k]; print "H\t" p "\t" hold[p] }
    }'
}

# list_orphans: the orphans verb's rows.
list_orphans() {
  lo_procs=$(stream_json_procs) || mc_fail "cannot read the process table (procfs, else ps -U <uid> -ww -o pid= -o ppid= -o lstart= -o args=)"
  while IFS="	" read -r lo_kind lo_pid lo_start lo_worker lo_a lo_b; do
    lo_why=''
    case $lo_kind in
      S)
        lo_rec=''
        if [ ! -d "$lo_a" ]; then
          lo_why="its state directory $lo_a is gone"
        elif [ -f "$lo_a/supervisor.pid" ] && [ ! -L "$lo_a/supervisor.pid" ]; then
          IFS= read -r lo_rec <"$lo_a/supervisor.pid" 2>/dev/null || :
          if mc_valid_uint "$lo_rec" && [ "$lo_rec" != "$lo_pid" ]; then
            lo_why="its state directory $lo_a records supervisor $lo_rec"
          fi
        fi
        ;;
      C)
        lo_why="no supervisor (its parent is pid $lo_a)"
        if ! mc_valid_handle "$lo_worker" || [ ! -d "$FLEET_HOME/streamjson/$lo_worker" ]; then
          lo_why="$lo_why; no fleet record names it under $FLEET_HOME"
        fi
        ;;
      H)
        # Held open by nothing: its command or test is gone and init, or a
        # subreaper acting as it, adopted it. One whose parent still runs
        # belongs to that parent.
        lo_adopter=''
        if [ "$lo_a" = 1 ]; then
          lo_adopter=init
        elif [ -n "${PROC_ROOT:-}" ] && mc_valid_uint "$lo_a" && [ "$lo_a" -gt 1 ]; then
          # The redirect sits inside the group so a parent that is gone says
          # nothing; the row is then skipped until a later pass.
          { IFS= read -r lo_comm <"$PROC_ROOT/$lo_a/comm"; } 2>/dev/null || lo_comm=''
          case $lo_comm in
            systemd | init | launchd) lo_adopter=$lo_comm ;;
          esac
        fi
        [ -n "$lo_adopter" ] || continue
        lo_why="a tail -f /dev/null or sleep infinity holder that nothing owns (adopted by $lo_adopter, pid $lo_a)"
        ;;
      *) continue ;;
    esac
    lo_cwd=''
    [ "$lo_kind" = H ] || lo_cwd=$(proc_cwd "$lo_pid")
    case $lo_cwd in
      gone:*) lo_why="${lo_why:+$lo_why; }its working directory ${lo_cwd#gone:} is gone" ;;
    esac
    [ -n "$lo_why" ] || continue
    [ "$lo_kind" != S ] || [ "$lo_b" = - ] || lo_why="$lo_why; worker pid $(printf '%s' "$lo_b" | sed 's/,/, /g')"
    case $lo_kind in
      S) lo_role=supervisor ;;
      H) lo_role=holder ;;
      *) lo_role=claude ;;
    esac
    printf 'orphan\t%s\t%s\t%s\t%s\t%s\n' "$lo_pid" "$lo_start" "$lo_role" \
      "$(sanitize_printable "$lo_worker")" "$(sanitize_printable "$lo_why")" || return 1
  done <<EOF
$lo_procs
EOF
}

PROGRAM='' NOW_RAW='' PANE_FILE='' NAME='' LOST_NAMES='' LOST_NEW='' LOST_NOW='' LOST_EVENT=-
[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help)
    help_text
    exit 0
    ;;
  classify | scan) ;;
  orphans)
    [ $# -eq 0 ] || usage
    FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
    PROC_ROOT=$(resolve_proc_root) || exit 1
    list_orphans
    exit
    ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --pane)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) PROGRAM=$2 ;;
        --now) NOW_RAW=$2 ;;
        --pane)
          [ "$verb" = classify ] || usage
          PANE_FILE=$2
          ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      [ "$verb" = classify ] && [ -z "$NAME" ] || usage
      NAME=$1
      shift
      ;;
  esac
done
[ -n "$PROGRAM" ] || usage
[ "$verb" = scan ] || [ -n "$NAME" ] || usage
[ -z "$NAME" ] || valid_name "$NAME" || mc_usage_fail "invalid session name '$(sanitize_printable "$NAME")'"
[ -z "$PANE_FILE" ] || { [ -f "$PANE_FILE" ] && [ -r "$PANE_FILE" ]; } || mc_usage_fail "cannot read the pane file $(sanitize_printable "$PANE_FILE")"
mc_now_arg "$NOW_RAW"
mc_require_program "$PROGRAM"

STALL_RAW=$(mc_knob mission_control_stall_window mc_parse_cadence) || exit 1
STALL_SECONDS=$(mc_seconds "$STALL_RAW")
FLEET_HOME=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
REG="$FLEET_HOME/mission-control/sessions"
RUNTIME=$(mc_runtime "$PROGRAM") || mc_fail "cannot create the runtime directory of program $PROGRAM"
STALL_DIR="$RUNTIME/stall"
mkdir -p "$STALL_DIR" 2>/dev/null || mc_fail "cannot create $(sanitize_printable "$STALL_DIR")"
pw_lock_trap_install

case $verb in
  classify)
    row="$REG/$NAME"
    row_ok "$row"
    case $? in
      0) ;;
      2) mc_usage_fail "refusing the registry row $NAME: its format field is $(sanitize_printable "${R_format:-missing}"), not $ROW_FORMAT" ;;
      4) mc_fail "cannot read the registry row $NAME" ;;
      *)
        printf '%s\n' "$prog: no session of program $PROGRAM is registered as $NAME" >&2
        exit 3
        ;;
    esac
    if [ "$R_state" != launched ]; then
      printf '%s\n' "$prog: $NAME is not launched (its row reads $(sanitize_printable "${R_state:-no state}"))" >&2
      exit 3
    fi
    lost_rc=0
    if [ "$R_backend" = tmux ] && tmux_valid_server "$R_server"; then
      server_lost "$R_server" || lost_rc=1
    fi
    classify_one "$row"
    rc=$?
    [ "$rc" != 0 ] || rc=$lost_rc
    exit "$rc"
    ;;
  scan)
    if [ ! -e "$REG" ]; then
      exit 0
    fi
    [ -d "$REG" ] && [ -r "$REG" ] && [ -x "$REG" ] || mc_fail "cannot read the registry $(sanitize_printable "$REG")"
    failed=0
    server_lost || failed=1
    set +f
    set -- "$REG"/mc-*
    set -f
    for row in "$@"; do
      [ -e "$row" ] || continue
      case ${row##*/} in *.tmp.*) continue ;; esac
      valid_name "${row##*/}" || continue
      row_ok "$row"
      case $? in
        0) ;;
        2)
          printf '%s\n' "$prog: skipping the registry row $(sanitize_printable "${row##*/}"): its format field is not $ROW_FORMAT" >&2
          continue
          ;;
        4)
          printf '%s\n' "$prog: cannot read the registry row $(sanitize_printable "${row##*/}")" >&2
          failed=1
          continue
          ;;
        *) continue ;;
      esac
      [ "$R_state" = launched ] || continue
      classify_one "$row"
      [ "$?" != 1 ] || failed=1
    done
    exit "$failed"
    ;;
esac
