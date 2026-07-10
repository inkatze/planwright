#!/bin/sh
# obs-consume.sh — the observation consumption + archival helper
# (observation-recording Task 4, REQ-A1.5, REQ-B1.2, REQ-C1.2, REQ-D1.1,
# REQ-D1.3; D-3, D-7). `/spec-draft` mining consumes an observation through this
# helper; no skill hand-composes a fragment path or an annotation.
#
# What it does (D-3): consuming a fragment resolves it by UID across entries/
# *and* archive/, appends a `Consumed-by: specs/<spec> (<date>)` line inside the
# fragment, then moves the file from entries/ to archive/ with its filename (and
# UID) preserved. Ordering is annotate-first, move-second, so a crash between
# the two leaves a visibly annotated fragment still in entries/ that a re-run
# completes; both halves are idempotent — the annotate is skipped when a
# same-spec `Consumed-by:` line already exists, and it is written atomically
# (temp file, then rename), so a re-run neither duplicates nor tears the
# annotation. UID resolution has defined edges: already archived with a
# same-spec annotation → clean no-op; no match → clean non-zero refusal;
# multiple matches (the D-2 duplicate window) → refusal naming every match,
# never a silent pick.
#
# The legacy arm (--legacy) annotates a frozen-log line in place instead of
# moving a file: frozen `opportunities.md` lines carry no UID (the accepted,
# shrinking brittleness D-5 names), so the line is located by fixed-string
# comparison (its content is never used as a pattern or format string, D-7),
# the annotation lands on exactly one line — the first unannotated exact match —
# and textually identical unconsumed lines are each independently consumable.
#
# Identity (REQ-A1.5): consumption keys on the UID, never on entry text, so a
# renamed slug or an edited entry still consumes cleanly and the archived
# filename preserves the UID — `obs:<uid>` stays a one-file citation after the
# move.
#
# Security posture (REQ-D1.1, REQ-D1.3, D-7): the UID and the spec identifier
# are validated against their anchored grammars under LC_ALL=C before any path
# use or before the spec id enters the `Consumed-by:` line; annotate and move
# operate only on regular files, never through symlinks; fragment and legacy
# content is data only — moved and matched verbatim, never evaluated, expanded,
# or used as a pattern. Hostile input is a clean refusal with no path touched
# and no raw input echoed to the terminal.
#
# Usage:
#   obs-consume.sh --uid <uid> --spec <spec> [--today <YYYY-MM-DD>] [--obs-dir <dir>]
#   obs-consume.sh --legacy --line <content> --spec <spec>
#                  [--today <YYYY-MM-DD>] [--obs-dir <dir>]
#
#   --uid      the 8-lowercase-hex fragment UID to consume (fragment arm)
#   --legacy   consume a frozen-log line instead of a fragment (legacy arm)
#   --line     the exact frozen-log line content to annotate (legacy arm)
#   --spec     the consuming spec identifier ([a-z0-9][a-z0-9-]*, ≤64 chars);
#              written into the `Consumed-by: specs/<spec> (<date>)` annotation
#   --today    pin the consume date (tests); defaults to the system date
#   --obs-dir  the observations dir holding entries/ + archive/ + the frozen
#              legacy files; defaults to specs/_observations under the repo cwd
#
# Exit codes: 0 success or clean no-op; 1 refusal (grammar, containment,
#   content, symlink, or an internal filesystem error); 2 usage error; 3 not
#   found (unknown UID, or no matching unconsumed legacy line); 4 ambiguous
#   (a UID matching more than one fragment — the D-2 duplicate window).
#
# Portable: POSIX sh + BSD tooling (bash 3.2 / BSD compatible); no eval, input
# treated as data only (the framework-script safety rule).
set -eu

# Pin the C locale: [a-z0-9] and friends are collation-dependent under UTF-8
# locales (uppercase collates into [a-z]); the pin makes charset validation a
# byte-range check (mirrors obs-record.sh and the sibling guards).
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes its destination into command substitutions,
# corrupting the canonicalized paths below.
unset CDPATH

prog=obs-consume

