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
# Fixture numbers made up for the tests, never recorded from a host.
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
         below) and writes it to
           <fleet-home>/control-plane/baseline/<since>--<until>.tsv
         replacing an earlier recording of the same window, then prints
         `recorded<TAB><path>`. The fleet home is scripts/fleet-state.sh
         root's. A location inside a git work tree is refused, so a
         recording never lands where it could be committed.
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
         A turn is a message with usage, each message id once (as
         token-spend-total.awk counts); main or sub is the transcript's chain.
         The role is the session's kind from its first prompt
         (token-spend-lib.awk's session_kind); a session with no prompt line
         is `unknown`. Asked counts AskUserQuestion uses and pushed
         PushNotification uses, each tool-use id once. A merge counts once per
         repository and number, on its merged-at day. Dollars use --prices
         (default config/token-prices.tsv); a model missing from it is priced
         at zero and named on stderr.
check-committed
         Fails when a file git tracks under --repo-root (default the
         enclosing work tree's top level), its working-tree copy included,
         holds a recorded figure: the format line above, or a turns, spend,
         interruptions, merges or summary row. The fixture set under
         tests/fixtures/control-plane-baseline/ is exempt.

Exit: 0 done (check-committed: no figure found); 1 a transcript or forge read
      failed, a forge read hit its limit, or check-committed found a figure,
      each named on stderr; 2 usage, a missing tool, an unreadable rows file
      or price table, an unresolved or refused location, or a --repo-root
      that is not a git work tree.
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

clean() { printf '%s' "$1" | tr -d '\000-\010\013-\037\177'; }

scratch=""
cleanup() { [ -z "$scratch" ] || rm -rf "$scratch"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
scratch_dir() {
  [ -n "$scratch" ] || scratch=$(mktemp -d "${TMPDIR:-/tmp}/$prog.XXXXXX") || die 2 "mktemp failed"
}

valid_day() {
  case $1 in
    [0-9][0-9][0-9][0-9]-0[1-9]-[0-2][0-9] | [0-9][0-9][0-9][0-9]-0[1-9]-3[01]) ;;
    [0-9][0-9][0-9][0-9]-1[0-2]-[0-2][0-9] | [0-9][0-9][0-9][0-9]-1[0-2]-3[01]) ;;
    *) return 1 ;;
  esac
  case $1 in *-00) return 1 ;; esac
}

valid_repo() {
  case $1 in
    */*/* | /* | */ | *[!A-Za-z0-9._/-]*) return 1 ;;
    ?*/?*) return 0 ;;
  esac
  return 1
}

check_window() { # check_window <since> <until>
  valid_day "$1" || die 2 "--since takes YYYY-MM-DD"
  valid_day "$2" || die 2 "--until takes YYYY-MM-DD"
  [ "$(printf '%s' "$1" | tr -d -)" -le "$(printf '%s' "$2" | tr -d -)" ] || die 2 "--until is before --since"
}

check_prices() {
  [ -f "$1" ] && [ -r "$1" ] && [ -s "$1" ] || die 2 "unreadable or empty price table: $(clean "$1")"
}

# compute_baseline <since> <until> <prices> <rows-file>: the baseline, header
# first, on stdout.
compute_baseline() {
  scratch_dir
  awk -F '\t' -v prog="$prog" -v since="$1" -v until="$2" \
    -f "$here/token-spend-lib.awk" -f "$here/control-plane-baseline.awk" "$3" "$4" >"$scratch/body" \
    || die 2 "computing the baseline failed"
  printf '# control-plane-baseline: format 1\n# window\t%s\t%s\n' "$1" "$2"
  sort "$scratch/body"
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

# inside_work_tree <dir>: whether <dir>, or its nearest existing ancestor,
# lies inside a git work tree.
inside_work_tree() {
  iw=$1
  while [ ! -d "$iw" ]; do
    case $iw in
      */*) iw=${iw%/*} ;;
      *) return 1 ;;
    esac
    [ -n "$iw" ] || iw=/
  done
  [ "$(git -C "$iw" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
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
  dir=${home%/}/control-plane/baseline
  if inside_work_tree "$dir"; then
    die 2 "refusing a location inside a git work tree: $(clean "$dir")"
  fi
  scratch_dir
  # token-spend.sh's --since is local midnight; the window's days are UTC.
  TZ=UTC0 "$here/token-spend.sh" rows --asks --since "$since" >"$scratch/rows" \
    || die 1 "reading the transcripts failed; nothing recorded"
  limit=1000
  for repo in $repos; do
    gh pr list --repo "$repo" --state merged --search "merged:${since}T00:00:00Z..${until}T23:59:59Z" \
      --limit "$limit" --json number,mergedAt >"$scratch/prs.json" 2>"$scratch/gh.err" \
      || die 1 "the forge read failed for $repo: $(clean "$(head -n 3 "$scratch/gh.err")")"
    n=$(jq 'length' "$scratch/prs.json" 2>/dev/null) || die 1 "the forge returned no list for $repo"
    [ "$n" -lt "$limit" ] || die 1 "the forge read for $repo hit its $limit-row limit; record a shorter window"
    jq -r --arg r "$repo" '.[] | ["g", $r, (.number | tostring), (.mergedAt // "")] | @tsv' \
      "$scratch/prs.json" >>"$scratch/rows" || die 1 "the forge returned malformed rows for $repo"
  done
  compute_baseline "$since" "$until" "$prices" "$scratch/rows" >"$scratch/baseline" || exit $?
  prev=$(umask)
  umask 077
  mkdir -p -- "$dir" || die 2 "cannot create $(clean "$dir")"
  umask "$prev"
  dest=$dir/$since--$until.tsv
  part=$dir/.$since--$until.tsv.$$
  if ! cp -- "$scratch/baseline" "$part" || ! mv -f -- "$part" "$dest"; then
    rm -f -- "$part"
    die 2 "cannot write $(clean "$dest")"
  fi
  printf 'recorded\t%s\n' "$dest"
}

cmd_check() {
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
  top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] \
    || die 2 "not a git work tree: $(clean "$root")"
  tab=$(printf '\t')
  scratch_dir
  git -C "$top" grep -l -I -E \
    -e '^# control-plane-baseline: format [0-9]+$' \
    -e "^(turns|spend|interruptions|merges)${tab}[0-9]{4}-[0-9]{2}-[0-9]{2}${tab}" \
    -e "^summary${tab}(days|turns-per-day|spend-share|merges-per-day|interruptions-per-day)$tab" \
    -- . ":(exclude)$fixture_dir/" >"$scratch/hits" 2>"$scratch/grep.err"
  case $? in
    0)
      while IFS= read -r f; do
        printf '%s: a recorded figure is committed: %s\n' "$prog" "$(clean "$f")" >&2
      done <"$scratch/hits"
      printf '%s: baselines are machine-local data; see docs/control-plane-baseline.md\n' "$prog" >&2
      exit 1
      ;;
    1) printf '%s: no recorded figure in a tracked file\n' "$prog" ;;
    *) die 2 "git grep failed: $(clean "$(head -n 3 "$scratch/grep.err")")" ;;
  esac
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  record) cmd_record "$@" ;;
  compute) cmd_compute "$@" ;;
  check-committed) cmd_check "$@" ;;
  -h | --help) help_text ;;
  *) usage ;;
esac
