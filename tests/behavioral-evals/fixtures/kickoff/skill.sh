#!/bin/sh
# kickoff/skill.sh — the kickoff eval fixture skill (operator-dialogue Task 6;
# REQ-H1.2, REQ-A1.3-adjacent, REQ-C1.1, REQ-C1.2, REQ-C1.5, REQ-D1.1, REQ-B1.5,
# REQ-E1.1, REQ-F1.2, D-11). It is a DETERMINISTIC stand-in for the real,
# model-backed /spec-kickoff surface: driving the true skill needs a live Claude
# TTY session (nondeterministic, on-demand, model-priced), so the assertable
# INVARIANTS of a kickoff run are pinned here against a faithful shell model that
# exercises each measurable-acceptance behavior. The experiential qualities of a
# real kickoff (was the teaching genuinely well-pitched?) remain scored by the
# independent grader and the human (REQ-H1.3), never asserted here.
#
# It models one guided kickoff dialogue that instantiates the three disciplines
# and writes the DURABLE artifacts a grader reads (a structured decision log and
# an eval-only sign-off record) — never a scraped pane (REQ-G1.3):
#
#   - TEACH TO THE FRONTIER (REQ-B1.3/B1.5): explanation depth is pitched to the
#     operator's stated level (calibration), scaffolding FADES across sections,
#     and every normative token the explanation conveys (SHALL/MUST/…) is
#     preserved VERBATIM in the rendered text and recorded, so B1.5 is checkable.
#   - INTERVIEW TO COMPLETENESS (REQ-C1.1/C1.2/C1.5): a required design decision
#     must be defined before the run is READY; unparseable input RE-PROMPTS
#     (bounded) without corrupting the running calibration estimate; a changed
#     upstream answer REOPENS the dependent decision rather than leaving it stale.
#   - PRESENT WITHOUT STEERING (REQ-D1.1/E1.1/F1.2): the design fork is presented
#     non-directively with no pre-selected default; the sign-off is a
#     SELF-CONTAINED confirmation (each option restates its action + consequence,
#     an explicit equal-weight reject, no default); a shared-understanding SUMMARY
#     is emitted BEFORE the confirmation decision; and the skill NEVER delivers a
#     quality verdict on the spec on its own behalf.
#
# Replay model (identical to greeter/skill.sh): every read is `read || exit 0`,
# so under the hermetic stub the accumulated answers replay on stdin and a
# partial replay EOF-exits before the artifact write; only the complete dialogue
# writes a sign-off. The log is truncated at start so a partial replay never
# leaves a half-written log standing. Turn identity is a MONOTONIC counter — a
# re-prompt or a reopen advances it — so the driver's `turn=<N>` tracking never
# double-sends and each read maps to answer.<N>.
#
# Usage: skill.sh <artifacts-dir>
# Env (set by the harness): PLANWRIGHT_EVAL_ONLY=1 / PLANWRIGHT_PUBLISH_DISABLED=1
# — this fixture always marks its sign-off eval-only/non-authoritative and has no
# publish path, the contract the real Task-6 surface inherits (REQ-G1.6).
#
# Portable POSIX sh. jq encodes every operator-supplied value, so the structured
# log and the sign-off are escape-safe and non-code-bearing (REQ-G1.6): an answer
# is data, never a fragment spliced into an artifact.
set -u
LC_ALL=C
export LC_ALL

art="${1:-}"
if [ -z "$art" ]; then
  echo "kickoff/skill.sh: an artifacts directory argument is required" >&2
  exit 2
fi
mkdir -p "$art" 2>/dev/null || {
  echo "kickoff/skill.sh: cannot create artifacts dir '$art'" >&2
  exit 2
}

log="$art/decision-log.jsonl"
signoff="$art/sign-off.json"
: >"$log"

subject="operator-dialogue-fixture"

# Monotonic turn identity. next_turn advances it; emit_ready prints the at-prompt
# anchor the driver keys reads on. Prose printed between prompts never contains
# `turn=` so the driver's last-anchor scan stays unambiguous.
t=0
next_turn() { t=$((t + 1)); }
emit_ready() { printf 'EVAL-READY turn=%s\n' "$t"; }

# log_entry <json> — append one escape-safe JSON object (already built by jq).
log_entry() {
  printf '%s\n' "$1" >>"$log" 2>/dev/null || {
    echo "kickoff/skill.sh: failed to append a decision-log entry" >&2
    exit 2
  }
}