usage() {
  cat >&2 <<EOF
usage: $prog --uid <uid> --spec <spec> [--today <YYYY-MM-DD>] [--obs-dir <dir>]
       $prog --legacy --line <content> --spec <spec>
              [--today <YYYY-MM-DD>] [--obs-dir <dir>]
EOF
}

# refuse <exit-code> <message> — print a message that names the offending field
# but never echoes raw untrusted input, so no attacker-controlled byte reaches
# the terminal (the echo-discipline posture, satisfied by omission).
refuse() {
  echo "$prog: $2" >&2
  exit "$1"
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
# real calendar date (month 1-12, day within the month, leap Feb), else 1
# (mirrors obs-record.sh / check-obs.sh).
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

# --- argument parsing ----------------------------------------------------

uid=""
spec=""
line=""
today=""
obsdir="specs/_observations"
legacy=0
have_uid=0
have_line=0

while [ $# -gt 0 ]; do
  case $1 in
    --uid)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      uid=$2
      have_uid=1
      shift 2
      ;;
    --spec)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      spec=$2
      shift 2
      ;;
    --line)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      line=$2
      have_line=1
      shift 2
      ;;
    --legacy)
      legacy=1
      shift
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

# This helper takes no positional arguments; any surviving token is unexpected.
[ $# -eq 0 ] || {
  usage
  exit 2
}

# Arm selection: exactly one of the fragment arm (--uid) and the legacy arm
# (--legacy --line) may be active. --spec is required in both.
[ -n "$spec" ] || {
  usage
  exit 2
}
if [ "$legacy" -eq 1 ]; then
  # Legacy arm: --line required, --uid forbidden.
  { [ "$have_line" -eq 1 ] && [ "$have_uid" -eq 0 ]; } || {
    usage
    exit 2
  }
else
  # Fragment arm: --uid required, --line forbidden.
  { [ "$have_uid" -eq 1 ] && [ "$have_line" -eq 0 ]; } || {
    usage
    exit 2
  }
fi

# --- argument validation (before any path use) ---------------------------

# Spec identifier: [a-z0-9][a-z0-9-]* of at most 64 chars (the spec-format
# identifier discipline, bootstrap REQ-A1.8). Validated before it is written
# into the `Consumed-by:` line — traversal (`/`, `.`), glob (`*`, `?`),
# uppercase, whitespace, and control bytes are all outside the set (D-7).
[ "${#spec}" -ge 1 ] && [ "${#spec}" -le 64 ] \
  || refuse 1 "spec identifier must be 1 to 64 characters"
case "$spec" in
  [!a-z0-9]*) refuse 1 "spec identifier must begin with a lowercase alphanumeric" ;;
  *[!a-z0-9-]*) refuse 1 "spec identifier must be [a-z0-9-] (kebab-case)" ;;
esac

# Fragment UID: exactly 8 lowercase hex chars. The charset check rejects
# traversal, glob, uppercase, wrong length, and control bytes under the pinned
# C locale, before the UID is ever used to compose a glob or path.
if [ "$legacy" -eq 0 ]; then
  case "$uid" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) refuse 1 "uid must be exactly 8 lowercase hex characters" ;;
  esac
fi

# Date: mint today when unset, then validate shape + calendar validity for
# every source (a --today argument is untrusted like any other input).
if [ -z "$today" ]; then
  today=$(date +%F) || refuse 1 "cannot determine the current date"
fi
case "$today" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
  *) refuse 1 "date is not a well-formed YYYY-MM-DD" ;;
esac
valid_calendar_date "$today" || refuse 1 "date is not a real calendar date"

# --- observations directory containment ----------------------------------

# A leading '-' is refused before any path use (validate, contain, refuse; D-7):
# a bare '-' makes `cd "$obsdir"` a `cd -` that switches to $OLDPWD, silently
# rooting the store outside the named directory (mirrors obs-record.sh).
case "$obsdir" in
  -*) refuse 1 "observations directory must not begin with a hyphen" ;;
esac

