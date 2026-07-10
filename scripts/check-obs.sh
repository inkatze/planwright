#!/bin/sh
# check-obs.sh — the standing CI guard over the observation fragment store
# (observation-recording Task 2, REQ-D1.4, REQ-A1.2; D-6, D-7). It re-validates,
# on every commit, the invariants scripts/obs-record.sh (Task 1) and
# scripts/obs-consume.sh (Task 4) enforce at write time, so a hand-edited fragment,
# a merge-mangled name, or a stray committed compiled view cannot slip past CI.
#
# What it checks under the pinned C locale (REQ-D1.4):
#   * every file under entries/ and archive/ matches the fragment filename
#     grammar `<date>-<slug>-<uid>.md` (REQ-A1.2) with `<date>` a real calendar
#     date, `<slug>` a kebab-case token of at most 40 chars, and `<uid>` exactly
#     8 lowercase hex characters — the same grammar the recording helper mints;
#   * every fragment carries exactly one entry-form line (`- <date> [<scope>]
#     <text>`) as its first content line, and beyond it only blank lines and
#     whitelisted metadata (`Consumed-by:`) — free prose and any other
#     `Key: value` line fail (whitelist exactness; REQ-A1.4);
#   * UIDs are unique across entries/ AND archive/ together, so `obs:<uid>`
#     stays a one-file citation after a consume moves a fragment;
#   * nothing unexpected sits directly under specs/_observations/: the two
#     fragment directories and the frozen legacy files (opportunities.md,
#     archive.md) are the only expected contents — the standing block on
#     committed compiled views (REQ-B1.3).
#
# Null-safe (REQ-A1.6, REQ-D1.4): entries/ and archive/ are created on demand
# and may not exist in a given tree; an absent directory (or an absent
# observations root entirely) is a clean pass, not a failure.
#
# Security posture (D-7): fragment names and content are data only — never
# evaluated, expanded, or used as a pattern; the observations root is never a
# path composed from a fragment name; and untrusted names have their control
# bytes stripped before they reach a finding message (echo discipline, mirrored
# across the sibling guards).
#
# Usage: check-obs.sh [--obs-dir <dir>]
#   --obs-dir  the observations dir holding entries/ + archive/ and the frozen
#              legacy files; defaults to specs/_observations under the repo cwd.
#
# Exit codes: 0 clean, 1 one or more violations, 2 usage error.
#
# Portable: POSIX sh + awk (bash 3.2 / BSD compatible); no eval, input treated
# as data only (the framework-script safety rule).
set -u

# Pin the C locale: [a-z0-9] and friends are collation-dependent under UTF-8
# locales (uppercase collates into [a-z]); the pin makes charset validation a
# byte-range check (mirrors obs-record.sh and the sibling guards).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into command substitutions and corrupt the
# derived paths below.
unset CDPATH

prog=check-obs

usage() {
  echo "usage: $prog [--obs-dir <dir>]" >&2
}

# --- argument parsing ----------------------------------------------------

obsdir="specs/_observations"
while [ $# -gt 0 ]; do
  case $1 in
    --obs-dir)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      obsdir=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* | *)
      usage
      exit 2
      ;;
  esac
done
[ $# -eq 0 ] || {
  usage
  exit 2
}

# A hyphen-leading obs-dir is refused up front: it is read as an option by the
# tooling below and no caller legitimately names the store '-' (mirrors the
# obs-record.sh guard).
case "$obsdir" in
  -*) {
    echo "$prog: observations directory must not begin with a hyphen" >&2
    exit 2
  } ;;
esac

status=0

# fail <message> — record a violation on stderr and mark the run failed. Runs in
# the main shell (never a pipe/subshell), so the status mutation sticks.
fail() {
  echo "$prog: $1" >&2
  status=1
}

# safe <string> — strip C0 control bytes and DEL so an untrusted fragment name
# embedded in a finding cannot smuggle an escape sequence into CI logs (echo
# discipline; under LC_ALL=C the stripped set is exactly C0 + DEL, so legitimate
# multibyte UTF-8 survives).
safe() {
  printf '%s' "$1" | tr -d '\000-\037\177'
}

# --- calendar-date validity (mirrors obs-record.sh) ----------------------

# strip0 <digits> — drop leading zeros so arithmetic never reads 08/09 as octal.
strip0() {
  _n=$1
  while [ "$_n" != "${_n#0}" ] && [ "${#_n}" -gt 1 ]; do
    _n=${_n#0}
  done
  printf '%s' "$_n"
}

# valid_calendar_date <YYYY-MM-DD> — 0 if the already-shape-checked date is a
# real calendar date (month 1-12, day within the month, leap Feb), else 1.
valid_calendar_date() {
  _y=$(strip0 "${1%%-*}")
  _rest=${1#*-}
  _mo=$(strip0 "${_rest%%-*}")
  _da=$(strip0 "${_rest#*-}")
  [ "$_mo" -ge 1 ] && [ "$_mo" -le 12 ] || return 1
  case "$_mo" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) _max=31 ;;
    4 | 6 | 9 | 11) _max=30 ;;
    2)
      if { [ $((_y % 4)) -eq 0 ] && [ $((_y % 100)) -ne 0 ]; } \
        || [ $((_y % 400)) -eq 0 ]; then
        _max=29
      else
        _max=28
      fi
      ;;
    *) return 1 ;;
  esac
  [ "$_da" -ge 1 ] && [ "$_da" -le "$_max" ]
}

