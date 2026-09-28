#!/bin/bash
# Tests for scripts/check-guard-wiring.sh — the guard-reachability check.
#
# This file carries an obligation the others do not: the script under test
# exists because guards that cannot fail keep shipping, so a test suite that
# cannot fail here would be the same defect one level up. Every positive
# assertion below is paired with a planted negative that the guard must catch.
#
# Some cases are load-bearing beyond ordinary coverage:
#   g4  reachability, not presence — a guard wired into a task nothing depends
#       on is the exact state the check exists to catch, and a search over the
#       task file rather than its graph would pass it;
#   g4b a guard NAMED in a task's description but run by nothing. An earlier
#       revision of the script matched task text as a blob and accepted it,
#       which made the guard vacuous in its own terms;
#   g3c a guard reachable only through a `wait_for`, which orders but never
#       runs its target. An earlier revision followed that edge and passed it;
#   g8a/g8b a guard or `mise run` edge named only in a whole-line comment of a
#       reached run body. An earlier revision counted the comment as wiring.
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
# The explicit template is not decoration: BSD mktemp supplies no default one,
# so a bare `mktemp -d` is a usage error on macOS (same reason
# tests/test-check-hook-contracts.sh spells it out).
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-guard-wiring.XXXXXX") || fail "mktemp -d failed"
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
# g3b: an edge made by a RUN BODY, not by a depends list. The script documents
#      that a reached task calling `mise run <task>` extends the closure, and
#      nothing exercised it — so the extraction could have stopped working
#      silently, which is the failure this whole file exists to prevent.
# ---------------------------------------------------------------------------
r="$tmp/r3b"
mkrepo "$r" "check:outer" "mise run check:inner"
cat >>"$r/mise.toml" <<'TOML'

[tasks."check:inner"]
run = "/bin/sh scripts/check-planted.sh"
TOML
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
grep -q 'check-planted.sh' "$r/mise.toml" \
  || fail "g3b: the fixture no longer runs the guard anywhere"
grep -q '"check:inner"' "$r/mise.toml" \
  || fail "g3b: the fixture's inner task is gone"
#      Nothing DEPENDS on check:inner: its only path from the aggregate is the
#      `mise run` call inside check:outer's body. If that edge is not followed,
#      the guard is unreachable and the check must fail.
grep -q 'depends.*check:inner' "$r/mise.toml" \
  && fail "g3b: the fixture gained a depends edge — the run-body path is no longer the only one"
run_cg "$r" >/dev/null \
  || fail "g3b: a guard reachable only through a run-body 'mise run' was not found: $(cat "$tmp/err")"
echo "ok: g3b a run body's own 'mise run' extends the closure"

# ---------------------------------------------------------------------------
# g3c: `wait_for` IS NOT AN EDGE. It orders a task after another only when
#      both are already scheduled; it never causes its target to run. A guard
#      whose task is reachable solely through a wait_for is run by nothing,
#      and counting that edge made the check fail open on exactly its case.
# ---------------------------------------------------------------------------
r="$tmp/r3c"
mkrepo "$r" "check:orderer" "/bin/sh scripts/check-alpha.sh"
cat >>"$r/mise.toml" <<'TOML'
wait_for = ["check:waited"]

[tasks."check:waited"]
run = "/bin/sh scripts/check-planted.sh"
TOML
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-planted.sh"
grep -q 'depends.*check:waited' "$r/mise.toml" \
  && fail "g3c: the fixture gained a depends edge — wait_for is no longer the only path"
run_cg "$r" >/dev/null \
  && fail "g3c: a guard reachable only through wait_for passed — wait_for never runs its target"
grep -q 'check-planted.sh' "$tmp/err" || fail "g3c: the wait_for-only guard was not named"
#      Control: the same fixture with the wait_for spelled as depends passes,
#      so the failure above comes from the edge kind and not a broken fixture.
sed 's/^wait_for = /depends = /' "$r/mise.toml" >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
grep -q '^depends = \["check:waited"\]' "$r/mise.toml" \
  || fail "g3c control: the fixture rewrite did not produce the depends edge"
run_cg "$r" >/dev/null \
  || fail "g3c control: the same guard behind a depends edge should pass: $(cat "$tmp/err")"
#      And behind depends_post, which also schedules its target: the edge kind
#      kept alongside depends must keep counting.
sed 's/^depends = \["check:waited"\]/depends_post = ["check:waited"]/' "$r/mise.toml" >"$r/mise.toml.new"
mv "$r/mise.toml.new" "$r/mise.toml"
grep -q '^depends_post = \["check:waited"\]' "$r/mise.toml" \
  || fail "g3c control: the fixture rewrite did not produce the depends_post edge"
