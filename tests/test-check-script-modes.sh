#!/bin/bash
# Tests for scripts/check-script-modes.sh — the executable-bit guard over the
# shipped scripts/*.sh.
#
# A script committed without its executable bit works through `bash <path>`
# and fails with "Permission denied" (exit 126) when called by path, which is
# how a plugin cache invokes it. The mode lives in the git index, not on disk,
# so the fixtures set the index mode directly and the guard must read it from
# there: a worktree chmod that never reached the index ships nothing.
#
# The fail-closed arm is the other half: a scan that reaches no scripts, or a
# root that is not a repository, must exit 2 rather than report clean.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-script-modes.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*)
      echo "FAIL: $1 (output mentioned '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# make_repo <dir> — an empty repository with its own identity, so the
# fixtures never read the host's git config for anything that matters.
make_repo() {
  mkdir -p "$1/scripts" || exit 1
  git -C "$1" init -q || exit 1
  git -C "$1" config core.fileMode true
}

# stage <dir> <path> <index-mode> <line>... — write the file and record it in
# the index at exactly <index-mode> (644 or 755), whatever the disk mode is.
stage() {
  st_dir="$1"
  st_path="$2"
  st_mode="$3"
  shift 3
  mkdir -p "$(dirname "$st_dir/$st_path")" || exit 1
  printf '%s\n' "$@" >"$st_dir/$st_path" || exit 1
  git -C "$st_dir" add -- "$st_path" || exit 1
  if [ "$st_mode" = 755 ]; then
    git -C "$st_dir" update-index --chmod=+x -- "$st_path" || exit 1
  else
    git -C "$st_dir" update-index --chmod=-x -- "$st_path" || exit 1
  fi
}

# ---------------------------------------------------------------------------
# 1. The real tree passes, and the count is asserted rather than discarded:
#    it is the only evidence telling "scanned and found nothing" apart from
#    "scanned almost nothing".
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" 2>&1)"
assert "the repo's own scripts carry the right modes" 0 $?
assert_contains "the clean run reports a script count" "$out" "check-script-modes: clean ("
real_count="$(printf '%s' "$out" | sed -n 's/.*clean (\([0-9]*\) scripts).*/\1/p')"
if [ -n "$real_count" ] && [ "$real_count" -ge 100 ]; then
  echo "ok: the scan reached every shipped script ($real_count)"
else
  echo "FAIL: the scan covered implausibly few scripts (got '$real_count')" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 2. An executable with its bit and a sourced library without one pass.
# ---------------------------------------------------------------------------
make_repo "$tmp/good"
stage "$tmp/good" scripts/run.sh 755 '#!/bin/sh' 'echo run'
stage "$tmp/good" scripts/lib.sh 644 '# shellcheck shell=sh' 'f() { :; }'
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/good" 2>&1)"
assert "an executable at 100755 and a library at 100644 pass" 0 $?
assert_contains "the clean run counts both" "$out" "clean (2 scripts)"

# ---------------------------------------------------------------------------
# 3. The defect this guard exists for: a shebang script at 100644.
# ---------------------------------------------------------------------------
make_repo "$tmp/noexec"
stage "$tmp/noexec" scripts/run.sh 644 '#!/bin/bash' 'echo run'
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/noexec" 2>&1)"
assert "a shebang script without the executable bit fails" 1 $?
assert_contains "the failure names the script" "$out" "scripts/run.sh"
assert_contains "the failure names the fix" "$out" "git update-index --chmod=+x"
assert_not_contains "the failure names it relative to the root" "$out" "$tmp/noexec/scripts"

# ---------------------------------------------------------------------------
# 4. The index is the truth: a worktree chmod that never reached the index
#    still fails, since the index mode is what ships.
# ---------------------------------------------------------------------------
make_repo "$tmp/diskonly"
stage "$tmp/diskonly" scripts/run.sh 644 '#!/bin/sh' 'echo run'
chmod 755 "$tmp/diskonly/scripts/run.sh"
/bin/bash "$CHECKER" --repo-root "$tmp/diskonly" >/dev/null 2>&1
assert "an executable bit on disk but not in the index fails" 1 $?

