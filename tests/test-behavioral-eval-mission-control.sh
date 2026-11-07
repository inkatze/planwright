#!/bin/bash
# Tests for the mission control eval fixture (tests/behavioral-evals/fixtures/
# mission-control): one persona per [Gherkin] arm of the mission-control test
# spec, each graded by grade.jq's floor and its own arm's pin, and a seeded
# violation of every rule failing the grade (mission-control REQ-F1.7,
# REQ-F1.8, REQ-B1.1, REQ-A1.7, REQ-H1.4, REQ-I1.5, REQ-F1.12 among the arms).
#
# Two lanes: end to end through the real harness under the shared stub tmux,
# and direct invocation of the stand-in with grade.jq negatives. Hermetic: no
# tmux, no model, no API key.
# shellcheck disable=SC2016 # the $-sigils in quoted jq filters are jq bindings
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/behavioral-eval.sh"
FIXTURE="$REPO_ROOT/tests/behavioral-evals/fixtures/mission-control"
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

PERSONAS=$(awk -F '=' '$1 == "personas" { sub(/^[^=]*=/, ""); print; exit }' "$FIXTURE/fixture.conf")
feed_persona() { sed -n 's/^answer\.[0-9]*=//p' "$1"; }
merged() {
  jq -n --arg persona "$1" --slurpfile log "$2/decision-log.jsonl" --slurpfile rec "$2/sign-off.json" \
    '{persona: $persona, decision_log: $log, sign_off: $rec[0]}'
}

# Lane 1 — end to end through the harness, on three personas: a pasted line
# through send-keys, the relayed walk-through, and a one-turn status. Every
# persona goes through the harness lane on demand (mise run eval:mission-control);
# here the per-persona cost of the stub's polling would blow the file's time
# budget, and lane 2 drives every persona's stand-in directly.
E2E="$TMP/e2e"
E2E_PERSONAS="no-send relayed-kickoff status-form"
mkdir -p "$E2E/wb" "$E2E/rec" "$E2E/state"
set --
for p in $E2E_PERSONAS; do set -- "$@" --persona "$p"; done
e2eout="$(BEHAVIORAL_EVAL_TMUX="$STUB" BEHAVIORAL_EVAL_TMUX_STATE="$E2E/state" \
  BEHAVIORAL_EVAL_WORKBASE="$E2E/wb" BEHAVIORAL_EVAL_POLL_SLEEP=0 \
  /bin/sh "$RUNNER" --record "$E2E/rec" "$@" "$FIXTURE" 2>&1)"
e2erc=$?
if [ "$e2erc" -eq 0 ]; then
  ok "the sampled personas complete through the harness"
else
  fail "the harness exited $e2erc"
  printf '%s\n' "$e2eout" >&2
fi
for p in $E2E_PERSONAS; do
  if [ "$(jq -r .structural_pass "$E2E/rec/mission-control.$p.json" 2>/dev/null)" = true ]; then
    ok "[$p] structural grade passes on the harness"
  else
    fail "[$p] structural grade did not pass: $(cat "$E2E/rec/mission-control.$p.json" 2>/dev/null)"
  fi
done

# Lane 2 — direct invocation, then a seeded violation of each rule.
for p in $PERSONAS; do
  mkdir -p "$TMP/$p"
  feed_persona "$FIXTURE/personas/$p.persona" \
    | /bin/sh "$SKILL" "$TMP/$p" >"$TMP/$p.pane" 2>&1 \
    || fail "[$p] the stand-in exited non-zero: $(cat "$TMP/$p.pane")"
  merged "$p" "$TMP/$p" >"$TMP/$p.json" || fail "[$p] the artifacts do not merge"
  if jq -e -f "$GRADEJQ" "$TMP/$p.json" >/dev/null; then
    ok "[$p] the arm grades green"
  else
    fail "[$p] the arm does not grade green"
  fi
done

if jq -e -f "$GRADEJQ" <(jq '.persona = "no-such-arm"' "$TMP/status-form.json") >/dev/null 2>&1; then
  fail "a persona with no pin graded green"
else
  ok "a persona with no pin fails"
fi

# seeded <persona> <label> <jq-defect> — the defect applied to the persona's
# green run must fail the grade.
seeded() {
  if jq "$3" "$TMP/$1.json" | jq -e -f "$GRADEJQ" >/dev/null 2>&1; then
    fail "[$1] the grade passed a seeded violation: $2"
  else
    ok "[$1] the grade fails a seeded violation: $2"
  fi
}
first_present='(.decision_log | map(.kind == "present") | index(true))'
first_item='(.decision_log | map(.kind == "present" and .item != null) | index(true))'

