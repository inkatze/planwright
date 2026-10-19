#!/bin/sh
# check-diff-scoped.sh — the per-fix check: run the tests touching the changed
# files and the linters over them, so each fix is validated in seconds while
# the full suite runs once per loop iteration (review-effectiveness REQ-D1.3,
# D-11).
#
# THE CHANGED FILES are the paths given, or with --base <rev> every file that
# differs from the merge base of <rev> and HEAD: committed, uncommitted, and
# untracked (ignored files excepted), both sides of a rename. A path git
# quotes (it holds a control byte, a quote, or a backslash) is reported
# `skipped path` and checked by nothing.
#
# THE TESTS are the files matching --tests (default `tests/test-*.sh`) that
# are themselves changed and still exist, or that name a changed file by its
# repo path, or by its basename when no other file in the repository shares
# it, either one as a whole word (a top-level file's repo path is its
# basename, so the sharing rule covers it too). A test reaching a file only
# through a constructed path is not selected; the full suite covers it.
#
# THE LINTERS, per changed file that still exists: `shellcheck -x` (following
# its `source=` directives, as the whole-tree lint does) and `shfmt -d`
# on shell (`.sh`, `.bash`, or an extensionless file with a shell shebang),
# markdownlint-cli2 on `.md`, `yamllint --strict` on `.yml` and `.yaml`. A
# linter not on PATH is reported as skipped, never passed. A file matching a
# --lint-exclude entry is linted by nothing but still selects its tests; an
# entry holding `*`, `?`, or `[` is a shell pattern with `*` crossing `/`, one
# ending in `/` covers everything under it (under every match, for a pattern),
# and anything else names one path; a leading `./` is dropped. Markdown files
# reach markdownlint-cli2 as literal paths, never as its globs.
# The caller passes what its own lint tasks leave out, by an exclusion or by an
# include list that never names the file (data, fixtures that are malformed on
# purpose, generated files).
#
# Each test runs as scripts/run-tests.sh runs a file: PLANWRIGHT_FLEET_STATE_DIR,
# and CLAUDE_PLUGIN_DATA and CLAUDE_DIR when set, point at a sentinel home of
# its own, and a test that creates anything there fails, since under a fleet
# worker it would have written the operator's real state; and
# SPEC_WALKTHROUGH_DOT_TIMEOUT defaults to the suite's load headroom.
#
# Paths and output come from the branch, so non-printable bytes are stripped
# from everything printed.
#
# Prints `test <file>` and `lint <tool> <file>` lines with --list, running
# nothing; otherwise `pass|fail test <file>`, `pass|fail lint <tool>`, and
# `skipped lint <tool> not installed`, a failure's output going to stderr.
# Tests run one at a time from the repository root through --runner (default
# /bin/bash, the repo's bash 3.2 floor, else bash on PATH).
#
# Usage:
#   check-diff-scoped.sh [--list] [--tests <pathspec>] [--runner <command>]
#       [--lint-exclude <entry> ...] (--base <rev> | <path>...)
#
# Exit codes: 0 no selected check failed (or nothing was selected); a
#   skipped linter or path is reported on its own line and does not fail the
#   check, so a consumer reads the `skipped` lines; 1 a test or linter failed;
#   2 usage, a refused path, or a git or other internal failure (named on
#   stderr).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# A git hook exports these, and every git command below must act on the
# repository the caller is in, never the one they point at, under no inherited
# configuration.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
# --tests is a glob pathspec by contract; an inherited setting must not turn
# it literal and select nothing.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS

prog=check-diff-scoped
NL='
'

usage() {
  cat >&2 <<EOF
usage: $prog [--list] [--tests <pathspec>] [--runner <command>]
         [--lint-exclude <entry> ...] (--base <rev> | <path>...)
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" | printable >&2
  exit "$1"
}
# printable — the input without its non-printable bytes, tabs and newlines kept.
printable() { tr -d '\000-\010\013-\037\177\200-\237'; }
# say <format> <arg>... — printf through printable.
say() {
  # shellcheck disable=SC2059 # the format is always a literal at the call site
  printf "$@" | printable
}
# lint_excluded <path> — the path matches a --lint-exclude entry.
lint_excluded() {
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    # shellcheck disable=SC2254 # the entry is a pattern by contract
    case $e in
      *[*?[]*/) case $1 in $e*) return 0 ;; esac ;;
      *[*?[]*) case $1 in $e) return 0 ;; esac ;;
      */) case $1 in "$e"*) return 0 ;; esac ;;
      *) [ "$1" != "$e" ] || return 0 ;;
    esac
  done <<EOF
