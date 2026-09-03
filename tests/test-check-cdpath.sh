#!/bin/bash
# Tests for scripts/check-cdpath.sh — the CDPATH house-pattern guard.
#
# The guard flags any shebang-bearing file under scripts/, tests/, or
# githooks/ that resolves paths through `cd` inside a command substitution
# without a top-level `unset CDPATH`. Enumeration is by shebang rather than
# by *.sh extension, so the extensionless githooks/ hooks are actually
# covered — the gap that motivated the guard.
#
# The fail-closed arm covers a zero-file enumeration and a missing scope
# directory: a scan that reaches nothing is a broken enumeration, not a
# clean tree.
#
# shellcheck disable=SC2016 # every fixture body below is literal shell text
# the guard must read as written; expanding it here would defeat the fixture.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-cdpath.sh"

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

# Build a fixture root with the three scope directories present and empty.
make_root() {
  mkdir -p "$1/scripts" "$1/tests" "$1/githooks"
}

# write_script <path> <mode> <body-line>... — a shebang-bearing file whose
# mode is `unset` (carries the top-level unset) or `bare` (does not).
write_script() {
  ws_path="$1"
  ws_mode="$2"
  shift 2
  mkdir -p "$(dirname "$ws_path")"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -u'
    [ "$ws_mode" = "unset" ] && echo 'unset CDPATH'
    for ws_line in "$@"; do
      echo "$ws_line"
    done
  } >"$ws_path"
}

# ---------------------------------------------------------------------------
# 1. The real tree passes. Every shipped script that resolves paths through a
#    cd-substitution already carries the unset; this is the assertion that
#    keeps it that way.
# ---------------------------------------------------------------------------
/bin/bash "$CHECKER" >/dev/null
assert "the repo's own tree is CDPATH-clean" 0 $?

# ---------------------------------------------------------------------------
# 2. A compliant fixture passes: the cd-substitution is there, and so is the
#    top-level unset.
# ---------------------------------------------------------------------------
make_root "$tmp/good"
write_script "$tmp/good/scripts/resolve.sh" unset \
  'root="$(cd "$(dirname "$0")/.." && pwd)"' \
  'echo "$root"'
/bin/bash "$CHECKER" "$tmp/good" >/dev/null
assert "a cd-substitution with a top-level unset passes" 0 $?

# ---------------------------------------------------------------------------
# 3. The same script without the unset fails and is named.
# ---------------------------------------------------------------------------
make_root "$tmp/bare"
write_script "$tmp/bare/scripts/resolve.sh" bare \
  'root="$(cd "$(dirname "$0")/.." && pwd)"' \
  'echo "$root"'
out="$(/bin/bash "$CHECKER" "$tmp/bare" 2>&1)"
assert "a cd-substitution without the unset fails" 1 $?
assert_contains "the failure names the offending file" "$out" "scripts/resolve.sh"

# ---------------------------------------------------------------------------
# 4. An extensionless githooks/ hook is reached. This is the case a *.sh glob
#    misses and the reason enumeration goes by shebang.
# ---------------------------------------------------------------------------
make_root "$tmp/hook"
write_script "$tmp/hook/githooks/pre-commit" bare \
  'repo="$(cd "$(dirname "$0")/.." && pwd)"' \
  'echo "$repo"'
out="$(/bin/bash "$CHECKER" "$tmp/hook" 2>&1)"
assert "an offending extensionless hook fails" 1 $?
assert_contains "the failure names the hook" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 5. The backtick substitution form is the same footgun and is flagged too.
# ---------------------------------------------------------------------------
make_root "$tmp/backtick"
write_script "$tmp/backtick/tests/legacy.sh" bare \
  'root=`cd "$(dirname "$0")/.." && pwd`' \
  'echo "$root"'
out="$(/bin/bash "$CHECKER" "$tmp/backtick" 2>&1)"
assert "the backtick substitution form fails" 1 $?
assert_contains "the backtick failure names the file" "$out" "tests/legacy.sh"

