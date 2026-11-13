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
for lib in echo-safety.sh mc-lib.sh fleet-pane-vocabulary.sh lock-lib.sh; do
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
  mc-stall.sh answer --program <p> [--now <epoch>] <name> <prompt id>
      (--standing <decision id> | --operator-answer <decision entry id>)
      answer one permission prompt pending in a stream-json session:
      --standing through the tower-comms answer channel
      (scripts/fleet-attention.sh claim), which re-checks that the
      standing decision covers the prompt's command, and only for a
      request that is one plain command; --operator-answer with the
      operator's own recorded answer (scripts/mc-decide.sh note --shape
      answer, subject `<name> prompt <prompt id>`, target allow or deny,
      made after the prompt arrived). Each answer is written to the undo
      ledger, naming what authorized it, before it is delivered. A tmux
      session has no answer channel and is refused: its prompt takes the
      operator's own answer at its pane.

Liveness is positive evidence from the session's rung, through
scripts/fleet-death-evidence.sh, never pane text or elapsed time:
  tmux         the window the launch recorded, which must still carry the
               session's name (a session mission control adopted keeps
               its owner's window name), then the process in its pane
  stream-json  the worker's pid the supervisor records (worker.pid, else
               supervisor.pid); a state directory holding neither pidfile
               is a supervisor that has exited, since it removes both
A session mission control adopted (its row's origin is `adopted`) also
carries the pid of its process; the rung's record, where it has one,
outranks it, and a row with no process behind it is never live.
The states, first match wins:
  dead                   the predicate reports the window or process gone,
                         or a stream-json state directory holds neither
                         pidfile
  prompt-pending         a stream-json worker with a permission prompt
                         pending in its journal (after dead and unknown)
  unknown                no liveness evidence either way (no state
                         directory, an unreadable pidfile, an unreachable
                         or unresponsive tmux server, a window id now naming
                         another window); the reason says whether the pane
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
busy-unchanged (but prompt-pending) emits one event, kind stall-<state>, subject the session name
(scripts/mc-event.sh); a state held across passes emits no second one, and a
relaunch under the same name starts a fresh sample.
A pending prompt instead raises one stall-prompt-pending event per prompt
id, however many passes see it, and one stall-prompt-cleared event once
it is no longer pending, whatever answered it; an open-selector reason
carries the dialog's command.

Output, one line per session, tab separated:
  <name> <kind> <state> <reason> <event id or ->

Exit codes: 0 classified; 1 the registry, a sample or a lock could not be
read or written, an event could not be emitted, the stall-window knob or the
fleet home does not resolve; a scan classifies every other session first;
2 usage, a malformed name or a registry row of an unknown format; 3 the
program is not configured, or no launched row names the session (none, a
launch still in flight, or a row naming another session); answer exits
4 for a refusal (named on stderr), 0 delivered, and 1 for a store, the
undo ledger or the delivery failing.
HELP
}

refuse() {
  printf '%s\n' "$prog: refused: $1" >&2
  exit 4
}

usage() {
  mc_usage_fail "usage: mc-stall.sh classify --program <p> [--now <epoch>] [--pane <file>] <name> | scan --program <p> [--now <epoch>] | answer --program <p> [--now <epoch>] <name> <prompt id> (--standing <id> | --operator-answer <id>)"
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
  R_format='' R_name='' R_state='' R_program='' R_kind='' R_backend='' R_handle='' R_launched='' R_token='' R_origin='' R_process='' R_scope=''
  rr_out=$(awk -F '\t' '
    $1 ~ /^(format|name|state|program|kind|backend|handle|launched|token|origin|process|scope)$/ && !($1 in seen) {
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
      launched) R_launched=$rr_v ;;
      token) R_token=$rr_v ;;
      origin) R_origin=$rr_v ;;
      process) R_process=$rr_v ;;
      scope) R_scope=$rr_v ;;
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

