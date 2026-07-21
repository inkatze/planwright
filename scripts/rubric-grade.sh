#!/usr/bin/env bash
# rubric-grade.sh — the experiential-quality rubric instrument in its INDEPENDENT
# GRADER form (operator-dialogue Task 6; REQ-H1.3, REQ-D1.1, REQ-D1.5, REQ-G1.4,
# D-11). It scores a kickoff run's durable, fixture-only artifacts against the
# CDC Clear Communication Index and IPDAS balance criteria, and prints a single
# verdict — `pass` or `fail` — on stdout, honoring the behavioral-eval harness's
# `--grader` contract (print the verdict and exit 0; exit non-zero when it cannot
# grade, so the harness degrades to the human rater rather than failing the run).
#
# It is the grader, NOT the self-audit: this instrument scores, and it is applied
# by an id DISTINCT from the driver (REQ-G1.4). The human remains the final rater
# (REQ-H1.3); a `pass` here is the mechanical floor the human confirms, never a
# substitute for the human's judgment of experiential quality.
#
# The criteria are mechanical PROXIES over the artifacts — they cannot judge
# whether prose genuinely reads well (that is the human's job), only whether the
# structural signals of clear, balanced communication are present:
#   - CDC CCI: a shared-understanding summary is present, names the downstream
#     effect (actionable), and surfaces no lone percentage (natural frequencies,
#     REQ-D1.5);
#   - IPDAS: a presented confirmation carries an explicit equal-weight reject and
#     no pre-selected default, and the run delivers no self-verdict on the spec
#     (REQ-D1.1).
#
# Input: one merged fixture-only artifacts object (the shape the harness passes a
# grader) as a file argument, or `-`/omitted for stdin. Parsed as data by jq;
# never executed.
#
# Exit: 0 with `pass` or `fail` on stdout (a graded verdict); 2 when the input is
# unparseable or absent (ungradeable → the harness treats non-zero as unavailable
# and degrades to human-rater scoring, substituting no self-graded score).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

prog="rubric-grade"

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

# The shared rubric criteria: emit `pass` iff every criterion holds. The criteria
# are a pure jq data transform (doctrine/security-posture.md: artifact values are
# data, never code). A parse failure is a non-zero (ungradeable) exit.
verdict="$(jq -r '
  def corpus:
    ([.decision_log[]? | select(.kind == "explanation") | .text]
     + [.decision_log[]? | select(.kind == "summary") | .text]
     + [.decision_log[]? | select(.kind == "confirmation") | .question]
     + [.decision_log[]? | select(.kind == "confirmation") | .options[]? | (.description, .label)]
     | map(select(. != null)) | join(" "));
  def confs: [.decision_log[]? | select(.kind == "confirmation")];
  # Keep this verdict blocklist in sync with grade.jq and rubric-self-audit.sh.
  def verdicts: ["this spec is good", "ready-quality", "i recommend approv",
                 "looks good to me", "quality score", "strong spec",
                 "i would approve", "i'"'"'d approve"];
  (corpus) as $c
  | ($c | ascii_downcase) as $lc
  | (confs) as $conf
  | (.sign_off.ready == true) as $ready
  | [
      # The CCI completion criteria apply only when the run reached readiness; a
      # run that correctly HELD (ready:false, a required decision undefined) has
      # no summary/confirmation and is exempt, not failed (REQ-C1.1).
      (($ready | not) or (([.decision_log[]? | select(.kind == "summary")] | length) > 0)),
      (($ready | not) or ($lc | contains("downstream"))),
      (($c | test("[0-9]+ *%")) | not),
      (($conf | length) == 0) or (([$conf[] | .options[]? | select(.reject == true)] | length) > 0),
      (([$conf[] | .options[]? | select((.default == true) or (.preselected == true) or (.selected == true))] | length) == 0),
      (verdicts | all(. as $v | ($lc | contains($v)) | not))
    ]
  | if all then "pass" else "fail" end
' -- "$src" 2>/dev/null)" || {
  echo "$prog: input is not gradeable (unparseable artifacts JSON)" >&2
  exit 2
}

case "$verdict" in
  pass | fail)
    printf '%s\n' "$verdict"
    exit 0
    ;;
  *)
    echo "$prog: input is not gradeable (no verdict produced)" >&2
    exit 2
    ;;
esac
