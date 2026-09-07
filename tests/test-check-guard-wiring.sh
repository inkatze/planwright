#!/bin/bash
# Tests for scripts/check-guard-wiring.sh — the guard-reachability check.
#
# This file carries an obligation the others do not: the script under test
# exists because guards that cannot fail keep shipping, so a test suite that
# cannot fail here would be the same defect one level up. Every positive
# assertion below is paired with a planted negative that the guard must catch,
# and the reachability case (g4) is the one that separates this from a grep:
# a guard named in mise.toml but wired into a task `check` never depends on is
# exactly the state being guarded against.
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

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# mkrepo <dir> — a minimal tree with the three surfaces the guard reads: a
# mise.toml with a `check` aggregate, a workflows directory, and scripts/.
mkrepo() {
  mr=$1
  mkdir -p "$mr/scripts" "$mr/.github/workflows"
  cat >"$mr/mise.toml" <<'TOML'
[tasks.check]
depends = [
  "check:alpha",
]

[tasks."check:alpha"]
run = "/bin/sh scripts/check-alpha.sh"

[tasks."check:orphaned"]
run = "/bin/sh scripts/check-beta.sh"
TOML
  cat >"$mr/.github/workflows/ci.yml" <<'YML'
jobs:
  build:
    steps:
      - run: /bin/sh scripts/check-gamma.sh
YML
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
#     every passing case below: without this, a guard that had silently
#     stopped scanning would make all of them pass.
# ---------------------------------------------------------------------------
r="$tmp/r2"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
run_cg "$r" >/dev/null && fail "g2: an unwired guard was not caught"
grep -q 'check-planted.sh' "$tmp/err" \
  || fail "g2: the diagnostic does not name the unwired guard: $(cat "$tmp/err")"
echo "ok: g2 an unwired guard fails the check and is named"

# ---------------------------------------------------------------------------
# g3: the same guard, wired into a task the aggregate depends on, passes. This
#     is what proves g2's failure came from the wiring and not from the file's
#     mere existence.
# ---------------------------------------------------------------------------
r="$tmp/r3"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
cat >>"$r/mise.toml" <<'TOML'

[tasks."check:planted"]
run = "/bin/sh scripts/check-planted.sh"
TOML
sed -i.bak 's/  "check:alpha",/  "check:alpha",\n  "check:planted",/' "$r/mise.toml"
run_cg "$r" >/dev/null || fail "g3: a properly wired guard should pass: $(cat "$tmp/err")"
echo "ok: g3 the same guard passes once the aggregate depends on it"

# ---------------------------------------------------------------------------
# g4: REACHABILITY, NOT PRESENCE. The guard is named in mise.toml, in a task
#     that exists and is spelled correctly — but nothing depends on that task.
#     A grep over mise.toml would pass this. It is the exact state the check
#     exists to catch, so it must fail.
# ---------------------------------------------------------------------------
r="$tmp/r4"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-beta.sh"
grep -q 'check-beta.sh' "$r/mise.toml" \
  || fail "g4: the fixture no longer names the guard in mise.toml — this case would prove nothing"
run_cg "$r" >/dev/null \
  && fail "g4: a guard in an unreachable task passed — the check is a grep, not a reachability walk"
grep -q 'check-beta.sh' "$tmp/err" || fail "g4: the unreachable guard was not named"
echo "ok: g4 a guard in a task the aggregate never reaches still fails"

# ---------------------------------------------------------------------------
# g5: a workflow counts as wiring, since CI runs it directly.
# ---------------------------------------------------------------------------
r="$tmp/r5"
mkrepo "$r"
run_cg "$r" >/dev/null || fail "g5: a workflow-wired guard should pass: $(cat "$tmp/err")"
grep -q 'check-gamma.sh' "$r/.github/workflows/ci.yml" \
  || fail "g5: the fixture no longer wires a guard through a workflow"
echo "ok: g5 a guard a workflow runs counts as reached"

# ---------------------------------------------------------------------------
# g6: the allowlist exempts, and its two rot modes both fail. An exemption
#     nobody rechecks is how an allowlist becomes a hiding place.
# ---------------------------------------------------------------------------
r="$tmp/r6"
mkrepo "$r"
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
printf 'check-planted.sh  run by the frobnicator\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null || fail "g6: an allowlisted guard should pass: $(cat "$tmp/err")"
#     rot mode 1: the entry names a script that no longer exists.
printf 'check-planted.sh  run by the frobnicator\ncheck-vanished.sh  run by nobody\n' \
  >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null && fail "g6: a stale allowlist entry was accepted"
grep -q 'check-vanished.sh' "$tmp/err" || fail "g6: the stale entry was not named"
#     rot mode 2: the entry names a guard that is in fact wired.
printf 'check-alpha.sh  run by the frobnicator\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null && fail "g6: an allowlist entry shadowing a wired guard was accepted"
grep -q 'check-alpha.sh' "$tmp/err" || fail "g6: the redundant entry was not named"
echo "ok: g6 the allowlist exempts, and both of its rot modes fail"

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
