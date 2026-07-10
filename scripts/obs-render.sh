#!/bin/sh
# obs-render.sh — the derived chronological view of the observation fragment
# store (observation-recording Task 3, REQ-C1.4, REQ-B1.3, REQ-D1.3; D-1, D-4,
# D-7). Exposed as the mise task `obs:log`.
#
# The observations "log" is not a committed file — it is this render, produced
# on demand as a pure, byte-deterministic function of the live fragments under
# entries/ (plus the frozen legacy file's unconsumed lines while it drains, and
# archive/ fragments with --archived). Nothing here writes to the tree: the
# view goes to stdout only (REQ-B1.3), so there is never a compiled view to
# conflict on or fall stale.
#
# Total order (REQ-C1.4): by date (day granularity), and within one date the
# frozen legacy lines (in file order) before the fragments (by UID). *Live*
# means a fragment in entries/ with no `Consumed-by:` line; a consumed-but-
# unmoved fragment (a stuck consume) is excluded from the view (the drain pass
# surfaces it). The frozen archive.md is never a render source (it is
# pre-fragment history); --archived adds only the archive/ *fragments*.
#
# Skip-and-warn (D-4): a file whose name breaks the fragment grammar, whose
# first content line is not the entry form, or which is a symlink is excluded
# from the output and named on stderr — an invalid file is never a silently
# lost observation, and never silently corrupts the view. A legacy entry-form
# line whose date is not a real calendar date is skipped and named the same way.
#
# Security posture (REQ-D1.3, D-7): fragment names and content — and the legacy
# file's interleaved lines — are data only. Names are never used to compose a
# path beyond the fixed <obs-dir>/{entries,archive} join, content is never
# evaluated or expanded, and every byte reaching stdout or a warning is run
# through a sanitizer that strips the C0 controls and DEL (the terminal-escape
# bytes) so a hostile fragment or legacy line cannot inject an escape sequence,
# while preserving legitimate UTF-8 prose (see safe() for why C1 is kept here).
#
# Empty state: with no live entries the view is empty (no stdout) and the exit
# is 0. All globs are null-safe; an absent observations root, entries/ dir, or
# legacy file is a clean empty contribution, never an error.
#
# Usage:
#   obs-render.sh [--archived] [--obs-dir <dir>]
#
#   --archived  also include the archive/ fragments (consumed history), merged
#               into the same chronological order
#   --obs-dir   the observations dir holding entries/ + archive/ and the frozen
#               legacy files; defaults to specs/_observations under the repo cwd
#
# Exit codes: 0 rendered (including the empty view); 2 usage error. Invalid
# files are report content (skip-and-warn), never a non-zero exit.
#
# Portable: POSIX sh + awk/sort (bash 3.2 / BSD compatible, mawk-safe — no
# regex interval expressions). No fish/mise/tmux dependency.
set -eu

# Pin the C locale: [a-z0-9] ranges and the sort order are collation-dependent
# under UTF-8 locales; the pin makes charset validation a byte-range check and
# the sort byte-deterministic (house pattern, see the sibling obs scripts).
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes its destination into command substitutions,
# corrupting derived paths.
unset CDPATH

prog=obs-render

usage() {
  echo "usage: $prog [--archived] [--obs-dir <dir>]" >&2
}

# warn <message> — a skip-and-warn notice on stderr. printf, not echo: the
# message embeds a safe()'d fragment name, and a #!/bin/sh echo would re-expand
# backslash sequences the sanitizer does not strip (echo discipline, D-7).
warn() {
  printf '%s\n' "$prog: $1" >&2
}

