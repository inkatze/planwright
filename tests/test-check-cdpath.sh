#!/bin/bash
# Tests for scripts/check-cdpath.sh — the CDPATH house-pattern guard
# (guard-coverage Task 10; REQ-G1.2, REQ-H1.3; D-12).
#
# The guard flags a shell file that resolves paths through `cd` inside a
# command substitution without a top-level `unset CDPATH`. The cases below are
# organised around the ways such a file can hide: a substitution written across
# two lines, a library with no shebang, a remedy that appears in a heredoc or
# inside a function without ever running.
#
# The fail-closed arm (REQ-H1.3) is the other half. Anything that would make
# the scan cover less than it claims — an unreadable file, an absent scope
# directory, a filename the enumeration cannot carry, a scan reaching nothing —
# must exit 2 rather than report a clean tree.
#
# shellcheck disable=SC2016 # every fixture body below is literal shell text
# the guard must read as written; expanding it here would defeat the fixture.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

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

make_root() {
  mkdir -p "$1/scripts" "$1/tests" "$1/githooks" || exit 1
}

# write_file <path> <line>... — verbatim, no shebang added.
write_file() {
  wf_path="$1"
  shift
  mkdir -p "$(dirname "$wf_path")" || exit 1
  for wf_line in "$@"; do
    echo "$wf_line"
  done >"$wf_path" || exit 1
}

# write_script <path> <mode> <line>... — a shebang-bearing file. Mode `unset`
# prepends a top-level `unset CDPATH`; `bare` does not.
write_script() {
  ws_path="$1"
  ws_mode="$2"
  shift 2
  if [ "$ws_mode" = "unset" ]; then
    write_file "$ws_path" '#!/usr/bin/env bash' 'set -u' 'unset CDPATH' "$@"
  else
    write_file "$ws_path" '#!/usr/bin/env bash' 'set -u' "$@"
  fi
}

# ---------------------------------------------------------------------------
# 1. The real tree passes, and the count is asserted rather than discarded.
#    The count is the only evidence distinguishing "scanned the tree and found
#    nothing" from "scanned almost nothing and found nothing".
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" 2>&1)"
assert "the repo's own tree is CDPATH-clean" 0 $?
assert_contains "the clean run reports a file count" "$out" "check-cdpath: clean ("
real_count="$(printf '%s' "$out" | sed -n 's/.*clean (\([0-9]*\) files).*/\1/p')"
if [ -n "$real_count" ] && [ "$real_count" -ge 200 ]; then
  echo "ok: the scan reached the whole tree ($real_count files)"
else
  echo "FAIL: the scan covered implausibly few files (got '$real_count')" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 2. A cd-substitution with a top-level unset passes; without it, fails.
# ---------------------------------------------------------------------------
make_root "$tmp/good"
write_script "$tmp/good/scripts/resolve.sh" unset \
  'root="$(cd "$(dirname "$0")/.." && pwd)"' \
  'echo "$root"'
/bin/bash "$CHECKER" "$tmp/good" >/dev/null 2>&1
assert "a cd-substitution with a top-level unset passes" 0 $?

make_root "$tmp/bare"
write_script "$tmp/bare/scripts/resolve.sh" bare \
  'root="$(cd "$(dirname "$0")/.." && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/bare" 2>&1)"
assert "a cd-substitution without the unset fails" 1 $?
assert_contains "the failure names the offending file" "$out" "scripts/resolve.sh"
assert_not_contains "the failure names it relative to the root" "$out" "$tmp/bare/scripts"

# ---------------------------------------------------------------------------
# 3. An extensionless githooks/ hook is reached — the case a *.sh glob misses.
# ---------------------------------------------------------------------------
make_root "$tmp/hook"
write_script "$tmp/hook/githooks/pre-commit" bare \
  'repo="$(cd "$(dirname "$0")/.." && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/hook" 2>&1)"
assert "an offending extensionless hook fails" 1 $?
assert_contains "the failure names the hook" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 4. A shebang-less .sh library is reached — the mirror gap. The repo's own
#    sourced libraries (echo-safety.sh, spec-parse.sh) open with a
#    `# shellcheck shell=` line, and a shared path-resolving helper would live
#    in exactly such a file.
# ---------------------------------------------------------------------------
make_root "$tmp/lib"
write_file "$tmp/lib/scripts/helper.sh" \
  '# shellcheck shell=bash' \
  'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/lib" 2>&1)"
