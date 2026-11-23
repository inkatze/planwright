#!/bin/sh
# control-plane-baseline.sh: the control plane's measurement baseline, taken
# from this host's session transcripts and the forge before any control-plane
# code is wired, and written only to machine-local data. docs/control-plane-
# baseline.md is the method; `control-plane-baseline.sh --help` the contract.
#
# Usage: control-plane-baseline.sh record --since <YYYY-MM-DD> --until <YYYY-MM-DD>
#            --repo <owner>/<name> [--repo <owner>/<name>]... [--prices <tsv>]
#        control-plane-baseline.sh compute --since <YYYY-MM-DD> --until <YYYY-MM-DD>
#            [--prices <tsv>] <rows-file>
#        control-plane-baseline.sh check-committed [--repo-root <dir>]
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=control-plane-baseline
here=$(cd "$(dirname "$0")" && pwd) || exit 2
# Exempt from check-committed: its numbers are made up for the tests.
fixture_dir=tests/fixtures/control-plane-baseline

usage() {
  cat >&2 <<'EOF'
usage: control-plane-baseline.sh record --since <YYYY-MM-DD> --until <YYYY-MM-DD>
           --repo <owner>/<name> [--repo <owner>/<name>]... [--prices <tsv>]
       control-plane-baseline.sh compute --since <YYYY-MM-DD> --until <YYYY-MM-DD>
           [--prices <tsv>] <rows-file>
       control-plane-baseline.sh check-committed [--repo-root <dir>]
EOF
  exit 2
}

help_text() {
  cat <<'EOF'
control-plane-baseline.sh: the control plane's measurement baseline.

record   Reads every transcript under $CLAUDE_CONFIG_DIR/projects (default
         ~/.claude/projects) written since the window opened, through
         `token-spend.sh rows --asks`, and each --repo's pull requests merged
         in the window, through `gh pr list`; computes the baseline (compute,
         below) and writes it, owner-only, to
           <fleet-home>/control-plane/baseline/<since>--<until>.tsv
         replacing an earlier recording of the same window (the last run to
         finish wins), then prints `recorded<TAB><path>`. The fleet home is
         scripts/fleet-state.sh root's and must be an absolute path. A
         location with a .git entry in it or above it, its symbolic links
         resolved, is refused, so a recording never lands where it could be
         committed.
compute  Prints the baseline of a rows file holding token-spend.sh rows
         (m, s and a lines) and merge lines (g <repo> <number> <merged-at>).
         The window is whole UTC days, --since to --until inclusive. Lines,
         tab-separated, after a `# control-plane-baseline: format 1` line and
         a `# window <since> <until>` line, sorted:
           turns <day> <role> <main> <sub>
           spend <day> <role> <usd>
           interruptions <day> <role> <asked> <pushed>
           merges <day> <repo> <count>
           summary days <n>
           summary turns-per-day <role> <main> <sub>
           summary spend-share <role> <usd> <percent>
           summary merges-per-day <n>
           summary interruptions-per-day <asked> <pushed>
         The rows are sorted before they are read, so where a message, a
         session's prompt line or a tool use appears in more than one
         transcript the same copy counts on every run. A turn is a message
         with usage, each message id once, counted from the first of its
         lines that has usage in the window; main or sub is the transcript's
         chain. The role is the session's kind read from its prompt line
         (token-spend-lib.awk's session_kind; where several transcripts carry
         one, the first in sort order); a session with no prompt line is
         `unknown`. Asked counts AskUserQuestion uses and
         pushed PushNotification uses, each tool-use id once and a use with no
         id on every line. A merge counts once per repository and number, on
         its merged-at day. Dollars use --prices (default
         config/token-prices.tsv); a model missing from it is priced at zero
         and named on stderr.
check-committed
         Fails when any file git tracks in the work tree holding --repo-root
         (default the current directory), in its committed (HEAD) or its
         working-tree copy, holds a recorded figure: the format line above,
         or a turns, spend, interruptions, merges or summary row. Files git
         treats as binary are read as text. The fixture set under
         tests/fixtures/control-plane-baseline/ is exempt.

Exit: 0 done (check-committed: no figure found); 1 a transcript or forge read
      failed, a forge read hit its limit, or check-committed found a figure,
      each named on stderr; 2 usage, a missing tool, an unreadable rows file,
      an unreadable or malformed price table, an unresolved or refused
      location, a --repo-root that is not a git work tree, or a git read
      that failed (a file it could not read, a HEAD it could not resolve).
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

clean() { printf '%s' "$1" | tr -d '\000-\010\013-\037\177'; }

scratch=""
part=""
cleanup() {
  [ -z "$scratch" ] || rm -rf "$scratch"
  [ -z "$part" ] || rm -f -- "$part"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
scratch_dir() {
  [ -n "$scratch" ] || scratch=$(mktemp -d "${TMPDIR:-/tmp}/$prog.XXXXXX") || die 2 "mktemp failed"
}

# awk reads an operand shaped name=value as an assignment, not a file.
awk_operand() {
  case $1 in
    /*) printf '%s' "$1" ;;
    *) printf './%s' "$1" ;;
  esac
}

valid_day() {
  case $1 in
    [1-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
    *) return 1 ;;
  esac
  vy=${1%%-*}
  vm=${1#*-}
  vm=${vm%-*}
  vm=${vm#0}
  vd=${1##*-}
  vd=${vd#0}
  [ "$vm" -ge 1 ] && [ "$vm" -le 12 ] && [ "$vd" -ge 1 ] || return 1
  case $vm in
    2)
      if [ $((vy % 4)) -eq 0 ] && { [ $((vy % 100)) -ne 0 ] || [ $((vy % 400)) -eq 0 ]; }; then
        vmax=29
      else
        vmax=28
      fi
      ;;
    4 | 6 | 9 | 11) vmax=30 ;;
    *) vmax=31 ;;
  esac
  [ "$vd" -le "$vmax" ]
}

valid_repo() {
  case $1 in
    */*/* | /* | */ | *[!A-Za-z0-9._/-]*) return 1 ;;
    ?*/?*) return 0 ;;
  esac
  return 1
}

