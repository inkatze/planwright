#!/bin/sh
# fleet-audit.sh — the shared audit-trail write helper every autonomous daemon
# mechanism logs through (Task 1: D-16, REQ-F1.4).
#
# Every autonomous daemon action the fleet-autonomy bundle introduces (a
# cleanup, a restart, a throttle engagement) records its trigger and reasoning
# here, so "did things go out of whack" is answerable from a durable record of
# what actually happened — the same audit-then-review discipline the autonomy
# gate applies to findings, extended to daemon actions. Routine state
# classification is NOT logged through this trail (kickoff risk row 31): the
# trail records actions, not high-frequency status noise.
#
# STORAGE (kickoff risk row 18 — the windowing policy). One TSV row per
# action in a UTC-dated daily file under the cross-spec fleet home
# (fleet-state.sh root, orchestration-fleet D-11):
#   <fleet-home>/audit/audit-<YYYY-MM-DD>.tsv
#   <epoch>\t<utc-iso8601>\t<mechanism>\t<action>\t<trigger>\t<reasoning>
# Daily files time-bound the store: retention is pruning old files (operator-
# owned; a dated file is safe to archive or delete whole), and a range query
# never has to index inside an unbounded single log. Rows are append-only in
# content — nothing rewrites or reorders an existing record — and each write
# lands via copy-append-RENAME (the fleet-state.sh register discipline), so
# a lockless reader always sees a complete file: the row payload (two 512-
# byte texts plus fields) exceeds any per-write atomicity the platform
# guarantees for plain appends, which is why a bare `>>` would not do.
#
# WRITE DISCIPLINE (kickoff risk rows 8 and 35; REQ-A1.6 artifact hygiene).
# Fields are validated BEFORE write — byte-identical grammar to
# fleet-attention.sh: <mechanism>/<action> against the fleet field grammar
# (valid_field), <trigger>/<reasoning> against the control-free text grammar
# (valid_text: non-empty, <=512 bytes, no C0/DEL/C1) — so a traversal token,
# an embedded tab/newline, or an escape sequence is refused rather than
# tearing the record or driving a terminal at render time. Writes serialize
# through fleet-state.sh's existing cross-spec advisory lock — the same
# primitive its sibling fleet-attention.sh holds for the same store area, so
# no second lock primitive exists (REQ-G1.3's floor; the per-spec
# orchestration lock D-20 carries cannot serialize cross-spec writers, which
# is exactly why the fleet home has its own pre-existing lock). The
# timestamp is stamped UNDER the lock, so lock contention can never commit
# an invocation-time-ordered older stamp after a newer one (a wall-clock
# step backwards, e.g. NTP, is outside this guarantee and self-heals at the
# file level: each row lands in the file matching its own stamped day).
# Query output re-sanitizes every field and skips a non-6-field row with a
# warning (a hand-corrupted store line can neither drive the terminal nor
# masquerade as data). Re-sanitization is the in-awk [[:print:]] strip
# (echo-safety.sh's documented awk-form posture), so query OUTPUT is printable
# ASCII: bytes >= 0xA0 that the text grammar admits (e.g. multibyte
# punctuation) are dropped from the query view, while the daily file keeps
# them byte-exact — the store, not the query, is the durable record.
#
# CALLER CONTRACT: a daemon mechanism records the action it just performed
# and must surface a non-zero `record` exit (the trail refuses rather than
# writes a bad row, and lock starvation drops the write) instead of
# swallowing it — an unrecorded action is exactly what the trail exists to
# prevent.
#
# CALLER-HELD LOCK (fleet-autonomy Task 9; REQ-G1.3): a mechanism whose state
# is DERIVED from this trail (the usage-gate restriction ladder, D-28) must
# check-then-append atomically — derive the current rung and record the
# transition under ONE hold of the shared advisory lock, so concurrent towers
# cannot both record the same transition. Because that caller already holds the
# lock (`fleet-state.sh lock`) and this helper's own acquire would deadlock on
# the same non-reentrant primitive, `record` skips its acquire/release when the
# caller sets PLANWRIGHT_FLEET_LOCK_HELD=1. The timestamp-under-lock and
# copy-append-rename guarantees still hold — the caller's hold provides the
# mutual exclusion this helper's own acquire otherwise would. Query never locks,
# so it is unaffected. Default (unset): record acquires and releases as before.
#
# Usage:
#   fleet-audit.sh record <mechanism> <action> <trigger> <reasoning>
#       Append one action row. <action> is a short token (cleanup, restart,
#       throttle, ...) — kept free-form under the field grammar so later
#       tasks' vocabularies need no helper edit.
#   fleet-audit.sh query [--mechanism <m>] [--since <epoch>] [--until <epoch>]
#       Print matching rows (TSV, oldest file first) on stdout. Bounds are
#       inclusive epoch seconds; every filter is optional. Reads are lockless:
#       each write replaces the day file atomically (the copy-append-rename
#       above), so a reader sees a complete file (at worst missing the newest
#       row), never a torn one.
#
# Exit codes: 0 success; 2 usage error, unresolvable home, refused hostile
#   input, or a filesystem/lock error (fail closed).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date
# +%s`, awk, a fractional `sleep` (the lock retry, as fleet-attention.sh
# uses). No eval, no jq (REQ-K1.5). All input is data.
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# sourced as the sibling fleet scripts do; a missing helper is a broken
# install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
TAB=$(printf '\t')