grep -q '^depends = \[$' "$r/mise.toml" \
  || fail "g3c control: the rewrite touched the aggregate's own depends"
run_cg "$r" >/dev/null \
  || fail "g3c control: the same guard behind a depends_post edge should pass: $(cat "$tmp/err")"
echo "ok: g3c a wait_for edge does not reach a task, but depends and depends_post edges do"

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
#     Every entry exempts, not just the last one. The list is read as one
#     newline-separated string, so a membership test written in terms of
#     space-delimited words matches only the final line.
printf '#!/bin/sh\nexit 0\n' >"$r/scripts/check-second.sh"
printf 'check-planted.sh  x\ncheck-second.sh  y\n' >"$r/scripts/guard-wiring-allow.txt"
run_cg "$r" >/dev/null \
  || fail "g6: a non-final allowlist entry was dropped: $(cat "$tmp/err")"
rm -f "$r/scripts/check-second.sh"
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

# ---------------------------------------------------------------------------
# g8: the check must agree with what `mise run check` ACTUALLY runs. Each case
#     below also runs the fixture's gate for real: the planted guard leaves a
#     marker when executed, so the expected verdict is pinned to mise itself
#     rather than to a reading of its documentation.
# ---------------------------------------------------------------------------
plant() {
  # shellcheck disable=SC2016 # the expansion belongs to the planted script
  printf '#!/bin/sh\ntouch "$(dirname "$0")/ran-%s"\n' "$2" >"$1/scripts/check-$2.sh"
}
# expect_mise <rc> <repo> <guard> <label>: the fixture's own `mise run check`
# gives 0 when it ran the guard, 1 when it passed without running it, 2 when
# the gate itself failed. The user's global mise config is kept out, so the
# verdict is the fixture's alone.
expect_mise() {
  rm -f "$2/scripts/ran-$3"
  if (cd "$2" && MISE_TRUSTED_CONFIG_PATHS="$2" MISE_GLOBAL_CONFIG_FILE=/dev/null \
    MISE_CONFIG_DIR="$tmp/no-mise-config" MISE_CEILING_PATHS="$tmp" \
    mise run check >"$tmp/mise-out" 2>&1); then
    if [ -f "$2/scripts/ran-$3" ]; then mr_rc=0; else mr_rc=1; fi
  else
    mr_rc=2
  fi
  [ "$mr_rc" = "$1" ] \
    || fail "$4: the fixture's own gate gave $mr_rc, expected $1: $(cat "$tmp/mise-out")"
}
# expect_cg <rc> <repo> <label>: the guard-wiring verdict, exit code exact so
# a fail-closed 5 never passes for a 1.
expect_cg() {
  run_cg "$2" >/dev/null
  cg_rc=$?
  [ "$cg_rc" = "$1" ] \
    || fail "$3: check-guard-wiring gave $cg_rc, expected $1: $(cat "$tmp/err")"
}
# wired <dir> <check:outer run body> [appendix]: check:outer sits in the
# aggregate. mkrepo writes check:outer's table last, so an appendix that opens
# with a `depends` line extends check:outer.
wired() {
  mkrepo "$1" "check:outer" "$2"
  printf '%s\n' "${3:-}" >>"$1/mise.toml"
  plant "$1" planted
}
inner='
[tasks."check:inner"]
run = "/bin/sh scripts/check-planted.sh"'

#     g8a: A COMMENTED-OUT `mise run` IS NOT AN EDGE, indented or not, and the
#     same line uncommented is.
r="$tmp/r8a"
for body in '# mise run check:inner' '  # mise run check:inner'; do
  wired "$r" "$body\n/bin/sh scripts/check-alpha.sh" "$inner"
  expect_mise 1 "$r" planted "g8a '$body'"
  expect_cg 1 "$r" "g8a '$body'"
  grep -q 'check-planted.sh' "$tmp/err" || fail "g8a '$body': the comment-only guard was not named"
done
wired "$r" 'mise run check:inner\n/bin/sh scripts/check-alpha.sh' "$inner"
expect_mise 0 "$r" planted "g8a control"
expect_cg 0 "$r" "g8a control"
echo "ok: g8a a commented-out 'mise run' is not an edge, the same line uncommented is"

#     g8b: A COMMENTED-OUT GUARD IS NOT RUN.
r="$tmp/r8b"
wired "$r" '# /bin/sh scripts/check-planted.sh\n/bin/sh scripts/check-alpha.sh'
expect_mise 1 "$r" planted "g8b"
expect_cg 1 "$r" "g8b"
grep -q 'check-planted.sh' "$tmp/err" || fail "g8b: the comment-only guard was not named"
wired "$r" '/bin/sh scripts/check-planted.sh\n/bin/sh scripts/check-alpha.sh'
expect_mise 0 "$r" planted "g8b control"
expect_cg 0 "$r" "g8b control"
echo "ok: g8b a guard named only in a run-body comment is not wiring"

