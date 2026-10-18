#!/bin/bash
# Tests for the persona fan-out helper (inception REQ-P1.3–P1.9, REQ-B1.3 ·
# D-2, D-6, D-7, D-18).
#
# What is pinned: the frame compiles to the normative six-part template; the
# seat-count triage stays in the three-to-five band; the Gate 1 roster
# discloses backend, sessions, cost, and every lost decorrelation; a seat brief
# carries its card's task framing and the mandatory escalation section, and
# nothing meant for the synthesizer; the seat-artifact check enforces the typed
# escalation section; the synthesis input carries no seat identity or ordering
# cue, and attribution returns only in the final table; the synthesis and
# challenge prompts are persona-free; the amendment runs once; Gate 2 offers
# typed human powers; and staffing honesty auto-files coverage risks, collapsing
# them on a zero-seat run (REQ-P1.8).
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FANOUT="$REPO_ROOT/scripts/inception-fanout.sh"
VALIDATE="$REPO_ROOT/scripts/inception-validate.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}
assert_before() {
  case "$4" in
    *"$2"*"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected '$2' before '$3')" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_file() {
  if [ -f "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 ($2 was not written)" >&2
    failures=$((failures + 1))
  fi
}
assert_no_file() {
  if [ -e "$2" ]; then
    echo "FAIL: $1 ($2 exists)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

if [ ! -x "$FANOUT" ]; then
  echo "FAIL: fan-out helper missing or not executable at $FANOUT" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

fresh() {
  d="$(mktemp -d "$tmp/vXXXXXX")" || exit 1
  inception_fixture_write "$d" "${1:-untracked}" || exit 1
  printf '%s' "$d"
}
newrun() { mktemp -d "$tmp/runXXXXXX"; }
sed_i() { sed "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }

export PLANWRIGHT_INCEPTION_TODAY=2026-08-26
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_REPO_ROOT=none
unset CLAUDE_PLUGIN_ROOT CLAUDE_DIR CLAUDE_PLUGIN_DATA

# A team overlay supplying a second card with a stance axis, so a roster can
# staff two disciplines and run one at a pole. It is the core card with its id,
# display name, role, and stance changed, so it lints clean by construction.
overlay="$tmp/overlay"
mkdir -p "$overlay/catalogs" "$overlay/cards"
cat >"$overlay/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: ops-design
    discipline: "Operations design"
YAML
sed -e 's/^# Product strategy — discipline card$/# Operations design — discipline card/' \
  -e 's/^\*\*Card-id:\*\* product-strategy$/**Card-id:** ops-design/' \
  -e 's/^\*\*Stance-axis:\*\* none$/**Stance-axis:** optimist-skeptic/' \
  -e 's/^Lays out the venture.s strategic options/Maps the operating workflow the venture changes/' \
  "$REPO_ROOT/cards/product-strategy.md" >"$overlay/cards/ops-design.md"
export PLANWRIGHT_ADOPTER_OVERLAY="$overlay"

# ---------------------------------------------------------------------------
# 1. The frame compiles to the normative template, in order (D-18).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$FANOUT" frame "$v" 2>&1)"
rc=$?
assert_eq "frame: exit 0" "0" "$rc"
assert_file "frame: writes exports/frame.md" "$v/exports/frame.md"
assert_contains "frame: reports the path" "exports/frame.md" "$out"
frame="$(cat "$v/exports/frame.md" 2>/dev/null)"
assert_before "frame: problem statement before evidence" "## Problem statement" "## Evidence pointers" "$frame"
assert_before "frame: evidence before constraints" "## Evidence pointers" "## Constraints" "$frame"
assert_before "frame: constraints before decisions" "## Constraints" "## Door-classified decisions" "$frame"
assert_before "frame: decisions before staffing" "## Door-classified decisions" "## Discipline staffing table" "$frame"
assert_before "frame: staffing before metric state" "## Discipline staffing table" "## Success metric and kill criteria" "$frame"
assert_contains "frame: names the venture" "# Northwind Signals — Frame" "$frame"
assert_contains "frame: carries the framing, joined" "re-key the same incident summary into three tools; the duplication shows up as dead time" "$frame"
assert_contains "frame: carries who hurts" "closing an incident at end of shift" "$frame"
assert_contains "frame: carries the sources register" "**workflow audit**" "$frame"
assert_contains "frame: carries a held-out source as held out" "held out: the notes name individuals" "$frame"
assert_contains "frame: carries the no-gos" "No agent-authored customer messaging" "$frame"
assert_contains "frame: carries a skipped appetite as skipped" "_Skipped: appetite is set at the portfolio level" "$frame"
assert_contains "frame: carries inherited constraints" "incident-tooling consolidation" "$frame"
assert_contains "frame: lists the open decision with its door" "**DEC-1** (two-way, open)" "$frame"
assert_not_contains "frame: omits a decided decision" "DEC-2" "$frame"
assert_contains "frame: carries the staffing table" "| org-design | unstaffed | none |" "$frame"
assert_contains "frame: carries the success metric" "below ten minutes" "$frame"
assert_contains "frame: classifies a clear kill criterion" "by 2026-10-01 — clear" "$frame"
assert_contains "frame: classifies an approaching kill criterion" "by 2026-09-15 — approaching" "$frame"
first="$(cat "$v/exports/frame.md")"
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: regeneration is byte-identical" "$first" "$(cat "$v/exports/frame.md")"
PLANWRIGHT_INCEPTION_TODAY=2026-09-20 "$FANOUT" frame "$v" >/dev/null 2>&1
assert_contains "frame: a passed date is tripped" "by 2026-09-15 — tripped" "$(cat "$v/exports/frame.md")"

v="$(fresh)"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$v/$f.md" 's/^\*\*Format-version:\*\* 1.0$/**Format-version:** 9.0/'
done
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: an unsupported format-version is refused (exit 3)" "3" "$?"
assert_no_file "frame: nothing written on a refusal" "$v/exports/frame.md"

v="$(fresh)"
mkdir -p "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$v/exports"
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: a symlinked exports/ is refused" "2" "$?"
assert_no_file "frame: nothing written through the link" "$tmp/elsewhere/frame.md"

# ---------------------------------------------------------------------------
# 2. Seat-count triage stays in the three-to-five band (REQ-P1.6).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$FANOUT" triage "$v")"
assert_contains "triage: a low-stake bundle gets the default three" "seats	3" "$out"
assert_contains "triage: names the signal" "signal	1" "$out"
for n in 3 4 5 6 7 8; do
  cat >>"$v/decisions.md" <<EOF

### DEC-$n — a one-way call number $n

- **Status:** open
- **Door:** one-way
- **Discipline:** product-strategy
- **Deciders:** Dana Reyes
- **Options:**
  - go — commits the venture
  - wait — keeps the option open
- **Outcome:** open
- **Consequences:** none
- **Feed-forward:** none
EOF
  if [ "$n" = 5 ]; then
    assert_contains "triage: a middling signal adds a seat" "seats	4" "$("$FANOUT" triage "$v")"
  fi
done
assert_contains "triage: a heavy signal caps at five" "seats	5" "$("$FANOUT" triage "$v")"

# ---------------------------------------------------------------------------
# 3. The Gate 1 roster: staffing, backend, sessions, cost, decorrelation
#    (REQ-P1.6, REQ-P1.7, D-7).
# ---------------------------------------------------------------------------
v="$(fresh)"
"$FANOUT" frame "$v" >/dev/null 2>&1
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist@haiku "$v" 2>&1)"
rc=$?
assert_eq "roster: exit 0" "0" "$rc"
assert_file "roster: writes the roster" "$run/roster.tsv"
assert_contains "roster: discloses the backend" "backend	subagent" "$out"
assert_contains "roster: lists a seat with its card and model" "seat	seat-1	product-strategy	Product strategy	none	opus" "$out"
assert_contains "roster: lists a pole" "seat	seat-2	ops-design	Operations design	skeptic	sonnet" "$out"
assert_contains "roster: counts the sessions (seats, synthesis, challenge, amendment)" "sessions	6" "$out"
assert_contains "roster: discloses an estimated cost" "cost	" "$out"
assert_contains "roster: names an unstaffed discipline" "unstaffed	org-design" "$out"
assert_not_contains "roster: varied models on a model-capable backend lose nothing" "decorrelation" "$out"
assert_contains "roster: says per-seat models are on" "per-seat-model	yes" "$out"

run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend in-session \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist "$v" 2>&1)"
assert_contains "roster: a backend that cannot set a model reports the lost decorrelation" \
  "degraded	the in-session seat launch cannot set a per-seat model" "$out"
assert_contains "roster: says per-seat models are off" "per-seat-model	no" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend tmux \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet "$v" 2>&1)"
assert_contains "roster: the tmux seat launch applies one tier, so it reports the loss" \
  "degraded	the tmux seat launch cannot set a per-seat model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy --seat ops-design:skeptic --seat ops-design:optimist "$v" 2>&1)"
assert_contains "roster: seats on one model report the lost decorrelation" \
  "degraded	every seat runs on the same model" "$out"

run="$(newrun)"
"$FANOUT" roster --run "$run" --backend subagent --seat product-strategy:skeptic "$v" >/dev/null 2>&1
assert_eq "roster: a pole on a card without a stance axis is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat ops-design:sideways "$v" >/dev/null 2>&1
assert_eq "roster: a pole the axis does not name is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat no-such-card "$v" >/dev/null 2>&1
assert_eq "roster: an unknown card is refused" "1" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat 'product-strategy@op us' "$v" >/dev/null 2>&1
assert_eq "roster: a malformed model token is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy --seat product-strategy --seat product-strategy \
  --seat product-strategy --seat product-strategy --seat product-strategy "$v" >/dev/null 2>&1
assert_eq "roster: more than five seats is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent "$v" >/dev/null 2>&1
assert_eq "roster: zero seats is not a fan-out" "2" "$?"
assert_no_file "roster: a refused roster writes nothing" "$run/roster.tsv"
run="$(newrun)"
"$FANOUT" roster --run "$run" --backend subagent --seat product-strategy "$v" >/dev/null 2>&1
"$FANOUT" roster --run "$run" --backend subagent --seat product-strategy "$v" >/dev/null 2>&1
assert_eq "roster: an existing roster is never overwritten" "5" "$?"
v2="$(fresh)"
"$FANOUT" roster --run "$(newrun)" --backend subagent --seat product-strategy "$v2" >/dev/null 2>&1
assert_eq "roster: no frame yet is refused" "2" "$?"

# ---------------------------------------------------------------------------
# 4. A seat brief: the card's task framing plus the frame, the mandatory
#    escalation section, and nothing meant for the synthesizer (REQ-P1.5, D-3).
# ---------------------------------------------------------------------------
run="$(newrun)"
"$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist@haiku "$v" >/dev/null 2>&1
b1="$("$FANOUT" brief --run "$run" seat-1 "$v" 2>&1)"
assert_eq "brief: exit 0" "0" "$?"
assert_contains "brief: carries the role line" "Lays out the venture's strategic options" "$b1"
assert_contains "brief: carries the mandate" "Which segment named in the frame feels the problem sharply" "$b1"
assert_contains "brief: carries the grounding gate" "Refuse without:" "$b1"
assert_contains "brief: carries the escalation contract" "**irreversibility** (powers:" "$b1"
assert_contains "brief: carries the frame" "# Northwind Signals — Frame" "$b1"
assert_contains "brief: says where the subscribed files are" "bundle, in \`$v\`" "$b1"
assert_contains "brief: requires the typed final section" \
  "| Decision | Tier and reason | Owning role | Evidence needed | Trigger | Powers |" "$b1"
assert_contains "brief: forbids talking to the human" "never ask the human" "$b1"
assert_contains "brief: forbids writing the registers" "read-only" "$b1"
assert_not_contains "brief: no synthesizer-facing anti-patterns" "## Anti-patterns" "$b1"
assert_not_contains "brief: no blind spots" "## Blind spots" "$b1"
assert_not_contains "brief: no other seat's card" "Maps the operating workflow" "$b1"
assert_not_contains "brief: a stance-free seat gets no pole" "## Stance" "$b1"
b2="$("$FANOUT" brief --run "$run" seat-2 "$v" 2>&1)"
assert_contains "brief: a pole seat gets its stance" "skeptic" "$b2"
assert_contains "brief: by default the artifact is the final answer" "as the final answer" "$b1"
b3="$("$FANOUT" brief --deliver-file --run "$run" seat-3 "$v" 2>&1)"
assert_contains "brief: --deliver-file names the seat's run file" "to the file \`$run/seat-3.md\`" "$b3"
assert_not_contains "brief: --deliver-file drops the final-answer form" "as the final answer" "$b3"
"$FANOUT" brief --run "$run" seat-9 "$v" >/dev/null 2>&1
assert_eq "brief: an unknown seat is refused" "2" "$?"
"$FANOUT" brief --run "$run" '../x' "$v" >/dev/null 2>&1
assert_eq "brief: a hostile seat id is refused" "2" "$?"

# ---------------------------------------------------------------------------
# 5. The seat-artifact check: the typed escalation section ends every artifact
#    (REQ-P1.5, REQ-P1.9).
# ---------------------------------------------------------------------------
seat_artifact() {
  # $1 path, $2 a marker unique to the seat, $3 a phrase naming the seat
  cat >"$1" <<EOF
## Job and segment

$3 finds the ops lead at end of shift is the sharpest segment ($2); the workflow audit
shows the dead time.

## Assumptions to test

- believe ops leads file once; verify with the shadow run; measure the filed share; right if
  seven of ten arrive through the surface.

## Decisions I cannot make

| Decision | Tier and reason | Owning role | Evidence needed | Trigger | Powers |
| --- | --- | --- | --- | --- | --- |
| Commit the handover moment publicly | human-authority — a one-way door | gate decider | the A-1 shadow run | irreversibility | halt, override |
EOF
}
art="$tmp/good.md"
seat_artifact "$art" "MARK-ONE" "This seat"
"$FANOUT" check-seat "$art" >/dev/null 2>&1
assert_eq "check-seat: a well-formed artifact passes" "0" "$?"

cp "$art" "$tmp/notlast.md"
printf '\n## Afterword\n\nMore text.\n' >>"$tmp/notlast.md"
out="$("$FANOUT" check-seat "$tmp/notlast.md" 2>&1)"
assert_eq "check-seat: the section must come last" "1" "$?"
assert_contains "check-seat: names the rule" "Decisions I cannot make" "$out"

sed 's/| irreversibility |/| it seems risky |/' "$art" >"$tmp/untyped.md"
out="$("$FANOUT" check-seat "$tmp/untyped.md" 2>&1)"
assert_eq "check-seat: an untyped trigger fails" "1" "$?"
assert_contains "check-seat: names the bad trigger" "it seems risky" "$out"

sed 's/| halt, override |/| halt, veto |/' "$art" >"$tmp/power.md"
"$FANOUT" check-seat "$tmp/power.md" >/dev/null 2>&1
assert_eq "check-seat: a power outside the four fails" "1" "$?"

sed 's/| human-authority — a one-way door |/| because it matters |/' "$art" >"$tmp/tier.md"
"$FANOUT" check-seat "$tmp/tier.md" >/dev/null 2>&1
assert_eq "check-seat: a reason without its tier fails" "1" "$?"

sed 's/| human-authority — a one-way door |/| human-authority. A one-way door. |/' "$art" >"$tmp/period.md"
"$FANOUT" check-seat "$tmp/period.md" >/dev/null 2>&1
assert_eq "check-seat: a tier closed by a full stop passes" "0" "$?"

sed '/^## Decisions I cannot make$/,$d' "$art" >"$tmp/nosection.md"
"$FANOUT" check-seat "$tmp/nosection.md" >/dev/null 2>&1
assert_eq "check-seat: a missing section fails" "1" "$?"

sed 's/| Trigger | Powers |$/|/; s/| --- | --- |$/|/' "$art" >"$tmp/oldheader.md"
"$FANOUT" check-seat "$tmp/oldheader.md" >/dev/null 2>&1
assert_eq "check-seat: the untyped four-column table fails" "1" "$?"

sed '/^| Commit the handover/d' "$art" >"$tmp/empty.md"
"$FANOUT" check-seat "$tmp/empty.md" >/dev/null 2>&1
assert_eq "check-seat: an empty table without none fails" "1" "$?"
printf 'none\n' >>"$tmp/empty.md"
"$FANOUT" check-seat "$tmp/empty.md" >/dev/null 2>&1
assert_eq "check-seat: an empty table stating none passes" "0" "$?"

sed 's/the workflow audit/I am highly confident the workflow audit/' "$art" >"$tmp/conf.md"
out="$("$FANOUT" check-seat "$tmp/conf.md" 2>&1)"
assert_eq "check-seat: verbalized self-confidence fails" "1" "$?"
assert_contains "check-seat: names the confidence rule" "confidence" "$out"
sed 's/the workflow audit/with 80% probability the workflow audit/' "$art" >"$tmp/prob.md"
"$FANOUT" check-seat "$tmp/prob.md" >/dev/null 2>&1
assert_eq "check-seat: a stated probability fails" "1" "$?"

# ---------------------------------------------------------------------------
# 6. The synthesis input is anonymized and order-shuffled; the orchestrator's
#    map stays outside it (REQ-P1.3).
# ---------------------------------------------------------------------------
seat_artifact "$run/seat-1.md" "MARK-ONE" "As the Product strategy seat (product-strategy, seat-1), this"
seat_artifact "$run/seat-2.md" "MARK-TWO" "As the skeptic Operations design seat (ops-design), this"
seat_artifact "$run/seat-3.md" "MARK-THREE" "The optimist reading from operations design"
out="$(PLANWRIGHT_FANOUT_SEED=7 "$FANOUT" anonymize --run "$run" 2>&1)"
assert_eq "anonymize: exit 0" "0" "$?"
assert_file "anonymize: writes the synthesis input" "$run/synthesis-input.md"
assert_file "anonymize: writes the orchestrator's label map" "$run/labels.tsv"
si="$(cat "$run/synthesis-input.md")"
for leak in "product-strategy" "Product strategy" "ops-design" "Operations design" \
  "operations design" "seat-1" "seat-2" "seat-3" "skeptic" "optimist" "opus" "sonnet" "haiku"; do
  assert_not_contains "anonymize: no seat identity ($leak)" "$leak" "$si"
done
assert_contains "anonymize: keeps the content" "MARK-ONE" "$si"
assert_contains "anonymize: labels input A" "## Input A" "$si"
assert_contains "anonymize: labels input C" "## Input C" "$si"
assert_contains "anonymize: demotes seat headings under the label" "### Job and segment" "$si"
assert_eq "anonymize: the map covers every seat once" "seat-1 seat-2 seat-3" \
  "$(cut -f2 "$run/labels.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
order() { grep -o 'MARK-[A-Z]*' "$1" | tr '\n' ' '; }
o7="$(order "$run/synthesis-input.md")"
seen_other=no
for seed in 1 2 3 4 5 6 8 9; do
  rm -f "$run/synthesis-input.md" "$run/labels.tsv"
  PLANWRIGHT_FANOUT_SEED=$seed "$FANOUT" anonymize --run "$run" >/dev/null 2>&1
  [ "$(order "$run/synthesis-input.md")" != "$o7" ] && seen_other=yes
done
assert_eq "anonymize: the order is shuffled, not the seat order" "yes" "$seen_other"
"$FANOUT" anonymize --run "$run" >/dev/null 2>&1
assert_eq "anonymize: an existing synthesis input is never overwritten" "5" "$?"
rm -f "$run/synthesis-input.md" "$run/labels.tsv"
cp "$run/seat-3.md" "$tmp/seat-3.keep"
sed_i "$run/seat-3.md" 's/| irreversibility |/| vibes |/'
"$FANOUT" anonymize --run "$run" >/dev/null 2>&1
assert_eq "anonymize: a seat artifact failing the check is refused" "1" "$?"
cp "$tmp/seat-3.keep" "$run/seat-3.md"
PLANWRIGHT_FANOUT_SEED=7 "$FANOUT" anonymize --run "$run" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 7. Synthesis and challenge prompts are persona-free; the challenge sees the
#    synthesis and frame, never per-seat output (REQ-P1.4).
# ---------------------------------------------------------------------------
sp="$("$FANOUT" synthesis-brief --run "$run" "$v" 2>&1)"
assert_eq "synthesis-brief: exit 0" "0" "$?"
assert_contains "synthesis-brief: carries the anonymized inputs" "MARK-TWO" "$sp"
assert_contains "synthesis-brief: carries the frame" "# Northwind Signals — Frame" "$sp"
assert_contains "synthesis-brief: names the mandatory table" \
  "| Kind | Claim | Claim type | Convergence | Outliers | Grounding |" "$sp"
assert_not_contains "synthesis-brief: no card role line" "Lays out the venture" "$sp"
assert_not_contains "synthesis-brief: no seat identity" "ops-design" "$sp"
assert_not_contains "synthesis-brief: no identity framing" "You are" "$sp"
assert_contains "synthesis-brief: --deliver-file writes synthesis.md" "$run/synthesis.md" \
  "$("$FANOUT" synthesis-brief --deliver-file --run "$run" "$v" 2>&1)"

cat >"$run/synthesis.md" <<'EOF'
## Synthesis

The inputs agree on the segment and split on the sinks.

## Synthesis table

| Kind | Claim | Claim type | Convergence | Outliers | Grounding |
| --- | --- | --- | --- | --- | --- |
| agreement | The end-of-shift ops lead is the sharpest segment | extractive | 3 of 3 | none | workflow audit |
| tension | Whether the sinks accept direct writes | interpretive | 2 of 3 | Input B | none |
| open-question | Who owns the surface after launch | interpretive | 1 of 3 | Input A, Input C | none |
EOF
"$FANOUT" check-synthesis --run "$run" "$run/synthesis.md" >/dev/null 2>&1
assert_eq "check-synthesis: a well-formed table passes" "0" "$?"
sed 's/| extractive |/| obvious |/' "$run/synthesis.md" >"$tmp/s1.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s1.md" >/dev/null 2>&1
assert_eq "check-synthesis: an unknown claim type fails" "1" "$?"
sed 's/| 3 of 3 |/| 90% |/' "$run/synthesis.md" >"$tmp/s2.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s2.md" >/dev/null 2>&1
assert_eq "check-synthesis: a percentage instead of a count fails" "1" "$?"
sed 's/| 3 of 3 |/| 4 of 3 |/' "$run/synthesis.md" >"$tmp/s3.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s3.md" >/dev/null 2>&1
assert_eq "check-synthesis: more converging inputs than inputs fails" "1" "$?"
sed 's/| 3 of 3 |/| 3 of 4 |/' "$run/synthesis.md" >"$tmp/s3b.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s3b.md" >/dev/null 2>&1
assert_eq "check-synthesis: a count over the wrong number of inputs fails" "1" "$?"
sed 's/| 2 of 3 | Input B |/| 2 of 3 | none |/' "$run/synthesis.md" >"$tmp/s4.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s4.md" >/dev/null 2>&1
assert_eq "check-synthesis: a split claim that names no outlier fails" "1" "$?"
sed 's/| Input B |/| Input Q |/' "$run/synthesis.md" >"$tmp/s5.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s5.md" >/dev/null 2>&1
assert_eq "check-synthesis: an outlier that is no input fails" "1" "$?"
sed 's/| agreement |/| consensus |/' "$run/synthesis.md" >"$tmp/s6.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s6.md" >/dev/null 2>&1
assert_eq "check-synthesis: an unknown kind fails" "1" "$?"
sed 's/The inputs agree/The ops-design input and the others agree/' "$run/synthesis.md" >"$tmp/s7.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s7.md" >/dev/null 2>&1
assert_eq "check-synthesis: a seat identity in the blind synthesis fails" "1" "$?"
sed '/^## Synthesis table$/,$d' "$run/synthesis.md" >"$tmp/s8.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s8.md" >/dev/null 2>&1
assert_eq "check-synthesis: a missing table fails" "1" "$?"

cp "$run/synthesis.md" "$tmp/synthesis.keep"
cp "$tmp/s1.md" "$run/synthesis.md"
"$FANOUT" challenge-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "challenge-brief: a synthesis failing the check is refused" "1" "$?"
cp "$tmp/synthesis.keep" "$run/synthesis.md"
cp=$("$FANOUT" challenge-brief --run "$run" "$v" 2>&1)
assert_eq "challenge-brief: exit 0" "0" "$?"
assert_contains "challenge-brief: carries the synthesis" "The inputs agree on the segment" "$cp"
assert_contains "challenge-brief: carries the frame" "# Northwind Signals — Frame" "$cp"
assert_contains "challenge-brief: asks for a premortem" "premortem" "$cp"
assert_contains "challenge-brief: asks for a key-assumptions check" "key-assumptions check" "$cp"
assert_not_contains "challenge-brief: never per-seat output" "MARK-ONE" "$cp"
assert_not_contains "challenge-brief: no card role line" "Lays out the venture" "$cp"
assert_not_contains "challenge-brief: no identity framing" "You are" "$cp"

"$FANOUT" amend-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "amend-brief: needs the challenge first" "2" "$?"
printf '## Premortem\n\nThe sinks reject writes.\n\n## Key assumptions\n\nA-2 carries the venture.\n' >"$run/challenge.md"
ap="$("$FANOUT" amend-brief --run "$run" "$v" 2>&1)"
assert_eq "amend-brief: exit 0" "0" "$?"
assert_contains "amend-brief: carries the challenge" "The sinks reject writes" "$ap"
assert_contains "amend-brief: carries the synthesis" "The inputs agree on the segment" "$ap"
assert_contains "amend-brief: carries the anonymized inputs" "MARK-THREE" "$ap"
assert_not_contains "amend-brief: no card role line" "Lays out the venture" "$ap"
cp "$run/synthesis.md" "$run/amended.md"
"$FANOUT" amend-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "amend-brief: the synthesis amends at most once" "1" "$?"

# ---------------------------------------------------------------------------
# 8. Attribution returns only in the final table (REQ-P1.3, REQ-P1.9).
# ---------------------------------------------------------------------------
sed_i "$run/amended.md" 's/The inputs agree on the segment/The amended inputs agree on the segment/'
out="$("$FANOUT" attribute --run "$run" 2>&1)"
assert_eq "attribute: exit 0" "0" "$?"
assert_file "attribute: writes the final table" "$run/table.md"
tbl="$(cat "$run/table.md")"
label_b="$(awk -F '\t' '$1 == "B" { print $2 }' "$run/labels.tsv")"
case $label_b in
  seat-1) want_b="Input B (Product strategy, opus)" ;;
  seat-2) want_b="Input B (Operations design, skeptic pole, sonnet)" ;;
  seat-3) want_b="Input B (Operations design, optimist pole, haiku)" ;;
  *) want_b="unmapped" ;;
