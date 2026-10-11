#!/bin/sh
# quota-hold.sh — the per-vendor hold store and usage ledger. A vendor that
# refused with a quota, usage, or rate limit is held host-wide: each unit holding
# it is recorded in this store, never in tasks.md, until a resume releases the
# vendor. Beside the holds, each vendor keeps an
# append-only ledger of the requests sent to it, its answers and refusals, and
# the holds and resumes. docs/quota.md describes the operator surface.
#
# WHERE. <fleet-home>/quota/<vendor>/, the fleet home resolved by
# scripts/fleet-state.sh root and never committed:
#   hold.tsv    one line per holding unit, rewritten whole (temp + rename):
#               since  unit  step  reset  recognizer  reason  end
#   ledger.tsv  one appended line per event, rewritten only by prune:
#               time  event  unit  pr  head  recognizer  reason  end
#   pushed      the since of the hold whose attention event was last pushed,
#               rewritten whole under the lock while that hold is still the
#               vendor's, and removed by resume
#   lock        the vendor's lock, taken through scripts/lock-lib.sh for every
#               write, since several units on a host can meet one limit at once
# An absent optional field is `-`. The trailing `end` field is what lets a line
# torn by an embedded newline fail on read in both halves.
#
# FIELD GRAMMARS, checked on write (a failing argument is refused, exit 2,
# before any path or ledger use) and again on read (a failing line is skipped,
# never trusted):
#   vendor, step   the step-id grammar: ^[a-z][a-z0-9-]*$, at most 64 bytes
#   unit           the fleet-state field grammar: [A-Za-z0-9._=@:-], at most
#                  128 bytes, never `.` or `..`
#   recognizer     <vendor>.<name>, the vendor this line belongs to and a name
#                  in the step-id grammar
#   pr             a decimal PR number without a leading zero, at most 10 digits
#   head           40 or 64 lowercase hex characters
#   reset, time    epoch seconds, at most 15 digits
#   reason         screened as scripts/step-record.sh screens a record excerpt,
#                  flattened to one line, at most 512 bytes, no control byte
#
# Usage:
#   quota-hold.sh hold --vendor <id> --unit <unit> --step <id> --reason <text>
#       [--reset <epoch>] [--recognizer <id>] [--pr <n>] [--head <sha>] [--now <epoch>]
#     Record <unit> as held at <step>. A unit already holding the vendor is
#     renewed in place and keeps the time it first held. Appends a `hold` ledger
#     line, then pushes the attention event (vendor, reason, stated reset time,
#     resume command) through scripts/fleet-attention.sh notify, keyed on the
#     time the vendor's hold began and skipped once `pushed` names that time,
#     so one hold is one push whoever joins it.
#     Prints `held<TAB><vendor><TAB><since>`. Whatever the caller, holding and
#     pushing are one act of this verb. A hold records no refusal: a caller
#     whose request the vendor refused records that with `record` first.
#   quota-hold.sh resume --vendor <id> [--reason <text>] [--now <epoch>]
#     Release every unit holding the vendor, printing
#     `released<TAB><unit><TAB><step>` for each, and append one `resume` line
#     (reason `operator resume` unless given). A vendor not held is a no-op.
#   quota-hold.sh record --vendor <id> --event request|answer|refusal
#       [--unit <unit>] [--pr <n>] [--head <sha>] [--recognizer <id>]
#       [--reason <text>] [--now <epoch>]
#     Append one ledger line for a request sent, an answer received, or a
#     limit refusal.
#   quota-hold.sh status [--vendor <id>] [--now <epoch>]
#     Read-only and lockless. A store it cannot read fails the call with exit
#     6, never a vendor read as clear; lines printed before the failure are no
#     verdict. Prints `retention<TAB><days>`, then for the vendor
#     (or every vendor with a store directory):
#       vendor<TAB><id><TAB>held|clear<TAB><since|-><TAB><reset|-><TAB><units><TAB><reason|->
#       holder<TAB><id><TAB><unit><TAB><step><TAB><since>   one per holding unit
#       count<TAB><id><TAB><event><TAB><n>   for request, answer, refusal, hold,
#                                            resume, over the retention period
#     A held vendor's since is its earliest holder's, its reason that holder's,
#     and its reset the latest any holder stated.
#   quota-hold.sh prune [--vendor <id>] [--now <epoch>]
#     Drop ledger lines older than the retention period, and lines failing the
#     grammar, keeping the rest byte for byte.
#
# The retention period is the `quota_ledger_retention_days` knob (default 90),
# resolved through scripts/resolve-config-knob.sh; a value above 36500 reads as
# 36500. --now pins the clock for fixtures.
#
# Exit: 0 success · 2 usage, or a refused field · 3 the hold is recorded but its
# attention push failed (named on stderr) · 4/5 propagated from the knob
# resolver · 6 a runtime failure (no fleet home, the lock, a write, no clock, a
# store file or directory that is unreadable, not a regular file, or a symlink,
# which every verb refuses, status included).
#
# POSIX sh + awk on the bash 3.2 / BSD tooling floor. No eval. Every stored and
# read value is data.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

