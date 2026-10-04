#!/bin/sh
# tmux-launch-stub-tmux.sh — the stub `tmux` of the launch fixture harness
# (tests/lib/tmux-launch-harness.sh installs a `tmux` shim that execs this with
# the harness state directory as its first argument). Never run directly.
#
# It models the one property the launch fixtures depend on: a session's command
# runs with the stub SERVER's environment (the KEY=VALUE lines of
# <state>/server.env, under `env -i`), never the calling client's. A launch
# that applies its environment outside the session therefore loses it here,
# exactly as it does under a real server.
#
# Behaviour, per subcommand (argv is split into commands at a literal `;` word,
# as tmux does, and a failing command stops the rest):
#   new-session  flags given separately (-d -P -A -D -E -X; -s -c -F -n -x -y
#                -t -e -f take a value), then optional `--` and the command
#                words. The name is rewritten `.`/`:` to `_`; a live session
#                holding it is refused `duplicate session: <name>`; a `-c` that
#                is not a directory silently starts in the server's HOME. The
#                command runs in the background, detached from every caller
#                fd. `-P` prints the `-F` format (default `#{session_name}:`)
#                expanding session_name, session_id, window_id, pane_id,
#                pane_pid, and pane_current_path (the -c value as given).
#   has-session / kill-session / list-sessions  against live sessions; a
#                session whose command has exited is gone (remain-on-exit off).
#                A target without `=` matches exactly, then by unique prefix.
#   anything else  logged and answered 0 (capture-pane prints nothing,
#                display-message -p prints its message words).
#
# Knobs (one-line files under <state>/knobs/, written by tlh_knob):
#   new-session  ok (default) | fail | duplicate | block — block creates the
#                session and then never returns, the old launcher's shape
#   server       up (default) | none | unreachable — none answers every query
#                `no server running` (new-session still starts one);
#                unreachable refuses every call, new-session included
#
# Every invocation's argv lands in its own file, <state>/calls/<seq>, written
# to a private temp name and renamed, so concurrent calls never interleave;
# <seq> is claimed with an atomic mkdir. Every process this stub starts is
# recorded as <state>/pids/<pid> for the harness's reaper.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

S=$1
shift

# claim_seq <kind> — claim and print the next free number for <kind>. Claims
# are never released, so the count of existing ones is where to start; a
# racing claimer that took it moves this one to the next.
claim_seq() {
  [ -d "$S/seq" ] || return 1
  cs_kind=$1
  set -- "$S/seq/$cs_kind".*
  cs_n=$#
  [ -e "$1" ] || cs_n=0
  cs_n=$((cs_n + 1))
  while [ "$cs_n" -lt 1000000 ]; do
    cs_id=$(printf '%06d' "$cs_n")
    if mkdir "$S/seq/$cs_kind.$cs_id" 2>/dev/null; then
      printf '%s\n' "$cs_id"
      return 0
    fi
    cs_n=$((cs_n + 1))
  done
  return 1
}

write_atomic() {
  wa_tmp="$(dirname "$1")/.tmp.$$"
  cat >"$wa_tmp" && mv "$wa_tmp" "$1"
}

knob() {
  if [ -r "$S/knobs/$1" ]; then
    IFS= read -r kv_val <"$S/knobs/$1" || true
    printf '%s\n' "${kv_val:-$2}"
  else
    printf '%s\n' "$2"
  fi
}

record_call() {
  rc_id=$(claim_seq call) || {
    echo "stub tmux: cannot claim a call sequence number under $S" >&2
    exit 70
  }
  {
    rc_first=1
    for rc_a in "$@"; do
      if [ "$rc_first" = 1 ]; then
        printf '%s' "$rc_a"
        rc_first=0
      else
        printf '\t%s' "$rc_a"
      fi
    done
    printf '\n'
  } | write_atomic "$S/calls/$rc_id"
}

server_home() {
  sh_home=$(sed -n 's/^HOME=//p' "$S/server.env" 2>/dev/null | head -n 1)
  printf '%s\n' "${sh_home:-/}"
}

kill_tree() {
  for kt_c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$2" '$2 == p { print $1 }'); do
    kill_tree "$1" "$kt_c"
  done
  kill "-$1" "$2" 2>/dev/null
}

# session_live <name> — 0 while the session's command runs. A session still
# being created (no pid yet) counts as live; a dead one is removed.
session_live() {
  [ -d "$S/sessions/$1" ] || return 1
  [ -r "$S/sessions/$1/pid" ] || return 0
  IFS= read -r sl_pid <"$S/sessions/$1/pid" || return 0
  kill -0 "$sl_pid" 2>/dev/null && return 0
  rm -rf "$S/sessions/$1"
  return 1
}

live_sessions() {
  for ls_d in "$S"/sessions/*; do
    [ -d "$ls_d" ] || continue
    ls_n=${ls_d##*/}
    session_live "$ls_n" && printf '%s\n' "$ls_n"
  done
}

# resolve_target <target> — print the live session it names, or fail.
resolve_target() {
  rt_t=$1
  rt_exact=0
  case $rt_t in =*) rt_exact=1 rt_t=${rt_t#=} ;; esac
  rt_t=${rt_t%%:*}
  [ -n "$rt_t" ] || return 1
  if session_live "$rt_t"; then
    printf '%s\n' "$rt_t"
    return 0
  fi
  [ "$rt_exact" = 1 ] && return 1
  rt_hits=$(live_sessions | while IFS= read -r rt_n; do
    case $rt_n in "$rt_t"*) printf '%s\n' "$rt_n" ;; esac
  done)
  [ -n "$rt_hits" ] || return 1
  [ "$(printf '%s\n' "$rt_hits" | wc -l | tr -d ' ')" = 1 ] || return 1
  printf '%s\n' "$rt_hits"
}