# liveness <name> <backend> <handle>: set L_STATE (dead, alive or unknown)
# and L_REASON.
liveness() {
  L_STATE=unknown L_REASON='no liveness evidence'
  case $2 in
    tmux)
      valid_window "$3" || {
        L_REASON='no window recorded'
        return 0
      }
      case $(death tmux-window "$PROGRAM" "$3") in
        dead)
          L_STATE=dead L_REASON="window $3 gone"
          return 0
          ;;
        unknown)
          L_REASON='tmux server unreachable'
          return 0
          ;;
      esac
      lv_line=$(bounded tmux display-message -p -t "$3" '#{window_name}	#{pane_pid}' 2>/dev/null) || {
        L_REASON="window $3 unreadable"
        return 0
      }
      # A session mission control launched owns its window's name; one it
      # adopted keeps whatever its owner called it.
      if [ "$R_origin" != adopted ] && [ "${lv_line%%	*}" != "$1" ]; then
        L_REASON="window $3 names another window"
        return 0
      fi
      lv_pid=${lv_line#*	}
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
      for lv_f in worker.pid supervisor.pid; do
        if [ -f "$lv_dir/$lv_f" ] && [ ! -L "$lv_dir/$lv_f" ]; then
          lv_pid=$(head -n 1 "$lv_dir/$lv_f" 2>/dev/null) || lv_pid=''
          break
        fi
      done
      if [ -z "$lv_pid" ] && [ -z "$R_process" ]; then
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
  # The rung's own record of the process is current (a recovered worker has a
  # new pid); the pid the registry holds for an adopted session stands in
  # only where the rung records none.
  [ -n "$lv_pid" ] || lv_pid=$R_process
  mc_valid_uint "$lv_pid" && [ "$lv_pid" -gt 0 ] || {
    L_REASON='unreadable pid'
    return 0
  }
  case $(death process "$lv_pid") in
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

# pending_prompts <handle>: set P_LIST to one `<request id> <tool> <command>
# <shape>` line, tab separated, per request the stream-json worker's journal
# still reads pending. The command is a Bash request's own; the shape is
# `plain` only when that command is the whole request (one command line, no
# other input field, no notice about the stored envelope), since a standing
# decision is matched against the command alone. Returns 1 when the worker's
# journal could not be read.
pending_prompts() {
  P_LIST=''
  pp_out=$(bounded /bin/sh "$script_dir/fleet-streamjson.sh" pending "$1" 2>/dev/null </dev/null) || return 1
  P_LIST=$(printf '%s\n' "$pp_out" | awk '
    function flush() {
      if (id == "") return
      if (tool != "Bash" || cmd == "" || lines != 1 || extra || cmd ~ /\t/) { if (cmd ~ /\t/) cmd = ""; shape = "complex" } else shape = "plain"
      print id "\t" tool "\t" cmd "\t" shape
      id = ""
    }
    /^== / { flush(); n = split($0, f, " "); id = f[3]; tool = f[4]; cmd = ""; lines = 0; extra = 0; next }
    /^\| / && id != "" { lines++; if (lines == 1) cmd = substr($0, 3); next }
    id != "" && /^(\+ |-- )/ { extra = 1 }
    END { flush() }')
}

# prompt_command <pane>: the command a permission dialog asks about, the
# first line under its "Bash command" heading, cut to 200 characters.
prompt_command() {
  printf '%s\n' "$1" | awk '
    seen && NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print substr($0, 1, 200); exit }
    /^[ \t]*Bash command[ \t]*$/ { seen = 1 }'
}

# prompt_events <name> <kind> <current list>: one stall-prompt-pending event
# per prompt not seen before and one stall-prompt-cleared per prompt gone,
# the prompts raised so far kept in the session's ledger. The ledger follows
# each event that was emitted, so a failure part way (C_EVENT_FAILED) leaves
# the next pass to retry only what is left.
prompt_events() {
  pe_ledger="$STALL_DIR/prompts.$1"
  pe_old=''
  [ ! -f "$pe_ledger" ] || [ -L "$pe_ledger" ] || pe_old=$(cat "$pe_ledger" 2>/dev/null) || pe_old=''
  pe_cur=$(printf '%s\n' "$3" | awk -F '\t' 'NF { print $1 }')
  pe_keep=$pe_old
  # Fields are cut, not read: a tab is IFS whitespace and would collapse an
  # empty command field into the shape after it.
  while IFS= read -r pe_line; do
    pe_id=$(printf '%s\n' "$pe_line" | cut -f 1)
    [ -n "$pe_id" ] || continue
    pe_tool=$(printf '%s\n' "$pe_line" | cut -f 2)
    pe_cmd=$(printf '%s\n' "$pe_line" | cut -f 3)
    case "
$pe_old
" in
      *"
$pe_id
"*) ;;
      *)
        pe_text=$(sanitize_printable "$2: prompt $pe_id: $pe_tool $pe_cmd")
        pe_text=$(printf '%s' "$pe_text" | cut -c1-400)
        if mc_event emit --program "$PROGRAM" --now "$NOW" -- stall-prompt-pending "$1" "$pe_text" >/dev/null; then
          pe_keep="$pe_keep
$pe_id"
        else
          C_EVENT_FAILED=1
        fi
        ;;
    esac
    [ "$C_EVENT_FAILED" = 0 ] || break
  done <<EOF
$3
EOF
  if [ "$C_EVENT_FAILED" = 0 ]; then
    for pe_id in $pe_old; do
      case "
$pe_cur
" in
        *"
$pe_id
"*) ;;
        *)
          if mc_event emit --program "$PROGRAM" --now "$NOW" -- stall-prompt-cleared "$1" "prompt $pe_id is no longer pending" >/dev/null; then
            pe_keep=$(printf '%s\n' "$pe_keep" | awk -v i="$pe_id" '$0 != i')
          else
            C_EVENT_FAILED=1
            break
          fi
          ;;
      esac
    done
  fi
  printf '%s\n' "$pe_keep" | awk 'NF' | mc_write "$pe_ledger" || C_EVENT_FAILED=1
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
  elif c_cap=$(capture "$R_backend" "$R_handle"); then
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

  liveness "$c_name" "$R_backend" "$R_handle"

  # A stream-json worker's pending prompts come from its journal, each raised
  # as an event once and cleared once when it is no longer pending.
  c_prompts=''
  if [ "$R_backend" = stream-json ] && [ "$L_STATE" = alive ] && pending_prompts "$R_handle"; then
    c_prompts=$P_LIST
    C_EVENT_FAILED=0
    prompt_events "$c_name" "$c_kind" "$c_prompts"
    if [ "$C_EVENT_FAILED" = 1 ]; then
      pw_lock_release "$c_lock" || :
      printf '%s\n' "$prog: a prompt event or the prompt ledger of $c_name could not be written" >&2
      return 1
    fi
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
  elif [ -n "$c_prompts" ]; then
    c_state=prompt-pending
    c_reason=$(printf '%s\n' "$c_prompts" | awk 'NF { n++ } END { printf "%d pending permission prompt(s)", n }')
  elif [ "$c_have_pane" = 0 ]; then
    c_state=live c_reason="$L_REASON, no pane"
  elif [ "$c_kind" = mission-control ] && selection_prompt_present "$c_pane" && ! permission_prompt_present "$c_pane"; then
    c_state=operator-question c_reason='mission control awaiting the operator'
  elif permission_prompt_present "$c_pane"; then
    c_state=open-selector c_reason='waiting on a permission prompt'
    c_cmd=$(prompt_command "$c_pane")
    [ -z "$c_cmd" ] || c_reason="$c_reason: $c_cmd"
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
    working | idle | live | operator-question | prompt-pending) ;;
    *)
      if [ "$c_state" != "$c_prev_state" ]; then
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