$lint_exclude
EOF
  return 1
}

list=0
base=
tests_spec='tests/test-*.sh'
runner=
lint_exclude=
while [ $# -gt 0 ]; do
  case $1 in
    --list)
      list=1
      shift
      ;;
    --base | --tests | --runner | --lint-exclude)
      [ $# -ge 2 ] || usage
      case $1 in
        --base) base=$2 ;;
        --tests) tests_spec=$2 ;;
        --runner) runner=$2 ;;
        --lint-exclude)
          e=$2
          while :; do
            case $e in ./*) e=${e#./} ;; *) break ;; esac
          done
          case $e in *"$NL"* | '') die 2 "--lint-exclude takes one non-empty entry" ;; esac
          lint_exclude=$lint_exclude$e$NL
          ;;
      esac
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ -n "$base" ] || [ $# -gt 0 ] || usage
[ -z "$base" ] || [ $# -eq 0 ] || usage
if [ -z "$runner" ]; then
  if [ -x /bin/bash ]; then runner=/bin/bash; else runner=bash; fi
fi

top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git work tree"
cd "$top"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-diff-scoped.XXXXXX") || die 2 "cannot create a working directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
changed=$work/changed
if [ -n "$base" ]; then
  case $base in -*) die 2 "--base must be a revision, not an option" ;; esac
  sha=$(git rev-parse --verify --quiet "$base^{commit}") || die 2 "--base names no commit: $base"
  mb=$(git merge-base "$sha" HEAD) || die 2 "--base shares no history with HEAD"
  git -c core.quotePath=false diff --no-ext-diff --no-renames --name-only "$mb" -- >"$work/diffed" \
    || die 2 "git diff failed listing the changes against $mb"
  git -c core.quotePath=false ls-files --others --exclude-standard >"$work/untracked" \
    || die 2 "git ls-files failed listing the untracked files"
  sort -u "$work/diffed" "$work/untracked" >"$work/listed"
  : >"$changed"
  while IFS= read -r f; do
    case $f in
      '"'*) say 'skipped\tpath\t%s\n' "$f" ;;
      *) printf '%s\n' "$f" >>"$changed" ;;
    esac
  done <"$work/listed"
else
  : >"$changed"
  for p in "$@"; do
    case $p in
      '' | -* | /* | .. | ../* | */.. | */../* | *"$NL"*) die 2 "a path must be repo-relative and stay inside the repository: $p" ;;
    esac
    printf '%s\n' "${p#./}" >>"$changed"
  done
  sort -u -o "$changed" "$changed"
fi
if [ ! -s "$changed" ]; then
  printf 'nothing changed; no checks selected\n'
  exit 0
fi

# --- selection ---------------------------------------------------------------

git -c core.quotePath=false ls-files --cached --others --exclude-standard -- "$tests_spec" >"$work/test-files" \
  || die 2 "git ls-files failed listing the tests"
sort -u -o "$work/all-tests" "$work/test-files"
git -c core.quotePath=false ls-files --cached --others --exclude-standard >"$work/tree" \
  || die 2 "git ls-files failed listing the tree"
awk -F/ '{ n[$NF]++ } END { for (b in n) if (n[b] == 1) print b }' "$work/tree" >"$work/unique-basenames"

# One pattern per changed file: its repo path when it has a directory, and its
# basename when no other file shares it. One grep over the existing tests then
# selects every test naming any of them.
awk -F/ -v uniq="$work/unique-basenames" '
  BEGIN { while ((getline b < uniq) > 0) u[b] = 1 }
  NF > 1 { print }
  $NF in u { print $NF }' "$changed" | sort -u >"$work/patterns"
: >"$work/tests"
: >"$work/lint"
: >"$work/existing-tests"
while IFS= read -r t; do
  [ ! -f "$t" ] || printf '%s\n' "$t" >>"$work/existing-tests"
done <"$work/all-tests"
if [ -s "$work/patterns" ] && [ -s "$work/existing-tests" ]; then
  set --
  while IFS= read -r t; do set -- "$@" "./$t"; done <"$work/existing-tests"
  rc=0
  grep -lwF -f "$work/patterns" "$@" >"$work/selected" || rc=$?
  [ "$rc" -le 1 ] || die 2 "grep failed (exit $rc) selecting the tests"
  sed 's#^\./##' "$work/selected" >>"$work/tests"
fi
while IFS= read -r f; do
  if grep -Fxq -e "$f" "$work/all-tests" && [ -f "./$f" ]; then printf '%s\n' "$f" >>"$work/tests"; fi
  [ -f "./$f" ] || continue
  ! lint_excluded "$f" || continue
  case ${f##*/} in
    *.sh | *.bash) printf 'shellcheck\t%s\nshfmt\t%s\n' "$f" "$f" >>"$work/lint" ;;
    *.md) printf 'markdownlint-cli2\t%s\n' "$f" >>"$work/lint" ;;
    *.yml | *.yaml) printf 'yamllint\t%s\n' "$f" >>"$work/lint" ;;
    *.*) ;;
    *)
      if sed -n 1p "./$f" | grep -Eq '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)'; then
        printf 'shellcheck\t%s\nshfmt\t%s\n' "$f" "$f" >>"$work/lint"
      fi
      ;;
  esac
