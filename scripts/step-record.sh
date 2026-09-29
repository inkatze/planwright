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
#                 The cache is <worktree>/.claude/steps/, created mode 0700.
#   new-run       issue the next run id (six digits, zero-padded, strictly
#                 increasing within the cache) and print it. Run ids order
#                 attempts: the latest run is the highest id.
#   write         validate every field, then write one record and print its
#                 absolute path (the value a later step's
#                 PLANWRIGHT_STEP_PREV_RECORD carries). --completion writes
#                 the point-completion record instead; --warning repeats.
#   list          print every record of the run (every run when --run is
#                 absent), oldest first, optionally one point's only: a
#                 `record<TAB><worktree-relative path>` line, the record's
#                 stored lines, then a blank line.
#   render        print one markdown table per point of the run (default the
#                 latest run), in the order the points first recorded, or
#                 the named points in the order given.
#   regenerate    print the pending-sign-off checklist rebuilt from the
#                 marked commits of <base>..<head>, a blank line, then the
#                 render of the run (default the latest; nothing when the
#                 cache holds no run).
#
# Field grammar (write refuses a violation with exit 2, naming the field and
# never echoing its value; no value is ever interpolated before it passes):
#   --run          an issued run id: ^[0-9]{6}$ naming an existing run dir
#   --point        a name from doctrine/custom-steps.md's vocabulary
#   --step         ^[a-z][a-z0-9-]*$, at most 64 bytes, never `implementation`
#   --kind         skill | command | prompt
#   --hosting      isolated | continue | in-session
#   --backend      ^[A-Za-z0-9][A-Za-z0-9._:-]*$, at most 128 bytes
#   --session      the same charset; optional
#   --head         ^[0-9a-f]{7,64}$
#   --start/--end  YYYY-MM-DDTHH:MM:SSZ
#   --outcome      passed | applied | halted | failed | skipped; skipped
#                  requires --skip-reason, and --skip-reason requires skipped
#   --target, --skip-reason, --warning
#                  non-empty single-line text, no C0 control byte or DEL, at
#                  most 1024 bytes
#   --output       a path inside the worktree, stored worktree-relative; no
#                  `..` segment
#
# Storage: <cache>/<run>/<seq>-step-<point>-<step>.rec and
# <cache>/<run>/<seq>-done-<point>.rec, <seq> three digits in write order.
# A record is `<key><TAB><value>` lines: type, run, seq, then the fields
# above under their flag names (skip-reason for --skip-reason), an empty
# optional field stored empty; `excerpt` and `warning` lines repeat. Its form
# is unstable to anything but this helper.
#
# The excerpt (--excerpt-file): tabs become spaces, carriage returns and
# every other C0 control byte and DEL are stripped (bytes 0x80 and above are
# kept, being UTF-8 text), then the last 20 lines, cut to the last 2000
# bytes, are kept. The kept text is screened through
# scripts/inception-secret-screen.sh (the repository's secret screen,
# honoring PLANWRIGHT_SECRET_SCREEN_TOOL). Screen action: on a hit the whole
# excerpt is withheld and stored as one placeholder line; a screen that
# cannot run withholds it the same way, never passing it unscreened. The
# full captured output stays where --output names, unscreened.
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
# `- Warning: <text>` line per warning. Every cell and warning is table-safe:
# `&`, `<`, `>` become entities, `@` and `#` become numeric entities (no
# mention, issue reference, or closing keyword survives), `://` loses its
# slashes to entities (no autolink), and `\`, `|`, backtick, `*`, `_`, `[`,
# `]`, `~`, `(`, `)`, and `!` are backslash-escaped.
#
# Checklist (regenerate), per doctrine/gate-wiring.md: a commit in the range
# is marked by a `Planwright-Sign-Off: PS-<n>` trailer (read through git's
# trailer parser) or, legacy, a `[pending-sign-off]` subject suffix (rendered
# with the ID `legacy`, the suffix dropped). A marked commit drops out when a
# commit in the range carries `This reverts commit <its full sha>` in its
# body, or when its ID is named by a `Planwright-Sign-Off-Rejected:` trailer
# in the range. Entries order by ID number, legacy entries last in commit
# order; an ID marked twice keeps its oldest commit. An entry is
#   - [ ] **<id>** <subject> · commit `<sha7>`
#     - Route reason: <the body's `Route reason:` line, or `not recorded in
#       the commit`>
#     - <each body line beginning `- `, the batched-commit manifest>
#     - Reject with: `git revert <sha7>` (plus the hand-edit note when a
#       manifest is present)
# with mentions, issue references, links, and HTML neutralized as in the
# table (markdown is kept: the manifest's code spans are the format). An
# empty checklist renders `- none`. A <base> or <head> that does not resolve
# fails by name.
#
# Exit: 0 success · 1 a runtime failure (an unresolvable range, a cache that
# cannot be written) · 2 a usage or field-validation error.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

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

