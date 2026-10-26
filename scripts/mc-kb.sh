#!/usr/bin/env bash
# mc-kb.sh — a mission-control program's knowledge base: the layout under the
# program home (scripts/mc-program.sh resolves it, never inside one of the
# program's repositories), its index, capped reads, the append-only logs,
# the follow-up ledger, the source table and the mechanism inventory.
#
# Layout, under <home>/kb/:
#   index.md         one line per entry, "- `<path>`: <summary>", loaded
#                    whole within mission_control_kb_index_budget lines
#   <duty dir>/      one per armed duty, named by its catalog `files` field
#   logs/<log>-<YYYY-MM>.log
#                    monthly segments of the decision, undo, would-have and
#                    lock logs: append-only, one entry per line,
#                    id<TAB>ts<TAB>subject<TAB>act<TAB>target<TAB>grounds
#                    <TAB>reversal, the reversal `none` or `argv:` and the
#                    command's words, `%` and space percent-encoded
#   followups.tsv    id<TAB>opened<TAB>owner<TAB>trigger<TAB>state<TAB>text
#                    <TAB>evidence<TAB>closed; a trigger is date:<YYYY-MM-DD>
#                    or event:<name>
#   sources.tsv      name<TAB>kind<TAB>watermark<TAB>ref, kind living or
#                    consumed, a living watermark in epoch seconds
#   mechanisms.tsv   kind<TAB>mechanism<TAB>where<TAB>source
# Every store's first line carries its format field ("# format: 1", or
# "<!-- format: 1 -->" in index.md, and in each segment's .seal sidecar);
# a store with a missing or unknown format is refused and named. Specs and
# tickets are cited by link, never copied (scripts/check-kb-copies.sh).
#
# A segment is never rewritten: each append records the segment's length and
# checksum in its sidecar, and the next append refuses a segment whose
# recorded prefix changed. Every write holds the file's lock
# (<file>.lock, scripts/lock-lib.sh), waiting up to mission_control_kb_lock_wait
# seconds; a lock whose holder is no longer running is released by the next
# writer, which reports it and logs it to the lock log under the file's path.
#
# Usage (every verb takes --program <name>):
#   init                              create the layout and the armed duties'
#                                     directories; an empty directory of a
#                                     disarmed duty is removed, a non-empty
#                                     one reported and kept
#   index                             print the index within its budget
#   index-add <path> <summary>        index an entry, replacing its line
#   read <path>                       print an indexed body within the entry
#                                     cap (mission_control_kb_entry_cap bytes)
#   append <decision|undo|would-have> --subject <s> --act <text>
#          [--target <t>] [--grounds <text>] [--no-reversal | -- <command>...]
#                                     log an act and print its id; an undo
#                                     entry states its reversal or that it
#                                     has none
#   query <decision|undo|would-have|lock> --subject <s>
#                                     the entries for a subject, every segment
#   revert <undo-id>                  run an entry's reversal, as its words
#                                     and never through a shell, and log it
#   lock <path> [--holder <pid>]      claim a file's write lock for a process
#                                     (default the caller), printing the token
#   unlock <path> --token <token>     release it
#   followup add --owner <o> --trigger <t> --text <text>
#   followup due [--date <YYYY-MM-DD>] [--event <name>]...
#   followup close <id> --evidence <text>
#   followup list
#   source set <name> --kind <living|consumed> --ref <ref> [--watermark <w>]
#   inventory-refresh                 rewrite the mechanism inventory from the
#                                     installed planwright and host surfaces
#                                     and move its watermark
#   freshness                         <name><TAB><epoch><TAB><age-seconds> per
#                                     store, log and epoch-stamped source
#
# Exit codes: 0 done; 1 refused (a store's format, a cap, a budget, a held
# lock, a rewritten segment, an entry not found, a failed reversal, a
# program whose home does not resolve); 2 usage or an invalid value;
# 3 the program is not configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

prog=mc-kb
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

FORMAT=1
tab=$(printf '\t')
scratch=''
on_exit() {
  pw_lock_release_all
  [ -z "$scratch" ] || rm -rf "$scratch"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  printf '%s\n' "usage: mc-kb.sh <verb> --program <name> [args]; verbs: init, index, index-add, read, append, query, revert, lock, unlock, followup, source, inventory-refresh, freshness" >&2
  exit 2
}
say() { printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2; }
refuse() {
  say "$1"
  exit 1
}
bad() {
  say "$1"
  exit 2
}

