#!/bin/bash
# Tests for the per-file deadline in scripts/run-tests.sh (REQ-D1.4): a file
# still running past PLANWRIGHT_TEST_FILE_DEADLINE is ended, reported failed
# naming the file and the deadline, and its ticket returned; a file inside the
# deadline is unaffected; a malformed value or 0 warns once and uses the
# default; a host with no usable timeout or gtimeout warns once and runs files
# unbounded; gtimeout alone bounds them; a signal to a worker reaches its
# bounded file; a nested runner inherits the variable.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"
# shellcheck source=tests/lib/no-timeout-path.sh
. "$REPO_ROOT/tests/lib/no-timeout-path.sh"

# This file runs under the suite's own runner, whose mark and knobs would
# otherwise reach every run below.
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
# count_lines <pattern> <text> — lines of <text> containing <pattern>.
count_lines() {
  printf '%s\n' "$2" | grep -c -- "$1"
}
# gone_within <pid> <tenths> — 0 once <pid> has exited, 1 if still alive after
# <tenths> tenths of a second.
gone_within() {
  gw_n=0
  while kill -0 "$1" 2>/dev/null; do
    [ "$gw_n" -lt "$2" ] || return 1
    sleep 0.1
    gw_n=$((gw_n + 1))
  done
  return 0
}
# wait_for_file <path> <tenths> — 0 once <path> is non-empty.
wait_for_file() {
  wf_n=0
  until [ -s "$1" ]; do
    [ "$wf_n" -lt "$2" ] || return 1
    sleep 0.1
    wf_n=$((wf_n + 1))
  done
  return 0
}

# ppid_of <pid> / args_of <pid> — from /proc where it exists, since busybox's
# ps (the Alpine leg) takes no -p; else from ps (macOS has no /proc).
ppid_of() {
  if [ -r "/proc/$1/stat" ]; then
    sed 's/.*) //' "/proc/$1/stat" | awk '{ print $2 }'
  else
    ps -o ppid= -p "$1" | tr -d ' '
  fi
}
args_of() {
  if [ -r "/proc/$1/cmdline" ]; then
    tr '\000' ' ' <"/proc/$1/cmdline"
  else
    ps -o args= -p "$1"
  fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-deadline.XXXXXX")" || exit 1
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"
export PLANWRIGHT_TEST_DURATIONS=""

real_timeout=$(command -v timeout || command -v gtimeout || true)
# busybox's timeout signals the file alone, so what the file started outlives
# it there; the descendant checks below hold only for a process-group timeout.
group_bound=0
if [ -n "$real_timeout" ]; then
  case "$("$real_timeout" --help 2>&1)" in
    *BusyBox*) ;;
    *) group_bound=1 ;;
  esac
fi

