#!/bin/sh
# check-diff-scoped.sh — the per-fix check: run the tests touching the changed
# files and the linters over them, so each fix is validated in seconds while
# the full suite runs once per loop iteration (review-effectiveness REQ-D1.3,
# D-11).
#
# THE CHANGED FILES are the paths given, or with --base <rev> every file that
# differs from it: committed, uncommitted, and untracked (ignored files
# excepted).
#
# THE TESTS are the files matching --tests (default `tests/test-*.sh`) that
# are themselves changed, or that name a changed file by its repo path, or by
# its basename when no other file in the repository shares it. A test reaching
# a file only through a constructed path is not selected; the full suite
# covers it.
#
# THE LINTERS, per changed file that still exists: shellcheck and `shfmt -d`
# on shell (`.sh`, `.bash`, or an extensionless file with a shell shebang),
# markdownlint-cli2 on `.md`, `yamllint --strict` on `.yml` and `.yaml`. A
# linter not on PATH is reported as skipped, never passed.
#
# Prints `test <file>` and `lint <tool> <file>` lines with --list, running
# nothing; otherwise `pass|fail test <file>`, `pass|fail lint <tool>`, and
# `skipped lint <tool> not installed`, a failure's output going to stderr.
# Tests run one at a time from the repository root through --runner (default
# /bin/bash, the repo's bash 3.2 floor, else bash on PATH).
#
# Usage:
#   check-diff-scoped.sh [--list] [--tests <pathspec>] [--runner <command>]
#       (--base <rev> | <path>...)
#
# Exit codes: 0 no selected check failed (or nothing was selected); a
#   skipped linter is reported on its own line and does not fail the
#   check, so a consumer reads the `skipped` lines; 1 a test or linter failed;
#   2 usage or a refused path.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-diff-scoped
NL='
'

usage() {
  cat >&2 <<EOF
usage: $prog [--list] [--tests <pathspec>] [--runner <command>] (--base <rev> | <path>...)
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

list=0
base=
tests_spec='tests/test-*.sh'
runner=
while [ $# -gt 0 ]; do
  case $1 in
    --list)
      list=1
      shift
      ;;
    --base | --tests | --runner)
      [ $# -ge 2 ] || usage
      case $1 in
        --base) base=$2 ;;
        --tests) tests_spec=$2 ;;
        --runner) runner=$2 ;;
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

work=$(mktemp -d "${TMPDIR:-/tmp}/check-diff-scoped.XXXXXX")
trap 'rm -rf "$work"' EXIT
changed=$work/changed
if [ -n "$base" ]; then
  case $base in -*) die 2 "--base must be a revision, not an option" ;; esac
  sha=$(git rev-parse --verify --quiet "$base^{commit}") || die 2 "--base names no commit: $base"
  {
    git -c core.quotePath=false diff --no-ext-diff --name-only "$sha" --
    git -c core.quotePath=false ls-files --others --exclude-standard
  } | sort -u >"$changed"
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

{
  git -c core.quotePath=false ls-files -- "$tests_spec"
  git -c core.quotePath=false ls-files --others --exclude-standard -- "$tests_spec"
} | sort -u >"$work/all-tests"
git -c core.quotePath=false ls-files --cached --others --exclude-standard \
  | awk -F/ '{ n[$NF]++ } END { for (b in n) if (n[b] == 1) print b }' >"$work/unique-basenames"

: >"$work/tests"
: >"$work/lint"
while IFS= read -r f; do
  grep -Fxq -e "$f" "$work/all-tests" && printf '%s\n' "$f" >>"$work/tests"
  b=${f##*/}
  while IFS= read -r t; do
    [ -f "$t" ] || continue
    if grep -Fq -e "$f" "$t" \
      || { grep -Fxq -e "$b" "$work/unique-basenames" && grep -Fq -e "$b" "$t"; }; then
      printf '%s\n' "$t" >>"$work/tests"
    fi
  done <"$work/all-tests"
  [ -f "$f" ] || continue
  case $f in
    *.sh | *.bash) printf 'shellcheck\t%s\nshfmt\t%s\n' "$f" "$f" >>"$work/lint" ;;
    *.md) printf 'markdownlint-cli2\t%s\n' "$f" >>"$work/lint" ;;
    *.yml | *.yaml) printf 'yamllint\t%s\n' "$f" >>"$work/lint" ;;
    */*.* | *.*) ;;
    *)
      if sed -n 1p "$f" | grep -Eq '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)'; then
        printf 'shellcheck\t%s\nshfmt\t%s\n' "$f" "$f" >>"$work/lint"
      fi
      ;;
  esac
done <"$changed"
sort -u -o "$work/tests" "$work/tests"

if [ "$list" -eq 1 ]; then
  sed 's/^/test\t/' "$work/tests"
  sed 's/^/lint\t/' "$work/lint"
  exit 0
fi

# --- running -----------------------------------------------------------------

status=0
while IFS= read -r t; do
  # shellcheck disable=SC2086 # --runner is a command line by contract
  if $runner "$t" >"$work/out" 2>&1 </dev/null; then
    printf 'pass\ttest\t%s\n' "$t"
  else
    printf 'fail\ttest\t%s\n' "$t"
    cat "$work/out" >&2
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
  while IFS= read -r f; do set -- "$@" "$f"; done <"$work/files"
  case $tool in
    shfmt) set -- -d "$@" ;;
    yamllint) set -- --strict "$@" ;;
  esac
  if "$tool" "$@" >"$work/out" 2>&1 </dev/null; then
    printf 'pass\tlint\t%s\n' "$tool"
  else
    printf 'fail\tlint\t%s\n' "$tool"
    cat "$work/out" >&2
    status=1
  fi
done
exit "$status"
