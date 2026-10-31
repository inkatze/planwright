#!/usr/bin/env bash
# mc-kb.sh — a mission-control program's knowledge base under the program
# home: its index, capped reads, append-only logs, locks, follow-up ledger,
# source table and mechanism inventory. `mc-kb.sh --help` prints the layout,
# the verbs and the exit codes.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH
caller_umask=$(umask)
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
claude_dir=${CLAUDE_DIR:-$HOME/.claude}
LOGS="decisions undo would-have locks"
STORES="index.md followups.tsv sources.tsv mechanisms.tsv proposals.tsv"
tab=$(printf '\t')
MECH_HEADER="# kind${tab}mechanism${tab}where${tab}source"
PROP_HEADER="# id${tab}opened${tab}pattern${tab}shape${tab}subject${tab}target${tab}evidence${tab}kind${tab}mechanism${tab}where${tab}source${tab}change${tab}cadence${tab}intervene${tab}cost${tab}off${tab}state${tab}trigger${tab}closed"
scratch=''
TMP=''
TMP2=''
TMP3=''
on_exit() {
  pw_lock_release_all
  [ -z "$TMP" ] || rm -f "$TMP"
  [ -z "$TMP2" ] || rm -f "$TMP2"
  [ -z "$TMP3" ] || rm -f "$TMP3"
  [ -z "$scratch" ] || rm -rf "$scratch"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

help_text() {
  cat <<'EOF'
mc-kb.sh — a mission-control program's knowledge base: the layout under the
program home (scripts/mc-program.sh resolves it, never inside one of the
program's repositories), its index, capped reads, the append-only logs,
the follow-up ledger, the source table and the mechanism inventory.

Layout, under <home>/kb/:
  index.md         one line per entry, "- `<path>`: <summary>", loaded
                   whole within mission_control_kb_index_budget lines
  <duty dir>/      one per armed duty, named by its catalog `files` field
  <log>-<YYYY-MM>.log
                   monthly segments of the decisions, undo, would-have and
                   locks logs: append-only, one entry per line,
                   id<TAB>ts<TAB>subject<TAB>act<TAB>target<TAB>grounds
                   <TAB>reversal<TAB>duty; the id is
                   <log>-<YYYYMM>-<n>, the subject free text, the reversal
                   `none` or `argv:` and the command's words with `%` and
                   space percent-encoded, the duty a catalog duty's id or
                   `-`; the locks log records each dead holder's lock
                   released, under the locked file's kb/ path
  followups.tsv    id<TAB>opened<TAB>owner<TAB>trigger<TAB>state<TAB>text
                   <TAB>evidence<TAB>closed; a trigger is date:<YYYY-MM-DD>
                   or event:<name>
  sources.tsv      name<TAB>kind<TAB>watermark<TAB>ref; kind living (the
                   watermark is the epoch second it was last refreshed) or
                   consumed (the watermark is how far it was consumed, in
                   the source's own terms); an omitted watermark records
                   the current epoch second for either kind
  mechanisms.tsv   kind<TAB>mechanism<TAB>where<TAB>source
  proposals.tsv    the mechanization proposal record
                   (scripts/mc-proposals.sh --help holds its columns)
Every store's first line carries its format field ("# format: 1", or
"<!-- format: 1 -->" in index.md, and in each segment's .seal sidecar);
a store with a missing or unknown format is refused and named. Specs and
tickets are cited by link, never copied (scripts/check-kb-copies.sh).

A segment is never rewritten: its sidecar records the length and checksum
of what has been appended, and an append refuses a segment whose recorded
prefix changed, a segment with entries and no sidecar, and a sidecar whose
segment is gone. Bytes past the recorded length that end mid-line are an
append a crash cut short, and the next append drops them, warning. The
checksum catches an accidental rewrite, not a deliberate one: the sidecar
is as writable as the segment. Every write after a store's creation holds
the file's lock (<file>.lock, scripts/lock-lib.sh), waiting at least
mission_control_kb_lock_wait seconds; a writer whose acquire breaks the
lock of a holder no longer running reports the release and logs it.

Usage (every verb takes --program <name> before its own options):
  init                              create the layout and the armed duties'
                                    directories; an empty directory of a
                                    disarmed duty is removed, a non-empty
                                    one reported and kept
  index                             print the index within its budget
  index-add <path> <summary>        index an entry, replacing its line
  read <path>                       print an indexed body within the entry
                                    cap (mission_control_kb_entry_cap bytes)
  append <decisions|undo|would-have> --subject <s> --act <text>
         [--target <t>] [--grounds <text>] [--duty <id>]
         [--no-reversal | -- <command>...]
                                    log an act and print its id; an undo
                                    entry states its reversal or that it
                                    has none, a would-have entry its duty;
                                    the acts reverting, reverted and revert
                                    failed are revert's own
  query <decisions|undo|would-have|locks> --subject <s>
                                    the entries for a subject, every
                                    segment, the subject matched with ASCII
                                    case folded, blank runs collapsed and
                                    ends trimmed (the rule store's key)
  entries <decisions|undo|would-have|locks>
                                    every entry of a log, every segment,
                                    oldest first
  revert <undo-id> [--outcome <reverted|failed> --grounds <text>]
                                    run an entry's reversal once and print
                                    the id of the entry logging the
                                    outcome; a `reverting` entry is logged
                                    first, so an interrupted revert is
                                    never run again unasked, and --outcome
                                    settles one, running nothing. The reversal
                                    runs as its words through exec (never a
                                    shell, a function or a builtin), in the
                                    caller's directory and umask, its output
                                    on stderr; a bare first word naming a
                                    planwright script runs from this
                                    installation, any other through PATH,
                                    so record reversals with absolute paths
  lock <path> [--holder <pid>]      claim a file's write lock for a process
                                    (default the caller), printing the
                                    token; never a locks segment
  unlock <path> --token <token>     release it
  followup add --owner <o> --trigger <t> --text <text>
  followup due [--date <YYYY-MM-DD>] [--event <name>]...
  followup close <id> --evidence <text>
  followup list
  source set <name> --kind <living|consumed> --ref <ref> [--watermark <w>]
  inventory-refresh                 rewrite the mechanism inventory from the
                                    installed planwright and host surfaces
                                    and move its watermark, the two
                                    published together
  freshness                         <name><TAB><epoch><TAB><age-seconds> per
                                    store, log and living source

Exit codes: 0 done; 1 refused (a store's format, a cap, a budget, a held
lock, a rewritten segment, an entry not found, a failed reversal, a
program whose home does not resolve); 2 usage or an invalid value;
3 the program is not configured.
EOF
}
usage() {
  printf '%s\n' "usage: mc-kb.sh <verb> --program <name> [args]; verbs: init, index, index-add, read, append, query, entries, revert, lock, unlock, followup, source, inventory-refresh, freshness; mc-kb.sh --help for the layout and each verb" >&2
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
lbl() { printf 'kb/%s' "${1#"$KB"/}"; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

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
  need "the subject" "$1"
  [ "${#1}" -le 256 ] || bad "the subject is longer than 256 characters"
  case $1 in
    *[!\ ]*) ;;
    *) bad "the subject is blank" ;;
  esac
}
count_rows() { # count_rows <file>: ROWS, the entry lines, never a failed read's empty
  cr_n=$(grep -vc '^#' "$1")
  case $cr_n in
    "" | *[!0-9]*) refuse "cannot read $(lbl "$1")" ;;
  esac
  ROWS=$cr_n
}
ends_in_newline() { [ ! -s "$1" ] || [ "$(tail -c 1 "$1" | wc -l | tr -d ' ')" -eq 1 ]; }
now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
now_epoch() { date -u '+%s'; }
# shell-gnu-only-flag: BSD stat -f is the fallback when GNU stat -c fails
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
ensure_scratch() {
  [ -n "$scratch" ] || scratch=$(mktemp -d "${TMPDIR:-/tmp}/mc-kb.XXXXXX") || refuse "cannot create a scratch directory"
}

# int_knob <key>: set KNOB to a positive integer knob through config-get.sh
# --layers, the highest valid layer winning; an invalid adopter or
# machine-local value is warned about and the next lower layer read, an
# invalid repo-tracked or core value fails.
KNOB=''
int_knob() {
  # shell-config-pin: mission control's knobs live in the overlay layers of the checkout it runs from
  ik_lines=$(/bin/sh "$script_dir/config-get.sh" --layers "$1")
  case $? in
    0) ;;
    3) refuse "$1 is not set (broken install)" ;;
    *) refuse "reading $1 failed" ;;
  esac
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
      adopter | machine-local) say "warning: the $ik_layer value of $1 is not a positive integer of at most nine digits; degrading to the next lower layer" ;;
      *) refuse "the $ik_layer value of $1 is not a positive integer of at most nine digits" ;;
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
  kb_contained
}
# kb_contained: the knowledge base is a real directory in the program home,
# never a link that would carry every store somewhere else.
kb_contained() {
  [ ! -L "$KB" ] || refuse "$KB is a symlink; the knowledge base is a directory in the program home"
  kc_kb=$(cd "$KB" && pwd -P) || refuse "cannot read $KB"
  kc_home=$(cd "$HOME_DIR" && pwd -P) || refuse "cannot read $HOME_DIR"
  [ "$kc_kb" = "$kc_home/kb" ] || refuse "$KB resolves outside the program home"
}

