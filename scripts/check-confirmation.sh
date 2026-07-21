#!/usr/bin/env bash
# check-confirmation.sh — the reusable self-contained-confirmation structural
# check (operator-dialogue Task 2; REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-H1.2, D-7).
#
# A confirmation is answerable from its option set alone (D-7): prose above the
# selector is hidden by the operator's terminal, so the label and its
# consequence must carry the decision. This check asserts the *structural*
# invariants of that rule over a machine-readable confirmation:
#
#   - self-contained: a restating question stem, and every option restates its
#     own action and consequence (a non-empty description)  (REQ-E1.1);
#   - an explicit reject/defer option is present and no option is pre-selected
#     as a default  (REQ-E1.2);
#   - no generic OK/Yes/No/Approve option label, and no bare generic stem
#     (Approve? / OK? / Proceed?) that forces the operator back to unseen
#     context  (REQ-E1.3).
#
# It does NOT judge the *prose quality* of a restatement — that a description
# genuinely reads as an action-plus-consequence is the manual pilot (REQ-E1.4).
# The structural floor is: the description exists, a reject exists, no default,
# no generic tokens.
#
# Input contract (the structured decision log a skill emits, REQ-G1.3): a JSON
# document that is either one confirmation object or an array of them. Each
# confirmation is:
#   { "question": "<stem restating the decision>",
#     "options": [
#       { "label": "<names the action>",
#         "description": "<action + consequence>",
#         "reject": <true on the reject/defer option>,   // optional
#         "default": <true if pre-selected>,             // optional; also
#                                                        //   preselected/selected
#         "recommended": <true if grounded-recommended>  // optional; NOT a default
#       }, ... ] }
# A marked `recommended` option is permitted (a grounded recommendation may be
# marked, REQ-D1.4); only `default`/`preselected`/`selected` is a pre-selection.
#
# Usage: check-confirmation.sh [<file>]   (reads stdin when <file> is omitted)
#
# Exit codes: 0 every confirmation is self-contained; 1 one or more violations;
# 2 usage error (missing file, invalid JSON, or zero confirmations — fail-closed
# so a mis-fed check never silently passes).
#
# Output carries no untrusted input bytes: violations are reported by
# confirmation/option index and static rule text only, so an escape sequence
# embedded in a label can never drive the terminal (echo discipline,
# doctrine/security-posture.md). Input JSON is parsed as data by jq, never
# executed. Portable bash 3.2 / BSD tooling; jq is the only external dependency
# (already relied on by lint:json and sibling checks).
set -u

# Pin the C locale so the bracket expressions in the jq regexes mean exactly
# their ASCII range on every host (defensive; mirrors sibling checks).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below.
unset CDPATH

prog="check-confirmation"

if ! command -v jq >/dev/null 2>&1; then
  echo "$prog: jq not found on PATH (required to parse the confirmation JSON)" >&2
  exit 2
fi

input="${1:-}"
if [ -n "$input" ]; then
  if [ ! -f "$input" ]; then
    echo "$prog: input file not found: $input" >&2
    exit 2
  fi
  src="$input"
else
  src="-" # stdin
fi

# Read the whole document once so we can both validate/count and scan it without
# consuming stdin twice.
if ! doc="$(cat -- "$src")"; then
  echo "$prog: could not read input" >&2
  exit 2
fi

# Parse guard: invalid JSON is a usage error, distinct from a rule violation.
count="$(printf '%s' "$doc" | jq -e '
  if type == "array" then length
  elif type == "object" then 1
  else error("top-level JSON must be an object or an array of confirmations")
  end' 2>/dev/null)" || {
  echo "$prog: input is not valid confirmation JSON (expected an object or an array of them)" >&2
  exit 2
}

# Fail-closed on zero confirmations: a reformatted or empty log must not turn
# this check into a silent no-op (mirrors check-options-reference's zero-key
# guard).
if [ "$count" -eq 0 ]; then
  echo "$prog: no confirmations found in the input (fail-closed)" >&2
  exit 2
fi

