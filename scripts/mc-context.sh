#!/usr/bin/env bash
# mc-context.sh — a context reading for every mission-control session: the
# percent of its model's context window the last assistant message used,
# read from the tail of the transcript the session's registry row names,
# never from a path given as an argument. Read-only apart from `record`,
# which writes the program's reading records.
#
# `mc-context.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-context
# The most of a transcript's end that is read; a message's last frame sits
# well inside it.
TAIL_BYTES=262144
# A host percent (the panel mod's reading) older than this is a mod that
# stopped; a recorded reading older than this is a runner that stopped.
HOST_FRESH=300
# scripts/mc-panel.sh contexts() holds the same hour; change both together.
RECORD_FRESH=3600
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh mc-transcript-usage.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

help_text() {
  cat <<'EOF'
mc-context.sh — a context reading for every mission-control session.

Usage:
  mc-context.sh read --program <p> [--session <name>] [--now <epoch>]
      one reading:
        context<TAB><session|-><TAB><percent|unknown><TAB><host|transcript|->
      the percent of the window the last assistant message used (input,
      cache-read and cache-creation tokens, the last frame of a message
      streamed in several), from the tail of the transcript the session's
      registry row names: its `transcript` field, or for a stream-json
      session its capture under the fleet home. The window is the one the
      transcript records, else the session's
      <fleet home>/mission-control/context/<name> file's (format 1, key
      `window`), else mission_control_context_window. Where the panel mod
      gave a fresh percent for the program's holder (or, with no --session,
      its attended session) that value is used, source `host`. A missing
      or link transcript, an unknown window or a record that does not parse
      reads `unknown` (never 0). There is no argument that names a
      transcript.
  mc-context.sh record --program <p> [--now <epoch>]
      the runner's act, once per wake: one reading for each of the
      program's registered mission-control sessions (and its attended
      session, printed under the name `attended`, where the mod gave a fresh
      percent), each printed as above and
      kept in <runtime>/readings/<name>:
        format<TAB>1   written<TAB><epoch>   percent<TAB><n|unknown>
        source<TAB><host|transcript|->
      a record of a session no longer registered is dropped.
  mc-context.sh recorded --program <p> --session <name> [--now <epoch>]
      the recorded percent, or `unknown` where there is none, it is older
      than an hour or it does not parse: what mc-handover.sh due reads.
Exit codes: 0 done; 1 a store that cannot be read or written; 2 usage;
3 the program is not configured.
EOF
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
usage() {
  mc_usage_fail "usage: mc-context.sh read|record|recorded --program <p> [--session <name>] [--now <epoch>]; mc-context.sh --help"
}
[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  read | record | recorded) ;;
  *) usage ;;
esac
program="" session="" now=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --session | --now)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --session) session=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
if [ -n "$session" ]; then
  [ "${#session}" -le 64 ] || mc_usage_fail "--session takes a session name"
  case $session in
    *[!a-z0-9-]* | -*) mc_usage_fail "--session takes a session name" ;;
  esac
fi
[ "$verb" != recorded ] || [ -n "$session" ] || usage
[ "$verb" != record ] || [ -z "$session" ] || usage
mc_now_arg "$now"
mc_require_program "$program"

FLEET=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
RUNTIME=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory of program $program"
REG="$FLEET/mission-control/sessions"

parse_window() {
  mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100000000 ] || return 1
  printf '%s\n' "$1"
}

# host_percent <session|->: a fresh percent the mod stamped, for the holder
# of the program (a session) or its attended session (-); fails otherwise.
host_percent() {
  hp_f="$RUNTIME/context"
  [ -f "$hp_f" ] && [ ! -L "$hp_f" ] && [ ! -L "$RUNTIME" ] && mc_format_ok "$hp_f" || return 1
  hp_w=$(mc_kv "$hp_f" written) && mc_valid_uint "$hp_w" || return 1
  [ "$hp_w" -le $((NOW + 60)) ] && [ $((NOW > hp_w ? NOW - hp_w : 0)) -le "$HOST_FRESH" ] || return 1
  hp_p=$(mc_kv "$hp_f" percent) && mc_valid_uint "$hp_p" && [ "$hp_p" -le 100 ] || return 1
  hp_h="$RUNTIME/holder"
  hp_hs="" hp_hk=""
  if [ -f "$hp_h" ] && [ ! -L "$hp_h" ] && mc_format_ok "$hp_h"; then
    hp_hs=$(mc_kv "$hp_h" session)
    hp_hk=$(mc_kv "$hp_h" kind)
  fi
  if [ "$1" = - ]; then
    [ "$hp_hk" = attended ] || return 1
  else
    [ "$hp_hs" = "$1" ] && [ "$hp_hk" = registry ] || return 1
  fi
  printf '%s\n' "$hp_p"
}

