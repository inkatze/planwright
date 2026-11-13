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
expect "mode-bit: a quoted chmod \"000\" with no access probe fails" 1 \
  "test-mode-bit-quoted.sh:5: mode-bit" "$(root_with mb-tpq mode-bit-quoted.sh)"
expect "mode-bit: a chmod -- 000 with no access probe fails" 1 \
  "test-mode-bit-dashdash.sh:5: mode-bit" "$(root_with mb-tpd mode-bit-dashdash.sh)"
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
# A here-string or an arithmetic shift is no heredoc: mistaking one swallows
# the rest of the file as a body and hides what follows it.
r=$(root_with here-string)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
read -r y <<< hello
chmod 000 "$f"
SUITE
expect "a here-string does not hide a later mode-bit fixture" 1 "test-case.sh:3: mode-bit" "$r"
r=$(root_with shift)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
n=$((1<<3))
chmod 000 "$f"
SUITE
expect "an arithmetic shift does not hide a later mode-bit fixture" 1 "test-case.sh:3: mode-bit" "$r"

# A quote inside a string before the operator still leaves the heredoc open,
# so the stub's body stays text.
r=$(root_with quote-before-heredoc)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
printf "it's\n" >/dev/null; cat >stub <<'EOF'
chmod 000 "$1"
echo "$PLANWRIGHT_ROOT"
EOF
SUITE
expect "a quoted heredoc opened after a quote-holding string stays text" 0 "clean" "$r"

# A string whose closing quote sits on a line opening with # still closes.
r=$(root_with hash-line-in-string)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
x='a
# b'
printf '%s\n' "$x" "$PLANWRIGHT_ROOT"
SUITE
expect "a #-led line inside a string does not leave the string open" 1 "test-case.sh:4: unsourced" "$r"

# --- mode-bit edges ------------------------------------------------------------
r=$(root_with short-mode)
printf '#!/bin/bash\nchmod 0 "$f"\n' >"$r/tests/test-case.sh"
expect "mode-bit: a short numeric mode is read as chmod pads it" 1 "test-case.sh:2: mode-bit" "$r"
r=$(root_with unrelated-probe)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 "$f"
[ -r "$log" ] || exit 1
chmod 644 "$f"
SUITE
expect "mode-bit: a probe of another path does not satisfy the fixture" 1 "test-case.sh:2: mode-bit" "$r"
r=$(root_with mkdir-mode)
printf '#!/bin/bash\nmkdir -m 500 "$d"\nmkdir -m 0700 "$e"\n' >"$r/tests/test-case.sh"
expect "mode-bit: a mkdir given a restrictive mode fails, a 0700 one does not" 1 \
  "test-case.sh:2: mode-bit" "$r"
case $out in
  *"test-case.sh:3:"*) fail "mode-bit: a mkdir -m 0700 was flagged: $out" ;;
esac
r=$(root_with mkdir-probed)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
mkdir -m 500 "$d"
if hermetic_access_denied w "$d"; then run_guard "$d"; fi
SUITE
expect "mode-bit: a mkdir -m fixture probing its target passes" 0 "clean" "$r"

# --- dead-owner edges ----------------------------------------------------------
r=$(root_with quoted-capture)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid="$!"
wait "$pid"
printf '%s\n' "$pid" >lock
SUITE
expect "dead-owner: a quoted \$! capture is still a capture" 1 "test-case.sh:5: dead-owner" "$r"
r=$(root_with local-capture)
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
r=$(root_with bare-wait)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait
ln -s "$pid-0-1" lock
SUITE
expect "dead-owner: a bare wait reaps the capture" 1 "test-case.sh:5: dead-owner" "$r"
r=$(root_with heredoc-use)
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
r=$(root_with dead-exempt)
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
r=$(root_with read-before-source)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
printf '%s\n' "$PLANWRIGHT_ROOT"
. "$(dirname "$0")/lib/hermetic-env.sh"
SUITE
expect "unsourced: a read before the source fails" 1 "test-case.sh:2: unsourced: reads \$PLANWRIGHT_ROOT before line 3" "$r"
r=$(root_with quoted-source)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
msg='run . tests/lib/hermetic-env.sh first'
echo "$msg $PLANWRIGHT_ROOT"
SUITE
expect "unsourced: a source spelled inside a string is no source" 1 "test-case.sh:3: unsourced" "$r"
r=$(root_with unsourced-exempt)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
x=${PLANWRIGHT_ROOT:-} # hermetic-exempt: reports the inherited value, by design
SUITE
expect "unsourced: an exclusion with a reason excludes the read" 0 "clean" "$r"