# Emit one plain-text violation per line. Every message names the offending
# confirmation (and option) by numeric index and a static rule code; no value
# parsed from the input is interpolated, so the output is safe to echo raw.
violations="$(printf '%s' "$doc" | jq -r '
  def norm($s): ($s // "") | ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "");
  # A field is blank when it is absent, non-string, or whitespace-only. The
  # non-string arm matters because jq `// ""` only substitutes null/false, so a
  # truthy non-string (true, a number, an array) would otherwise stringify and
  # pass as a "restatement" that carries no text — the same string type-guard
  # the question stem already carries, applied to the option fields (REQ-E1.1).
  def blank($s): ($s | type) != "string" or (($s | gsub("[[:space:]]"; "") | length) == 0);
  def banned_labels: ["ok", "yes", "no", "y", "n", "approve", "confirm", "proceed"];
  def banned_stems:  ["approve?", "approve", "ok?", "ok", "confirm?", "confirm",
                      "proceed?", "proceed", "continue?", "continue",
                      "are you sure?", "yes/no?", "y/n?", "yes/no", "y/n"];

  (if type == "array" then . else [.] end)
  | to_entries[]
  | .key as $i | .value as $c
  | ( if ($c | type) != "object" then
        [ "confirmation #\($i): MALFORMED_CONFIRMATION — entry is not a JSON object (REQ-E1.1)" ]
      else
        ( [ # --- confirmation-level checks ---
            (if ($c.question | type) != "string" or blank($c.question)
               then "confirmation #\($i): STEM_MISSING — the question stem is empty; it must restate what is being decided (REQ-E1.1, REQ-E1.3)"
               else empty end),
            (if ($c.question | type) == "string" and ((banned_stems | index(norm($c.question))) != null)
               then "confirmation #\($i): STEM_GENERIC — the question stem is a bare generic prompt (OK/Yes/No/Approve/Proceed); restate the decision in full (REQ-E1.3)"
               else empty end),
            (if ($c.options | type) != "array" or (($c.options | length) < 2)
               then "confirmation #\($i): OPTIONS_TOO_FEW — a confirmation needs at least two options: an action and an explicit reject (REQ-E1.2)"
               else empty end),
            (if ($c.options | type) == "array"
                and (($c.options | map(select((type == "object") and .reject == true)) | length) == 0)
               then "confirmation #\($i): NO_REJECT — no option is marked reject:true; a confirmation must carry an explicit equal-prominence reject/defer option (REQ-E1.2)"
               else empty end)
          ]
          + ( ($c.options | if type == "array" then . else [] end)
              | to_entries
              | map(
                  .key as $j | .value as $o
                  | if ($o | type) != "object" then
                      [ "confirmation #\($i) option #\($j): MALFORMED_OPTION — option is not a JSON object (REQ-E1.1)" ]
                    else
                      [ (if blank($o.label)
                           then "confirmation #\($i) option #\($j): NO_LABEL — option has no label naming its action (REQ-E1.3)"
                           else empty end),
                        (if ($o.label | type) == "string" and ((banned_labels | index(norm($o.label))) != null)
                           then "confirmation #\($i) option #\($j): GENERIC_LABEL — option label is a generic OK/Yes/No/Approve token; name the action (REQ-E1.3)"
                           else empty end),
                        (if blank($o.description)
                           then "confirmation #\($i) option #\($j): NO_CONSEQUENCE — option has no description restating its action and consequence (REQ-E1.1)"
                           else empty end),
                        (if ($o.default == true) or ($o.preselected == true) or ($o.selected == true)
                           then "confirmation #\($i) option #\($j): DEFAULT_PRESELECTED — option is pre-selected as a default; no option may be pre-selected (REQ-E1.2)"
                           else empty end) ]
                    end
                )
              | add // []
            )
        )
      end )
  | .[]
')"

if [ -n "$violations" ]; then
  # Print each violation prefixed with the program name. The lines are static
  # rule text plus indices; no untrusted bytes flow through here.
  printf '%s\n' "$violations" | while IFS= read -r line; do
    printf '%s: %s\n' "$prog" "$line" >&2
  done
  exit 1
fi

echo "$prog: all $count confirmation(s) are self-contained"
exit 0
