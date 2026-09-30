#!/bin/bash
# Tests for the machine-wide ticket pool in scripts/run-tests.sh: every run on
# the host together executes at most the pool's capacity of test files at
# once, a killed runner's tickets are reclaimed, an unusable pool degrades to
# one warning and an unpooled run, waiting is kept out of the per-file time,
# and a runner nested inside a pooled test file runs unpooled.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"
MARK=PLANWRIGHT_TEST_IN_POOLED_FILE

# This file itself runs under the suite's pooled runner, which marks its
# environment; the mark would make every run below unpooled.
unset "$MARK"
unset PLANWRIGHT_TEST_SLOTS PLANWRIGHT_TEST_JOBS PLANWRIGHT_TEST_FORCE_SERIAL

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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-pool.XXXXXX")" || exit 1
tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"

cores="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || true)"

# make_suite <dir> <count> <events-file> [<seconds>] — <count> fixture files
# that append a start and an end event around a sleep. An append of one short
# line is atomic, so the file's order is the order the events happened in, and
# each file's events sit inside the time it held its ticket.
make_suite() {
  mkdir -p "$1"
  ms_i=1
  while [ "$ms_i" -le "$2" ]; do
    cat >"$1/test-f$ms_i.sh" <<EOF
#!/bin/bash
echo "S" >>"$3"
sleep ${4:-0.4}
echo "E" >>"$3"
EOF
    ms_i=$((ms_i + 1))
  done
}

# max_depth <events-file> — the most files executing at any one instant.
max_depth() {
  awk '$1 == "S" { d++; if (d > m) m = d } $1 == "E" { d-- } END { print m + 0 }' "$1"
}

# ---------------------------------------------------------------------------
# 1. Two concurrent runs share one bound, and reach it.
# ---------------------------------------------------------------------------
ev="$tmp/ev1"
make_suite "$tmp/s1a" 4 "$ev"
make_suite "$tmp/s1b" 4 "$ev"
PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s1a" >"$tmp/o1a" 2>&1 &
p1=$!
PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s1b" >"$tmp/o1b" 2>&1
rc_b=$?
wait "$p1"
rc_a=$?
assert_exit "concurrent pooled run A passes" 0 "$rc_a"
assert_exit "concurrent pooled run B passes" 0 "$rc_b"
d="$(max_depth "$ev")"
if [ "$d" -le 2 ]; then pass "two runs at capacity 2 never execute more than 2 files ($d)"; else fail "two runs at capacity 2 executed $d files at once"; fi
if [ "$d" -eq 2 ]; then pass "two runs at capacity 2 reach 2 files at once"; else fail "two runs at capacity 2 never reached 2 files at once ($d)"; fi
assert_contains "the run header names the pool capacity" "pool 2 slots" "$(cat "$tmp/o1a")"
left="$(find "$tmp/pool" -name 'slot-*' 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "every ticket is returned when the runs finish" 0 "$left"

# Negative control: the same two runs with the pool bypassed (the nested mark)
# overlap past the bound, so the fixture can see an overshoot.
ev="$tmp/ev1n"
rm -rf "$tmp/s1a" "$tmp/s1b"
make_suite "$tmp/s1a" 4 "$ev"
make_suite "$tmp/s1b" 4 "$ev"
env "$MARK=1" PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s1a" >/dev/null 2>&1 &
p1=$!
env "$MARK=1" PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s1b" >/dev/null 2>&1
wait "$p1"
d="$(max_depth "$ev")"
if [ "$d" -gt 2 ]; then pass "negative control: unpooled runs overlap past the bound ($d)"; else fail "negative control: unpooled runs stayed within 2 ($d); the fixture cannot see an overshoot"; fi

