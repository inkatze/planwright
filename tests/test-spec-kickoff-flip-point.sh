#!/bin/bash
# Tests for /spec-kickoff's pre-spec-ready-flip point (custom-steps Task 6;
# REQ-A1.2, REQ-D1.12, REQ-E1.3, REQ-E1.6, REQ-J1.2; D-13, D-20, D-32).
#
# The kickoff flow is skill prose, so the wiring is fenced structurally over
# skills/spec-kickoff/SKILL.md and doctrine/kickoff-verification.md. The
# scenarios then drive the script sequence that prose names (resolve the
# point, run and record its steps, complete it, post the status) in a fixture
# worktree with a gh stub, against the shipped config and catalog plus a
# fixture adopter overlay:
#   - the default empty list posts a `success` status;
#   - a failing command step records `failed` with its end head and posts
#     `failure`;
#   - a seeded `limited` record of an earlier run ending on the head posts
#     `failure` though the flip attempt itself is clean.
#
# Runs standalone: ./tests/test-spec-kickoff-flip-point.sh
# shellcheck disable=SC2016 # backticks in the patterns are literal markdown
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/spec-kickoff/SKILL.md"
gate_doc="$REPO_ROOT/doctrine/kickoff-verification.md"
RS="$REPO_ROOT/scripts/resolve-steps.sh"
SR="$REPO_ROOT/scripts/step-record.sh"
TAB=$(printf '\t')

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2"
  fi
}

for f in "$skill" "$gate_doc" "$RS" "$SR"; do
  [ -f "$f" ] || {
    echo "FAIL: required file missing: $f" >&2
    exit 1
  }
done

flat="$(tr '\n' ' ' <"$skill" | tr -s '[:space:]' ' ')"
doc_flat="$(tr '\n' ' ' <"$gate_doc" | tr -s '[:space:]' ' ')"

# --- Structure: the point sits after the push and PR, before the CI gate -------

# The slice from sign-off step 7 (push and draft PR) to step 8 (the flip).
step7="${flat#*7. \*\*Push and draft PR\*\*}"
step7="${step7%%8. \*\*Mark the spec PR ready*}"
[ "$step7" != "$flat" ]
verdict "sign-off step 7 is locatable" "cannot locate sign-off step 7 in the skill"

printf '%s' "$step7" | grep -qE 'gh pr create --draft.*`pre-spec-ready-flip` point'
verdict "REQ-A1.2: the point fires in step 7, after the push and PR" "REQ-A1.2: step 7 does not fire pre-spec-ready-flip after the PR step"
printf '%s' "$step7" | grep -qF '`scripts/resolve-steps.sh pre-spec-ready-flip'
verdict "REQ-A1.2: the point resolves through the resolver" "REQ-A1.2: step 7 does not call scripts/resolve-steps.sh pre-spec-ready-flip"
printf '%s' "$step7" | grep -qE 'whether or not a flip follows'
verdict "REQ-A1.2: the point fires whether or not the flip is configured to follow" "REQ-A1.2: step 7 does not fire the point regardless of the opt-out"
printf '%s' "$step7" | grep -qF '`scripts/step-record.sh status --point pre-spec-ready-flip'
verdict "REQ-E1.6: the status is posted through the record helper's status verb" "REQ-E1.6: step 7 does not post the status through step-record.sh status"
printf '%s' "$step7" | grep -qE 'head the list ends on'
verdict "REQ-E1.3: the status and the flip target the head the list ends on" "REQ-E1.3: step 7 does not name the head the list ends on"
printf '%s' "$step7" | grep -qE 'end head'
verdict "REQ-D1.12: the point's records carry their end head" "REQ-D1.12: step 7 does not say the records carry their end head"
# The status verb refuses a head no completion record of the point names.
printf '%s' "$step7" | grep -qF 'step-record.sh write --completion'
verdict "REQ-E1.6: the point writes its completion record before the post" "REQ-E1.6: step 7 never writes the completion record the status post requires"
printf '%s' "$step7" | grep -qE '`failure` status.{0,80}refuses the flip'
verdict "REQ-J1.2: a failure status refuses the flip" "REQ-J1.2: step 7 does not refuse the flip on a failure status"
printf '%s' "$step7" | grep -qE 'Awaiting input.{0,40}naming the step'
verdict "REQ-A1.2: the refusal records the pending flip to Awaiting input naming the step" "REQ-A1.2: the refusal's Awaiting-input entry does not name the step"
for ref in REQ-A1.2 REQ-E1.6 REQ-J1.2 D-13; do
  printf '%s' "$step7" | grep -qF "$ref"
  verdict "step 7's point prose cites $ref" "step 7's point prose does not cite $ref"
