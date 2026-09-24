#!/bin/bash
# Tests for scripts/check-task-registration.sh — the standing registration
# check: every `check:` / `lint:` / `scan:` task in mise.toml must be reachable
# from the `check` aggregate (REQ-H1.2, REQ-H1.3).
#
# Same obligation as tests/test-check-guard-wiring.sh: the guard under test
# exists because a guard nothing runs cannot fail, so every passing case here
# is paired with a planted negative the guard must catch. mise.toml is
# PR-controllable, so the guard reads it as text; the fixtures below are
# written by generating whole files, never by patching with sed.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-task-registration.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
CHECKER="$REPO_ROOT/scripts/check-task-registration.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CHECKER" ] || fail "scripts/check-task-registration.sh missing or not executable"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-task-registration.XXXXXX") || fail "mktemp -d failed"
[ -n "$tmp" ] && [ -d "$tmp" ] || fail "mktemp -d produced no directory"
trap 'rm -rf "$tmp"' EXIT

# mkrepo <dir>
#   A minimal mise.toml whose aggregate reaches one task per namespace, plus
#   an un-namespaced task nothing depends on (which must never be flagged), a
#   commented-out edge, and a multi-line run body holding a bare edge line and
#   a header (which must never be read as either). Cases append planted tasks
#   with a heredoc.
mkrepo() {
  mr=$1
  rm -rf "$mr"
  mkdir -p "$mr"
  cat >"$mr/mise.toml" <<'TOML'
[tasks.check]
description = "aggregate: prose naming check:described is not an edge"
# depends = ["check:commented"]
depends = [
  "test",
  "check:alpha",  # trailing comment
  'lint:alpha',
  "scan:alpha",
]

[tasks.test]
run = "true"

[tasks.release]
run = "true"

[tasks."check:alpha"]
run = "true"

[tasks.'lint:alpha']
run = "true"

[tasks."scan:alpha"]
run = '''
depends = ["check:in-run-body"]
[tasks."check:in-run-body"]
'''
TOML
}

run_checker() { /bin/sh "$CHECKER" --repo-root "$1" 2>"$tmp/err"; }

# ---------------------------------------------------------------------------
# t1: the real repository passes. If this ever fails, a guard has come loose.
# ---------------------------------------------------------------------------
/bin/sh "$CHECKER" --repo-root "$REPO_ROOT" >/dev/null 2>"$tmp/err" \
  || fail "t1: the real repo should pass, got: $(cat "$tmp/err")"
echo "ok: t1 every namespaced task in the repository's mise.toml is registered"

# ---------------------------------------------------------------------------
# t2: the baseline fixture passes, then one planted task per namespace fails
#     and is named. POSITIVE CONTROL for every passing case below.
# ---------------------------------------------------------------------------
r="$tmp/r2"
mkrepo "$r"
run_checker "$r" >/dev/null || fail "t2: the baseline fixture should pass: $(cat "$tmp/err")"
for ns in check lint scan; do
  mkrepo "$r"
  printf '\n[tasks."%s:planted"]\nrun = "true"\n' "$ns" >>"$r/mise.toml"
  run_checker "$r" >/dev/null
  rc=$?
  [ "$rc" = 1 ] || fail "t2: an unregistered $ns: task should be exit 1, got $rc: $(cat "$tmp/err")"
  grep -q "$ns:planted" "$tmp/err" \
    || fail "t2: the diagnostic does not name the unregistered $ns: task: $(cat "$tmp/err")"
done
echo "ok: t2 an unregistered check:/lint:/scan: task fails the check and is named"

# ---------------------------------------------------------------------------
# t3: the same task, listed in the aggregate's depends, passes — proving t2's
#     failure came from the wiring and not the task's existence.
# ---------------------------------------------------------------------------
r="$tmp/r3"
mkrepo "$r"
cat >>"$r/mise.toml" <<'TOML'

[tasks."check:planted"]
run = "true"
TOML
{
  printf '[tasks.check]\ndepends = ["check:alpha", "lint:alpha", "scan:alpha", "check:planted"]\n'
  sed -n '/^\[tasks.test\]/,$p' "$r/mise.toml"
} >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
run_checker "$r" >/dev/null || fail "t3: a registered task should pass: $(cat "$tmp/err")"
echo "ok: t3 the same task passes once the aggregate depends on it"