# A heredoc inside a command substitution opened within a double-quoted
# string is still a heredoc, and its quoted body stays text.
r=$(root_with subst-heredoc)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
out="$(
  cat <<'STUB'
chmod 000 "$1"
don't
STUB
)"
echo "$out $PLANWRIGHT_ROOT"
SUITE
expect "a heredoc inside \"\$( stays a heredoc, its body text" 1 "test-case.sh:8: unsourced" "$r"
case $out in
  *"test-case.sh:4:"*) fail "a heredoc body inside \"\$( was scanned as code: $out" ;;
esac

# Inside a multi-line string, a << opens nothing and a source line is text.
r=$(root_with string-heredoc)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
msg="first
cat <<EOF
. tests/lib/hermetic-env.sh
"
chmod 000 "$f"
echo "$msg $PLANWRIGHT_ROOT"
SUITE
expect "a << or a source inside a string opens and sources nothing" 1 "test-case.sh:6: mode-bit" "$r"
case $out in
  *"test-case.sh:7: unsourced"*) ;;
  *) fail "a source spelled inside a multi-line string counted as a source: $out" ;;
esac

# An escaped quote inside a double-quoted string does not end it.
r=$(root_with escaped-quote)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
echo "say \"hi\" <<EOF"
chmod 000 "$f"
SUITE
expect "an escaped quote does not expose a quoted << as a heredoc" 1 "test-case.sh:3: mode-bit" "$r"

# A #-led line inside a string is string text, and expands there.
r=$(root_with hash-read)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
msg="x
#$PLANWRIGHT_ROOT
"
SUITE
expect "a read on a #-led line inside a string is a read" 1 "test-case.sh:3: unsourced" "$r"

# --- mode-bit spellings ----------------------------------------------------------
r=$(root_with mkdir-spellings)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
mkdir -vm 500 "$a"
mkdir --mode 500 "$b"
mkdir -pm 500 "$c"
mkdir -m500 "$d"
mkdir --mode=500 "$e"
SUITE
out=$(/bin/bash "$CHECKER" "$r" 2>&1)
missed=""
for l in 2 3 4 5 6; do
  case $out in
    *"test-case.sh:$l: mode-bit"*) ;;
    *) missed="$missed $l" ;;
  esac
done
if [ -z "$missed" ]; then
  pass "mode-bit: every mkdir mode spelling opens a fixture"
else
  fail "mode-bit: mkdir spellings on lines$missed went unflagged: $out"
fi
r=$(root_with mkdir-no-restore)
printf '#!/bin/bash\nchmod 000 "$f"\nmkdir -m 700 "$f"\n' >"$r/tests/test-case.sh"
expect "mode-bit: a mkdir never restores an open fixture" 1 \
  "test-case.sh:2: mode-bit: removes owner access to \"\$f\" with no access probe after it" "$r"
r=$(root_with probe-prefix)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 "$f"
[ -r "$file" ] || exit 1
chmod 644 "$f"
SUITE
expect "mode-bit: a probe of a longer name is not a probe of the target" 1 "test-case.sh:2: mode-bit" "$r"
r=$(root_with probe-spellings)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 $f
if hermetic_access_denied r "${f}"; then :; fi
chmod 644 "$f"
SUITE
expect "mode-bit: a probe spelling the target with other quotes or braces counts" 0 "clean" "$r"

# --- dead-owner spellings ----------------------------------------------------------
r=$(root_with capture-spellings)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
readonly p1=$!
if true; then p2=$!; fi
wait "$p1" "$p2"
echo "$p1" >lock1
echo "$p2" >lock2
SUITE
out=$(/bin/bash "$CHECKER" "$r" 2>&1)
case $out in
  *"test-case.sh:6: dead-owner"*"test-case.sh:7: dead-owner"* | *"test-case.sh:7: dead-owner"*"test-case.sh:6: dead-owner"*)
    pass "dead-owner: captures after readonly and after then are captures"
    ;;
  *) fail "dead-owner: a readonly or then capture went unflagged: $out" ;;
esac
r=$(root_with wait-redirect)
printf '#!/bin/bash\nsleep 0 &\npid=$!\nwait 2>/dev/null\necho "$pid" >lock\n' >"$r/tests/test-case.sh"
expect "dead-owner: a bare wait with a redirect reaps the capture" 1 "test-case.sh:5: dead-owner" "$r"
r=$(root_with wait-line-use)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 30 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null; wait; }
{ kill "$pid"; wait; } 2>/dev/null
SUITE
expect "dead-owner: a line that waits is not a use of what it reaps" 0 "clean" "$r"
r=$(root_with wait-in-comment)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 30 &
pid=$!
do_thing # and wait
printf '%s\n' "$pid" >lock
SUITE
expect "dead-owner: wait in a trailing comment reaps nothing" 0 "clean" "$r"
r=$(root_with escaped-body-use)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"
cat >stub <<STUB
echo \$pid >out
STUB
SUITE
expect "dead-owner: an escaped \$pid in a heredoc body is the stub's, not a use" 0 "clean" "$r"