done

# REQ-F1.3: the skill no longer names the retired knob.
! grep -qiE 'review[_ -]sequence' "$skill"
verdict "REQ-F1.3: the skill no longer names the review-sequence knob" "REQ-F1.3: the skill still names the review-sequence knob"

# REQ-E1.6: the terminal CI gate excludes the flip-point contexts by name.
printf '%s' "$doc_flat" | grep -qE 'excluding the `planwright/pre-ready-flip` and `planwright/pre-spec-ready-flip` contexts by name'
verdict "REQ-E1.6: the kickoff CI gate excludes the flip-point contexts by name" "REQ-E1.6: kickoff-verification does not exclude the flip-point contexts"

# --- Scenarios: the script sequence the prose names --------------------------

command -v git >/dev/null 2>&1 || {
  echo "FAIL: git is required" >&2
  exit 1
}
tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

wt="$tmp/wt"
adopter="$tmp/adopter"
bin="$tmp/bin"
mkdir -p "$wt" "$adopter/catalogs" "$bin" "$tmp/home" "$tmp/claude"
git -C "$wt" init -q -b planwright/fixture/spec
git -C "$wt" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  commit -q --allow-empty -m "chore: base"
head=$(git -C "$wt" rev-parse HEAD)

cat >"$bin/gh" <<'STUB'
#!/bin/sh
: >"$GH_STUB_LOG"
for a in "$@"; do printf '%s\n' "$a" >>"$GH_STUB_LOG"; done
printf '{"state":"posted"}\n'
STUB
printf '#!/bin/sh\necho "fixture check failed" >&2\nexit 1\n' >"$bin/fixture-fail"
chmod +x "$bin/gh" "$bin/fixture-fail"
GH_STUB_LOG="$tmp/gh.args"
export GH_STUB_LOG

STEP_UNSETS="-u PLANWRIGHT_STEP_SPEC -u PLANWRIGHT_STEP_TASK_IDS -u PLANWRIGHT_STEP_UNIT_KIND -u PLANWRIGHT_STEP_BRANCH -u PLANWRIGHT_STEP_BASE_BRANCH -u PLANWRIGHT_STEP_WORKTREE -u PLANWRIGHT_STEP_PR_NUMBER -u PLANWRIGHT_STEP_POINT -u PLANWRIGHT_STEP_ID -u PLANWRIGHT_STEP_PREV_RECORD -u PLANWRIGHT_STEP_PREV_HEAD -u PLANWRIGHT_STEP_NEW_HEAD -u PLANWRIGHT_STEP_POOL_HOLD"
# resolve <args...>: the resolver over the shipped config and catalog, the
# fixture adopter overlay, and no repo or machine-local layer.
resolve() {
  # shellcheck disable=SC2086 # the unset flags are meant to word-split
  env $STEP_UNSETS -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_CONFIG_DEFAULTS="$REPO_ROOT/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="" CLAUDE_DIR="$tmp/claude" HOME="$tmp/home" PATH="$bin:$PATH" \
    /bin/bash "$RS" "$@"
}
sr() { PATH="$bin:$PATH" "$SR" --worktree "$wt" "$@"; }

