#!/bin/bash
# Tests for the authoring-posture eval fixture (tests/behavioral-evals/
# fixtures/authoring-posture; custom-spec-location REQ-E1.2, REQ-E1.3): with
# the spec root in a holder, /spec-draft's bundle lands on the holder's spec
# branch in the holder's worktree and the work repository gains nothing; with
# a plain store, the files are written, no spec branch or worktree exists
# anywhere, and the handoff names every skipped step and the absent guards.
#
# Two lanes: end to end through the real harness under the shared stub tmux,
# and direct invocation of the fixture with grade.jq negatives. Hermetic: no
# tmux, no model, no API key.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/authoring-posture"
SKILL="$FIXTURE/skill.sh"
GRADEJQ="$FIXTURE/grade.jq"
STUB="$REPO_ROOT/tests/behavioral-evals/lib/tmux-stub.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq required for these tests" >&2
  exit 1
}
TMP="$(mktemp -d)" || exit 1
TMP=$(cd "$TMP" && pwd -P) || exit 1
trap 'rm -rf "$TMP"' EXIT

feed_persona() { sed -n 's/^answer\.[0-9]*=//p' "$1"; }
merged() {
  jq -n --arg persona "$1" --slurpfile log "$2/decision-log.jsonl" --slurpfile rec "$2/sign-off.json" \
    '{persona: $persona, decision_log: $log, sign_off: $rec[0]}'
}

# Lane 1 — end to end through the harness.
GRADER="$TMP/grader.sh"
cat >"$GRADER" <<'GRADER_EOF'
#!/bin/sh
jq -e '.sign_off.publishing_disabled == true' "$1" >/dev/null 2>&1 && echo pass || echo fail
GRADER_EOF
chmod +x "$GRADER"
E2E="$TMP/e2e"
mkdir -p "$E2E/wb" "$E2E/rec" "$E2E/state"
e2eout="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$E2E/state" \
  BEHAVIORAL_EVAL_WORKBASE="$E2E/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 BEHAVIORAL_EVAL_DRIVER_ID=planwright-eval-driver \
  /bin/sh "$RUNNER" --record "$E2E/rec" --grader "$GRADER" --grader-id ext-panel "$FIXTURE" 2>&1)"
e2erc=$?
if [ "$e2erc" -eq 0 ]; then
  ok "every persona completes through the harness"
else
  fail "the harness exited $e2erc"
  printf '%s\n' "$e2eout" >&2
fi
for p in holder plain; do
  if [ "$(jq -r .structural_pass "$E2E/rec/authoring-posture.$p.json" 2>/dev/null)" = true ]; then
    ok "[$p] structural grade passes on the harness"
  else
    fail "[$p] structural grade did not pass: $(cat "$E2E/rec/authoring-posture.$p.json" 2>/dev/null)"
  fi
done

# Lane 2 — direct invocation, and the grade's negatives.
for p in holder plain; do
  mkdir -p "$TMP/$p"
  feed_persona "$FIXTURE/personas/$p.persona" \
    | PLANWRIGHT_EVAL_ONLY=1 PLANWRIGHT_PUBLISH_DISABLED=1 /bin/sh "$SKILL" "$TMP/$p" >"$TMP/$p.pane" 2>&1 \
    || fail "[$p] the stand-in exited non-zero: $(cat "$TMP/$p.pane")"
  m=$(merged "$p" "$TMP/$p")
  if printf '%s' "$m" | jq -e -f "$GRADEJQ" >/dev/null; then
    ok "[$p] the scenario's grade passes"
  else
    fail "[$p] the grade fails: $m"
  fi
done
if [ "$(merged holder "$TMP/holder" | jq -r .sign_off.worktree)" = "$TMP/holder/holder/.claude/worktrees/demo-spec" ]; then
  ok "[holder] the spec worktree is <holder>/.claude/worktrees/<id>-spec"
else
  fail "[holder] the worktree is $(merged holder "$TMP/holder" | jq -r .sign_off.worktree)"
fi
if [ -f "$TMP/plain/store/demo/requirements.md" ] && [ ! -e "$TMP/plain/store/.git" ]; then
  ok "[plain] the bundle is a set of files in the store"
else
  fail "[plain] the store does not hold the bundle as plain files"
fi

m=$(merged holder "$TMP/holder")
for defect in '.sign_off.branch_has_bundle = false' '.sign_off.work_new_commit = true' \
  '.sign_off.work_new_branch = true' '.sign_off.work_new_worktree = true' \
  '.sign_off.holder_pushed = true' '.sign_off.holder_clean = false' \
  '.sign_off.worktree = "/elsewhere"' '.sign_off.files_written = 3' '.persona = "plain"' \
  '.sign_off.eval_only = false' '.sign_off.authoritative = true'; do
  if printf '%s' "$m" | jq "$defect" | jq -e -f "$GRADEJQ" >/dev/null; then
    fail "the holder grade passed a run with: $defect"
  else
    ok "the holder grade rejects a run with: $defect"
  fi
done
m=$(merged plain "$TMP/plain")
for defect in '.sign_off.spec_branch_anywhere = true' '.sign_off.store_has_git = true' \
  '.sign_off.work_new_commit = true' \
  '.decision_log |= map(if .kind == "handoff" then .text |= sub("ready flip"; "") else . end)' \
  '.decision_log |= map(if .kind == "handoff" then .text |= sub("no spec guard runs"; "") else . end)' \
  '.decision_log |= map(if .kind == "handoff" then .text |= sub("commit, "; "") else . end)' \
  '.persona = "holder"'; do
  if printf '%s' "$m" | jq "$defect" | jq -e -f "$GRADEJQ" >/dev/null; then
    fail "the plain grade passed a run with: $defect"
  else
    ok "the plain grade rejects a run with: $defect"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-behavioral-eval-authoring-posture.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-behavioral-eval-authoring-posture.sh"
