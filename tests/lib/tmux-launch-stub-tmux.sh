#!/bin/sh
# tmux-launch-stub-tmux.sh — the stub `tmux` of the launch fixture harness
# (tests/lib/tmux-launch-harness.sh installs a `tmux` shim that execs this with
# the stub state directory as its first argument). Never run directly.
#
# It models the one property the launch fixtures depend on: a session's command
# runs with the stub SERVER's environment (the KEY=VALUE lines of
# <state>/server.env, under `env -i`, then any `-e` values, then TMUX and
# TMUX_PANE), never the calling client's. A launch that applies its
# environment outside the session therefore loses it here, exactly as it does
# under a real server.
#
# Parsing follows tmux 3.6: a word ending in `;` ends a command (the `;` is
# dropped), `\;` at a word's end is a literal `;`, an unknown command refuses
# the whole invocation before anything runs, and a failing command stops the
# rest.
#
# Behaviour, per command:
#   new-session  flags given separately (-d -P -A -D -E -X; -s -c -F -n -x -y
#                -t -e -f take a value; -e applies KEY=VALUE to the session,
#                the rest are accepted and ignored, so -A never attaches).
#                Values are NOT format-expanded: a fixture checking a charset
#                refusal asserts that no call arrived at all. The name is
#                rewritten `.`/`:` to `_`; a live session holding it is
#                refused `duplicate session: <name>`; an unnamed session takes
#                the next session number, as tmux names it. A name holding
#                `/`, whitespace, or a glob character is refused as not
#                modelled. A `-c` that is not a directory silently starts in
#                the server's HOME. One command word runs as `/bin/sh -c
#                <word>`, several are executed directly, as tmux does. The
#                command runs in the background with fds 0-9 closed or
#                redirected. `-P` prints the `-F` format (default
#                `#{session_name}:`) expanding session_name, session_id,
#                window_id, pane_id, pane_pid, and pane_current_path, which is
#                the -c value as given: tmux reports the path before the
#                pane's chdir. Any other `#{...}` key expands to nothing.
#   set-option   `remain-on-exit` is honoured, per session (-t, or the session
#                this invocation created) or globally (-g); other options are
#                accepted and ignored.
#   has-session / kill-session / kill-server / list-sessions / list-panes /
#   capture-pane against live sessions. A session whose command has exited is
#                gone unless remain-on-exit is on for it; the session this
#                invocation created stays live for the commands chained after
#                it until one kills it. A target without `=` matches exactly,
#                then by unique prefix; capture-pane refuses a bare
#                `=<session>` pane target, as tmux 3.6 does. Killing a session
#                sends its command SIGHUP, as closing its pty does. With no
#                live session left the server has exited, and every command
#                but new-session and start-server answers `no server
#                running`. Liveness reads the pid alone; only the harness's
#                reaper, which signals, checks a pid's start time.
#   list-panes   one line per pane (-t <session>, -a, or every session),
#                expanding its -F format (default `#{pane_id}`) with the keys
#                -P knows, pane_current_path being the physical directory the
#                pane started in.
#   display-message -p  prints its message expanded against the -t session
#                or, with none, the newest session; client variables, having
#                no client, expand to nothing.
#   new-window   refused as not modelled.
#   others tmux knows (switch-client, attach-session, send-keys, ...) are
#                recorded and answered 0.
#
# Knobs (one-line files under <state>/knobs/, written by tlh_knob):
#   new-session     ok (default) | fail | duplicate | block — block creates
#                   the session and then never returns, a launch that waits on
#                   its worker
#   server          up (default) | none | unreachable — none answers every
#                   command but new-session `no server running`; unreachable
#                   refuses every command, new-session included
#   remain-on-exit  off (default) | on — the operator's global option, which a
#                   session's own set-option overrides
#
# Every invocation's argv lands in its own file, <state>/calls/<seq>, written
# to a private temp name and renamed, so concurrent calls never interleave.
# Every session command, and a blocking stub itself, is recorded under
# <state>/pids/ for the harness's reaper.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

STUB_STATE=$1
shift
# shellcheck source=tests/lib/tmux-launch-stub-common.sh
. "${0%/*}/tmux-launch-stub-common.sh"

# The internal command separator. A command word that is a lone newline
# would be read as one, which no launch passes.
SEP='
'
SOCKET="$STUB_STATE/socket"
CUR_DIR=''
CUR_NAME=''