prog=quota-hold
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6

for dep in echo-safety.sh lock-lib.sh; do
  if [ ! -f "$script_dir/$dep" ] || [ ! -r "$script_dir/$dep" ]; then
    printf '%s\n' "quota-hold.sh: $dep is missing or unreadable (broken install)" >&2
    exit 6
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

FS="$script_dir/fleet-state.sh"
ATTN="$script_dir/fleet-attention.sh"
RESOLVER="$script_dir/resolve-config-knob.sh"
SR="$script_dir/step-record.sh"
TAB=$(printf '\t')
REASON_MAX=512
RETENTION_MAX=36500

work=""
CUR_TMP=""
cleanup() {
  pw_lock_release_all
  [ -z "$CUR_TMP" ] || rm -f "$CUR_TMP"
  [ -z "$work" ] || rm -rf "$work"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

usage() {
  printf '%s\n' "usage: quota-hold.sh hold|resume|record|status|prune [--vendor <id>] ... (see the script header)" >&2
  exit 2
}
die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

valid_id() {
  case $1 in
    "" | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}
# Byte-identical in intent to scripts/fleet-state.sh valid_field.
valid_unit() {
  case $1 in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}
valid_recognizer() {
  case $1 in
    "$2".*) valid_id "${1#"$2".}" ;;
    *) return 1 ;;
  esac
}
valid_pr() {
  case $1 in
    "" | 0* | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 10 ]
}
valid_head() {
  case $1 in
    "" | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}
valid_epoch() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# utc_iso <epoch>: best-effort UTC rendering, byte-identical to
# fleet-throttle.sh's helper.
utc_iso() {
  ui_v=$(TZ=UTC date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v=$(TZ=UTC date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v="epoch $1"
  printf '%s' "$ui_v"
}

# The read-side grammar, shared by every awk pass over a stored line. `v` is
# the vendor the file belongs to, grammar-checked before it reaches awk.
# shellcheck disable=SC2016 # awk source; awk expands its own fields
AWK_GRAMMAR='
function digits(s, max) { return s ~ /^[0-9]+$/ && length(s) <= max }
function sid(s) { return s ~ /^[a-z][a-z0-9-]*$/ && length(s) <= 64 }
function unit_ok(s) { return s ~ /^[A-Za-z0-9._=@:-]+$/ && s != "." && s != ".." && length(s) <= 128 }
function rec_ok(s) { return substr(s, 1, length(v) + 1) == v "." && sid(substr(s, length(v) + 2)) }
function pr_ok(s) { return s ~ /^[1-9][0-9]*$/ && length(s) <= 10 }
function head_ok(s) { return s ~ /^[0-9a-f]+$/ && (length(s) == 40 || length(s) == 64) }
function text_ok(s) { return s != "" && s !~ /[[:cntrl:]]/ && length(s) <= '"$REASON_MAX"' }
function hold_ok() {
  return NF == 7 && $7 == "end" && digits($1, 15) && unit_ok($2) && sid($3) &&
    ($4 == "-" || digits($4, 15)) && ($5 == "-" || rec_ok($5)) && text_ok($6)
}
function ledger_ok() {
  return NF == 8 && $8 == "end" && digits($1, 15) &&
    ($2 == "request" || $2 == "answer" || $2 == "refusal" || $2 == "hold" || $2 == "resume") &&
    ($3 == "-" || unit_ok($3)) && ($4 == "-" || pr_ok($4)) && ($5 == "-" || head_ok($5)) &&
    ($6 == "-" || rec_ok($6)) && text_ok($7)
}
'

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  hold) allowed="vendor unit step reason reset recognizer pr head now" ;;
  resume) allowed="vendor reason now" ;;
  record) allowed="vendor event unit pr head recognizer reason now" ;;
  status | prune) allowed="vendor now" ;;
  *) usage ;;