# A wait line is read one command at a time: a use after the wait on the
# same line is a use, a wait on one PID does not hide another's, and a
# command merely starting with "wait" is no wait.
r=$(root_with wait-then-use)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait; printf '%s\n' "$pid" >lock
SUITE
expect "dead-owner: a use after a bare wait on the same line fails" 1 "test-case.sh:4: dead-owner" "$r"
r=$(root_with wait-other)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
p1=$!
wait "$p1"
sleep 0 &
p2=$!
wait "$p2"; printf '%s\n' "$p1" >lock
SUITE
expect "dead-owner: a wait on one PID does not hide a use of another" 1 "test-case.sh:7: dead-owner" "$r"
r=$(root_with wait-prefix)
printf '#!/bin/bash\nsleep 0 &\npid=$!\nwait2>/dev/null\nprintf "%%s\\n" "$pid" >lock\n' >"$r/tests/test-case.sh"
expect "dead-owner: a command named wait2 is no wait" 0 "clean" "$r"
r=$(root_with probe-brace-suffix)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 "${f}x"
[ -r "$fx" ] || exit 1
chmod 644 "${f}x"
SUITE
expect "mode-bit: a probe of \$fx is not a probe of \${f}x" 1 "test-case.sh:2: mode-bit" "$r"
r=$(root_with subst-heredoc-one-line)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
out="$(cat <<'STUB'
chmod 000 "$1"
STUB
)"
SUITE
expect "a heredoc opened on the line of a \"\$( keeps its body text" 0 "clean" "$r"

# A wait reaps wherever a command word can sit, and a kill there is no use.
r=$(root_with wait-positions)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
p1=$!
if ! wait "$p1"; then echo failed; fi
sleep 0 &
p2=$!
time wait "$p2"
sleep 0 &
p3=$!
case $mode in stop) wait "$p3" ;; esac
sleep 0 &
p4=$!
rc=$(wait "$p4"; echo $?)
echo "$p1 $p2 $p3 $p4" >lock
SUITE
expect "dead-owner: a wait after if !, time, a case pattern or \$( still reaps" 1 "test-case.sh:14: dead-owner" "$r"
missed=""
for v in p1 p2 p3 p4; do
  case $out in
    *"uses \$$v after"*) ;;
    *) missed="$missed $v" ;;
  esac
done
[ -z "$missed" ] || fail "dead-owner: waits on$missed went unread: $out"
r=$(root_with kill-after-then)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"; if true; then kill "$pid" 2>/dev/null; fi
SUITE
expect "dead-owner: a kill after then is no use" 0 "clean" "$r"

# A chmod inside a double-quoted $( ) names its own target, and a target
# spelled "$f"x is the same path as ${f}x and not $fx.
r=$(root_with chmod-in-subst)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
x="$(chmod 000 "$f")"
if hermetic_access_denied r "$f"; then :; fi
chmod 644 "$f"
SUITE
expect "mode-bit: a chmod inside \"\$( ) is matched to its probe and restore" 0 "clean" "$r"
r=$(root_with quote-split)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
chmod 000 "${f}x"
[ -r "$f"x ] || echo denied
chmod 644 "${f}x"
chmod 000 "$g"x
[ -r "$gx" ] || exit 1
chmod 644 "$g"x
SUITE
expect "mode-bit: \"\$g\"x is not \$gx" 1 "test-case.sh:5: mode-bit" "$r"
case $out in
  *"test-case.sh:2:"*) fail "mode-bit: a probe of \"\$f\"x did not satisfy \${f}x: $out" ;;
esac

# The word wait or kill as an argument or a case label is plain text: it
# reaps nothing and hides no use.
r=$(root_with wait-as-text)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 5 &
pid=$!
printf '%s\n' "$out" | grep -q wait
echo wait
f() { local wait; }
case "$action" in
  wait) echo "$pid" ;;
esac
echo "$pid" >log
SUITE
expect "dead-owner: wait as an argument or a case label reaps nothing" 0 "clean" "$r"
r=$(root_with kill-as-text)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"; log_step kill "$pid"
SUITE
expect "dead-owner: kill as an argument does not hide a use" 1 "test-case.sh:4: dead-owner" "$r"