# safe <string> — strip the C0 control bytes (0x00-0x1F) and DEL (0x7F) so an
# untrusted fragment name or content line cannot smuggle an escape sequence into
# the terminal (echo discipline, D-7). Newline is among them: this sanitizes
# single-token names and single content lines, and the caller owns the line
# structure, so a stray newline must not forge a row.
#
# Unlike check-obs.sh / drain-gates.sh, this does NOT strip the C1 range
# (0x80-0x9F). Those siblings sanitize ASCII-only *report* text, where a C1 byte
# can only be an injected 8-bit control. This is the human-readable *content*
# view of legitimate observation prose: obs-record.sh deliberately preserves C1
# bytes at write time because they are the UTF-8 continuation bytes of ordinary
# characters (em-dash U+2014 is 0xE2 0x80 0x94; smart quotes, arrows likewise),
# and refuses only C0 + DEL. Stripping 0x80-0x9F here would corrupt every such
# character in the rendered log (proven live against the legacy file). The
# terminal-injection threat is the C0 ESC-based sequences, which are stripped;
# C1-as-control requires a legacy 8-bit terminal mode incompatible with the
# UTF-8 the substrate commits to. So render preserves 0x80-0xFF and strips only
# the unambiguous C0 + DEL controls (the exact set obs-record.sh refuses).
safe() {
  printf '%s' "$1" | tr -d '\000-\037\177'
}

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
# Mirrors obs-record.sh / check-obs.sh.
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
# name is never used to compose a path (D-7). The `_v`-prefixed locals keep a
# private namespace from valid_calendar_date, which reassigns _rest/_mo/... as
# globals (POSIX sh has no function-local scope). Mirror of check-obs.sh.
valid_name() {
  _vb=$1
  case "$_vb" in
    *.md) : ;;
    *) return 1 ;;
  esac
  _vstem=${_vb%.md}
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
  case "$_vrest" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) : ;;
    *) return 1 ;;
  esac
  _vslug=${_vrest#??????????-} # strip "YYYY-MM-DD-"
  _vdate=${_vrest%"-$_vslug"}  # the leading YYYY-MM-DD (captured before the clobber)
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

# is_entry_form <line> — 0 if the line is the one-line entry form
# `- <date> [<scope>] <text>` (shape only; the date's calendar validity is a
# separate step). Used to skip a fragment whose first content line is not an
# entry, and to select legacy entry lines.
is_entry_form() {
  case "$1" in
    "- "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" ["*"] "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- argument parsing ----------------------------------------------------

archived=0
obsdir="specs/_observations"
while [ $# -gt 0 ]; do
  case $1 in
    --archived)
      archived=1
      shift
      ;;
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

# An empty or hyphen-leading --obs-dir is a caller error, refused up front
# (mirrors obs-record.sh / check-obs.sh): an empty path would masquerade as
# "no root" and a '-' is read as an option by the tooling below.
[ -n "$obsdir" ] || {
  echo "$prog: observations directory must not be empty" >&2
  exit 2
}
case "$obsdir" in
  -*)
    echo "$prog: observations directory must not begin with a hyphen" >&2
    exit 2
    ;;
esac

entries="$obsdir/entries"
archive="$obsdir/archive"
legacy="$obsdir/opportunities.md"

# The keyed work file accumulates `<sortkey>\t<content>` rows; a final
# LC_ALL=C sort plus a key strip yields the byte-deterministic view. The
# content is sanitized before it lands here, so it carries no tab (0x09 is a
# stripped C0 byte) and the tab delimiter is unambiguous.
work=$(mktemp "${TMPDIR:-/tmp}/obs-render.XXXXXX") || {
  echo "$prog: cannot create a temporary work file" >&2
  exit 2
}
# A trapped signal does not itself terminate the shell in POSIX sh; split INT/
# TERM from the EXIT cleanup so a Ctrl-C re-exits (re-entering the EXIT trap
# that removes the work file) instead of resuming (house idiom, see obs-record).
trap 'rm -f "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# sort key: `<date>|<type>|<tiebreak>` — fixed-width, tab-free, so a plain
# LC_ALL=C sort over `<key>\t<content>` realizes the total order. <date> is 10
# chars; type 0 (legacy) sorts before type 1 (fragment) within a date; the
# tiebreak is a zero-padded file-order index for legacy and the 8-hex UID for
# fragments (both fixed width within their type). Keys are unique, so content
# never affects the order.
emit_row() {
  # emit_row <date> <type> <tiebreak> <content>
  printf '%s|%s|%s\t%s\n' "$1" "$2" "$3" "$(safe "$4")" >>"$work"
}

# --- fragments (entries/ live, and archive/ with --archived) -------------

collect_frags() {
  # collect_frags <dir> <type-is-archive:0|1>
  _fdir=$1
  _isarch=$2
  [ -d "$_fdir" ] || return 0
  # Never traverse a symlinked fragment directory (D-7); the guard refuses one
  # in CI, render simply declines to read through it.
  [ ! -L "$_fdir" ] || {
    warn "skipping symlinked fragment directory: $(safe "$_fdir")"
    return 0
  }
  for _f in "$_fdir"/*.md; do
    [ -e "$_f" ] || continue
    _name=${_f##*/}
    if [ -L "$_f" ]; then
      warn "skipping symlinked fragment: $(safe "$_name")"
      continue
    fi
    [ -f "$_f" ] || continue
    if ! valid_name "$_name"; then
      warn "skipping invalid fragment name: $(safe "$_name")"
      continue
    fi
    # One pure-shell pass over the (tiny) fragment: capture the first content
    # line and whether any `Consumed-by:` metadata line is present. No
    # subprocess per fragment, so the O(N) sweep stays cheap at scale.
    _first=""
    _gotfirst=0
    _consumed=0
    while IFS= read -r _line || [ -n "$_line" ]; do
      if [ "$_gotfirst" -eq 0 ]; then
        _first=$_line
        _gotfirst=1
      fi
      case "$_line" in
        Consumed-by:*) _consumed=1 ;;
      esac
    done <"$_f"
    if ! is_entry_form "$_first"; then
      warn "skipping fragment whose first line is not the entry form: $(safe "$_name")"
      continue
    fi
    # entries/ live view excludes a stuck consume (annotated but unmoved); the
    # drain pass surfaces it instead. archive/ fragments are consumed history
    # and are always included when --archived asked for them.
    if [ "$_isarch" -eq 0 ] && [ "$_consumed" -eq 1 ]; then
      continue
    fi
    _ftail=${_name#??????????} # everything after the 10-char YYYY-MM-DD
    _fdate=${_name%"$_ftail"}  # the leading YYYY-MM-DD
    _fstem=${_name%.md}
    _fuid=${_fstem##*-}
    emit_row "$_fdate" 1 "$_fuid" "$_first"
  done
}

collect_frags "$entries" 0
if [ "$archived" -eq 1 ]; then
  collect_frags "$archive" 1
fi

# --- frozen legacy file (unconsumed entry lines) -------------------------

if [ -f "$legacy" ] && [ ! -L "$legacy" ] && [ -r "$legacy" ]; then
  _idx=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _idx=$((_idx + 1))
    is_entry_form "$_line" || continue
    # A consumed legacy line carries an in-place `— consumed-by:` annotation
    # (the frozen-log convention); it is no longer live. Keyed on the substring
    # (legacy consumption is line-content-keyed by design, D-5).
    case "$_line" in
      *"consumed-by:"*) continue ;;
    esac
    _rest=${_line#"- "}
    _ldate=${_rest%% *}
    if ! valid_calendar_date "$_ldate"; then
      warn "skipping legacy entry line $_idx with an invalid date"
      continue
    fi
    _kidx=$(printf '%08d' "$_idx")
    emit_row "$_ldate" 0 "$_kidx" "$_line"
  done <"$legacy"
fi

# --- emit the ordered view (stdout only) ---------------------------------

# Unique keys make the sort a pure function of the input set; strip the key
# column to leave the sanitized content. cut -f2- keeps everything after the
# first tab, so a content line's own bytes are preserved verbatim.
if [ -s "$work" ]; then
  LC_ALL=C sort "$work" | cut -f2-
fi

exit 0