esac

vendor="" vendor_set=0 unit="" unit_set=0 step="" step_set=0 reason="" reason_set=0
reset="" reset_set=0 recognizer="" recognizer_set=0 pr="" pr_set=0 head="" head_set=0
event="" event_set=0 now="" now_set=0
while [ $# -gt 0 ]; do
  case $1 in
    --vendor | --unit | --step | --reason | --reset | --recognizer | --pr | --head | --event | --now) ;;
    *) usage ;;
  esac
  flag=${1#--}
  case " $allowed " in
    *" $flag "*) ;;
    *) die 2 "$verb takes no --$flag" ;;
  esac
  [ $# -ge 2 ] || usage
  case $flag in
    vendor) vendor=$2 vendor_set=1 ;;
    unit) unit=$2 unit_set=1 ;;
    step) step=$2 step_set=1 ;;
    reason) reason=$2 reason_set=1 ;;
    reset) reset=$2 reset_set=1 ;;
    recognizer) recognizer=$2 recognizer_set=1 ;;
    pr) pr=$2 pr_set=1 ;;
    head) head=$2 head_set=1 ;;
    event) event=$2 event_set=1 ;;
    now) now=$2 now_set=1 ;;
  esac
  shift 2
done

case $verb in
  hold) [ "$vendor_set$unit_set$step_set$reason_set" = 1111 ] || die 2 "hold needs --vendor, --unit, --step, and --reason" ;;
  resume) [ "$vendor_set" = 1 ] || die 2 "resume needs --vendor" ;;
  record) [ "$vendor_set$event_set" = 11 ] || die 2 "record needs --vendor and --event" ;;
esac
if [ "$vendor_set" = 1 ]; then
  valid_id "$vendor" || die 2 "--vendor is outside the step-id grammar"
fi
if [ "$unit_set" = 1 ]; then
  valid_unit "$unit" || die 2 "--unit is outside the fleet-state field grammar"
fi
if [ "$step_set" = 1 ]; then
  valid_id "$step" || die 2 "--step is outside the step-id grammar"
fi
if [ "$recognizer_set" = 1 ]; then
  valid_recognizer "$recognizer" "$vendor" || die 2 "--recognizer is not <vendor>.<name> for this vendor"
fi
if [ "$pr_set" = 1 ]; then
  valid_pr "$pr" || die 2 "--pr is not a decimal PR number"
fi
if [ "$head_set" = 1 ]; then
  valid_head "$head" || die 2 "--head is not a 40- or 64-character lowercase hex SHA"
fi
if [ "$reset_set" = 1 ]; then
  valid_epoch "$reset" || die 2 "--reset is not epoch seconds"
fi
if [ "$event_set" = 1 ]; then
  case $event in
    request | answer | refusal) ;;
    *) die 2 "--event is one of request, answer, refusal" ;;
  esac