record_call() {
  stub_claim_seq call || {
    echo "stub tmux: cannot claim a call sequence number under $STUB_STATE" >&2
    exit 70
  }
  rcall_line=''
  rcall_first=1
  for rcall_a in "$@"; do
    if [ "$rcall_first" = 1 ]; then
      rcall_line=$rcall_a
      rcall_first=0
    else
      rcall_line="$rcall_line${STUB_TAB}$rcall_a"
    fi
  done
  stub_write_file "$STUB_STATE/calls/$STUB_SEQ" "$rcall_line$SEP"
}

server_home() {
  shome=$(sed -n 's/^HOME=//p' "$STUB_STATE/server.env" 2>/dev/null | head -n 1)
  printf '%s\n' "${shome:-/}"
}

# A session is a symlink sessions/<name> -> ../sdata/<seq>, the directory that
# holds its state files. Creating the link is the exclusive claim on the name.

# remain_of <session dir> — set STUB_REMAIN to the session's remain-on-exit.
remain_of() {
  if [ -r "$1/remain" ]; then
    IFS= read -r STUB_REMAIN <"$1/remain" || true
  else
    stub_knob remain-on-exit off
    STUB_REMAIN=$STUB_KNOB
  fi
}

# dir_live <session dir> — 0 while the session exists: its command runs, or
# its pane is dead under remain-on-exit, or its creator is still starting it.
dir_live() {
  [ -e "$1/killed" ] && return 1
  dl_p=''
  if [ -r "$1/pid" ]; then
    IFS= read -r dl_p <"$1/pid" || true
  fi
  if [ -n "$dl_p" ]; then
    kill -0 "$dl_p" 2>/dev/null && return 0
    remain_of "$1"
    [ "$STUB_REMAIN" = on ]
    return
  fi
  [ -r "$1/creator" ] || return 1
  IFS= read -r dl_c <"$1/creator" || true
  kill -0 "$dl_c" 2>/dev/null
}

# cur_session_live — 0 while this invocation's own new session stands: it is
# live for the commands chained after it until one of them kills it.
cur_session_live() {
  [ -n "$CUR_NAME" ] && [ ! -e "$CUR_DIR/killed" ]
}

session_live() {
  [ -L "$STUB_STATE/sessions/$1" ] || return 1
  cur_session_live && [ "$1" = "$CUR_NAME" ] && return 0
  dir_live "$STUB_STATE/sessions/$1"
}

live_sessions() {
  for ls_l in "$STUB_STATE"/sessions/*; do
    [ -L "$ls_l" ] || continue
    ls_n=${ls_l##*/}
    case $ls_n in *'#break#'*) continue ;; esac
    dir_live "$ls_l" && printf '%s\n' "$ls_n"
  done
  return 0
}

any_live_session() {
  for al_l in "$STUB_STATE"/sessions/*; do
    [ -L "$al_l" ] || continue
    case ${al_l##*/} in *'#break#'*) continue ;; esac
    dir_live "$al_l" && return 0
  done
  return 1
}

# A name is also a file name and a word in an unquoted list here, so the names
# that would leave sessions/, collide with a break claim, or split or glob are
# refused rather than modelled.
name_ok() {
  case $1 in
    '' | . | .. | */* | *'#break#'* | *' '* | *"$STUB_TAB"* | *"$SEP"* | *'*'* | *'?'* | *'['*) return 1 ;;
  esac
  return 0
}

# claim_name <name> <seq> — take the name for session <seq>. A stale holder
# (its session gone) is broken through a claim on `<name>#break#<old seq>`, so
# two creators racing over one stale name cannot both win it.
claim_name() {
  cn_link="$STUB_STATE/sessions/$1"
  cn_target="../sdata/$2"
  ln -sn "$cn_target" "$cn_link" 2>/dev/null && return 0
  cn_old=$(readlink "$cn_link" 2>/dev/null) || {
    ln -sn "$cn_target" "$cn_link" 2>/dev/null
    return
  }
  cn_oseq=${cn_old##*/}
  dir_live "$STUB_STATE/sdata/$cn_oseq" && return 1
  ln -sn "$cn_target" "$cn_link#break#$cn_oseq" 2>/dev/null || return 1
  [ "$(readlink "$cn_link" 2>/dev/null)" = "$cn_old" ] || return 1
  rm -f "$cn_link"
  ln -sn "$cn_target" "$cn_link" 2>/dev/null
}

