#!/bin/bash
# Tests that scripts/run-tests.sh gives every test file a process group of its
# own on a host with no timeout(1) or gtimeout (macOS), as GNU timeout already
# does elsewhere. A file sharing the runner's group can leave a stopped process
# there (a close freezes a fixture worker tree with SIGSTOP); when that group
# then has no member with a parent outside it in its session, as under a CI
# runner a service manager started, the kernel's orphaned-group rule sends
# SIGHUP to the whole group: the runner, its caller and every other file.
#
#   g1: with no bounder, a file leads its own process group.
#   g2: a runner in a fresh session survives a file that orphans its own
#       group while holding a stopped child, and the file passes.
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

if ! command -v perl >/dev/null 2>&1; then
  # The runner groups files through perl where no bounder does it.
  echo "ok: skipped: no perl on this host"
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-file-group.XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT
farm=$(no_timeout_path "$tmp/notimeout")

# Every file reads its group from /proc where it exists, since busybox's ps
# takes no -p; else from ps (macOS has no /proc).
pgid_snippet='pgid_of() {
  if [ -r "/proc/$1/stat" ]; then
    sed "s/.*) //" "/proc/$1/stat" | awk "{ print \$3 }"
  else
    ps -o pgid= -p "$1" | tr -d " "
  fi
}'

# g1
s1="$tmp/s1"
mkdir -p "$s1"
{
  echo '#!/bin/bash'
  printf '%s\n' "$pgid_snippet"
  # shellcheck disable=SC2016 # expanded by the fixture file
  echo 'g=$(pgid_of $$); [ "$g" = "$$" ] || { echo "file $$ runs in group $g"; exit 1; }'
} >"$s1/test-own-group.sh"
out=$(PATH="$farm" PLANWRIGHT_TEST_TIMING_REPORT="$tmp/r1.tsv" "$RUNNER" "$s1" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "g1: with no bounder, a file leads its own process group"
else
  fail "g1: with no bounder, a file leads its own process group (exit $rc): $out"
fi

# g2: the file stops a child of its own, then a process of its group that left
# a child there moves to a group of its own and exits, which orphans the
# group the file runs in, if nothing outside it anchors it.
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all file-group tests passed"