fi
if [ "$reason_set" = 1 ] && [ "$verb" = hold ] && [ -z "$reason" ]; then
  die 2 "--reason is empty"
fi
if [ "$now_set" = 1 ]; then
  valid_epoch "$now" || die 2 "--now is not epoch seconds"
else
  now=$(date +%s)
  valid_epoch "$now" || die 6 "cannot read the clock"
fi

root=$("$FS" root) || die 6 "cannot resolve the fleet home"
store="$root/quota"

# clean_reason <text>: set REASON to the text screened as a record excerpt,
# flattened to one line and bounded, or `-` when nothing is left.
REASON=-
clean_reason() {
  [ -n "$work" ] || work=$(mktemp -d "${TMPDIR:-/tmp}/quota-hold.XXXXXX") || die 6 "cannot create a temporary directory"
  printf '%s\n' "$1" | tr '\t\r' '  ' >"$work/reason" || die 6 "cannot write a temporary file"
  cr_v=$(/bin/sh "$SR" excerpt "$work/reason") || die 6 "cannot screen the reason"
  REASON=$(printf '%s' "$cr_v" | tr '\n' ' ' | tr -d '\000-\037\177\200-\237' \
    | sed 's/   */ /g; s/^ //; s/ $//' | cut -c "1-$REASON_MAX")
  [ -n "$REASON" ] || REASON=-
}

# refuse_links <vendor>: an append follows a symlink, and a read through one
# reports a store that is not this one, so no verb goes through a planted link.
refuse_links() {
  for rl_p in "$store" "$store/$1" "$store/$1/ledger.tsv" "$store/$1/hold.tsv"; do
    [ ! -L "$rl_p" ] || die 6 "refusing a symlink in the vendor's store"
  done
}

vendor_dir() {
  vd_d="$store/$1"
  refuse_links "$1"
  mkdir -p "$vd_d" || die 6 "cannot create the vendor's store directory"
  printf '%s' "$vd_d"
}

lock_vendor() {
  lv_rc=0
  pw_lock_acquire "$1/lock" || lv_rc=$?
  [ "$lv_rc" -eq 0 ] || die 6 "cannot take the vendor's lock (lock-lib exit $lv_rc)"
}
unlock_vendor() {
  pw_lock_release "$1/lock" || die 6 "cannot release the vendor's lock"
}

# ledger_append <dir> <event> <unit> <pr> <head> <recognizer> <reason>
ledger_append() {
  # A write cut short leaves no newline, and the next line would join it. The
  # newline is counted, not compared: a substitution drops a NUL tail.
  if [ -s "$1/ledger.tsv" ] && [ "$(tail -c 1 "$1/ledger.tsv" | wc -l | tr -d ' ')" = 0 ]; then
    printf '\n' >>"$1/ledger.tsv" || die 6 "cannot append to the vendor's ledger"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tend\n' "$now" "$2" "$3" "$4" "$5" "$6" "$7" \
    >>"$1/ledger.tsv" || die 6 "cannot append to the vendor's ledger"
}

retention_days() {
  [ -x "$RESOLVER" ] || die 5 "the knob resolver is missing or not executable (broken install)"
  rd_v=$("$RESOLVER" --key quota_ledger_retention_days --type posint --fallback 90) || exit $?
  valid_epoch "$rd_v" || die 5 "the retention knob did not resolve to a number"
  if [ "${#rd_v}" -gt 5 ] || [ "$rd_v" -gt "$RETENTION_MAX" ]; then
    rd_v=$RETENTION_MAX
  fi
  printf '%s' "$rd_v"
}