PROGRAM='' NOW_RAW='' PANE_FILE='' NAME='' REQ='' STANDING='' OPERATOR_ANSWER=''
[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help)
    help_text
    exit 0
    ;;
  classify | scan | answer) ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --pane | --standing | --operator-answer)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) PROGRAM=$2 ;;
        --now) NOW_RAW=$2 ;;
        --pane)
          [ "$verb" = classify ] || usage
          PANE_FILE=$2
          ;;
        --standing | --operator-answer)
          [ "$verb" = answer ] || usage
          case $2 in
            "" | *[!A-Za-z0-9._-]*) mc_usage_fail "$1 takes a decision id" ;;
          esac
          if [ "$1" = --standing ]; then STANDING=$2; else OPERATOR_ANSWER=$2; fi
          ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ "$verb" = answer ] && [ -n "$NAME" ] && [ -z "$REQ" ]; then
        REQ=$1
        shift
        continue
      fi
      [ "$verb" != scan ] && [ -z "$NAME" ] || usage
      NAME=$1
      shift
      ;;
  esac
done
[ -n "$PROGRAM" ] || usage
[ "$verb" = scan ] || [ -n "$NAME" ] || usage
if [ "$verb" = answer ]; then
  [ -n "$REQ" ] || usage
  case $REQ in
    *[!A-Za-z0-9-]*) mc_usage_fail "invalid prompt id '$(sanitize_printable "$REQ")'" ;;
  esac
  { [ -n "$STANDING" ] && [ -z "$OPERATOR_ANSWER" ]; } || { [ -z "$STANDING" ] && [ -n "$OPERATOR_ANSWER" ]; } || usage
