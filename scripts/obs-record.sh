#!/bin/sh
# obs-record.sh — the single shared observation-recording helper
# (observation-recording Task 1, REQ-A1.1..A1.6, REQ-B1.1, REQ-D1.1;
# D-1, D-2, D-6, D-7). Every recording skill drops one observation fragment
# through this helper; none composes a fragment path by hand and none appends
# to a shared committed log.
#
# What it does (REQ-A1.6): mint an 8-hex UID from a system entropy source,
# validate every filename component against its anchored grammar under
# LC_ALL=C (calendar-date validity included), containment-check the composed
# path after canonicalization, and publish the fragment atomically *and
# exclusively* — a temp file written in place, then a fail-on-exists hard-link
# publish (never a destination-replacing rename), so a crash mid-write leaves
# nothing and a racing writer can never clobber a fragment. Collisions retry
# with a freshly minted UID up to a small fixed cap; the collision check keys
# on the UID across entries/ *and* archive/ (D-2 kickoff decision), so an
# archived UID is never re-minted and `obs:<uid>` stays a one-file citation.
# Retry exhaustion and an unavailable entropy source are clean refusals.
#
# Fragment filename grammar (REQ-A1.2): <date>-<slug>-<uid>.md where <date> is
# a real calendar date YYYY-MM-DD, <slug> is a cosmetic kebab-case token
# [a-z0-9]+(-[a-z0-9]+)* of at most 40 chars, and <uid> is exactly 8 lowercase
# hex characters. Fragment content is the established one-line entry form
# `- <date> [<scope>] <text>` (REQ-A1.4); the date is minted as today, never a
# caller-facing backfill date; `--today` only pins the minted date for tests
# (no backfill exists — bulk conversion is out of scope).
#
# Security posture (REQ-D1.1, D-7 — carried from orchestration-concurrency
# REQ-F1.1): validate, contain, refuse. Every component is grammar-checked
# under the pinned C locale before any path use; a hostile component (path
# traversal, absolute path, uppercase, control byte) is a clean non-zero
# refusal with no path touched and no raw input echoed to the terminal; entry
# text carrying a newline or control character is refused at write time.
#
# Usage:
#   obs-record.sh --slug <slug> --scope <scope> --text <text>
#                 [--today <YYYY-MM-DD>] [--obs-dir <dir>]
#
#   --slug     cosmetic kebab-case topic token (filename only; renameable)
#   --scope    the `[<scope>]` bracket content (a repo/context identifier)
#   --text     the observation prose (single line; no newlines/control chars)
#   --today    pin the minted date (tests); defaults to the system date
#   --obs-dir  the observations dir holding entries/ + archive/;
#              defaults to specs/_observations under the host repo root (cwd) —
#              never the plugin root (D-6: the fragment store is the host
#              repo's even when the helper resolves plugin-relative)
#
# On success the created fragment path is printed to stdout and the exit is 0.
#
# Exit codes: 0 success; 1 refusal (grammar, containment, content, hostile
#   input, or an internal filesystem error); 2 usage error; 3 collision retry
#   exhausted; 4 entropy source unavailable.
#
# Portable: POSIX sh + BSD tooling (bash 3.2 / BSD compatible); no
# fish/mise/tmux dependency (the framework-runtime portability rule).
set -eu

# Pin the C locale: [a-z0-9] and friends are collation-dependent under UTF-8
# locales (uppercase collates into [a-z]); the pin makes charset validation a
# byte-range check (house pattern, see sibling scripts).
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes its destination into command substitutions,
# corrupting the canonicalized paths below.
unset CDPATH

# A small fixed retry cap: at planwright's entry rate 32 bits of entropy make a
# genuine collision astronomically rare, so this is only ever hit by the
# stubbed-entropy exhaustion test; kept small so a wedged entropy source fails
# fast rather than spinning.
MAX_RETRIES=16

prog=obs-record

usage() {
  cat >&2 <<EOF
usage: $prog --slug <slug> --scope <scope> --text <text>
              [--today <YYYY-MM-DD>] [--obs-dir <dir>]
EOF
}

# refuse <exit-code> <message> — print a message that names the offending
# field but never echoes raw untrusted input, so no attacker-controlled byte
# reaches the terminal (the echo-discipline posture, satisfied by omission).
refuse() {
  echo "$prog: $2" >&2
  exit "$1"
}

# strip0 <digits> — echo the number with leading zeros removed, so arithmetic
# never interprets a zero-padded field (08, 09) as invalid octal. Leaves a
# lone "0" intact.
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

