#!/bin/sh
# step-record.sh — write, list, and render custom-steps records, and
# regenerate the pending-sign-off checklist (custom-steps Task 4; REQ-D1.5,
# REQ-E1.2, REQ-H1.3; D-12, D-16).
# doctrine/custom-steps.md (*Records*) is the normative home of what a record
# holds and where it folds; doctrine/gate-wiring.md owns the checklist format.
# This header pins what those docs delegate here: the verbs, the storage
# layout, the excerpt bound, the screen action, and the rendered shapes.
#
# Usage:
#   step-record.sh [--worktree <dir>] new-run
#   step-record.sh [--worktree <dir>] write --run <id> --point <point>
#       --step <id> --kind <kind> --target <target> --hosting <hosting>
#       --backend <name> --head <sha> --start <ts> --end <ts>
#       --outcome <outcome> [--session <id>] [--excerpt-file <file>]
#       [--output <path>] [--skip-reason <text>]
#   step-record.sh [--worktree <dir>] write --completion --run <id>
#       --point <point> --head <sha> [--warning <text>]...
#   step-record.sh [--worktree <dir>] list [--run <id>] [--point <point>]
#   step-record.sh [--worktree <dir>] render [--run <id>] [--point <point>]...
#   step-record.sh [--worktree <dir>] regenerate --base <rev> --head <rev>
#       [--run <id>]
#
#   --worktree    the unit's worktree; default the enclosing git top level.
#                 The cache is <worktree>/.claude/steps/, created mode 0700;
#                 a cache, run directory, or record that is a symlink is
#                 refused, as is one that cannot be read.
#   new-run       issue the next run id (six digits, zero-padded, one past
#                 the highest in the cache) and print it. A run is one unit
#                 run or flip attempt; run ids order attempts, the latest
#                 being the highest id.
#   write         validate every field, then write one record and print its
#                 absolute path (the value a later step's
#                 PLANWRIGHT_STEP_PREV_RECORD carries). --completion writes
#                 the point-completion record instead; --warning repeats. A
#                 point fires once per run: a step or completion record for a
#                 point the run already completed is refused. A repeated
#                 write is a second record; retrying is the caller's call.
#   list          print every record of the run (every run when --run is
#                 absent), oldest first, optionally one point's only: a
#                 `record<TAB><worktree-relative path>` line, the record's
#                 stored lines, then a blank line.
#   render        print one markdown table per point of the run (default the
#                 latest run holding a record), in the order the points first
#                 recorded, or the named points in the order given.
#   regenerate    print the pending-sign-off checklist rebuilt from the
#                 marked commits of <base>..<head>, then, when the run
#                 (default as for render) renders anything, a blank line and
#                 that render.
#
# Field grammar (write refuses a violation with exit 2, naming the field and
# never echoing its value; no value is ever interpolated before it passes):
#   --run          an issued run id: six digits naming an existing run dir
#   --point        a name from doctrine/custom-steps.md's vocabulary
#   --step         ^[a-z][a-z0-9-]*$, at most 64 bytes, never `implementation`
#   --kind         skill | command | prompt
#   --hosting      isolated | continue | in-session
#   --backend      ^[a-z0-9][a-z0-9-]*$, at most 64 bytes (the backend
#                  identifier charset)
#   --session      [A-Za-z0-9._:-], 1 to 128 bytes; optional
#   --head         a full commit id: 40 or 64 lowercase hex digits
#   --start/--end  YYYY-MM-DDTHH:MM:SSZ
#   --outcome      passed | applied | halted | failed | skipped; skipped
#                  requires --skip-reason, and --skip-reason requires skipped
#   --target, --skip-reason, --warning
#                  non-empty single-line text, no C0 control byte or DEL, at
#                  most 1024 bytes
#   --output       an existing regular file under the cache, absolute or
#                  relative to the worktree, stored worktree-relative
#
# Storage: <cache>/<run>/<seq>-step-<point>-<step>.rec and
# <cache>/<run>/<seq>-done-<point>.rec, <seq> three digits unique within the
# run and increasing in write order (each claimed atomically), at most 999
# records a run. A record is `<key><TAB><value>` lines: type, run, seq, then
# the fields above under their flag names (skip-reason for --skip-reason), an
# empty optional field stored empty; `excerpt` and `warning` lines repeat.
# Records are mode 0600. Its form is unstable to anything but this helper.
#
# Text cleaning, applied to every stored text value, the excerpt, and the
# commit text regenerate reads: tabs become spaces; carriage returns and
# every other C0 control byte and DEL are stripped; invalid UTF-8 is dropped;
# C1 controls and the invisible and bidi-control code points are stripped
# (the list scripts/flight-dispatch.sh's INVIS_SED names).
#
# The excerpt (--excerpt-file): the whole cleaned output is screened through
# scripts/inception-secret-screen.sh (the repository's secret screen,
# honoring PLANWRIGHT_SECRET_SCREEN_TOOL), then its last 20 lines, cut to the
# last 2000 bytes (a character the cut splits dropped), are kept. Screen
# action: on a hit the excerpt is withheld and stored as one placeholder
# line; a screen that cannot run withholds it the same way, never passing it
# unscreened. The step, target, backend, session, output, and skip-reason
# values, and each warning, pass the same screen, a hit storing a
# placeholder in the value's place. The full captured output stays where
# --output names, unscreened.
#
# Rendered table (render, regenerate): per point,
#   ## Steps at `<point>` (run `<id>`)
# then a table with the columns
#   # | Step | Kind | Target | Hosting | Backend | Session | Head | Start |
#   End | Outcome | Excerpt | Output
# one row per step record (Outcome reads `skipped: <reason>` for a skip; the
# excerpt's lines join with ` / `; Head shows 12 characters), or a single
# `none` row when the point has only its completion record; then
# `Ended on `<head>`.` when a completion record exists, and one
# `- Warning: <text>` line per warning.
#
# Neutralizing, applied to every rendered cell, warning, and checklist text:
# `&`, `<`, and `>` become entities; a zero-width space (`&#8203;`) follows
# every `@` and `#`, splits `://`, `www.`, and `GH-`, so no mention, issue
# reference, closing keyword, or autolink survives; and `\`, `|`, backtick,
# `*`, `_`, `[`, `]`, `~`, `(`, `)`, and `!` are backslash-escaped, so no
# markup, link, or image survives either.
#
# Checklist (regenerate), per doctrine/gate-wiring.md: a commit in the range
# is marked by a `Planwright-Sign-Off: PS-<n>` trailer (read through git's
# trailer parser) or, legacy, a `[pending-sign-off]` subject suffix (rendered
# with the ID `legacy`, the suffix dropped). A marked commit drops out when a
# commit in the range that is not itself undone carries `This reverts commit
# <its full sha>.` in its body, or when its PS ID is named by a
# `Planwright-Sign-Off-Rejected:` trailer in the range (a legacy entry has no
# ID a trailer can name). Entries order by ID number, legacy entries last in
# commit order; an ID marked twice keeps its oldest live commit. An entry is
#   - [ ] **<id>** <subject> · commit `<sha7>`
#     - Route reason: <the body's first `Route reason:` line, or `not
#       recorded in the commit`>
#     - <each manifest line: a body line `- <file> — before: …`, joined with
#       the indented lines that continue it>
#     - Reject with: `git revert <sha7>` (plus the hand-edit note when a
#       manifest is present)
# An empty checklist renders `- none`. A <base> or <head> that does not
# resolve, or a range git cannot read, fails by name.
#
# Exit: 0 success · 1 a runtime failure (an unresolvable or unreadable range,
# a cache that cannot be read or written, an exhausted counter) · 2 a usage
# or field-validation error.
#
# Portable POSIX sh + awk + iconv; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 1
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

