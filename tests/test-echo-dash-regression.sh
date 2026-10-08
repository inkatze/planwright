#!/bin/bash
# Regression test for the dash escape re-synthesis (the echo discipline,
# doctrine/security-posture.md).
#
# sanitize_printable strips control BYTES and keeps the printable text `\033`.
# dash's `echo` expands that text back into a real ESC, so a printable-only
# argument used to reach the terminal as a live escape through the very
# refusal paths meant to contain it. Each case below runs a real script's
# refusal path under dash with such an argument and asserts no control byte
# (other than newline and tab) comes out. A control case first proves the
# located shell does re-synthesize, so a shell that cannot reproduce the
# hazard fails this test rather than passing it vacuously.
#
# The shell is `dash` from PATH, else /bin/sh when it expands echo escapes
# (macOS /bin/sh does, through xpg_echo). Neither present is a failure with
# the remedy, never a skip.
# shellcheck disable=SC2016 # the -c programs are meant for the shell under test
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO_ROOT/scripts"

failures=0
ok() { printf 'ok: %s\n' "$1"; }
bad() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# The count of control bytes in file $1, newline and tab excepted. A file,
# never a command substitution: bash drops NUL bytes from those, so a NUL the
# shell emitted would go uncounted.
ctl_count() {
  tr -d '\n\t' <"$1" | tr -cd '\000-\037\177' | wc -c | tr -d ' '
}

expands() {
  [ "$("$1" -c 'echo "$1"' _ '\101' 2>/dev/null)" = "A" ]
}

sh_under_test=""
if command -v dash >/dev/null 2>&1; then
  sh_under_test=$(command -v dash)
elif [ -x /bin/sh ] && expands /bin/sh; then
  sh_under_test=/bin/sh
fi
if [ -z "$sh_under_test" ]; then
  printf 'FAIL: no dash on PATH and /bin/sh does not expand echo escapes; install dash to run this regression test\n' >&2
  exit 1
fi
ok "shell under test: $sh_under_test"

# ESC in both octal spellings dash reads, and a NUL (\0000).
hostile='x\033[31mRED\0033[0m\0000end'

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-echo-dash-regression.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/data" "$tmp/spec"

# Control: the located shell turns the printable text into live ESC and NUL.
"$sh_under_test" -c 'echo "$1"' _ "$hostile" >"$tmp/control"
if [ "$(ctl_count "$tmp/control")" -gt 0 ] && [ "$(tr -cd '\000' <"$tmp/control" | wc -c | tr -d ' ')" -gt 0 ]; then
  ok "the shell under test re-synthesizes ESC and NUL from printable text (the hazard is real here)"
else
  bad "the shell under test did not expand the escape text, so the cases below would prove nothing"
fi

# run_case <label> <script> <args...> — run under the shell, from an empty
# directory with HOME and the plugin data dir pointed into the temp tree, and
# assert a refusal with no control byte in the combined output.
run_case() {
  label=$1
  shift
  (cd "$tmp" && HOME="$tmp/home" CLAUDE_PLUGIN_DATA="$tmp/data" \
    "$sh_under_test" "$@" >"$tmp/out" 2>&1 </dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "$label: expected a refusal, got exit 0"
    return
  fi
  n=$(ctl_count "$tmp/out")
  if [ "$n" -eq 0 ]; then
    ok "$label: refusal carries no control byte"
  else
    bad "$label: refusal emitted $n control byte(s)"
  fi
  if grep -qF '\033' "$tmp/out"; then
    ok "$label: the escape text is shown inert"
  else
    bad "$label: the refusal did not show the hostile value as text"
  fi
}

run_case "allocation-ledger malformed unit" \
  "$SCRIPTS/allocation-ledger.sh" append "$hostile" s 1 e pm pe cm ce rm re sc ok in
run_case "allocation-ledger non-numeric attempt" \
  "$SCRIPTS/allocation-ledger.sh" append spec:task-1 step "$hostile" e pm pe cm ce rm re sc ok in
run_case "orchestrate-marker malformed task id" \
  "$SCRIPTS/orchestrate-marker.sh" write "$tmp/spec" "1$hostile"
run_case "fleet-liveness unknown command" \
  "$SCRIPTS/fleet-liveness.sh" "$hostile"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all echo-dash-regression tests passed\n'