# ---------------------------------------------------------------------------
# 2. Runs that disagree on capacity are bounded by the largest value in use.
# ---------------------------------------------------------------------------
ev="$tmp/ev2"
make_suite "$tmp/s2a" 4 "$ev"
make_suite "$tmp/s2b" 4 "$ev"
PLANWRIGHT_TEST_SLOTS=1 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s2a" >/dev/null 2>&1 &
p1=$!
PLANWRIGHT_TEST_SLOTS=3 PLANWRIGHT_TEST_JOBS=4 /bin/bash "$RUNNER" "$tmp/s2b" >/dev/null 2>&1
wait "$p1"
d="$(max_depth "$ev")"
if [ "$d" -le 3 ]; then pass "capacities 1 and 3 together never exceed 3 ($d)"; else fail "capacities 1 and 3 together executed $d files at once"; fi

# ---------------------------------------------------------------------------
# 3. Capacity: the core count by default, PLANWRIGHT_TEST_SLOTS when set, and
#    PLANWRIGHT_TEST_JOBS still caps one run beneath it.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/one"
printf '#!/bin/bash\nexit 0\n' >"$tmp/one/test-one.sh"
out="$(/bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a default-capacity run passes" 0 $?
assert_contains "the default capacity is the probed core count" "pool $cores slots" "$out"
assert_contains "the report header records the capacity" "pool=$cores" "$(head -n 1 "$tmp/one/.timing-report.tsv")"
out="$(PLANWRIGHT_TEST_SLOTS=5 /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_contains "PLANWRIGHT_TEST_SLOTS sets the capacity" "pool 5 slots" "$out"

ev="$tmp/ev3"
make_suite "$tmp/s3" 4 "$ev" 0.3
PLANWRIGHT_TEST_SLOTS=4 PLANWRIGHT_TEST_JOBS=1 /bin/bash "$RUNNER" "$tmp/s3" >/dev/null 2>&1
assert_exit "a jobs=1 run under capacity 4 passes" 0 $?
d="$(max_depth "$ev")"
if [ "$d" -le 1 ]; then pass "PLANWRIGHT_TEST_JOBS below the capacity caps the run ($d)"; else fail "a jobs=1 run executed $d files at once"; fi

for bad in banana 0 99999999999999999999; do
  out="$(PLANWRIGHT_TEST_SLOTS="$bad" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
  assert_exit "a malformed capacity ($bad) still passes" 0 $?
  n="$(count_lines 'PLANWRIGHT_TEST_SLOTS' "$out")"
  if [ "$n" -eq 1 ]; then pass "a malformed capacity ($bad) warns once"; else fail "a malformed capacity ($bad) warned $n times: $out"; fi
done
out="$(PLANWRIGHT_TEST_SLOTS=banana /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_contains "a non-numeric capacity takes the job count's fallback" "pool 4 slots" "$out"
if [ "$cores" = 4 ]; then
  pass "fallback-versus-core-count distinction skipped (this host has 4 cores)"
else
  assert_not_contains "the fallback is not the core count" "pool $cores slots" "$out"
fi
out="$(PLANWRIGHT_TEST_SLOTS=0 /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_contains "a zero capacity is clamped to 1" "pool 1 slots" "$out"

# ---------------------------------------------------------------------------
# 4. A runner killed mid-file leaves tickets the next run reclaims.
# ---------------------------------------------------------------------------
kpool="$tmp/kpool"
mkdir -p "$tmp/hang" "$tmp/beacons"
for n in 1 2; do
  cat >"$tmp/hang/test-hang$n.sh" <<EOF
#!/bin/bash
echo "\$PPID \$\$" >"$tmp/beacons/$n"
sleep 60
EOF
done
PLANWRIGHT_TEST_SLOT_DIR="$kpool" PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=2 \
  /bin/bash "$RUNNER" "$tmp/hang" >/dev/null 2>&1 &
victim=$!
i=0
while [ "$i" -lt 150 ] && { [ ! -s "$tmp/beacons/1" ] || [ ! -s "$tmp/beacons/2" ]; }; do
  sleep 0.1
  i=$((i + 1))