# resolve_target <target> — set RT_NAME to the live session it names, or fail.
resolve_target() {
  rt_t=$1
  rt_exact=0
  case $rt_t in =*) rt_exact=1 rt_t=${rt_t#=} ;; esac
  rt_t=${rt_t%%:*}
  name_ok "$rt_t" || return 1
  if session_live "$rt_t"; then
    RT_NAME=$rt_t
    return 0
  fi
  [ "$rt_exact" = 1 ] && return 1
  RT_NAME=''
  for rt_n in $(live_sessions); do
    case $rt_n in
      "$rt_t"*)
        [ -n "$RT_NAME" ] && return 1
        RT_NAME=$rt_n
        ;;
    esac
  done
  [ -n "$RT_NAME" ]
}

server_gate() {
  stub_knob server up
  case $STUB_KNOB in
    none)
      echo "no server running on $SOCKET" >&2
      return 1
      ;;
    unreachable)
      echo "error connecting to $SOCKET (Permission denied)" >&2
      return 1
      ;;
  esac
  cur_session_live && return 0
  any_live_session && return 0
  echo "no server running on $SOCKET" >&2
  return 1
}

# expand_format <fmt> — expands against one session's ns_* variables (the one
# cmd_new_session just made, or one load_session_vars read).
expand_format() {
  ef_s=$1
  ef_out=''
  ef_open='#{'
  ef_close='}'
  while :; do
    case $ef_s in
      *"$ef_open"*)
        ef_pre=${ef_s%%"$ef_open"*}
        ef_rest=${ef_s#*"$ef_open"}
        ef_key=${ef_rest%%"$ef_close"*}
        ef_s=${ef_rest#*"$ef_close"}
        ef_v=''
        case $ef_key in
          session_name) ef_v=$ns_name ;;
          session_id) [ -n "$ns_num" ] && ef_v="\$$ns_num" ;;
          window_id) [ -n "$ns_num" ] && ef_v="@$ns_num" ;;
          pane_id) [ -n "$ns_num" ] && ef_v="%$ns_num" ;;
          pane_pid) ef_v=$ns_pid ;;
          pane_current_path) ef_v=$ns_dir ;;
        esac
        ef_out=$ef_out$ef_pre$ef_v
        ;;
      *)
        ef_out=$ef_out$ef_s
        break
        ;;
    esac
  done
  printf '%s\n' "$ef_out"
}

# tmux_name <name> — set STORED_NAME to the name as tmux stores it.
tmux_name() {
  STORED_NAME=$1
  while :; do
    case $STORED_NAME in
      *.*) STORED_NAME="${STORED_NAME%%.*}_${STORED_NAME#*.}" ;;
      *:*) STORED_NAME="${STORED_NAME%%:*}_${STORED_NAME#*:}" ;;
      *) return 0 ;;
    esac
  done
}

# load_session_vars <name> — set the ns_* variables expand_format reads from
# a live session's state files.
load_session_vars() {
  lsv_d="$STUB_STATE/sessions/$1"
  ns_name=$1 ns_num='' ns_pid='' ns_dir=''
  [ -r "$lsv_d/num" ] && { IFS= read -r ns_num <"$lsv_d/num" || true; }
  [ -r "$lsv_d/pid" ] && { IFS= read -r ns_pid <"$lsv_d/pid" || true; }
  [ -r "$lsv_d/pcwd" ] && { IFS= read -r ns_dir <"$lsv_d/pcwd" || true; }
  return 0
}

# latest_session — set RT_NAME to the most recently created live session, the
# one tmux falls back to with no client and no target.
latest_session() {
  RT_NAME=''
  ls_best=-1
  for ls_n in $(live_sessions); do
    ls_num=-1
    [ -r "$STUB_STATE/sessions/$ls_n/num" ] && { IFS= read -r ls_num <"$STUB_STATE/sessions/$ls_n/num" || true; }
    if [ "${ls_num:--1}" -gt "$ls_best" ]; then
      ls_best=$ls_num
      RT_NAME=$ls_n
    fi
  done
  [ -n "$RT_NAME" ]
}