# The vendors to read: the one named, or every store directory whose name is
# in the grammar.
list_vendors() {
  if [ "$vendor_set" = 1 ]; then
    printf '%s\n' "$vendor"
    return 0
  fi
  [ -d "$store" ] || return 0
  # A linked vendor directory is listed so the reader refuses it.
  find "$store" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | while IFS= read -r lv_p; do
    lv_n=${lv_p##*/}
    valid_id "$lv_n" && printf '%s\n' "$lv_n"
  done | sort
}

none() { [ -n "$1" ] && printf '%s' "$1" || printf '-'; }

case $verb in
  hold)
    clean_reason "$reason"
    dir=$(vendor_dir "$vendor") || exit 6
    lock_vendor "$dir"
    hf="$dir/hold.tsv"
    # mv onto a directory would land the store inside it and report a hold.
    [ ! -e "$hf" ] || [ -f "$hf" ] || die 6 "the vendor's hold store is not a regular file"
    pf="$dir/pushed"
    [ ! -e "$pf" ] || [ -f "$pf" ] || die 6 "the vendor's push record is not a regular file"
    src=/dev/null
    [ ! -f "$hf" ] || src=$hf
    CUR_TMP=$(mktemp "$dir/.hold.XXXXXX") || die 6 "cannot create a write temp"
    QH_UNIT=$unit QH_STEP=$step QH_RESET=$(none "$reset") QH_REC=$(none "$recognizer") QH_REASON=$REASON \
      awk -F "$TAB" -v v="$vendor" -v now="$now" "$AWK_GRAMMAR"'
      BEGIN { OFS = "\t"; u = ENVIRON["QH_UNIT"] }
      !hold_ok() { next }
      $2 == u {
        if (found++) next
        print $1, u, ENVIRON["QH_STEP"], ENVIRON["QH_RESET"], ENVIRON["QH_REC"], ENVIRON["QH_REASON"], "end"
        next
      }
      { print }
      END { if (!found) print now, u, ENVIRON["QH_STEP"], ENVIRON["QH_RESET"], ENVIRON["QH_REC"], ENVIRON["QH_REASON"], "end" }
    ' "$src" >"$CUR_TMP" || die 6 "cannot rewrite the hold store"
    since=$(awk -F "$TAB" '{ if (m == "" || $1 + 0 < m + 0) m = $1 } END { print m }' "$CUR_TMP")
    # The ledger line goes first, so a failed write leaves nothing held.
    ledger_append "$dir" hold "$unit" "$(none "$pr")" "$(none "$head")" "$(none "$recognizer")" "$REASON"
    mv -f "$CUR_TMP" "$hf" || die 6 "cannot commit the hold store"
    CUR_TMP=""
    unlock_vendor "$dir"

    if [ -n "$reset" ]; then
      when="stated reset $(utc_iso "$reset")"
    else
      when="no stated reset time"
    fi
    short=$(printf '%s' "$REASON" | cut -c 1-200)
    summary="quota hold: $vendor is held ($short); $when; resume with scripts/quota-hold.sh resume --vendor $vendor"
    printf 'held\t%s\t%s\n' "$vendor" "$since"
    if [ ! -x "$ATTN" ]; then
      printf '%s\n' "$prog: the hold on $vendor is recorded, but the attention helper is missing (broken install)" >&2
      exit 3
    fi
    # The notify key dedupes only while its push is pending, so a unit joining
    # after the push was relayed would push the same hold again.
    if [ -f "$pf" ] && [ "$(cat "$pf" 2>/dev/null)" = "$since" ]; then
      exit 0
    fi
    "$ATTN" notify "$summary" --key "quota-hold-$vendor-$since" >/dev/null || {
      printf '%s\n' "$prog: the hold on $vendor is recorded, but its attention push failed" >&2
      exit 3
    }
    # Recorded under the lock and only while this hold is still the vendor's:
    # a late write for a hold a resume already ended would silence the next.
    unrecorded=""
    if pw_lock_acquire "$dir/lock"; then
      cur="" cur_rc=0
      [ ! -f "$hf" ] || cur=$(awk -F "$TAB" -v v="$vendor" "$AWK_GRAMMAR"'
        hold_ok() && (m == "" || $1 + 0 < m + 0) { m = $1 } END { print m }' "$hf") || cur_rc=$?
      if [ "$cur_rc" != 0 ]; then
        unrecorded="the hold store could not be read"
      elif [ "$cur" = "$since" ]; then
        if CUR_TMP=$(mktemp "$dir/.pushed.XXXXXX") && printf '%s\n' "$since" >"$CUR_TMP" && mv -f "$CUR_TMP" "$pf"; then
          CUR_TMP=""
        else
          unrecorded="the record could not be written"
        fi
      fi
      pw_lock_release "$dir/lock" \
        || printf '%s\n' "$prog: the hold on $vendor is pushed, but the vendor's lock could not be released (retried on exit)" >&2
    else
      unrecorded="the vendor's lock could not be taken"
    fi
    [ -z "$unrecorded" ] || printf '%s\n' "$prog: the hold on $vendor is pushed, but the push was not recorded ($unrecorded); a unit joining it may push again" >&2
    exit 0
    ;;

  resume)
    if [ "$reason_set" = 1 ]; then
      clean_reason "$reason"
    else
      REASON="operator resume"
    fi
    refuse_links "$vendor"
    # A directory that cannot be searched hides the hold file it holds.
    for d in "$store" "$store/$vendor"; do
      [ ! -d "$d" ] || [ -x "$d" ] || die 6 "cannot search the vendor's store"
    done
    [ -e "$store/$vendor/hold.tsv" ] || exit 0
    dir=$(vendor_dir "$vendor") || exit 6
    lock_vendor "$dir"
    hf="$dir/hold.tsv"
    if [ ! -e "$hf" ]; then
      unlock_vendor "$dir"
      exit 0
    fi
    [ -f "$hf" ] || die 6 "the vendor's hold store is not a regular file"
    released=$(awk -F "$TAB" -v v="$vendor" "$AWK_GRAMMAR"'
      hold_ok() { printf "released\t%s\t%s\n", $2, $3 }' "$hf") || die 6 "cannot read the hold store"
    # The ledger line goes first, so a failed write releases nobody and the
    # resume can be retried.
    [ -z "$released" ] || ledger_append "$dir" resume - - - - "$REASON"
    rm -f "$dir/pushed" || die 6 "cannot clear the vendor's push record"
    rm -f "$hf" || die 6 "cannot clear the hold store"
    [ -z "$released" ] || printf '%s\n' "$released"
    unlock_vendor "$dir"
    exit 0
    ;;

  record)
    if [ "$reason_set" = 1 ]; then
      clean_reason "$reason"
    fi
    dir=$(vendor_dir "$vendor") || exit 6
    lock_vendor "$dir"
    ledger_append "$dir" "$event" "$(none "$unit")" "$(none "$pr")" "$(none "$head")" "$(none "$recognizer")" "$REASON"
    unlock_vendor "$dir"
    exit 0
    ;;

  status)
    days=$(retention_days) || exit $?
    cutoff=$((now - days * 86400))
    [ ! -L "$store" ] || die 6 "refusing a symlink in the vendor's store"
    # A directory that cannot be searched hides its files, and one that
    # cannot be listed hides its vendors: neither reads as clear.
    if [ -d "$store" ] && { [ ! -x "$store" ] || { [ "$vendor_set" != 1 ] && [ ! -r "$store" ]; }; }; then
      die 6 "cannot read the quota store"
    fi
    vendors=$(list_vendors)
    [ -n "$work" ] || work=$(mktemp -d "${TMPDIR:-/tmp}/quota-hold.XXXXXX") || die 6 "cannot create a temporary directory"
    printf 'retention\t%s\n' "$days"
    for v in $vendors; do
      refuse_links "$v"
      [ ! -d "$store/$v" ] || [ -x "$store/$v" ] || die 6 "cannot search the store of $v"
      hf="$store/$v/hold.tsv"
      lf="$store/$v/ledger.tsv"
      # A FIFO or a directory here would hang or skip the read. The second
      # test spares a hold file a resume removed between the first two.
      for f in "$hf" "$lf"; do
        if [ -e "$f" ] && [ ! -f "$f" ] && [ -e "$f" ]; then
          die 6 "a store file of $v is not a regular file"
        fi
      done
      # This read takes no lock, and resume removes the hold file under its
      # own: read a copy, and a file gone between the test and the copy as
      # no holder.
      hsnap=/dev/null
      if [ -e "$hf" ]; then
        if cp "$hf" "$work/hold" 2>/dev/null; then
          hsnap="$work/hold"
        elif [ -e "$hf" ]; then
          die 6 "cannot read the hold store of $v"
        fi
      fi
      [ -e "$lf" ] || lf=/dev/null
      awk -F "$TAB" -v v="$v" -v cutoff="$cutoff" "$AWK_GRAMMAR"'
        FILENAME == ARGV[1] {
          if (!hold_ok()) next
          n++
          hu[n] = $2; hs[n] = $3; hsince[n] = $1
          if (since == "" || $1 + 0 < since + 0) { since = $1; reason = $6 }
          if ($4 != "-" && (reset == "" || $4 + 0 > reset + 0)) reset = $4
          next
        }
        ledger_ok() && $1 + 0 >= cutoff + 0 { c[$2]++ }
        END {
          if (n) printf "vendor\t%s\theld\t%s\t%s\t%d\t%s\n", v, since, (reset == "" ? "-" : reset), n, reason
          else printf "vendor\t%s\tclear\t-\t-\t0\t-\n", v
          for (i = 1; i <= n; i++) printf "holder\t%s\t%s\t%s\t%s\n", v, hu[i], hs[i], hsince[i]
          split("request answer refusal hold resume", ev, " ")
          for (i = 1; i <= 5; i++) printf "count\t%s\t%s\t%d\n", v, ev[i], c[ev[i]] + 0
        }
      ' "$hsnap" "$lf" </dev/null >"$work/status" || die 6 "cannot read the store of $v"
      tr -d '\000-\010\013-\037\177\200-\237' <"$work/status" || die 6 "cannot render the status of $v"
    done
    exit 0
    ;;

  prune)
    days=$(retention_days) || exit $?
    cutoff=$((now - days * 86400))
    [ ! -L "$store" ] || die 6 "refusing a symlink in the vendor's store"
    # As in status: a store that cannot be searched or listed hides ledgers.
    if [ -d "$store" ] && { [ ! -x "$store" ] || { [ "$vendor_set" != 1 ] && [ ! -r "$store" ]; }; }; then
      die 6 "cannot read the quota store"
    fi
    for v in $(list_vendors); do
      refuse_links "$v"
      [ ! -d "$store/$v" ] || [ -x "$store/$v" ] || die 6 "cannot search the store of $v"
      [ -f "$store/$v/ledger.tsv" ] || continue
      dir=$(vendor_dir "$v") || exit 6
      lock_vendor "$dir"
      CUR_TMP=$(mktemp "$dir/.ledger.XXXXXX") || die 6 "cannot create a write temp"
      awk -F "$TAB" -v v="$v" -v cutoff="$cutoff" "$AWK_GRAMMAR"'
        ledger_ok() && $1 + 0 >= cutoff + 0' "$dir/ledger.tsv" >"$CUR_TMP" || die 6 "cannot prune the ledger"
      if cmp -s "$CUR_TMP" "$dir/ledger.tsv"; then
        rm -f "$CUR_TMP"
      else
        mv -f "$CUR_TMP" "$dir/ledger.tsv" || die 6 "cannot commit the pruned ledger"
      fi
      CUR_TMP=""
      unlock_vendor "$dir"
    done
    exit 0
    ;;
esac
