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
# action, appended to a UTC-dated daily file under the cross-spec fleet home
# (fleet-state.sh root, orchestration-fleet D-11):
#   <fleet-home>/audit/audit-<YYYY-MM-DD>.tsv
#   <epoch>\t<utc-iso8601>\t<mechanism>\t<action>\t<trigger>\t<reasoning>
# Daily files time-bound the store: retention is pruning old files (operator-
# owned; a dated file is safe to archive or delete whole), and a range query
# never has to index inside an unbounded single log. Rows are append-only —
# nothing here rewrites or reorders an existing record.
#
# WRITE DISCIPLINE (kickoff risk rows 8 and 35; REQ-A1.6 artifact hygiene).
# Fields are validated BEFORE write — byte-identical grammar to
# fleet-attention.sh: <mechanism>/<action> against the fleet field grammar
# (valid_field), <trigger>/<reasoning> against the control-free text grammar
# (valid_text: non-empty, <=512 bytes, no C0/DEL/C1) — so a traversal token,
# an embedded tab/newline, or an escape sequence is refused rather than
# tearing the record or driving a terminal at render time. Writes serialize
# through fleet-state.sh's advisory lock (D-20: the existing primitive, never
# a second one), with the timestamp stamped UNDER the lock so committed rows
# never regress. Query output re-sanitizes every field (a hand-corrupted
# store line still cannot drive the terminal).
#
# Usage:
#   fleet-audit.sh record <mechanism> <action> <trigger> <reasoning>
#       Append one action row. <action> is a short token (cleanup, restart,
#       throttle, ...) — kept free-form under the field grammar so later
#       tasks' vocabularies need no helper edit.
#   fleet-audit.sh query [--mechanism <m>] [--since <epoch>] [--until <epoch>]
#       Print matching rows (TSV, oldest file first) on stdout. Bounds are
#       inclusive epoch seconds; every filter is optional. Reads are lockless:
#       a row append is a single short atomic write, so a reader sees whole
#       rows (at worst missing the newest), never a torn one.
#
# Exit codes: 0 success; 2 usage error, unresolvable home, refused hostile
#   input, or a filesystem/lock error (fail closed).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date
# +%s`, awk/sort/find, a fractional `sleep` (the lock retry, as
# fleet-attention.sh uses). No eval, no jq (REQ-K1.5). All input is data.
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
    acquire_lock || exit 2
    # Stamp the row's time UNDER the lock (commit time, not invocation time) —
    # the fleet-state.sh register discipline — so contention can never commit
    # an older timestamp after a newer one and regress the trail's order.
    ts=$(now_epoch)
    if [ -z "$ts" ]; then
      release_lock
      echo "fleet-audit: could not read a numeric timestamp" >&2
      exit 2
    fi
    iso=$(TZ=UTC date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || iso=""
    case $iso in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
      *)
        release_lock
        echo "fleet-audit: could not read a UTC timestamp" >&2
        exit 2
        ;;
    esac
    day=${iso%%T*}
    w_rc=0
    if ! mkdir -p "$audit_dir" 2>/dev/null; then
      release_lock
      echo "fleet-audit: cannot create the audit dir $audit_dir" >&2
      exit 2
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ts" "$iso" "$mechanism" "$action" "$trigger" "$reasoning" \
      >>"$audit_dir/audit-$day.tsv" || w_rc=2
    release_lock
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
    [ -d "$audit_dir" ] || exit 0
    # Daily file names are this script's own (audit-YYYY-MM-DD.tsv: no
    # whitespace, no globs), so a newline-separated find|sort is a safe list.
    files=$(find "$audit_dir" -name 'audit-*.tsv' 2>/dev/null | sort) || {
      echo "fleet-audit: cannot list the audit dir $audit_dir" >&2
      exit 2
    }
    [ -n "$files" ] || exit 0
    for f in $files; do
      # Filter rows by mechanism (exact string match — the "" concatenation
      # pins awk to string comparison for numeric-looking tokens) and by the
      # inclusive epoch bounds; re-sanitize each field on the way out so a
      # hand-corrupted store line cannot drive the terminal.
      awk -F "$TAB" -v OFS="$TAB" -v m="$q_mech" -v s="$q_since" -v u="$q_until" '
        (m == "" || ($3 "") == (m "")) &&
        (s == "" || $1 + 0 >= s + 0) &&
        (u == "" || $1 + 0 <= u + 0) {
          for (i = 1; i <= NF; i++) gsub(/[^[:print:]]/, "", $i)
          print
        }' "$f" || {
        echo "fleet-audit: failed reading $f" >&2
        exit 2
      }
    done
    exit 0
    ;;
  *)
    echo "usage: fleet-audit.sh record <mechanism> <action> <trigger> <reasoning> | query [--mechanism <m>] [--since <epoch>] [--until <epoch>]" >&2
    exit 2
    ;;
esac