# claim_number — set ns_num to the next session number, from 0.
claim_number() {
  stub_claim_seq sessnum || return 1
  ns_num=$((${STUB_SEQ#"${STUB_SEQ%%[!0]*}"} - 1))
}

need_value() {
  [ "$1" -ge 2 ] && return 0
  echo "stub tmux: $2 needs a value" >&2
  return 1
}

cmd_new_session() {
  ns_name='' ns_dir='' ns_fmt='#{session_name}:' ns_print=0 ns_env=''
  while [ $# -gt 0 ]; do
    case $1 in
      --)
        shift
        break
        ;;
      -d | -A | -D | -E | -X) shift ;;
      -P)
        ns_print=1
        shift
        ;;
      -s | -c | -F | -n | -x | -y | -t | -e | -f)
        need_value "$#" "$1" || return 1
        case $1 in
          -s) ns_name=$2 ;;
          -c) ns_dir=$2 ;;
          -F) ns_fmt=$2 ;;
          -e)
            ns_key=${2%%=*}
            case $2 in *=*) ;; *) ns_key='' ;; esac
            case $2 in *"$SEP"*) ns_key='' ;; esac
            case $ns_key in
              '' | [0-9]* | *[!A-Za-z0-9_]*)
                echo "invalid environment: $2" >&2
                return 1
                ;;
            esac
            ns_env=$ns_env$2$SEP
            ;;
        esac
        shift 2
        ;;
      -*)
        echo "unknown flag $1" >&2
        return 1
        ;;
      *) break ;;
    esac
  done
  stub_knob server up
  if [ "$STUB_KNOB" = unreachable ]; then
    server_gate
    return 1
  fi
  tmux_name "$ns_name"
  ns_name=$STORED_NAME
  stub_knob new-session ok
  ns_mode=$STUB_KNOB
  case $ns_mode in
    fail)
      echo "create session failed: stubbed failure" >&2
      return 1
      ;;
    duplicate)
      echo "duplicate session: $ns_name" >&2
      return 1
      ;;
  esac
  name_ok "${ns_name:-0}" || {
    echo "stub tmux: session name '$ns_name' is not modelled" >&2
    return 1
  }
  stub_claim_seq session || return 1
  ns_seq=$STUB_SEQ
  ns_sd="$STUB_STATE/sdata/$ns_seq"
  mkdir -p "$ns_sd" || return 1
  stub_write_file "$ns_sd/creator" "$$$SEP" || return 1
  stub_write_file "$ns_sd/env" "$ns_env" || return 1
  ns_start=${ns_dir:-$(pwd)}
  [ -d "$ns_start" ] || ns_start=$(server_home)
  stub_write_file "$ns_sd/pcwd" "$(cd "$ns_start" && pwd -P)$SEP" || return 1
  # tmux numbers only the sessions it creates, so a named create takes its
  # number once the name is won; an unnamed one takes numbers as its name
  # until one is free, as tmux skips a number a named session holds.
  ns_num=''
  if [ -z "$ns_name" ]; then
    ns_try=0
    while :; do
      claim_number || return 1
      claim_name "$ns_num" "$ns_seq" && break
      ns_try=$((ns_try + 1))
      [ "$ns_try" -lt 100 ] || {
        echo "stub tmux: no free session number" >&2
        return 1
      }
    done
    ns_name=$ns_num
  else
    if ! claim_name "$ns_name" "$ns_seq"; then
      echo "duplicate session: $ns_name" >&2
      return 1
    fi
    claim_number || return 1
  fi
  stub_write_file "$ns_sd/num" "$ns_num$SEP" || return 1
  CUR_DIR=$ns_sd
  CUR_NAME=$ns_name
  [ $# -gt 0 ] || set -- sleep 600
  [ $# -eq 1 ] && set -- /bin/sh -c "$1"
  # The session command records itself before it runs, so a stub killed
  # after the fork still leaves its child reapable, and a child that cannot
  # record itself (its sandbox already gone) never runs.
  (
    STUB_WRITER=$(sh -c 'echo "$PPID"')
    stub_record_pid "$STUB_WRITER" || exit 1
    stub_write_file "$ns_sd/pid" "$STUB_WRITER$SEP" || exit 1
    [ -e "$ns_sd/killed" ] && exit 0
    cd "$ns_start" 2>/dev/null || exit 1
    exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
    # Rebuild argv as `KEY=VALUE... command words` for env -i: the command
    # words are rotated behind the assignments, sh having no arrays.
    ns_ncmd=$#
    while IFS= read -r ns_kv; do
      [ -n "$ns_kv" ] && set -- "$@" "$ns_kv"
    done <"$STUB_STATE/server.env"
    while IFS= read -r ns_kv; do
      [ -n "$ns_kv" ] && set -- "$@" "$ns_kv"
    done <"$ns_sd/env"
    set -- "$@" "TMUX=$SOCKET,$$,0" "TMUX_PANE=%$ns_num"
    ns_i=0
    while [ "$ns_i" -lt "$ns_ncmd" ]; do
      set -- "$@" "$1"
      shift
      ns_i=$((ns_i + 1))
    done
    exec env -i "$@"
  ) </dev/null >"$ns_sd/out" 2>&1 &
  ns_pid=$!
  # Written here too, so the session reads live the moment this returns.
  stub_write_file "$ns_sd/pid" "$ns_pid$SEP" || return 1
  if [ "$ns_mode" = block ]; then
    stub_record_pid "$$"
    exec sleep 600
  fi
  [ "$ns_print" = 1 ] && expand_format "$ns_fmt"
  return 0
}

# target_arg <args...> — set TARGET to the -t value, empty when none.
target_arg() {
  TARGET=''
  while [ $# -gt 0 ]; do
    case $1 in
      -t)
        need_value "$#" -t || return 1
        TARGET=$2
        shift 2
        ;;
      *) shift ;;
    esac
  done
  return 0
}