# ---------------------------------------------------------------------------
# t3b: registration is transitive over the edge kinds that SCHEDULE a task —
#      depends and depends_post — and over a wildcard dependency. `wait_for`
#      only waits for a task already scheduled (mise's task-configuration
#      reference), so a task named only there is not run by the gate.
# ---------------------------------------------------------------------------
for kind in depends depends_post wait_for; do
  r="$tmp/r3b-$kind"
  mkrepo "$r"
  {
    printf '[tasks.check]\ndepends = ["check:alpha", "lint:alpha", "scan:alpha", "check:group"]\n\n'
    printf '[tasks."check:group"]\n%s = ["check:planted"]\nrun = "true"\n\n' "$kind"
    printf '[tasks."check:planted"]\nrun = "true"\n\n'
    sed -n '/^\[tasks.test\]/,$p' "$r/mise.toml"
  } >"$r/mise.toml.new"
  mv "$r/mise.toml.new" "$r/mise.toml"
  grep -q '^depends = \["check:alpha", "lint:alpha", "scan:alpha", "check:group"\]' "$r/mise.toml" \
    || fail "t3b: the $kind fixture lost its aggregate edge"
  run_checker "$r" >/dev/null
  rc=$?
  case $kind in
    wait_for)
      [ "$rc" = 1 ] || fail "t3b: a task named only in wait_for is not scheduled, so it should be exit 1, got $rc: $(cat "$tmp/err")"
      grep -q 'check:planted' "$tmp/err" || fail "t3b: the wait_for-only task was not named as unregistered"
      ;;
    *)
      [ "$rc" = 0 ] || fail "t3b: a task reached through $kind should pass: $(cat "$tmp/err")"
      ;;
  esac
done
r="$tmp/r3b-wild"
mkrepo "$r"
{
  printf '[tasks.check]\ndepends = ["check:*", "lint:alpha", "scan:alpha"]\n\n'
  printf '[tasks."check:planted"]\nrun = "true"\n\n'
  sed -n '/^\[tasks.test\]/,$p' "$r/mise.toml"
} >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
run_checker "$r" >/dev/null \
  || fail "t3b: a task matched by a wildcard dependency should pass: $(cat "$tmp/err")"
echo "ok: t3b depends, depends_post and a wildcard register; wait_for does not"

# ---------------------------------------------------------------------------
# t3c: TOML the parser must not misread. A task header followed by a trailing
#      comment is still a header (dropping it would let the task go unchecked),
#      and a `#` inside a quoted dependency (mise accepts "task --args"
#      entries) is part of the value, not a comment: treating it as one
#      swallows the rest of the array and the next task header with it.
# ---------------------------------------------------------------------------
r="$tmp/r3c-header-comment"
mkrepo "$r"
printf '\n[tasks."check:planted"] # not yet wired\nrun = "true"\n' >>"$r/mise.toml"
run_checker "$r" >/dev/null
rc=$?
[ "$rc" = 1 ] || fail "t3c: a header with a trailing comment declares a task; unregistered, it should be exit 1, got $rc: $(cat "$tmp/err")"
grep -q 'check:planted' "$tmp/err" || fail "t3c: the task declared with a trailing comment was not named"

r="$tmp/r3c-hash-in-value"
mkrepo "$r"
{
  printf '[tasks.check]\ndepends = ["check:alpha", \x27check:x --grep # nightly\x27, "lint:alpha", "scan:alpha"]\n\n'
  printf '[tasks."check:x"]\nrun = "true"\n\n'
  sed -n '/^\[tasks.test\]/,$p' "$r/mise.toml"
} >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
grep -q "'check:x --grep # nightly'" "$r/mise.toml" || fail "t3c: the fixture lost its quoted '#'"
run_checker "$r" >/dev/null || fail "t3c: a '#' inside a quoted dependency is part of the value; the fixture should pass: $(cat "$tmp/err")"
grep -q 'names no task' "$tmp/err" && fail "t3c: a '#' inside a quoted dependency truncated the array: $(cat "$tmp/err")"
echo "ok: t3c a trailing header comment and a '#' inside a quoted name parse as TOML does"

# ---------------------------------------------------------------------------
# t4: TEXT IS NOT WIRING. A task named in the aggregate's description, in a
#     comment, or inside another task's run body is not registered by that.
#     (The lesson tests/test-check-guard-wiring.sh g4b records, one level up.)
# ---------------------------------------------------------------------------
for name in described commented in-run-body; do
  r="$tmp/r4-$name"
  mkrepo "$r"
  grep -q "check:$name" "$r/mise.toml" \
    || fail "t4: the fixture no longer mentions check:$name — this case would prove nothing"
  printf '\n[tasks."check:%s"]\nrun = "true"\n' "$name" >>"$r/mise.toml"
  run_checker "$r" >/dev/null
  rc=$?
  [ "$rc" = 1 ] || fail "t4: check:$name is only mentioned in text; unregistered, it should be exit 1, got $rc: $(cat "$tmp/err")"
  grep -q "check:$name" "$tmp/err" || fail "t4: check:$name was not named as unregistered"
done
echo "ok: t4 a description, a comment, and a run body are text, not edges"

# ---------------------------------------------------------------------------
# t5: an un-namespaced task nothing depends on is not the guard's business,
#     and a `depends` entry naming no task is noted rather than failing.
# ---------------------------------------------------------------------------
r="$tmp/r5"
mkrepo "$r"
grep -q '^\[tasks.release\]' "$r/mise.toml" || fail "t5: the fixture lost its un-namespaced task"
printf '\n[tasks.docs]\nrun = "true"\n' >>"$r/mise.toml"
run_checker "$r" >/dev/null || fail "t5: an unregistered un-namespaced task should not fail: $(cat "$tmp/err")"
{
  printf '[tasks.check]\ndepends = ["check:alpha", "lint:alpha", "scan:alpha", "check:vanished"]\n\n'
  sed -n '/^\[tasks.test\]/,$p' "$r/mise.toml"
} >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
run_checker "$r" >/dev/null || fail "t5: a dangling dependency should be a note, not a failure: $(cat "$tmp/err")"
grep -q 'check:vanished' "$tmp/err" || fail "t5: the dangling dependency was not noted"
echo "ok: t5 the namespaces bound the scan, and a dangling edge is noted"