prog='step-record.sh'
TAB=$(printf '\t')
LF='
'
EXCERPT_LINES=20
EXCERPT_BYTES=2000
TEXT_MAX=1024

# The byte sequences of the C1 controls, then the invisible and bidi-control
# code points, deleted bytewise; the second list is flight-dispatch.sh's.
INVIS_SED=$(printf 's/\302[\200-\237]//g;s/\302[\205\255]//g;s/\330\234//g;s/\341\205[\237\240]//g;s/\341\236[\264\265]//g;s/\341\240\216//g;s/\342\200[\213-\217\250-\256]//g;s/\342\201[\240-\244\246-\257]//g;s/\343\205\244//g;s/\357\270[\200-\217]//g;s/\357\273\277//g;s/\357\276\240//g;s/\357\277[\271-\273]//g;s/\363\240[\200\201][\200-\277]//g;s/\363\240[\204-\206][\200-\277]//g;s/\363\240\207[\200-\257]//g')

# Word splitting only on newlines, and no globbing: record paths live under a
# worktree path that may carry blanks.
IFS=$LF
set -f

work=''
pending=''
cleanup() {
  [ -z "$pending" ] || rm -f "$pending"
  [ -z "$work" ] || rm -rf "$work"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}
usage() {
  sed -n '/^# Usage:/,/^# Field grammar/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
  exit 2
}
# bad <flag> <reason>: a refused field, named, its value never echoed.
bad() { die 2 "$1: $2"; }

