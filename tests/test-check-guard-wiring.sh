#!/bin/bash
# Tests for scripts/check-guard-wiring.sh — the guard-reachability check.
#
# This file carries an obligation the others do not: the script under test
# exists because guards that cannot fail keep shipping, so a test suite that
# cannot fail here would be the same defect one level up. Every positive
# assertion below is paired with a planted negative that the guard must catch.
#
# Two cases are load-bearing beyond ordinary coverage:
#   g4  reachability, not presence — a guard wired into a task nothing depends
#       on is the exact state the check exists to catch, and a search over the
#       task file rather than its graph would pass it;
#   g4b a guard NAMED in a task's description but run by nothing. An earlier
#       revision of the script matched task text as a blob and accepted it,
#       which made the guard vacuous in its own terms.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-guard-wiring.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
CG="$REPO_ROOT/scripts/check-guard-wiring.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CG" ] || fail "scripts/check-guard-wiring.sh missing or not executable"
for t in jq mise; do
  command -v "$t" >/dev/null 2>&1 || fail "$t is required to exercise the task-graph reader"
done

# An unchecked mktemp leaves $tmp empty and the trap then runs `rm -rf ""`.
tmp=$(mktemp -d) || fail "mktemp -d failed"
[ -n "$tmp" ] && [ -d "$tmp" ] || fail "mktemp -d produced no directory"
trap 'rm -rf "$tmp"' EXIT

# mkrepo <dir> [extra-task-name] [extra-task-run] [wf-ext]
#   A minimal tree with the three surfaces the guard reads. The optional extra
#   task is appended AND added to the aggregate's depends, built by generating
#   the file rather than patching it: `sed 's/…\n…/'` inserts a literal `n`
#   on BSD sed, so a fixture patched that way is silently malformed on macOS
#   and the case it supports stops testing anything there.
mkrepo() {
  mr=$1
  mr_task=${2:-}
  mr_run=${3:-}
  mr_ext=${4:-yml}
  rm -rf "$mr"
  mkdir -p "$mr/scripts" "$mr/.github/workflows"
  {
    printf '[tasks.check]\ndepends = [\n  "check:alpha",\n'
    [ -n "$mr_task" ] && printf '  "%s",\n' "$mr_task"
    printf ']\n\n[tasks."check:alpha"]\nrun = "/bin/sh scripts/check-alpha.sh"\n'
    printf '\n[tasks."check:orphaned"]\nrun = "/bin/sh scripts/check-beta.sh"\n'
    if [ -n "$mr_task" ]; then
      printf '\n[tasks."%s"]\nrun = "%s"\n' "$mr_task" "$mr_run"
    fi
  } >"$mr/mise.toml"
  printf 'jobs:\n  build:\n    steps:\n      - run: /bin/sh scripts/check-gamma.sh\n' \
    >"$mr/.github/workflows/ci.$mr_ext"
  for g in alpha gamma; do
    printf '#!/bin/sh\nexit 0\n' >"$mr/scripts/check-$g.sh"
    chmod +x "$mr/scripts/check-$g.sh"
  done
}

run_cg() { /bin/sh "$CG" --repo-root "$1" 2>"$tmp/err"; }

# ---------------------------------------------------------------------------
# g1: the real repository passes. If this ever fails, a guard has come loose.
# ---------------------------------------------------------------------------
/bin/sh "$CG" --repo-root "$REPO_ROOT" >/dev/null 2>"$tmp/err" \
  || fail "g1: the real repo should pass, got: $(cat "$tmp/err")"
echo "ok: g1 the repository's own guards are all reached"

# ---------------------------------------------------------------------------
# g2: a guard wired into nothing is caught, and named. POSITIVE CONTROL for
#     every passing case below.
# ---------------------------------------------------------------------------
r="$tmp/r2"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
run_cg "$r" >/dev/null && fail "g2: an unwired guard was not caught"
grep -q 'check-planted.sh' "$tmp/err" \
  || fail "g2: the diagnostic does not name the unwired guard: $(cat "$tmp/err")"
echo "ok: g2 an unwired guard fails the check and is named"

# ---------------------------------------------------------------------------
# g3: the same guard, run by a task the aggregate depends on, passes — which
#     proves g2's failure came from the wiring and not the file's existence.
# ---------------------------------------------------------------------------
r="$tmp/r3"
mkrepo "$r" "check:planted" "/bin/sh scripts/check-planted.sh"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
run_cg "$r" >/dev/null || fail "g3: a properly wired guard should pass: $(cat "$tmp/err")"
echo "ok: g3 the same guard passes once the aggregate depends on it"

# ---------------------------------------------------------------------------
# g4: REACHABILITY, NOT PRESENCE. The guard is named in the run body of a task
#     that exists and is spelled correctly — but nothing depends on that task.
# ---------------------------------------------------------------------------
r="$tmp/r4"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-beta.sh"
grep -q 'check-beta.sh' "$r/mise.toml" \
  || fail "g4: the fixture no longer names the guard in mise.toml — this case would prove nothing"
run_cg "$r" >/dev/null \
  && fail "g4: a guard in an unreachable task passed — the check is a search, not a reachability walk"
grep -q 'check-beta.sh' "$tmp/err" || fail "g4: the unreachable guard was not named"
echo "ok: g4 a guard in a task the aggregate never reaches still fails"