done
held="$(find "$kpool" -name 'slot-*' -type l 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "the killed run held both tickets while its files ran" 2 "$held"
{
  kill -9 "$victim"
  for n in 1 2; do
    # The worker holding the ticket, then the test file it was running.
    read -r w t <"$tmp/beacons/$n" && kill -9 "$w" "$t"
  done
  wait "$victim"
} 2>/dev/null
held="$(find "$kpool" -name 'slot-*' -type l 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "the killed run's tickets outlive it" 2 "$held"
mkdir -p "$tmp/overlap" "$tmp/sync"
for pair in one:two two:one; do
  me="${pair%%:*}"
  peer="${pair##*:}"
  cat >"$tmp/overlap/test-$me.sh" <<EOF
#!/bin/bash
: >"$tmp/sync/$me.here"
i=0
while [ \$i -lt 80 ]; do
  [ -e "$tmp/sync/$peer.here" ] && exit 0
  sleep 0.25
  i=\$((i + 1))
done
exit 1
EOF
done
PLANWRIGHT_TEST_SLOT_DIR="$kpool" PLANWRIGHT_TEST_SLOTS=2 PLANWRIGHT_TEST_JOBS=2 \
  /bin/bash "$RUNNER" "$tmp/overlap" >"$tmp/o4" 2>&1
assert_exit "the next run reclaims both dead tickets and runs at full concurrency" 0 $?
left="$(find "$kpool" -name 'slot-*' -type l 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "the killed run's tickets are cleared" 0 "$left"

# ---------------------------------------------------------------------------
# 5. No fleet, no plugin, no config: the pool resolves under the home state
#    directory, created owner-only.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/home"
out="$(env -u PLANWRIGHT_TEST_SLOT_DIR -u XDG_STATE_HOME -u CLAUDE_PLUGIN_DATA \
  -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_STATE_HOME HOME="$tmp/home" \
  /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a run with nothing installed or configured passes" 0 $?
home_pool="$tmp/home/.local/state/planwright/test-slots"
assert_not_contains "the home pool is used without a warning" "WARNING" "$out"
if [ -d "$home_pool" ] && [ ! -L "$home_pool" ]; then pass "the pool is created under the home state directory"; else fail "no pool directory at $home_pool"; fi
# shellcheck disable=SC2012 # one known path; the mode string is the point
perms="$(ls -ld "$home_pool" 2>/dev/null | cut -c1-10)"
if [ "$perms" = drwx------ ]; then pass "a fresh pool directory is owner-only"; else fail "fresh pool directory mode is '$perms'"; fi
out="$(env -u PLANWRIGHT_TEST_SLOT_DIR XDG_STATE_HOME="$tmp/xdg" HOME="$tmp/home" \
  /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a run under XDG_STATE_HOME passes" 0 $?
if [ -d "$tmp/xdg/planwright/test-slots" ]; then pass "XDG_STATE_HOME places the pool"; else fail "no pool under XDG_STATE_HOME"; fi

# ---------------------------------------------------------------------------
# 6. A hostile or unusable pool path: one warning naming the cause, an
#    unpooled run, and the suite's own verdict.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/real-pool"
ln -s "$tmp/real-pool" "$tmp/link-pool"
out="$(PLANWRIGHT_TEST_SLOT_DIR="$tmp/link-pool" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a symbolic-link pool path still passes" 0 $?
n="$(count_lines 'WARNING' "$out")"
if [ "$n" -eq 1 ]; then pass "a symbolic-link pool path warns once"; else fail "a symbolic-link pool path warned $n times: $out"; fi
assert_contains "the symbolic-link warning names the cause" "symbolic link" "$out"
assert_contains "the symbolic-link run is unpooled" "pool=off" "$(head -n 1 "$tmp/one/.timing-report.tsv")"
out="$(PLANWRIGHT_TEST_SLOT_DIR="$tmp/link-pool/" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_contains "a trailing slash does not get a link past the refusal" "symbolic link" "$out"
out="$(PLANWRIGHT_TEST_SLOT_DIR="$tmp/link-pool/." /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_contains "a trailing '/.' does not get a link past the refusal" "must not end in" "$out"
assert_contains "the trailing-'/.' run is unpooled" "pool=off" "$(head -n 1 "$tmp/one/.timing-report.tsv")"