# The floor, on any persona's run.
seeded status-form "register: an identifier reaches the operator" \
  ".decision_log[$first_present].text += \" (REQ-F1.3)\""
seeded status-form "register: a script name reaches the operator" \
  ".decision_log[$first_present].text += \" via mc-inbox.sh\""
seeded on-behalf "register: a pane is named" \
  ".decision_log[$first_present].text += \" in pane 3\""
seeded no-concepts "register: a planwright concept is named" \
  ".decision_log[$first_present].text += \" Shall I open a spec?\""
seeded no-concepts "register: a skill name on a turn that hands no command" \
  ".decision_log[$first_present].text += \" Run /spec-draft.\""
seeded status-form "density: a multi-line turn" \
  ".decision_log[$first_present].text += \"\\nmore\""
seeded delivery "density: two uncoupled items in one turn" \
  "(.decision_log[] | select(.kind == \"present\" and .item != null) | .item.cluster) = \"\""
seeded answerable "item shape: no link" ".decision_log[$first_item].item.link = \"\""
seeded answerable "item shape: no id" ".decision_log[$first_item].item.id = \"\""
seeded answerable "item shape: no subject" "del(.decision_log[$first_item].item.subject)"
seeded answerable "item shape: no check stated" ".decision_log[$first_item].item.checked = \"\""
seeded answerable "item shape: an option without its effect" ".decision_log[$first_item].item.options[0].effect = \"\""
seeded picklist "picklist shape: a default no option carries" \
  "(.decision_log[] | select(.kind == \"present\" and .picklist != null) | .picklist.default) = \"later\""
seeded duty-proposal "proposal shape: no explicit decline" \
  "(.decision_log[] | select(.kind == \"present\" and .proposal != null) | .options) |= map(select(.label != \"no\"))"
seeded on-behalf "own words: a relayed answer that is not the operator's" \
  "(.decision_log[] | select(.action == \"answer-selector\") | .quote) = \"ship the code first\""
seeded no-send "own words: a send on the pasted yes" \
  "(.decision_log[] | select(.action == \"send\") | .on_seq) -= 1"
seeded status-form "no merge: a merge decision" \
  '.decision_log += [{kind: "decision", action: "merge", seq: 999}]'
seeded status-form "the run record: authoritative" '.sign_off.authoritative = true'
seeded status-form "the run record: an approval" '.sign_off.approved = true'
seeded nothing-dropped "an item leaving with no reason" \
  "(.decision_log[] | select(.action == \"item-leave\") | .reason) = \"\""

seeded no-send "own words: a send with no shown draft" \
  "(.decision_log[] | select(.action == \"send\")) |= del(.draft_seq)"
seeded on-behalf "own words: a relayed answer quoting pasted material" \
  "(.decision_log[] | select(.kind == \"answer\" and .text == \"ship the docs change first\") | .text) = \"> ship it\" | (.decision_log[] | select(.action == \"answer-selector\") | .quote) = \"> ship it\""
seeded duty-proposal "own words: an enable on a yes given before the proposal" \
  "(.decision_log[] | select(.action == \"proposal\") | .seq) = 9990"

seeded no-send "own words: a send before the operator's yes" \
  "(.decision_log[] | select(.action == \"send\") | .seq) = ((.decision_log[] | select(.action == \"clipboard\") | .seq) + 0.5)"
seeded duty-proposal "own words: an enable before the operator's yes" \
  "(.decision_log[] | select(.action == \"enable\") | .seq) = ((.decision_log[] | select(.action == \"proposal\") | .seq) + 0.5)"
seeded no-send "own words: a word that only starts with yes" \
  "(.decision_log[] | select(.kind == \"answer\" and .text == \"yes, send it\") | .text) = \"yesterday it was wrong, hold it\""
seeded follow-up "work started with no trigger at all" \
  'del(.decision_log[] | select(.kind == "event" and .event == "trigger-fired")) | (.decision_log[] | select(.action == "start-work") | .seq) = 0'
seeded delivery "items delivered with no presence events" \
  'del(.decision_log[] | select(.kind == "event" and .event == "presence"))'