esac
assert_contains "attribute: an outlier is named with its seat" "$want_b" "$tbl"
assert_contains "attribute: reads the amended synthesis when there is one" "The amended inputs agree" "$tbl"
assert_contains "attribute: prose outside the table stays blind" "The amended inputs agree on the segment and split" "$tbl"
assert_not_contains "attribute: the synthesis input stays blind" "Product strategy" "$(cat "$run/synthesis-input.md")"
"$FANOUT" attribute --run "$run" >/dev/null 2>&1
assert_eq "attribute: an existing final table is never overwritten" "5" "$?"

# ---------------------------------------------------------------------------
# 9. Gate 2: escalations as typed human-power choices; the five outcomes
#    (REQ-P1.5, REQ-P1.7, D-6).
# ---------------------------------------------------------------------------
out="$("$FANOUT" gate2 --run "$run" 2>&1)"
assert_eq "gate2: exit 0" "0" "$?"
assert_contains "gate2: an escalation becomes a choice with its powers" \
  "choice	1	seat-1	Commit the handover moment publicly	human-authority	gate decider	irreversibility	halt, override" "$out"
assert_contains "gate2: offers the five outcomes" "outcomes	proceed park kill re-run-seat pull-bench" "$out"

# ---------------------------------------------------------------------------
# 10. Recording a run in the venture: the final table, the challenge, and the
#     seat artifacts by seat, never the private map (REQ-P1.3).
# ---------------------------------------------------------------------------
out="$("$FANOUT" record --run "$run" "$v" 2>&1)"
assert_eq "record: exit 0" "0" "$?"
dest="$(printf '%s\n' "$out" | awk -F '\t' '$1 == "recorded" { print $2 }')"
assert_contains "record: lands under fanout/ dated" "fanout/2026-08-26-1" "$dest"
assert_file "record: the final table" "$v/fanout/2026-08-26-1/table.md"
assert_file "record: the challenge" "$v/fanout/2026-08-26-1/challenge.md"
assert_file "record: a seat artifact" "$v/fanout/2026-08-26-1/seat-2.md"
assert_file "record: the roster" "$v/fanout/2026-08-26-1/roster.tsv"
"$FANOUT" record --run "$run" "$v" >/dev/null 2>&1
assert_file "record: a second run takes the next number" "$v/fanout/2026-08-26-2/table.md"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "record: the bundle still validates" "0" "$?"