done <"$changed"
sort -u -o "$work/tests" "$work/tests"

if [ "$list" -eq 1 ]; then
  sed 's/^/test\t/' "$work/tests" | printable
  sed 's/^/lint\t/' "$work/lint" | printable
  exit 0
fi

# --- running -----------------------------------------------------------------

status=0
n=0
while IFS= read -r t; do
  n=$((n + 1))
  sentinel=$work/sentinel/$n
  rc=0
  (
    export PLANWRIGHT_FLEET_STATE_DIR="$sentinel/fleet"
    [ -z "${CLAUDE_PLUGIN_DATA+set}" ] || export CLAUDE_PLUGIN_DATA="$sentinel/plugin-data"
    [ -z "${CLAUDE_DIR+set}" ] || export CLAUDE_DIR="$sentinel/claude"
    export SPEC_WALKTHROUGH_DOT_TIMEOUT="${SPEC_WALKTHROUGH_DOT_TIMEOUT:-60}"
    # shellcheck disable=SC2086 # --runner is a command line by contract
    exec $runner "./$t"
  ) >"$work/out" 2>&1 </dev/null || rc=$?
  for fh in "$sentinel/fleet" "$sentinel/plugin-data" "$sentinel/claude"; do
    if [ -e "$fh" ] || [ -L "$fh" ]; then
      printf '%s\n' "$prog: the test wrote into the fleet home it inherited (under a fleet worker, the operator's real one); pin a fixture home per case (tests/lib/fleet-home.sh)" >>"$work/out"
      rc=1
      break
    fi
  done
  if [ "$rc" -eq 0 ]; then
    say 'pass\ttest\t%s\n' "$t"
  else
    say 'fail\ttest\t%s\n' "$t"
    printable <"$work/out" >&2
    status=1
  fi
done <"$work/tests"
for tool in shellcheck shfmt markdownlint-cli2 yamllint; do
  awk -F '\t' -v t="$tool" '$1 == t { print $2 }' "$work/lint" >"$work/files"
  [ -s "$work/files" ] || continue
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'skipped\tlint\t%s\tnot installed\n' "$tool"
    continue
  fi
  set --
  # markdownlint-cli2 reads a `:`-prefixed argument as a literal path.
  case $tool in markdownlint-cli2) lit=: ;; *) lit= ;; esac
  while IFS= read -r f; do set -- "$@" "$lit./$f"; done <"$work/files"
  case $tool in
    shellcheck) set -- -x "$@" ;;
    shfmt) set -- -d "$@" ;;
    yamllint) set -- --strict "$@" ;;
  esac
  if "$tool" "$@" >"$work/out" 2>&1 </dev/null; then
    printf 'pass\tlint\t%s\n' "$tool"
  else
    printf 'fail\tlint\t%s\n' "$tool"
    printable <"$work/out" >&2
    status=1
  fi
done
exit "$status"
