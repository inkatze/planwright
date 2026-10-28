#!/usr/bin/env bash
# mc-handover.sh — mission control's succession: the handover trigger for a
# session without the mod, the handover file, the launch of a successor
# through the launcher, the successor's self-check against the file, the
# transfer of the program name and the retirement of the predecessor, and
# the operator-asked resume by name.
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

# The age past which an attended holder's lease no longer proves it live,
# the bound scripts/mc-wake.sh puts on a mod's lease.
LEASE_FRESH=300

help_text() {
  cat <<'HELP'
mc-handover.sh — the succession of a program's mission-control session.

THE PROGRAM NAME is held by exactly one session at a time, recorded in the
holder record <runtime>/holder (the program's runtime directory under the
fleet home): the session's handle, its kind and the generation it took
the name at. A `registry` holder is a session the launcher started
(scripts/mission-control-launch.sh), live while its registry row exists;
an `attended` holder is the operator's own session, live while its wake
lease (<runtime>/leases/<handle>, which the mod restamps) is younger than
five minutes. The harness's own session name is a display name fixed at
launch, so the name other sessions address is this record, never it.

THE HANDOVER FILE, <home>/handover.tsv in the program home, is what the
predecessor hands its successor, one record per line, tab separated:
  format 1 | program <p> | predecessor <handle> | written <epoch>
  | ledger <last decisions-log id or -> | rules <digest of the loaded rules>
  | item <id>... | session <handle>...
A reader refuses a file whose format it does not know, naming the field.

Usage:
  mc-handover.sh due --program <p> --context <percent|-> --wakes <n>
      --compactions <n>
      the trigger the mod applies, for a session without it: the
      compaction ceiling first, then measured context where there is a
      reading, the completed-wake count otherwise. Prints
      due<TAB><reason> or not-due
  mc-handover.sh holder --program <p> [--now <epoch>]
      holder<TAB><handle><TAB><kind><TAB><since><TAB><generation>
      <TAB>live|stale, or holder<TAB>- with no holder
  mc-handover.sh path --program <p>
      path<TAB>unattended, or path<TAB>operator-act<TAB><command> where
      the holder is attended: the harness cannot move the operator's
      terminal to a launched session, so the handover is one operator act
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
      [--backend stream-json|tmux] [--cwd <dir>] [--now <epoch>]
      launch the successor through the launcher (kind mission-control,
      scope gen-<generation>), its brief carrying the handover file's
      path. A live holder admits only the operator's ask (--asked) or a
      live handover (--handover: a handover file naming the live
      holder); any other launch is refused naming the holder. Prints
      successor<TAB><name>
  mc-handover.sh verify --program <p> --session <name> --picture <file>
      --digest <hex> --ledger <id|-> [--durable <file>]
      the successor's self-check: its held picture, rules digest and
      ledger position against the handover file (or, with none, against
      --durable, read by the caller from the stores), through
      mc-rules.sh selfcheck. A pass marks the successor verified and
      prints verified<TAB><name><TAB><the self-check line>; a failure
      raises an item (event handover-failed), prints its item lines and
      leaves the predecessor holding the name
  mc-handover.sh release --program <p> --session <handle> [--now <epoch>]
      the holder gives up the name to a verified successor or to a
      resume that asked for it; prints released<TAB><handle><TAB><to>
  mc-handover.sh take --program <p> --session <name> [--window <cadence>]
      [--now <epoch>]
      the verified successor takes the name: it waits up to the window
      (mission_control_handover_window) for the predecessor's release,
      moves the holder record, retires the predecessor's registry row
      through the launcher (one that did not release is retired all the
      same) and announces itself
  mc-handover.sh resume --program <p> --session <handle>
      [--kind attended|registry] --picture <file> --digest <hex>
      --durable <file> [--window <cadence>] [--now <epoch>]
      the operator-asked resume: the self-check against --durable, a
      release request to a live holder (event handover-requested), the
      same wait, transfer, retirement and announcement, and what changed
      since the operator's last turn

take and resume print, in order:
  took<TAB><handle><TAB><predecessor|-><TAB>released|retired|none
  retire<TAB><predecessor><TAB>released|partial|attended|gone
  changed<TAB>decision<TAB><ts><TAB><subject><TAB><act>     (resume)
  changed<TAB>event<TAB><epoch><TAB><kind><TAB><subject>    (resume)
  changed<TAB>none                                          (resume)
  announce<TAB><session>      each live session the launcher registered
                              for the program, the event
                              mission-control-announce raised once for all
  line<TAB><the one line the operator sees>

Exit codes: 0 done; 1 refused (a store's format, a failed self-check, a
session that is not the holder or the verified successor, a failed write,
a retirement only partly done) or a launcher failure; 2 usage or an
invalid value; 3 the name is held (a launch with neither the ask nor a
live handover, a successor already pending, a take or resume beaten to
the name) or the program is not configured; 4 a launch the holder's kind
rules out (an attended holder hands over by the operator's act).

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-handover.sh due|holder|path|offer|write|launch|verify|release|take|resume --program <p> ... (mc-handover.sh --help)"
}

scratch=''
# shellcheck disable=SC2329 # invoked from the EXIT trap
cleanup() {
  pw_lock_release_all
  [ -z "$scratch" ] || rm -f "$scratch"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

say() { printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2; }

# kv <file> <key>: the value of the first <key> record.
kv() { K=$2 awk -F '\t' '$1 == ENVIRON["K"] { print substr($0, length($1) + 2); exit }' "$1"; }

# kv_handle <file> <key>: a session handle a record names, or `-`; a value
# outside the handle grammar is refused, since it reaches paths and the
# launcher.
kv_handle() {
  kh=$(kv "$1" "$2")
  [ "$kh" = - ] || mc_valid_handle "$kh" || mc_fail "$(sanitize_printable "$1") names a $2 outside the handle grammar"
  printf '%s\n' "$kh"
}

valid_hex() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

# check_picture <file>: a readable file of `item <id>` and `session <h>`.
check_picture() {
  [ -f "$1" ] && [ -r "$1" ] || mc_usage_fail "$(sanitize_printable "$1") is not a readable file"
  cp_bad=$(awk '!/^[ ]*$/ && !/^(item|session) [A-Za-z0-9._:-]+$/ { print NR; exit }' <"$1")
  [ -z "$cp_bad" ] || mc_usage_fail "$(sanitize_printable "$1"):$cp_bad: not an 'item <id>' or 'session <handle>' line"
}

# store_check <file>: refuse a store whose format this script does not know.
store_check() {
  mc_format_ok "$1" && return 0
  sc_f=$(awk -F '\t' 'NR == 1 && $1 == "format" { print $2 }' "$1" 2>/dev/null)
  mc_fail "refusing $(sanitize_printable "$1"): its format field is $(sanitize_printable "${sc_f:-missing}"), not $MC_FORMAT"
}

paths() {
  RUNTIME=$(mc_runtime "$program") || mc_fail "the runtime directory of program $program does not resolve"
  FH=$(mc_fleet_home) || mc_fail "the fleet home does not resolve"
  HOLDER=$RUNTIME/holder
  SUCC=$RUNTIME/successor
  RELEASED=$RUNTIME/released
  REQUEST=$RUNTIME/release-request
  LOCK=$RUNTIME/handover.lock
}

home_path() {
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home 2>/dev/null) || mc_fail "the home of program $program does not resolve"
  case $HOME_DIR in
    /*) ;;
    *) mc_fail "the program home is not absolute" ;;
  esac
  HANDOVER=$HOME_DIR/handover.tsv
}

# read_holder: H_SESSION (empty with no holder), H_KIND, H_SINCE, H_GEN,
# H_LIVE (1 or 0).
read_holder() {
  H_SESSION='' H_KIND='' H_SINCE='' H_GEN=0 H_LIVE=0
  [ -e "$HOLDER" ] || return 0
  store_check "$HOLDER"
  H_SESSION=$(kv "$HOLDER" session)
  H_KIND=$(kv "$HOLDER" kind)
  H_SINCE=$(kv "$HOLDER" since)
  H_GEN=$(kv "$HOLDER" generation)
  if ! mc_valid_handle "$H_SESSION" || ! mc_valid_uint "$H_GEN" || ! mc_valid_uint "$H_SINCE"; then
    mc_fail "the holder record $(sanitize_printable "$HOLDER") is outside its grammar"
  fi
  if session_live "$H_SESSION" "$H_KIND"; then H_LIVE=1; fi
}

# session_live <handle> <kind>: the evidence the holder's kind keeps.
session_live() {
  case $2 in
    registry) [ -f "$FH/mission-control/sessions/$1" ] ;;
    attended)
      sl_l="$RUNTIME/leases/$1"
      [ -f "$sl_l" ] || return 1
      sl_at=$(head -n 1 "$sl_l" 2>/dev/null)
      mc_valid_uint "$sl_at" || return 1
      [ "$sl_at" -le "$NOW" ] && [ $((NOW - sl_at)) -lt "$LEASE_FRESH" ]
      ;;
    *) mc_fail "the holder record names an unknown kind '$(sanitize_printable "$2")'" ;;
  esac
}

lock() {
  pw_lock_trap_install
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

raise() { # raise <kind> <subject> <text>
  mc_event emit --program "$program" --now "$NOW" -- "$1" "$2" "$3" >/dev/null \
    || say "warning: the $1 item could not be raised: $3"
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

# wait_release <predecessor> <seconds>: 0 once the predecessor's release is
# on disk, 1 when the window closes first.
wait_release() {
  wr_end=$(($(mc_now) + $2))
  while :; do
    if [ -f "$RELEASED" ] && mc_format_ok "$RELEASED" && [ "$(kv "$RELEASED" session)" = "$1" ]; then
      return 0
    fi
    [ "$(mc_now)" -lt "$wr_end" ] || return 1
    sleep 1
  done
}

window_seconds() {
  if [ -n "$window" ]; then
    mc_seconds "$window" || mc_usage_fail "--window takes a cadence (a positive count of s, m, h or d)"
    return
  fi
  ws=$(mc_knob mission_control_handover_window mc_parse_cadence) || exit 1
  mc_seconds "$ws"
}

# succeed <successor> <kind> <predecessor|-> <predecessor kind> <wait>: the
# name moves to the successor once the predecessor has released or the
# window has closed, the predecessor's row is retired, and the successor
# announces itself. Sets RETIRE_OK.
succeed() {
  s_to=$1 s_kind=$2 s_from=$3 s_from_kind=$4
  s_how=none
  if [ "$s_from" != - ]; then
    # A predecessor already gone has nothing to release.
    s_wait=$5
    session_live "$s_from" "$s_from_kind" || s_wait=0
    if wait_release "$s_from" "$s_wait"; then s_how=released; else s_how=retired; fi
  fi
  lock
  read_holder
  if [ -n "$H_SESSION" ] && [ "$H_SESSION" != "$s_from" ] && [ "$H_SESSION" != "$s_to" ] && [ "$H_LIVE" -eq 1 ]; then
    unlock
    say "the program name $program was taken by $H_SESSION during the handover"
    exit 3
  fi
  record "$HOLDER" session "$s_to" kind "$s_kind" since "$NOW" generation $((H_GEN + 1))
  rm -f "$RELEASED" "$REQUEST" "$SUCC" "$HANDOVER"
  unlock
  printf 'took\t%s\t%s\t%s\n' "$s_to" "$s_from" "$s_how"

  RETIRE_OK=1
  if [ "$s_from" != - ]; then
    case $s_from_kind in
      registry)
        if [ ! -f "$FH/mission-control/sessions/$s_from" ]; then
          printf 'retire\t%s\tgone\n' "$s_from"
        elif /bin/sh "$script_dir/mission-control-launch.sh" retire "$s_from" >/dev/null 2>&1 </dev/null; then
          printf 'retire\t%s\treleased\n' "$s_from"
        else
          printf 'retire\t%s\tpartial\n' "$s_from"
          raise handover-retire-failed "$s_from" "the predecessor $s_from could not be retired; retire it by name"
          RETIRE_OK=0
        fi
        ;;
      *) printf 'retire\t%s\tattended\n' "$s_from" ;;
    esac
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
    NF >= 2 && $2 == ENVIRON["P"] && $1 != ENVIRON["S"] && $1 != ENVIRON["F"] { printf "announce\t%s\n", $1 }'
  printf 'line\thandover: %s\n' "$a_text"
}

# what_changed <since epoch>: the decisions and events after the operator's
# last turn.
what_changed() {
  wc_iso=$(mc_iso "$1")
  wc_n=0
  wc_d=$(mc_kb_entries "$program" decisions) || exit 1
  wc_out=$(printf '%s\n' "$wc_d" | T=$wc_iso awk -F '\t' 'NF >= 4 && $2 > ENVIRON["T"] { printf "changed\tdecision\t%s\t%s\t%s\n", $2, $3, $4 }' | mc_clean_text)
  wc_e=$(mc_event list --program "$program" 2>/dev/null) || wc_e=''
  wc_out2=$(printf '%s\n' "$wc_e" | T=$1 awk -F '\t' 'NF >= 4 && $2 > ENVIRON["T"] { printf "changed\tevent\t%s\t%s\t%s\n", $2, $3, $4 }' | mc_clean)
  [ -z "$wc_out" ] || {
    printf '%s\n' "$wc_out"
    wc_n=1
  }
  [ -z "$wc_out2" ] || {
    printf '%s\n' "$wc_out2"
    wc_n=1
  }
  [ "$wc_n" -eq 1 ] || printf 'changed\tnone\n'
}

# selfcheck <digest> <held> <durable>: mc-rules.sh selfcheck, its lines
# kept in SC_OUT.
selfcheck() {
  SC_OUT=$(/bin/bash "$script_dir/mc-rules.sh" selfcheck "$program" --digest "$1" --held "$2" --durable "$3" 2>/dev/null)
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
window='' now='' kind='' mode='' context='' wakes='' compactions=''
while [ $# -gt 0 ]; do
  case $1 in
    --program | --session | --picture | --digest | --ledger | --durable | --brief | --backend | --cwd | --window | --now | --kind | --context | --wakes | --compactions)
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
[ -z "$digest" ] || valid_hex "$digest" || mc_usage_fail "--digest takes a SHA-256 in lowercase hex"
need() { [ -n "$2" ] || mc_usage_fail "--$1 is required"; }
mc_require_program "$program"

case $verb in
  due)
    need wakes "$wakes"
    need compactions "$compactions"
    need context "$context"
    mc_valid_uint "$wakes" || mc_usage_fail "--wakes takes a count"
    mc_valid_uint "$compactions" || mc_usage_fail "--compactions takes a count"
    [ "$context" = - ] || mc_valid_uint "$context" || mc_usage_fail "--context takes a percent or -"
    k_comp=$(mc_knob mission_control_handover_compactions mc_parse_count) || exit 1
    if [ "$compactions" -ge "$k_comp" ]; then
      printf 'due\t%s compactions\n' "$compactions"
    elif [ "$context" != - ]; then
      k_ctx=$(mc_knob mission_control_handover_context mc_parse_count) || exit 1
      if [ "$context" -ge "$k_ctx" ]; then printf 'due\tcontext at %s%%\n' "$context"; else printf 'not-due\n'; fi
    else
      k_wakes=$(mc_knob mission_control_handover_wakes mc_parse_count) || exit 1
      if [ "$wakes" -ge "$k_wakes" ]; then printf 'due\t%s wakes\n' "$wakes"; else printf 'not-due\n'; fi
    fi
    ;;
  holder)
    paths
    read_holder
    if [ -z "$H_SESSION" ]; then
      printf 'holder\t-\n'
    else
      if [ "$H_LIVE" -eq 1 ]; then st=live; else st=stale; fi
      printf 'holder\t%s\t%s\t%s\t%s\t%s\n' "$H_SESSION" "$H_KIND" "$H_SINCE" "$H_GEN" "$st"
    fi
    ;;
  path | offer)
    paths
    read_holder
    act="/clear, then /planwright:mission-control $program"
    if [ "$verb" = path ]; then
      if [ "$H_KIND" = attended ]; then printf 'path\toperator-act\t%s\n' "$act"; else printf 'path\tunattended\n'; fi
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
    paths
    home_path
    read_holder
    [ "$H_SESSION" = "$session" ] || mc_fail "$session does not hold the program name $program (the holder is ${H_SESSION:-nobody})"
    led=$(last_ledger)
    (umask 077 && mkdir -p "$HOME_DIR") || mc_fail "cannot create the program home"
    {
      printf 'format\t%s\nprogram\t%s\npredecessor\t%s\nwritten\t%s\nledger\t%s\nrules\t%s\n' \
        "$MC_FORMAT" "$program" "$session" "$NOW" "$led" "$digest"
      awk 'NF == 2 { printf "%s\t%s\n", $1, $2 }' "$picture"
    } | (umask 077 && mc_write "$HANDOVER") || mc_fail "cannot write the handover file"
    printf 'handover\t%s\t%s\n' "$HANDOVER" "$led"
    ;;
  launch)
    need brief "$brief"
    [ -f "$brief" ] && [ -r "$brief" ] && [ -s "$brief" ] || mc_usage_fail "--brief must name a readable, non-empty regular file"
    paths
    home_path
    read_holder
    if [ -f "$SUCC" ]; then
      store_check "$SUCC"
      pend=$(kv_handle "$SUCC" session) || exit 1
      if [ "$pend" != "$H_SESSION" ] && [ -f "$FH/mission-control/sessions/$pend" ]; then
        say "a successor, $pend, is already pending for program $program"
        exit 3
      fi
    fi
    pred=-
    if [ -n "$H_SESSION" ] && [ "$H_LIVE" -eq 1 ]; then
      pred=$H_SESSION
      case $mode in
        asked) ;;
        handover)
          if [ "$H_KIND" = attended ]; then
            say "the holder $H_SESSION is the operator's own session, which the harness cannot move to a launched successor; offer the operator's act instead (mc-handover.sh offer)"
            exit 4
          fi
          [ -f "$HANDOVER" ] || {
            say "the program name $program is held by $H_SESSION, and no handover file is written"
            exit 3
          }
          store_check "$HANDOVER"
          fp=$(kv "$HANDOVER" predecessor)
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
    gen=$((H_GEN + 1))
    scope="gen-$gen"
    name=$(/bin/sh "$script_dir/mission-control-launch.sh" name --program "$program" --kind mission-control --scope "$scope" </dev/null) \
      || mc_fail "the launcher cannot name the successor"
    scratch=$(mktemp "${TMPDIR:-/tmp}/mc-handover.XXXXXX") || mc_fail "cannot compose the successor's brief"
    file_note="no handover file: verify against the durable stores (--durable)"
    [ ! -f "$HANDOVER" ] || file_note="the handover file is $HANDOVER"
    {
      cat "$brief"
      printf '\n## Succession\n\n'
      printf 'You are %s, the successor for program %s (predecessor %s); %s. ' "$name" "$program" "$pred" "$file_note"
      # shellcheck disable=SC2016 # the backticks are markdown in the brief
      printf 'Rebuild from the durable stores, then run `mc-handover.sh verify --program %s --session %s` with your held picture, rules digest and ledger position, and on a pass `mc-handover.sh take --program %s --session %s`.\n' \
        "$program" "$name" "$program" "$name"
    } >"$scratch" || mc_fail "cannot compose the successor's brief"
    set -- launch --program "$program" --kind mission-control --scope "$scope" --brief "$scratch"
    [ -z "$backend" ] || set -- "$@" --backend "$backend"
    [ -z "$cwd" ] || set -- "$@" --cwd "$cwd"
    lout=$(/bin/sh "$script_dir/mission-control-launch.sh" "$@" </dev/null)
    lrc=$?
    [ "$lrc" -eq 0 ] || {
      say "the launcher did not start the successor (mission-control-launch.sh exit $lrc)"
      [ "$lrc" -eq 3 ] && exit 3
      exit 1
    }
    got=$(printf '%s\n' "$lout" | awk -F '\t' '$1 == "launch" && $2 == "name" { print $3; exit }')
    [ "$got" = "$name" ] || mc_fail "the launcher named the successor '$(sanitize_printable "$got")', not $name"
    record "$SUCC" session "$name" predecessor "$pred" predecessor-kind "${H_KIND:--}" launched "$NOW" mode "${mode:-start}" verified -
    printf 'successor\t%s\n' "$name"
    ;;
  verify)
    need session "$session"
    need picture "$picture"
    need digest "$digest"
    need ledger "$ledger"
    check_picture "$picture"
    paths
    home_path
    [ -f "$SUCC" ] || fail_item successor "$session is not the pending successor of program $program: none is pending"
    store_check "$SUCC"
    [ "$(kv "$SUCC" session)" = "$session" ] || fail_item successor "$session is not the pending successor of program $program"
    pred=$(kv_handle "$SUCC" predecessor) || exit 1
    scratch=$(mktemp "${TMPDIR:-/tmp}/mc-handover.XXXXXX") || mc_fail "cannot stage the durable picture"
    if [ -f "$HANDOVER" ]; then
      if ! mc_format_ok "$HANDOVER"; then
        ff=$(awk -F '\t' 'NR == 1 && $1 == "format" { print $2 }' "$HANDOVER")
        fail_item format "refusing the handover file $HANDOVER: its format field is ${ff:-missing}, not $MC_FORMAT"
      fi
      [ "$(kv "$HANDOVER" predecessor)" = "$pred" ] \
        || fail_item file "the handover file names $(kv "$HANDOVER" predecessor), not the predecessor $pred"
      f_rules=$(kv "$HANDOVER" rules)
      f_ledger=$(kv "$HANDOVER" ledger)
      [ "$f_rules" = "$digest" ] || fail_item rules "the successor's rules (digest $digest) are not the predecessor's ($f_rules)"
      [ "$f_ledger" = "$ledger" ] || fail_item ledger "the successor's ledger position $ledger is not the predecessor's last entry $f_ledger"
      awk -F '\t' '$1 == "item" || $1 == "session" { printf "%s %s\n", $1, $2 }' "$HANDOVER" >"$scratch"
    elif [ -n "$durable" ]; then
      check_picture "$durable"
      cat "$durable" >"$scratch"
    else
      fail_item file "no handover file and no --durable picture to check $session against"
    fi
    if ! selfcheck "$digest" "$picture" "$scratch"; then
      printf '%s\n' "$SC_OUT" | awk -F '\t' '$1 == "item"' | mc_clean
      first=$(printf '%s\n' "$SC_OUT" | awk -F '\t' '$1 == "item" { print $4; exit }')
      raise handover-failed "$session" "the successor's self-check failed: ${first:-see the self-check}"
      exit 1
    fi
    lock
    record "$SUCC" session "$session" predecessor "$pred" predecessor-kind "$(kv "$SUCC" predecessor-kind)" \
      launched "$(kv "$SUCC" launched)" mode "$(kv "$SUCC" mode)" verified "$NOW"
    unlock
    printf 'verified\t%s\t%s\n' "$session" "$(printf '%s\n' "$SC_OUT" | head -n 1 | mc_clean)"
    ;;
  release)
    need session "$session"
    paths
    read_holder
    [ "$H_SESSION" = "$session" ] || mc_fail "$session does not hold the program name $program"
    to=''
    if [ -f "$SUCC" ]; then
      store_check "$SUCC"
      [ "$(kv "$SUCC" verified)" = - ] || to=$(kv_handle "$SUCC" session) || exit 1
    fi
    if [ -z "$to" ] && [ -f "$REQUEST" ]; then
      store_check "$REQUEST"
      to=$(kv_handle "$REQUEST" from) || exit 1
    fi
    [ -n "$to" ] || mc_fail "no verified successor and no resume asked for the name: releasing would leave program $program with no holder"
    record "$RELEASED" session "$session" to "$to" at "$NOW"
    printf 'released\t%s\t%s\n' "$session" "$to"
    ;;
  take)
    need session "$session"
    paths
    [ -f "$SUCC" ] || mc_fail "$session is not the pending successor of program $program"
    store_check "$SUCC"
    [ "$(kv "$SUCC" session)" = "$session" ] || mc_fail "$session is not the pending successor of program $program"
    [ "$(kv "$SUCC" verified)" != - ] || mc_fail "$session has not passed its self-check against the handover file"
    home_path
    secs=$(window_seconds) || exit 1
    pred=$(kv_handle "$SUCC" predecessor) || exit 1
    succeed "$session" registry "$pred" "$(kv "$SUCC" predecessor-kind)" "$secs"
    announce "$session" "$s_from"
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
    paths
    home_path
    if ! selfcheck "$digest" "$picture" "$durable"; then
      printf '%s\n' "$SC_OUT" | awk -F '\t' '$1 == "item"' | mc_clean
      raise handover-failed "$session" "the resumed session's self-check failed; the name stays where it is"
      exit 1
    fi
    secs=$(window_seconds) || exit 1
    read_holder
    since=$H_SINCE
    if [ -f "$RUNTIME/presence" ] && mc_format_ok "$RUNTIME/presence"; then
      lp=$(kv "$RUNTIME/presence" last-prompt)
      ! mc_valid_uint "$lp" || since=$lp
    fi
    from=- from_kind=-
    if [ -n "$H_SESSION" ] && [ "$H_SESSION" != "$session" ] && [ "$H_LIVE" -eq 1 ]; then
      from=$H_SESSION from_kind=$H_KIND
      record "$REQUEST" from "$session" at "$NOW"
      raise handover-requested "$H_SESSION" "the operator resumed mission control for $program in $session; release the name"
    elif [ -n "$H_SESSION" ] && [ "$H_SESSION" != "$session" ] && [ "$H_KIND" = registry ]; then
      from=$H_SESSION from_kind=registry
      secs=0
    fi
    succeed "$session" "$kind" "$from" "$from_kind" "$secs"
    what_changed "${since:-0}"
    announce "$session" "$from"
    [ "$RETIRE_OK" -eq 1 ] || exit 1
    ;;
  *) usage ;;
esac