# text_ok <label> <value>: a single-line field with no tab or control byte.
text_ok() {
  case $2 in
    *[[:cntrl:]]*) bad "$1 carries a tab, newline or control character" ;;
  esac
}
need() { # need <label> <value>
  [ -n "$2" ] || bad "$1 is required"
  text_ok "$1" "$2"
}
kebab_ok() { # kebab_ok <label> <value>
  [ "${#2}" -le 64 ] || bad "$1 is longer than 64 characters"
  case $2 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) bad "$1 must be lowercase letters, digits and hyphens" ;;
  esac
}
subject_ok() {
  [ "${#1}" -le 128 ] || bad "the subject is longer than 128 characters"
  case $1 in
    "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._:/@-]*) bad "the subject must be letters, digits and . _ : / @ -, starting with a letter or digit" ;;
  esac
}
now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
now_epoch() { date -u '+%s'; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
work() {
  [ -n "$scratch" ] || scratch=$(mktemp -d) || refuse "cannot create a scratch directory"
}

# int_knob <key>: set KNOB to a positive integer knob through config-get.sh --layers, the
# highest valid layer winning; an invalid adopter or machine-local value is
# warned about and the next lower layer read, an invalid repo-tracked or core
# value fails.
int_knob() {
  ik_lines=$(/bin/sh "$script_dir/config-get.sh" --layers "$1") || refuse "reading $1 failed"
  ik_rev=$(printf '%s\n' "$ik_lines" | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')
  while IFS= read -r ik_line; do
    [ -n "$ik_line" ] || continue
    ik_layer=${ik_line%%"$tab"*}
    ik_val=${ik_line#*"$tab"}
    case $ik_val in
      "" | 0* | *[!0-9]*) ;;
      *)
        if [ "${#ik_val}" -le 9 ]; then
          KNOB=$ik_val
          return 0
        fi
        ;;
    esac
    case $ik_layer in
      adopter | machine-local) say "warning: the $ik_layer value of $1 is not a positive integer; degrading to the next lower layer" ;;
      *) refuse "the $ik_layer value of $1 is not a positive integer" ;;
    esac
  done <<EOF
$ik_rev
EOF
  refuse "$1 is not set (broken install)"
}

# --- the program and its layout ---------------------------------------------