# A value quoted in a warning loses its control bytes, the C1 range included:
# 0x9B alone is a terminal escape introducer.
out="$(PLANWRIGHT_TEST_SLOTS="$(printf 'x\2335m')" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
if printf '%s' "$out" | LC_ALL=C grep -q "$(printf '\233')"; then
  fail "a C1 control byte reached the warning"
else
  pass "a C1 control byte is stripped from the warning"
fi
left="$(find "$tmp/real-pool" -name 'slot-*' 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "nothing is written through the link" 0 "$left"

# Foreign ownership, through the ownership check's probe: `id -u` is what the
# owner is compared against, so a shim answering another uid is a directory
# owned by somebody else.
mkdir -p "$tmp/idshim" "$tmp/foreign-pool"
cat >"$tmp/idshim/id" <<'EOF2'
#!/bin/sh
if [ "${1:-}" = -u ]; then echo 4242424; else exec /usr/bin/id "$@"; fi
EOF2
chmod +x "$tmp/idshim/id"
out="$(PATH="$tmp/idshim:$PATH" PLANWRIGHT_TEST_SLOT_DIR="$tmp/foreign-pool" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a foreign-owned pool still passes" 0 $?
n="$(count_lines 'WARNING' "$out")"
if [ "$n" -eq 1 ]; then pass "a foreign-owned pool warns once"; else fail "a foreign-owned pool warned $n times: $out"; fi
assert_contains "the foreign-owner warning names the cause" "not owned by" "$out"
assert_contains "the foreign-owned run is unpooled" "pool=off" "$(head -n 1 "$tmp/one/.timing-report.tsv")"

# The suite's own verdict survives the fallback: a failing file still fails.
mkdir -p "$tmp/failing"
printf '#!/bin/bash\nexit 3\n' >"$tmp/failing/test-bad.sh"
PLANWRIGHT_TEST_SLOT_DIR="$tmp/link-pool" /bin/bash "$RUNNER" "$tmp/failing" >/dev/null 2>&1
assert_exit "an unpooled fallback run keeps a failing verdict" 1 $?

out="$(PLANWRIGHT_TEST_SLOT_DIR="relative/pool" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
assert_exit "a relative pool path still passes" 0 $?
assert_contains "a relative pool path is refused with a warning" "absolute" "$out"
assert_contains "the relative-path run is unpooled" "pool=off" "$(head -n 1 "$tmp/one/.timing-report.tsv")"

# A lock-library error on a ticket (here a regular file squatting a ticket
# path) sends the file unpooled, and the run says so once.
mkdir -p "$tmp/squat-pool" "$tmp/three"
chmod 700 "$tmp/squat-pool"
: >"$tmp/squat-pool/slot-1"
for n in 1 2 3; do printf '#!/bin/bash\nexit 0\n' >"$tmp/three/test-t$n.sh"; done
out="$(PLANWRIGHT_TEST_SLOT_DIR="$tmp/squat-pool" PLANWRIGHT_TEST_SLOTS=1 /bin/bash "$RUNNER" "$tmp/three" 2>&1)"
assert_exit "a lock-library error still passes" 0 $?
n="$(count_lines 'WARNING' "$out")"
if [ "$n" -eq 1 ]; then pass "a lock-library error warns once"; else fail "a lock-library error warned $n times: $out"; fi
assert_contains "the lock-library warning names the cause" "not a lock symlink" "$out"
assert_contains "the lock-library warning counts the unpooled files" "3 file(s) ran unpooled" "$out"

if [ "$(id -u)" -eq 0 ]; then
  pass "unwritable-pool case skipped (running as root)"
