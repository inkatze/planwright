#!/bin/bash
# Tests for the holder-halt eval fixture (tests/behavioral-evals/fixtures/
# holder-halt; custom-spec-location REQ-E1.9): an execution skill halting with
# its spec root in a holder or a plain store leaves the note as an
# uncommitted file there, gains the holder no commit, branch, or push, and
# names the file in its handoff.
#
# Two lanes: end to end through the real harness under the shared stub tmux,
# and direct invocation of the fixture with grade.jq negatives. Hermetic: no
# tmux, no model, no API key.
# shellcheck disable=SC2016 # the $-sigils in quoted jq filters are jq bindings
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/holder-halt"
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
  BEHAVIORAL_EVAL_WORKBASE="$E2E/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$E2E/rec" --grader "$GRADER" --grader-id ext-panel "$FIXTURE" 2>&1)"
e2erc=$?
if [ "$e2erc" -eq 0 ]; then
  ok "every persona completes through the harness"
else
  fail "the harness exited $e2erc"
  printf '%s\n' "$e2eout" >&2
fi
for p in holder plain; do
  if [ "$(jq -r .structural_pass "$E2E/rec/holder-halt.$p.json" 2>/dev/null)" = true ]; then
    ok "[$p] structural grade passes on the harness"
  else
    fail "[$p] structural grade did not pass: $(cat "$E2E/rec/holder-halt.$p.json" 2>/dev/null)"
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
    ok "[$p] the halt note lands uncommitted and the handoff names it"
  else
    fail "[$p] the grade fails: $m"
  fi
  case $p in
    holder) want="$TMP/holder/holder/specs/demo/tasks.md" ;;
    plain) want="$TMP/plain/store/demo/tasks.md" ;;
  esac
  if [ "$(printf '%s' "$m" | jq -r .sign_off.note_file)" = "$want" ]; then
    ok "[$p] the note is in the store's primary view"
  else
    fail "[$p] the note file is $(printf '%s' "$m" | jq -r .sign_off.note_file)"
  fi
done
m=$(merged holder "$TMP/holder")
for defect in '.sign_off.holder_new_commit = true' '.sign_off.holder_new_branch = true' \
  '.sign_off.holder_pushed = true' '.sign_off.uncommitted = false' '.sign_off.bullet_written = false' \
  '.decision_log |= map(if .kind == "handoff" then .text = "halted" else . end)' \
  '.persona = "plain"'; do
  if printf '%s' "$m" | jq "$defect" | jq -e -f "$GRADEJQ" >/dev/null; then
    fail "the grade passed a run with: $defect"
  else
    ok "the grade rejects a run with: $defect"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-behavioral-eval-holder-halt.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-behavioral-eval-holder-halt.sh"