# The fleet field grammar, byte-identical to fleet-state.sh /
# fleet-attention.sh valid_field: excludes path separators, whitespace, and
# any control or shell metacharacter; bounded to 128 chars.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# The control-free text grammar for the free-text fields (trigger,
# reasoning), byte-identical to fleet-attention.sh valid_text: non-empty, at
# most 512 bytes, and free of C0/DEL/C1 control bytes — a value that changes
# under sanitize_printable carries one and is refused. Blocks record-tearing
# (tab/newline) and terminal injection while admitting ordinary punctuation.
valid_text() {
  vt_v=$1
  [ -n "$vt_v" ] || return 1
  [ "${#vt_v}" -le 512 ] || return 1
  [ "$(sanitize_printable "$vt_v")" = "$vt_v" ]
}

resolve_home() {
  rh_root=$("$FS" root) || return 2
  printf '%s' "$rh_root"
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

HOLD_LOCK=0
# Release on ANY exit, signals included (the fleet-attention.sh trap
# discipline): a SIGINT/SIGTERM mid-critical-section must not leave the
# shared cross-spec lock held until the stale-break threshold. INT/TERM
# route through EXIT via explicit exits with the conventional codes.
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt 1000 ]; do
    "$FS" lock >/dev/null 2>&1
    al_rc=$?
    case $al_rc in
      0)
        HOLD_LOCK=1
        return 0
        ;;
      1) ;; # a live holder has it — retry
      *)
        echo "fleet-audit: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-audit: gave up acquiring the fleet lock after contention" >&2
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

if [ "$#" -lt 1 ]; then
  echo "usage: fleet-audit.sh record <mechanism> <action> <trigger> <reasoning> | query [--mechanism <m>] [--since <epoch>] [--until <epoch>]" >&2
  exit 2
fi
cmd=$1
shift