# mint_uid — echo 8 lowercase hex characters read from the system entropy
# source via `od` (the PATH-resolvable reader the test suite stubs). Echoes an
# empty string on any read failure; the caller shape-checks the result.
mint_uid() {
  od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

# uid_present <uid> — 0 if any fragment carrying this UID already exists under
# entries/ or archive/ (the collision check keys on the UID, D-2). Null-safe
# over an absent archive/ (created on demand by the consume step, not here).
uid_present() {
  for _dir in "$entries" "$archive"; do
    for _f in "$_dir"/*-"$1".md; do
      [ -e "$_f" ] && return 0
    done
  done
  return 1
}

# --- argument parsing ----------------------------------------------------

slug=""
scope=""
text=""
today=""
obsdir="specs/_observations"
have_text=0

while [ $# -gt 0 ]; do
  case $1 in
    --slug)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      slug=$2
      shift 2
      ;;
    --scope)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      scope=$2
      shift 2
      ;;
    --text)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      text=$2
      have_text=1
      shift 2
      ;;
    --today)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      today=$2
      shift 2
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

# This helper takes no positional arguments; any token surviving the parse
# (e.g. after a `--`) is unexpected, so refuse rather than silently drop it.
[ $# -eq 0 ] || {
  usage
  exit 2
}

[ -n "$slug" ] || {
  usage
  exit 2
}
[ -n "$scope" ] || {
  usage
  exit 2
}
[ "$have_text" -eq 1 ] || {
  usage
  exit 2
}

# --- component validation (before any filesystem write) ------------------

# Date: mint today when unset, then validate shape + calendar validity for
# every source (a --today argument is untrusted like any other input). The
# `|| refuse` keeps an unavailable/broken `date` a clean refusal rather than a
# bare set -e abort mid-assignment.
if [ -z "$today" ]; then
  today=$(date +%F) || refuse 1 "cannot determine the current date"
fi
case "$today" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
  *) refuse 1 "date is not a well-formed YYYY-MM-DD" ;;
esac
valid_calendar_date "$today" || refuse 1 "date is not a real calendar date"
entry_date=$today

# Slug: 1..40 chars, kebab-case [a-z0-9]+(-[a-z0-9]+)*, no leading/trailing or
# doubled hyphen, lowercase alnum + single hyphens only. The charset check
# rejects path traversal (`.`/`/` are outside the set), uppercase, underscore,
# control bytes, and UTF-8 continuation bytes under the pinned C locale.
[ "${#slug}" -ge 1 ] && [ "${#slug}" -le 40 ] \
  || refuse 1 "slug must be 1 to 40 characters"
case "$slug" in
  -* | *-) refuse 1 "slug must not start or end with a hyphen" ;;
  *--*) refuse 1 "slug must not contain a doubled hyphen" ;;
esac
case "$slug" in
  *[!a-z0-9-]*) refuse 1 "slug must be lowercase kebab-case [a-z0-9-]" ;;
esac

# Scope: 1..64 chars, must open with an alphanumeric, and carry only
# [A-Za-z0-9._-]. Forbidding `[`, `]`, whitespace, and control bytes keeps the
# `[<scope>]` bracket mechanically parseable and echo-safe.
[ "${#scope}" -ge 1 ] && [ "${#scope}" -le 64 ] \
  || refuse 1 "scope must be 1 to 64 characters"
case "$scope" in
  [!A-Za-z0-9]*) refuse 1 "scope must begin with an alphanumeric" ;;
  *[!A-Za-z0-9._-]*) refuse 1 "scope must be an identifier token [A-Za-z0-9._-]" ;;
esac

# Text: non-empty and free of C0 control characters (newline, CR, tab, …) and
# DEL, so the fragment stays a single entry line (REQ-A1.4). C1 bytes
# (0x80-0x9F) are *allowed*: under UTF-8 they are the continuation bytes of
# legitimate multibyte prose (em-dash, smart quotes), so refusing them would
# reject valid entry text; the read-time posture here is content integrity,
# not the display sanitization the readers apply.
[ -n "$text" ] || refuse 1 "entry text must not be empty"
_tlen=$(printf '%s' "$text" | wc -c | tr -d ' ')
_slen=$(printf '%s' "$text" | tr -d '\000-\037\177' | wc -c | tr -d ' ')
[ "$_tlen" = "$_slen" ] \
  || refuse 1 "entry text must not contain newlines or control characters"

# --- directory setup + containment ---------------------------------------

# Validate/contain before create (D-7). Create only the observations root
# first and canonicalize it, so the containment check runs against a resolved
# base rather than riding an entries/ that a mkdir followed through a symlink.
# Suppress mkdir's stderr (as the sibling `cd` canonicalizations do): on
# failure it echoes the caller-supplied --obs-dir path, and the sanitized
# `refuse` message is the only terminal output the echo-discipline posture
# permits.
mkdir -p "$obsdir" 2>/dev/null || refuse 1 "cannot create the observations directory"
# Reject a symlinked observations root before canonicalizing it — the same
# escape vector the entries/ guard below closes, one level up. `cd ... && pwd -P`
# would silently resolve a symlinked obs-dir to its target and root the whole
# store there; refuse it so the fragment store stays where the caller named it.
[ ! -L "$obsdir" ] || refuse 1 "observations directory path must not be a symlink"
canon_obs=$(cd "$obsdir" 2>/dev/null && pwd -P) \
  || refuse 1 "cannot resolve the observations directory"
entries="$canon_obs/entries"
archive="$canon_obs/archive"

# A real entries/ is always a directory; a symlink is precisely the escape
# vector containment exists to close. Reject it here — before any mkdir — so a
# dangling escape target is never materialized as a side effect on a platform
# whose mkdir -p would follow it.
[ ! -L "$entries" ] || refuse 1 "entries path must not be a symlink"

mkdir -p "$entries" 2>/dev/null || refuse 1 "cannot create the entries directory"

# Re-canonicalize entries/ after creation and confirm it resolves to exactly
# <obs-dir>/entries. `entries` is the canonical path, used verbatim for the
# write below, so nothing is reopened by a non-canonical name between this
# check and the publish.
canon_entries=$(cd "$entries" 2>/dev/null && pwd -P) \
  || refuse 1 "cannot resolve the entries directory"
[ "$canon_entries" = "$entries" ] \
  || refuse 1 "entries path escapes the observations directory"

entry_line="- $entry_date [$scope] $text"

# --- mint, then atomic exclusive publish with bounded retry --------------

_tmp=""
# EXIT is the cleanup; INT/TERM re-`exit` rather than share the EXIT handler.
# A trapped signal does not itself terminate the shell in POSIX sh, so a
# cleanup-only INT/TERM handler would run and then *resume* the publish loop
# (surprising after a Ctrl-C, and out of step with the sibling scripts). The
# re-`exit` re-enters the EXIT trap, so the temp is still removed. House idiom,
# see scripts/fleet-attention.sh.
trap 'if [ -n "$_tmp" ]; then rm -f "$_tmp"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
  attempt=$((attempt + 1))

  uid=$(mint_uid)
  case "$uid" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) refuse 4 "entropy source unavailable (no valid UID minted)" ;;
  esac

  # Same-tree collision: retry with a fresh UID (keys on the UID, D-2).
  if uid_present "$uid"; then
    continue
  fi

  fragname="$entry_date-$slug-$uid.md"
  dest="$entries/$fragname"

  # Atomic exclusive publish: write a temp file in entries/ (same filesystem),
  # then hard-link it into place. `ln` without -f fails when the destination
  # exists, so a racing writer that created the same name between the check
  # above and this publish is caught here — never overwritten.
  _tmp=$(mktemp "$entries/.obs-record.XXXXXX") \
    || refuse 1 "cannot create a temporary fragment file"
  printf '%s\n' "$entry_line" >"$_tmp" \
    || refuse 1 "cannot write the fragment (filesystem error)"
  if ln "$_tmp" "$dest" 2>/dev/null; then
    rm -f "$_tmp"
    _tmp=""
    # Report the fragment in the caller's own frame (the passed --obs-dir),
    # not the canonicalized path used internally for the write.
    printf '%s\n' "$obsdir/entries/$fragname"
    exit 0
  fi
  # Publish failed. Drop the temp, then distinguish the two causes: if the
  # destination now exists, a racing writer won the name — retry with a fresh
  # UID. If it does not exist, `ln` itself is unusable (a filesystem failure,
  # not a collision): refuse cleanly rather than burning retries and
  # mislabeling it as exhaustion.
  rm -f "$_tmp"
  _tmp=""
  [ -e "$dest" ] || refuse 1 "cannot publish the fragment (filesystem error)"
done

refuse 3 "collision retry exhausted; no fragment written"