PROGRAM=''
HOME_DIR=''
KB=''
resolve_program() {
  [ -n "$PROGRAM" ] || bad "--program <name> is required"
  HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" home)
  rp_rc=$?
  case $rp_rc in
    0) ;;
    3) exit 3 ;;
    2) exit 2 ;;
    *) refuse "the home of program $PROGRAM does not resolve" ;;
  esac
  case $HOME_DIR in
    /*) ;;
    *) refuse "the home of program $PROGRAM is not an absolute path" ;;
  esac
  KB=$HOME_DIR/kb
}
require_kb() {
  [ -d "$KB" ] || refuse "no knowledge base at $KB (run mc-kb.sh init --program $PROGRAM)"
}

# check_format <file> <label>: the store's first line names a known format.
check_format() {
  [ -f "$1" ] || refuse "store $2 is missing (run mc-kb.sh init --program $PROGRAM)"
  cf_first=$(head -n 1 "$1")
  case $cf_first in
    "<!-- format: "*" -->")
      cf_v=${cf_first#"<!-- format: "}
      cf_v=${cf_v%" -->"}
      ;;
    "# format: "*) cf_v=${cf_first#"# format: "} ;;
    *) refuse "store $2 has no format field" ;;
  esac
  [ "$cf_v" = "$FORMAT" ] || refuse "store $2 has unknown format $cf_v"
}

# new_store <file> <header lines...>: create the store when absent, else
# check its format.
new_store() {
  ns_file=$1
  shift
  if [ -e "$ns_file" ]; then
    check_format "$ns_file" "kb/${ns_file#"$KB"/}"
    return 0
  fi
  printf '%s\n' "$@" >"$ns_file" || refuse "cannot write $ns_file"
}

# kb_path <path>: validate a knowledge-base relative path and set KP to it
# absolute; the path must stay inside the knowledge base, symlinks resolved.
KP=''
kb_path() {
  case $1 in
    "" | /* | .* | */.* | *//* | */) bad "invalid knowledge-base path: $1" ;;
    *[!A-Za-z0-9._/-]*) bad "invalid knowledge-base path: $1" ;;
  esac
  kp_dir=$(dirname "$1")
  kp_real=$(cd "$KB/$kp_dir" 2>/dev/null && pwd -P) || refuse "no such directory in the knowledge base: $kp_dir"
  kp_kb=$(cd "$KB" && pwd -P) || refuse "cannot read $KB"
  case $kp_real in
    "$kp_kb" | "$kp_kb"/*) ;;
    *) refuse "$1 resolves outside the knowledge base" ;;
  esac
  KP=$KB/$1
}

# A body is a regular file inside a duty's directory or the knowledge base's
# top level, never a symlink, a log or one of the stores.
body_path() {
  kb_path "$1"
  case $1 in
    logs/* | index.md | followups.tsv | sources.tsv | mechanisms.tsv) refuse "$1 is a store, read through its own verb" ;;
  esac
  [ ! -L "$KP" ] || refuse "$1 is a symlink; a body is never read through a link"
  [ -f "$KP" ] || refuse "no such entry: $1"
}

# --- locks -------------------------------------------------------------------

LOCK_WAIT=''
KNOB=''
lock_wait() {
  [ -n "$LOCK_WAIT" ] && return 0
  int_knob mission_control_kb_lock_wait
  LOCK_WAIT=$KNOB
}

# claim <file> [<holder-pid>]: take <file>'s write lock for this process, or
# for <holder-pid>; a dead holder's lock is released and logged.
claim() {
  local cl_file cl_lock cl_label cl_tries cl_dead cl_tok cl_rc
  cl_file=$1
  cl_lock=$cl_file.lock
  cl_label=${cl_file#"$KB"/}
  lock_wait
  cl_tries=$((LOCK_WAIT * 50))
  cl_dead=''
  cl_tok=$(pw_lock_owner "$cl_lock")
  if [ -n "$cl_tok" ] && ! pw_lock_owner_alive "$cl_tok"; then
    cl_dead=${cl_tok%%-*}
  fi
  if [ $# -ge 2 ]; then
    pw_lock_acquire_for "$cl_lock" "$2" "$cl_tries"
  else
    pw_lock_acquire "$cl_lock" "$cl_tries"
  fi
  cl_rc=$?
  case $cl_rc in
    0) ;;
    1)
      cl_tok=$(pw_lock_owner "$cl_lock")
      refuse "$cl_label is locked by pid ${cl_tok%%-*}; gave up after ${LOCK_WAIT}s"
      ;;
    *) refuse "cannot take the lock on $cl_label" ;;
  esac
  CLAIM_TOKEN=$PW_LOCK_TOKEN
  if [ -n "$cl_dead" ]; then
    say "released the lock on $cl_label left by pid $cl_dead, which is no longer running"
    do_append lock "$cl_label" "released a dead holder's lock" "pid $cl_dead" "the holder is not running" none
  fi
}
release() { pw_lock_release "$1.lock" || refuse "cannot release the lock on ${1#"$KB"/}"; }

# Replace a store whole: write beside it, then rename over it.
replace_with() { # replace_with <file> <new-content-file>
  mv -f "$2" "$1" || refuse "cannot replace ${1#"$KB"/}"
}

# --- logs --------------------------------------------------------------------

log_ok() { # log_ok <name> <allowed...>
  lo_name=$1
  shift
  for lo_a in "$@"; do
    [ "$lo_name" != "$lo_a" ] || return 0
  done
  bad "unknown log: $lo_name (one of: $*)"
}

seal_of() { printf '%s\n' "$(dirname "$1")/.$(basename "$1" .log).seal"; }

# seal_ok <segment>: the prefix the last append recorded is unchanged.
seal_ok() {
  so_seal=$(seal_of "$1")
  if [ ! -f "$so_seal" ]; then
    [ "$(grep -vc '^#' "$1")" -eq 0 ]
    return
  fi
  check_format "$so_seal" "kb/${so_seal#"$KB"/}"
  so_rec=$(sed -n 2p "$so_seal")
  so_len=${so_rec%% *}
  so_sum=${so_rec#* }
  case $so_len in
    "" | *[!0-9]*) return 1 ;;
  esac
  so_size=$(wc -c <"$1" | tr -d ' ')
  [ "$so_size" -ge "$so_len" ] || return 1
  [ "$(head -c "$so_len" "$1" | cksum | awk '{ print $1 }')" = "$so_sum" ]
}
seal_write() {
  sw_seal=$(seal_of "$1")
  if ! printf '# format: %s\n%s %s\n' "$FORMAT" "$(wc -c <"$1" | tr -d ' ')" "$(cksum <"$1" | awk '{ print $1 }')" >"$sw_seal.new" \
    || ! mv -f "$sw_seal.new" "$sw_seal"; then
    refuse "cannot seal ${1#"$KB"/}"
  fi
}

# do_append <log> <subject> <act> <target> <grounds> <reversal>: append one
# entry under the segment's lock, setting LAST_ID.
LAST_ID=''
do_append() {
  local da_month da_seg da_label da_n da_id
  da_month=$(date -u '+%Y-%m')
  da_seg=$KB/logs/$1-$da_month.log
  da_label=kb/logs/$1-$da_month.log
  claim "$da_seg"
  if [ -f "$da_seg" ]; then
    check_format "$da_seg" "$da_label"
    seal_ok "$da_seg" || refuse "segment $da_label was rewritten since its last append; logs are append-only"
  else
    printf '# format: %s\n' "$FORMAT" >"$da_seg" || refuse "cannot write $da_label"
  fi
  da_n=$(($(grep -vc '^#' "$da_seg") + 1))
  da_id=$1-${da_month%-*}${da_month#*-}-$da_n
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$da_id" "$(now_iso)" "$2" "$3" "${4:--}" "${5:--}" "$6" >>"$da_seg" \
    || refuse "cannot append to $da_label"
  seal_write "$da_seg"
  release "$da_seg"
  LAST_ID=$da_id
}

segments() { # segments <log>: every segment of a log, oldest first
  set +f
  for sg in "$KB"/logs/"$1"-[0-9][0-9][0-9][0-9]-[0-9][0-9].log; do
    [ -f "$sg" ] && printf '%s\n' "$sg"
  done
  set -f
}

# encode_word <word>: percent-encode `%` and space.
encode_word() {
  ew=${1//%/%25}
  printf '%s' "${ew// /%20}"
}

# --- verbs -------------------------------------------------------------------

v_init() {
  [ $# -eq 0 ] || usage
  duty_rows=$(/bin/bash "$script_dir/mc-duties.sh" files --program "$PROGRAM") || refuse "the duties of program $PROGRAM do not resolve"
  mkdir -p "$KB/logs" || refuse "cannot create $KB"
  new_store "$KB/index.md" "<!-- format: $FORMAT -->"
  new_store "$KB/followups.tsv" "# format: $FORMAT" "# id${tab}opened${tab}owner${tab}trigger${tab}state${tab}text${tab}evidence${tab}closed"
  new_store "$KB/sources.tsv" "# format: $FORMAT" "# name${tab}kind${tab}watermark${tab}ref"
  new_store "$KB/mechanisms.tsv" "# format: $FORMAT" "# kind${tab}mechanism${tab}where${tab}source"
  armed=''
  while IFS="$tab" read -r d_id d_dir; do
    [ -n "$d_id" ] || continue
    case $d_dir in
      logs) refuse "duty $d_id names the reserved directory logs" ;;
    esac
    kebab_ok "the directory of duty $d_id" "$d_dir"
    mkdir -p "$KB/$d_dir" || refuse "cannot create kb/$d_dir"
    armed="$armed $d_dir "
  done <<EOF
$duty_rows
EOF
  set +f
  for d in "$KB"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    d=${d##*/}
    case $d in logs) continue ;; esac
    case $armed in *" $d "*) continue ;; esac
    if rmdir "$KB/$d" 2>/dev/null; then
      say "removed kb/$d, the empty directory of a duty no longer armed"
    else
      say "kb/$d belongs to no armed duty; kept, since it holds files"
    fi
  done
  set -f
  printf '%s\n' "$KB"
}