# transcript_of <name>: the file the registry row names, nothing else.
transcript_of() {
  to_row="$REG/$1"
  [ -f "$to_row" ] && [ ! -L "$to_row" ] && [ "$(mc_kv "$to_row" format)" = 1 ] || return 1
  [ "$(mc_kv "$to_row" program)" = "$program" ] || return 1
  to_t=$(mc_kv "$to_row" transcript)
  if [ -z "$to_t" ]; then
    [ "$(mc_kv "$to_row" backend)" = stream-json ] || return 1
    to_t="$FLEET/streamjson/$1/events.jsonl"
  fi
  case $to_t in
    /*) ;;
    *) return 1 ;;
  esac
  mc_valid_text "$to_t" || return 1
  [ -f "$to_t" ] && [ ! -L "$to_t" ] && [ -r "$to_t" ] || return 1
  printf '%s\n' "$to_t"
}

# transcript_percent <name>: the percent from the row's transcript tail.
transcript_percent() {
  tp_file=$(transcript_of "$1") || return 1
  tp_out=$(/bin/bash "$script_dir/mc-transcript-usage.sh" "$tp_file" "$TAIL_BYTES") || return 1
  tp_win=""
  tp_ctx=$(printf '%s\n' "$tp_out" | awk -F '\t' '
    $1 == "w" && $2 + 0 > w { w = $2 + 0 }
    # A frame that counts no input (a synthetic one) is no reading.
    $1 == "m" && $3 + $4 + $5 + $6 > 0 { ctx = $3 + $4 + $5 + $6; seen = 1 }
    END { if (seen) print ctx " " w }') || return 1
  [ -n "$tp_ctx" ] || return 1
  tp_win=${tp_ctx#* }
  tp_ctx=${tp_ctx%% *}
  if ! parse_window "$tp_win" >/dev/null 2>&1; then
    tp_win=""
    tp_cf="$FLEET/mission-control/context/$1"
    if [ -f "$tp_cf" ] && [ ! -L "$tp_cf" ] && [ "$(mc_kv "$tp_cf" format)" = 1 ]; then
      tp_win=$(parse_window "$(mc_kv "$tp_cf" window)" 2>/dev/null) || tp_win=""
    fi
    [ -n "$tp_win" ] || tp_win=$(mc_knob mission_control_context_window parse_window 2>/dev/null) || return 1
  fi
  [ "$tp_ctx" -gt 0 ] || return 1
  tp_pct=$((tp_ctx * 100 / tp_win))
  [ "$tp_pct" -le 100 ] || tp_pct=100
  printf '%s\n' "$tp_pct"
}

# reading <name|->: print the reading line.
reading() {
  rd_name=$1
  if rd_p=$(host_percent "$rd_name"); then
    printf 'context\t%s\t%s\thost\n' "$rd_name" "$rd_p"
  elif [ "$rd_name" != - ] && rd_p=$(transcript_percent "$rd_name"); then
    printf 'context\t%s\t%s\ttranscript\n' "$rd_name" "$rd_p"
  else
    printf 'context\t%s\tunknown\t-\n' "$rd_name"
  fi
}

case $verb in
  read) reading "${session:--}" ;;
  record)
    rd="$RUNTIME/readings"
    [ ! -L "$rd" ] || mc_fail "the readings folder is a symlink"
    mkdir -p "$rd" || mc_fail "cannot create $rd"
    keep=" "
    set +f
    for row in "$REG"/*; do
      [ -f "$row" ] && [ ! -L "$row" ] || continue
      n=${row##*/}
      [ "${#n}" -le 64 ] || continue
      case $n in *[!a-z0-9-]* | -* | attended) continue ;; esac
      [ "$(mc_kv "$row" format)" = 1 ] && [ "$(mc_kv "$row" program)" = "$program" ] \
        && [ "$(mc_kv "$row" kind)" = mission-control ] || continue
      line=$(reading "$n")
      keep="$keep$n "
      printf '%s\n' "$line"
      IFS='	' read -r _ _ pct src <<EOF
$line
EOF
      printf 'format\t1\nwritten\t%s\npercent\t%s\nsource\t%s\n' "$NOW" "$pct" "$src" \
        | mc_write "$rd/$n" || mc_fail "cannot write the reading of $n"
    done
    if hp=$(host_percent -); then
      printf 'context\tattended\t%s\thost\n' "$hp"
      keep="${keep}attended "
      printf 'format\t1\nwritten\t%s\npercent\t%s\nsource\thost\n' "$NOW" "$hp" \
        | mc_write "$rd/attended" || mc_fail "cannot write the reading of the attended session"
    fi
    for old in "$rd"/*; do
      [ -f "$old" ] || [ -L "$old" ] || continue
      n=${old##*/}
      case $keep in *" $n "*) ;; *) rm -f -- "$old" ;; esac
    done
    set -f
    ;;
  recorded)
    f="$RUNTIME/readings/$session"
    r=unknown
    if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L "$RUNTIME/readings" ] && mc_format_ok "$f"; then
      w=$(mc_kv "$f" written)
      p=$(mc_kv "$f" percent)
      if mc_valid_uint "$w" && [ "$w" -le $((NOW + 60)) ] && [ $((NOW > w ? NOW - w : 0)) -le "$RECORD_FRESH" ] \
        && mc_valid_uint "$p" && [ "$p" -le 100 ]; then
        r=$p
      fi
    fi
    printf '%s\n' "$r"
    ;;
esac
