#!/bin/bash
# Tests for the authoring-surface repairs (operator-dialogue Task 10; REQ-J1.1,
# REQ-J1.3, REQ-J1.5, REQ-I1.4; D-15, D-19, D-21).
#
# Task 10 repairs the two authoring skills against the turn/artifact
# arbitration: /spec-draft's running summary becomes delta-plus-open and its
# phase-6 read-through becomes a projection of the bundle on disk;
# /spec-kickoff's resume path confirms signed sections at one line each, its
# lens-coverage table declares the artifact side, and its handoff report
# becomes a projection; both mirror their turn-side emissions into the
# structured log as turn records.
#
# REQ-J1.3 and REQ-J1.5 grade eval transcripts against fixtures the
# enforcement task owns, and REQ-J1.1's design-level half is a human review
# at the acceptance join. The assertions here are the cheap mechanical floor
# under both, the same role tests/test-operator-dialogue-doctrine.sh plays for
# Task 7: they pin that each converted form is stated where the sweep found
# the wall, that the superseded wording does not creep back, and that each
# repaired form cites the arbitration. They pin presence, not ordering (the
# eval's decisions-first invariant owns that), and they do not judge the prose.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTRINE="$REPO_ROOT/doctrine"
SKILLS="$REPO_ROOT/skills"