# The register reads words, not prefixes, and never a link.
if jq '(.decision_log[] | select(.kind == "present") | .text) |= . + " The panel shows the specific items I handled (https://forge.example/planwright/pull/1)."' \
  "$TMP/status-form.json" | jq -e -f "$GRADEJQ" >/dev/null 2>&1; then
  ok "the register passes panel, specific, handled and a link's path"
else
  fail "the register fails ordinary words or a link"
fi

# Each arm's own pin.
seeded bring-up "the stale state file read" \
  "(.decision_log[] | select(.action == \"bringup\") | .state_file_read) = true"
seeded bring-up "the state file's figure reported" \
  ".decision_log[$first_present].text += \" (17 open)\""
seeded on-behalf "no launch" 'del(.decision_log[] | select(.action == "launch"))'
# Quiet by default: a routine act is logged, never narrated.
routine_ev='(.decision_log | map(.kind == "event" and (.raw | startswith("routine "))) | index(true))'
seeded on-behalf "quiet: a turn narrates a routine approval" \
  ".decision_log[$first_present].text += \" I approved the export work's request to run its tests.\""
seeded on-behalf "quiet: a turn answers a routine-only event" \
  "$routine_ev as \$i | .decision_log |= (.[0:(\$i + 1)] + [{v: 2, seq: 993, phase: \"session\", kind: \"present\", text: \"All quiet; the readiness watch is back.\"}] + .[(\$i + 1):])"
seeded on-behalf "quiet: a routine act with no undo entry" \
  "(.decision_log[] | select(.action == \"approve\") | .undo_logged) = false"
seeded on-behalf "quiet: a turn opens on an acknowledgement" \
  ".decision_log[$first_present].text |= \"Got it. \" + ."
seeded on-behalf "quiet: a turn runs past five lines" \
  "$first_present as \$i | .decision_log |= (.[0:(\$i + 1)] + [range(5) | {v: 2, seq: (980 + .), phase: \"session\", kind: \"present\", text: \"One more thing.\"}] + .[(\$i + 1):])"
seeded no-concepts "a plan-worthy ask not drafted with the operator" \
  'del(.decision_log[] | select(.action == "draft-with-operator"))'
seeded entry-args "two programs resumed without asking" \
  "(.decision_log[] | select(.action == \"entry\" and .route == \"ask\") | .route) = \"resume\""
seeded entry-args "the first turn after silence not saying what changed" \
  "(.decision_log[] | select(.first_turn == true) | .text) = \"Moving: three sessions.\""
seeded rule-entry "a proposal raised for a stated rule" \
  '.decision_log += [{kind: "decision", action: "proposal", seq: 998}]'
seeded rule-entry "no undo entry" 'del(.decision_log[] | select(.action == "undo-logged"))'
seeded mechanization "a declined pattern raised again" \
  '.decision_log += [{kind: "decision", action: "proposal", pattern: "reword-title", names: "rule", row: "standing-rule", ready_change: false, settings_written: false, seq: 997}]'
seeded mechanization "a settings change written" \
  "(.decision_log[] | select(.action == \"proposal\" and .pattern == \"allow-forge\") | .settings_written) = true"
seeded mechanization "a duty proposed where an inventory row covers" \
  "(.decision_log[] | select(.action == \"proposal\" and .pattern == \"rerun-checks\") | .names) = \"duty\""
seeded self-check "a failed self-check raising no item" \
  'del(.decision_log[] | select(.kind == "present" and .item != null))'
seeded shadow "an item raised while in shadow" \
  ".decision_log += [.decision_log[] | select(.kind == \"present\") | .item = {id: \"x\", subject: \"s\", link: \"l\", does: \"d\", asks: \"a\", right: \"r\", checked: \"c\", cluster: \"\", options: [{label: \"yes\", effect: \"e\"}, {label: \"no\", effect: \"e\"}]} | .seq = 996]"
seeded duty-proposal "a duty enabled before the yes" \
  "(.decision_log[] | select(.action == \"enable\") | .seq) = 1"
seeded drive-to-done "a fork settled instead of queued" \
  'del(.decision_log[] | select(.action == "queue"))'
seeded push-first "a wake delivered while busy" \
  "(.decision_log[] | select(.action == \"wake\" and .state == \"held\")) |= (.state = \"delivered\" | .via = \"push\")"
seeded status-form "a history section" ".decision_log[$first_present].text += \" History: ten items.\""
seeded status-form "the sections out of order" \
  "(.decision_log[] | select(.status_sections != null) | .status_sections) = [\"landed\", \"decisions\", \"moving\"]"
