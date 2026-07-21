#!/bin/sh
# greeter/skill.sh — the generic fixture "skill" the behavioral-eval scaffold
# drives (operator-dialogue Task 5; REQ-G1.1, REQ-G1.2, REQ-G1.3). It is a
# deliberately tiny, real interactive TTY program that stands in for the true
# /spec-kickoff surface (wired in Task 6): it prints questions, blocks on the
# operator's answers read from the TTY, adapts one explanation to the operator's
# stated level (the behaviourally-observable calibration hook, REQ-B1.3 in
# miniature), and — only once the whole dialogue completes — writes the DURABLE
# artifacts the grader reads: a structured decision log and an eval-only sign-off
# record. Grading never scrapes the pane (REQ-G1.3); these files are the stable
# observables.
#
# Between turns it prints a stable at-prompt anchor line `EVAL-READY turn=<N>` so
# the harness's positive-footer-anchor idle detector (scripts/fleet-pane-detect.sh
# with FLEET_PANE_PROMPT_ANCHORS=eval-ready) can tell "awaiting input" from
# "working", and `turn=<N>` gives the driver a monotonic turn identity so a stale
# frame never causes a double-send.
#
# Input delivery is identical between the two run modes, because every read is
# `read || exit 0`: under REAL tmux the process is long-lived and blocks on the
# TTY between turns; under the hermetic test's stub tmux the accumulated answers
# are replayed on stdin and a partial replay simply EOF-exits before the artifact
# write, so only the complete dialogue ever produces a sign-off. The skill body
# is byte-identical across both — the stub reuses this real skill rather than
# re-implementing it.
#
# Usage: skill.sh <artifacts-dir>
# Env (set by the harness): PLANWRIGHT_EVAL_ONLY=1 marks the run non-authoritative
# (stamped into the sign-off); PLANWRIGHT_PUBLISH_DISABLED=1 asserts no publishing
# side effect is attempted (this fixture has none — it is the contract the real
# Task-6 surface honors).
#
# Portable POSIX sh. jq encodes every operator-supplied value, so the structured
# log and the sign-off are escape-safe and non-code-bearing (REQ-G1.6): an answer
# is data, never a fragment spliced into the artifact.
set -u
LC_ALL=C
export LC_ALL

art="${1:-}"
if [ -z "$art" ]; then
  echo "greeter/skill.sh: an artifacts directory argument is required" >&2
  exit 2
fi
mkdir -p "$art" 2>/dev/null || {
  echo "greeter/skill.sh: cannot create artifacts dir '$art'" >&2
  exit 2
}

log="$art/decision-log.jsonl"
signoff="$art/sign-off.json"
# Truncate at start so a partial replay never leaves a half-written log standing
# as if complete; the harness only grades once the sign-off appears.
: >"$log"

emit_ready() { printf 'EVAL-READY turn=%s\n' "$1"; }

# log_turn <n> <question-id> <answer> [depth] — append one escape-safe JSON
# object. jq --arg encodes the answer as data; no operator text is ever
# interpolated into a shell or jq program.
log_turn() {
  _lt_depth="${4:-}"
  jq -cn \
    --argjson turn "$1" \
    --arg q "$2" \
    --arg a "$3" \
    --arg d "$_lt_depth" \
    '{turn: $turn, question: $q, answer: $a} + (if $d == "" then {} else {depth: $d} end)' \
    >>"$log" 2>/dev/null || {
    echo "greeter/skill.sh: failed to append the decision-log turn" >&2
    exit 2
  }
}

# Turn 1 — the subject to greet.
printf 'Greeter: hello. What name should I greet?\n'
emit_ready 1
IFS= read -r name || exit 0
log_turn 1 name "$name"

# Turn 2 — the operator's stated level. The one explanation this fixture pitches
# to the frontier: an operator who signals expertise gets the brief form, a
# novice gets the full teach. The chosen depth is recorded so the persona
# divergence is behaviourally observable in the artifact (REQ-G1.2, seeds H1.4).
printf 'Greeter: how familiar are you with greetings? (novice / expert)\n'
emit_ready 2
IFS= read -r familiarity || exit 0
case $familiarity in
  *expert* | *Expert* | *EXPERT*)
    depth=brief
    printf 'Greeter: (brief) noted — skipping the primer.\n'
    ;;
  *)
    depth=full
    printf 'Greeter: (full) a greeting is a friendly salutation that opens a\n'
    printf 'Greeter:        conversation; here is the longer primer...\n'
    ;;
esac
log_turn 2 familiarity "$familiarity" "$depth"

# Turn 3 — a self-contained confirmation (REQ-E in miniature): each option
# restates its action and its TRUTHFUL consequence, and there is an explicit
# equal-weight reject. The stem does not lean on prose the operator's terminal
# may have scrolled off. Both choices are recorded — the run always writes a
# sign-off carrying the decision, so the eval has a durable artifact to grade
# either way; the option text says so rather than claiming a reject records
# nothing (which the skill does not do).
printf 'Greeter: Record your decision on the greeting for this run.\n'
printf 'Greeter:   [approve-and-record]  approve it; the sign-off records the approval\n'
printf 'Greeter:   [reject-and-record]   reject it; the sign-off records the rejection\n'
emit_ready 3
IFS= read -r decision || exit 0
log_turn 3 confirmation "$decision"

# The dialogue completed: write the durable sign-off. This fixture is a driver
# under eval, so it ALWAYS marks the record eval-only / non-authoritative — a
# driver-produced sign-off must never be mistaken for a human one (REQ-G1.6). The
# harness sets PLANWRIGHT_EVAL_ONLY=1 and re-verifies the marking post-run; the
# invariant here is unconditional, not gated on that signal.
#
# ATOMIC PUBLISH: write to a temp file and rename into place. The harness treats
# the mere existence of sign-off.json as "the run completed, grade it now"; a
# bare `>` truncates the file to zero bytes before jq writes it, so a grader poll
# that lands in that window would read empty/partial JSON and fail-closed. The
# rename makes the sign-off appear only once fully written.
if ! jq -n \
  --arg subject "$name" \
  --arg decision "$decision" \
  --arg depth "$depth" \
  '{subject: $subject, decision: $decision, depth: $depth, eval_only: true, authoritative: false}' \
  >"$signoff.tmp" 2>/dev/null; then
  echo "greeter/skill.sh: failed to write the sign-off record" >&2
  exit 2
fi
mv "$signoff.tmp" "$signoff" || {
  echo "greeter/skill.sh: failed to publish the sign-off record" >&2
  exit 2
}

printf 'Greeter: done — sign-off recorded (eval-only).\n'
exit 0