# fire: one kickoff firing of the point on the worktree's head. Each resolved
# command step runs, its outcome its exit code, and is recorded on the head
# it started from; then the completion and the status post. Sets FIRE_RUN,
# FIRE_STATUS (the status verb's output), and FIRE_RC.
fire() {
  FIRE_RUN=$(sr new-run) || {
    fail "fixture: new-run failed"
    return 1
  }
  rows=$(resolve pre-spec-ready-flip --explain --attended) || {
    fail "fixture: the point did not resolve"
    return 1
  }
  while IFS="$TAB" read -r disp id _point _l1 _l2 target hosting kind _rest; do
    [ "$disp" = run ] || continue
    [ "$kind" = command ] || {
      fail "fixture: unexpected step kind $kind"
      continue
    }
    start=$(git -C "$wt" rev-parse HEAD)
    if PATH="$bin:$PATH" "$target" >/dev/null 2>&1; then outcome=passed; else outcome=failed; fi
    sr write --run "$FIRE_RUN" --point pre-spec-ready-flip --step "$id" --kind command \
      --target "$target" --hosting "$hosting" --backend terminal --head "$start" \
      --start 2026-10-18T10:00:00Z --outcome "$outcome" >/dev/null \
      || fail "fixture: cannot record step $id"
  done <<EOF
$rows
EOF
  sr write --completion --run "$FIRE_RUN" --point pre-spec-ready-flip >/dev/null \
    || fail "fixture: cannot write the completion"
  rm -f "$GH_STUB_LOG"
  FIRE_STATUS=$(sr status --point pre-spec-ready-flip --repo acme/widgets 2>"$tmp/status.err")
  FIRE_RC=$?
}
posted() { grep -qxF "$1" "$GH_STUB_LOG" 2>/dev/null; }

# REQ-A1.2 / REQ-E1.6: the default empty list posts success on the head.
fire
[ "$FIRE_RC" = 0 ] && [ "$FIRE_STATUS" = "posted${TAB}planwright/pre-spec-ready-flip${TAB}success${TAB}$head" ] \
  && posted "repos/acme/widgets/statuses/$head" && posted "state=success" \
  && posted "context=planwright/pre-spec-ready-flip"
verdict "REQ-A1.2: the default empty list posts a success status on the head" "default list: rc=$FIRE_RC out='$FIRE_STATUS' err='$(cat "$tmp/status.err")'"
! sr list --run "$FIRE_RUN" --point pre-spec-ready-flip | grep -q "^step${TAB}"
verdict "the default list records no step" "the default list recorded a step"

# REQ-A1.2 / REQ-D1.12: a failing command step in the adopter overlay records
# failed with its end head, and the status is failure.
printf 'steps:\n  - id: fixture-gate\n    kind: command\n    target: fixture-fail\n    hosting: in-session\n' \
  >"$adopter/catalogs/steps.yaml"
printf 'steps_pre_spec_ready_flip: [fixture-gate]\n' >"$adopter/planwright.yml"
fire
[ "$FIRE_RC" = 0 ] && [ "$FIRE_STATUS" = "posted${TAB}planwright/pre-spec-ready-flip${TAB}failure${TAB}$head" ] \
  && posted "state=failure"
verdict "REQ-A1.2: a failing step at the point posts a failure status" "failing step: rc=$FIRE_RC out='$FIRE_STATUS' err='$(cat "$tmp/status.err")'"
recs=$(sr list --run "$FIRE_RUN" --point pre-spec-ready-flip)
printf '%s\n' "$recs" | grep -qx "step${TAB}fixture-gate" \
  && printf '%s\n' "$recs" | grep -qx "outcome${TAB}failed" \
  && printf '%s\n' "$recs" | grep -qx "end-head${TAB}$head"
verdict "REQ-D1.12: the failed step's record names the step and carries its end head" "failed record: '$recs'"

# REQ-J1.2: a limited record of an earlier run ending on the head fails a clean
# flip attempt.
rm -f "$adopter/catalogs/steps.yaml" "$adopter/planwright.yml"
git -C "$wt" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  commit -q --allow-empty -m "chore: next"
head=$(git -C "$wt" rev-parse HEAD)
held=$(sr new-run)
sr write --run "$held" --point convergence --step held-review --kind command --target true \
  --hosting in-session --backend terminal --start 2026-10-18T09:00:00Z --outcome limited >/dev/null \
  || fail "fixture: cannot seed the limited record"
fire
[ "$FIRE_RC" = 0 ] && [ "$FIRE_STATUS" = "posted${TAB}planwright/pre-spec-ready-flip${TAB}failure${TAB}$head" ]
verdict "REQ-J1.2: an unretired limited record ending on the head posts failure" "limited: rc=$FIRE_RC out='$FIRE_STATUS' err='$(cat "$tmp/status.err")'"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all spec-kickoff flip-point tests passed"