# format_line_ok <line>: the line is a known format field, either form.
format_line_ok() {
  case $1 in
    "# format: $FORMAT" | "<!-- format: $FORMAT -->") return 0 ;;
  esac
  return 1
}
# check_format <file>: the store's first line names a known format.
check_format() {
  [ ! -L "$1" ] || refuse "store $(lbl "$1") is a symlink"
  [ -f "$1" ] || refuse "store $(lbl "$1") is missing (run mc-kb.sh init --program $PROGRAM)"
  cf_first=$(head -n 1 "$1")
  format_line_ok "$cf_first" && return 0
  case $cf_first in
    "<!-- format: "*" -->")
      cf_v=${cf_first#"<!-- format: "}
      cf_v=${cf_v%" -->"}
      ;;
    "# format: "*) cf_v=${cf_first#"# format: "} ;;
    *) refuse "store $(lbl "$1") has no format field" ;;
  esac
  refuse "store $(lbl "$1") has unknown format $cf_v"
}

# new_store <file> <header lines...>: create the store when absent, never
# clobbering one a concurrent init created first, then check its format.
new_store() {
  ns_file=$1
  shift
  if [ ! -e "$ns_file" ] && ! [ -L "$ns_file" ]; then
    (
      set -C
      printf '%s\n' "$@" >"$ns_file"
    ) 2>/dev/null
  fi
  check_format "$ns_file"
}