v_index() {
  [ $# -eq 0 ] || usage
  require_kb
  check_format "$KB/index.md" kb/index.md
  int_knob mission_control_kb_index_budget
  budget=$KNOB
  lines=$(tail -n +2 "$KB/index.md" | grep -c .)
  tail -n +2 "$KB/index.md" | grep . | head -n "$budget"
  if [ "$lines" -gt "$budget" ]; then
    over=$((lines - budget))
    unit=lines
    [ "$over" -ne 1 ] || unit=line
    refuse "the index is $over $unit over its budget of $budget (mission_control_kb_index_budget); the overflow was not loaded"
  fi
}

v_index_add() {
  [ $# -eq 2 ] || usage
  require_kb
  body_path "$1"
  need "the summary" "$2"
  check_format "$KB/index.md" kb/index.md
  int_knob mission_control_kb_index_budget
  budget=$KNOB
  work
  claim "$KB/index.md"
  {
    head -n 1 "$KB/index.md"
    P="- \`$1\`: " awk 'NR > 1 && index($0, ENVIRON["P"]) != 1 && $0 != ""' "$KB/index.md"
    printf '%s\n' "- \`$1\`: $2"
  } >"$KB/index.md.new"
  lines=$(tail -n +2 "$KB/index.md.new" | grep -c .)
  if [ "$lines" -gt "$budget" ]; then
    rm -f "$KB/index.md.new"
    refuse "indexing $1 would put the index at $lines lines, over its budget of $budget (mission_control_kb_index_budget); retire an entry or raise the knob"
  fi
  replace_with "$KB/index.md" "$KB/index.md.new"
  release "$KB/index.md"
}

v_read() {
  [ $# -eq 1 ] || usage
  require_kb
  check_format "$KB/index.md" kb/index.md
  if [ -L "$KB/$1" ]; then
    refuse "$1 is a symlink; a body is never read through a link"
  fi
  body_path "$1"
  P="- \`$1\`: " awk 'index($0, ENVIRON["P"]) == 1 { f = 1 } END { exit !f }' "$KB/index.md" \
    || refuse "$1 is not in the index; index it before reading it"
  int_knob mission_control_kb_entry_cap
  cap=$KNOB
  size=$(wc -c <"$KP" | tr -d ' ')
  if [ "$size" -gt "$cap" ]; then
    refuse "$1 is $size bytes, above the entry cap of $cap (mission_control_kb_entry_cap); offload the read to a read-only session that returns an answer (/planwright:offload), never the file"
  fi
  cat "$KP"
}

v_append() {
  [ $# -ge 1 ] || usage
  log=$1
  shift
  log_ok "$log" decision undo would-have
  subject='' act='' target='' grounds='' rev=''
  while [ $# -gt 0 ]; do
    case $1 in
      --subject | --act | --target | --grounds)
        [ $# -ge 2 ] || usage
        case $1 in
          --subject) subject=$2 ;;
          --act) act=$2 ;;
          --target) target=$2 ;;
          --grounds) grounds=$2 ;;
        esac
        shift 2
        ;;
      --no-reversal)
        [ -z "$rev" ] || bad "state one reversal"
        rev=none
        shift
        ;;
      --)
        shift
        [ -z "$rev" ] || bad "state one reversal"
        [ $# -ge 1 ] || bad "-- needs the reversal command"
        rev=argv:
        sep=''
        for w in "$@"; do
          [ -n "$w" ] || bad "a reversal word is empty"
          text_ok "a reversal word" "$w"
          rev=$rev$sep$(encode_word "$w")
          sep=' '
        done
        set --
        ;;
      *) usage ;;
    esac
  done
  [ -n "$subject" ] || bad "--subject is required"
  subject_ok "$subject"
  need "--act" "$act"
  text_ok "--target" "$target"
  text_ok "--grounds" "$grounds"
  if [ -z "$rev" ]; then
    [ "$log" != undo ] || bad "an undo entry states its reversal (-- <command>...) or --no-reversal"
    rev=none
  fi
  require_kb
  do_append "$log" "$subject" "$act" "$target" "$grounds" "$rev"
  printf '%s\n' "$LAST_ID"
}