case "$cmd" in
  record)
    if [ "$#" -ne 4 ]; then
      echo "usage: fleet-audit.sh record <mechanism> <action> <trigger> <reasoning>" >&2
      exit 2
    fi
    mechanism=$1
    action=$2
    trigger=$3
    reasoning=$4
    if ! valid_field "$mechanism"; then
      echo "fleet-audit: refusing malformed mechanism '$(sanitize_printable "$mechanism" "(unprintable mechanism)")'" >&2
      exit 2
    fi
    if ! valid_field "$action"; then
      echo "fleet-audit: refusing malformed action '$(sanitize_printable "$action" "(unprintable action)")'" >&2
      exit 2
    fi
    if ! valid_text "$trigger"; then
      echo "fleet-audit: refusing trigger text (non-empty, <=512 bytes, no control characters)" >&2
      exit 2
    fi
    if ! valid_text "$reasoning"; then
      echo "fleet-audit: refusing reasoning text (non-empty, <=512 bytes, no control characters)" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    audit_dir="$root/audit"
    # The dir create is idempotent and order-independent; doing it BEFORE the
    # lock keeps the contended critical section as short as possible.
    if ! mkdir -p "$audit_dir" 2>/dev/null; then
      echo "fleet-audit: cannot create the audit dir $audit_dir" >&2
      exit 2
    fi
    # A caller whose state is derived from this trail (the usage-gate ladder)
    # holds the shared lock across its own derive+record critical section; a
    # nested acquire of the same non-reentrant primitive would deadlock, so skip
    # it here and let the caller's hold provide the mutual exclusion.
    lock_held=0
    if [ "${PLANWRIGHT_FLEET_LOCK_HELD:-}" = 1 ]; then
      lock_held=1
    fi
    if [ "$lock_held" = 0 ]; then
      acquire_lock || exit 2
    fi
    # Stamp the row's time UNDER the lock (commit time, not invocation time) —
    # the fleet-state.sh register discipline — so lock contention can never
    # commit an invocation-ordered older stamp after a newer one. Epoch and
    # ISO come from two clock reads; sampling the UTC day on both sides and
    # retrying on a mismatch pins all three to one UTC day, so a row's epoch
    # always falls within its file's named day (the retention-by-file model
    # depends on that).
    ts=""
    iso=""
    day=""
    st_try=0
    while [ "$st_try" -lt 3 ]; do
      day_before=$(TZ=UTC date -u '+%Y-%m-%d' 2>/dev/null) || day_before=""
      ts=$(now_epoch)
      iso=$(TZ=UTC date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || iso=""
      day=${iso%%T*}
      [ -n "$ts" ] && [ "$day_before" = "$day" ] && break
      ts=""
      st_try=$((st_try + 1))
    done
    if [ -z "$ts" ]; then
      echo "fleet-audit: could not read a stable numeric/UTC timestamp" >&2
      exit 2
    fi
    case $iso in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
      *)
        echo "fleet-audit: could not read a UTC timestamp" >&2
        exit 2
        ;;
    esac
    # Copy-append-rename (the fleet-state.sh register discipline): the
    # renamed file is complete at every instant, so the lockless query path
    # never sees a torn row — a plain `>>` append of a row this large (two
    # 512-byte texts) has no such guarantee.
    store="$audit_dir/audit-$day.tsv"
    w_rc=0
    w_tmp=$(mktemp "$audit_dir/.audit.XXXXXX") || {
      echo "fleet-audit: cannot create a temp file under $audit_dir" >&2
      exit 2
    }
    if [ -f "$store" ]; then
      cat "$store" >"$w_tmp" 2>/dev/null || w_rc=2
    fi
    if [ "$w_rc" = 0 ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ts" "$iso" "$mechanism" "$action" "$trigger" "$reasoning" \
        >>"$w_tmp" || w_rc=2
    fi
    if [ "$w_rc" = 0 ]; then
      mv -f "$w_tmp" "$store" || w_rc=2
    fi
    [ "$w_rc" = 0 ] || rm -f "$w_tmp" 2>/dev/null
    if [ "$lock_held" = 0 ]; then
      release_lock
    fi
    if [ "$w_rc" != 0 ]; then
      echo "fleet-audit: failed to write the audit trail" >&2
      exit 2
    fi
    exit 0
    ;;
  query)
    q_mech=""
    q_since=""
    q_until=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --mechanism)
          [ "$#" -ge 2 ] || {
            echo "fleet-audit: --mechanism needs a value" >&2
            exit 2
          }
          q_mech=$2
          shift 2
          ;;
        --since)
          [ "$#" -ge 2 ] || {
            echo "fleet-audit: --since needs an epoch value" >&2
            exit 2
          }
          q_since=$2
          shift 2
          ;;
        --until)
          [ "$#" -ge 2 ] || {
            echo "fleet-audit: --until needs an epoch value" >&2
            exit 2
          }
          q_until=$2
          shift 2
          ;;
        *)
          echo "usage: fleet-audit.sh query [--mechanism <m>] [--since <epoch>] [--until <epoch>]" >&2
          exit 2
          ;;
      esac
    done
    if [ -n "$q_mech" ] && ! valid_field "$q_mech"; then
      echo "fleet-audit: refusing malformed mechanism filter '$(sanitize_printable "$q_mech" "(unprintable mechanism)")'" >&2
      exit 2
    fi
    for bound in "$q_since" "$q_until"; do
      [ -z "$bound" ] && continue
      case "$bound" in
        *[!0-9]*)
          echo "fleet-audit: a time bound must be epoch seconds (got '$(sanitize_printable "$bound" "(unprintable bound)")')" >&2
          exit 2
          ;;
      esac
      if [ "${#bound}" -gt 15 ]; then
        echo "fleet-audit: a time bound must be at most 15 digits" >&2
        exit 2
      fi
    done
    root=$(resolve_home) || exit 2
    audit_dir="$root/audit"
    # No trail yet is a clean empty answer; the path existing as a NON-dir is
    # a corrupted home and must fail loudly (record's mkdir fails on the same
    # state), not masquerade as an empty trail.
    [ -e "$audit_dir" ] || exit 0
    if [ ! -d "$audit_dir" ]; then
      echo "fleet-audit: audit path $audit_dir exists but is not a directory" >&2
      exit 2
    fi
    # An unreadable/untraversable dir must not masquerade as an empty trail
    # (an audit query answering "nothing happened" because of a permission
    # problem is an opaque failure).
    if [ ! -r "$audit_dir" ] || [ ! -x "$audit_dir" ]; then
      echo "fleet-audit: audit dir $audit_dir exists but is not readable" >&2
      exit 2
    fi
    # The file list is built by a glob INSIDE the dir (a subshell cd), so a
    # fleet-home path containing whitespace never word-splits: the matched
    # names themselves are this script's own audit-YYYY-MM-DD.tsv (no
    # whitespace, no globs), and LC_ALL=C glob order is date order. One awk
    # runs over every file (not one per file); regular-file-ness and
    # readability are pre-checked so the query fails BEFORE emitting any
    # partial output. Rows are filtered
    # by mechanism (exact string match — the "" concatenation pins awk to
    # string comparison for numeric-looking tokens) and by the inclusive
    # epoch bounds; every field is re-sanitized on the way out (the in-awk
    # [[:print:]] strip: under LC_ALL=C it also drops admitted >= 0xA0 bytes
    # from the OUTPUT — the header's query-view-is-ASCII contract; the stored
    # file keeps them), and a row that is not the 6-field shape is skipped
    # and counted, warned to stderr (a hand-corrupted line can neither drive
    # the terminal nor pass as data).
    (
      cd "$audit_dir" || exit 2
      set +f
      set -- audit-*.tsv
      set -f
      [ -e "$1" ] || exit 0
      for f in "$@"; do
        # A match that is not a regular file is a corrupted home; refuse it
        # here deterministically (awk's handling of a directory operand is
        # platform-variant: silently tolerated by BSD awk, warned or fatal
        # under gawk), never let it masquerade as data or emptiness.
        if [ ! -f "$f" ]; then
          echo "fleet-audit: store match $audit_dir/$f is not a regular file" >&2
          exit 2
        fi
        if [ ! -r "$f" ]; then
          echo "fleet-audit: cannot read $audit_dir/$f" >&2
          exit 2
        fi
      done
      awk -F "$TAB" -v OFS="$TAB" -v m="$q_mech" -v s="$q_since" -v u="$q_until" '
        NF != 6 { skipped++; next }
        (m == "" || ($3 "") == (m "")) &&
        (s == "" || $1 + 0 >= s + 0) &&
        (u == "" || $1 + 0 <= u + 0) {
          for (i = 1; i <= NF; i++) gsub(/[^[:print:]]/, "", $i)
          print
        }
        END {
          if (skipped > 0)
            printf "fleet-audit: skipped %d malformed (non-6-field) row(s)\n", skipped | "cat 1>&2"
        }' "$@" || {
        echo "fleet-audit: failed reading the audit files" >&2
        exit 2
      }
    ) || exit "$?"
    exit 0
    ;;
  *)
    echo "usage: fleet-audit.sh record <mechanism> <action> <trigger> <reasoning> | query [--mechanism <m>] [--since <epoch>] [--until <epoch>]" >&2
    exit 2
    ;;
esac