# Staged rewrites: tmp_for names a fresh dot-named sibling (a leading dot
# keeps it out of every path kb_path admits, and on_exit removes it), the
# caller writes TMP, then publish renames it over the store once its format
# line checks; discard_staged abandons it, refuse_staged abandons it and
# refuses.
tmp_for() {
  TMP=${1%/*}/.${1##*/}.$$.new
  rm -f "$TMP"
}
discard_staged() {
  [ -z "$TMP" ] || rm -f "$TMP"
  TMP=''
}
refuse_staged() { # refuse_staged <file>
  discard_staged
  refuse "cannot rewrite $(lbl "$1")"
}
publish() { # publish <file>
  format_line_ok "$(head -n 1 "$TMP" 2>/dev/null)" || refuse_staged "$1"
  mv -f "$TMP" "$1" || refuse_staged "$1"
  TMP=''
}

# kb_path <path>: validate a knowledge-base relative path and set KP to it
# absolute and KREL to its canonical relative form, which the store and locks
# guards check; the path must stay inside the knowledge base, symlinks
# resolved.
KP=''
KREL=''
kb_path() {
  case $1 in
    "" | /* | .* | -* | */.* | *//* | */) bad "invalid knowledge-base path: $1" ;;
    *[!A-Za-z0-9._/-]*) bad "invalid knowledge-base path: $1" ;;
  esac
  case $1 in
    */*) kp_dir=${1%/*} ;;
    *) kp_dir=. ;;
  esac
  kp_real=$(cd "$KB/$kp_dir" 2>/dev/null && pwd -P) || refuse "no such directory in the knowledge base: $kp_dir"
  kp_kb=$(cd "$KB" && pwd -P) || refuse "cannot read $KB"
  case $kp_real in
    "$kp_kb") KREL=${1##*/} ;;
    "$kp_kb"/*) KREL=${kp_real#"$kp_kb"/}/${1##*/} ;;
    *) refuse "$1 resolves outside the knowledge base" ;;
  esac
  KP=$KB/$1
}

# is_store <path>: a store, log segment or lock at the top level, compared
# with case folded for case-insensitive filesystems.
is_store() {
  is_p=$(lower "$1")
  case $is_p in
    */*) return 1 ;;
    *.log | *.lock) return 0 ;;
  esac
  for is_s in $STORES; do
    [ "$is_p" != "$is_s" ] || return 0
  done
  return 1
}

# A body is a regular file inside a duty's directory or the knowledge base's
# top level, never a symlink, a log or one of the stores.
body_path() {
  kb_path "$1"
  ! is_store "$KREL" || refuse "$1 is a store, read through its own verb"
  [ ! -L "$KP" ] || refuse "$1 is a symlink; a body is never read through a link"
  [ -f "$KP" ] || refuse "no such entry: $1"
}

# --- locks -------------------------------------------------------------------

LOCK_WAIT=''
lock_wait() {
  [ -n "$LOCK_WAIT" ] && return 0
  int_knob mission_control_kb_lock_wait
  LOCK_WAIT=$KNOB
}

# claim <file> [<holder-pid>]: take <file>'s write lock for this process, or
# for <holder-pid>, waiting at least the lock wait; every dead owner the
# acquire calls removed on the way (PW_LOCK_BROKEN) is reported and logged,
# a refusal included. Sets CLAIM_TOKEN.
CLAIM_TOKEN=''
claim() {
  local cl_lock cl_label cl_start cl_dead cl_tok cl_rc cl_pid
  cl_lock=$1.lock
  cl_label=$(lbl "$1")
  lock_wait
  cl_start=$SECONDS
  cl_dead=''
  while :; do
    # About a second of lock-lib's own spin per pass, so the holder is probed
    # at its stride rather than on every try.
    if [ $# -ge 2 ]; then
      pw_lock_acquire_for "$cl_lock" "$2" 50
    else
      pw_lock_acquire "$cl_lock" 50
    fi
    cl_rc=$?
    while IFS= read -r cl_tok; do
      [ -n "$cl_tok" ] || continue
      cl_pid=${cl_tok%%-*}
      case $cl_pid in
        "" | *[!0-9]*) cl_pid='?' ;;
      esac
      cl_dead="$cl_dead $cl_pid"
    done <<EOF
$PW_LOCK_BROKEN
EOF
    [ "$cl_rc" -eq 1 ] || break
    if [ $((SECONDS - cl_start)) -gt "$LOCK_WAIT" ]; then
      report_releases "$1" "$cl_label" "$cl_dead"
      cl_tok=$(pw_lock_owner "$cl_lock")
      refuse "$cl_label is locked by pid ${cl_tok%%-*}; gave up after ${LOCK_WAIT}s"
    fi
  done
  if [ "$cl_rc" -ne 0 ]; then
    report_releases "$1" "$cl_label" "$cl_dead"
    refuse "cannot take the lock on $cl_label (an unwritable directory, or a path lock-lib.sh refuses)"
  fi
  CLAIM_TOKEN=$PW_LOCK_TOKEN
  report_releases "$1" "$cl_label" "$cl_dead"
}

# report_releases <file> <label> <pids>: report and log each dead holder's
# release.
report_releases() {
  for rr_pid in $3; do
    say "released the lock on $2 left by pid $rr_pid, which is no longer running"
    log_release "$2" "$rr_pid"
  done
}

# log_release <label> <pid>: log a dead holder's release. In a subshell, so a
# locks log that cannot be written warns rather than failing the write that
# broke the lock, and so the nested claim cannot touch this shell's globals.
# A subshell does not inherit on_exit, so its own trap releases the locks
# segment unless the append got as far as releasing it. Releasing it twice
# would unlink an outer hold: logging the release of the locks segment's own
# dead holder nests here, inside the append that broke it. Releasing
# everything would also drop the lock the parent is writing under, which the
# subshell's copy of the lock registry names too.
log_release() {
  (
    lr_done=''
    lr_seg=$KB/locks-$(date -u '+%Y-%m').log
    trap '[ -n "$lr_done" ] || pw_lock_release "$lr_seg.lock" 2>/dev/null; discard_staged' EXIT
    do_append locks "$1" "released a dead holder's lock" "pid $2" "the holder is not running" none -
    lr_done=1
  ) || say "warning: the release on $1 could not be logged"
}
release() { pw_lock_release "$1.lock" || refuse "cannot release the lock on $(lbl "$1")"; }

# --- logs --------------------------------------------------------------------

log_ok() { # log_ok <name> <allowed...>
  lo_name=$1
  shift
  for lo_a in "$@"; do
    [ "$lo_name" != "$lo_a" ] || return 0
  done
  bad "unknown log: $lo_name (one of: $*)"
}

seal_of() { # seal_of <segment>
  sf_base=${1##*/}
  printf '%s\n' "${1%/*}/.${sf_base%.log}.seal"
}