else
  mkdir -p "$tmp/ro-pool"
  chmod 500 "$tmp/ro-pool"
  out="$(PLANWRIGHT_TEST_SLOT_DIR="$tmp/ro-pool" /bin/bash "$RUNNER" "$tmp/one" 2>&1)"
  assert_exit "an unwritable pool still passes" 0 $?
  n="$(count_lines 'WARNING' "$out")"
  if [ "$n" -eq 1 ]; then pass "an unwritable pool warns once"; else fail "an unwritable pool warned $n times: $out"; fi
  assert_contains "the unwritable warning names the cause" "not writable" "$out"
  assert_contains "the unwritable run is unpooled" "pool=off" "$(head -n 1 "$tmp/one/.timing-report.tsv")"
  chmod 700 "$tmp/ro-pool"
fi

# ---------------------------------------------------------------------------
# 7. Waiting is not test time: a file that waits on a held ticket reports the
#    wait separately, and check:test-time reads the execution time only.
# ---------------------------------------------------------------------------
wpool="$tmp/wpool"
mkdir -p "$wpool" "$tmp/quick"
chmod 700 "$wpool"
printf '#!/bin/bash\nexit 0\n' >"$tmp/quick/test-quick.sh"
# A live holder of the only ticket for a known interval.
LIB="$REPO_ROOT/scripts/lock-lib.sh" SLOT="$wpool/slot-1" /bin/sh -c \
  '. "$LIB"; pw_lock_trap_install; pw_lock_acquire "$SLOT" || exit 1; sleep 2' &
holder=$!
i=0
while [ "$i" -lt 100 ] && [ ! -L "$wpool/slot-1" ]; do
  sleep 0.05
  i=$((i + 1))
done
PLANWRIGHT_TEST_SLOT_DIR="$wpool" PLANWRIGHT_TEST_SLOTS=1 /bin/bash "$RUNNER" "$tmp/quick" >"$tmp/o7" 2>&1
assert_exit "a file that waited for its ticket passes" 0 $?
wait "$holder"
rep="$tmp/quick/.timing-report.tsv"
assert_contains "the report is version 2" "planwright-test-timing	2	" "$(head -n 1 "$rep")"
exec_t="$(awk -F'\t' '$1 == "file" && $2 == "test-quick.sh" { print $3 }' "$rep")"
wait_t="$(awk -F'\t' '$1 == "file" && $2 == "test-quick.sh" { print $4 }' "$rep")"
if awk -v w="$wait_t" 'BEGIN { exit !(w != "" && w >= 1.0) }'; then pass "the wait field records the wait ($wait_t)"; else fail "the wait field did not record the wait: '$wait_t'"; fi
if awk -v e="$exec_t" 'BEGIN { exit !(e != "" && e < 1.0) }'; then pass "the execution time excludes the wait ($exec_t)"; else fail "the execution time includes the wait: '$exec_t'"; fi
printf -- '---\nper_file_seconds: 1\nsuite_total_seconds: 600\n' >"$tmp/budget.yml"
out="$(/bin/bash "$REPO_ROOT/scripts/check-test-time.sh" --mode ci --suite "$tmp/quick" \
  --report "$rep" --budget "$tmp/budget.yml" 2>&1)"
assert_exit "check:test-time reads the execution time, not the wait" 0 $?

# ---------------------------------------------------------------------------
# 8. A runner nested inside a pooled file runs unpooled, silently, and never
#    waits on the ticket its ancestor holds.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/inner" "$tmp/outer"
printf '#!/bin/bash\nexit 0\n' >"$tmp/inner/test-inner.sh"
cat >"$tmp/outer/test-nest.sh" <<EOF
#!/bin/bash
PLANWRIGHT_TEST_TIMING_REPORT="$tmp/inner-report.tsv" /bin/bash "$RUNNER" "$tmp/inner" >"$tmp/inner-out" 2>&1
EOF
PLANWRIGHT_TEST_SLOT_DIR="$tmp/npool" PLANWRIGHT_TEST_SLOTS=1 /bin/bash "$RUNNER" "$tmp/outer" >"$tmp/o8" 2>&1 &
outer=$!
i=0
while [ "$i" -lt 300 ] && kill -0 "$outer" 2>/dev/null; do
  sleep 0.1
  i=$((i + 1))