seeded delivery "an item delivered while away" \
  "(.decision_log[] | select(.kind == \"event\" and .event == \"presence\")) |= (.seq = 9999)"
seeded delivery "the lower-ranked item first" \
  "(.decision_log[] | select(.kind == \"present\" and .item.id == \"i2\") | .item.id) = \"i4\""
seeded nothing-dropped "an item dropped on a dead source" \
  "(.decision_log[] | select(.action == \"item-leave\" and .id == \"i2\") | .by) = \"source-dead\""
seeded picklist "the window settling nothing" 'del(.decision_log[] | select(.action == "settle-default"))'
seeded picklist "settled by default not shown" 'del(.decision_log[] | select(.settled_by_default != null))'
seeded answerable "nothing delivered" 'del(.decision_log[] | select(.kind == "present" and .item != null))'
seeded decide-or-queue "a human gate decided by mission control" \
  "(.decision_log[] | select(.action == \"queue\" and .reason == \"human-gate\")) |= (.action = \"decide\" | .by = \"mission-control\")"
seeded decide-or-queue "a settled decision queued" \
  "(.decision_log[] | select(.action == \"decide\")) |= (.action = \"queue\" | .reason = \"fork\")"
seeded follow-up "a row closed without evidence of the work" \
  "(.decision_log[] | select(.action == \"close-row\") | .evidence) = \"too-early\""
seeded follow-up "work started before the trigger" "(.decision_log[] | select(.action == \"start-work\") | .seq) = 1"
seeded draft-clipboard "a draft sent" \
  '([.decision_log[] | select(.action == "clipboard") | .seq][0]) as $d
    | .decision_log += [{kind: "answer", source: "operator", text: "yes, send it", seq: 994.5},
      {kind: "decision", action: "send", seq: 995, on_seq: 994.5, draft_seq: $d}]'
seeded first-run "an objective skipped" \
  'del(.decision_log[] | select(.first_run.objective == 3))'
seeded first-run "no knowledge-base skeleton written" \
  'del(.decision_log[] | select(.action == "write" and .what == "knowledge-base-skeleton"))'
seeded first-run "a step counter shown" \
  '(.decision_log[] | select(.first_run.objective == 2) | .text) |= "(2 of 6) " + .'
seeded first-run "no questions-left count on a question" \
  'del(.decision_log[] | select(.first_run.objective == 1) | .first_run.left)'
seeded first-run "the questions-left count overstated" \
  '(.decision_log[] | select(.first_run.objective == 1) | .first_run.left) = 99'
seeded first-run "the questions-left count not reaching zero" \
  '(.decision_log[] | select(.first_run.objective == 5) | .first_run.left) = 1'
seeded first-run "a settled objective asked" \
  '(.decision_log[] | select(.first_run.objective == 4) | .first_run) = {objective: 4, asked: true}'
seeded denial "the denial text paraphrased" \
  "(.decision_log[] | select(.action == \"relay-denial\") | .text) = \"push refused\""
seeded denial "another route tried" '.decision_log += [{kind: "decision", action: "retry-elsewhere", seq: 994}]'
seeded cited-source "a cited source given an age" \
  "(.decision_log[] | select(.source_modes != null) | .source_modes[0].age) = \"5m\""
seeded cited-source "the work-item picture claimed as known" \
  "(.decision_log[] | select(.source_modes != null) | .text) = \"Work items: four open.\""
seeded no-send "the relayed yes not ignored" 'del(.decision_log[] | select(.action == "ignore-yes" and .source == "session"))'
seeded relayed-kickoff "the record's answer relayed" \
  "(.decision_log[] | select(.action == \"kickoff-relay\") | .quote) = \"csv\""
seeded relayed-kickoff "a walk-through opened unasked" \
  'del(.decision_log[] | select(.action == "no-kickoff"))'
seeded relayed-kickoff "manual mode not handing the command" \
  'del(.decision_log[] | select(.action == "hand-command"))'
seeded succession "a failed self-check retiring the predecessor" \
  "(.decision_log[] | select(.action == \"keep-predecessor\") | .action) = \"predecessor-retired\""
seeded succession "no fallback where takeover is unsupported" \
  'del(.decision_log[] | select(.action == "offer-fallback"))'

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-behavioral-eval-mission-control.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-behavioral-eval-mission-control.sh"