# ---------------------------------------------------------------------------
# 6. A file with no shebang is not enumerated, even when it contains the
#    offending text. Enumeration is by shebang, so data and prose files under
#    the scope directories are out of reach by construction.
# ---------------------------------------------------------------------------
make_root "$tmp/no-shebang"
write_script "$tmp/no-shebang/scripts/ok.sh" unset 'echo fine'
mkdir -p "$tmp/no-shebang/tests"
printf '%s\n' 'root="$(cd .. && pwd)"' >"$tmp/no-shebang/tests/notes.txt"
out="$(/bin/bash "$CHECKER" "$tmp/no-shebang" 2>&1)"
assert "a shebang-less file is not scanned" 0 $?
assert_not_contains "the clean run does not name the data file" "$out" "notes.txt"

# ---------------------------------------------------------------------------
# 7. A comment mentioning the pattern is not a use of it.
# ---------------------------------------------------------------------------
make_root "$tmp/comment"
write_script "$tmp/comment/scripts/doc.sh" bare \
  '# A $(cd ...) here would need a top-level unset CDPATH.' \
  'echo fine'
/bin/bash "$CHECKER" "$tmp/comment" >/dev/null 2>&1
assert "a commented-out pattern is not flagged" 0 $?

# ---------------------------------------------------------------------------
# 8. Fail closed: a scope tree holding no shebang-bearing file at all is a
#    broken enumeration, not a clean tree (REQ-H1.3).
# ---------------------------------------------------------------------------
make_root "$tmp/empty"
out="$(/bin/bash "$CHECKER" "$tmp/empty" 2>&1)"
assert "a zero-file enumeration fails closed" 2 $?
assert_contains "the zero-file failure says so" "$out" "no shebang-bearing files"

# ---------------------------------------------------------------------------
# 8b. Fail closed the same way when the scan finds files but every scope
#     directory it was told to walk is gone: a silently narrowed scope must
#     not read as clean.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/partial/scripts"
write_script "$tmp/partial/scripts/ok.sh" unset 'echo fine'
out="$(/bin/bash "$CHECKER" "$tmp/partial" 2>&1)"
assert "a missing scope directory fails closed" 2 $?
assert_contains "the missing-scope failure names the directory" "$out" "githooks"

# ---------------------------------------------------------------------------
# 9. Fail closed: a root that does not exist is a usage error.
# ---------------------------------------------------------------------------
/bin/bash "$CHECKER" "$tmp/no-such-root" >/dev/null 2>&1
assert "a missing root is an error" 2 $?

# ---------------------------------------------------------------------------
# 10. Every offender is reported, not just the first — one red run should tell
#     the author about all of them.
# ---------------------------------------------------------------------------
make_root "$tmp/many"
write_script "$tmp/many/scripts/one.sh" bare 'root="$(cd .. && pwd)"'
write_script "$tmp/many/tests/two.sh" bare 'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/many" 2>&1)"
assert "multiple offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "scripts/one.sh"
assert_contains "the second offender is named" "$out" "tests/two.sh"

# ---------------------------------------------------------------------------
# 11. --help records the CDPATH=. regression-test convention, so an author
#     adding a cd-resolving script learns what test to write from the guard
#     that flagged them.
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" --help 2>&1)"
assert "--help exits clean" 0 $?
assert_contains "--help records the regression-test convention" "$out" "CDPATH=."

# ---------------------------------------------------------------------------
# 12. The convention applied to this task's own script: check-cdpath.sh
#     resolves its scope through a cd-substitution, so it gets the CDPATH=.
#     regression test its --help prescribes. Under a CDPATH that would make
#     `cd` echo, the derived root must still be the real one.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/decoy" "$tmp/work"
cp -R "$REPO_ROOT/scripts" "$tmp/work/"
cp -R "$REPO_ROOT/tests" "$tmp/work/"
cp -R "$REPO_ROOT/githooks" "$tmp/work/"
(cd "$tmp/work" && CDPATH=".:$tmp/decoy" /bin/bash scripts/check-cdpath.sh >/dev/null 2>&1)
assert "CDPATH=. does not corrupt the guard's own root derivation" 0 $?

# ---------------------------------------------------------------------------
# 13. The guard is wired into the `check` aggregate, so a red run is reachable
#     from `mise run check` rather than only by direct invocation.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks\."check:cdpath"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:cdpath is defined as a mise task"
else
  echo "FAIL: mise.toml defines no check:cdpath task" >&2
  failures=$((failures + 1))
fi
if grep -q '^  "check:cdpath",' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:cdpath is wired into the check aggregate"
else
  echo "FAIL: check:cdpath is not in the check aggregate's depends list" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-cdpath tests passed"