v_query() {
  [ $# -eq 3 ] && [ "$2" = --subject ] || usage
  log_ok "$1" decision undo would-have lock
  subject_ok "$3"
  require_kb
  for seg in $(segments "$1"); do
    check_format "$seg" "kb/${seg#"$KB"/}"
    S=$3 awk -F '\t' '!/^#/ && $3 == ENVIRON["S"]' "$seg"
  done
}

v_revert() {
  [ $# -eq 1 ] || usage
  case $1 in
    undo-[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]*) ;;
    *) bad "invalid undo entry id: $1" ;;
  esac
  case ${1#undo-??????-} in
    *[!0-9]*) bad "invalid undo entry id: $1" ;;
  esac
  require_kb
  ym=${1#undo-}
  ym=${ym%%-*}
  seg=$KB/logs/undo-${ym%??}-${ym#????}.log
  [ -f "$seg" ] || refuse "no undo entry $1"
  check_format "$seg" "kb/${seg#"$KB"/}"
  entry=$(I=$1 awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print; exit }' "$seg")
  [ -n "$entry" ] || refuse "no undo entry $1"
  r_subject=$(printf '%s\n' "$entry" | cut -f 3)
  r_rev=$(printf '%s\n' "$entry" | cut -f 7)
  case $r_rev in
    argv:?*) ;;
    *) refuse "undo entry $1 records no reversal" ;;
  esac
  for s in $(segments undo); do
    if I=$1 awk -F '\t' '!/^#/ && $4 == "reverted" && $5 == ENVIRON["I"] { f = 1 } END { exit !f }' "$s"; then
      refuse "undo entry $1 was already reverted"
    fi
  done
  args=()
  IFS=' '
  for w in ${r_rev#argv:}; do
    w=${w//%20/ }
    args[${#args[@]}]=${w//%25/%}
  done
  unset IFS
  "${args[@]}"
  r_rc=$?
  if [ "$r_rc" -ne 0 ]; then
    do_append undo "$r_subject" "revert failed" "$1" "exit $r_rc" none
    refuse "the reversal of $1 failed (exit $r_rc)"
  fi
  do_append undo "$r_subject" reverted "$1" "exit 0" none
  printf '%s\n' "$LAST_ID"
}

v_lock() {
  [ $# -ge 1 ] || usage
  file=$1
  shift
  holder=$PPID
  while [ $# -gt 0 ]; do
    case $1 in
      --holder)
        [ $# -ge 2 ] || usage
        holder=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  case $holder in
    "" | 0* | *[!0-9]*) bad "--holder needs a process id" ;;
  esac
  require_kb
  kb_path "$file"
  claim "$KP" "$holder"
  printf '%s\n' "$CLAIM_TOKEN"
}

v_unlock() {
  [ $# -eq 3 ] && [ "$2" = --token ] || usage
  need "--token" "$3"
  require_kb
  kb_path "$1"
  pw_lock_release_token "$KP.lock" "$3" || refuse "$1 is not locked by that token"
}

v_followup() {
  [ $# -ge 1 ] || usage
  sub=$1
  shift
  require_kb
  fu=$KB/followups.tsv
  check_format "$fu" kb/followups.tsv
  case $sub in
    add)
      owner='' trigger='' text=''
      while [ $# -gt 0 ]; do
        [ $# -ge 2 ] || usage
        case $1 in
          --owner) owner=$2 ;;
          --trigger) trigger=$2 ;;
          --text) text=$2 ;;
          *) usage ;;
        esac
        shift 2
      done
      [ -n "$owner" ] || bad "--owner is required"
      kebab_ok "--owner" "$owner"
      [ -n "$trigger" ] || bad "--trigger is required"
      case $trigger in
        date:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        event:?*) kebab_ok "the trigger's event" "${trigger#event:}" ;;
        *) bad "a trigger is date:<YYYY-MM-DD> or event:<name>" ;;
      esac
      need "--text" "$text"
      claim "$fu"
      n=$(($(grep -vc '^#' "$fu") + 1))
      printf 'f-%s\t%s\t%s\t%s\topen\t%s\t-\t-\n' "$n" "$(now_iso)" "$owner" "$trigger" "$text" >>"$fu" \
        || refuse "cannot append to kb/followups.tsv"
      release "$fu"
      printf 'f-%s\n' "$n"
      ;;
    due)
      day=$(date -u '+%Y-%m-%d')
      events=' '
      while [ $# -gt 0 ]; do
        [ $# -ge 2 ] || usage
        case $1 in
          --date)
            case $2 in
              [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) day=$2 ;;
              *) bad "--date takes YYYY-MM-DD" ;;
            esac
            ;;
          --event)
            kebab_ok "--event" "$2"
            events="$events$2 "
            ;;
          *) usage ;;
        esac
        shift 2
      done
      D=$day E=$events awk -F '\t' '
        /^#/ || $5 != "open" { next }
        $4 ~ /^date:/ && substr($4, 6) <= ENVIRON["D"] { print; next }
        $4 ~ /^event:/ && index(ENVIRON["E"], " " substr($4, 7) " ") { print }
      ' "$fu"
      ;;
    close)
      [ $# -ge 1 ] || usage
      id=$1
      shift
      evidence=''
      while [ $# -gt 0 ]; do
        [ $# -ge 2 ] && [ "$1" = --evidence ] || usage
        evidence=$2
        shift 2
      done
      case $id in
        f-[1-9]*) ;;
        *) bad "invalid follow-up id: $id" ;;
      esac
      case ${id#f-} in *[!0-9]*) bad "invalid follow-up id: $id" ;; esac
      need "--evidence (a row closes only with evidence)" "$evidence"
      claim "$fu"
      state=$(I=$id awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print $5; exit }' "$fu")
      [ -n "$state" ] || refuse "no follow-up $id"
      [ "$state" = open ] || refuse "follow-up $id is already $state"
      I=$id V=$evidence T=$(now_iso) awk -F '\t' -v OFS='\t' '
        !/^#/ && $1 == ENVIRON["I"] { $5 = "closed"; $7 = ENVIRON["V"]; $8 = ENVIRON["T"] }
        { print }
      ' "$fu" >"$fu.new" || refuse "cannot rewrite kb/followups.tsv"
      replace_with "$fu" "$fu.new"
      release "$fu"
      ;;
    list)
      [ $# -eq 0 ] || usage
      grep -v '^#' "$fu"
      ;;
    *) usage ;;
  esac
  return 0
}