# ---------------------------------------------------------------------------
# 5. The mirror: an executable bit on a shebang-less file. Exec'ing it gets
#    ENOEXEC and whichever shell the caller happens to run; the shebang is the
#    one declaration of "this is run, not sourced", and the mode must agree.
# ---------------------------------------------------------------------------
make_repo "$tmp/libexec"
stage "$tmp/libexec" scripts/lib.sh 755 '# shellcheck shell=sh' 'f() { :; }'
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/libexec" 2>&1)"
assert "an executable bit on a shebang-less library fails" 1 $?
assert_contains "the failure names the library" "$out" "scripts/lib.sh"

# ---------------------------------------------------------------------------
# 6. A mode that is neither (a symbolic link) is reported, not skipped.
# ---------------------------------------------------------------------------
make_repo "$tmp/link"
stage "$tmp/link" scripts/run.sh 755 '#!/bin/sh'
ln -s run.sh "$tmp/link/scripts/alias.sh"
git -C "$tmp/link" add -- scripts/alias.sh || exit 1
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/link" 2>&1)"
assert "a symbolic link under scripts/ fails" 1 $?
assert_contains "the failure names the link" "$out" "scripts/alias.sh"

# ---------------------------------------------------------------------------
# 7. Scope is scripts/*.sh at the top level, the same set lint:shell reads:
#    nested directories and non-.sh files are not shipped scripts.
# ---------------------------------------------------------------------------
make_repo "$tmp/scope"
stage "$tmp/scope" scripts/run.sh 755 '#!/bin/sh'
stage "$tmp/scope" scripts/sub/deep.sh 644 '#!/bin/sh'
stage "$tmp/scope" scripts/data.jq 644 '#!/usr/bin/jq -f'
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/scope" 2>&1)"
assert "nested and non-.sh files are out of scope" 0 $?
assert_contains "only the top-level script is counted" "$out" "clean (1 scripts)"

# ---------------------------------------------------------------------------
# 8. Every finding is reported in one run, not just the first.
# ---------------------------------------------------------------------------
make_repo "$tmp/many"
stage "$tmp/many" scripts/a.sh 644 '#!/bin/sh'
stage "$tmp/many" scripts/b.sh 644 '#!/bin/sh'
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/many" 2>&1)"
assert "two offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "scripts/a.sh"
assert_contains "the second offender is named" "$out" "scripts/b.sh"

# ---------------------------------------------------------------------------
# 9. BSD mktemp supplies no default template, so a bare `mktemp` fails on the
#    macOS half of the support bar. A stub refusing a template-less call
#    stands in for it; the guard must still run clean.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bsdbin" || exit 1
real_mktemp="$(command -v mktemp)" || exit 1
printf '#!/bin/sh\n[ $# -gt 0 ] || { echo "usage: mktemp [-d] template" >&2; exit 1; }\nexec %s "$@"\n' \
  "$real_mktemp" >"$tmp/bsdbin/mktemp" || exit 1
chmod 755 "$tmp/bsdbin/mktemp" || exit 1
out="$(PATH="$tmp/bsdbin:$PATH" /bin/bash "$CHECKER" --repo-root "$tmp/good" 2>&1)"
assert "the guard runs where mktemp has no default template" 0 $?
assert_contains "it still reports the scan" "$out" "clean (2 scripts)"

# ---------------------------------------------------------------------------
# 10. Fail closed: nothing to scan, or no repository, is exit 2, never clean.
# ---------------------------------------------------------------------------
make_repo "$tmp/empty"
out="$(/bin/bash "$CHECKER" --repo-root "$tmp/empty" 2>&1)"
assert "a repository with no scripts/*.sh fails closed" 2 $?
assert_not_contains "the empty scan does not read as clean" "$out" "clean ("

mkdir -p "$tmp/norepo/scripts"
printf '#!/bin/sh\n' >"$tmp/norepo/scripts/run.sh"
/bin/bash "$CHECKER" --repo-root "$tmp/norepo" >/dev/null 2>&1
assert "a root outside any repository fails closed" 2 $?

/bin/bash "$CHECKER" --repo-root "$tmp/does-not-exist" >/dev/null 2>&1
assert "an absent root fails closed" 2 $?

/bin/bash "$CHECKER" --bogus >/dev/null 2>&1
assert "an unknown argument is a usage error" 2 $?

/bin/bash "$CHECKER" --help >/dev/null 2>&1
assert "--help exits 0" 0 $?

if [ "$failures" -ne 0 ]; then
  echo "check-script-modes tests: $failures failure(s)" >&2
  exit 1
fi
echo "check-script-modes tests: all passed"