# pane_target <target> — resolve a pane target; tmux 3.6 refuses a bare
# `=<session>` there and needs `=<session>:`.
pane_target() {
  case $1 in
    =*:*) ;;
    =*)
      echo "can't find pane: ${1#=}" >&2
      return 1
      ;;
  esac
  resolve_target "$1" && return 0
  echo "can't find pane: ${1#=}" >&2
  return 1
}

# kill_dir <session dir> — mark the session killed and end its command,
# waiting briefly for a creator still starting it to record the pid.
kill_dir() {
  kd_t=0
  while [ ! -r "$1/pid" ] && [ "$kd_t" -lt 20 ] && dir_live "$1"; do
    sleep 0.1
    kd_t=$((kd_t + 1))
  done
  : >"$1/killed"
  kd_p=''
  if [ -r "$1/pid" ]; then
    IFS= read -r kd_p <"$1/pid" || true
  fi
  [ -n "$kd_p" ] && kill -0 "$kd_p" 2>/dev/null && stub_kill_tree HUP "$kd_p"
  return 0
}

cmd_set_option() {
  so_global=0 so_t=''
  while [ $# -gt 0 ]; do
    case $1 in
      -g)
        so_global=1
        shift
        ;;
      -t)
        need_value "$#" -t || return 1
        so_t=$2
        shift 2
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "${1:-}" = remain-on-exit ] || return 0
  so_v=${2:-on}
  if [ "$so_global" = 1 ]; then
    stub_write_file "$STUB_STATE/knobs/remain-on-exit" "$so_v$SEP"
    return
  fi
  if [ -n "$so_t" ]; then
    resolve_target "$so_t" || {
      echo "can't find session: ${so_t#=}" >&2
      return 1
    }
    so_dir="$STUB_STATE/sessions/$RT_NAME"
  else
    so_dir=$CUR_DIR
  fi
  [ -n "$so_dir" ] || {
    echo "no current session" >&2
    return 1
  }
  stub_write_file "$so_dir/remain" "$so_v$SEP"
}

known_command() {
  case $1 in
    new-session | new | has-session | has | kill-session | kill-server | \
      list-sessions | ls | display-message | display | set-option | set | \
      set-window-option | setw | capture-pane | capturep | send-keys | send | \
      switch-client | switchc | attach-session | attach | a | list-panes | \
      list-windows | select-pane | load-buffer | paste-buffer | set-buffer | \
      delete-buffer | show-options | show | show-environment | \
      set-environment | setenv | rename-session | start-server | start | \
      new-window | neww) return 0 ;;
  esac
  return 1
}