check_window() { # check_window <since> <until>
  valid_day "$1" || die 2 "--since takes a real YYYY-MM-DD date"
  valid_day "$2" || die 2 "--until takes a real YYYY-MM-DD date"
  [ "$(printf '%s' "$1" | tr -d -)" -le "$(printf '%s' "$2" | tr -d -)" ] || die 2 "--until is before --since"
}

check_prices() {
  [ -f "$1" ] && [ -r "$1" ] && [ -s "$1" ] || die 2 "unreadable or empty price table: $(clean "$1")"
}

# compute_baseline <since> <until> <prices> <rows-file>: the baseline, header
# first, on stdout.
compute_baseline() {
  scratch_dir
  sort -- "$4" >"$scratch/sorted" || die 2 "sorting the rows failed"
  awk -F '\t' -v prog="$prog" -v since="$1" -v until="$2" \
    -f "$here/token-spend-lib.awk" -f "$here/control-plane-baseline.awk" \
    "$(awk_operand "$3")" "$(awk_operand "$scratch/sorted")" >"$scratch/body" \
    || die 2 "computing the baseline failed"
  sort "$scratch/body" >"$scratch/body.sorted" || die 2 "sorting the baseline failed"
  printf '# control-plane-baseline: format 1\n# window\t%s\t%s\n' "$1" "$2"
  cat "$scratch/body.sorted"
}

cmd_compute() {
  since="" until="" prices=$here/../config/token-prices.tsv
  while [ $# -gt 0 ]; do
    case $1 in
      --since | --until | --prices) [ $# -ge 2 ] || usage ;;
      --) shift && break ;;
      -*) usage ;;
      *) break ;;
    esac
    case $1 in
      --since) since=$2 ;;
      --until) until=$2 ;;
      --prices) prices=$2 ;;
    esac
    shift 2
  done
  [ $# -eq 1 ] || usage
  check_window "$since" "$until"
  check_prices "$prices"
  [ -f "$1" ] && [ -r "$1" ] || die 2 "unreadable rows file: $(clean "$1")"
  compute_baseline "$since" "$until" "$prices" "$1"
}