# ---------------------------------------------------------------------------
# g4b: A DESCRIPTION IS NOT EXECUTION. The guard is named in a reachable
#      task's description and run by nothing. Regression: an earlier revision
#      read task text as a blob and passed this, which made the check vacuous
#      in exactly its own terms.
# ---------------------------------------------------------------------------
r="$tmp/r4b"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-ghost.sh"
cat >>"$r/mise.toml" <<'TOML'

[tasks."check:mentions"]
description = "prose naming scripts/check-ghost.sh without ever running it"
run = "/bin/sh scripts/check-alpha.sh"
TOML
# Make it reachable, so the only reason it could pass is the description.
{
  printf '[tasks.check]\ndepends = ["check:alpha", "check:mentions"]\n\n'
  sed -n '/\[tasks."check:alpha"\]/,$p' "$r/mise.toml"
} >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
grep -q 'check-ghost.sh' "$r/mise.toml" \
  || fail "g4b: the fixture no longer mentions the guard at all — this case would prove nothing"
run_cg "$r" >/dev/null \
  && fail "g4b: a guard named only in a description passed — a description is not execution"
grep -q 'check-ghost.sh' "$tmp/err" || fail "g4b: the merely-mentioned guard was not named"
#      Control: the very same guard, moved into the run body, passes. Without
#      this the case above could pass because the fixture is broken.
r="$tmp/r4c"
mkrepo "$r" "check:mentions" "/bin/sh scripts/check-ghost.sh"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-ghost.sh"
run_cg "$r" >/dev/null \
  || fail "g4b control: the same guard in a run body should pass: $(cat "$tmp/err")"
echo "ok: g4b a description that names a guard is not wiring, but a run body is"

# ---------------------------------------------------------------------------
# g5: a workflow counts as wiring, in BOTH YAML spellings. GitHub accepts
#     .yaml, so matching only .yml would call a wired guard unwired.
# ---------------------------------------------------------------------------
for ext in yml yaml; do
  r="$tmp/r5$ext"
  mkrepo "$r" "" "" "$ext"
  [ -f "$r/.github/workflows/ci.$ext" ] || fail "g5: the .$ext fixture was not written"
  run_cg "$r" >/dev/null || fail "g5: a .$ext workflow-wired guard should pass: $(cat "$tmp/err")"
done
echo "ok: g5 a guard a workflow runs counts as reached, .yml and .yaml alike"

# ---------------------------------------------------------------------------
# g6: the allowlist exempts, and its rot modes fail. An exemption nobody
#     rechecks is how an allowlist becomes a hiding place.
# ---------------------------------------------------------------------------
r="$tmp/r6"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
printf 'check-planted.sh  run by the frobnicator\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null || fail "g6: an allowlisted guard should pass: $(cat "$tmp/err")"
#     An INDENTED entry is still an entry: stripping from the first blank
#     before trimming the leading run would blank the line and drop it.
printf '   check-planted.sh  run by the frobnicator\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null || fail "g6: an indented allowlist entry was silently dropped"
#     rot mode 1: the entry names a script that no longer exists.
printf 'check-planted.sh  x\ncheck-vanished.sh  run by nobody\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null && fail "g6: a stale allowlist entry was accepted"
grep -q 'check-vanished.sh' "$tmp/err" || fail "g6: the stale entry was not named"
#     rot mode 2: the entry names a guard that is in fact wired.
printf 'check-alpha.sh  x\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null && fail "g6: an allowlist entry shadowing a wired guard was accepted"
grep -q 'check-alpha.sh' "$tmp/err" || fail "g6: the redundant entry was not named"
echo "ok: g6 the allowlist exempts (indented too), and both rot modes fail"

# ---------------------------------------------------------------------------
# g7: every input that would make the scan vacuous fails CLOSED (exit 5)
#     rather than reporting a clean pass over nothing.
# ---------------------------------------------------------------------------
r="$tmp/r7"
mkrepo "$r"
run_cg "$r" >/dev/null || fail "g7: the baseline fixture should pass first: $(cat "$tmp/err")"

rm -f "$r/mise.toml"
run_cg "$r" >/dev/null
[ "$?" = 5 ] || fail "g7: a missing mise.toml should be exit 5"

printf '# no tasks here\n' >"$r/mise.toml"
run_cg "$r" >/dev/null
[ "$?" = 5 ] || fail "g7: a mise.toml with zero tasks should be exit 5"

printf '[tasks."check:alpha"]\nrun = "x"\n' >"$r/mise.toml"
run_cg "$r" >/dev/null
[ "$?" = 5 ] || fail "g7: a mise.toml with no check aggregate should be exit 5"

mkrepo "$r"
rm -f "$r"/scripts/check-*.sh
run_cg "$r" >/dev/null
[ "$?" = 5 ] || fail "g7: finding zero guards should be exit 5, not a clean pass"

mkrepo "$r"
rm -rf "$r/.github/workflows"
run_cg "$r" >/dev/null
[ "$?" = 5 ] || fail "g7: a missing workflows directory should be exit 5"
echo "ok: g7 every scan-narrowing input fails closed instead of passing vacuously"

echo "ALL PASS: check-guard-wiring"