# set_source <name> <kind> <watermark> <ref>: replace the source's row.
set_source() {
  ss=$KB/sources.tsv
  check_format "$ss" kb/sources.tsv
  claim "$ss"
  {
    N=$1 awk -F '\t' '/^#/ || $1 != ENVIRON["N"]' "$ss"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  } >"$ss.new" || refuse "cannot rewrite kb/sources.tsv"
  replace_with "$ss" "$ss.new"
  release "$ss"
}

v_source() {
  [ $# -ge 2 ] && [ "$1" = set ] || usage
  name=$2
  shift 2
  kebab_ok "the source name" "$name"
  kind='' ref='' wm=''
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --kind) kind=$2 ;;
      --ref) ref=$2 ;;
      --watermark) wm=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  case $kind in
    living | consumed) ;;
    *) bad "--kind is living or consumed" ;;
  esac
  need "--ref" "$ref"
  [ -n "$wm" ] || wm=$(now_epoch)
  text_ok "--watermark" "$wm"
  require_kb
  set_source "$name" "$kind" "$wm" "$ref"
}

# inventory_rows: kind<TAB>mechanism<TAB>where<TAB>source, one per mechanism
# the installed planwright and host can make deterministic.
inventory_rows() {
  core=${PLANWRIGHT_ROOT:-$script_dir/..}
  ver=$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$core/.claude-plugin/plugin.json" 2>/dev/null | head -n 1)
  [ -n "$ver" ] || ver=unknown
  opts=$core/docs/options-reference.md
  if [ -r "$opts" ]; then
    V=$ver awk '
      /^\| `[a-z0-9_]+` \|/ {
        k = $0; sub(/^\| `/, "", k); sub(/`.*/, "", k)
        printf "knob\t%s\tthe config layers (config/defaults.yml and its overlays)\tdocs/options-reference.md (planwright %s)\n", k, ENVIRON["V"]
      }' "$opts"
  else
    say "warning: no options reference at $opts; no knob rows"
  fi
  if steps=$(/bin/bash "$script_dir/resolve-catalog.sh" steps --explain 2>/dev/null); then
    printf '%s\n' "$steps" | awk -F '\t' 'NF >= 2 && $1 != "" { printf "catalog-step\t%s\tthe %s steps catalog\tscripts/resolve-catalog.sh steps\n", $1, $2 }'
  else
    say "warning: the steps catalog does not resolve; no catalog-step rows"
  fi
  if duties=$(/bin/bash "$script_dir/mc-duties.sh" list 2>/dev/null); then
    printf '%s\n' "$duties" | awk -F '\t' 'NF >= 2 && $1 != "" { printf "duty\t%s\tthe %s duties catalog\tscripts/mc-duties.sh list\n", $1, $2 }'
  else
    say "warning: the duties catalog does not resolve; no duty rows"
  fi
  claude_dir=${CLAUDE_DIR:-$HOME/.claude}
  files="$claude_dir/settings.json$tab$claude_dir/settings.local.json"
  repos=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" repositories 2>/dev/null) || repos=''
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    files="$files$tab$r/.claude/settings.json$tab$r/.claude/settings.local.json"
  done <<EOF
$repos
EOF
  if command -v jq >/dev/null 2>&1; then
    IFS=$tab
    for f in $files; do
      [ -f "$f" ] || continue
      F=$f jq -r '
        def clean: tostring | gsub("[[:cntrl:]]"; "?");
        ((.hooks // {}) | to_entries[] | .key as $e | (.value // [])[]
          | ["hook", ($e + " " + ((.matcher // "*") | clean)), $ENV.F, $ENV.F]),
        ((.permissions // {}) | to_entries[] | select(.key == "allow" or .key == "ask" or .key == "deny")
          | .key as $l | (.value // [])[] | ["permission", ($l + ": " + (. | clean)), $ENV.F, $ENV.F])
        | @tsv' "$f" 2>/dev/null || say "warning: $f does not parse as settings JSON; skipped"
    done
    unset IFS
  else
    say "warning: jq is not on PATH; no hook or permission rows"
  fi
  printf '%s\n' \
    "hook${tab}(a new hook on any host event)${tab}$claude_dir/settings.json${tab}host capability" \
    "permission${tab}(a new allow, ask or deny rule)${tab}$claude_dir/settings.json${tab}host capability" \
    "routine${tab}a scheduled routine${tab}the host's routine scheduler (/schedule)${tab}host capability" \
    "rule${tab}a rule-store entry${tab}$HOME_DIR/rules.yaml${tab}the mission-control rule store"
}

v_inventory_refresh() {
  [ $# -eq 0 ] || usage
  require_kb
  inv=$KB/mechanisms.tsv
  check_format "$inv" kb/mechanisms.tsv
  work
  inventory_rows | awk -F '\t' 'NF == 4' | sort -u >"$scratch/rows"
  wm=$(now_epoch)
  claim "$inv"
  {
    printf '# format: %s\n' "$FORMAT"
    printf '# refreshed: %s\n' "$wm"
    printf '# kind\tmechanism\twhere\tsource\n'
    cat "$scratch/rows"
  } >"$inv.new" || refuse "cannot write kb/mechanisms.tsv"
  replace_with "$inv" "$inv.new"
  release "$inv"
  set_source mechanism-inventory living "$wm" kb/mechanisms.tsv
  printf '%s\n' "$(grep -c . "$scratch/rows") mechanisms"
}

v_freshness() {
  [ $# -eq 0 ] || usage
  require_kb
  now=$(now_epoch)
  for s in index.md followups.tsv sources.tsv mechanisms.tsv; do
    [ -f "$KB/$s" ] || continue
    t=$(mtime "$KB/$s") || continue
    printf '%s\t%s\t%s\n' "$s" "$t" "$((now - t))"
  done
  for l in decision undo would-have lock; do
    newest=''
    for seg in $(segments "$l"); do newest=$seg; done
    [ -n "$newest" ] || continue
    t=$(mtime "$newest") || continue
    printf '%s\t%s\t%s\n' "logs/$l" "$t" "$((now - t))"
  done
  check_format "$KB/sources.tsv" kb/sources.tsv
  N=$now awk -F '\t' '!/^#/ && $3 ~ /^[0-9]+$/ { printf "source:%s\t%s\t%d\n", $1, $3, ENVIRON["N"] - $3 }' "$KB/sources.tsv"
}

# --- dispatch ----------------------------------------------------------------

[ $# -ge 1 ] || usage
verb=$1
shift
rest=()
while [ $# -gt 0 ]; do
  case $1 in
    --program)
      [ $# -ge 2 ] || usage
      PROGRAM=$2
      shift 2
      ;;
    --)
      # `--` and everything after it (an append's reversal command), verbatim.
      for a in "$@"; do rest[${#rest[@]}]=$a; done
      set --
      ;;
    *)
      rest[${#rest[@]}]=$1
      shift
      ;;
  esac
done
case $verb in
  init | index | index-add | read | append | query | revert | lock | unlock | followup | source | inventory-refresh | freshness) ;;
  *) usage ;;
esac
resolve_program
set -- ${rest[@]+"${rest[@]}"}
case $verb in
  init) v_init "$@" ;;
  index) v_index "$@" ;;
  index-add) v_index_add "$@" ;;
  read) v_read "$@" ;;
  append) v_append "$@" ;;
  query) v_query "$@" ;;
  revert) v_revert "$@" ;;
  lock) v_lock "$@" ;;
  unlock) v_unlock "$@" ;;
  followup) v_followup "$@" ;;
  source) v_source "$@" ;;
  inventory-refresh) v_inventory_refresh "$@" ;;
  freshness) v_freshness "$@" ;;
esac
