#!/bin/bash
# Tests for scripts/check-test-hermeticity.sh (review-effectiveness REQ-F1.5):
# each of the three shapes fails on its fixture and its conforming twin
# passes, the dead-owner twins covering both the helper's PID and a
# lock-library token. Each fixture under tests/fixtures/test-hermeticity/ is
# scanned alone, in a root holding a copy of the real clearing library, so the
# list the guard checks against is the one the suites source.
#
# Anything that would make the scan cover less than it claims is exit 2,
# never a clean report.
#
# shellcheck disable=SC2016 # fixture bodies are literal shell text the guard
# reads as written; expanding them here would defeat the fixture.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
CHECKER="$REPO_ROOT/scripts/check-test-hermeticity.sh"
FIX="$here/fixtures/test-hermeticity"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'chmod -R u+rw "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# root_with <name> <fixture>...: a scan root holding the library and the
# fixtures as suites.
root_with() {
  r="$tmp/$1"
  shift
  mkdir -p "$r/tests/lib"
  cp "$REPO_ROOT/tests/lib/hermetic-env.sh" "$r/tests/lib/"
  for f in "$@"; do
    cp "$FIX/$f" "$r/tests/test-$f"
  done
  printf '%s\n' "$r"
}

# expect <label> <exit> <needle-or-empty> <root>
expect() {
  out=$(/bin/bash "$CHECKER" "$4" 2>&1)
  rc=$?
  if [ "$rc" -ne "$2" ]; then
    fail "$1 (expected exit $2, got $rc): $out"
    return
  fi
  case "$out" in
    *"$3"*) pass "$1" ;;
    *) fail "$1 (output did not mention '$3'): $out" ;;
  esac
}

[ -f "$CHECKER" ] || {
  echo "FAIL: checker missing at $CHECKER" >&2
  exit 1
}

# --- the three shapes, each with its twin ------------------------------------
expect "mode-bit: a chmod 000 fixture with no access probe fails" 1 \
  "test-mode-bit-unprobed.sh:6: mode-bit" "$(root_with mb-tp mode-bit-unprobed.sh)"
expect "mode-bit: a fixture probing through hermetic_access_denied passes" 0 "clean" \
  "$(root_with mb-tn mode-bit-probed.sh)"
expect "mode-bit: a symbolic a-w fixture probing with [ -w ] passes" 0 "clean" \
  "$(root_with mb-tn2 mode-bit-test-probe.sh)"

expect "dead-owner: a reaped \$! PID reused as an owner fails" 1 \
  "test-dead-owner-reaped.sh:8: dead-owner" "$(root_with do-tp dead-owner-reaped.sh)"
expect "dead-owner: a PID from dead_owner_pid passes" 0 "clean" \
  "$(root_with do-tn dead-owner-helper.sh)"
expect "dead-owner: a lock-library token from an exited holder passes" 0 "clean" \
  "$(root_with do-tn2 dead-owner-lock-token.sh)"

expect "unsourced: reading a listed root variable without the library fails" 1 \
  "test-unsourced-read.sh:4: unsourced: reads \$PLANWRIGHT_ROOT" "$(root_with uv-tp unsourced-read.sh)"
expect "unsourced: the same read after sourcing the library passes" 0 "clean" \
  "$(root_with uv-tn sourced-read.sh)"
expect "unsourced: a pinned variable read after fleet_home_pin passes" 0 "clean" \
  "$(root_with uv-tn2 pinned-read.sh)"
expect "unsourced: names in comments, single quotes, escapes and quoted heredocs are not reads" 0 "clean" \
  "$(root_with uv-tn3 literal-mention.sh)"

# An unquoted heredoc body is expanded by the suite itself.
r=$(root_with uv-heredoc)
printf '#!/bin/bash\ncat <<EOF\n$CLAUDE_PLUGIN_ROOT/x\nEOF\n' >"$r/tests/test-heredoc.sh"
expect "unsourced: a read in an unquoted heredoc body fails" 1 "test-heredoc.sh:3: unsourced" "$r"

# Every listed variable is checked, the pinned ones included.
for v in $(hermetic_env_names); do
  r=$(root_with "each-$v")
  printf '#!/bin/bash\nx=${%s:-}\n' "$v" >"$r/tests/test-each.sh"
  out=$(/bin/bash "$CHECKER" "$r" 2>&1)
  case "$out" in
    *"reads \$$v without"*) ;;
    *) fail "unsourced: a read of $v went unflagged: $out" ;;
  esac
done
pass "unsourced: a read of each listed variable is flagged"

# --- exclusions --------------------------------------------------------------
expect "an exclusion marker with a reason excludes its line" 0 "clean" \
  "$(root_with ex-ok exempt-with-reason.sh)"
expect "an exclusion marker with no reason excludes nothing" 1 "mode-bit" \
  "$(root_with ex-bare exempt-without-reason.sh)"

# --- scope -------------------------------------------------------------------
r=$(root_with scope sourced-read.sh)
mkdir -p "$r/tests/fixtures"
cp "$FIX/unsourced-read.sh" "$r/tests/fixtures/"
expect "fixtures under tests/fixtures are not scanned" 0 "clean" "$r"
r=$(root_with lib-scope)
cp "$FIX/unsourced-read.sh" "$r/tests/lib/helper.sh"
expect "a sourced library under tests/lib is scanned" 1 "tests/lib/helper.sh:4: unsourced" "$r"

# --- fail closed ---------------------------------------------------------------
mkdir -p "$tmp/no-tests"
expect "a root with no tests directory is exit 2" 2 "no tests directory" "$tmp/no-tests"
r=$(root_with no-lib sourced-read.sh)
rm "$r/tests/lib/hermetic-env.sh"
expect "a root with no clearing library is exit 2" 2 "cannot read the variable list" "$r"
r=$(root_with empty-lib sourced-read.sh)
printf 'hermetic_env_names() { :; }\n' >"$r/tests/lib/hermetic-env.sh"
expect "a library listing nothing is exit 2" 2 "lists no variables" "$r"
r=$(root_with unreadable sourced-read.sh)
chmod 000 "$r/tests/test-sourced-read.sh"
if hermetic_access_denied r "$r/tests/test-sourced-read.sh"; then
  expect "an unreadable suite is exit 2" 2 "cannot read tests/test-sourced-read.sh" "$r"
else
  echo "skip: unreadable-suite case: the running user reads mode 000"
fi
chmod 644 "$r/tests/test-sourced-read.sh"
expect "an unknown option is exit 2" 2 "unknown option" "--bogus"

# --- this repository ---------------------------------------------------------
expect "this repository's test surface is clean" 0 "clean" "$REPO_ROOT"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-test-hermeticity tests passed"