done
if kill -0 "$outer" 2>/dev/null; then
  kill -9 "$outer" 2>/dev/null
  fail "the outer run hung on a nested runner"
else
  wait "$outer"
  assert_exit "the outer run finishes with its nested runner" 0 $?
fi
inner_out="$(cat "$tmp/inner-out" 2>/dev/null)"
assert_contains "the nested run completes" "all 1 test files passed" "$inner_out"
assert_not_contains "the nested run prints no pool warning" "WARNING" "$inner_out"
assert_contains "the nested run is unpooled" "pool=off" "$(head -n 1 "$tmp/inner-report.tsv" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 9. A signal to the run stops it and returns its ticket, in either mode. The
#    run gets its own process group (job control), as a terminal's Ctrl-C
#    would reach it; a background job would otherwise start with SIGINT
#    ignored.
# ---------------------------------------------------------------------------
# signal_case <serial:0|1> <SIG>
signal_case() {
  sc_dir="$tmp/sig-$1-$2"
  mkdir -p "$sc_dir/suite"
  for n in 1 2; do
    printf '#!/bin/bash\n: >"%s/started-%s"\nsleep 5\n' "$sc_dir" "$n" >"$sc_dir/suite/test-i$n.sh"
  done
  set -m
  PLANWRIGHT_TEST_SLOT_DIR="$sc_dir/pool" PLANWRIGHT_TEST_SLOTS=1 PLANWRIGHT_TEST_JOBS=1 \
    PLANWRIGHT_TEST_FORCE_SERIAL="$1" /bin/bash "$RUNNER" "$sc_dir/suite" >"$sc_dir/out" 2>&1 &
  sc_run=$!
  set +m
  sc_i=0
  while [ "$sc_i" -lt 150 ] && [ ! -e "$sc_dir/started-1" ]; do
    sleep 0.1
    sc_i=$((sc_i + 1))
  done
  kill -s "$2" -- "-$sc_run" 2>/dev/null
  wait "$sc_run" 2>/dev/null
  sc_rc=$?
  if [ "$sc_rc" -ne 0 ]; then pass "SIG$2 fails a pooled run (serial=$1, exit $sc_rc)"; else fail "SIG$2 left a pooled run exiting 0 (serial=$1)"; fi
  if [ ! -e "$sc_dir/started-2" ]; then pass "SIG$2 stops a pooled run (serial=$1)"; else fail "a pooled run went on to the next file after SIG$2 (serial=$1)"; fi
  # The parent can die before its worker's release finishes; a leaked ticket
  # is one still standing after that settles.
  sc_i=0
  while :; do
    sc_left="$(find "$sc_dir/pool" -name 'slot-*' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$sc_left" -ne 0 ] && [ "$sc_i" -lt 50 ] || break
    sleep 0.1
    sc_i=$((sc_i + 1))
  done
  assert_exit "SIG$2 returns the worker's ticket (serial=$1)" 0 "$sc_left"
}
signal_case 1 INT
signal_case 0 INT
signal_case 1 TERM
signal_case 1 HUP

# ---------------------------------------------------------------------------
# 10. Built on the shared lock primitive: the retired-mkdir guard reports the
#    runner clean.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/scan/scripts" "$tmp/scan/tests" "$tmp/scan/githooks"
cp "$RUNNER" "$tmp/scan/scripts/run-tests.sh"
out="$(/bin/bash "$REPO_ROOT/scripts/check-lock-primitive.sh" "$tmp/scan" 2>&1)"
assert_exit "check-lock-primitive reports the runner clean" 0 $?
if grep -q '^[[:space:]]*# shellcheck source=scripts/lock-lib\.sh$' "$RUNNER"; then pass "the runner sources the shared lock library"; else fail "the runner does not source scripts/lock-lib.sh"; fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all run-tests pool tests passed"
