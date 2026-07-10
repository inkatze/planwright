#!/bin/sh
# check-obs.sh — the standing CI guard over the observation fragment store
# (observation-recording Task 2, REQ-D1.4, REQ-A1.2; D-6, D-7). It re-validates,
# on every commit, the structural invariants scripts/obs-record.sh (Task 1) and
# scripts/obs-consume.sh (Task 4) enforce at write time — the filename grammar,
# the one-entry-per-file content shape, and UID uniqueness — so a hand-edited
# fragment, a merge-mangled name, or a stray committed compiled view cannot slip
# past CI. (The `[<scope>]` token is checked only for bracket shape, not the
# writer's full scope charset; that grammar is uncharacterized in the spec and is
# tracked as an open drift in specs/_observations/opportunities.md.)
#
# What it checks under the pinned C locale (REQ-D1.4):
#   * every file under entries/ and archive/ matches the fragment filename
#     grammar `<date>-<slug>-<uid>.md` (REQ-A1.2) with `<date>` a real calendar
#     date, `<slug>` a kebab-case token of at most 40 chars, and `<uid>` exactly
#     8 lowercase hex characters — the same grammar the recording helper mints;
#   * every fragment carries exactly one entry-form line (`- <date> [<scope>]
#     <text>`) as its literal first line, and beyond it only blank lines and
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
# Exit codes: 0 clean, 1 one or more violations, 2 usage or internal error
# (an argument-parse failure, or an environment failure such as mktemp — never
# conflated with 1, so a broken environment cannot read as a clean/violation run).
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
# the main shell (never a pipe/subshell), so the status mutation sticks. printf,
# not echo: the message embeds an untrusted (safe()'d) fragment name, and a
# `#!/bin/sh` `echo` re-expands backslash sequences (`\t`, `\c`, `\033`) that
# safe() does not strip — verified live on this host — re-injecting the very
# control bytes the echo-discipline posture exists to keep out of CI logs (D-7).
fail() {
  printf '%s\n' "$prog: $1" >&2
  status=1
}

# safe <string> — strip C0 control bytes, DEL, and the C1 range so an untrusted
# fragment name embedded in a finding cannot smuggle an escape sequence into CI
# logs (echo discipline, D-7). This is a *display*-path sanitizer: its output goes
# only to finding messages on stderr, so it mirrors the sibling display sanitizer
# scripts/drain-gates.sh, which strips C1 (0x80-0x9F) too — otherwise byte 0x9B
# (8-bit CSI) and friends survive as a live terminal-injection vector even after
# ESC (0x1B) is neutralized. The cost is that a legitimate multibyte UTF-8 byte in
# the 0x80-0x9F range renders mangled in the message, but the name being reported
# is already invalid/unexpected, so display fidelity yields to injection safety.
# (Scoped to this guard: the write-time storage path in obs-record.sh deliberately
# preserves C1 as UTF-8 continuation bytes, and the shared echo-safety.sh sanitizer
# still strips C0+DEL only — the repo-wide "should every display sanitizer strip
# C1" question is left open as an observation.)
safe() {
  printf '%s' "$1" | tr -d '\000-\037\177\200-\237'
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
    # Strip a trailing CR first so a CRLF-saved (merge-mangled) fragment parses
    # like an LF one — otherwise a CRLF blank separator fails the blank-line rule
    # while a single-line CRLF fragment slips through (opposite verdicts from one
    # defect). Mirrors scripts/check-ledger.sh / drain-gates.sh.
    { sub(/\r$/, "") }
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
    /^Consumed-by: .+/ { next }   # the sole whitelisted metadata key (non-empty value)
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
  # A symlinked fragment directory is refused at the top-level layout check
  # below; do not traverse through it here (never read through a symlink — D-7).
  [ ! -L "$_dir" ] || return 0
  # Enumerate dotfiles too (`.*`): a POSIX `*` glob never matches a leading-dot
  # name, so a hidden fragment — a committed obs-record `.obs-record.XXXXXX` temp,
  # or any `.`-prefixed hand-edit — would otherwise escape both name and content
  # validation AND never reach the UID ledger (a hidden dup would defeat the
  # cross-directory uniqueness check). The `.`/`..` self/parent links are skipped.
  for _f in "$_dir"/* "$_dir"/.*; do
    # `-e` is false for the literal unmatched glob AND for a dangling symlink, so
    # test `-L` too: skip only a truly-absent entry, never let a dangling symlink
    # slip past the refusal below (a committed symlink to a nonexistent target is
    # a real git artifact that must still be rejected).
    [ -e "$_f" ] || [ -L "$_f" ] || continue
    _name=${_f##*/}
    case "$_name" in . | ..) continue ;; esac
    # A symlink passes `-f` when it points at a regular file, so refuse it
    # explicitly before the type check: a fragment is a real file the recording
    # helper wrote, never a link that could read through to outside the tree (D-7,
    # the containment symmetry obs-record.sh holds at write time).
    if [ -L "$_f" ]; then
      fail "$_label/$(safe "$_name"): a fragment must be a regular file, not a symlink"
      continue
    fi
    if [ ! -f "$_f" ]; then
      fail "$_label/$(safe "$_name"): expected a regular fragment file"
      continue
    fi
    if ! valid_name "$_name"; then
      fail "$_label/$(safe "$_name"): invalid fragment filename (grammar or calendar date)"
      continue
    fi
    # Honor check_content's exit code, not just its message: an awk read failure
    # (e.g. an embedded NUL some awks abort on) exits non-zero with empty stdout,
    # and treating that as valid would silently pass an unvalidated fragment.
    _msg=$(check_content "$_f")
    _crc=$?
    if [ "$_crc" -ne 0 ] || [ -n "$_msg" ]; then
      fail "$_label/$(safe "$_name"): ${_msg:-content validation failed}"
      continue
    fi
    _stem=${_name%.md}
    _uid=${_stem##*-}
    printf '%s %s/%s\n' "$_uid" "$_label" "$_name" >>"$uidledger"
  done
}

