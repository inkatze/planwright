#!/bin/bash
# Tests for the authoring-surface repairs (operator-dialogue Task 10; REQ-J1.1,
# REQ-J1.3, REQ-J1.5; D-15, D-19, D-21).
#
# Task 10 repairs the two authoring skills against the turn/artifact
# arbitration: /spec-draft's running summary becomes delta-plus-open and its
# phase-6 read-through becomes a projection of the bundle on disk;
# /spec-kickoff's resume path confirms signed sections at one line each, its
# lens-coverage table declares the artifact side, and its handoff report
# becomes a projection; both mirror their turn-side emissions into the
# structured log as turn records.
#
# The REQ-J1.1/J1.3/J1.5 test-spec arms grade eval transcripts against fixtures
# the enforcement task owns. The assertions here are the cheap mechanical floor
# under that lane, the same role tests/test-operator-dialogue-doctrine.sh plays
# for Task 7: they pin that each converted form is stated where the sweep found
# the wall, that the superseded wording does not creep back, and that each
# surface cites the arbitration. They do not judge the prose.
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

draft="$(flatten <"$SKILLS/spec-draft/SKILL.md")"
kickoff="$(flatten <"$SKILLS/spec-kickoff/SKILL.md")"

# ---------------------------------------------------------------------------
# 1. REQ-J1.3 / D-21 — /spec-draft's per-phase running summary is
#    delta-plus-open, and the monotonic "everything decided so far" form is
#    gone from the elicitation rule.
# ---------------------------------------------------------------------------
elicit="$(section "$SKILLS/spec-draft/SKILL.md" "Elicitation")"
assert_contains "spec-draft: the elicitation section exists" "phase" "$elicit"
assert_contains "spec-draft: the running summary is delta-plus-open" \
  "delta-plus-open" "$elicit"
assert_contains "spec-draft: the summary carries what remains open" \
  "remains open" "$elicit"
assert_absent "spec-draft: the monotonic summary wording is gone" \
  "everything decided so far" "$elicit"

# ---------------------------------------------------------------------------
# 2. REQ-J1.5 / D-15 — the phase-6 read-through is a projection: a bounded
#    excerpt with the bundle as the artifact, self-critique dispositions as
#    counts plus open questions; never the assembled bundle plus a cumulative
#    summary in one turn.
# ---------------------------------------------------------------------------
assert_contains "spec-draft: the read-through is a projection" \
  "projection" "$elicit"
assert_contains "spec-draft: the read-through carries a bounded excerpt" \
  "bounded excerpt" "$elicit"
assert_contains "spec-draft: dispositions reach the turn as counts" \
  "as counts" "$elicit"
assert_contains "spec-draft: open questions still reach the turn" \
  "open questions" "$elicit"
assert_absent "spec-draft: the cumulative read-through wording is gone" \
  "cumulative summary" "$draft"

# ---------------------------------------------------------------------------
# 3. REQ-J1.3 — /spec-kickoff's resume path confirms signed sections at one
#    line each instead of replaying them.
# ---------------------------------------------------------------------------
pre="$(section "$SKILLS/spec-kickoff/SKILL.md" "Pre-flight")"
assert_contains "spec-kickoff: the pre-flight section exists" "brief" "$pre"
assert_contains "spec-kickoff: resume confirms signed sections at one line each" \
  "one line each" "$pre"
assert_absent "spec-kickoff: the resume replay wording is gone" \
  "running summary of every signed section" "$pre"

# ---------------------------------------------------------------------------
# 4. REQ-I1.4 / D-15 — the lens-coverage table declares its side: recorded in
#    full in the brief section, counts plus notable rows in the turn. The
#    mandate lives in kickoff-verification (the skill's point-of-use doc), and
#    the skill's own sign-off step states the split too.
# ---------------------------------------------------------------------------
signoff="$(section "$SKILLS/spec-kickoff/SKILL.md" "Sign-off")"
assert_contains "spec-kickoff: the sign-off section exists" "anchor" "$signoff"
assert_contains "spec-kickoff: the lens table is artifact-side" \
  "artifact-side" "$signoff"
assert_contains "spec-kickoff: the turn carries counts plus notable rows" \
  "notable rows" "$signoff"

lensrev="$(section "$DOCTRINE/kickoff-verification.md" \
  "Sign-off lens review — scope and fan-out (REQ-A3.3, D-45)")"
assert_contains "kickoff-verification: the lens review section exists" \
  "Lens-coverage table" "$lensrev"
assert_contains "kickoff-verification: the lens table is artifact-side" \
  "artifact-side" "$lensrev"
assert_contains "kickoff-verification: the turn carries counts plus notable rows" \
  "notable rows" "$lensrev"
assert_absent "kickoff-verification: the side-less emit mandate is gone" \
  "Emit the canonical lens-coverage table." "$lensrev"

# ---------------------------------------------------------------------------
# 5. REQ-J1.5 / D-15 — the handoff report is a projection: counts plus the
#    actionable residue at the turn, the full report artifact-side.
# ---------------------------------------------------------------------------
assert_contains "spec-kickoff: the handoff is a projection" \
  "projection" "$signoff"
assert_contains "spec-kickoff: the handoff carries the actionable residue" \
  "actionable residue" "$signoff"

# ---------------------------------------------------------------------------
# 6. D-19 — both surfaces mirror their turn-side emissions into the structured
#    log as turn records, and the log schema names the record kind.
# ---------------------------------------------------------------------------
assert_contains "spec-draft: turn-side emissions are mirrored as turn records" \
  "turn\` record" "$draft"
assert_contains "spec-kickoff: turn-side emissions are mirrored as turn records" \
  "turn\` record" "$kickoff"
log="$(section "$DOCTRINE/kickoff-dialogue.md" \
  "The structured decision/transcript log (REQ-G1.3, D-9)")"
assert_contains "kickoff-dialogue: the log section exists" "JSON Lines" "$log"
assert_contains "kickoff-dialogue: the schema names the turn record kind" \
  "\`turn\`" "$log"
proj="$(section "$DOCTRINE/interaction-style.md" "Turn projection")"
assert_contains "interaction-style: the projection is mirrored into the log" \
  "turn\` record" "$proj"

# ---------------------------------------------------------------------------
# 7. Done-when — each repaired surface cites the arbitration by name.
# ---------------------------------------------------------------------------
assert_contains "spec-draft cites the arbitration" "arbitration" "$draft"
assert_contains "spec-kickoff cites the arbitration" "arbitration" "$kickoff"

if [ "$failures" -ne 0 ]; then
  echo "test-operator-dialogue-authoring: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-operator-dialogue-authoring: all assertions passed"