assert "an offending shebang-less .sh library fails" 1 $?
assert_contains "the failure names the library" "$out" "scripts/helper.sh"

# ---------------------------------------------------------------------------
# 5. The substitution written across two lines — this repo's own house style
#    for a long substitution, and invisible to any line-at-a-time match.
# ---------------------------------------------------------------------------
make_root "$tmp/multiline"
write_script "$tmp/multiline/scripts/split.sh" bare \
  'root=$(' \
  '  cd "$(dirname "$0")/.." && pwd' \
  ')'
out="$(/bin/bash "$CHECKER" "$tmp/multiline" 2>&1)"
assert "a multi-line cd substitution fails" 1 $?
assert_contains "the multi-line failure names the file" "$out" "scripts/split.sh"

# Blank and comment lines do not close a substitution, so neither may reset the
# state that carries `$(` to the `cd` below it. Both spellings are valid shell
# and both would otherwise slip past.
make_root "$tmp/spaced"
write_script "$tmp/spaced/scripts/blank.sh" bare \
  'root=$(' \
  '' \
  '  cd "$(dirname "$0")/.." && pwd' \
  ')'
write_script "$tmp/spaced/tests/commented.sh" bare \
  'root=$(' \
  '  # resolve the repo root' \
  '  cd .. && pwd' \
  ')'
out="$(/bin/bash "$CHECKER" "$tmp/spaced" 2>&1)"
assert "a blank or comment line does not hide the substitution" 1 $?
assert_contains "the blank-line offender is named" "$out" "scripts/blank.sh"
assert_contains "the comment-line offender is named" "$out" "tests/commented.sh"

# A trailing comment or a line continuation after the opening `$(` still opens
# a substitution, and a heredoc operator quoted inside a string does not open a
# heredoc — believing otherwise would swallow the rest of the file.
make_root "$tmp/opening"
write_script "$tmp/opening/scripts/trailing.sh" bare \
  'root=$( # resolve the repo root' \
  '  cd .. && pwd' \
  ')'
write_script "$tmp/opening/tests/continued.sh" bare \
  "root=\$( \\" \
  '  cd .. && pwd' \
  ')'
write_script "$tmp/opening/githooks/quoted-op" bare \
  'echo "<<EOF"' \
  'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/opening" 2>&1)"
assert "a comment, a continuation, or a quoted heredoc operator hides nothing" 1 $?
assert_contains "the trailing-comment offender is named" "$out" "scripts/trailing.sh"
assert_contains "the line-continuation offender is named" "$out" "tests/continued.sh"
assert_contains "the quoted-operator offender is named" "$out" "githooks/quoted-op"

# ---------------------------------------------------------------------------
# 6. The other substitution spellings: backtick, process substitution, and
#    pushd (which consults CDPATH and echoes exactly as cd does).
# ---------------------------------------------------------------------------
make_root "$tmp/forms"
write_script "$tmp/forms/tests/backtick.sh" bare 'root=`cd .. && pwd`'
write_script "$tmp/forms/tests/procsub.sh" bare 'read -r root < <(cd .. && pwd)'
write_script "$tmp/forms/githooks/pushy" bare 'root="$(pushd .. >/dev/null && pwd)"'
write_script "$tmp/forms/tests/grouped.sh" bare 'root=$({ cd ..; pwd; })'
out="$(/bin/bash "$CHECKER" "$tmp/forms" 2>&1)"
assert "the alternate substitution forms fail" 1 $?
assert_contains "the backtick form is named" "$out" "tests/backtick.sh"
assert_contains "the process-substitution form is named" "$out" "tests/procsub.sh"
assert_contains "the pushd form is named" "$out" "githooks/pushy"
assert_contains "a grouped substitution is named" "$out" "tests/grouped.sh"