matches() { printf '%s' "$1" | grep -Eq "$2"; }

is_single_line_text() {
  # Non-empty, no newline, no C0 control byte or DEL, bounded.
  [ -n "$1" ] || return 1
  case $1 in *"$LF"*) return 1 ;; esac
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177' | wc -c)" -eq "$(printf '%s' "$1" | wc -c)" ] || return 1
  [ "$(printf '%s' "$1" | wc -c)" -le "$TEXT_MAX" ]
}

is_point() {
  case $1 in
    pre-implementation | pre-ci | convergence | pre-pr | post-pr | pre-ready-flip | \
      pre-spec-ready-flip | spec-drafted | kickoff-signed-off | unit-selected | \
      pre-dispatch | post-dispatch | unit-halted | post-merge | orchestrator-idle) return 0 ;;
  esac
  return 1
}

# Word splitting only on newlines, and no globbing: record paths live under a
# worktree path that may carry blanks.
IFS=$LF
set -f

# --- global option and verb ---------------------------------------------------
worktree=
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
  worktree=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "--worktree: not given and not inside a git work tree"
fi
[ -d "$worktree" ] || bad --worktree "not a directory"
worktree=$(cd "$worktree" && pwd -P) || bad --worktree "not readable"
cache="$worktree/.claude/steps"

# glob_names <dir> <pattern>: the names in <dir> matching <pattern>, sorted,
# one per line (globbing is off everywhere else).
glob_names() {
  set +f
  for _g in "$1"/$2; do
    [ -f "$_g" ] || [ -d "$_g" ] && printf '%s\n' "${_g##*/}"
  done
  set -f
}

run_ids() {
  [ -d "$cache" ] || return 0
  glob_names "$cache" '[0-9][0-9][0-9][0-9][0-9][0-9]'
}

latest_run() { run_ids | tail -n 1; }

valid_run() {
  matches "$1" '^[0-9]{6}$' || bad --run "not a run id"
  [ -d "$cache/$1" ] || bad --run "no such run in the cache"
}