# parse_level <raw> — lenient: any input resolves to a defined level (novice
# unless the operator signals expertise), so the calibration seed is never
# "undefined" (the completeness gate is about the DESIGN decision, not the level).
parse_level() {
  case "$1" in
    *expert* | *Expert* | *EXPERT* | *advanced* | *fluent*) printf 'expert' ;;
    *) printf 'novice' ;;
  esac
}

# parse_decision <raw> — STRICT: only the two presented option ids are defined;
# anything else is unparseable (empty), which drives the re-prompt / completeness
# gate. This is the input-robustness boundary (REQ-C1.5).
parse_decision() {
  case "$1" in
    option-alpha) printf 'option-alpha' ;;
    option-beta) printf 'option-beta' ;;
    *) printf '' ;;
  esac
}

depth_for() { # depth_for <level> -> full|brief
  if [ "$1" = "expert" ]; then printf 'brief'; else printf 'full'; fi
}

# render_section <n> <concept> <depth> — echo the rendered explanation text for a
# section at the given depth. Each carries a VERBATIM normative token (SHALL);
# fade is modeled by the brief form being materially shorter, and section 2 is
# always terser than section 1 for the same depth (scaffolding fades across
# sections, REQ-B1.3). No verdict phrasing appears in any branch (REQ-D1.1).
render_section() {
  case "$1.$3" in
    1.full) printf 'A self-contained confirmation means each option SHALL restate its own action and its consequence, so the choice is answerable from the option set alone even when the prose above the selector is scrolled off. That is why the sign-off below spells out what each choice records.' ;;
    1.brief) printf 'Confirmations are self-contained: each option SHALL restate its action and consequence.' ;;
    2.full) printf 'A surfaced likelihood SHALL be given as a natural frequency with a fixed denominator (say, 8 in 10), not a lone percentage.' ;;
    2.brief) printf 'Likelihoods SHALL be natural frequencies (8 in 10), never a lone percentage.' ;;
    *) printf 'This concept SHALL be conveyed without softening its normative tokens.' ;;
  esac
}

# text_len <s> — portable character count (the length metric the persona-pilot
# divergence + fade assertions read from the sign-off).
text_len() { printf '%s' "$1" | wc -c | tr -d ' '; }

# ---- calibration: a lightweight running per-run uptake estimate (REQ-B1.4). It
# increments only on a PARSED, substantive answer; unparseable input leaves it
# unchanged (REQ-C1.5), which is what makes "garbage does not corrupt the
# estimate" checkable. It is a single integer, deliberately NOT a learner model.
calibration=0

# ---- Turn 1: the operator's level (calibration seed) -------------------------
next_turn
printf 'Kickoff: before we walk the spec, how familiar are you with planwright kickoff decisions? (novice / expert)\n'
emit_ready
IFS= read -r level_raw || exit 0
level="$(parse_level "$level_raw")"
calibration=$((calibration + 1))
depth="$(depth_for "$level")"
log_entry "$(jq -cn --argjson turn "$t" --arg a "$level_raw" --arg lvl "$level" --argjson cal "$calibration" \
  '{turn:$turn, kind:"question", concept:"level", answer:$a, level:$lvl, calibration:$cal}')"

# ---- Two taught sections, pitched to the frontier and faded -------------------
# Rendered as durable explanation entries (comprehend-then-teach); the normative
# token each conveys is recorded so B1.5 non-distortion is mechanically checkable.
sec1_text="$(render_section 1 confirmation-rule "$depth")"
sec1_len="$(text_len "$sec1_text")"
printf 'Kickoff (section 1/2): %s\n' "$sec1_text"
log_entry "$(jq -cn --argjson turn "$t" --arg text "$sec1_text" --arg depth "$depth" --argjson chars "$sec1_len" --argjson cal "$calibration" \
  '{turn:$turn, kind:"explanation", concept:"confirmation-rule", section:1, depth:$depth, chars:$chars, normative_tokens:["SHALL"], text:$text}')"

sec2_text="$(render_section 2 frequency-rule "$depth")"
sec2_len="$(text_len "$sec2_text")"
printf 'Kickoff (section 2/2): %s\n' "$sec2_text"
log_entry "$(jq -cn --argjson turn "$t" --arg text "$sec2_text" --arg depth "$depth" --argjson chars "$sec2_len" --argjson cal "$calibration" \
  '{turn:$turn, kind:"explanation", concept:"frequency-rule", section:2, depth:$depth, chars:$chars, normative_tokens:["SHALL"], text:$text}')"