fi
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
  answer)
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
    [ "$R_state" = launched ] || refuse "$NAME is not launched (its row reads $(sanitize_printable "${R_state:-no state}"))"
    [ "$R_backend" = stream-json ] || refuse "$NAME is on the $(sanitize_printable "$R_backend") rung, which has no answer channel; only the operator's own answer reaches its prompt, at its pane (scripts/mc-pane-answer.sh)"
    mc_valid_handle "$R_handle" || refuse "the registry row of $NAME names no usable worker"
    mc_kb entries undo --program "$PROGRAM" >/dev/null 2>&1 || mc_fail "the undo ledger of $PROGRAM cannot be read; nothing was answered"
    pw_lock_acquire "$STALL_DIR/.lock.answer.$NAME" 50 || mc_fail "another answer to $NAME is in flight"
    pending_prompts "$R_handle" || mc_fail "cannot read the pending prompts of $NAME"
    p_line=$(printf '%s\n' "$P_LIST" | REQ=$REQ awk -F '\t' '$1 == ENVIRON["REQ"] { print; exit }')
    [ -n "$p_line" ] || refuse "no prompt $REQ is pending in $NAME"
    p_tool=$(printf '%s\n' "$p_line" | cut -f 2)
    p_cmd=$(printf '%s\n' "$p_line" | cut -f 3)
    p_shape=$(printf '%s\n' "$p_line" | cut -f 4)
    if [ -n "$STANDING" ]; then
      [ "$p_shape" = plain ] || refuse "the request of prompt $REQ is not one plain command (several lines, another input field, or a notice about its stored form), so no standing decision can cover it; only the operator's own answer settles it"
      # The permission-park record is what the channel matches a standing
      # decision against, and it holds the prompt's own command, never one
      # this script composes.
      a_err=$(printf '%s\n' "$p_cmd" | /bin/sh "$script_dir/fleet-attention.sh" permission "$R_handle" "$R_scope" - 2>&1 >/dev/null) \
        || refuse "the answer channel would not record the prompt of $NAME: $(sanitize_printable "$a_err")"
      a_err=$(/bin/sh "$script_dir/fleet-attention.sh" claim "$R_handle" - 'approve in the worker session' --standing "$STANDING" 2>&1 >/dev/null </dev/null)
      a_rc=$?
      if [ "$a_rc" = 3 ]; then
        refuse "the answer channel refused: $(sanitize_printable "$a_err")"
      elif [ "$a_rc" != 0 ]; then
        mc_fail "the answer channel failed (exit $a_rc): $(sanitize_printable "$a_err")"
      fi
      a_verdict=allow a_by="standing decision $STANDING"
    else
      a_entries=$(mc_kb entries decisions --program "$PROGRAM" 2>/dev/null) || mc_fail "cannot read the decisions log of $PROGRAM"
      a_entry=$(printf '%s\n' "$a_entries" | D=$OPERATOR_ANSWER awk -F '\t' '$1 == ENVIRON["D"] { print; exit }')
      [ -n "$a_entry" ] || refuse "decision $OPERATOR_ANSWER is not in the decisions log of $PROGRAM"
      a_check=$(printf '%s\n' "$a_entry" | S="$NAME prompt $REQ" awk -F '\t' "$MC_GROUNDS_AWK"'
        { r = grounds($6) ? G_REASON : ""
          if (r != "answer") print "not the operator'"'"'s answer"
          else if ($3 != ENVIRON["S"]) print "about another prompt"
          else if ($5 != "allow" && $5 != "deny") print "neither allow nor deny"
          else print "ok " $5 }')
      case $a_check in
        "ok "*) a_verdict=${a_check#ok } ;;
        *) refuse "decision $OPERATOR_ANSWER is $a_check" ;;
      esac
      a_at=$(printf '%s\n' "$a_entry" | cut -f 2)
      a_seen=$(awk -F '\t' -v i="$REQ" '$1 == i { print $3; exit }' "$FLEET_HOME/streamjson/$R_handle/journal" 2>/dev/null)
      mc_valid_uint "$a_seen" || refuse "the journal of $NAME holds no readable time for prompt $REQ"
      a_seen_iso=$(mc_iso "$a_seen") || mc_fail "cannot format the prompt's time"
      [[ ! $a_at < $a_seen_iso ]] || refuse "decision $OPERATOR_ANSWER predates prompt $REQ"
      a_by="the operator's answer $OPERATOR_ANSWER"
    fi
    # The entry is written before the answer is delivered, so an answer that
    # lands is always on the ledger; an answer cannot be taken back.
    mc_kb append undo --program "$PROGRAM" --subject "$NAME" --act answer-prompt --target "$NAME" \
      --grounds "$a_verdict prompt $REQ ($(sanitize_printable "$p_tool")); authorized by $a_by" --no-reversal >/dev/null \
      || mc_fail "cannot record the answer on the undo ledger; nothing was delivered"
    if [ "$a_verdict" = allow ]; then a_flag=--allow; else a_flag=--deny; fi
    a_err=$(/bin/sh "$script_dir/fleet-streamjson.sh" answer "$R_handle" "$REQ" "$a_flag" 2>&1 >/dev/null </dev/null) \
      || mc_fail "the $a_verdict could not be delivered to $NAME ($(sanitize_printable "$a_err")); its ledger entry stands"
    printf 'answered\t%s\t%s\t%s\t%s\n' "$NAME" "$REQ" "$a_verdict" "$(sanitize_printable "$a_by")"
    exit 0
    ;;
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
    classify_one "$row"
    exit $?
    ;;
  scan)
    if [ ! -e "$REG" ]; then
      exit 0
    fi
    [ -d "$REG" ] && [ -r "$REG" ] && [ -x "$REG" ] || mc_fail "cannot read the registry $(sanitize_printable "$REG")"
    failed=0
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
