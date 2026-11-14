#!/bin/bash
# Tests that scripts/run-tests.sh takes its whole worker tree with it when the
# run is cancelled: a TERM, INT or HUP to the runner, even one started with
# INT and QUIT inherited ignored (as a job started asynchronously by a shell
# without job control, such as a CI runner's, gets them), leaves no test file
# or anything it started running.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"
# shellcheck source=tests/lib/poll-until.sh
. "$REPO_ROOT/tests/lib/poll-until.sh"

unset PLANWRIGHT_TEST_IN_POOLED_FILE PLANWRIGHT_TEST_SLOTS PLANWRIGHT_TEST_JOBS \
  PLANWRIGHT_TEST_FORCE_SERIAL PLANWRIGHT_TEST_TIMING_REPORT \
  PLANWRIGHT_TEST_DURATIONS PLANWRIGHT_TEST_FILE_DEADLINE

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-run-tests-cancel.XXXXXX")" || exit 2
all_pids=""
cleanup() {
  # shellcheck disable=SC2086 # a list of pids
  [ -z "$all_pids" ] || kill -s KILL $all_pids 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

# started_count <dir> — stub files that have recorded themselves.
started_count() {
  find "$1" -name 'file-*' 2>/dev/null | wc -l | tr -d ' '
}
enough_started() { [ "$(started_count "$1")" -ge "$2" ]; }
# stub_pids <dir> — every recorded pid, file and child alike.
stub_pids() {
  cat "$1"/file-* "$1"/child-* 2>/dev/null
}
none_running() {
  for np_pid in "$@"; do
    kill -0 "$np_pid" 2>/dev/null && return 1
  done
  return 0
}

# cancel_case <label> <dir> <signal> [VAR=value...] — run the runner on two
# slow stub files with INT and QUIT ignored, signal it, and require the run
# and every stub process to be gone within the deadline.
cancel_case() {
  cc_label=$1
  cc_dir=$2
  cc_sig=$3
  shift 3
  cc_want=2
  case " $* " in *FORCE_SERIAL*) cc_want=1 ;; esac
  mkdir -p "$cc_dir/suite" "$cc_dir/pids"
  for cc_n in a b; do
    cat >"$cc_dir/suite/test-$cc_n.sh" <<EOF
#!/bin/bash
echo \$\$ >"$cc_dir/pids/file-$cc_n"
sleep 300 &
echo \$! >"$cc_dir/pids/child-$cc_n"
wait
EOF
  done
  # shellcheck disable=SC2016 # the inner shell expands its own arguments
  env "$@" PLANWRIGHT_TEST_JOBS=2 PLANWRIGHT_TEST_TIMING_REPORT="$cc_dir/r.tsv" \
    sh -c 'trap "" INT QUIT; exec /bin/bash "$0" "$1"' "$RUNNER" "$cc_dir/suite" \
    >"$cc_dir/out" 2>&1 </dev/null &
  cc_run=$!
  all_pids="$all_pids $cc_run"
  if ! poll_until --what "$cc_label: the stub files started" -- enough_started "$cc_dir/pids" "$cc_want"; then
    fail "$cc_label: the stub files started"
    kill -s KILL "$cc_run" 2>/dev/null
    return
  fi
  # shellcheck disable=SC2046 # a list of pids
  cc_stubs=$(stub_pids "$cc_dir/pids")
  # shellcheck disable=SC2086
  all_pids="$all_pids $cc_stubs"
  kill -s "$cc_sig" "$cc_run"
  if poll_until --deadline 30 --what "$cc_label: the runner ends" -- none_running "$cc_run"; then
    pass "$cc_label: the runner ends"
  else
    fail "$cc_label: the runner ends"
  fi
  # shellcheck disable=SC2086 # a list of pids
  if poll_until --deadline 30 --what "$cc_label: no stub outlives it" -- none_running $cc_stubs; then
    pass "$cc_label: no stub outlives it"
  else
    fail "$cc_label: no stub outlives it"
  fi
}

cancel_case "TERM" "$tmp/term" TERM
cancel_case "INT" "$tmp/int" INT
cancel_case "HUP" "$tmp/hup" HUP
cancel_case "TERM, serial" "$tmp/serial" TERM PLANWRIGHT_TEST_FORCE_SERIAL=1

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all cancel tests passed"