# A function head, a parenthesised case pattern and time -p all put the next
# word in command position.
r=$(root_with wait-in-heads)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
p1=$!
reap() { wait "$p1" 2>/dev/null; }
sleep 0 &
p2=$!
case $x in (a) wait "$p2" ;; esac
sleep 0 &
p3=$!
time -p wait "$p3"
echo "$p1 $p2 $p3" >log
SUITE
out=$(/bin/bash "$CHECKER" "$r" 2>&1)
missed=""
for v in p1 p2 p3; do
  case $out in
    *"uses \$$v after"*) ;;
    *) missed="$missed $v" ;;
  esac
done
if [ -z "$missed" ]; then
  pass "dead-owner: a wait after a function head, a (pattern) or time -p reaps"
else
  fail "dead-owner: waits on$missed went unread: $out"
fi
r=$(root_with wait-after-bang-paren)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
p1=$!
if !(wait "$p1"); then :; fi
sleep 0 &
p2=$!
if true; then {(wait "$p2"); }; fi
echo "$p1 $p2" >log
SUITE
out=$(/bin/bash "$CHECKER" "$r" 2>&1)
case $out in
  *"uses \$p1 after"*"uses \$p2 after"* | *"uses \$p2 after"*"uses \$p1 after"*)
    pass "dead-owner: a wait right after a bang or brace and a paren reaps"
    ;;
  *) fail "dead-owner: a wait after !( or {( went unread: $out" ;;
esac
r=$(root_with kill-in-head)
cat >"$r/tests/test-case.sh" <<'SUITE'
#!/bin/bash
sleep 0 &
pid=$!
wait "$pid"
stop() { kill "$pid" 2>/dev/null; wait "$pid"; }
SUITE
expect "dead-owner: a kill opening a function body is no use" 0 "clean" "$r"

# The command-position test stays linear: a long line of substitutions
# beside a wait-like word scans at once.
r=$(root_with long-subst-line)
{
  printf '#!/bin/bash\nsleep 0 &\npid=$!\necho'
  i=0
  while [ "$i" -lt 40 ]; do
    printf ' x$(a) b`c` d)'
    i=$((i + 1))
  done
  printf ' waitx\n'
} >"$r/tests/test-case.sh"
started=$SECONDS
expect "a long line of substitutions beside a wait-like word is scanned" 0 "clean" "$r"
if [ $((SECONDS - started)) -gt 20 ]; then
  fail "the long substitution line took $((SECONDS - started))s to scan"
fi
# A run of parenthesised words before a wait the pattern then rejects is the
# shape an ambiguous token would backtrack on; timeout, where the host has
# it, turns such a hang into a failure.
for tok in ' (a)' ' !a)' ' {a)' ' function a{{{{' ' function a!!!!' \
  ' if{a)' ' do!a)' ' function a{if' ' function f{a)' ' then{if!a)' ' if{(a)' ' a){('; do
  r=$(root_with long-token-line)
  {
    printf '#!/bin/bash\nsleep 0 &\npid=$!\n'
    i=0
    while [ "$i" -lt 40 ]; do
      printf '%s' "$tok"
      i=$((i + 1))
    done
    printf ' x wait\n'
  } >"$r/tests/test-case.sh"
  started=$SECONDS
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout 60 /bin/bash "$CHECKER" "$r" 2>&1)
  else
    out=$(/bin/bash "$CHECKER" "$r" 2>&1)
  fi
  rc=$?
  if [ "$rc" -eq 0 ] && [ $((SECONDS - started)) -le 20 ]; then
    pass "a long run of '$tok' before a wait is scanned at once"
  else
    fail "a line of '$tok' took $((SECONDS - started))s (exit $rc): $out"
  fi
  rm -rf "$r"
done

# A library name holding a glob character is malformed as written, never
# expanded to the files it would match.
r=$(root_with glob-name sourced-read.sh)
cat >"$r/tests/lib/hermetic-env.sh" <<'LIB'
hermetic_env_names() { printf '%s\n' '*'; }
LIB
mkdir -p "$tmp/glob-cwd"
: >"$tmp/glob-cwd/VALIDNAME"
out=$(cd "$tmp/glob-cwd" && /bin/bash "$CHECKER" "$r" 2>&1)
rc=$?
case $out in
  *"malformed name"*) named=1 ;;
  *) named=0 ;;
esac
if [ "$rc" -eq 2 ] && [ "$named" -eq 1 ]; then
  pass "a glob character in a listed name is refused as written"
else
  fail "a glob name was expanded or accepted (exit $rc): $out"
fi

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
