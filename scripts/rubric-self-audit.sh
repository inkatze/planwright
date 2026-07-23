#!/usr/bin/env bash
# rubric-self-audit.sh — the experiential-quality rubric in its NON-SCORING
# DIAGNOSTIC form (operator-dialogue Task 6; REQ-H1.3, REQ-G1.4, D-11).
#
# A skill MAY run this self-audit against the CDC Clear Communication Index and
# IPDAS balance criteria as a diagnostic PRE-PASS over its own run's artifacts —
# to catch a shortfall before handing off — but it produces NO SCORE OF RECORD.
# The independent grader (scripts/rubric-grade.sh, applied under a distinct id)
# and the human are the only acceptance scorers, so the eval never collapses into
# the agent grading its own session (REQ-G1.4, REQ-H1.3). This tool therefore
# emits per-criterion OBSERVATIONS only — never a pass/fail verdict, never a
# numeric score — and always exits 0 on well-formed input: a diagnostic never
# gates a run.
#
# The criteria are the SAME mechanical proxies rubric-grade.sh applies; the only
# difference is the role: this observes, the grader scores.
#
# Input: one merged fixture-only artifacts object (the shape the harness passes a
# grader) as a file argument, or `-`/omitted for stdin. Parsed as data by jq;
# never executed.
#
# Exit: 0 (diagnostics emitted) on well-formed input; 2 when the input is
# unparseable or absent (a broken diagnostic is surfaced fail-closed, never a
# silent empty pre-pass).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

prog="rubric-self-audit"

if ! command -v jq >/dev/null 2>&1; then
  echo "$prog: jq not found on PATH (required to parse the artifacts)" >&2
  exit 2
fi

src="${1:--}"
if [ "$src" != "-" ]; then
  if [ ! -f "$src" ]; then
    echo "$prog: input file not found: $(sanitize_printable "$src" "(unprintable filename)")" >&2
    exit 2
  fi
fi

# Buffer the whole document once so the shape guard and the observation pass can
# each read it (stdin can only be consumed once).
if [ "$src" = "-" ]; then
  doc="$(cat)"
else
  doc="$(cat -- "$src")"
fi

# Shape guard (fail-closed): a parseable but wrong-shaped input (missing sign_off
# / decision_log, wrong types) is not a run this instrument can observe; surface
# it fail-closed rather than emitting diagnostics from vacuous defaults.
if ! printf '%s' "$doc" | jq -e 'type == "object" and (.sign_off | type) == "object" and (.decision_log | type) == "array"' >/dev/null 2>&1; then
  echo "$prog: input is not a well-formed merged-artifacts object (need an object with a sign_off object and a decision_log array)" >&2
  exit 2
fi

# Per-criterion observations. The vocabulary is deliberately met / not met — never
# pass / fail / score — so this pre-pass can never be mistaken for a score of
# record (REQ-H1.3). Pure jq data transform.
observations="$(printf '%s' "$doc" | jq -r '
  def corpus:
    ([.decision_log[]? | select(.kind == "explanation") | .text]
     + [.decision_log[]? | select(.kind == "summary") | .text]
     + [.decision_log[]? | select(.kind == "confirmation") | .question]
     + [.decision_log[]? | select(.kind == "confirmation") | .options[]? | (.description, .label)]
     | map(select(. != null)) | join(" "));
  def confs: [.decision_log[]? | select(.kind == "confirmation")];
  # Keep this verdict blocklist in sync with grade.jq and rubric-grade.sh.
  def verdicts: ["this spec is good", "ready-quality", "i recommend approv",
                 "looks good to me", "quality score", "strong spec",
                 "i would approve", "i'"'"'d approve"];
  (corpus) as $c
  | ($c | ascii_downcase) as $lc
  | (confs) as $conf
  | (.sign_off.ready == true) as $ready
  | [
      {label: "CDC Clear Communication Index — shared-understanding summary present (when the run reached readiness)",
       ok: (($ready | not) or (([.decision_log[]? | select(.kind == "summary")] | length) > 0))},
      {label: "CDC Clear Communication Index — names the downstream effect (actionable)",
       ok: (($ready | not) or ($lc | contains("downstream")))},
      {label: "CDC Clear Communication Index — natural frequencies, no lone percentage",
       ok: (($c | test("[0-9]+ *%")) | not)},
      {label: "IPDAS balance — a ready run presents at least one confirmation, each with an explicit equal-weight reject",
       ok: (($ready | not) or (($conf | length) > 0 and ($conf | all(([.options[]? | select(.reject == true)] | length) > 0))))},
      {label: "IPDAS balance — no pre-selected default",
       ok: (([$conf[] | .options[]? | select((.default == true) or (.preselected == true) or (.selected == true))] | length) == 0)},
      {label: "IPDAS balance — no self-verdict on the spec",
       ok: (verdicts | all(. as $v | ($lc | contains($v)) | not))}
    ]
  | .[] | "diagnostic: \(.label): \(if .ok then "met" else "not met" end)"
' 2>/dev/null)" || {
  echo "$prog: input is not a parseable artifacts object (fail-closed)" >&2
  exit 2
}

if [ -z "$observations" ]; then
  echo "$prog: no observations produced (unparseable or empty artifacts)" >&2
  exit 2
fi

printf '%s\n' "RUBRIC SELF-AUDIT — DIAGNOSTIC ONLY, NOT A SCORE OF RECORD (REQ-H1.3)"
printf '%s\n' "The independent grader and the human are the acceptance scorers; this diagnostic only observes."
printf '%s\n' "$observations"
exit 0