# The observations root must already exist for a consume (fragments were
# recorded into it); a symlinked root would resolve the store outside the tree,
# so refuse it before canonicalizing (D-7, mirroring obs-record.sh).
[ -e "$obsdir" ] || refuse 3 "observations directory does not exist (nothing to consume)"
[ ! -L "$obsdir" ] || refuse 1 "observations directory path must not be a symlink"
[ -d "$obsdir" ] || refuse 1 "observations root exists but is not a directory"
canon_obs=$(cd "$obsdir" 2>/dev/null && pwd -P) \
  || refuse 1 "cannot resolve the observations directory"
entries="$canon_obs/entries"
archive="$canon_obs/archive"

# The annotation written inside a fragment (a metadata line) and appended to a
# legacy line (a suffix). The spec id is grammar-validated above, the date is
# calendar-validated; neither can carry a metacharacter.
consume_meta="Consumed-by: specs/$spec ($today)"
legacy_suffix=" — consumed-by: specs/$spec ($today)"

# fragment_annotated <file> — 0 if the fragment already carries a same-spec
# `Consumed-by: specs/<spec> (` line. Exact-prefix match via awk index(): the
# trailing " (" disambiguates spec `foo` from `foo-bar`. Content is data only —
# matched, never evaluated (D-7); the prefix is passed through the environment
# so awk's -v backslash processing never touches it.
fragment_annotated() {
  OBS_PREFIX="Consumed-by: specs/$spec (" awk '
    BEGIN { p = ENVIRON["OBS_PREFIX"] }
    index($0, p) == 1 { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# annotate_fragment <file> — append the Consumed-by metadata line atomically
# (temp file in the same directory, then a replacing rename), preserving the
# existing content verbatim and guaranteeing a separating newline. A crash
# leaves either the old file or the fully rewritten one, never a torn fragment.
annotate_fragment() {
  _src=$1
  _dir=${_src%/*}
  _tmp=$(mktemp "$_dir/.obs-consume.XXXXXX") \
    || refuse 1 "cannot create a temporary fragment file"
  # Preserve the source bytes exactly, then ensure a trailing newline before the
  # appended metadata so the annotation never joins the previous line.
  cat "$_src" >"$_tmp" || {
    rm -f "$_tmp"
    refuse 1 "cannot read the fragment (filesystem error)"
  }
  if [ -s "$_src" ] && [ -n "$(tail -c 1 "$_src")" ]; then
    printf '\n' >>"$_tmp"
  fi
  printf '%s\n' "$consume_meta" >>"$_tmp" || {
    rm -f "$_tmp"
    refuse 1 "cannot write the fragment annotation (filesystem error)"
  }
  mv -f "$_tmp" "$_src" || {
    rm -f "$_tmp"
    refuse 1 "cannot publish the fragment annotation (filesystem error)"
  }
}

# --- fragment arm --------------------------------------------------------

consume_fragment() {
  # Resolve the UID across both directories. The glob keys on `*-<uid>.md`; the
  # UID is grammar-validated, so the pattern is safe. Refuse a symlink match
  # before it is ever read or moved (operate only on regular files, D-7).
  match=""
  matchdir=""
  matches=""
  _n=0
  for _d in "$entries" "$archive"; do
    # A symlinked fragment directory is an escape vector — globbing through it
    # would resolve fragments outside the tree; refuse before reading (D-7).
    [ ! -L "$_d" ] || refuse 1 "fragment directory must not be a symlink"
    [ -d "$_d" ] || continue
    for _f in "$_d"/*-"$uid".md; do
      [ -e "$_f" ] || [ -L "$_f" ] || continue
      _base=${_f##*/}
      matches="$matches${matches:+ }${_d##*/}/$_base"
      _n=$((_n + 1))
      match=$_f
      matchdir=$_d
    done
  done

  [ "$_n" -ne 0 ] || refuse 3 "no fragment found for the given UID"
  if [ "$_n" -gt 1 ]; then
    echo "$prog: UID matches more than one fragment (re-mint one; D-2): $matches" >&2
    exit 4
  fi

  # A fragment is a real file the recording helper wrote, never a link that
  # could read/write through to outside the tree (D-7 containment symmetry).
  [ ! -L "$match" ] || refuse 1 "fragment must be a regular file, not a symlink"
  [ -f "$match" ] || refuse 1 "fragment is not a regular file"

  _name=${match##*/}

  # Already archived: a same-spec annotation means the consume is fully done
  # (clean no-op); otherwise this fragment was archived by another spec, so
  # annotate in place (union the citation) without a move — it is already home.
  if [ "$matchdir" = "$archive" ]; then
    if fragment_annotated "$match"; then
      exit 0
    fi
    annotate_fragment "$match"
    exit 0
  fi

  # Live fragment: annotate (conditionally — skipped on the crash-window re-run
  # where the annotation is already present), then move to archive/.
  fragment_annotated "$match" || annotate_fragment "$match"

  # Create archive/ on demand only now that a move is committed (a refusal above
  # touched no path). Refuse a symlinked archive/ and confirm containment.
  [ ! -L "$archive" ] || refuse 1 "archive path must not be a symlink"
  mkdir -p "$archive" 2>/dev/null || refuse 1 "cannot create the archive directory"
  canon_archive=$(cd "$archive" 2>/dev/null && pwd -P) \
    || refuse 1 "cannot resolve the archive directory"
  [ "$canon_archive" = "$archive" ] \
    || refuse 1 "archive path escapes the observations directory"

  dest="$archive/$_name"
  # The exactly-one-match guarantee means no archived fragment already carries
  # this filename; refuse rather than clobber if one somehow does (belt and
  # braces — never overwrite an archived fragment).
  [ ! -e "$dest" ] || refuse 1 "archive destination already exists (refusing to overwrite)"
  mv "$match" "$dest" || refuse 1 "cannot move the fragment to archive/ (filesystem error)"
  exit 0
}

# --- legacy arm ----------------------------------------------------------

consume_legacy() {
  frozen="$canon_obs/opportunities.md"
  [ -e "$frozen" ] || refuse 3 "no frozen legacy file to consume from"
  [ ! -L "$frozen" ] || refuse 1 "the frozen legacy file must not be a symlink"
  [ -f "$frozen" ] || refuse 1 "the frozen legacy file is not a regular file"

  # Locate and annotate the first line that exactly equals the target content
  # (fixed-string, never content-as-pattern — REQ-D1.3). The content is passed
  # through the environment so awk applies no backslash processing to it.
  _tmp=$(mktemp "$canon_obs/.obs-consume.XXXXXX") \
    || refuse 1 "cannot create a temporary work file"
  # `|| _arc=$?` keeps awk's "no bare match" exit (1) from tripping `set -e`
  # before it is inspected; the redirect still lands the (unchanged) copy.
  _arc=0
  OBS_LINE="$line" OBS_ANNOT="$line$legacy_suffix" awk '
    BEGIN { c = ENVIRON["OBS_LINE"]; a = ENVIRON["OBS_ANNOT"]; done = 0 }
    (!done && $0 == c) { print a; done = 1; next }
    { print }
    END { exit done ? 0 : 1 }
  ' "$frozen" >"$_tmp" || _arc=$?

  if [ "$_arc" -eq 0 ]; then
    # A line was annotated: publish the rewrite atomically.
    mv -f "$_tmp" "$frozen" \
      || {
        rm -f "$_tmp"
        refuse 1 "cannot publish the legacy annotation (filesystem error)"
      }
    exit 0
  fi

  rm -f "$_tmp"

  # No unannotated exact match. If a same-spec annotated copy already exists the
  # consume is idempotently done (clean no-op); otherwise the line is unknown
  # (absent, or consumed only by another spec) — a clean not-found refusal.
  if OBS_PREFIX="$line$legacy_suffix" awk \
    'BEGIN { p = ENVIRON["OBS_PREFIX"] }
     index($0, p) == 1 { found = 1 }
     END { exit found ? 0 : 1 }' "$frozen"; then
    exit 0
  fi
  refuse 3 "no matching unconsumed legacy line"
}

if [ "$legacy" -eq 1 ]; then
  consume_legacy
else
  consume_fragment
fi