# hang_file <path> <dir> — a file that records its shell's pid in <dir>/pid
# and its child's in <dir>/child, then outlives any deadline set here.
hang_file() {
  cat >"$1" <<EOF
#!/bin/bash
echo \$\$ >"$2/pid"
sleep 60 &
echo \$! >"$2/child"
wait
EOF
}
# stubborn_file <path> <dir> — a hung file that notes a TERM in <dir>/termed
# and runs on.
stubborn_file() {
  cat >"$1" <<EOF
#!/bin/bash
echo \$\$ >"$2/pid"
trap ': >"$2/termed"' TERM
sleep 60 &
echo \$! >"$2/child"
while :; do wait; done
EOF
}
quick_file() {
  printf '#!/bin/bash\nexit 0\n' >"$1"
}
# check_hang_gone <label> <dir> — the hung file and, under a process-group
# timeout, its child are gone.
check_hang_gone() {
  if gone_within "$(cat "$2/pid")" 30; then
    pass "$1: the hung file's shell is gone"
  else
    fail "$1: the hung file's shell is gone"
  fi
  if [ "$group_bound" -eq 1 ]; then
    if gone_within "$(cat "$2/child")" 30; then
      pass "$1: the hung file's child is gone"
    else
      fail "$1: the hung file's child is gone"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 1. A hung file is ended at its deadline, named with it, and its ticket is
#    free for the next file: a second run on the one-ticket pool, started
#    once the hung file holds the ticket, gets it at the deadline.
if [ -z "$real_timeout" ]; then
  pass "a hung file is ended at its deadline (skipped: neither timeout nor gtimeout on this host)"
else
  s1="$tmp/s1"
  h1="$tmp/h1"
  mkdir -p "$s1" "$h1" "$tmp/s1q"
  hang_file "$s1/test-a-hang.sh" "$h1"
  quick_file "$tmp/s1q/test-b-quick.sh"
  PLANWRIGHT_TEST_FILE_DEADLINE=6 PLANWRIGHT_TEST_SLOTS=1 \
    PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1.tsv" "$RUNNER" "$s1" >"$tmp/o1" 2>&1 &
  run_a=$!
  if wait_for_file "$h1/child" 100; then
    start=$(date +%s)
    PLANWRIGHT_TEST_FILE_DEADLINE=6 PLANWRIGHT_TEST_SLOTS=1 \
      PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1b.tsv" "$RUNNER" "$tmp/s1q" >"$tmp/o1b" 2>&1
    rc=$?
    took=$(($(date +%s) - start))
    assert_exit "the next file takes the freed ticket and passes" 0 "$rc"
    if [ "$took" -lt 30 ]; then
      pass "the ticket is free at the deadline, not at the file's own end (${took}s)"
    else
      fail "the ticket is free at the deadline, not at the file's own end (${took}s)"
    fi
    waited=$(awk -F'\t' '$1 == "file" { print $4 }' "$tmp/r1b.tsv")
    case "$waited" in
      0.* | '') fail "the next file waited for the hung file's ticket (waited ${waited:-?}s)" ;;
      *) pass "the next file waited for the hung file's ticket (${waited}s)" ;;
    esac
  else
    fail "the hung file started"
  fi
  wait "$run_a"
  assert_exit "a hung file fails the run" 1 "$?"
  out=$(cat "$tmp/o1")
  assert_contains "the hung file is reported failed" "=== FAIL: test-a-hang.sh" "$out"
  assert_contains "the failure names the file and the deadline" \
    "run-tests: test-a-hang.sh ran past its 6s deadline (PLANWRIGHT_TEST_FILE_DEADLINE) and was ended" "$out"
  check_hang_gone "deadline" "$h1"
fi

# ---------------------------------------------------------------------------
# 2. A file finishing inside the deadline is unaffected, a bounded file starts
#    with INT at its default as an unbounded one does, and a file that exits
#    124 on its own is a plain failure, not a deadline.
s2="$tmp/s2"
mkdir -p "$s2"
printf '#!/bin/bash\nsleep 0.2\necho inside\n' >"$s2/test-inside.sh"
# A child that signals itself dies of it instead of sleeping on.
cat >"$s2/test-int-default.sh" <<'EOF'
#!/bin/bash
sh -c 'kill -INT $$; sleep 1; exit 0'
[ "$?" -ne 0 ]
EOF
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=5 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2.tsv" "$RUNNER" "$s2" 2>&1)
assert_exit "files inside their deadline pass, INT at its default" 0 "$?"
[ -z "$real_timeout" ] || assert_contains "the files ran bounded" "deadline 5s per file" "$out"
assert_not_contains "a file inside its deadline draws no deadline message" "ran past its" "$out"
# A wall clock that jumps past the deadline while a passing file runs (a
# suspend, an NTP step) leaves timeout's alarm unfired and the file passed.
# The shim steps only the nanosecond reading, the runner's clock where date
# has one.
if [ -z "$real_timeout" ]; then
  pass "a clock jump keeps a file passed (skipped: no timeout or gtimeout on this host)"
elif ! date +%N | grep -q '^[0-9]\{9\}$'; then
  pass "a clock jump keeps a file passed (skipped: date has no nanoseconds here)"
