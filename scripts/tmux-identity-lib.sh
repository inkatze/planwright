# shellcheck shell=sh disable=SC2034 # TH_*, TP_NOW and TP_WHY are read by the scripts sourcing it
# tmux-identity-lib.sh — a tmux window or pane id names one window only for
# the life of the server that issued it: a restarted server numbers from @0
# and %0 again, so a bare recorded id can name an unrelated window, mission
# control's own included. Every id planwright records is pinned to the server
# that issued it (TMUX_SERVER_FORMAT: its pid and start time) and to the
# window's name, and these helpers read that pin and act only through it.
# Sourced, never executed; POSIX sh.
#
# tmux prints a tab in a format as `_` under LC_ALL=C, which every caller
# sets, so formats here separate fields with `/` and spaces, never tabs.
#
# TID_SOCK, when set, is the socket every call here goes to (tmux -S).

TMUX_SERVER_FORMAT='#{pid}.#{start_time}'

tid_tmux() {
  if [ -n "${TID_SOCK:-}" ]; then
    tmux -S "$TID_SOCK" "$@"
  else
    tmux "$@"
  fi
}

# tmux_valid_server <token>: a server identity as TMUX_SERVER_FORMAT prints it.
tmux_valid_server() {
  case $1 in
    *.*) ;;
    *) return 1 ;;
  esac
  case ${1%%.*}/${1#*.} in
    /* | */ | *[!0-9/]*) return 1 ;;
  esac
  [ "${#1}" -le 40 ]
}

# tmux_valid_name <name>: a window name a pin can carry. The death-handle
# token charset, so it is safe inside a tmux format and a record alike.
tmux_valid_name() {
  case $1 in
    '' | -* | *[!A-Za-z0-9_@%.-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# tmux_server_id: print the running server's identity; 1 when none answers.
tmux_server_id() {
  tsi=$(tid_tmux display-message -p "$TMUX_SERVER_FORMAT" 2>/dev/null </dev/null) || return 1
  tmux_valid_server "$tsi" || return 1
  printf '%s\n' "$tsi"
}

# tmux_handle_parse <rest>: split what follows `tmux-window ` in a death
# handle into TH_SESSION, TH_WINDOW, TH_SERVER and TH_NAME. A handle written
# before the pin carries the first two only, and leaves the others empty;
# any other shape returns 1. The session and window tokens are the caller's
# to validate.
tmux_handle_parse() {
  TH_SESSION='' TH_WINDOW='' TH_SERVER='' TH_NAME=''
  thp=$1
  TH_SESSION=${thp%% *}
  [ "$TH_SESSION" != "$thp" ] && [ -n "$TH_SESSION" ] || return 1
  thp=${thp#* }
  TH_WINDOW=${thp%% *}
  [ -n "$TH_WINDOW" ] || return 1
  [ "$TH_WINDOW" != "$thp" ] || return 0
  thp=${thp#* }
  TH_SERVER=${thp%% *}
  [ "$TH_SERVER" != "$thp" ] || return 1
  TH_NAME=${thp#* }
  case $TH_NAME in *' '*) return 1 ;; esac
  tmux_valid_server "$TH_SERVER" && tmux_valid_name "$TH_NAME"
}

# tmux_pin_read <window|pane> <target>: set TP_NOW to
# <server>/<id>/<window name> as the server sees the target now. 0 found; 1
# gone (no server, or the id names nothing); 2 tmux did not answer.
tmux_pin_read() {
  case $1 in
    window) tpr_f='#{window_id}' ;;
    pane) tpr_f='#{pane_id}' ;;
    *) return 2 ;;
  esac
  TP_NOW=''
  if ! tpr_out=$(tid_tmux display-message -p -t "$2" "$TMUX_SERVER_FORMAT/$tpr_f/#{window_name}" 2>&1 </dev/null); then
    case $tpr_out in
      *'no server running'* | *'error connecting to'*'No such file or directory'* | *"can't find"*) return 1 ;;
    esac
    return 2
  fi
  tpr_rest=${tpr_out#*/}
  # display-message answers for another target when this one is gone.
  [ "${tpr_rest%%/*}" = "$2" ] || return 1
  tmux_valid_server "${tpr_out%%/*}" || return 2
  TP_NOW=$tpr_out
}

# tmux_pin_close <window|pane> <target> <server> <name>: close the target
# only while the running server, the id and its window name all match the
# pin, the match checked by tmux itself in the command that closes, so a
# server restarted in between is never acted on. TP_WHY says why nothing was
# done. 0 closed; 1 not a target (a mismatch, or no pin recorded), and
# nothing was done to tmux; 2 unknown, left as it is; 3 already gone.
tmux_pin_close() {
  TP_WHY=''
  if ! tmux_valid_server "$3" || ! tmux_valid_name "$4"; then
    TP_WHY="not closing $2: it was recorded without its tmux server, so its id may name another window now"
    return 1
  fi
  case $1 in
    window) tpc_c=kill-window tpc_f='#{window_id}' ;;
    pane) tpc_c=kill-pane tpc_f='#{pane_id}' ;;
    *) return 2 ;;
  esac
  tpc_rc=0
  tmux_pin_read "$1" "$2" || tpc_rc=$?
  case $tpc_rc in
    1) return 3 ;;
    2)
      TP_WHY="not closing $2: tmux did not answer for it"
      return 2
      ;;
  esac
  tpc_name=${TP_NOW#*/}
  tpc_name=${tpc_name#*/}
  if [ "${TP_NOW%%/*}" != "$3" ]; then
    TP_WHY="not closing $2: that id now belongs to a tmux server started after it was recorded"
    return 1
  fi
  if [ "$tpc_name" != "$4" ]; then
    TP_WHY="not closing $2: its window is no longer named $4"
    return 1
  fi
  tid_tmux if-shell -F -t "$2" "#{==:$TMUX_SERVER_FORMAT/$tpc_f/#{window_name},$3/$2/$4}" "$tpc_c -t $2" >/dev/null 2>&1 </dev/null || :
  tpc_rc=0
  tmux_pin_read "$1" "$2" || tpc_rc=$?
  case $tpc_rc in
    1) return 0 ;;
    0)
      if [ "$TP_NOW" = "$3/$2/$4" ]; then
        TP_WHY="$2 did not close"
        return 2
      fi
      TP_WHY="not closing $2: it changed while it was being closed"
      return 1
      ;;
  esac
  TP_WHY="tmux did not answer for $2 after closing it"
  return 2
}
