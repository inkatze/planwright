#!/bin/bash
# Tests for the per-file deadline in scripts/run-tests.sh (REQ-D1.4): a file
# still running past PLANWRIGHT_TEST_FILE_DEADLINE is ended, reported failed
# naming the file and the deadline, and its ticket returned; a file inside the
# deadline is unaffected; a malformed value or 0 warns once and uses the
# default; a host with neither timeout nor gtimeout warns once and runs files
# unbounded; gtimeout alone bounds them; a nested runner inherits the variable.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"

# This file runs under the suite's own runner, whose mark, knobs and handoff
# values would otherwise reach every run below.
unset PLANWRIGHT_TEST_IN_POOLED_FILE PLANWRIGHT_TEST_SLOTS PLANWRIGHT_TEST_JOBS \
  PLANWRIGHT_TEST_FORCE_SERIAL PLANWRIGHT_TEST_TIMING_REPORT \
  PLANWRIGHT_TEST_DURATIONS PLANWRIGHT_TEST_FILE_DEADLINE

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then pass "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (missing '$2'; got: $3)" ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*) fail "$1 (unexpected '$2'; got: $3)" ;;
    *) pass "$1" ;;
  esac
}
count_lines() {
  printf '%s\n' "$2" | grep -c -- "$1"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-deadline.XXXXXX")" || exit 1
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"
export PLANWRIGHT_TEST_DURATIONS=""

real_timeout=$(command -v timeout || command -v gtimeout || true)

# hang_file <path> <pid-file> — a file that records its shell's pid, then
# outlives any deadline these cases set.
hang_file() {
  cat >"$1" <<EOF
#!/bin/bash
echo \$\$ >"$2"
sleep 60
EOF
}
quick_file() {
  printf '#!/bin/bash\nexit 0\n' >"$1"
}

# ---------------------------------------------------------------------------
# 1. A hung file is ended at its deadline, named with it, and its ticket is
#    free for the next file: one ticket, two jobs, the hung file first.
if [ -z "$real_timeout" ]; then
  pass "a hung file is ended at its deadline (skipped: neither timeout nor gtimeout on this host)"
else
  s1="$tmp/s1"
  mkdir -p "$s1"
  hang_file "$s1/test-a-hang.sh" "$tmp/hang.pid"
  quick_file "$s1/test-b-quick.sh"
  start=$(date +%s)
  out=$(PLANWRIGHT_TEST_FILE_DEADLINE=2 PLANWRIGHT_TEST_SLOTS=1 PLANWRIGHT_TEST_JOBS=2 \
    PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1.tsv" "$RUNNER" "$s1" 2>&1)
  rc=$?
  took=$(($(date +%s) - start))
  assert_exit "a hung file fails the run" 1 "$rc"
  assert_contains "the hung file is reported failed" "=== FAIL: test-a-hang.sh" "$out"
  assert_contains "the failure names the file and the deadline" \
    "run-tests: test-a-hang.sh ran past its 2s deadline (PLANWRIGHT_TEST_FILE_DEADLINE) and was ended" "$out"
  assert_contains "the next file takes the freed ticket and passes" "ok: test-b-quick.sh" "$out"
  if [ "$took" -lt 30 ]; then
    pass "the run ends near the deadline, not at the file's own end (${took}s)"
  else
    fail "the run ends near the deadline, not at the file's own end (${took}s)"
  fi
  hang_pid=$(cat "$tmp/hang.pid" 2>/dev/null)
  if [ -n "$hang_pid" ] && kill -0 "$hang_pid" 2>/dev/null; then
    fail "the hung file's process is gone after the run (pid $hang_pid alive)"
  else
    pass "the hung file's process is gone after the run"
  fi
  mkdir -p "$tmp/s1q"
  quick_file "$tmp/s1q/test-c.sh"
  out=$(PLANWRIGHT_TEST_FILE_DEADLINE=2 PLANWRIGHT_TEST_SLOTS=1 \
    PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1b.tsv" "$RUNNER" "$tmp/s1q" 2>&1)
  assert_exit "a later run takes the ended file's ticket" 0 "$?"
fi

# ---------------------------------------------------------------------------
# 2. A file finishing inside the deadline is unaffected, and a file that
#    exits 124 on its own is a plain failure, not a deadline.
s2="$tmp/s2"
mkdir -p "$s2"
printf '#!/bin/bash\nsleep 0.2\necho inside\n' >"$s2/test-inside.sh"
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=5 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2.tsv" "$RUNNER" "$s2" 2>&1)
assert_exit "a file inside its deadline passes" 0 "$?"
assert_not_contains "a file inside its deadline draws no deadline message" "deadline (PLANWRIGHT" "$out"
# A bounded file starts with INT at its default, as an unbounded one does: a
# child that signals itself dies of it instead of sleeping on.
cat >"$s2/test-int-default.sh" <<'EOF'
#!/bin/bash
sh -c 'kill -INT $$; sleep 1; exit 0'
[ "$?" -ne 0 ]
EOF
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=5 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2i.tsv" "$RUNNER" "$s2" 2>&1)
assert_exit "a bounded file's INT is not ignored" 0 "$?"
printf '#!/bin/bash\nexit 124\n' >"$s2/test-own-124.sh"
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=5 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2b.tsv" "$RUNNER" "$s2" 2>&1)
assert_exit "a file exiting 124 itself fails" 1 "$?"
assert_contains "a file exiting 124 itself is reported failed" "=== FAIL: test-own-124.sh" "$out"
assert_not_contains "a file exiting 124 itself is not called a deadline" "ran past its" "$out"

# ---------------------------------------------------------------------------
# 3. Unset is the default with no warning; a malformed value and 0 each warn
#    once, naming the default, and use it.
s3="$tmp/s3"
mkdir -p "$s3"
quick_file "$s3/test-1.sh"
quick_file "$s3/test-2.sh"
quick_file "$s3/test-3.sh"
out=$("$RUNNER" "$s3" 2>&1)
assert_exit "unset: the run passes" 0 "$?"
assert_contains "unset: the header names the default deadline" "deadline 900s per file" "$out"
assert_not_contains "unset: no deadline warning" "PLANWRIGHT_TEST_FILE_DEADLINE" "$out"
for bad in 0 abc -5 1.5 '' 12x 0000 99999999999; do
  out=$(PLANWRIGHT_TEST_FILE_DEADLINE="$bad" "$RUNNER" "$s3" 2>&1)
  rc=$?
  assert_exit "'$bad': the run passes" 0 "$rc"
  n=$(count_lines "WARNING PLANWRIGHT_TEST_FILE_DEADLINE" "$out")
  if [ "$n" -eq 1 ]; then
    pass "'$bad': warns exactly once"
  else
    fail "'$bad': warns exactly once (got $n: $out)"
  fi
  assert_contains "'$bad': the warning names the default" "using the default of 900" "$out"
  assert_contains "'$bad': the default is used" "deadline 900s per file" "$out"
done
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=007 "$RUNNER" "$s3" 2>&1)
assert_contains "leading zeros read as decimal" "deadline 7s per file" "$out"
assert_not_contains "leading zeros draw no warning" "WARNING PLANWRIGHT_TEST_FILE_DEADLINE" "$out"

# ---------------------------------------------------------------------------
# 4. Fixture hosts: a PATH holding every tool but the two bounders, then the
#    same with only gtimeout (the Homebrew coreutils shape).
# One ln per directory, not per tool, which costs seconds on a long PATH; ln
# skips a name already linked, so an earlier directory wins as on the PATH.
farm="$tmp/notimeout"
mkdir -p "$farm"
old_ifs=$IFS
IFS=:
for d in $PATH; do
  [ -d "$d" ] || continue
  set -- "$d"/*
  [ -e "$1" ] || continue
  ln -s "$@" "$farm/" 2>/dev/null || true
done
IFS=$old_ifs
rm -f "$farm/timeout" "$farm/gtimeout"
set --

s4="$tmp/s4"
mkdir -p "$s4"
printf '#!/bin/bash\nsleep 3\n' >"$s4/test-slow-1.sh"
printf '#!/bin/bash\nsleep 3\n' >"$s4/test-slow-2.sh"
out=$(PATH="$farm" PLANWRIGHT_TEST_FILE_DEADLINE=1 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r4.tsv" \
  "$RUNNER" "$s4" 2>&1)
assert_exit "no bounding tool: files past the deadline still pass" 0 "$?"
n=$(count_lines "WARNING neither timeout nor gtimeout" "$out")
if [ "$n" -eq 1 ]; then
  pass "no bounding tool: warns exactly once"
else
  fail "no bounding tool: warns exactly once (got $n: $out)"
fi
assert_contains "no bounding tool: the header says files run unbounded" "no per-file deadline" "$out"

if [ -z "$real_timeout" ]; then
  pass "gtimeout alone bounds files (skipped: neither timeout nor gtimeout on this host)"
else
  witness="$tmp/gtimeout-used"
  {
    echo '#!/bin/sh'
    echo "printf 'x' >>\"$witness\""
    echo "exec \"$real_timeout\" \"\$@\""
  } >"$farm/gtimeout"
  chmod +x "$farm/gtimeout"
  s5="$tmp/s5"
  mkdir -p "$s5"
  hang_file "$s5/test-hang.sh" "$tmp/hang5.pid"
  out=$(PATH="$farm" PLANWRIGHT_TEST_FILE_DEADLINE=1 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r5.tsv" \
    "$RUNNER" "$s5" 2>&1)
  assert_exit "gtimeout alone: the hung file fails the run" 1 "$?"
  assert_contains "gtimeout alone: the hung file is ended at its deadline" \
    "test-hang.sh ran past its 1s deadline" "$out"
  if [ -s "$witness" ]; then
    pass "gtimeout alone: the runner bounded files through gtimeout"
  else
    fail "gtimeout alone: the runner bounded files through gtimeout"
  fi
fi

# ---------------------------------------------------------------------------
# 5. A nested runner (REQ-A1.8's unpooled one) inherits the variable.
s6="$tmp/s6"
inner="$tmp/s6-inner"
mkdir -p "$s6" "$inner"
cat >"$inner/test-echo.sh" <<EOF
#!/bin/bash
printf '%s\n' "\${PLANWRIGHT_TEST_FILE_DEADLINE-unset}" >"$tmp/inherited"
EOF
cat >"$s6/test-outer.sh" <<EOF
#!/bin/bash
PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r6-inner.tsv" "$RUNNER" "$inner"
EOF
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=37 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r6.tsv" "$RUNNER" "$s6" 2>&1)
assert_exit "nested: the outer run passes" 0 "$?"
assert_contains "nested: the inner file sees the outer value" "37" "$(cat "$tmp/inherited" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 6. The usage header documents the variable and its default.
header=$(awk 'NR > 1 && !/^#/ { exit } { print }' "$RUNNER")
assert_contains "the usage header names the variable" "PLANWRIGHT_TEST_FILE_DEADLINE" "$header"
assert_contains "the usage header names the default" "default 900" "$header"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all deadline tests passed"
