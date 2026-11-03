#!/bin/bash
# Tests for scripts/mc-eval-cadence.sh and its wiring: the eval suite's
# completeness check, a ledger record per head, the pre-ready-flip step that
# refuses a gated unit's flip on a red or missing record, the manual sweep's
# inventory row, and CI running only the deterministic checks
# (mission-control REQ-B1.1, REQ-F1.7, REQ-F1.8, REQ-I1.5 through the suite;
# the cadence and CI wiring per the bundle's Task 15).
#
# Hermetic: the suite runs under the shared stub tmux; every ledger is a
# temporary file; no model, no API key.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SCRIPT="$repo_root/scripts/mc-eval-cadence.sh"
FIXTURE="$repo_root/tests/behavioral-evals/fixtures/mission-control"
STUB="$repo_root/tests/behavioral-evals/lib/tmux-stub.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# A disposable checkout to give the step a head, isolated from the host's git
# configuration.
gitx() {
  env -u GIT_DIR -u GIT_WORK_TREE HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git "$@"
}
mkdir -p "$tmp/home"
wt="$tmp/wt"
gitx -c init.defaultBranch=main init -q "$wt" || exit 1
printf 'x\n' >"$wt/f"
gitx -C "$wt" add f && gitx -C "$wt" commit -q -m one || exit 1
head1=$(gitx -C "$wt" rev-parse HEAD)

# A one-arm suite: the real stand-in and grade, one persona, a test spec with
# one [Gherkin] entry, so a suite run through the stub harness stays cheap.
mini="$tmp/mini"
mkdir -p "$mini/personas"
cp "$FIXTURE/skill.sh" "$FIXTURE/grade.jq" "$FIXTURE/gated-specs" "$mini/"
cp "$FIXTURE/personas/status-form.persona" "$mini/personas/"
sed 's/^personas=.*/personas=status-form/' "$FIXTURE/fixture.conf" >"$mini/fixture.conf"
cat >"$tmp/mini-test-spec.md" <<'EOF'
# Mini — Test Spec

### REQ-F1.3 — One fixed status form [Gherkin]

Status on request renders decisions, then landed, then moving.

### REQ-F1.9 — A script outcome [test]

Not an arm.
EOF

run() {
  OUT=$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$tmp/state" \
    BEHAVIORAL_EVAL_WORKBASE="$tmp/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 /bin/bash "$SCRIPT" "$@" 2>&1)
  RC=$?
}
mkdir -p "$tmp/state" "$tmp/wb"

# --- completeness --------------------------------------------------------
run complete
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "every [Gherkin] arm of the mission-control test spec has exactly one fixture"
else
  fail "the shipped suite is incomplete (exit $RC): $OUT"
fi

gap="$tmp/gap"
cp -R "$FIXTURE" "$gap"
sed -i.bak 's/ status-form / /' "$gap/fixture.conf" && rm -f "$gap/fixture.conf.bak"
run complete --fixture "$gap"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qx "missing	REQ-F1.3"; then
  ok "a [Gherkin] arm with no fixture fails the completeness check, named"
else
  fail "a dropped arm was not caught (exit $RC): $OUT"
fi

printf 'arm=REQ-F1.3\nexpertise=expert\nanswer.1=status\n' >"$gap/personas/extra.persona"
sed -i.bak 's/^personas=/personas=status-form extra /' "$gap/fixture.conf" && rm -f "$gap/fixture.conf.bak"
run complete --fixture "$gap"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qx "duplicate	REQ-F1.3"; then
  ok "two fixtures for one arm fail the completeness check"
else
  fail "a duplicated arm was not caught (exit $RC): $OUT"
fi

sed -i.bak 's/^arm=.*/arm=REQ-F1.9/' "$gap/personas/extra.persona" && rm -f "$gap/personas/extra.persona.bak"
run complete --fixture "$gap"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^orphan	extra	names REQ-F1.9, not a \[Gherkin\] arm"; then
  ok "a fixture naming a non-[Gherkin] entry fails the completeness check"
else
  fail "an orphan fixture was not caught (exit $RC): $OUT"
fi

# --- the step: ungated, missing, green, red ------------------------------
ledger="$tmp/ledger.tsv"
OUT=$(PLANWRIGHT_STEP_SPEC=custom-steps PLANWRIGHT_STEP_WORKTREE="$wt" /bin/bash "$SCRIPT" step --ledger "$ledger" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "not gated: custom-steps" ] && [ ! -e "$ledger" ]; then
  ok "an ungated spec's unit passes the step and records nothing"
else
  fail "an ungated unit: exit $RC, $OUT"
fi

for s in mission-control review-desk spec-currency environment-broker night-shift state-source-adapters; do
  if /bin/bash "$SCRIPT" gated "$s"; then ok "$s is gated"; else fail "$s is not gated"; fi