else
  jump="$tmp/jump"
  mkdir -p "$jump/bin" "$jump/suite"
  cat >"$jump/bin/date" <<EOF
#!/bin/sh
out=\$($(command -v date) "\$@") || exit
if [ -e "$jump/stepped" ] && [ "\$1" = '+%s %N' ]; then
  out="\$((\${out%% *} + 2000)) \${out#* }"
fi
printf '%s\n' "\$out"
EOF
  chmod +x "$jump/bin/date"
  printf '#!/bin/bash\n: >"%s"\n' "$jump/stepped" >"$jump/suite/test-jumped.sh"
  out=$(PATH="$jump/bin:$PATH" PLANWRIGHT_TEST_FILE_DEADLINE=5 \
    PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2j.tsv" "$RUNNER" "$jump/suite" 2>&1)
  assert_exit "a clock jump does not fail a passing file" 0 "$?"
  assert_contains "a clock jump leaves the file passed" "ok: test-jumped.sh" "$out"
fi
printf '#!/bin/bash\nexit 124\n' >"$s2/test-own-124.sh"
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=5 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2b.tsv" "$RUNNER" "$s2" 2>&1)
assert_exit "a file exiting 124 itself fails" 1 "$?"
assert_contains "a file exiting 124 itself is reported failed" "=== FAIL: test-own-124.sh" "$out"
assert_not_contains "a file exiting 124 itself is not called a deadline" "ran past its" "$out"

# ---------------------------------------------------------------------------
# 3. Unset is the default with no warning; a malformed value and 0 each warn
#    once, naming the default, and use it. The header shows the value only
#    where files are bounded.
if [ -n "$real_timeout" ]; then
  shows() { printf 'deadline %ss per file' "$1"; }
else
  shows() { printf 'no per-file deadline'; }
fi
s3="$tmp/s3"
mkdir -p "$s3"
quick_file "$s3/test-1.sh"
quick_file "$s3/test-2.sh"
out=$("$RUNNER" "$s3" 2>&1)
assert_exit "unset: the run passes" 0 "$?"
assert_contains "unset: the default is used" "$(shows 900)" "$out"
assert_not_contains "unset: no deadline warning" "PLANWRIGHT_TEST_FILE_DEADLINE" "$out"
for bad in 0 abc -5 1.5 '' 12x 0000 1234567890; do
  out=$(PLANWRIGHT_TEST_FILE_DEADLINE="$bad" "$RUNNER" "$s3" 2>&1)
  assert_exit "'$bad': the run passes" 0 "$?"
  n=$(count_lines "WARNING PLANWRIGHT_TEST_FILE_DEADLINE" "$out")
  if [ "$n" -eq 1 ]; then
    pass "'$bad': warns exactly once"
  else
    fail "'$bad': warns exactly once (got $n: $out)"
  fi
  assert_contains "'$bad': the warning names the default" "using the default of 900" "$out"
  assert_contains "'$bad': the default is used" "$(shows 900)" "$out"
done
for good in 007:7 999999999:999999999; do
  out=$(PLANWRIGHT_TEST_FILE_DEADLINE="${good%%:*}" "$RUNNER" "$s3" 2>&1)
  assert_contains "'${good%%:*}' is read as ${good#*:}" "$(shows "${good#*:}")" "$out"
  assert_not_contains "'${good%%:*}' draws no warning" "WARNING PLANWRIGHT_TEST_FILE_DEADLINE" "$out"
done

# ---------------------------------------------------------------------------
# 4. Fixture hosts: a PATH without either bounder, one whose timeout refuses
#    -k (an old busybox), and one with only gtimeout (Homebrew's coreutils).
farm=$(no_timeout_path "$tmp/notimeout")
s4="$tmp/s4"
mkdir -p "$s4"
printf '#!/bin/bash\nsleep 2\n' >"$s4/test-slow-1.sh"
printf '#!/bin/bash\nsleep 2\n' >"$s4/test-slow-2.sh"
no_tool_case() {
  out=$(PATH="$farm" PLANWRIGHT_TEST_FILE_DEADLINE=1 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r4.tsv" \
    "$RUNNER" "$s4" 2>&1)
  assert_exit "$1: files past the deadline still pass" 0 "$?"
  n=$(count_lines "WARNING no usable timeout(1) or gtimeout" "$out")
  if [ "$n" -eq 1 ]; then
    pass "$1: warns exactly once"
  else
    fail "$1: warns exactly once (got $n: $out)"
  fi
  assert_contains "$1: the header says files run unbounded" "no per-file deadline" "$out"
}
no_tool_case "no bounding tool"
# shellcheck disable=SC2016 # $1 and $@ belong to the stub
printf '#!/bin/sh\n[ "$1" = -k ] && exit 125\nexec "$@"\n' >"$farm/timeout"
chmod +x "$farm/timeout"
no_tool_case "a timeout without -k"
rm -f "$farm/timeout"

if [ -z "$real_timeout" ]; then
  pass "gtimeout alone bounds files (skipped: neither timeout nor gtimeout on this host)"
else
  witness="$tmp/gtimeout-used"
  {
    echo '#!/bin/sh'
    printf '%s\n' "echo x >>\"$witness\""
    echo "exec \"$real_timeout\" \"\$@\""
  } >"$farm/gtimeout"
  chmod +x "$farm/gtimeout"
  s5="$tmp/s5"
  h5="$tmp/h5"
  mkdir -p "$s5" "$h5"
  hang_file "$s5/test-hang.sh" "$h5"
  out=$(PATH="$farm" PLANWRIGHT_TEST_FILE_DEADLINE=1 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r5.tsv" \
    "$RUNNER" "$s5" 2>&1)
  assert_exit "gtimeout alone: the hung file fails the run" 1 "$?"
  assert_contains "gtimeout alone: the hung file is ended at its deadline" \
    "test-hang.sh ran past its 1s deadline" "$out"
  # One mark is the runner's probe; the second is the file's own bound.
  n=$(grep -c x "$witness" 2>/dev/null)
  if [ "${n:-0}" -ge 2 ]; then
    pass "gtimeout alone: the file ran under gtimeout"
  else
    fail "gtimeout alone: the file ran under gtimeout (${n:-0} use(s))"
  fi
  check_hang_gone "gtimeout alone" "$h5"
fi

# ---------------------------------------------------------------------------
# 5. A signal to a worker reaches its bounded file as TERM, pooled and
#    parallel, and serial and unpooled, where the run must not then go on to
#    pass; a file that outlives that TERM is killed ten seconds later.
if [ -z "$real_timeout" ]; then
  pass "a worker passes a signal on (skipped: neither timeout nor gtimeout on this host)"
else
  # signal_case <label> <dir> <signal> <file-kind> [VAR=value...] — start a
  # run on one hung file (hang, or stubborn: it notes a TERM and runs on),
  # send <signal> to the worker holding it, and check the file and the run
  # both end.
  signal_case() {
    sc_label=$1
    sc_dir=$2
    sc_sig=$3
    sc_kind=$4
    shift 4
    mkdir -p "$sc_dir/suite"
    if [ "$sc_kind" = stubborn ]; then
      stubborn_file "$sc_dir/suite/test-hang.sh" "$sc_dir"
    else
      hang_file "$sc_dir/suite/test-hang.sh" "$sc_dir"
    fi
    quick_file "$sc_dir/suite/test-later.sh"
    env "$@" PLANWRIGHT_TEST_FILE_DEADLINE=60 PLANWRIGHT_TEST_JOBS=1 \
      PLANWRIGHT_TEST_TIMING_REPORT="$sc_dir/r.tsv" "$RUNNER" "$sc_dir/suite" >"$sc_dir/out" 2>&1 &
    sc_run=$!
    if ! wait_for_file "$sc_dir/child" 100; then
      fail "$sc_label: the hung file started"
      kill "$sc_run" 2>/dev/null
      wait "$sc_run"
      return
    fi
    # The worker is the nearest ancestor of the file running --run-one: its
    # parent under GNU timeout, the file's own parent under busybox's, which
    # becomes the file.
    sc_worker=""
    sc_p=$(cat "$sc_dir/pid")
    for _ in 1 2 3; do
      sc_p=$(ppid_of "$sc_p")
      [ -n "$sc_p" ] && [ "$sc_p" -gt 1 ] || break
      case "$(args_of "$sc_p")" in
        *xargs*) ;;
        *--run-one*)
          sc_worker=$sc_p
          break
          ;;
      esac
    done
    if [ -n "$sc_worker" ]; then
      kill -s "$sc_sig" "$sc_worker"
    else
      fail "$sc_label: the worker was found"
    fi
    if [ "$sc_kind" = stubborn ]; then
      if gone_within "$(cat "$sc_dir/pid")" 200; then
        pass "$sc_label: the file is killed after the grace"
      else
        fail "$sc_label: the file is killed after the grace"
      fi
      if [ -e "$sc_dir/termed" ]; then
        pass "$sc_label: the file got TERM first"
      else
        fail "$sc_label: the file got TERM first"
      fi
    else
      check_hang_gone "$sc_label" "$sc_dir"
    fi
    if gone_within "$sc_run" 100; then
      pass "$sc_label: the run ends"
    else
      fail "$sc_label: the run ends"
      kill "$sc_run" 2>/dev/null
    fi
    # Whatever the outcome, nothing of the case outlives it.
    kill -s KILL "$(cat "$sc_dir/pid")" "$(cat "$sc_dir/child")" 2>/dev/null
    wait "$sc_run"
    sc_rc=$?
    if [ "$sc_rc" -ne 0 ]; then
      pass "$sc_label: the run does not pass (exit $sc_rc)"
    else
      fail "$sc_label: the run does not pass ($(cat "$sc_dir/out"))"
    fi
  }
  signal_case "pooled worker" "$tmp/sig1" TERM hang
  signal_case "a HUP to a worker" "$tmp/sig3" HUP stubborn
  signal_case "serial unpooled worker" "$tmp/sig2" TERM hang PLANWRIGHT_TEST_FORCE_SERIAL=1 \
    PLANWRIGHT_TEST_IN_POOLED_FILE=1
fi

# ---------------------------------------------------------------------------
# 6. A runner started from inside a test file inherits the variable and
#    bounds its own files by it.
s6="$tmp/s6"
inner="$tmp/s6-inner"
mkdir -p "$s6" "$inner"
cat >"$inner/test-echo.sh" <<EOF
#!/bin/bash
printf '%s\n' "\${PLANWRIGHT_TEST_FILE_DEADLINE-unset}" >"$tmp/inherited"
EOF
cat >"$s6/test-outer.sh" <<EOF
#!/bin/bash
PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r6-inner.tsv" "$RUNNER" "$inner" >"$tmp/inner-out" 2>&1
EOF
out=$(PLANWRIGHT_TEST_FILE_DEADLINE=37 PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r6.tsv" "$RUNNER" "$s6" 2>&1)
assert_exit "nested: the outer run passes" 0 "$?"
assert_contains "nested: the inner file sees the outer value" "37" "$(cat "$tmp/inherited" 2>/dev/null)"
assert_contains "nested: the inner runner bounds its files by it" "$(shows 37)" "$(cat "$tmp/inner-out" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 7. The usage header documents the variable and its default.
header=$(awk 'NR > 1 && !/^#/ { exit } { print }' "$RUNNER")
assert_contains "the usage header names the variable" "PLANWRIGHT_TEST_FILE_DEADLINE" "$header"
assert_contains "the usage header names the default" "default 900" "$header"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all deadline tests passed"