run_one() {
  [ $# -gt 0 ] || return 0
  ro_cmd=$1
  shift
  case $ro_cmd in
    new-session | new | start-server | start) ;;
    *) server_gate || return 1 ;;
  esac
  case $ro_cmd in
    new-session | new) cmd_new_session "$@" ;;
    new-window | neww)
      echo "stub tmux: new-window is not modelled" >&2
      return 1
      ;;
    has-session | has)
      target_arg "$@" || return 1
      resolve_target "$TARGET" && return 0
      echo "can't find session: ${TARGET#=}" >&2
      return 1
      ;;
    kill-session)
      target_arg "$@" || return 1
      resolve_target "$TARGET" || {
        echo "can't find session: ${TARGET#=}" >&2
        return 1
      }
      kill_dir "$STUB_STATE/sessions/$RT_NAME"
      ;;
    kill-server)
      for ro_n in $(live_sessions); do kill_dir "$STUB_STATE/sessions/$ro_n"; done
      return 0
      ;;
    list-sessions | ls) live_sessions ;;
    list-panes)
      ro_fmt='#{pane_id}' ro_t='' ro_all=0
      while [ $# -gt 0 ]; do
        case $1 in
          -a)
            ro_all=1
            shift
            ;;
          -t | -F | -f)
            need_value "$#" "$1" || return 1
            [ "$1" = -t ] && ro_t=$2
            [ "$1" = -F ] && ro_fmt=$2
            shift 2
            ;;
          *) shift ;;
        esac
      done
      if [ -n "$ro_t" ] && [ "$ro_all" = 0 ]; then
        resolve_target "$ro_t" || {
          echo "can't find window: ${ro_t#=}" >&2
          return 1
        }
        ro_names=$RT_NAME
      else
        ro_names=$(live_sessions)
      fi
      for ro_n in $ro_names; do
        load_session_vars "$ro_n"
        expand_format "$ro_fmt"
      done
      return 0
      ;;
    capture-pane | capturep)
      target_arg "$@" || return 1
      [ -z "$TARGET" ] && return 0
      pane_target "$TARGET"
      ;;
    set-option | set | set-window-option | setw) cmd_set_option "$@" ;;
    display-message | display)
      ro_p=0 ro_t=''
      while [ $# -gt 0 ]; do
        case $1 in
          -p)
            ro_p=1
            shift
            ;;
          -t | -c | -F)
            need_value "$#" "$1" || return 1
            [ "$1" = -t ] && ro_t=$2
            shift 2
            ;;
          *) break ;;
        esac
      done
      [ "$ro_p" = 1 ] || return 0
      ns_name='' ns_num='' ns_pid='' ns_dir=''
      if [ -n "$ro_t" ]; then
        resolve_target "$ro_t" || {
          echo "can't find pane: ${ro_t#=}" >&2
          return 1
        }
        load_session_vars "$RT_NAME"
      elif latest_session; then
        load_session_vars "$RT_NAME"
      fi
      expand_format "$*"
      ;;
    *) return 0 ;;
  esac
}

# run_head <count> <argv...> — run the first <count> words as one command.
run_head() {
  rh_k=$1
  shift
  rh_n=$#
  rh_i=0
  for rh_a; do
    rh_i=$((rh_i + 1))
    [ "$rh_i" -le "$rh_k" ] && set -- "$@" "$rh_a"
  done
  shift "$rh_n"
  run_one "$@"
}

record_call "$@"

# Normalize separators to the SEP word, then refuse an unknown command before
# anything runs.
nwords=$#
for w; do
  case $w in
    ';') set -- "$@" "$SEP" ;;
    *'\;') set -- "$@" "${w%\\;};" ;;
    *';') set -- "$@" "${w%;}" "$SEP" ;;
    *) set -- "$@" "$w" ;;
  esac
done
shift "$nwords"
at_start=1
for w; do
  if [ "$w" = "$SEP" ]; then
    at_start=1
    continue
  fi
  if [ "$at_start" = 1 ]; then
    known_command "$w" || {
      echo "unknown command: $w" >&2
      exit 1
    }
    at_start=0
  fi
done

while :; do
  sep=0
  idx=0
  for w; do
    idx=$((idx + 1))
    if [ "$w" = "$SEP" ]; then
      sep=$idx
      break
    fi
  done
  if [ "$sep" -eq 0 ]; then
    run_one "$@"
    exit $?
  fi
  run_head "$((sep - 1))" "$@" || exit 1
  shift "$sep"
done