# --- new-run -------------------------------------------------------------------
cmd_new_run() {
  [ $# -eq 0 ] || usage
  (umask 077 && mkdir -p "$cache") || die 1 "cannot create the record cache"
  last=$(latest_run)
  next=$((1${last:-000000} - 1000000 + 1))
  tries=0
  while [ "$tries" -lt 100 ]; do
    id=$(printf '%06d' "$next")
    if (umask 077 && mkdir "$cache/$id") 2>/dev/null; then
      printf '%s\n' "$id"
      return 0
    fi
    next=$((next + 1))
    tries=$((tries + 1))
  done
  die 1 "cannot issue a run id"
}

# --- excerpt --------------------------------------------------------------------
# excerpt_lines <file>: the bounded, stripped, screened excerpt on stdout.
excerpt_lines() {
  work=$(mktemp -d "${TMPDIR:-/tmp}/step-record.XXXXXX") || die 1 "cannot create a temporary directory"
  tr '\t' ' ' <"$1" | tr -d '\000-\010\013-\037\177' \
    | tail -n "$EXCERPT_LINES" | tail -c "$EXCERPT_BYTES" >"$work/excerpt"
  src=0
  if [ -r "$script_dir/inception-secret-screen.sh" ]; then
    /bin/sh "$script_dir/inception-secret-screen.sh" -- "$work/excerpt" >/dev/null 2>&1 || src=$?
  else
    src=2
  fi
  case $src in
    0) cat "$work/excerpt" ;;
    1) printf '%s\n' "[withheld: the secret screen flagged this excerpt]" ;;
    *) printf '%s\n' "[withheld: the excerpt could not be screened]" ;;
  esac
  rm -rf "$work"
}

# --- write ------------------------------------------------------------------------
# claim <run> <stem>: write stdin to the run's next sequence slot without
# clobbering a concurrent writer, printing the record's absolute path.
claim() {
  dir="$cache/$1"
  tmpf=$(mktemp "$dir/.rec.XXXXXX") || die 1 "cannot write to the record cache"
  cat >"$tmpf"
  tries=0
  while [ "$tries" -lt 100 ]; do
    n=$(find "$dir" -name '[0-9][0-9][0-9]-*.rec' -type f | wc -l | tr -d ' ')
    seq=$(printf '%03d' $((n + 1 + tries)))
    path="$dir/$seq-$2.rec"
    {
      printf 'type\t%s\nrun\t%s\nseq\t%s\n' "$3" "$1" "$seq"
      cat "$tmpf"
    } >"$tmpf.full"
    if ln "$tmpf.full" "$path" 2>/dev/null; then
      rm -f "$tmpf" "$tmpf.full"
      printf '%s\n' "$path"
      return 0
    fi
    tries=$((tries + 1))
  done
  rm -f "$tmpf" "$tmpf.full"
  die 1 "cannot claim a record slot"
}

