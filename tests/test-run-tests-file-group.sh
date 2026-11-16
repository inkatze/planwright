#!/bin/bash
# Tests that scripts/run-tests.sh gives every test file a process group of its
# own on a host with no timeout(1) or gtimeout (macOS); why is in its header.
#
#   g1: with no bounder, a file leads its own process group.
#   g2: a runner in a fresh session survives a file that orphans its own
#       group while holding a stopped child, and the file passes.
#   g3: with neither a bounder nor perl, files still run, in the worker's
#       group.
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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-file-group.XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT
# A pool of its own: the machine-wide one is full while the outer suite runs,
# and every run below would wait there for a ticket.
export PLANWRIGHT_TEST_SLOT_DIR="$tmp/pool"

# Every file reads its group from /proc where it exists, since busybox's ps
# takes no -p; else from ps (macOS has no /proc).
# shellcheck disable=SC2016 # expanded by the fixture file
pgid_snippet='pgid_of() {
  if [ -r "/proc/$1/stat" ]; then
    sed "s/.*) //" "/proc/$1/stat" | awk "{ print \$3 }"
  else
    ps -o pgid= -p "$1" | tr -d " "
  fi
}'

# group_file <path> <test> — a file that fails unless its group passes <test>
# against its own pid ("=" leads its group, "!=" does not).
group_file() {
  {
    echo '#!/bin/bash'
    printf '%s\n' "$pgid_snippet"
    # shellcheck disable=SC2016 # expanded by the fixture file
    printf 'g=$(pgid_of $$); [ "$g" %s "$$" ] || { echo "file $$ runs in group $g"; exit 1; }\n' "$2"
  } >"$1"
}

# g1
if command -v perl >/dev/null 2>&1; then
  farm=$(no_timeout_path "$tmp/notimeout")
  s1="$tmp/s1"
  mkdir -p "$s1"
  group_file "$s1/test-own-group.sh" "="
  out=$(PATH="$farm" PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1.tsv" "$RUNNER" "$s1" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "g1: with no bounder, a file leads its own process group"
  else
    fail "g1: with no bounder, a file leads its own process group (exit $rc): $out"
  fi

  # g2: the file stops a child of its own, then a process of its group that
  # left a child there moves to a group of its own and exits, which orphans
  # the group the file runs in, if nothing outside it anchors it.
  s2="$tmp/s2"
  mkdir -p "$s2"
  cat >"$s2/test-orphans-group.sh" <<'FILE'
#!/bin/bash
sleep 30 &
held=$!
kill -STOP "$held"
perl -e 'my $c = fork(); if (!$c) { sleep 2; exit 0 } setpgrp(0, 0); exit 0'
sleep 1
kill -CONT "$held"
kill "$held"
exit 0
FILE
  # The runner leads a session of its own, so no member of its group has a
  # parent outside the group in that session.
  PATH="$farm" PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r2.tsv" \
    perl -MPOSIX -e 'POSIX::setsid() or exit 126; exec @ARGV or exit 127' -- \
    /bin/bash "$RUNNER" "$s2" >"$tmp/g2.out" 2>&1 </dev/null &
  wait "$!"
  rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^ok: test-orphans-group.sh' "$tmp/g2.out"; then
    pass "g2: a file that orphans its own group with a stopped child leaves the runner running"
  else
    fail "g2: a file that orphans its own group with a stopped child leaves the runner running (exit $rc): $(cat "$tmp/g2.out")"
  fi
else
  # The runner groups files through perl where no bounder does it.
  pass "g1, g2: skipped: no perl on this host"
fi

# g3
farm3=$(no_timeout_path "$tmp/noperl")
rm -f "$farm3/perl"
if PATH="$farm3" command -v perl >/dev/null 2>&1; then
  fail "g3: the fixture PATH still finds a perl"
fi
s3="$tmp/s3"
mkdir -p "$s3"
group_file "$s3/test-shared-group.sh" "!="
out=$(PATH="$farm3" PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r3.tsv" "$RUNNER" "$s3" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^ok: test-shared-group.sh'; then
  pass "g3: with neither a bounder nor perl, files still run, in the worker's group"
else
  fail "g3: with neither a bounder nor perl, files still run, in the worker's group (exit $rc): $out"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all file-group tests passed"