# ---------------------------------------------------------------------------
# 11. Staffing honesty: unstaffed disciplines auto-file coverage risks, a
#     missing card counts as unstaffed, a zero-seat run collapses (REQ-P1.8).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$FANOUT" staff "$v" 2>&1)"
assert_eq "staff: exit 0" "0" "$?"
assert_contains "staff: files the unstaffed discipline" "filed	A-5	org-design" "$out"
am="$(cat "$v/assumptions.md")"
assert_contains "staff: the entry is a coverage risk" "### A-5 — coverage risk: org-design unstaffed" "$am"
assert_contains "staff: in the standard skeleton" "believe this venture's org-design calls" "$am"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: the filed bundle validates" "0" "$?"
before="$(cat "$v/assumptions.md")"
out="$("$FANOUT" staff "$v" 2>&1)"
assert_eq "staff: a re-run files nothing new" "$before" "$(cat "$v/assumptions.md")"
assert_contains "staff: a re-run reports the existing entry" "exists	A-5	org-design" "$out"

v="$(fresh)"
"$FANOUT" staff --no-stake org-design "$v" >/dev/null 2>&1
assert_not_contains "staff: a discipline judged stake-free is not filed" "coverage risk" "$(cat "$v/assumptions.md")"

v="$(fresh)"
sed_i "$v/disciplines.md" 's/^| product-strategy | agent-persona | product-strategy |$/| product-strategy | agent-persona | pricing |/'
out="$("$FANOUT" staff "$v" 2>&1)"
assert_contains "staff: a seat with no card is unstaffed" "filed	A-5	product-strategy" "$out"
assert_contains "staff: says why" "no card" "$out"

v="$(fresh)"
sed_i "$v/disciplines.md" 's/^| product-strategy | agent-persona | product-strategy |$/| product-strategy | unstaffed | none |/'
out="$("$FANOUT" staff "$v" 2>&1)"
am="$(cat "$v/assumptions.md")"
assert_contains "staff: a zero-seat run files one collapsed row" \
  "### A-5 — personas waived (zero-seat); 2 disciplines unstaffed" "$am"
assert_not_contains "staff: no per-discipline rows on a zero-seat run" "coverage risk: org-design" "$am"
assert_contains "staff: reports the collapse" "collapsed	A-5	2" "$out"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: the collapsed bundle validates" "0" "$?"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-fanout: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-fanout: all assertions passed"