# ---------------------------------------------------------------------------
# 7. A remedy that never runs must not clear the file. Both shapes below look
#    like compliance to a whole-file grep: an `unset CDPATH` quoted inside a
#    heredoc (the shape a guard's own usage text has), and one nested inside a
#    function, which does not take effect at the top level.
# ---------------------------------------------------------------------------
make_root "$tmp/inert"
write_script "$tmp/inert/scripts/heredoc.sh" bare \
  "cat <<'DOC'" \
  'unset CDPATH' \
  'DOC' \
  'root="$(cd .. && pwd)"'
write_script "$tmp/inert/scripts/nested.sh" bare \
  'guard() {' \
  '  unset CDPATH' \
  '}' \
  'root="$(cd .. && pwd)"'
write_script "$tmp/inert/tests/reassigned.sh" bare \
  'CDPATH=.:/var' \
  'root="$(cd .. && pwd)"'
# A delimiter carrying a non-word character, and a backslash-escaped one. Get
# either wrong and the scanner either never leaves the heredoc (swallowing
# every later offense) or never enters it (letting the body clear the file).
write_script "$tmp/inert/githooks/delim-punct" bare \
  'cat <<EOF-1' \
  'filler' \
  'EOF-1' \
  'root="$(cd .. && pwd)"'
write_script "$tmp/inert/githooks/delim-escaped" bare \
  'cat <<\DOC' \
  'unset CDPATH' \
  'DOC' \
  'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/inert" 2>&1)"
assert "an inert unset does not clear the file" 1 $?
assert_contains "the heredoc-only unset is rejected" "$out" "scripts/heredoc.sh"
assert_contains "the function-scoped unset is rejected" "$out" "scripts/nested.sh"
assert_contains "a non-empty CDPATH assignment is not a remedy" "$out" "tests/reassigned.sh"
assert_contains "a punctuated heredoc delimiter terminates properly" "$out" "githooks/delim-punct"
assert_contains "a backslash-escaped heredoc delimiter is recognised" "$out" "githooks/delim-escaped"

# ---------------------------------------------------------------------------
# 8. The spellings that do fix the bug all count as compliance. Rejecting any
#    of these would make the guard demand a specific incantation rather than
#    the behaviour, which is how a guard earns a reputation for noise.
# ---------------------------------------------------------------------------
make_root "$tmp/spellings"
write_file "$tmp/spellings/scripts/dash-v.sh" '#!/bin/sh' 'unset -v CDPATH' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/scripts/multi.sh" '#!/bin/sh' 'unset FOO CDPATH' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/scripts/semi.sh" '#!/bin/sh' 'unset CDPATH; set -u' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/tests/assign.sh" '#!/bin/sh' 'CDPATH=' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/tests/assign-semi.sh" '#!/bin/sh' 'CDPATH=;' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/tests/tolerant.sh" '#!/bin/sh' 'unset CDPATH 2>/dev/null || true' 'r="$(cd .. && pwd)"'
write_file "$tmp/spellings/githooks/plain" '#!/bin/sh' 'unset CDPATH' 'r="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/spellings" 2>&1)"
assert "every working unset spelling counts as compliance" 0 $?

# ---------------------------------------------------------------------------
# 9. A file that is neither shebang-bearing nor .sh is not scanned, and an
#    indented comment mentioning the pattern is not a use of it.
# ---------------------------------------------------------------------------
make_root "$tmp/notcode"
write_script "$tmp/notcode/scripts/ok.sh" unset 'echo fine'
write_file "$tmp/notcode/tests/notes.txt" 'root="$(cd .. && pwd)"'
write_script "$tmp/notcode/githooks/commented" bare \
  '    # An indented $(cd ...) mention is prose, not code.' \
  'echo fine'
out="$(/bin/bash "$CHECKER" "$tmp/notcode" 2>&1)"
assert "non-shell files and comments are not flagged" 0 $?
assert_not_contains "the data file is not named" "$out" "notes.txt"

# ---------------------------------------------------------------------------
# 10. Nested directories are scanned. The real tree keeps shell under
#     tests/lib/, which mise.toml's lint:shell enumerates explicitly, so a
#     depth-limited walk would silently drop it.
# ---------------------------------------------------------------------------
make_root "$tmp/nested"
write_script "$tmp/nested/tests/lib/helper.sh" bare 'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/nested" 2>&1)"
assert "an offender below the top level fails" 1 $?
assert_contains "the nested offender is named with its path" "$out" "tests/lib/helper.sh"