# seal_ok <segment>: the prefix the last append recorded is unchanged; sets
# SEALED to its length (0 for a header-only segment with no sidecar yet).
SEALED=0
seal_ok() {
  so_seal=$(seal_of "$1")
  SEALED=0
  if [ ! -f "$so_seal" ]; then
    count_rows "$1"
    [ "$ROWS" -eq 0 ]
    return
  fi
  check_format "$so_seal"
  so_rec=$(sed -n 2p "$so_seal")
  so_len=${so_rec%% *}
  so_sum=${so_rec#* }
  case $so_len in
    "" | *[!0-9]*) return 1 ;;
  esac
  so_size=$(wc -c <"$1" | tr -d ' ')
  [ "$so_size" -ge "$so_len" ] || return 1
  [ "$(head -c "$so_len" "$1" | cksum | awk '{ print $1 }')" = "$so_sum" ] || return 1
  SEALED=$so_len
}
seal_write() {
  sw_seal=$(seal_of "$1")
  tmp_for "$sw_seal"
  printf '# format: %s\n%s %s\n' "$FORMAT" "$(wc -c <"$1" | tr -d ' ')" "$(cksum <"$1" | awk '{ print $1 }')" >"$TMP" \
    || refuse_staged "$sw_seal"
  publish "$sw_seal"
}