# under_git <absolute dir>: whether <dir> or an ancestor holds a .git entry,
# or <dir> lies inside one. Read without git, so a repository git refuses to
# open, or a host without git, still counts as one.
under_git() {
  ug=$1
  case $ug in */.git | */.git/*) return 0 ;; esac
  while :; do
    if [ -e "$ug/.git" ] || [ -L "$ug/.git" ]; then
      return 0
    fi
    [ -n "$ug" ] && [ "$ug" != / ] || return 1
    ug=${ug%/*}
  done
}

# physical_path <absolute path>: the path with every symbolic link in its
# longest existing prefix resolved.
physical_path() {
  pp_head=$1 pp_tail=""
  while [ ! -d "$pp_head" ]; do
    pp_tail=/${pp_head##*/}$pp_tail
    pp_head=${pp_head%/*}
    [ -n "$pp_head" ] || pp_head=/
  done
  pp_real=$(cd -P -- "$pp_head" && pwd -P) || return 1
  pp_out=${pp_real%/}$pp_tail
  printf '%s' "${pp_out:-/}"
}

# refuse_git_location <absolute dir>: die unless neither <dir> nor its
# physical path has a .git entry in it or above it.
refuse_git_location() {
  rg_real=$(physical_path "$1") || die 2 "cannot resolve $(clean "$1")"
  if under_git "$1" || under_git "$rg_real"; then
    die 2 "refusing a location inside a git work tree: $(clean "$1")"
  fi
}

cmd_record() {
  since="" until="" prices=$here/../config/token-prices.tsv repos=""
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --since) since=$2 ;;
      --until) until=$2 ;;
      --prices) prices=$2 ;;
      --repo)
        valid_repo "$2" || die 2 "--repo takes <owner>/<name>: $(clean "$2")"
        repos="$repos $2"
        ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$repos" ] || usage
  check_window "$since" "$until"
  check_prices "$prices"
  command -v jq >/dev/null 2>&1 || die 2 "jq is required"
  command -v gh >/dev/null 2>&1 || die 2 "gh is required"
  home=$(/bin/sh "$here/fleet-state.sh" root 2>/dev/null) && [ -n "$home" ] || die 2 "the fleet home does not resolve"
  case $home in
    /*) ;;
    *) die 2 "the fleet home is not an absolute path: $(clean "$home")" ;;
  esac
  dir=${home%/}/control-plane/baseline
  refuse_git_location "$dir"
  scratch_dir
  # token-spend.sh's --since is local midnight; the window's days are UTC.
  TZ=UTC0 "$here/token-spend.sh" rows --asks --since "$since" >"$scratch/rows" \
    || die 1 "reading the transcripts failed; nothing recorded"
  limit=1000
  for repo in $repos; do
    gh pr list --repo "$repo" --state merged --search "merged:${since}T00:00:00Z..${until}T23:59:59Z" \
      --limit "$limit" --json number,mergedAt >"$scratch/prs.json" 2>"$scratch/gh.err" \
      || die 1 "the forge read failed for $repo: $(clean "$(head -n 3 "$scratch/gh.err")")"
    n=$(jq 'if type == "array" then length else error end' "$scratch/prs.json" 2>/dev/null)
    case $n in
      '' | *[!0-9]*) die 1 "the forge returned no list for $repo" ;;
    esac
    [ "$n" -lt "$limit" ] || die 1 "the forge read for $repo hit its $limit-row limit; record a shorter window"
    jq -r --arg r "$repo" '.[] | ["g", $r, (.number | tostring), (.mergedAt // "")] | @tsv' \
      "$scratch/prs.json" >>"$scratch/rows" || die 1 "the forge returned malformed rows for $repo"
  done
  compute_baseline "$since" "$until" "$prices" "$scratch/rows" >"$scratch/baseline"
  umask 077
  mkdir -p -- "$dir" || die 2 "cannot create $(clean "$dir")"
  refuse_git_location "$dir"
  dest=$dir/$since--$until.tsv
  part=$dir/.$since--$until.tsv.$$
  if ! cp -- "$scratch/baseline" "$part" || ! mv -f -- "$part" "$dest"; then
    die 2 "cannot write $(clean "$dest")"
  fi
  part=""
  printf 'recorded\t%s\n' "$dest"
}

# grep_figures <top> [<tree>]: the tracked files holding a figure, in the
# working tree, or in <tree> when one is named; git grep's status.
grep_figures() {
  tab=$(printf '\t')
  gf_top=$1
  shift
  git -C "$gf_top" grep -l -a -E \
    -e '^# control-plane-baseline: format [0-9]+' \
    -e "^(turns|spend|interruptions|merges)${tab}[0-9]{4}-[0-9]{2}-[0-9]{2}${tab}" \
    -e "^summary${tab}(days|turns-per-day|spend-share|merges-per-day|interruptions-per-day)${tab}" \
    "$@" -- . ":(exclude)$fixture_dir/"
}

# scan_figures <top> [<tree>]: append grep_figures' hits to $scratch/hits and
# set found; a file git could not read fails the check even though git grep
# then exits 1.
scan_figures() {
  grep_figures "$@" >"$scratch/scan" 2>"$scratch/grep.err"
  sf=$?
  [ ! -s "$scratch/grep.err" ] || die 2 "git grep failed: $(clean "$(head -n 3 "$scratch/grep.err")")"
  case $sf in
    0)
      found=1
      sed 's/^HEAD://' "$scratch/scan" >>"$scratch/hits"
      ;;
    1) ;;
    *) die 2 "git grep failed with status $sf" ;;
  esac
}

cmd_check_committed() {
  root=""
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --repo-root) root=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -n "$root" ] || root=.
  command -v git >/dev/null 2>&1 || die 2 "git is required"
  top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] \
    || die 2 "not a git work tree: $(clean "$root")"
  scratch_dir
  found=0
  scan_figures "$top"
  if git -C "$top" rev-parse -q --verify HEAD >"$scratch/head" 2>"$scratch/head.err"; then
    scan_figures "$top" HEAD
  elif [ -n "$(git -C "$top" for-each-ref --count=1 2>"$scratch/head.err")" ] || [ -s "$scratch/head.err" ]; then
    die 2 "HEAD does not resolve: $(clean "$(head -n 3 "$scratch/head.err")")"
  fi
  if [ "$found" -eq 0 ]; then
    printf '%s: no recorded figure in a tracked file\n' "$prog"
    return 0
  fi
  sort -u "$scratch/hits" | while IFS= read -r f; do
    printf '%s: a recorded figure is committed: %s\n' "$prog" "$(clean "$f")" >&2
  done
  printf '%s: baselines are machine-local data; see docs/control-plane-baseline.md\n' "$prog" >&2
  exit 1
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  record) cmd_record "$@" ;;
  compute) cmd_compute "$@" ;;
  check-committed) cmd_check_committed "$@" ;;
  -h | --help) help_text ;;
  *) usage ;;
esac