# ---------------------------------------------------------------------------
# t6: every input that would make the scan vacuous fails CLOSED (exit 5)
#     rather than reporting a clean pass over nothing (REQ-H1.3).
# ---------------------------------------------------------------------------
r="$tmp/r6"
mkrepo "$r"
run_checker "$r" >/dev/null || fail "t6: the baseline fixture should pass first: $(cat "$tmp/err")"

rm -f "$r/mise.toml"
run_checker "$r" >/dev/null
[ "$?" = 5 ] || fail "t6: a missing mise.toml should be exit 5"

printf '# no tasks here\n[tools]\nshellcheck = "0.11.0"\n' >"$r/mise.toml"
run_checker "$r" >/dev/null
[ "$?" = 5 ] || fail "t6: a mise.toml with zero tasks should be exit 5"
grep -q 'zero tasks' "$tmp/err" || fail "t6: the zero-task verdict was not stated: $(cat "$tmp/err")"

printf '[tasks."check:alpha"]\nrun = "true"\n' >"$r/mise.toml"
run_checker "$r" >/dev/null
[ "$?" = 5 ] || fail "t6: a mise.toml with no check aggregate should be exit 5"

printf '[tasks.check]\ndepends = ["test"]\n\n[tasks.test]\nrun = "true"\n' >"$r/mise.toml"
run_checker "$r" >/dev/null
[ "$?" = 5 ] || fail "t6: a mise.toml with no namespaced task at all should be exit 5, not a clean pass"

# A string the file never closes would otherwise hide every later task behind
# a clean pass; so would a comment holding an odd number of triple quotes.
mkrepo "$r"
printf '\n[tasks.build]\nrun = """\necho building\n\n[tasks."check:planted"]\nrun = "true"\n' >>"$r/mise.toml"
run_checker "$r" >/dev/null
[ "$?" = 5 ] || fail "t6: an unterminated triple-quoted string should be exit 5, not a clean pass over the tasks it hides"
grep -q 'unterminated' "$tmp/err" || fail "t6: the unterminated-string verdict was not stated: $(cat "$tmp/err")"

mkrepo "$r"
printf "\n# don'''t read this comment as a string\n[tasks.\"check:planted\"]\nrun = \"true\"\n" >>"$r/mise.toml"
run_checker "$r" >/dev/null
rc=$?
[ "$rc" = 1 ] || fail "t6: a comment with an odd number of triple quotes is still a comment; the planted task should be exit 1, got $rc: $(cat "$tmp/err")"
grep -q 'check:planted' "$tmp/err" || fail "t6: the task after the odd-quoted comment was not named"
echo "ok: t6 every scan-narrowing input fails closed instead of passing vacuously"

# ---------------------------------------------------------------------------
# t7: usage faults are exit 2, distinct from the fail-closed and failure codes.
# ---------------------------------------------------------------------------
/bin/sh "$CHECKER" --bogus >/dev/null 2>&1
[ "$?" = 2 ] || fail "t7: an unknown argument should be exit 2"
/bin/sh "$CHECKER" --repo-root >/dev/null 2>&1
[ "$?" = 2 ] || fail "t7: --repo-root without a directory should be exit 2"
/bin/sh "$CHECKER" --repo-root "$tmp/r6" --aggregate 'bad name' >/dev/null 2>&1
[ "$?" = 2 ] || fail "t7: an aggregate name outside the task-name grammar should be exit 2"
echo "ok: t7 usage faults exit 2"

# ---------------------------------------------------------------------------
# t8: task names are PR-controlled text that reaches stderr. A literal-string
#     key holding backslash-escape text must not come out as a live escape
#     sequence (dash's echo would expand it), nor may control bytes pass.
# ---------------------------------------------------------------------------
r="$tmp/r8"
mkrepo "$r"
printf "\n[tasks.'check:x\\\\033[31mred\\\\033[0m']\nrun = 'true'\n" >>"$r/mise.toml"
grep -q 'check:x\\033' "$r/mise.toml" || fail "t8: the fixture lost its backslash-escape text"
run_checker "$r" >/dev/null
rc=$?
[ "$rc" = 1 ] || fail "t8: the escape-named task is unregistered and should be exit 1, got $rc: $(cat "$tmp/err")"
if od -An -c "$tmp/err" | grep -q '033'; then
  fail "t8: a task name's backslash-escape text reached stderr as a live ESC byte"
fi
grep -q 'check:x' "$tmp/err" || fail "t8: the escape-named task was not named at all: $(cat "$tmp/err")"
echo "ok: t8 task-name text reaches stderr inert, never as a live escape"

echo "ALL PASS: check-task-registration"
