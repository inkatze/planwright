#!/bin/bash
# Tests for /execute-task's pre-flight step check: before any implementation,
# the skill resolves every point it will use in one `resolve-steps.sh --check
# --unattended` run and halts on a `refuse` row, a skill step that cannot run
# (its file sets disable-model-invocation, or no file exists), instead of
# finding out at the point after the work is done.
#
# The pre-flight is procedure the agent reads, so the seam is the skill prose
# (the shape of tests/test-execute-task-status-gate.sh), plus one functional
# half: the command the prose names is extracted and run against fixtures, so
# the prose and the resolver are proven to agree.
#
# Runs standalone: ./tests/test-execute-task-step-preflight.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/execute-task/SKILL.md"
TAB=$(printf '\t')

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$skill" ] || {
  echo "FAIL: execute-task SKILL.md missing at $skill" >&2
  exit 1
}

# The pre-flight section, flattened so wrapped prose matches.
preflight=$(awk '/^## Pre-flight/ { on = 1; next } /^## / { on = 0 } on' "$skill" | tr '\n' ' ' | tr -s ' ')
step12=$(printf '%s' "$preflight" | sed -n 's/.*\(12\. \*\*Check every point.*\)$/\1/p')
[ -n "$step12" ] || fail "pre-flight has no step 12 that checks every point"

# The check is one run over every in-run point, in check mode, unattended.
# shellcheck disable=SC2016 # literal backticks of the skill's markdown, never expanded
cmd=$(printf '%s' "$step12" | grep -o '`scripts/resolve-steps\.sh [^`]*`' | head -1 | tr -d '`')
case "$cmd" in
  "scripts/resolve-steps.sh pre-implementation pre-ci convergence pre-pr post-pr "*"--check --unattended"*)
    ok "the pre-flight checks the five in-run points in one --check --unattended run"
    ;;
  *) fail "the pre-flight check command is not one --check --unattended run over the in-run points: '$cmd'" ;;
esac
case "$step12" in
  *"pre-ready-flip"*"unit-owner"*) ok "the flip point joins the check when the unit flips its own PR" ;;
  *) fail "the pre-flight check must add pre-ready-flip under ready_flip_policy unit-owner" ;;
esac

# It halts on a refuse row before any implementation, relaying the resolver's
# warning, which names the cause and the fix (asserted in the functional half).
# shellcheck disable=SC2016 # literal backticks of the skill's markdown, never expanded
case "$step12" in
  *'a `refuse` row halts, relaying its warning'*) ok "a refuse row halts, relaying its warning" ;;
  *) fail "step 12 must halt on a refuse row, relaying its warning" ;;
esac

# Step 12 is the last pre-flight step, so the check runs before the
# pre-implementation point and before the Implementation section.
last=$(printf '%s' "$preflight" | grep -oE '(^| )[0-9]+\. \*\*' | tail -1 | tr -d ' *.')
[ "$last" = 12 ] || fail "the check is not the last pre-flight step (last: '$last')"
if awk '/^## Pre-flight/ { p = NR } /Check every point/ { c = NR } /^## Implementation/ { i = NR } END { exit !(p && c > p && i > c) }' "$skill"; then
  ok "the check sits in pre-flight, ahead of Implementation"
else
  fail "the check must sit in Pre-flight, ahead of ## Implementation"
fi

# A refused step is a stop condition.
stops=$(awk '/^## Stop conditions/ { on = 1; next } /^## / { on = 0 } on' "$skill" | tr '\n' ' ')
case "$stops" in
  *"every pre-flight halt"*) ok "every pre-flight halt, the refusal included, is a stop condition" ;;
  *) fail "the stop conditions must cover every pre-flight halt" ;;
esac
# A point that runs nothing exits 1 whether its rows say park, ask, or only
# refuse, so the runner keys on the exit and attendance, never on a token.
if tr '\n' ' ' <"$skill" | tr -s ' ' | grep -q 'Exit 1: park the unit (attended, present and wait for a repair and re-resolve)'; then
  ok "exit 1 parks, or presents attended, whatever the rows' tokens"
else
  fail "the Points resolve step must park on exit 1 (attended, present and wait) without reading tokens"
fi

# Functional half: the named command against fixtures. A flagged skill and a
# missing one, both in an adopter list (whose unattended skip would otherwise
# pass), fail the check with a refuse row; the shipped defaults pass it.
tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/adopter/catalogs" "$tmp/claude/skills/gated" "$tmp/home"
printf -- '---\nname: gated\ndisable-model-invocation: true\n---\n' >"$tmp/claude/skills/gated/SKILL.md"
read -ra words <<<"${cmd#scripts/resolve-steps.sh }"
# The host's own planwright and step variables are cleared, as
# tests/test-resolve-steps.sh clears them, so a worker shell's exports never
# reach the fixture run.
run_check() {
  env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_JQ \
    -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS -u PLANWRIGHT_REPO_ROOT_CHECKED \
    -u PLANWRIGHT_STEP_SPEC -u PLANWRIGHT_STEP_TASK_IDS -u PLANWRIGHT_STEP_UNIT_KIND \
    -u PLANWRIGHT_STEP_BRANCH -u PLANWRIGHT_STEP_BASE_BRANCH -u PLANWRIGHT_STEP_WORKTREE \
    -u PLANWRIGHT_STEP_PR_NUMBER -u PLANWRIGHT_STEP_POINT -u PLANWRIGHT_STEP_ID \
    -u PLANWRIGHT_STEP_PREV_RECORD \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_CONFIG_DEFAULTS="$REPO_ROOT/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="" CLAUDE_DIR="$tmp/claude" HOME="$tmp/home" \
    /bin/bash "$REPO_ROOT/scripts/resolve-steps.sh" "${words[@]}"
}
out=$(run_check 2>"$tmp/err")
rc=$?
if [ "$rc" = 0 ]; then
  ok "the pre-flight check passes on the shipped defaults"
else
  fail "the pre-flight check fails on the shipped defaults: rc=$rc err='$(cat "$tmp/err")'"
fi
for target in gated panel-review; do
  printf 'steps:\n  - id: s-%s\n    kind: skill\n    target: %s\n' "$target" "$target" >"$tmp/adopter/catalogs/steps.yaml"
  printf 'steps_pre_pr: [s-%s]\n' "$target" >"$tmp/adopter/planwright.yml"
  out=$(run_check 2>"$tmp/err")
  rc=$?
  case $target in
    gated)
      want1="disable-model-invocation: true in $tmp/claude/skills/gated/SKILL.md"
      want2="drop the flag, or use a kind: prompt step that reads the skill file"
      ;;
    *)
      want1="'panel-review' resolves to no file (looked under: "
      want2="$tmp/claude/skills); install the skill or drop the step"
      ;;
  esac
  if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "^refuse${TAB}s-$target${TAB}pre-pr${TAB}" \
    && grep -qF "$want1" "$tmp/err" && grep -qF "$want2" "$tmp/err"; then
    ok "the pre-flight check refuses an adopter step on skill '$target'"
  else
    fail "the pre-flight check must refuse skill '$target': rc=$rc out='$out' err='$(cat "$tmp/err")'"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "FAIL: execute-task step pre-flight ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: execute-task step pre-flight"