done
if /bin/bash "$SCRIPT" gated tower-comms; then fail "tower-comms is gated"; else ok "an unrelated spec is not gated"; fi

stepx() {
  OUT=$(PLANWRIGHT_STEP_SPEC="$1" PLANWRIGHT_STEP_WORKTREE="$wt" BEHAVIORAL_EVAL_TMUX="${2:-$STUB}" \
    BEHAVIORAL_EVAL_TMUX_STATE="$tmp/state" BEHAVIORAL_EVAL_WORKBASE="$tmp/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
    /bin/bash "$SCRIPT" step --ledger "$ledger" --fixture "$mini" --test-spec "$tmp/mini-test-spec.md" 2>&1)
  RC=$?
}

# A suite that cannot run writes no record, and the missing record refuses.
stepx mission-control "$tmp/no-such-tmux"
if [ "$RC" -ne 0 ] && [ ! -s "$ledger" ] && printf '%s\n' "$OUT" | grep -q "missing eval record"; then
  ok "a missing record the suite cannot fill refuses the flip and writes nothing"
else
  fail "a suite that could not run: exit $RC, ledger $(cat "$ledger" 2>/dev/null), $OUT"
fi

stepx mission-control
rows=$(awk 'END { print NR }' "$ledger" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$rows" = 1 ] && awk -F '\t' -v h="$head1" '$2 == h && $3 == "mission-control" && $4 == "pass"' "$ledger" | grep -q .; then
  ok "with no record the step runs the suite and records a green run for the head"
else
  fail "a first step run: exit $RC, ledger $(cat "$ledger" 2>/dev/null), $OUT"
fi

stepx night-shift
if [ "$RC" -eq 0 ] && [ "$(awk 'END { print NR }' "$ledger")" = 1 ] && printf '%s\n' "$OUT" | grep -q "^green eval record"; then
  ok "a green record on the head passes a follow-on unit without a re-run"
else
  fail "a recorded green head: exit $RC, $OUT"
fi

printf 'x2\n' >"$wt/f"
gitx -C "$wt" commit -q -am two || exit 1
broken="$tmp/broken"
cp -R "$mini" "$broken"
printf 'false\n' >"$broken/grade.jq"
OUT=$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$tmp/state" BEHAVIORAL_EVAL_WORKBASE="$tmp/wb" \
  BEHAVIORAL_EVAL_POLL_SLEEP=0 /bin/bash "$SCRIPT" run --worktree "$wt" --ledger "$ledger" \
  --fixture "$broken" --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 1 ] && [ "$(awk -F '\t' 'END { print $4 }' "$ledger")" = fail ]; then
  ok "a seeded failing arm records a red run"
else
  fail "a failing suite: exit $RC, $OUT"
fi
stepx review-desk
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^red eval record"; then
  ok "a red record on the head refuses a follow-on unit's flip"
else
  fail "a red head: exit $RC, $OUT"
fi
stepx mission-control
if [ "$RC" -eq 1 ] && [ "$(awk 'END { print NR }' "$ledger")" = 2 ]; then
  ok "a red record is not silently re-run at the flip"
else
  fail "a red head re-ran or passed: exit $RC, $OUT"
fi

incomplete="$tmp/incomplete"
cp -R "$mini" "$incomplete"
sed -i.bak 's/^personas=.*/personas=/' "$incomplete/fixture.conf" && rm -f "$incomplete/fixture.conf.bak"
OUT=$(/bin/bash "$SCRIPT" run --worktree "$wt" --ledger "$ledger" --fixture "$incomplete" \
  --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 1 ] && awk -F '\t' 'END { exit !($4 == "fail" && $5 ~ /^incomplete/) }' "$ledger"; then
  ok "an incomplete suite records a red run"
else
  fail "an incomplete suite: exit $RC, $OUT"
fi

# --- the inventory -------------------------------------------------------
OUT=$(/bin/bash "$SCRIPT" inventory --ledger "$ledger")
if printf '%s\n' "$OUT" | head -n 1 | grep -q "^eval cadence: 3 runs over 2 heads; latest [0-9a-f]\{12\} fail at " \
  && printf '%s\n' "$OUT" | grep -q "^  [0-9a-f]\{12\}: 2 runs on one head$"; then
  ok "the inventory counts runs and heads and names a re-run head"
else
  fail "the inventory: $OUT"
fi
if [ -z "$(/bin/bash "$SCRIPT" inventory --ledger "$ledger" --live "tower-comms custom-steps")" ]; then
  ok "the inventory stays silent when no live spec is gated"
else
  fail "the inventory printed for ungated live specs"
fi
OUT=$(/bin/bash "$SCRIPT" inventory --ledger "$tmp/none.tsv" --live "mission-control")
if [ "$OUT" = "eval cadence: no runs recorded" ]; then
  ok "a gated live spec with no runs is said"
else
  fail "an empty ledger: $OUT"
fi

# --- the default ledger is shared by the repository's worktrees ----------
gitx -C "$wt" worktree add -q "$tmp/wt2" -b other >/dev/null 2>&1 || fail "cannot add a worktree"
common=$(gitx -C "$wt" rev-parse --git-common-dir)
case $common in /*) ;; *) common="$wt/$common" ;; esac
OUT=$(env HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 /bin/bash "$SCRIPT" inventory --worktree "$tmp/wt2")
printf '%s\t%s\tmission-control\tpass\tseeded\n' 2026-11-03T00:00:00Z "$head1" >"$common/planwright-probe" || true
mkdir -p "$common/planwright"
mv "$common/planwright-probe" "$common/planwright/mc-eval-cadence.tsv"
OUT2=$(env HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 /bin/bash "$SCRIPT" inventory --worktree "$tmp/wt2")
if [ "$OUT" = "eval cadence: no runs recorded" ] && printf '%s\n' "$OUT2" | grep -q "^eval cadence: 1 runs over 1 heads"; then
  ok "the default ledger lives in the git common directory every worktree shares"
else
  fail "the default ledger: before '$OUT', after '$OUT2'"
fi

# --- fail closed ---------------------------------------------------------
nolist="$tmp/nolist"
cp -R "$mini" "$nolist"
rm -f "$nolist/gated-specs"
OUT=$(PLANWRIGHT_STEP_SPEC=mission-control PLANWRIGHT_STEP_WORKTREE="$wt" /bin/bash "$SCRIPT" step \
  --ledger "$ledger" --fixture "$nolist" --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && ! printf '%s\n' "$OUT" | grep -q "not gated"; then
  ok "a missing gated-specs list refuses the step rather than reading as ungated"
else
  fail "a missing gated-specs list: exit $RC, $OUT"
fi
OUT=$(/bin/bash "$SCRIPT" run --worktree "$wt" --fixture "$mini" --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q "needs an explicit --ledger"; then
  ok "an overridden suite never writes the default ledger"
else
  fail "an overridden suite without --ledger: exit $RC, $OUT"
fi
OUT=$(/bin/bash "$SCRIPT" run --worktree "$wt" --ledger '' --fixture "$mini" --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q -- "--ledger needs a non-empty value"; then
  ok "an empty --ledger is refused, never read as the default ledger"
else
  fail "an empty --ledger: exit $RC, $OUT"
fi

OUT=$(/bin/bash "$SCRIPT" run --worktree "$wt" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q "names another checkout"; then
  ok "a run never grades one checkout's suite for another checkout's head"
else
  fail "a cross-checkout run: exit $RC, $OUT"
fi
OUT=$(/bin/bash "$SCRIPT" run --worktree "$wt" --ledger "$tmp/cross.tsv" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q "names another checkout" && [ ! -e "$tmp/cross.tsv" ]; then
  ok "an explicit ledger does not let the shipped suite grade another checkout's head"
else
  fail "a cross-checkout run with an explicit ledger: exit $RC, $OUT"
fi

badruns="$tmp/badruns"
cp -R "$mini" "$badruns"
printf 'runs=x\n' >>"$badruns/fixture.conf"
mkdir -p "$tmp/scratch-tmp"
OUT=$(TMPDIR="$tmp/scratch-tmp" BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$tmp/state" \
  BEHAVIORAL_EVAL_WORKBASE="$tmp/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 /bin/bash "$SCRIPT" run --worktree "$wt" \
  --ledger "$tmp/badruns.tsv" --fixture "$badruns" --test-spec "$tmp/mini-test-spec.md" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && [ -z "$(ls -A "$tmp/scratch-tmp")" ]; then
  ok "a run stopped by a usage error removes its scratch directory"
else
  fail "a usage error after the harness: exit $RC, left $(ls -A "$tmp/scratch-tmp"), $OUT"
fi

# --- usage ---------------------------------------------------------------
/bin/bash "$SCRIPT" gated 'bad/name' 2>/dev/null
RC=$?
if [ "$RC" -eq 2 ]; then
  ok "an invalid spec name is a usage error"
else
  fail "an invalid spec name exited $RC"
fi
OUT=$(PLANWRIGHT_STEP_SPEC='../x' PLANWRIGHT_STEP_WORKTREE="$wt" /bin/bash "$SCRIPT" step --ledger "$ledger" 2>&1)
RC=$?
if [ "$RC" -eq 2 ]; then
  ok "an invalid step spec is refused before use"
else
  fail "an invalid step spec exited $RC: $OUT"
fi

# --- the wiring ----------------------------------------------------------
cat="$repo_root/.claude/catalogs/steps.yaml"
if awk '/^  - id: mc-eval-cadence$/ { f = 1; next } /^  - id:/ { f = 0 } f' "$cat" | grep -q '^    kind: command$' \
  && awk '/^  - id: mc-eval-cadence$/ { f = 1; next } /^  - id:/ { f = 0 } f' "$cat" | grep -q '^    target: scripts/mc-eval-cadence.sh$' \
  && awk '/^  - id: mc-eval-cadence$/ { f = 1; next } /^  - id:/ { f = 0 } f' "$cat" | grep -q '^    args: step$'; then
  ok "the steps catalog defines the cadence step"
else
  fail "the steps catalog lacks the cadence step"
fi
if grep -Eq '^steps_pre_ready_flip: \[([a-z0-9-]+, )*mc-eval-cadence(, [a-z0-9-]+)*\]$' "$repo_root/.claude/planwright.yml"; then
  ok "the pre-ready-flip point runs the cadence step"
else
  fail "steps_pre_ready_flip does not name mc-eval-cadence"
fi
: >"$tmp/empty-local.yml"
if (cd "$repo_root" && PLANWRIGHT_REPO_ROOT="$repo_root" PLANWRIGHT_LOCAL_CONFIG="$tmp/empty-local.yml" \
  /bin/bash scripts/resolve-steps.sh pre-ready-flip --check --unattended 2>/dev/null | grep -qx "run	mc-eval-cadence"); then
  ok "the pre-ready-flip point resolves the step without a warning"
else
  fail "resolve-steps does not resolve mc-eval-cadence at pre-ready-flip"
fi
if grep -q '^\[tasks."eval:mission-control"\]$' "$repo_root/mise.toml" \
  && awk '/^\[tasks."eval:mission-control"\]$/ { f = 1; next } /^\[/ { f = 0 } f' "$repo_root/mise.toml" | grep -q 'scripts/mc-eval-cadence.sh run'; then
  ok "the suite runs on demand under the eval namespace"
else
  fail "no eval:mission-control task runs the suite"
fi
if (cd "$repo_root" && /bin/sh scripts/check-no-ci-evals.sh >/dev/null 2>&1); then
  ok "the CI-eval exclusion guard stays green with the step present"
else
  fail "check-no-ci-evals fails"
fi
nontest=$(awk '/^\[tasks."check:non-test"\]$/ { f = 1; next } /^\[/ { f = 0 } f' "$repo_root/mise.toml")
for c in check:duties check:mc-knobs check:panel-mod check:instructions check:kb-copies; do
  if printf '%s\n' "$nontest" | grep -q "\"$c\""; then ok "CI's lint job runs $c"; else fail "check:non-test lacks $c"; fi
done
if grep -q 'run: mise run check:non-test$' "$repo_root/.github/workflows/ci.yml"; then
  ok "the CI workflow runs check:non-test"
else
  fail "the CI workflow does not run check:non-test"
fi
# The drain's manual sweep, over a specs root in the checkout whose ledger
# the default-ledger case above seeded with one run.
for s in mission-control other-work; do
  mkdir -p "$wt/specs/$s"
  printf '# %s\n\n**Status:** Ready\n' "$s" >"$wt/specs/$s/requirements.md"
  printf '# %s — Tasks\n\n**Status:** Ready\n\n## Deferred\n\n(none yet)\n' "$s" >"$wt/specs/$s/tasks.md"
  printf '# %s — Test Spec\n\n### REQ-A1.1 — x [test]\n\nx\n' "$s" >"$wt/specs/$s/test-spec.md"
done
OUT=$(env HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  /bin/bash "$repo_root/scripts/drain-gates.sh" --today 2026-11-03 "$wt/specs" 2>&1)
if printf '%s\n' "$OUT" | awk '/^== manual verification ==$/ { f = 1; next } /^== / { f = 0 } f' \
  | grep -q "^eval cadence: 1 runs over 1 heads; latest ${head1%"${head1#????????????}"} pass at "; then
  ok "the drain's manual sweep inventories the eval runs for a live gated bundle"
else
  fail "the drain's manual sweep lacks the inventory row: $OUT"
fi
rm -rf "$wt/specs/mission-control"
OUT=$(env HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  /bin/bash "$repo_root/scripts/drain-gates.sh" --today 2026-11-03 "$wt/specs" 2>&1)
if printf '%s\n' "$OUT" | grep -q "eval cadence"; then
  fail "the drain inventoried eval runs with no gated bundle live: $OUT"
else
  ok "the drain prints no eval row when no live bundle is gated"
fi

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-mc-eval-cadence.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-mc-eval-cadence.sh"