# scratch: the one temporary directory, made in the main shell so its
# cleanup trap runs.
scratch() {
  [ -n "$work" ] && return 0
  work=$(mktemp -d "${TMPDIR:-/tmp}/step-record.XXXXXX") || die 1 "cannot create a temporary directory"
}

# has_ctl <value>: true when the value carries a C0 control byte or DEL.
has_ctl() {
  case $1 in *[[:cntrl:]]*) return 0 ;; esac
  return 1
}

is_text() {
  [ -n "$1" ] && ! has_ctl "$1" && [ "${#1}" -le "$TEXT_MAX" ]
}

# The vocabulary resolve-steps.sh's WIRED_POINTS and UNWIRED_POINTS hold; the
# two lists change together.
is_point() {
  case $1 in
    pre-implementation | pre-ci | convergence | pre-pr | post-pr | pre-ready-flip | \
      pre-spec-ready-flip | spec-drafted | kickoff-signed-off | unit-selected | \
      pre-dispatch | post-dispatch | unit-halted | post-merge | orchestrator-idle) return 0 ;;
  esac
  return 1
}

is_step_id() {
  case $1 in '' | [!a-z]* | *[!a-z0-9-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

is_backend() {
  case $1 in '' | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

is_session() {
  case $1 in '' | *[!A-Za-z0-9._:-]*) return 1 ;; esac
  [ "${#1}" -le 128 ]
}

is_head() {
  case $1 in *[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

is_ts() {
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
  esac
  return 1
}

is_run_id() {
  case $1 in [0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;; esac
  return 1
}

# clean <in> <out>: the text cleaning the header pins. The invisible strip
# repeats until stable, since one deletion can join its neighbours into
# another code point.
clean() {
  tr '\t' ' ' <"$1" | tr -d '\000-\010\013-\037\177' | iconv -c -f UTF-8 -t UTF-8 >"$2.1" 2>/dev/null
  [ -f "$2.1" ] || die 1 "cannot clean text"
  while :; do
    sed "$INVIS_SED" <"$2.1" >"$2.2" || die 1 "cannot clean text"
    cmp -s "$2.1" "$2.2" && break
    mv "$2.2" "$2.1" || die 1 "cannot clean text"
  done
  mv "$2.1" "$2" || die 1 "cannot clean text"
  rm -f "$2.2"
}

# clean_value <value>: sets CLEANED to the cleaned value.
clean_value() {
  scratch
  printf '%s\n' "$1" >"$work/value" || die 1 "cannot write a temporary file"
  clean "$work/value" "$work/value.clean"
  CLEANED=$(cat "$work/value.clean")
}

# screen <file>: sets SCREEN_RC to the secret screen's verdict on the file
# (0 clean, 1 flagged, 2 could not screen).
screen() {
  SCREEN_RC=0
  if [ -r "$script_dir/inception-secret-screen.sh" ]; then
    /bin/sh "$script_dir/inception-secret-screen.sh" -- "$1" >/dev/null 2>&1 || SCREEN_RC=$?
  else
    SCREEN_RC=2
  fi
  [ "$SCREEN_RC" -le 1 ] || SCREEN_RC=2
}

withheld() {
  if [ "$SCREEN_RC" -eq 1 ]; then
    printf '[withheld: the secret screen flagged this %s]' "$1"
  else
    printf '[withheld: the %s could not be screened]' "$1"
  fi
}

# screen_values <label> <value>...: write the values to $work/screened, one
# line each (an empty value an empty line), each replaced by its placeholder
# when the screen does not pass it. One screen call covers the batch; only a
# batch that does not pass is screened value by value, to name which values
# to withhold.
screen_values() {
  scratch
  sv_label=$1
  shift
  : >"$work/batch" || die 1 "cannot write a temporary file"
  for v in "$@"; do printf '%s\n' "$v" >>"$work/batch"; done
  screen "$work/batch"
  sv_all=$SCREEN_RC
  : >"$work/screened"
  for v in "$@"; do
    if [ "$sv_all" -ne 0 ] && [ -n "$v" ]; then
      printf '%s\n' "$v" >"$work/one"
      screen "$work/one"
      [ "$SCREEN_RC" -eq 0 ] || v=$(withheld "$sv_label")
    fi
    printf '%s\n' "$v" >>"$work/screened" || die 1 "cannot write a temporary file"
  done
}

# --- global option and verb ---------------------------------------------------
worktree=''
while [ $# -gt 0 ]; do
  case $1 in
    --worktree)
      [ $# -ge 2 ] || usage
      worktree=$2
      shift 2
      ;;
    -h | --help) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
verb=$1
shift

if [ -z "$worktree" ]; then
  command -v git >/dev/null 2>&1 || die 1 "git is not on PATH"
  worktree=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "--worktree: not given and not inside a git work tree"
fi
[ -d "$worktree" ] || bad --worktree "not a directory"
worktree=$(cd "$worktree" && pwd -P) || bad --worktree "not readable"
cache="$worktree/.claude/steps"

# check_dir <dir>: refuse a symlinked or unreadable cache directory.
check_dir() {
  [ ! -L "$1" ] || die 1 "the record cache holds a symlink; refusing it"
  [ ! -e "$1" ] || { [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ]; } || die 1 "the record cache cannot be read"
}

# glob_names <dir> <pattern>: the names in <dir> matching <pattern>, sorted,
# one per line (globbing is off everywhere else).
glob_names() {
  set +f
  for _g in "$1"/$2; do
    if [ -e "$_g" ] || [ -L "$_g" ]; then printf '%s\n' "${_g##*/}"; fi
  done
  set -f
}

run_ids() {
  [ -d "$cache" ] || return 0
  glob_names "$cache" '[0-9][0-9][0-9][0-9][0-9][0-9]'
}

# check_run <run>: refuse a run directory, or a record in it, that is a
# symlink or cannot be read. Runs in the main shell, before any listing
# below reads the run inside a command substitution, where a refusal could
# not end the script.
check_run() {
  check_dir "$cache/$1"
  for _f in $(glob_names "$cache/$1" '[0-9][0-9][0-9]-*.rec'); do
    _p="$cache/$1/$_f"
    { [ ! -L "$_p" ] && [ -f "$_p" ] && [ -r "$_p" ]; } || die 1 "a record cannot be read"
  done
}

# record_files <run>: the run's record paths in seq order (check_run first).
record_files() {
  for _f in $(glob_names "$cache/$1" '[0-9][0-9][0-9]-*.rec'); do
    printf '%s\n' "$cache/$1/$_f"
  done
}

valid_run() {
  is_run_id "$1" || bad --run "not a run id"
  [ -d "$cache/$1" ] || bad --run "no such run in the cache"
  check_run "$1"
}

# latest_run: sets LATEST to the highest run id holding a record, if any.
latest_run() {
  LATEST=''
  for _r in $(run_ids); do
    check_run "$_r"
    [ -z "$(record_files "$_r")" ] || LATEST=$_r
  done
}

# --- new-run -------------------------------------------------------------------
cmd_new_run() {
  [ $# -eq 0 ] || usage
  mkdir -p "$cache" || die 1 "cannot create the record cache"
  last=$(run_ids | tail -n 1)
  next=$((1${last:-000000} - 1000000 + 1))
  while :; do
    [ "$next" -le 999999 ] || die 1 "the run-id counter is exhausted"
    id=$(printf '%06d' "$next")
    if mkdir "$cache/$id" 2>/dev/null; then
      printf '%s\n' "$id" || die 1 "cannot print the run id"
      return 0
    fi
    [ -d "$cache/$id" ] || die 1 "cannot create a run directory"
    next=$((next + 1))
  done
}

# --- write ------------------------------------------------------------------------
# claim <run> <stem> <type> <body-file>: write the record under the run's
# next sequence number, claimed atomically, and print its absolute path.
claim() {
  dir="$cache/$1"
  last=$(glob_names "$dir" '.seq-[0-9][0-9][0-9]' | tail -n 1)
  last=${last#.seq-}
  next=$((1${last:-000} - 1000 + 1))
  while :; do
    [ "$next" -le 999 ] || die 1 "the run's record counter is exhausted"
    seq=$(printf '%03d' "$next")
    mkdir "$dir/.seq-$seq" 2>/dev/null && break
    [ -d "$dir/.seq-$seq" ] || die 1 "cannot write to the record cache"
    next=$((next + 1))
  done
  pending="$dir/.rec-$seq"
  { printf 'type\t%s\nrun\t%s\nseq\t%s\n' "$3" "$1" "$seq" && cat "$4"; } >"$pending" \
    || die 1 "cannot write to the record cache"
  path="$dir/$seq-$2.rec"
  ln "$pending" "$path" || die 1 "cannot write to the record cache"
  rm -f "$pending"
  pending=''
  printf '%s\n' "$path" || die 1 "cannot print the record path"
}

# completed <run> <point>: true when the run holds the point's completion.
completed() {
  for _f in $(record_files "$1"); do
    case ${_f##*/} in [0-9][0-9][0-9]-done-"$2".rec) return 0 ;; esac
  done
  return 1
}

cmd_write() {
  completion=0 run='' point='' step='' kind='' target='' hosting='' backend=''
  session='' head='' start='' end='' outcome='' excerpt_file='' output=''
  skip_reason='' warnings=''
  while [ $# -gt 0 ]; do
    case $1 in
      --completion)
        completion=1
        shift
        continue
        ;;
      --run | --point | --step | --kind | --target | --hosting | --backend | \
        --session | --head | --start | --end | --outcome | --excerpt-file | \
        --output | --skip-reason | --warning)
        [ $# -ge 2 ] || usage
        ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point) point=$2 ;;
      --step) step=$2 ;;
      --kind) kind=$2 ;;
      --target) target=$2 ;;
      --hosting) hosting=$2 ;;
      --backend) backend=$2 ;;
      --session) session=$2 ;;
      --head) head=$2 ;;
      --start) start=$2 ;;
      --end) end=$2 ;;
      --outcome) outcome=$2 ;;
      --excerpt-file) excerpt_file=$2 ;;
      --output) output=$2 ;;
      --skip-reason) skip_reason=$2 ;;
      --warning)
        is_text "$2" || bad --warning "must be non-empty single-line text of at most $TEXT_MAX bytes"
        warnings="$warnings$2$LF"
        ;;
    esac
    shift 2
  done

  [ -n "$run" ] || bad --run "required"
  valid_run "$run"
  is_point "$point" || bad --point "not a point of the vocabulary"
  is_head "$head" || bad --head "not a full commit id"
  ! completed "$run" "$point" || bad --point "already completed in this run"

  if [ "$completion" -eq 1 ]; then
    for f in "$step" "$kind" "$target" "$hosting" "$backend" "$session" \
      "$start" "$end" "$outcome" "$excerpt_file" "$output" "$skip_reason"; do
      [ -z "$f" ] || bad --completion "takes only --run, --point, --head, and --warning"
    done
    scratch
    cleaned=''
    for w in $warnings; do
      clean_value "$w"
      cleaned="$cleaned$CLEANED$LF"
    done
    # shellcheck disable=SC2086 # split on newlines by design (IFS)
    screen_values warning $cleaned
    {
      printf 'point\t%s\nhead\t%s\n' "$point" "$head"
      [ -z "$cleaned" ] || while IFS= read -r w; do
        printf 'warning\t%s\n' "$w"
      done <"$work/screened"
    } >"$work/body" || die 1 "cannot write a temporary file"
    claim "$run" "done-$point" completion "$work/body"
    return
  fi
  [ -z "$warnings" ] || bad --warning "belongs to write --completion"

  is_step_id "$step" || bad --step "not a step id"
  [ "$step" != implementation ] || bad --step "reserved for the implementation phase"
  case $kind in skill | command | prompt) ;; *) bad --kind "not skill, command, or prompt" ;; esac
  is_text "$target" || bad --target "must be non-empty single-line text of at most $TEXT_MAX bytes"
  case $hosting in isolated | continue | in-session) ;; *) bad --hosting "not isolated, continue, or in-session" ;; esac
  is_backend "$backend" || bad --backend "not a backend name"
  [ -z "$session" ] || is_session "$session" || bad --session "not a session id"
  is_ts "$start" || bad --start "not YYYY-MM-DDTHH:MM:SSZ"
  is_ts "$end" || bad --end "not YYYY-MM-DDTHH:MM:SSZ"
  case $outcome in passed | applied | halted | failed | skipped) ;; *) bad --outcome "not passed, applied, halted, failed, or skipped" ;; esac
  if [ "$outcome" = skipped ]; then
    is_text "$skip_reason" || bad --skip-reason "required for a skipped step, as single-line text of at most $TEXT_MAX bytes"
  elif [ -n "$skip_reason" ]; then
    bad --skip-reason "only a skipped step carries one"
  fi
  rel_output=''
  if [ -n "$output" ]; then
    is_text "$output" || bad --output "not a single-line path"
    case $output in /*) ;; *) output="$worktree/$output" ;; esac
    [ -f "$output" ] && [ ! -L "$output" ] || bad --output "not an existing regular file"
    _od=$(cd "$(dirname "$output")" 2>/dev/null && pwd -P) || bad --output "not an existing regular file"
    output="$_od/${output##*/}"
    case $output in
      "$cache"/*) rel_output=${output#"$worktree"/} ;;
      *) bad --output "outside the record cache" ;;
    esac
  fi
  if [ -n "$excerpt_file" ]; then
    [ -f "$excerpt_file" ] && [ -r "$excerpt_file" ] || bad --excerpt-file "not a readable file"
  fi

  scratch
  clean_value "$target"
  target=$CLEANED
  if [ -n "$skip_reason" ]; then
    clean_value "$skip_reason"
    skip_reason=$CLEANED
  fi
  screen_values value "$step" "$target" "$backend" "$session" "$rel_output" "$skip_reason"
  i=0
  while IFS= read -r l; do
    i=$((i + 1))
    case $i in
      1) s_step=$l ;;
      2) s_target=$l ;;
      3) s_backend=$l ;;
      4) s_session=$l ;;
      5) s_output=$l ;;
      6) s_skip=$l ;;
    esac
  done <"$work/screened"

  : >"$work/excerpt"
  if [ -n "$excerpt_file" ]; then
    clean "$excerpt_file" "$work/excerpt.full"
    screen "$work/excerpt.full"
    if [ "$SCREEN_RC" -eq 0 ]; then
      tail -n "$EXCERPT_LINES" "$work/excerpt.full" | tail -c "$EXCERPT_BYTES" \
        | iconv -c -f UTF-8 -t UTF-8 >"$work/excerpt" 2>/dev/null
    else
      withheld excerpt >"$work/excerpt"
      printf '\n' >>"$work/excerpt"
    fi
  fi

  {
    printf 'point\t%s\nstep\t%s\nkind\t%s\ntarget\t%s\nhosting\t%s\n' \
      "$point" "$s_step" "$kind" "$s_target" "$hosting"
    printf 'backend\t%s\nsession\t%s\nhead\t%s\nstart\t%s\nend\t%s\n' \
      "$s_backend" "$s_session" "$head" "$start" "$end"
    printf 'outcome\t%s\noutput\t%s\nskip-reason\t%s\n' \
      "$outcome" "$s_output" "$s_skip"
    while IFS= read -r line || [ -n "$line" ]; do
      printf 'excerpt\t%s\n' "$line"
    done <"$work/excerpt"
  } >"$work/body" || die 1 "cannot write a temporary file"
  claim "$run" "step-$point-$step" step "$work/body"
}

# --- list -----------------------------------------------------------------------
cmd_list() {
  run='' point=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point) point=$2 ;;
    esac
    shift 2
  done
  [ -z "$run" ] || valid_run "$run"
  [ -z "$point" ] || is_point "$point" || bad --point "not a point of the vocabulary"
  if [ -n "$run" ]; then runs=$run; else runs=$(run_ids); fi
  for r in $runs; do
    check_run "$r"
    for f in $(record_files "$r"); do
      if [ -n "$point" ]; then
        grep -Fxq "point$TAB$point" "$f" || continue
      fi
      printf 'record\t%s\n' "${f#"$worktree"/}"
      cat "$f" || die 1 "a record cannot be read"
      printf '\n'
    done
  done
}

# --- render ----------------------------------------------------------------------
# safe(s): the neutralizing the header pins, shared by both renderers.
AWK_SAFE='
function safe(s,    out, i, n, c, z) {
  out = ""; n = length(s); z = "&#8203;"
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "&") c = "&amp;"
    else if (c == "<") c = "&lt;"
    else if (c == ">") c = "&gt;"
    else if (c == "@" || c == "#") c = c z
    else if (c == ":" && substr(s, i + 1, 2) == "//") { c = ":/" z "/"; i += 2 }
    else if (tolower(substr(s, i, 4)) == "www.") { c = substr(s, i, 3) z "."; i += 3 }
    else if (c == "-" && i > 2 && tolower(substr(s, i - 2, 2)) == "gh") c = z "-"
    else if (index("\\|`*_[]~()!", c)) c = "\\" c
    out = out c
  }
  return out
}
'

# render_run <run> [<point>...]: the tables, points in the order given or,
# given none, the order they first recorded.
render_run() {
  r=$1
  shift
  files=$(record_files "$r")
  [ -n "$files" ] || return 0
  want=''
  for _w in "$@"; do want="$want $_w"; done
  # shellcheck disable=SC2086 # split on newlines by design (IFS)
  awk -v run="$r" -v want="$want" -v TAB="$TAB" "$AWK_SAFE"'
    FNR == 1 { k++ }
    {
      t = index($0, TAB); key = substr($0, 1, t - 1); val = substr($0, t + 1)
      if (key == "excerpt") ex[k] = ex[k] (ex[k] == "" ? "" : " / ") safe(val)
      else if (key == "warning") { nw[k]++; W[k, nw[k]] = val }
      else F[k, key] = val
    }
    END {
      np = split(want, P, " ")
      if (np == 0) {
        np = 0
        for (i = 1; i <= k; i++) if (!(F[i, "point"] in seen)) { seen[F[i, "point"]] = 1; P[++np] = F[i, "point"] }
      }
      first = 1
      for (p = 1; p <= np; p++) {
        pt = P[p]; any = 0
        for (i = 1; i <= k; i++) if (F[i, "point"] == pt) any = 1
        if (!any) continue
        if (!first) print ""
        first = 0
        printf "## Steps at `%s` (run `%s`)\n\n", safe(pt), safe(run)
        print "| # | Step | Kind | Target | Hosting | Backend | Session | Head | Start | End | Outcome | Excerpt | Output |"
        print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        rows = 0; done = 0
        for (i = 1; i <= k; i++) {
          if (F[i, "point"] != pt) continue
          if (F[i, "type"] == "completion") { done = i; continue }
          rows++
          outc = F[i, "outcome"]
          if (outc == "skipped") outc = outc ": " F[i, "skip-reason"]
          printf "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", rows,
            safe(F[i, "step"]), safe(F[i, "kind"]), safe(F[i, "target"]),
            safe(F[i, "hosting"]), safe(F[i, "backend"]), safe(F[i, "session"]),
            safe(substr(F[i, "head"], 1, 12)), safe(F[i, "start"]), safe(F[i, "end"]),
            safe(outc), ex[i], safe(F[i, "output"])
        }
        if (rows == 0) print "| none | | | | | | | | | | | | |"
        if (done) {
          printf "\nEnded on `%s`.\n", safe(substr(F[done, "head"], 1, 12))
          if (nw[done]) print ""
          for (j = 1; j <= nw[done]; j++) printf "- Warning: %s\n", safe(W[done, j])
        }
      }
    }' $files || die 1 "cannot render the records"
}

cmd_render() {
  run='' points=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --point)
        is_point "$2" || bad --point "not a point of the vocabulary"
        points="$points$2$LF"
        ;;
    esac
    shift 2
  done
  if [ -n "$run" ]; then
    valid_run "$run"
  else
    latest_run
    run=$LATEST
    [ -n "$run" ] || return 0
  fi
  # shellcheck disable=SC2086 # points are validated vocabulary words
  render_run "$run" $points
}

# --- regenerate ---------------------------------------------------------------------
cmd_regenerate() {
  base='' rhead='' run=''
  while [ $# -gt 0 ]; do
    case $1 in
      --base | --head | --run) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --base) base=$2 ;;
      --head) rhead=$2 ;;
      --run) run=$2 ;;
    esac
    shift 2
  done
  [ -n "$base" ] || bad --base "required"
  [ -n "$rhead" ] || bad --head "required"
  case $base in -*) bad --base "a revision may not begin with a dash" ;; esac
  case $rhead in -*) bad --head "a revision may not begin with a dash" ;; esac
  [ -z "$run" ] || valid_run "$run"
  command -v git >/dev/null 2>&1 || die 1 "git is not on PATH"
  git -C "$worktree" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || die 1 "--base: cannot resolve $(sanitize_printable "$base" '(unprintable)') to a commit"
  git -C "$worktree" rev-parse --verify --quiet "$rhead^{commit}" >/dev/null \
    || die 1 "--head: cannot resolve $(sanitize_printable "$rhead" '(unprintable)') to a commit"

  # One git read for the whole range. Each commit opens with a marker line
  # carrying a per-run nonce no commit text can predict, then its sha, short
  # sha, subject, sign-off ids, and rejected ids, one per line, then its body.
  scratch
  nonce=$(od -An -N12 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [ -n "$nonce" ] || nonce="$$-$(date +%s)"
  marker="@@planwright-commit-$nonce@@"
  git -C "$worktree" -c core.abbrev=7 log --reverse \
    --format="$marker%n%H%n%h%n%s%n%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x20)%n%(trailers:key=Planwright-Sign-Off-Rejected,valueonly,separator=%x20)%n%b" \
    "$base..$rhead" -- >"$work/log" 2>/dev/null \
    || die 1 "--base/--head: git cannot read the range"
  clean "$work/log" "$work/log.clean"

  awk -v MARK="$marker" "$AWK_SAFE"'
    $0 == MARK { n++; ln = 0; man[n] = 0; inman = 0; next }
    n == 0 { next }
    {
      ln++
      if (ln == 1) sha[n] = $0
      else if (ln == 2) short[n] = $0
      else if (ln == 3) subj[n] = $0
      else if (ln == 4) ids[n] = $0
      else if (ln == 5) rej[n] = $0
      else {
        if ($0 ~ /^This reverts commit [0-9a-f]+\./) {
          s = $0; sub(/^This reverts commit /, "", s); sub(/\..*$/, "", s)
          if (length(s) == 40 || length(s) == 64) { nr[n]++; R[n, nr[n]] = s }
        }
        if (!(n in route) && substr($0, 1, 14) == "Route reason: ") route[n] = substr($0, 15)
        if ($0 ~ /^- / && index($0, "before:")) { man[n]++; M[n, man[n]] = substr($0, 3); inman = 1 }
        else if (inman && $0 ~ /^[ \t]+[^ \t]/ && man[n]) { s = $0; sub(/^[ \t]+/, "", s); M[n, man[n]] = M[n, man[n]] " " s }
        else inman = 0
      }
    }
    END {
      # A revert undoes its target only while it is itself live; walking
      # newest first settles a reverted revert before the commit it names.
      for (i = n; i >= 1; i--) {
        live[i] = !(sha[i] in undone)
        if (live[i]) for (j = 1; j <= nr[i]; j++) undone[R[i, j]] = 1
      }
      for (i = 1; i <= n; i++) if (live[i]) {
        m = split(rej[i], r, " ")
        for (j = 1; j <= m; j++) rejected[r[j]] = 1
      }
      print "## Pending sign-off"
      print ""
      count = 0
      for (i = 1; i <= n; i++) {
        if (!live[i]) continue
        m = split(ids[i], r, " "); id = ""
        for (j = 1; j <= m; j++) if (r[j] ~ /^PS-[0-9]+$/) { id = r[j]; break }
        s = subj[i]
        if (id == "") {
          if (s !~ / ?\[pending-sign-off\]$/) continue
          sub(/ ?\[pending-sign-off\]$/, "", s)
          id = "legacy"
        } else if ((id in taken) || (id in rejected)) continue
        taken[id] = 1
        count++
        key[count] = (id == "legacy") ? 1e9 + i : substr(id, 4) + 0
        entry[count] = i; eid[count] = id; esubj[count] = s
      }
      for (a = 2; a <= count; a++)
        for (b = a; b > 1 && key[b - 1] > key[b]; b--) {
          t = key[b]; key[b] = key[b - 1]; key[b - 1] = t
          t = entry[b]; entry[b] = entry[b - 1]; entry[b - 1] = t
          t = eid[b]; eid[b] = eid[b - 1]; eid[b - 1] = t
          t = esubj[b]; esubj[b] = esubj[b - 1]; esubj[b - 1] = t
        }
      if (count == 0) print "- none"
      for (a = 1; a <= count; a++) {
        i = entry[a]
        printf "- [ ] **%s** %s · commit `%s`\n", eid[a], safe(esubj[a]), short[i]
        printf "  - Route reason: %s\n", ((i in route) ? safe(route[i]) : "not recorded in the commit")
        for (j = 1; j <= man[i]; j++) printf "  - %s\n", safe(M[i, j])
        if (man[i]) printf "  - Reject with: `git revert %s`; rejecting one sub-item is a hand edit the manifest guides\n", short[i]
        else printf "  - Reject with: `git revert %s`\n", short[i]
      }
    }' "$work/log.clean" || die 1 "cannot render the checklist"

  if [ -z "$run" ]; then
    latest_run
    run=$LATEST
  fi
  if [ -n "$run" ]; then
    render_run "$run" >"$work/render" || exit 1
    if [ -s "$work/render" ]; then
      printf '\n'
      cat "$work/render"
    fi
  fi
}

check_dir "$worktree/.claude"
check_dir "$cache"

case $verb in
  new-run) cmd_new_run "$@" ;;
  write) cmd_write "$@" ;;
  list) cmd_list "$@" ;;
  render) cmd_render "$@" ;;
  regenerate) cmd_regenerate "$@" ;;
  *) usage ;;
esac