cmd_write() {
  completion=0 run='' point='' step='' kind='' target='' hosting='' backend='' session=''
  head='' start='' end='' outcome='' excerpt_file='' output='' skip_reason=''
  warnings=
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
        is_single_line_text "$2" || bad --warning "must be non-empty single-line text of at most $TEXT_MAX bytes"
        warnings="$warnings$2$LF"
        ;;
    esac
    shift 2
  done

  [ -n "$run" ] || bad --run "required"
  valid_run "$run"
  is_point "$point" || bad --point "not a point of the vocabulary"
  matches "$head" '^[0-9a-f]{7,64}$' || bad --head "not a commit id"

  if [ "$completion" -eq 1 ]; then
    for f in "$step" "$kind" "$target" "$hosting" "$backend" "$session" \
      "$start" "$end" "$outcome" "$excerpt_file" "$output" "$skip_reason"; do
      [ -z "$f" ] || die 2 "write --completion takes only --run, --point, --head, and --warning"
    done
    {
      printf 'point\t%s\nhead\t%s\n' "$point" "$head"
      printf '%s' "$warnings" | while IFS= read -r w; do
        printf 'warning\t%s\n' "$w"
      done
    } | claim "$run" "done-$point" completion
    return
  fi
  [ -z "$warnings" ] || die 2 "--warning belongs to write --completion"

  { matches "$step" '^[a-z][a-z0-9-]*$' && [ "${#step}" -le 64 ]; } || bad --step "not a step id"
  [ "$step" != implementation ] || bad --step "reserved for the implementation phase"
  case $kind in skill | command | prompt) ;; *) bad --kind "not skill, command, or prompt" ;; esac
  is_single_line_text "$target" || bad --target "must be non-empty single-line text of at most $TEXT_MAX bytes"
  case $hosting in isolated | continue | in-session) ;; *) bad --hosting "not isolated, continue, or in-session" ;; esac
  { matches "$backend" '^[A-Za-z0-9][A-Za-z0-9._:-]*$' && [ "${#backend}" -le 128 ]; } || bad --backend "not a backend name"
  if [ -n "$session" ]; then
    { matches "$session" '^[A-Za-z0-9][A-Za-z0-9._:-]*$' && [ "${#session}" -le 128 ]; } || bad --session "not a session id"
  fi
  ts='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  matches "$start" "$ts" || bad --start "not YYYY-MM-DDTHH:MM:SSZ"
  matches "$end" "$ts" || bad --end "not YYYY-MM-DDTHH:MM:SSZ"
  case $outcome in passed | applied | halted | failed | skipped) ;; *) bad --outcome "not passed, applied, halted, failed, or skipped" ;; esac
  if [ "$outcome" = skipped ]; then
    is_single_line_text "$skip_reason" || bad --skip-reason "required for a skipped step, as single-line text of at most $TEXT_MAX bytes"
  elif [ -n "$skip_reason" ]; then
    bad --skip-reason "only a skipped step carries one"
  fi
  rel_output=
  if [ -n "$output" ]; then
    is_single_line_text "$output" || bad --output "not a single-line path"
    case /$output/ in */../*) bad --output "carries a .. segment" ;; esac
    # Canonicalized like the worktree, so a symlinked spelling of the same
    # directory (macOS's /var and /private/var) is not read as outside it.
    case $output in
      /*)
        _od=$(cd "$(dirname "$output")" 2>/dev/null && pwd -P) \
          && output="$_od/${output##*/}"
        ;;
    esac
    case $output in
      "$worktree"/*) rel_output=${output#"$worktree"/} ;;
      /*) bad --output "outside the worktree" ;;
      *) rel_output=${output#./} ;;
    esac
  fi
  if [ -n "$excerpt_file" ]; then
    [ -f "$excerpt_file" ] && [ -r "$excerpt_file" ] || bad --excerpt-file "not a readable file"
  fi

  {
    printf 'point\t%s\nstep\t%s\nkind\t%s\ntarget\t%s\nhosting\t%s\n' \
      "$point" "$step" "$kind" "$target" "$hosting"
    printf 'backend\t%s\nsession\t%s\nhead\t%s\nstart\t%s\nend\t%s\n' \
      "$backend" "$session" "$head" "$start" "$end"
    printf 'outcome\t%s\noutput\t%s\nskip-reason\t%s\n' \
      "$outcome" "$rel_output" "$skip_reason"
    if [ -n "$excerpt_file" ]; then
      excerpt_lines "$excerpt_file" | while IFS= read -r line || [ -n "$line" ]; do
        printf 'excerpt\t%s\n' "$line"
      done
    fi
  } | claim "$run" "step-$point-$step" step
}

# --- list -----------------------------------------------------------------------
# records <run-or-empty> <point-or-empty>: record paths, oldest first.
records() {
  [ -d "$cache" ] || return 0
  if [ -n "$1" ]; then
    runs=$1
  else
    runs=$(run_ids)
  fi
  for r in $runs; do
    for f in $(glob_names "$cache/$r" '[0-9][0-9][0-9]-*.rec'); do
      if [ -n "$2" ]; then
        grep -Fxq "point$TAB$2" "$cache/$r/$f" || continue
      fi
      printf '%s\n' "$cache/$r/$f"
    done
  done
}

cmd_list() {
  run='' point=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run)
        [ $# -ge 2 ] || usage
        run=$2
        ;;
      --point)
        [ $# -ge 2 ] || usage
        point=$2
        ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -z "$run" ] || valid_run "$run"
  [ -z "$point" ] || is_point "$point" || bad --point "not a point of the vocabulary"
  for f in $(records "$run" "$point"); do
    printf 'record\t%s\n' "${f#"$worktree"/}"
    cat "$f"
    printf '\n'
  done
}

# --- render ----------------------------------------------------------------------
# The neutralizer both renderers share. safe(s, table): entities for & < > @ #
# and the slashes of ://; with table set, markdown's inline markup and the
# pipe are backslash-escaped too.
AWK_SAFE='
function safe(s, table,    out, i, n, c) {
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "&") c = "&amp;"
    else if (c == "<") c = "&lt;"
    else if (c == ">") c = "&gt;"
    else if (c == "@") c = "&#64;"
    else if (c == "#") c = "&#35;"
    else if (c == ":" && substr(s, i + 1, 2) == "//") { c = ":&#47;&#47;"; i += 2 }
    else if (table && index("\\|`*_[]~()!", c)) c = "\\" c
    out = out c
  }
  return out
}
'

render_run() {
  # render_run <run> [<point>...]
  r=$1
  shift
  if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046 # split on newlines by design (IFS)
    set -- $(records "$r" "" | while IFS= read -r f; do
      sed -n "s/^point$TAB//p" "$f"
    done | awk '!seen[$0]++')
  fi
  first=1
  for p in "$@"; do
    files=$(records "$r" "$p")
    [ -n "$files" ] || continue
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    # shellcheck disable=SC2086 # record paths carry no blanks (validated names)
    awk -v run="$r" -v point="$p" -v TAB="$TAB" "$AWK_SAFE"'
      FNR == 1 { k++; excerpt[k] = "" }
      {
        t = index($0, TAB); key = substr($0, 1, t - 1); val = substr($0, t + 1)
        if (key == "type") type[k] = val
        else if (key == "excerpt") excerpt[k] = excerpt[k] (excerpt[k] == "" ? "" : " / ") safe(val, 1)
        else if (key == "warning") warn[++nw] = val
        else F[k, key] = val
      }
      END {
        printf "## Steps at `%s` (run `%s`)\n\n", point, run
        print "| # | Step | Kind | Target | Hosting | Backend | Session | Head | Start | End | Outcome | Excerpt | Output |"
        print "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        rows = 0; ended = ""
        for (i = 1; i <= k; i++) {
          if (type[i] == "completion") { ended = F[i, "head"]; continue }
          rows++
          outc = F[i, "outcome"]
          if (outc == "skipped") outc = outc ": " F[i, "skip-reason"]
          printf "| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", rows,
            safe(F[i, "step"], 1), safe(F[i, "kind"], 1), safe(F[i, "target"], 1),
            safe(F[i, "hosting"], 1), safe(F[i, "backend"], 1), safe(F[i, "session"], 1),
            substr(F[i, "head"], 1, 12), safe(F[i, "start"], 1), safe(F[i, "end"], 1),
            safe(outc, 1), excerpt[i], safe(F[i, "output"], 1)
        }
        if (rows == 0) print "| none | | | | | | | | | | | | |"
        if (ended != "") printf "\nEnded on `%s`.\n", substr(ended, 1, 12)
        if (nw) print ""
        for (i = 1; i <= nw; i++) printf "- Warning: %s\n", safe(warn[i], 1)
      }' $files
  done
}

cmd_render() {
  run=
  points=
  while [ $# -gt 0 ]; do
    case $1 in
      --run)
        [ $# -ge 2 ] || usage
        run=$2
        ;;
      --point)
        [ $# -ge 2 ] || usage
        is_point "$2" || bad --point "not a point of the vocabulary"
        points="$points$2$LF"
        ;;
      *) usage ;;
    esac
    shift 2
  done
  if [ -n "$run" ]; then
    valid_run "$run"
  else
    run=$(latest_run)
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
  [ -z "$run" ] || valid_run "$run"
  case $base$rhead in -*) die 2 "--base/--head: a revision may not begin with a dash" ;; esac
  git -C "$worktree" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || die 1 "--base: cannot resolve $(sanitize_printable "$base" '(unprintable)') to a commit"
  git -C "$worktree" rev-parse --verify --quiet "$rhead^{commit}" >/dev/null \
    || die 1 "--head: cannot resolve $(sanitize_printable "$rhead" '(unprintable)') to a commit"
  commits=$(git -C "$worktree" rev-list --reverse "$base..$rhead") \
    || die 1 "--base/--head: cannot list the range"

  # One unit-separated line per commit: sha, short sha, subject, sign-off ids,
  # rejected ids, reverted sha, route reason, then the manifest lines joined
  # by the record separator. Bodies are read line by line, never evaluated.
  US=$(printf '\037')
  RS=$(printf '\036')
  for c in $commits; do
    body=$(git -C "$worktree" show -s --format=%b "$c")
    ids=$(git -C "$worktree" show -s --format='%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x20)' "$c")
    rej=$(git -C "$worktree" show -s --format='%(trailers:key=Planwright-Sign-Off-Rejected,valueonly,separator=%x20)' "$c")
    reverts=$(printf '%s\n' "$body" | sed -n 's/^This reverts commit \([0-9a-f]\{40\}\)\..*$/\1/p' | head -n 1)
    route=$(printf '%s\n' "$body" | sed -n 's/^Route reason: //p' | head -n 1)
    manifest=$(printf '%s\n' "$body" | grep '^- ' | tr '\n' "$RS")
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$c" "$US" "$(git -C "$worktree" rev-parse --short=7 "$c")" "$US" \
      "$(git -C "$worktree" show -s --format=%s "$c")" "$US" "$ids" "$US" \
      "$rej" "$US" "$reverts" "$US" "$route" "$US" "$manifest"
  done | tr -d '\000-\010\013-\035\177' | awk -F "$US" -v RSEP="$RS" "$AWK_SAFE"'
    {
      n++; sha[n] = $1; short[n] = $2; subj[n] = $3; ids[n] = $4
      route[n] = $7; man[n] = $8
      if ($6 != "") reverted[$6] = 1
      m = split($5, r, " ")
      for (i = 1; i <= m; i++) rejected[r[i]] = 1
    }
    END {
      print "## Pending sign-off"
      print ""
      count = 0
      for (i = 1; i <= n; i++) {
        if (sha[i] in reverted) continue
        m = split(ids[i], r, " "); id = ""
        for (j = 1; j <= m; j++) if (r[j] ~ /^PS-[0-9]+$/) { id = r[j]; break }
        s = subj[i]
        if (id == "") {
          if (s !~ / ?\[pending-sign-off\]$/) continue
          sub(/ ?\[pending-sign-off\]$/, "", s)
          id = "legacy"
        } else if (id in taken) continue
        if (id in rejected) continue
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
        printf "- [ ] **%s** %s · commit `%s`\n", eid[a], safe(esubj[a], 0), short[i]
        printf "  - Route reason: %s\n", (route[i] == "" ? "not recorded in the commit" : safe(route[i], 0))
        m = split(man[i], ml, RSEP); hasman = 0
        for (j = 1; j <= m; j++) if (ml[j] != "") { printf "  %s\n", safe(ml[j], 0); hasman = 1 }
        if (hasman) printf "  - Reject with: `git revert %s`; rejecting one sub-item is a hand edit the manifest guides\n", short[i]
        else printf "  - Reject with: `git revert %s`\n", short[i]
      }
    }'
  if [ -z "$run" ]; then
    run=$(latest_run)
  fi
  if [ -n "$run" ]; then
    printf '\n'
    render_run "$run"
  fi
}

case $verb in
  new-run) cmd_new_run "$@" ;;
  write) cmd_write "$@" ;;
  list) cmd_list "$@" ;;
  render) cmd_render "$@" ;;
  regenerate) cmd_regenerate "$@" ;;
  *) usage ;;
esac