# --- top-level unexpected-file check -------------------------------------

# A symlinked observations root would let the whole store resolve to somewhere
# outside the tree; refuse it before the null-safe test resolves it (D-7,
# mirroring obs-record.sh's obs-dir guard).
if [ -L "$obsdir" ]; then
  printf '%s\n' "$prog: the observations root must not be a symlink" >&2
  exit 1
fi

# An absent observations root is a clean pass (null-safe): nothing to validate.
if [ ! -d "$obsdir" ]; then
  exit 0
fi

# Only the two fragment directories and the frozen legacy files are expected
# directly under the root (REQ-D1.4). Enforce the type too, so a whitelisted
# name of the wrong kind — a regular file named `entries`, a symlinked
# `archive`, a directory named `opportunities.md` — cannot slip past as an
# unscanned no-op (scan_dir would `-d`-skip it silently otherwise).
# Enumerate dotfiles too (`.*`): a POSIX `*` glob never matches a leading-dot
# name, so a hidden compiled view (e.g. `.rendered-log.md`) committed directly
# under the root would otherwise slip past the standing block on unexpected files
# (REQ-B1.3). The `.`/`..` self/parent links are skipped.
for _e in "$obsdir"/* "$obsdir"/.*; do
  # As in scan_dir: `-L` too, so a dangling symlink (name whitelisted or not) is
  # not skipped as "absent" before the type/unexpected checks run.
  [ -e "$_e" ] || [ -L "$_e" ] || continue
  _b=${_e##*/}
  case "$_b" in
    . | ..) continue ;;
    entries | archive)
      if [ -L "$_e" ] || [ ! -d "$_e" ]; then
        fail "\"$(safe "$_b")\" under the observations root must be a real directory, not a symlink or file"
      fi
      ;;
    opportunities.md | archive.md)
      if [ -L "$_e" ] || [ ! -f "$_e" ]; then
        fail "the frozen legacy file \"$(safe "$_b")\" must be a regular file, not a symlink or directory"
      fi
      ;;
    *) fail "unexpected path directly under the observations root: $(safe "$_b")" ;;
  esac
done

# --- fragment validation + UID uniqueness --------------------------------

uidledger=$(mktemp) || {
  printf '%s\n' "$prog: cannot create a temporary work file" >&2
  exit 2
}
# A trapped signal does not itself terminate the shell in POSIX sh: after the
# handler runs, control resumes at the interrupted point. Folding INT/TERM into
# the EXIT cleanup would rm the ledger mid-scan and then keep going (scan_dir
# re-creates it via `>>`), so a Ctrl-C would not stop the guard and the dedup
# pass could run over a truncated ledger. Split them so a signal re-exits with
# the conventional 128+signo code; the EXIT trap still cleans up on that exit
# (mirrors scripts/obs-record.sh).
trap 'rm -f "$uidledger"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
      printf '%s\n' "$prog: duplicate UID across entries/ and archive/ (breaks obs:<uid>): $_line" >&2
    done
    IFS=$oldifs
  fi
fi

exit "$status"