# ---------------------------------------------------------------------------
# 11. A symlinked script still runs, so it is still scanned.
# ---------------------------------------------------------------------------
make_root "$tmp/linked"
mkdir -p "$tmp/linktarget"
write_script "$tmp/linktarget/real.sh" bare 'root="$(cd .. && pwd)"'
ln -s "$tmp/linktarget/real.sh" "$tmp/linked/scripts/via-link.sh"
out="$(/bin/bash "$CHECKER" "$tmp/linked" 2>&1)"
assert "a symlinked offender fails" 1 $?
assert_contains "the symlinked offender is named" "$out" "scripts/via-link.sh"

# A symlinked directory is the case with no good traversal. Following it walks
# files outside the root and reports them as if they lived here; not following
# it covers less than the scan claims. Refusing is the fail-closed third
# answer (REQ-H1.3).
make_root "$tmp/linkdir"
mkdir -p "$tmp/linkdir-target"
write_script "$tmp/linkdir-target/foreign.sh" bare 'root="$(cd .. && pwd)"'
write_script "$tmp/linkdir/tests/ok.sh" unset 'echo fine'
ln -s "$tmp/linkdir-target" "$tmp/linkdir/scripts/vendored"
out="$(/bin/bash "$CHECKER" "$tmp/linkdir" 2>&1)"
assert "a symlinked scope subdirectory fails closed" 2 $?
assert_contains "the refusal names the symlink" "$out" "scripts/vendored"
assert_not_contains "the scan does not reach outside the root" "$out" "foreign.sh"

# A symlink pointing nowhere cannot be read, so it fails closed for the same
# reason an unreadable regular file does.
make_root "$tmp/linkbroken"
write_script "$tmp/linkbroken/tests/ok.sh" unset 'echo fine'
ln -s "$tmp/linkbroken/scripts/absent.sh" "$tmp/linkbroken/scripts/dangling.sh"
out="$(/bin/bash "$CHECKER" "$tmp/linkbroken" 2>&1)"
assert "a dangling symlink fails closed" 2 $?
assert_contains "the dangling-symlink failure names it" "$out" "scripts/dangling.sh"

# ---------------------------------------------------------------------------
# 12. Every offender is reported, not just the first.
# ---------------------------------------------------------------------------
make_root "$tmp/many"
write_script "$tmp/many/scripts/one.sh" bare 'root="$(cd .. && pwd)"'
write_script "$tmp/many/tests/two.sh" bare 'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/many" 2>&1)"
assert "multiple offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "scripts/one.sh"
assert_contains "the second offender is named" "$out" "tests/two.sh"

# ---------------------------------------------------------------------------
# 13. Fail-closed (REQ-H1.3). Each of these would otherwise be a scan that
#     covered less than it claims while reporting a clean tree.
# ---------------------------------------------------------------------------
make_root "$tmp/empty"
out="$(/bin/bash "$CHECKER" "$tmp/empty" 2>&1)"
assert "a zero-file enumeration fails closed" 2 $?
assert_contains "the zero-file failure says so" "$out" "no shell files"

mkdir -p "$tmp/partial/scripts"
write_script "$tmp/partial/scripts/ok.sh" unset 'echo fine'
out="$(/bin/bash "$CHECKER" "$tmp/partial" 2>&1)"
assert "a missing scope directory fails closed" 2 $?
assert_contains "the missing-scope failure names every missing directory" "$out" "tests githooks"

make_root "$tmp/unreadable"
write_script "$tmp/unreadable/scripts/secret.sh" unset 'echo fine'
chmod 000 "$tmp/unreadable/scripts/secret.sh"
out="$(/bin/bash "$CHECKER" "$tmp/unreadable" 2>&1)"
assert "an unreadable file fails closed" 2 $?
assert_contains "the unreadable failure names the file" "$out" "scripts/secret.sh"
chmod 644 "$tmp/unreadable/scripts/secret.sh"

out="$(/bin/bash "$CHECKER" "$tmp/no-such-root" 2>&1)"
assert "a missing root fails closed" 2 $?
assert_contains "the missing-root failure says so" "$out" "root not found"

