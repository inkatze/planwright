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

# Every listed variable is checked, the pinned ones included: one suite per
# variable, all in one root, so one scan covers the list.
r=$(root_with each)
for v in $(hermetic_env_names); do
  printf '#!/bin/bash\nx=${%s:-}\n' "$v" >"$r/tests/test-each-$v.sh"
done
out=$(/bin/bash "$CHECKER" "$r" 2>&1)
missed=""
for v in $(hermetic_env_names); do
  case "$out" in
    *"test-each-$v.sh:2: unsourced: reads \$$v without"*) ;;
    *) missed="$missed $v" ;;
  esac
done
if [ -z "$missed" ]; then
  pass "unsourced: a read of each listed variable is flagged"
else
  fail "unsourced: reads went unflagged:$missed: $out"
fi

# --- the parse the shapes rest on ----------------------------------------------
# case_root <name>: a root whose one suite, tests/test-case.sh, the caller
# writes next.
case_root() {
  r=$(root_with "$1")
  printf '%s\n' "$r"
}

# A here-string or an arithmetic shift is no heredoc: mistaking one swallows
# the rest of the file as a body and hides what follows it.
r=$(case_root here-string)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
read -r y <<< hello
chmod 000 "$f"
SUITE
expect "a here-string does not hide a later mode-bit fixture" 1 "test-case.sh:3: mode-bit" "$r"
r=$(case_root shift)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
n=$((1<<3))
chmod 000 "$f"
SUITE
expect "an arithmetic shift does not hide a later mode-bit fixture" 1 "test-case.sh:3: mode-bit" "$r"

# A quote inside a string before the operator still leaves the heredoc open,
# so the stub's body stays text.
r=$(case_root quote-before-heredoc)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
printf "it's\n" >/dev/null; cat >stub <<'EOF'
chmod 000 "$1"
echo "$PLANWRIGHT_ROOT"
EOF
SUITE
expect "a quoted heredoc opened after a quote-holding string stays text" 0 "clean" "$r"

# A string whose closing quote sits on a line opening with # still closes.
r=$(case_root hash-line-in-string)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
x='a
# b'
printf '%s\n' "$x" "$PLANWRIGHT_ROOT"
SUITE
expect "a #-led line inside a string does not leave the string open" 1 "test-case.sh:4: unsourced" "$r"

# --- mode-bit edges ------------------------------------------------------------
r=$(case_root short-mode)
printf '#!/bin/bash\nchmod 0 "$f"\n' >"$r/tests/test-case.sh"
expect "mode-bit: a short numeric mode is read as chmod pads it" 1 "test-case.sh:2: mode-bit" "$r"
r=$(case_root unrelated-probe)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 "$f"
[ -r "$log" ] || exit 1
chmod 644 "$f"
SUITE
expect "mode-bit: a probe of another path does not satisfy the fixture" 1 "test-case.sh:2: mode-bit" "$r"
r=$(case_root mkdir-mode)
printf '#!/bin/bash\nmkdir -m 500 "$d"\nmkdir -m 0700 "$e"\n' >"$r/tests/test-case.sh"
expect "mode-bit: a mkdir given a restrictive mode fails, a 0700 one does not" 1 \
  "test-case.sh:2: mode-bit" "$r"
case $out in
  *"test-case.sh:3:"*) fail "mode-bit: a mkdir -m 0700 was flagged: $out" ;;
esac
r=$(case_root mkdir-probed)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
mkdir -m 500 "$d"
if hermetic_access_denied w "$d"; then run_guard "$d"; fi
SUITE
expect "mode-bit: a mkdir -m fixture probing its target passes" 0 "clean" "$r"

# --- dead-owner edges ----------------------------------------------------------
r=$(case_root quoted-capture)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid="$!"
wait "$pid"
printf '%s\n' "$pid" >lock
SUITE
expect "dead-owner: a quoted \$! capture is still a capture" 1 "test-case.sh:5: dead-owner" "$r"
r=$(case_root local-capture)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
f() {
  sleep 0 &
  local p=$!
  wait "$p"
  ln -s "$p-0-1" lock
}
SUITE
expect "dead-owner: a local \$! capture is still a capture" 1 "test-case.sh:6: dead-owner" "$r"
r=$(case_root bare-wait)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait
ln -s "$pid-0-1" lock
SUITE
expect "dead-owner: a bare wait reaps the capture" 1 "test-case.sh:5: dead-owner" "$r"
r=$(case_root heredoc-use)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"
cat >lock <<EOF
$pid
EOF
SUITE
expect "dead-owner: a reaped PID expanded into an unquoted heredoc body fails" 1 "test-case.sh:6: dead-owner" "$r"
r=$(case_root dead-exempt)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"
# hermetic-exempt: asserts the reaped child is gone, not that its PID is free
printf '%s\n' "$pid" >lock
SUITE
expect "dead-owner: an exclusion with a reason excludes the use" 0 "clean" "$r"

# --- unsourced edges -----------------------------------------------------------
r=$(case_root read-before-source)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
printf '%s\n' "$PLANWRIGHT_ROOT"
. "$(dirname "$0")/lib/hermetic-env.sh"
SUITE
expect "unsourced: a read before the source fails" 1 "test-case.sh:2: unsourced: reads \$PLANWRIGHT_ROOT before line 3" "$r"
r=$(case_root quoted-source)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
msg='run . tests/lib/hermetic-env.sh first'
echo "$msg $PLANWRIGHT_ROOT"
SUITE
expect "unsourced: a source spelled inside a string is no source" 1 "test-case.sh:3: unsourced" "$r"
r=$(case_root unsourced-exempt)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
x=${PLANWRIGHT_ROOT:-} # hermetic-exempt: reports the inherited value, by design
SUITE
expect "unsourced: an exclusion with a reason excludes the read" 0 "clean" "$r"

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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-test-hermeticity tests passed"