# ---- Required design decision, presented without steering --------------------
# Two options in parallel, neutral order, NO pre-selected default. The decision
# is REQUIRED: the run is not READY until it is defined (REQ-C1.1). Unparseable
# input re-prompts (bounded) without touching calibration (REQ-C1.5).
present_fork() {
  printf 'Kickoff: one design decision is open — how should the fixture record a deferred sub-decision?\n'
  printf 'Kickoff:   [option-alpha]  record it inline in the brief; downstream reads it from the brief body\n'
  printf 'Kickoff:   [option-beta]   record it in a separate register; downstream reads it from the register\n'
  printf 'Kickoff: reply with option-alpha or option-beta.\n'
}

decision=""
attempts=0
max_attempts=3 # the initial ask plus two re-prompts
while [ "$attempts" -lt "$max_attempts" ]; do
  next_turn
  present_fork
  emit_ready
  IFS= read -r dec_raw || exit 0
  attempts=$((attempts + 1))
  decision="$(parse_decision "$dec_raw")"
  if [ -n "$decision" ]; then
    calibration=$((calibration + 1))
    log_entry "$(jq -cn --argjson turn "$t" --arg a "$dec_raw" --arg d "$decision" --argjson cal "$calibration" \
      '{turn:$turn, kind:"question", concept:"decision", answer:$a, decision:$d, calibration:$cal}')"
    break
  fi
  # Unparseable: re-prompt, restating what is needed; calibration is UNCHANGED.
  log_entry "$(jq -cn --argjson turn "$t" --arg a "$dec_raw" --argjson cal "$calibration" \
    '{turn:$turn, kind:"reprompt", concept:"decision", reason:"unparseable", answer:$a, calibration:$cal}')"
done

if [ -z "$decision" ]; then
  # The required decision stayed undefined through the re-prompt budget: the run
  # is NOT ready. Record a durable, blocked sign-off (no false readiness declared,
  # no confirmation reached) — completeness holds (REQ-C1.1).
  jq -n --arg subject "$subject" --arg level "$level" --arg depth "$depth" --argjson cal "$calibration" \
    '{subject:$subject, level:$level, depth:$depth, calibration:$cal, decision:null, approved:false,
      ready:false, blocked_on:["design-decision"], summary_before_confirmation:false, reopened:false,
      normative_tokens_presented:["SHALL"], eval_only:true, authoritative:false}' \
    >"$signoff.tmp" 2>/dev/null || {
    echo "kickoff/skill.sh: failed to write the blocked sign-off" >&2
    exit 2
  }
  mv "$signoff.tmp" "$signoff" || {
    echo "kickoff/skill.sh: failed to publish the blocked sign-off" >&2
    exit 2
  }
  printf 'Kickoff: the design decision is still undefined — holding; not ready to sign off.\n'
  exit 0
fi

# ---- Reopen dependents on a changed upstream answer (REQ-C1.2) ---------------
# Offer to restate the level; if it CHANGED, the dependent depth is recomputed
# and the dependent decision is REOPENED (re-asked), rather than leaving the
# stale answer standing.
reopened=false
next_turn
printf 'Kickoff: you said your level was %s — restate it now if it changed, or repeat it to confirm.\n' "$level"
emit_ready
IFS= read -r level2_raw || exit 0
level2="$(parse_level "$level2_raw")"
if [ "$level2" != "$level" ]; then
  reopened=true
  log_entry "$(jq -cn --argjson turn "$t" --arg from "$level" --arg to "$level2" --argjson cal "$calibration" \
    '{turn:$turn, kind:"reopen", concept:"decision", reason:"upstream-level-changed", from:$from, to:$to, calibration:$cal}')"
  level="$level2"
  depth="$(depth_for "$level")"
  # Re-ask the dependent decision; the stale answer is discarded.
  decision=""
  next_turn
  present_fork
  emit_ready
  IFS= read -r dec2_raw || exit 0
  decision="$(parse_decision "$dec2_raw")"
  if [ -z "$decision" ]; then
    jq -n --arg subject "$subject" --arg level "$level" --arg depth "$depth" --argjson cal "$calibration" \
      '{subject:$subject, level:$level, depth:$depth, calibration:$cal, decision:null, approved:false,
        ready:false, blocked_on:["design-decision"], summary_before_confirmation:false, reopened:true,
        normative_tokens_presented:["SHALL"], eval_only:true, authoritative:false}' \
      >"$signoff.tmp" 2>/dev/null && mv "$signoff.tmp" "$signoff"
    printf 'Kickoff: the reopened decision is undefined — holding; not ready to sign off.\n'
    exit 0
  fi
  calibration=$((calibration + 1))
  log_entry "$(jq -cn --argjson turn "$t" --arg a "$dec2_raw" --arg d "$decision" --argjson cal "$calibration" \
    '{turn:$turn, kind:"question", concept:"decision-reopened", answer:$a, decision:$d, calibration:$cal}')"