#     g8c: every spelling of a call that runs its target is an edge: each
#     `:::` segment, `mise r`, a leading flag with a separate value, a quoted
#     task name. A `mise run` that is only part of another word is not.
r="$tmp/r8c"
for body in \
  'mise run check:alpha ::: check:alpha --verbose ::: check:inner' \
  'mise r check:inner' \
  'mise run -j 2 \"check:inner\"'; do
  wired "$r" "$body" "$inner"
  expect_mise 0 "$r" planted "g8c '$body'"
  expect_cg 0 "$r" "g8c '$body'"
done
wired "$r" 'echo promise run check:inner' "$inner"
expect_mise 1 "$r" planted "g8c 'promise run'"
expect_cg 1 "$r" "g8c 'promise run'"
echo "ok: g8c ':::' segments, 'mise r', flags and quoting are edges; 'promise run' is not"

#     g8e: a task ALIAS resolves to its task, from a depends list and from a
#     run body alike; an alias nothing defines resolves to nothing.
r="$tmp/r8e"
wired "$r" 'mise run pr' '
depends = ["pd"]

[tasks."check:by-depends"]
alias = "pd"
run = "/bin/sh scripts/check-planted.sh"

[tasks."check:by-run"]
alias = ["x", "pr"]
run = "/bin/sh scripts/check-second.sh"'
plant "$r" second
expect_mise 0 "$r" planted "g8e depends alias"
expect_mise 0 "$r" second "g8e run-body alias"
expect_cg 0 "$r" "g8e"
wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"nope\"]$inner"
expect_mise 2 "$r" planted "g8e unknown alias"
expect_cg 1 "$r" "g8e unknown alias"
grep -q 'nope' "$tmp/err" || fail "g8e: the unresolvable alias was not reported"
echo "ok: g8e a task alias resolves to its task, an unknown one to nothing"

#     g8f: GLOB edges expand the way mise expands them: a trailing `*` spans
#     the `:` separator, an inner `*` and `?` never do, classes and braces are
#     honoured, aliases match too, and other characters are literal.
r="$tmp/r8f"
wired "$r" '/bin/sh scripts/check-alpha.sh' 'depends = ["guard:*"]

[tasks."guard:deep:planted"]
run = "/bin/sh scripts/check-planted.sh"'
expect_mise 0 "$r" planted "g8f 'guard:*'"
expect_cg 0 "$r" "g8f 'guard:*'"
target='
[tasks."guard:p"]
alias = "plant-alias"
run = "/bin/sh scripts/check-planted.sh"'
for pat in 'guard:?' 'guard:[pq]' 'guard:[!q]' 'guard:{p,zz}' 'plant-*' 'g*:p'; do
  wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"$pat\"]$target"
  expect_mise 0 "$r" planted "g8f '$pat'"
  expect_cg 0 "$r" "g8f '$pat'"
done
for pat in 'guard?p' 'gu*p' 'guard.*' 'nomatch:*'; do
  wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"$pat\"]$target"
  expect_mise 2 "$r" planted "g8f '$pat'"
  expect_cg 1 "$r" "g8f '$pat'"
  grep -q 'check-planted.sh' "$tmp/err" || fail "g8f '$pat': the unreached guard was not named"
  grep -qF "$pat" "$tmp/err" || fail "g8f '$pat': the glob matching nothing was not reported"
done
echo "ok: g8f a glob edge expands to the tasks mise would run, and only those"

#     g8g: task shapes `mise tasks --json` renders beyond a plain name: a
#     hidden task, a depends entry carrying arguments, and a structured
#     `{ task = ... }` run entry.
r="$tmp/r8g"
wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"guard:p\"]$target
hide = true"
expect_mise 0 "$r" planted "g8g hidden"
expect_cg 0 "$r" "g8g hidden"
wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"guard:p --flag\"]$target"
expect_mise 0 "$r" planted "g8g depends arguments"
expect_cg 0 "$r" "g8g depends arguments"
wired "$r" '/bin/sh scripts/check-alpha.sh' "depends = [\"check:structured\"]$target

[tasks.\"check:structured\"]
run = [{ task = \"guard:p\" }]"
expect_mise 0 "$r" planted "g8g structured run"
expect_cg 0 "$r" "g8g structured run"
echo "ok: g8g hidden tasks, depends arguments and structured run entries are followed"

echo "ALL PASS: check-guard-wiring"