# do_append <log> <subject> <act> <target> <grounds> <reversal> <duty>:
# append one entry under the segment's lock, setting LAST_ID; DA_MONTH, when
# set, names the segment's month instead of the current one.
LAST_ID=''
do_append() {
  local da_month da_seg da_id
  da_month=${DA_MONTH:-$(date -u '+%Y-%m')}
  da_seg=$KB/$1-$da_month.log
  claim "$da_seg"
  if [ -f "$da_seg" ] || [ -L "$da_seg" ]; then
    check_format "$da_seg"
    seal_ok "$da_seg" || refuse "segment $(lbl "$da_seg") was rewritten since its last append; logs are append-only"
    if ! ends_in_newline "$da_seg"; then
      # Unsealed bytes ending mid-line: an append a crash cut short.
      tmp_for "$da_seg"
      if [ "$SEALED" -gt 0 ]; then
        head -c "$SEALED" "$da_seg" >"$TMP" || refuse_staged "$da_seg"
      else
        printf '# format: %s\n' "$FORMAT" >"$TMP" || refuse_staged "$da_seg"
      fi
      publish "$da_seg"
      say "warning: dropped a partial line a crash left at the end of $(lbl "$da_seg")"
    fi
    # A header a crash left unsealed is sealed before the first entry lands.
    [ -f "$(seal_of "$da_seg")" ] || seal_write "$da_seg"
  else
    [ ! -e "$(seal_of "$da_seg")" ] || refuse "segment $(lbl "$da_seg") is gone but its seal remains; logs are append-only"
    printf '# format: %s\n' "$FORMAT" >"$da_seg" || refuse "cannot write $(lbl "$da_seg")"
    seal_write "$da_seg"
  fi
  count_rows "$da_seg"
  da_id=$1-${da_month%-*}${da_month#*-}-$((ROWS + 1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$da_id" "$(now_iso)" "$2" "$3" "${4:--}" "${5:--}" "$6" "${7:--}" >>"$da_seg" \
    || refuse "cannot append to $(lbl "$da_seg")"
  seal_write "$da_seg"
  release "$da_seg"
  LAST_ID=$da_id
}

# segment_list <log> [<from-month>]: SEGS, the log's segments oldest first,
# from the given YYYY-MM on when one is given.
segment_list() {
  SEGS=()
  set +f
  for sg in "$KB/$1"-[0-9][0-9][0-9][0-9]-[0-9][0-9].log; do
    [ -f "$sg" ] || continue
    if [ $# -ge 2 ]; then
      sg_month=${sg%.log}
      sg_month=${sg_month##*-}
      sg_year=${sg%-*.log}
      sg_year=${sg_year##*-}
      [ ! "$sg_year-$sg_month" \< "$2" ] || continue
    fi
    SEGS[${#SEGS[@]}]=$sg
  done
  set -f
}

# awk_segments <awk-program>: run the program over SEGS after each segment's
# format line checks; the caller passes the program's inputs in the
# environment.
awk_segments() {
  [ "${#SEGS[@]}" -gt 0 ] || return 0
  for as_seg in "${SEGS[@]}"; do check_format "$as_seg"; done
  awk -F '\t' "$1" "${SEGS[@]}"
}

# The subject key the rule store groups on: ASCII case folded, blank runs
# collapsed, ends trimmed.
SUBJECT_KEY_AWK='function key(s) { s = tolower(s); gsub(/[ ]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }'

# encode_word <word>: percent-encode `%` and space.
encode_word() {
  ew=${1//%/%25}
  printf '%s' "${ew// /%20}"
}

# --- verbs -------------------------------------------------------------------

v_init() {
  [ $# -eq 0 ] || usage
  duty_rows=$(/bin/bash "$script_dir/mc-duties.sh" files --program "$PROGRAM") || refuse "the duties of program $PROGRAM do not resolve"
  [ ! -L "$KB" ] || refuse "$KB is a symlink; the knowledge base is a directory in the program home"
  mkdir -p "$KB" || refuse "cannot create $KB"
  kb_contained
  new_store "$KB/index.md" "<!-- format: $FORMAT -->"
  new_store "$KB/followups.tsv" "# format: $FORMAT" "# id${tab}opened${tab}owner${tab}trigger${tab}state${tab}text${tab}evidence${tab}closed"
  new_store "$KB/sources.tsv" "# format: $FORMAT" "# name${tab}kind${tab}watermark${tab}ref"
  new_store "$KB/mechanisms.tsv" "# format: $FORMAT" "$MECH_HEADER"
  new_store "$KB/proposals.tsv" "# format: $FORMAT" "$PROP_HEADER"
  armed=''
  while IFS="$tab" read -r d_id d_dir; do
    [ -n "$d_id" ] || continue
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
  check_format "$KB/index.md"
  int_knob mission_control_kb_index_budget
  budget=$KNOB
  lines=$(awk 'NR > 1 && $0 != "" { n++ } END { print n + 0 }' "$KB/index.md")
  B=$budget awk 'NR > 1 && $0 != "" && ++n <= ENVIRON["B"] + 0' "$KB/index.md"
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
  check_format "$KB/index.md"
  int_knob mission_control_kb_index_budget
  budget=$KNOB
  claim "$KB/index.md"
  tmp_for "$KB/index.md"
  {
    head -n 1 "$KB/index.md" \
      && P="- \`$1\`: " awk 'NR > 1 && index($0, ENVIRON["P"]) != 1 && $0 != ""' "$KB/index.md" \
      && printf '%s\n' "- \`$1\`: $2"
  } >"$TMP" || refuse_staged "$KB/index.md"
  lines=$(awk 'NR > 1 && $0 != "" { n++ } END { print n + 0 }' "$TMP")
  if [ "$lines" -gt "$budget" ]; then
    discard_staged
    refuse "indexing $1 would put the index at $lines lines, over its budget of $budget (mission_control_kb_index_budget); retire an entry or raise the knob"
  fi
  publish "$KB/index.md"
  release "$KB/index.md"
}

v_read() {
  [ $# -eq 1 ] || usage
  require_kb
  check_format "$KB/index.md"
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
  log_ok "$log" decisions undo would-have
  subject='' act='' target='' grounds='' duty='' rev=''
  while [ $# -gt 0 ]; do
    case $1 in
      --subject | --act | --target | --grounds | --duty)
        [ $# -ge 2 ] || usage
        case $1 in
          --subject) subject=$2 ;;
          --act) act=$2 ;;
          --target) target=$2 ;;
          --grounds) grounds=$2 ;;
          --duty) duty=$2 ;;
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
  subject_ok "$subject"
  need "--act" "$act"
  case $act in
    reverting | reverted | "revert failed") bad "the act '$act' is recorded by revert only" ;;
  esac
  text_ok "--target" "$target"
  text_ok "--grounds" "$grounds"
  if [ -n "$duty" ]; then
    kebab_ok "--duty" "$duty"
    /bin/bash "$script_dir/mc-duties.sh" get "$duty" id >/dev/null 2>&1 || bad "--duty names no duty in the catalog: $duty"
  elif [ "$log" = would-have ]; then
    bad "a would-have entry names its duty (--duty)"
  fi
  if [ -z "$rev" ]; then
    [ "$log" != undo ] || bad "an undo entry states its reversal (-- <command>...) or --no-reversal"
    rev=none
  fi
  require_kb
  do_append "$log" "$subject" "$act" "$target" "$grounds" "$rev" "$duty"
  printf '%s\n' "$LAST_ID"
}

v_query() {
  [ $# -eq 3 ] && [ "$2" = --subject ] || usage
  # shellcheck disable=SC2086 # LOGS is a word list; globbing is off
  log_ok "$1" $LOGS
  subject_ok "$3"
  require_kb
  segment_list "$1"
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  S=$3 awk_segments "$SUBJECT_KEY_AWK"'
    BEGIN { want = key(ENVIRON["S"]) }
    !/^#/ && key($3) == want'
}

v_entries() {
  [ $# -eq 1 ] || usage
  # shellcheck disable=SC2086 # LOGS is a word list; globbing is off
  log_ok "$1" $LOGS
  require_kb
  segment_list "$1"
  awk_segments '!/^#/'
}

v_revert() {
  [ $# -eq 1 ] || [ $# -eq 5 ] || usage
  r_id=$1
  r_outcome='' r_grounds=''
  if [ $# -eq 5 ]; then
    [ "$2" = --outcome ] && [ "$4" = --grounds ] || usage
    case $3 in
      reverted) r_outcome=reverted ;;
      failed) r_outcome="revert failed" ;;
      *) bad "--outcome is reverted or failed" ;;
    esac
    need "--grounds" "$5"
    r_grounds=$5
  fi
  case $r_id in
    undo-[0-9][0-9][0-9][0-9][0-9][0-9]-[1-9]*) ;;
    *) bad "invalid undo entry id: $r_id" ;;
  esac
  case ${r_id#undo-??????-} in
    *[!0-9]*) bad "invalid undo entry id: $r_id" ;;
  esac
  require_kb
  entry_month=${r_id#undo-}
  entry_month=${entry_month%%-*}
  entry_month=${entry_month%??}-${entry_month#????}
  entry_seg=$KB/undo-$entry_month.log
  [ -f "$entry_seg" ] || refuse "no undo entry $r_id"
  cur_month=$(date -u '+%Y-%m')
  cur_seg=$KB/undo-$cur_month.log
  # The outcome check and the entry that follows it are one critical section
  # on the segment that entry lands in (its month pinned), so two reverts of
  # one entry cannot both proceed; the reversal then runs outside every lock.
  claim "$cur_seg"
  check_format "$entry_seg"
  seal_ok "$entry_seg" || refuse "segment $(lbl "$entry_seg") was rewritten since its last append; its reversals are not run"
  entry=$(head -c "$SEALED" "$entry_seg" | I=$r_id awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print; exit }')
  [ -n "$entry" ] || refuse "no undo entry $r_id"
  IFS=$tab read -r _ _ r_subject _ _ _ r_rev r_duty <<EOF
$entry
EOF
  case $r_rev in
    argv:?*) ;;
    *) refuse "undo entry $r_id records no reversal" ;;
  esac
  segment_list undo "$entry_month"
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  last_outcome=$(I=$r_id awk_segments '!/^#/ && $5 == ENVIRON["I"] && ($4 == "reverting" || $4 == "reverted" || $4 == "revert failed") { a = $4 } END { print a }') \
    || refuse "the undo log could not be read"
  if [ -n "$r_outcome" ]; then
    # Settling a revert that logged no outcome: the operator states what the
    # reversal did; nothing runs.
    [ "$last_outcome" = reverting ] || refuse "undo entry $r_id has no revert awaiting an outcome"
    DA_MONTH=$cur_month do_append undo "$r_subject" "$r_outcome" "$r_id" "$r_grounds" none "${r_duty:--}"
    release "$cur_seg"
    printf '%s\n' "$LAST_ID"
    return 0
  fi
  case $last_outcome in
    reverted) refuse "undo entry $r_id was already reverted" ;;
    reverting) refuse "a revert of undo entry $r_id started and logged no outcome; check whether its reversal ran, then settle it with revert $r_id --outcome reverted|failed --grounds <what you found>" ;;
  esac
  DA_MONTH=$cur_month do_append undo "$r_subject" reverting "$r_id" "-" none "${r_duty:--}"
  release "$cur_seg"
  args=()
  IFS=' '
  for w in ${r_rev#argv:}; do
    w=${w//%20/ }
    args[${#args[@]}]=${w//%25/%}
  done
  unset IFS
  case ${args[0]} in
    */*) ;;
    *)
      if [ -f "$script_dir/${args[0]}" ] && [ -x "$script_dir/${args[0]}" ]; then
        args[0]=$script_dir/${args[0]}
      fi
      ;;
  esac
  (
    umask "$caller_umask"
    exec -- "${args[@]}"
  ) >&2
  r_rc=$?
  if [ "$r_rc" -eq 0 ]; then
    r_act=reverted
  else
    r_act="revert failed"
  fi
  # In a subshell, so a log that cannot be written is reported as such rather
  # than as a failed revert: the reversal has already run.
  if ! r_logged=$(
    trap 'pw_lock_release_all; discard_staged' EXIT
    DA_MONTH=$cur_month do_append undo "$r_subject" "$r_act" "$r_id" "exit $r_rc" none "${r_duty:--}"
    printf '%s' "$LAST_ID"
  ); then
    refuse "the reversal of $r_id ran (exit $r_rc) but its outcome could not be logged; the entry stays awaiting an outcome (revert $r_id --outcome)"
  fi
  [ "$r_rc" -eq 0 ] || refuse "the reversal of $r_id failed (exit $r_rc); logged as $r_logged"
  printf '%s\n' "$r_logged"
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
  case $(lower "$KREL") in
    locks-*) bad "the locks log is written only by the knowledge base itself" ;;
  esac
  claim "$KP" "$holder"
  printf '%s\n' "$CLAIM_TOKEN"
}

v_unlock() {
  [ $# -eq 3 ] && [ "$2" = --token ] || usage
  need "--token" "$3"
  require_kb
  kb_path "$1"
  pw_lock_release_token "$KP.lock" "$3"
  case $? in
    0) ;;
    1) refuse "$1 is not locked by that token" ;;
    *) refuse "the lock on $1 could not be released and is still held" ;;
  esac
}

v_followup() {
  [ $# -ge 1 ] || usage
  sub=$1
  shift
  fu=$KB/followups.tsv
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
      require_kb
      check_format "$fu"
      claim "$fu"
      ends_in_newline "$fu" || refuse "kb/followups.tsv ends in a partial line; repair it by hand"
      count_rows "$fu"
      n=$((ROWS + 1))
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
      require_kb
      check_format "$fu"
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
      require_kb
      check_format "$fu"
      claim "$fu"
      state=$(I=$id awk -F '\t' '!/^#/ && $1 == ENVIRON["I"] { print $5; exit }' "$fu")
      [ -n "$state" ] || refuse "no follow-up $id"
      [ "$state" = open ] || refuse "follow-up $id is already $state"
      tmp_for "$fu"
      I=$id V=$evidence T=$(now_iso) awk -F '\t' -v OFS='\t' '
        !/^#/ && $1 == ENVIRON["I"] { $5 = "closed"; $7 = ENVIRON["V"]; $8 = ENVIRON["T"] }
        { print }
      ' "$fu" >"$TMP" || refuse_staged "$fu"
      publish "$fu"
      release "$fu"
      ;;
    list)
      [ $# -eq 0 ] || usage
      require_kb
      check_format "$fu"
      grep -v '^#' "$fu"
      ;;
    *) usage ;;
  esac
  return 0
}

# set_source <name> <kind> <watermark> <ref>: replace the source's row.
set_source() {
  ss=$KB/sources.tsv
  check_format "$ss"
  claim "$ss"
  tmp_for "$ss"
  {
    N=$1 awk -F '\t' '/^#/ || $1 != ENVIRON["N"]' "$ss" \
      && printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  } >"$TMP" || refuse_staged "$ss"
  publish "$ss"
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
  if [ "$kind" = living ]; then
    case $wm in
      *[!0-9]*) bad "a living source's watermark is an epoch second" ;;
    esac
  fi
  require_kb
  set_source "$name" "$kind" "$wm" "$ref"
}

# inventory_rows: kind<TAB>mechanism<TAB>where<TAB>source, one per mechanism
# read from the installed planwright and host surfaces.
inventory_rows() {
  ensure_scratch
  core=$(/bin/sh "$script_dir/resolve-root.sh" install 2>/dev/null) || core=$script_dir/..
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
    printf '%s\n' "$steps" | catalog_rows catalog-step steps "scripts/resolve-catalog.sh steps"
  else
    say "warning: the steps catalog does not resolve; no catalog-step rows"
  fi
  if duties=$(/bin/bash "$script_dir/mc-duties.sh" list 2>/dev/null); then
    printf '%s\n' "$duties" | catalog_rows duty duties "scripts/mc-duties.sh list"
  else
    say "warning: the duties catalog does not resolve; no duty rows"
  fi
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
      # Into a file first: jq streams, so rows before a failure would land.
      if F=$f jq -r '
        def clean: tostring | gsub("[[:cntrl:]]"; "?");
        ($ENV.F | clean) as $f
        | ((.hooks // {}) | to_entries[] | (.key | clean) as $e | (.value // [])[]
          | ["hook", ($e + " " + ((.matcher // "*") | clean)), $f, $f]),
        ((.permissions // {}) | to_entries[] | select(.key == "allow" or .key == "ask" or .key == "deny")
          | .key as $l | (.value // [])[] | ["permission", ($l + ": " + (. | clean)), $f, $f])
        | @tsv' "$f" >"$scratch/settings" 2>/dev/null; then
        cat "$scratch/settings"
      else
        say "warning: $f does not parse as settings JSON; skipped"
      fi
    done
    unset IFS
  else
    say "warning: jq is not on PATH; no hook or permission rows"
  fi
}

# catalog_rows <kind> <catalog> <source>: inventory rows from a catalog's
# <id><TAB><layer> lines on stdin.
catalog_rows() {
  K=$1 C=$2 S=$3 awk -F '\t' 'NF >= 2 && $1 != "" {
    gsub(/[[:cntrl:]]/, "?", $1); gsub(/[[:cntrl:]]/, "?", $2)
    printf "%s\t%s\tthe %s %s catalog\t%s\n", ENVIRON["K"], $1, $2, ENVIRON["C"], ENVIRON["S"]
  }'
}

# The kinds the host offers with no local record to read (a routine lives in
# the host's scheduler) or that this program's own stores provide.
capability_rows() {
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
  check_format "$inv"
  check_format "$KB/sources.tsv"
  ensure_scratch
  inventory_rows >"$scratch/raw" || refuse "the mechanism inventory could not be read"
  read_rows=$(awk -F '\t' 'NF == 4 { n++ } END { print n + 0 }' "$scratch/raw")
  [ "$read_rows" -gt 0 ] || refuse "no mechanism could be read from the installed surfaces; the stored inventory is kept"
  capability_rows >>"$scratch/raw" || refuse "the mechanism inventory could not be read"
  awk -F '\t' 'NF == 4' "$scratch/raw" | sort -u >"$scratch/rows" || refuse "the mechanism inventory could not be sorted"
  rows=$(grep -c . "$scratch/rows")
  # Both locks before either file moves, inventory then sources (the order
  # every writer takes them in), so the rows and their watermark land as a
  # pair and two refreshes never interleave.
  claim "$inv"
  claim "$KB/sources.tsv"
  wm=$(now_epoch)
  ss=$KB/sources.tsv
  tmp_for "$ss"
  ss_tmp=$TMP
  TMP2=$ss_tmp
  {
    awk -F '\t' '/^#/ || $1 != "mechanism-inventory"' "$ss" \
      && printf 'mechanism-inventory\tliving\t%s\tkb/mechanisms.tsv\n' "$wm"
  } >"$ss_tmp" || refuse_staged "$ss"
  format_line_ok "$(head -n 1 "$ss_tmp")" || refuse_staged "$ss"
  tmp_for "$inv"
  {
    printf '# format: %s\n# refreshed: %s\n%s\n' "$FORMAT" "$wm" "$MECH_HEADER" \
      && cat "$scratch/rows"
  } >"$TMP" || refuse_staged "$inv"
  # Both staged and checked; the two renames run back to back, and the old
  # inventory is kept aside so a failed second rename puts it back.
  inv_bak=${inv%/*}/.${inv##*/}.$$.bak
  TMP3=$inv_bak
  ln -f "$inv" "$inv_bak" || refuse_staged "$inv"
  publish "$inv"
  if ! mv -f "$ss_tmp" "$ss"; then
    mv -f "$inv_bak" "$inv"
    refuse "cannot rewrite kb/sources.tsv; the inventory was put back as it was"
  fi
  TMP2=''
  rm -f "$inv_bak"
  TMP3=''
  release "$ss"
  release "$inv"
  printf '%s\n' "$rows mechanisms"
}

v_freshness() {
  [ $# -eq 0 ] || usage
  require_kb
  now=$(now_epoch)
  for s in $STORES; do
    [ -f "$KB/$s" ] || continue
    t=$(mtime "$KB/$s") || continue
    printf '%s\t%s\t%s\n' "$s" "$t" "$((now - t))"
  done
  for l in $LOGS; do
    segment_list "$l"
    [ "${#SEGS[@]}" -gt 0 ] || continue
    t=$(mtime "${SEGS[${#SEGS[@]} - 1]}") || continue
    printf '%s\t%s\t%s\n' "log:$l" "$t" "$((now - t))"
  done
  check_format "$KB/sources.tsv"
  N=$now awk -F '\t' '!/^#/ && $2 == "living" && $3 ~ /^[0-9]+$/ { printf "source:%s\t%s\t%d\n", $1, $3, ENVIRON["N"] - $3 }' "$KB/sources.tsv"
}

# --- dispatch ----------------------------------------------------------------

[ $# -ge 1 ] || usage
case $1 in
  --help | -h | help)
    help_text
    exit 0
    ;;
esac
verb=$1
shift
# --program is taken where it leads the options, so an option's value that
# happens to read `--program` stays that option's value.
rest=()
opts_seen=0
while [ $# -gt 0 ]; do
  case $1 in
    --program)
      if [ "$opts_seen" -eq 0 ] && [ -z "$PROGRAM" ]; then
        [ $# -ge 2 ] || usage
        PROGRAM=$2
        shift 2
        continue
      fi
      ;;
    --)
      # `--` and everything after it (an append's reversal command), verbatim.
      for a in "$@"; do rest[${#rest[@]}]=$a; done
      set --
      continue
      ;;
    --*) opts_seen=1 ;;
  esac
  rest[${#rest[@]}]=$1
  shift
done
case $verb in
  init | index | index-add | read | append | query | entries | revert | lock | unlock | followup | source | inventory-refresh | freshness) ;;
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
  entries) v_entries "$@" ;;
  revert) v_revert "$@" ;;
  lock) v_lock "$@" ;;
  unlock) v_unlock "$@" ;;
  followup) v_followup "$@" ;;
  source) v_source "$@" ;;
  inventory-refresh) v_inventory_refresh "$@" ;;
  freshness) v_freshness "$@" ;;
esac
