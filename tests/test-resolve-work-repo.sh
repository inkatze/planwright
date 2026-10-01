#!/bin/bash
# Tests for scripts/resolve-work-repo.sh: which repository a bundle's
# execution state derives from, with the bundle in the work repository, in
# a holder repository, and in a plain directory, from the primary checkout,
# a worktree, and outside any repository. Plain bash 3.2, inline asserts.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HELPER="$REPO_ROOT/scripts/resolve-work-repo.sh"
SH=$(command -v dash || echo /bin/sh)

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case $3 in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to contain '$2', got '$3')" >&2
      failures=$((failures + 1))
      ;;
  esac
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home" "$tmp/adopter"
printf 'unrelated_key: 1\n' >"$tmp/core.yml"
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG HOME="$tmp/home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$@"
}
run() {
  rn_dir=$1
  shift
  (cd "$rn_dir" && base "$@") >"$tmp/.out" 2>"$tmp/.err"
  rc=$?
  out=$(cat "$tmp/.out")
  err=$(cat "$tmp/.err")
}
gitq() { base git "$@" >/dev/null 2>&1; }
mkrepo() {
  mkdir -p "$1"
  gitq -C "$1" init -q
  gitq -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}
mark() { printf 'project: fixture\nlayout: 1\n' >"$1/planwright-spec-root.yml"; }
bundle() { mkdir -p "$1" && printf '# T\n' >"$1/tasks.md"; }

# The work repository with a default-root bundle and a worktree of it.
mkrepo "$tmp/work"
bundle "$tmp/work/specs/demo"
gitq -C "$tmp/work" add -A
gitq -C "$tmp/work" -c user.name=t -c user.email=t@example.invalid commit -q -m bundle
gitq -C "$tmp/work" worktree add -q "$tmp/work/.claude/worktrees/wt" -b wt

run "$tmp/work" "$SH" "$HELPER" specs/demo
assert_eq "default root: the bundle's own repository (exit)" 0 "$rc"
assert_eq "default root: the bundle's own repository" "$tmp/work" "$out"

run "$tmp/work/.claude/worktrees/wt" "$SH" "$HELPER" specs/demo
assert_eq "default root from a worktree: the primary checkout" "$tmp/work" "$out"

run "$tmp/work/.claude/worktrees/wt" "$SH" "$HELPER" "$tmp/work/specs/demo"
assert_eq "the primary's bundle from a worktree: the primary checkout" "$tmp/work" "$out"

# Addressed from outside any repository, a default-layout bundle still
# derives from the repository it sits in.
mkdir -p "$tmp/elsewhere"
run "$tmp/elsewhere" "$SH" "$HELPER" "$tmp/work/specs/demo"
assert_eq "from outside a repository: the bundle's own repository" "$tmp/work" "$out"

# From another repository whose root does not hold the bundle: the bundle's.
mkrepo "$tmp/other"
run "$tmp/other" "$SH" "$HELPER" "$tmp/work/specs/demo"
assert_eq "from an unrelated repository: the bundle's own repository" "$tmp/work" "$out"

# A holder: the work repository points spec_root at a directory in a second
# repository. The bundle derives from the work repository, never the holder.
mkrepo "$tmp/holder"
mkdir -p "$tmp/holder/work-specs"
mark "$tmp/holder/work-specs"
bundle "$tmp/holder/work-specs/demo"
mkdir -p "$tmp/work/.claude"
printf 'spec_root: %s\n' "$tmp/holder/work-specs" >"$tmp/work/.claude/planwright.local.yml"
run "$tmp/work" "$SH" "$HELPER" "$tmp/holder/work-specs/demo"
assert_eq "holder root: the work repository (exit)" 0 "$rc"
assert_eq "holder root: the work repository, not the holder" "$tmp/work" "$out"
run "$tmp/work/.claude/worktrees/wt" "$SH" "$HELPER" "$tmp/holder/work-specs/demo"
assert_eq "holder root from a worktree: the work repository's primary" "$tmp/work" "$out"
run "$tmp/holder" "$SH" "$HELPER" "$tmp/holder/work-specs/demo"
assert_eq "holder bundle from the holder: the holder is all it can name" "$tmp/holder" "$out"

# A plain directory: the work repository owns it through spec_root.
mkdir -p "$tmp/plain-specs"
mark "$tmp/plain-specs"
bundle "$tmp/plain-specs/demo"
printf 'spec_root: %s\n' "$tmp/plain-specs" >"$tmp/work/.claude/planwright.local.yml"
run "$tmp/work" "$SH" "$HELPER" "$tmp/plain-specs/demo"
assert_eq "plain root: the work repository" "$tmp/work" "$out"
run "$tmp/elsewhere" "$SH" "$HELPER" "$tmp/plain-specs/demo"
assert_eq "plain root with no owning repository in sight (exit)" 3 "$rc"
assert_contains "plain root with no owning repository says so" "no work repository" "$err"
rm -f "$tmp/work/.claude/planwright.local.yml"

# An in-repo relocated root.
mkdir -p "$tmp/work/docs/specs-here"
mark "$tmp/work/docs/specs-here"
bundle "$tmp/work/docs/specs-here/demo"
printf 'spec_root: docs/specs-here\n' >"$tmp/work/.claude/planwright.local.yml"
run "$tmp/work" "$SH" "$HELPER" docs/specs-here/demo
assert_eq "in-repo relocated root: the work repository" "$tmp/work" "$out"
rm -f "$tmp/work/.claude/planwright.local.yml"

# PLANWRIGHT_REPO_ROOT names the current repository, as it does for the
# primary-root helper, and a refused value is refused here too.
run "$tmp/elsewhere" env PLANWRIGHT_REPO_ROOT="$tmp/work" "$SH" "$HELPER" "$tmp/work/specs/demo"
assert_eq "PLANWRIGHT_REPO_ROOT naming the work repository" "$tmp/work" "$out"
run "$tmp/work" env PLANWRIGHT_REPO_ROOT="$tmp/elsewhere" "$SH" "$HELPER" specs/demo
assert_eq "a refused PLANWRIGHT_REPO_ROOT (exit)" 4 "$rc"
assert_contains "a refused PLANWRIGHT_REPO_ROOT names the variable" "PLANWRIGHT_REPO_ROOT" "$err"

# Usage.
run "$tmp/work" "$SH" "$HELPER"
assert_eq "no argument is a usage error" 2 "$rc"
run "$tmp/work" "$SH" "$HELPER" specs/absent
assert_eq "a missing bundle directory is refused" 2 "$rc"

echo
if [ "$failures" -eq 0 ]; then
  echo "all resolve-work-repo tests passed"
  exit 0
fi
echo "$failures resolve-work-repo test(s) failed" >&2
exit 1