failures=0
assert_contains() {
  # assert_contains <description> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2')" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <description> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (expected NOT to find '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

flatten() {
  # Collapse every run of whitespace to one space, so a phrase wrapped at
  # markdownlint's column still matches as one needle.
  tr '\n' ' ' | tr -s '[:space:]' ' '
}

section() {
  # section <file> <heading-text> -> the body from that heading to the next
  # heading at the same or a shallower level, flattened. Empty output means the
  # heading is gone, which every caller below turns into a failed assertion.
  # Heading detection stands down inside a code fence (either delimiter; only
  # the opener closes it), as in the Task 7 sibling.
  awk -v want="$2" '
    /^(```|~~~)/ {
      if (!fence) { fence = 1; opener = substr($0, 1, 1) }
      else if (substr($0, 1, 1) == opener) { fence = 0 }
    }
    !fence && /^#+ / {
      line = $0
      sub(/^#+ +/, "", line)
      hashes = index($0, " ") - 1
      if (line == want) { depth = hashes; on = 1; next }
      if (on && hashes <= depth) { on = 0 }
    }
    on { print }
  ' "$1" | flatten
}

for f in "$SKILLS/spec-draft/SKILL.md" "$SKILLS/spec-kickoff/SKILL.md" \
  "$DOCTRINE/interaction-style.md" "$DOCTRINE/kickoff-dialogue.md" \
  "$DOCTRINE/kickoff-verification.md"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: $f missing" >&2
    exit 1
  fi
done

kickoff="$(flatten <"$SKILLS/spec-kickoff/SKILL.md")"

# ---------------------------------------------------------------------------
# 1. REQ-J1.3 / D-21 — /spec-draft's per-phase running summary is
#    delta-plus-open (the form itself, not the read-through's reference to
#    it), cites the rule, and the monotonic "summary of everything" form is
#    gone from the elicitation rule.
# ---------------------------------------------------------------------------
elicit="$(section "$SKILLS/spec-draft/SKILL.md" "Elicitation")"
assert_contains "spec-draft: the elicitation section exists" "Six phases" "$elicit"
assert_contains "spec-draft: the running summary is delta-plus-open" \
  "running summary in delta-plus-open form" "$elicit"
assert_contains "spec-draft: the summary carries what remains open" \
  "remains open" "$elicit"
assert_contains "spec-draft: the summary rule cites the arbitration" \
  "turn/artifact arbitration" "$elicit"
assert_absent "spec-draft: the monotonic summary wording is gone" \
  "summary of everything" "$elicit"

# ---------------------------------------------------------------------------
# 2. REQ-J1.5 / D-15 — the phase-6 read-through is a projection: never the
#    assembled bundle, a bounded excerpt with the bundle as the artifact, the
#    self-critique dispositions as counts plus open questions, and the full
#    list one request away.
# ---------------------------------------------------------------------------
assert_contains "spec-draft: the read-through is a projection" \
  "read-through as a projection" "$elicit"
assert_contains "spec-draft: the read-through is never the assembled bundle" \
  "never the assembled bundle" "$elicit"
assert_contains "spec-draft: the bundle on disk is the artifact" \
  "the bundle on disk is the artifact" "$elicit"
assert_contains "spec-draft: the read-through carries a bounded excerpt" \
  "bounded excerpt" "$elicit"
assert_contains "spec-draft: dispositions reach the turn as counts plus open questions" \
  "dispositions as counts plus the open questions" "$elicit"
assert_contains "spec-draft: the full disposition list stays one request away" \
  "full disposition list one request away" "$elicit"
assert_contains "spec-draft: the read-through cites the arbitration" \
  "interaction-style\`, the arbitration" "$elicit"
assert_absent "spec-draft: the cumulative read-through wording is gone" \
  "cumulative summary" "$elicit"

# ---------------------------------------------------------------------------
# 3. REQ-J1.3 — /spec-kickoff's resume path confirms signed sections at one
#    line each instead of replaying them, and the walkthrough's own summary
#    names the delta-plus-open form.
# ---------------------------------------------------------------------------
pre="$(section "$SKILLS/spec-kickoff/SKILL.md" "Pre-flight")"
assert_contains "spec-kickoff: the pre-flight section exists" \
  "Detect a partial brief" "$pre"
assert_contains "spec-kickoff: resume confirms signed sections at one line each" \
  "signed sections at one line each" "$pre"
assert_contains "spec-kickoff: resume never replays signed content" \
  "never a replay" "$pre"
assert_absent "spec-kickoff: the resume replay wording is gone" \
  "summary of every signed section" "$kickoff"

walk="$(section "$SKILLS/spec-kickoff/SKILL.md" "The walkthrough")"
assert_contains "spec-kickoff: the walkthrough section exists" \
  "Header block" "$walk"
assert_contains "spec-kickoff: the walkthrough summary is delta-plus-open" \
  "delta-plus-open running summary" "$walk"

# ---------------------------------------------------------------------------
# 4. REQ-I1.4 / D-15 — the lens-coverage table declares its side: recorded in
#    full in the brief section, counts plus notable rows in the turn. The
#    mandate lives in kickoff-verification (the skill's point-of-use doc), and
#    the skill's own sign-off step states the split too.
# ---------------------------------------------------------------------------
signoff="$(section "$SKILLS/spec-kickoff/SKILL.md" "Sign-off")"
assert_contains "spec-kickoff: the sign-off section exists" \
  "The lens review pass" "$signoff"
assert_contains "spec-kickoff: the lens table is recorded in full artifact-side" \
  "dispositions are artifact-side, recorded in full" "$signoff"
assert_contains "spec-kickoff: the turn carries counts plus notable rows" \
  "counts plus the notable rows" "$signoff"

lensrev="$(section "$DOCTRINE/kickoff-verification.md" \
  "Sign-off lens review — scope and fan-out (REQ-A3.3, D-45)")"
assert_contains "kickoff-verification: the lens review section exists" \
  "Lens-coverage table" "$lensrev"
assert_contains "kickoff-verification: the canonical table is artifact-side" \
  "canonical table is recorded artifact-side" "$lensrev"
assert_contains "kickoff-verification: the turn carries counts plus notable rows" \
  "counts plus the notable rows" "$lensrev"
assert_contains "kickoff-verification: the lens table cites the arbitration" \
  "interaction-style\`, the arbitration" "$lensrev"
assert_absent "kickoff-verification: the side-less emit mandate is gone" \
  "Emit the" "$lensrev"

# ---------------------------------------------------------------------------
# 5. REQ-J1.5 / D-15 — the handoff report is a projection: counts plus the
#    actionable residue at the turn, the full report artifact-side once the
#    PR body can carry it, regenerated on request when no PR exists, and the
#    merge step conditional on the PR being ready.
# ---------------------------------------------------------------------------
assert_contains "spec-kickoff: the handoff is a projection" \
  "The turn is its projection" "$signoff"
assert_contains "spec-kickoff: the handoff carries the actionable residue" \
  "actionable residue" "$signoff"
assert_contains "spec-kickoff: the full report lands in the PR body" \
  "written into the PR body" "$signoff"
assert_contains "spec-kickoff: the full report is regenerated when no PR exists" \
  "regenerated on request" "$signoff"
assert_contains "spec-kickoff: the next step is conditional on readiness" \
  "merge the spec PR once ready" "$signoff"
assert_contains "spec-kickoff: the handoff cites the arbitration" \
  "interaction-style\`, the arbitration" "$signoff"

# ---------------------------------------------------------------------------
# 6. D-19 — both surfaces mirror their projections into the structured log as
#    turn records at the emission point, the log schema names the record
#    kind and its distinct role, and the projection rule scopes the mirror to
#    surfaces that keep the log.
# ---------------------------------------------------------------------------
assert_contains "spec-draft: phase summaries are mirrored as turn records" \
  "mirrored into the structured decision/transcript log as a \`turn\` record" \
  "$elicit"
assert_contains "spec-kickoff: the run's projections are mirrored as turn records" \
  "mirrored into it as a \`turn\` record" "$walk"
log="$(section "$DOCTRINE/kickoff-dialogue.md" \
  "The structured decision/transcript log (REQ-G1.3, D-9)")"
assert_contains "kickoff-dialogue: the log section exists" "JSON Lines" "$log"
assert_contains "kickoff-dialogue: the schema names the turn record kind" \
  "/ \`turn\`)" "$log"
assert_contains "kickoff-dialogue: turn records mirror each projection" \
  "mirrored as one \`turn\` record" "$log"
proj="$(section "$DOCTRINE/interaction-style.md" "Turn projection")"
assert_contains "interaction-style: the projection is mirrored into the log" \
  "as one \`turn\` record" "$proj"
assert_contains "interaction-style: the mirror is scoped to surfaces keeping the log" \
  "A surface that keeps" "$proj"
assert_contains "interaction-style: an absent log is said, never improvised" \
  "never improvising" "$proj"

if [ "$failures" -ne 0 ]; then
  echo "test-operator-dialogue-authoring: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-operator-dialogue-authoring: all assertions passed"