else
  log_entry "$(jq -cn --argjson turn "$t" --arg a "$level2_raw" --argjson cal "$calibration" \
    '{turn:$turn, kind:"question", concept:"level-confirm", answer:$a, calibration:$cal}')"
fi

# ---- Shared-understanding summary BEFORE the confirmation (REQ-F1.2) ---------
# Logged at the current turn value, strictly before the confirmation turn, so the
# "summary emitted before the decision" ordering is mechanically checkable. It
# presents information about what is being approved and what changes downstream —
# never a quality verdict on the spec (REQ-D1.1).
summary_text="Here is what you are about to approve: the design records the deferred sub-decision via ${decision}, and this walkthrough was pitched at ${depth} depth. Downstream, /execute-task builds from this signed brief; sign-off flips the spec Ready, and the merge stays yours — nothing merges here."
printf 'Kickoff: %s\n' "$summary_text"
summary_turn="$t"
log_entry "$(jq -cn --argjson turn "$t" --arg text "$summary_text" --argjson cal "$calibration" \
  '{turn:$turn, kind:"summary", text:$text, calibration:$cal}')"

# ---- Self-contained confirmation (REQ-E1.1, REQ-E1.2, REQ-E1.3) --------------
# Each option restates its action + consequence; an explicit equal-weight reject
# is present; NO option is pre-selected. Emitted as a structured confirmation
# object so Task 2's check-confirmation.sh can grade it directly.
next_turn
conf_turn="$t"
printf 'Kickoff: Record your sign-off decision for this kickoff run — how should this run record your call on the design above?\n'
printf 'Kickoff:   [record-approval]   record your approval; the sign-off marks the design accepted and the run is captured eval-only\n'
printf 'Kickoff:   [record-rejection]  record your rejection; the sign-off marks the design not accepted and nothing downstream proceeds from it\n'
emit_ready
IFS= read -r conf_raw || exit 0
approved=false
[ "$conf_raw" = "record-approval" ] && approved=true
conf_obj="$(jq -cn --argjson turn "$conf_turn" --arg a "$conf_raw" \
  '{turn:$turn, kind:"confirmation",
    question:"Record your sign-off decision for this kickoff run — how should this run record your call on the design above?",
    options:[
      {label:"record-approval", description:"record your approval; the sign-off marks the design accepted and the run is captured eval-only"},
      {label:"record-rejection", description:"record your rejection; the sign-off marks the design not accepted and nothing downstream proceeds from it", reject:true}
    ],
    answer:$a}')"
log_entry "$conf_obj"

# ---- The durable, READY sign-off ---------------------------------------------
# All required decisions are defined, so the run is ready; blocked_on is empty
# (completeness holds). Always eval-only / non-authoritative (REQ-G1.6). Atomic
# publish (tmp + mv) so a grader poll never reads a partial file.
if ! jq -n \
  --arg subject "$subject" \
  --arg level "$level" \
  --arg depth "$depth" \
  --argjson cal "$calibration" \
  --arg decision "$decision" \
  --argjson approved "$approved" \
  --argjson reopened "$reopened" \
  --argjson sec1 "$sec1_len" \
  --argjson sec2 "$sec2_len" \
  --argjson summary_turn "$summary_turn" \
  --argjson conf_turn "$conf_turn" \
  '{subject:$subject, level:$level, depth:$depth, calibration:$cal, decision:$decision, approved:$approved,
    ready:true, blocked_on:[], summary_before_confirmation:($summary_turn < $conf_turn), reopened:$reopened,
    sections:[{concept:"confirmation-rule", section:1, depth:$depth, chars:$sec1},
              {concept:"frequency-rule", section:2, depth:$depth, chars:$sec2}],
    normative_tokens_presented:["SHALL"], eval_only:true, authoritative:false}' \
  >"$signoff.tmp" 2>/dev/null; then
  echo "kickoff/skill.sh: failed to write the sign-off record" >&2
  exit 2
fi
mv "$signoff.tmp" "$signoff" || {
  echo "kickoff/skill.sh: failed to publish the sign-off record" >&2
  exit 2
}

printf 'Kickoff: done — sign-off recorded (eval-only), ready=%s.\n' "true"
exit 0