server_gate() {
  case $(knob server up) in
    none)
      echo "no server running on $S/socket" >&2
      return 1
      ;;
    unreachable)
      echo "error connecting to $S/socket (Permission denied)" >&2
      return 1
      ;;
  esac
  return 0
}

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
        case $ef_key in
          session_name) ef_v=$ns_name ;;
          session_id) ef_v="\$$ns_num" ;;
          window_id) ef_v="@$ns_num" ;;
          pane_id) ef_v="%$ns_num" ;;
          pane_pid) ef_v=$ns_pid ;;
          pane_current_path) ef_v=$ns_dir ;;
          *) ef_v='' ;;
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

need_value() {
  [ "$1" -ge 2 ] && return 0
  echo "stub tmux: $2 needs a value" >&2
  return 1
}

cmd_new_session() {
  ns_name='' ns_dir='' ns_fmt='#{session_name}:' ns_print=0
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
  [ "$(knob server up)" = unreachable ] && {
    server_gate
    return 1
  }
  case $(knob new-session ok) in
    fail)
      echo "create session failed: stubbed failure" >&2
      return 1
      ;;
    duplicate)
      echo "duplicate session: $ns_name" >&2
      return 1
      ;;
  esac
  ns_seq=$(claim_seq session) || return 1
  ns_num=${ns_seq#"${ns_seq%%[!0]*}"}
  [ -n "$ns_name" ] || ns_name=$ns_num
  ns_name=$(printf '%s' "$ns_name" | tr '.:' '__')
  if ! mkdir "$S/sessions/$ns_name" 2>/dev/null; then
    if session_live "$ns_name" || ! mkdir "$S/sessions/$ns_name" 2>/dev/null; then
      echo "duplicate session: $ns_name" >&2
      return 1
    fi
  fi
  ns_sd="$S/sessions/$ns_name"
  ns_start=${ns_dir:-$(pwd)}
  [ -d "$ns_start" ] || ns_start=$(server_home)
  printf '%s\n' "$ns_dir" | write_atomic "$ns_sd/cwd"
  [ $# -gt 0 ] || set -- sleep 600
  (
    cd "$ns_start" 2>/dev/null || exit 1
    ns_n=$#
    while IFS= read -r ns_kv; do
      [ -n "$ns_kv" ] && set -- "$@" "$ns_kv"
    done <"$S/server.env"
    ns_i=0
    while [ "$ns_i" -lt "$ns_n" ]; do
      set -- "$@" "$1"
      shift
      ns_i=$((ns_i + 1))
    done
    exec env -i "$@"
  ) </dev/null >"$ns_sd/out" 2>&1 &
  ns_pid=$!
  : >"$S/pids/$ns_pid"
  printf '%s\n' "$ns_pid" | write_atomic "$ns_sd/pid"
  if [ "$(knob new-session ok)" = block ]; then
    : >"$S/pids/$$"
    exec sleep 600
  fi
  [ "$ns_print" = 1 ] && expand_format "$ns_fmt"
  return 0
}

target_arg() {
  ta_t=''
  while [ $# -gt 0 ]; do
    case $1 in
      -t)
        need_value "$#" -t || return 1
        ta_t=$2
        shift 2
        ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$ta_t"
}

run_one() {
  [ $# -gt 0 ] || return 0
  ro_cmd=$1
  shift
  case $ro_cmd in
    new-session | new) cmd_new_session "$@" ;;
    has-session | has)
      server_gate || return 1
      ro_t=$(target_arg "$@") || return 1
      resolve_target "$ro_t" >/dev/null && return 0
      echo "can't find session: ${ro_t#=}" >&2
      return 1
      ;;
    kill-session)
      server_gate || return 1
      ro_t=$(target_arg "$@") || return 1
      ro_n=$(resolve_target "$ro_t") || {
        echo "can't find session: ${ro_t#=}" >&2
        return 1
      }
      IFS= read -r ro_pid <"$S/sessions/$ro_n/pid" 2>/dev/null && kill_tree TERM "$ro_pid"
      rm -rf "$S/sessions/$ro_n"
      return 0
      ;;
    list-sessions | ls)
      server_gate || return 1
      ro_live=$(live_sessions)
      if [ -z "$ro_live" ]; then
        echo "no server running on $S/socket" >&2
        return 1
      fi
      printf '%s\n' "$ro_live"
      return 0
      ;;
    display-message | display)
      server_gate || return 1
      ro_p=0
      while [ $# -gt 0 ]; do
        case $1 in
          -p)
            ro_p=1
            shift
            ;;
          -t | -c | -F)
            need_value "$#" "$1" || return 1
            shift 2
            ;;
          *) break ;;
        esac
      done
      [ "$ro_p" = 1 ] && printf '%s\n' "$*"
      return 0
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
while :; do
  semi=0
  idx=0
  for a; do
    idx=$((idx + 1))
    if [ "$a" = ';' ]; then
      semi=$idx
      break
    fi
  done
  if [ "$semi" -eq 0 ]; then
    run_one "$@"
    exit $?
  fi
  run_head "$((semi - 1))" "$@" || exit 1
  shift "$semi"
done