# valid_name <basename> — 0 if the filename matches the composite fragment
# grammar `<date>-<slug>-<uid>.md` with a real calendar date, a kebab-case slug
# of 1..40 chars, and an 8-lowercase-hex UID, else 1. Pure string parsing: the
# name is never used to compose a path (D-7).
#
# The `_v`-prefixed locals are deliberate: POSIX sh has no function-local scope,
# and valid_calendar_date reassigns `_rest`/`_mo`/... as globals. A shared name
# here would be clobbered by that callee mid-parse (it was: the slug read back as
# the callee's leftover `_rest`), so this parser keeps its own namespace.
valid_name() {
  _vb=$1
  case "$_vb" in
    *.md) : ;;
    *) return 1 ;;
  esac
  _vstem=${_vb%.md}
  # UID is the final hyphen-delimited token; slug is mandatory, so a stem with
  # no hyphen after the date cannot parse.
  case "$_vstem" in
    *-*) : ;;
    *) return 1 ;;
  esac
  _vuid=${_vstem##*-}
  case "$_vuid" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) return 1 ;;
  esac
  _vrest=${_vstem%-*} # <date>-<slug>
  # A leading YYYY-MM-DD followed by at least one slug char.
  case "$_vrest" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) : ;;
    *) return 1 ;;
  esac
  _vslug=${_vrest#??????????-} # strip "YYYY-MM-DD-"
  _vdate=${_vrest%"-$_vslug"}  # the leading YYYY-MM-DD (before valid_calendar_date clobbers globals)
  [ -n "$_vslug" ] || return 1
  [ "${#_vslug}" -le 40 ] || return 1
  case "$_vslug" in
    -* | *-) return 1 ;;
    *--*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  valid_calendar_date "$_vdate" || return 1
  return 0
}

# check_content <file> — echo a violation message and return 1 if the file is
# not a single entry-form line optionally followed by blank lines and
# whitelisted `Consumed-by:` metadata; return 0 (silent) when the shape is
# valid. Content is data only: awk matches it, never evaluates it.
check_content() {
  awk '
    NR == 1 {
      if ($0 !~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \[[^][]+\] .+/) {
        print "first line is not the entry form \"- <date> [<scope>] <text>\""
        bad = 1
        exit
      }
      next
    }
    /^[ \t]*$/ { next }   # blank lines are allowed after the entry
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \[/ {
      print "multiple entry lines (one entry per file)"
      bad = 1
      exit
    }
    /^Consumed-by: / { next }   # the sole whitelisted metadata key
    {
      print "unexpected content line (only blank lines and Consumed-by: metadata may follow the entry)"
      bad = 1
      exit
    }
    END {
      if (bad) exit 1
      if (NR == 0) {
        print "empty fragment (missing entry line)"
        exit 1
      }
    }
  ' "$1"
}

# scan_dir <dir> <label> — validate every regular file under a fragment
# directory; append `<uid> <label>/<name>` to the UID ledger for each
# grammar-valid fragment. Null-safe over an absent directory.
scan_dir() {
  _dir=$1
  _label=$2
  [ -d "$_dir" ] || return 0
  for _f in "$_dir"/*; do
    [ -e "$_f" ] || continue # empty glob
    _name=${_f##*/}
    if [ ! -f "$_f" ]; then
      fail "$_label/$(safe "$_name"): expected a regular fragment file"
      continue
    fi
    if ! valid_name "$_name"; then
      fail "$_label/$(safe "$_name"): invalid fragment filename (grammar or calendar date)"
      continue
    fi
    _msg=$(check_content "$_f")
    if [ -n "$_msg" ]; then
      fail "$_label/$(safe "$_name"): $_msg"
      continue
    fi
    _stem=${_name%.md}
    _uid=${_stem##*-}
    printf '%s %s/%s\n' "$_uid" "$_label" "$_name" >>"$uidledger"
  done
}

# --- top-level unexpected-file check -------------------------------------

# An absent observations root is a clean pass (null-safe): nothing to validate.
if [ ! -d "$obsdir" ]; then
  exit 0
fi

for _e in "$obsdir"/*; do
  [ -e "$_e" ] || continue # empty glob
  _b=${_e##*/}
  case "$_b" in
    entries | archive | opportunities.md | archive.md) : ;;
    *) fail "unexpected path directly under the observations root: $(safe "$_b")" ;;
  esac
done

# --- fragment validation + UID uniqueness --------------------------------

uidledger=$(mktemp) || {
  echo "$prog: cannot create a temporary work file" >&2
  exit 2
}
trap 'rm -f "$uidledger"' EXIT INT TERM

scan_dir "$obsdir/entries" entries
scan_dir "$obsdir/archive" archive

# A UID appearing on more than one fragment (in either directory) breaks the
# one-file `obs:<uid>` citation guarantee. Group by UID deterministically and
# report each collision naming every matching fragment.
if [ -s "$uidledger" ]; then
  dupes=$(sort "$uidledger" | awk '
    { paths[$1] = paths[$1] " " $2; count[$1]++ }
    END { for (u in paths) if (count[u] > 1) print u paths[u] }
  ' | sort)
  if [ -n "$dupes" ]; then
    # Set status directly (not via `fail` in a pipe, which would lose the
    # mutation to a subshell); emit one finding line per duplicated UID.
    status=1
    oldifs=$IFS
    IFS='
'
    for _line in $dupes; do
      echo "$prog: duplicate UID across entries/ and archive/ (breaks obs:<uid>): $_line" >&2
    done
    IFS=$oldifs
  fi
fi

exit "$status"