out="$(/bin/bash "$CHECKER" "$tmp/good" "$tmp/bare" 2>&1)"
assert "a second root argument fails closed" 2 $?
assert_contains "the extra-argument failure says so" "$out" "too many arguments"

out="$(/bin/bash "$CHECKER" --docs 2>&1)"
assert "an unknown option fails closed" 2 $?
assert_contains "the unknown-option failure names the option" "$out" "--docs"

# ---------------------------------------------------------------------------
# 14. A root path containing whitespace scans correctly rather than degrading
#     into a misleading empty-tree report.
# ---------------------------------------------------------------------------
make_root "$tmp/with space"
write_script "$tmp/with space/githooks/pre-commit" bare 'root="$(cd .. && pwd)"'
out="$(/bin/bash "$CHECKER" "$tmp/with space" 2>&1)"
assert "a root containing whitespace still scans" 1 $?
assert_contains "the whitespace-root run names the real offender" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 15. --help and -h both work and record the regression-test convention.
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" --help 2>&1)"
assert "--help exits clean" 0 $?
assert_contains "--help records the regression-test convention" "$out" "CDPATH=."
assert_contains "--help notes which cd operands bypass CDPATH" "$out" "bypass CDPATH entirely"
/bin/bash "$CHECKER" -h >/dev/null 2>&1
assert "-h is accepted too" 0 $?

# ---------------------------------------------------------------------------
# 16. Done-when, on the real corpus: stripping one shipped script's unset turns
#     the check red. Synthetic fixtures cannot show that the guard still works
#     against 300-odd real files.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/work"
cp -R "$REPO_ROOT/scripts" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/tests" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/githooks" "$tmp/work/" || exit 1
/bin/bash "$CHECKER" "$tmp/work" >/dev/null 2>&1
assert "the copied real tree is clean" 0 $?

victim="$tmp/work/scripts/spec-anchor.sh"
if [ ! -f "$victim" ]; then
  echo "FAIL: expected a real cd-resolving script at scripts/spec-anchor.sh" >&2
  failures=$((failures + 1))
else
  grep -v '^unset CDPATH' "$victim" >"$victim.new" && mv "$victim.new" "$victim"
  out="$(/bin/bash "$CHECKER" "$tmp/work" 2>&1)"
  assert "removing a real script's unset turns the check red" 1 $?
  assert_contains "the red run names the real script" "$out" "scripts/spec-anchor.sh"
  cp "$REPO_ROOT/scripts/spec-anchor.sh" "$victim"
fi

# ---------------------------------------------------------------------------
# 17. The convention applied to this task's own guard. check-cdpath.sh derives
#     its root through a cd substitution, so it gets the CDPATH=. regression
#     test its --help prescribes.
#
#     The decoy is a complete, clean scope tree placed FIRST in CDPATH, and the
#     tree under test holds an offender. A guard whose root derivation survives
#     CDPATH scans the tree under test and goes red naming the offender; one
#     that resolves through the decoy scans the wrong tree and reports clean.
#     Asserting the offender by name is what makes the two outcomes
#     distinguishable — a bare exit-0 assertion passes in both.
# ---------------------------------------------------------------------------
make_root "$tmp/decoy"
write_script "$tmp/decoy/scripts/innocuous.sh" unset 'echo decoy'
write_script "$tmp/work/scripts/planted-offender.sh" bare 'root="$(cd .. && pwd)"'
out="$(cd "$tmp/work" && CDPATH="$tmp/decoy:." /bin/bash scripts/check-cdpath.sh 2>&1)"
assert "under CDPATH the guard resolves its own root correctly" 1 $?
assert_contains "it scanned the real tree, not the decoy" "$out" "scripts/planted-offender.sh"
assert_not_contains "it did not scan the decoy" "$out" "innocuous.sh"

# ---------------------------------------------------------------------------
# 18. The guard is wired into the `check` aggregate, so a red run is reachable
#     from `mise run check` rather than only by direct invocation.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks\."check:cdpath"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:cdpath is defined as a mise task"
else
  echo "FAIL: mise.toml defines no check:cdpath task" >&2
  failures=$((failures + 1))
fi
if grep -q '"check:cdpath",' "$REPO_ROOT/mise.toml"; then
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
