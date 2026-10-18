#!/bin/bash
# Tests for the persona fan-out helper (inception REQ-P1.3–P1.9 · D-2, D-6,
# D-7, D-18).
#
# What is pinned: the frame compiles to the normative six-part template; the
# seat-count triage stays in the three-to-five band; the Gate 1 roster
# discloses backend, sessions, cost, card reviews, and every degradation, and
# snapshots the frame into the run; a seat brief carries its card's task
# framing and the mandatory escalation section, and nothing meant for the
# synthesizer; the seat-artifact check enforces the typed escalation section
# against the card's contract; the synthesis input carries no seat identity or
# ordering cue, its label map matches its content, and attribution returns only
# in the final table; the synthesis and challenge prompts are persona-free and
# hold no roster or map; the challenge and the amendment each run once, with
# one re-ask of a failed answer; Gate 2 offers typed human powers and the
# table's forks; a run is recorded once; and staffing honesty auto-files
# coverage risks, collapsing them on a zero-seat run and superseding a stale
# collapse (REQ-P1.8).
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
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

fresh() {
  d="$(mktemp -d "$tmp/vXXXXXX")" || exit 1
  inception_fixture_write "$d" "${1:-untracked}" || exit 1
  printf '%s' "$d"
}
newrun() { mktemp -d "$tmp/runXXXXXX"; }
sed_i() { sed "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }
# mark_order <synthesis-input>: the seat markers in the order the inputs appear.
mark_order() { grep -o 'MARK-[A-Z]*' "$1" | tr '\n' ' '; }
# input_block <synthesis-input> <label>: one labelled input's lines.
input_block() { awk -v want="## Input $2" '/^## Input / { on = ($0 == want); next } on' "$1"; }
# shellcheck disable=SC2012 # the mode column of one named path; stat differs between GNU and BSD
mode_of() { ls -ld "$1" | cut -c1-10; }

export PLANWRIGHT_INCEPTION_TODAY=2026-08-26
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_REPO_ROOT=none
unset CLAUDE_PLUGIN_ROOT CLAUDE_DIR CLAUDE_PLUGIN_DATA POWERS PLANWRIGHT_FANOUT_SEED
umask 022

# A team overlay: a second card with a stance axis, a third with a model
# override and a fast rot rate, and a fourth that does not lint. Each is the
# core card with a few header or section lines changed.
overlay="$tmp/overlay"
mkdir -p "$overlay/catalogs" "$overlay/cards"
cat >"$overlay/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: ops-design
    discipline: "Operations design"
  - id: pricing-sim
    discipline: "Pricing"
  - id: broken-card
    discipline: "Broken"
YAML
sed -e 's/^# Product strategy — discipline card$/# Operations design — discipline card/' \
  -e 's/^\*\*Card-id:\*\* product-strategy$/**Card-id:** ops-design/' \
  -e 's/^\*\*Stance-axis:\*\* none$/**Stance-axis:** optimist-skeptic/' \
  -e 's/^Lays out the venture.s strategic options/Maps the operating workflow the venture changes/' \
  "$REPO_ROOT/cards/product-strategy.md" >"$overlay/cards/ops-design.md"
sed -e 's/^# Product strategy — discipline card$/# Pricing — discipline card/' \
  -e 's/^\*\*Card-id:\*\* product-strategy$/**Card-id:** pricing-sim/' \
  -e 's/^\*\*Stance-axis:\*\* none$/**Stance-axis:** none\n**Model-override:** haiku/' \
  -e 's/^\*\*Rot-rate:\*\* slow$/**Rot-rate:** fast/' \
  "$REPO_ROOT/cards/product-strategy.md" >"$overlay/cards/pricing-sim.md"
sed -e 's/^\*\*Card-id:\*\* product-strategy$/**Card-id:** broken-card/' \
  -e '/^## Mandate$/,/^## Frameworks$/{/^## Frameworks$/!d;}' \
  "$REPO_ROOT/cards/product-strategy.md" >"$overlay/cards/broken-card.md"
export PLANWRIGHT_ADOPTER_OVERLAY="$overlay"

# ---------------------------------------------------------------------------
# 1. The frame compiles to the normative template, in order (D-18).
# ---------------------------------------------------------------------------
v="$(fresh)"
cat >>"$v/decisions.md" <<'EOF'

### DEC-3 — a deferred pricing call

- **Status:** deferred
- **Door:** one-way
- **Discipline:** product-strategy
- **Deciders:** Dana Reyes
- **Options:**
  - now — commits early
  - later — keeps the option
- **Outcome:** deferred until the pilot reports
- **Consequences:** none
- **Feed-forward:** none

### DEC-4 — a superseded call

- **Status:** open
- **Door:** one-way
- **Discipline:** product-strategy
- **Deciders:** Dana Reyes
- **Options:**
  - a — one
  - b — two
- **Outcome:** open
- **Consequences:** none
- **Feed-forward:** none
- **Superseded-by:** DEC-3 (2026-08-20)
EOF
sed_i "$v/brief.md" 's/^- \*\*KC-2:\*\* \(.*\)$/- **KC-2:** \1\n- **KC-3:** an old criterion — by 2026-09-01 — **Superseded-by:** KC-2 (2026-08-02)\n- **KC-4:** a soft criterion — by 2026-11-01 (tentative)/'
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
assert_contains "frame: lists a deferred decision" "**DEC-3** (one-way, deferred)" "$frame"
assert_not_contains "frame: omits a decided decision" "DEC-2" "$frame"
assert_not_contains "frame: omits a superseded decision" "DEC-4" "$frame"
assert_contains "frame: carries the staffing table" "| org-design | unstaffed | none |" "$frame"
assert_contains "frame: carries the success metric" "below ten minutes" "$frame"
assert_contains "frame: classifies a clear kill criterion" "by 2026-10-01 — clear" "$frame"
assert_contains "frame: classifies an approaching kill criterion" "by 2026-09-15 — approaching" "$frame"
assert_not_contains "frame: omits a superseded kill criterion" "KC-3" "$frame"
assert_contains "frame: a date with a trailing note is unreadable, as the renderer reads it" "(tentative) — date unreadable" "$frame"
assert_eq "frame: the file takes the umask's mode" "-rw-r--r--" "$(mode_of "$v/exports/frame.md")"
first="$(cat "$v/exports/frame.md")"
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: regeneration is byte-identical" "$first" "$(cat "$v/exports/frame.md")"
PLANWRIGHT_INCEPTION_TODAY=2026-09-20 "$FANOUT" frame "$v" >/dev/null 2>&1
assert_contains "frame: a passed date is tripped" "by 2026-09-15 — tripped" "$(cat "$v/exports/frame.md")"
PLANWRIGHT_INCEPTION_TODAY=2026-13-45 "$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: an impossible pinned date is refused" "2" "$?"
assert_eq "frame: no temp file is left in exports/" "frame.md" "$(ls -A "$v/exports")"

v="$(fresh)"
esc="$(printf '\033')"
c1="$(printf '\302\233')"
sed_i "$v/brief.md" "s/^- \*\*Framing:\*\* Ops leads re-key/- **Framing:** Ops ${esc}[31mleads${esc}[0m ${c1} Ops leads re-key/"
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: bundle text loses its control characters" "0" "$(grep -c "$esc" "$v/exports/frame.md")"
assert_eq "frame: bundle text loses an encoded C1 control" "0" "$(grep -c "$c1" "$v/exports/frame.md")"
assert_contains "frame: and keeps its em dashes" "# Northwind Signals — Frame" "$(cat "$v/exports/frame.md")"

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

v="$(fresh)"
mkdir -p "$v/exports/frame.md"
"$FANOUT" frame "$v" >/dev/null 2>&1
assert_eq "frame: a directory in the frame's place is refused" "2" "$?"
assert_eq "frame: nothing written into it" "" "$(ls -A "$v/exports/frame.md")"

v="$(fresh)"
mkdir -p "$v/exports"
chmod 555 "$v/exports"
out="$("$FANOUT" frame "$v" 2>&1)"
assert_eq "frame: an unwritable exports/ fails rather than reporting success" "2" "$?"
assert_not_contains "frame: and prints no success line" "frame	exports/frame.md" "$out"
chmod 755 "$v/exports"

# ---------------------------------------------------------------------------
# 2. Seat-count triage stays in the three-to-five band (REQ-P1.6).
# ---------------------------------------------------------------------------
decision() {
  # $1 venture, $2 number, $3 status, $4 door, $5 an extra trailing bullet
  cat >>"$1/decisions.md" <<EOF

### DEC-$2 — a call number $2

- **Status:** ${3:-open}
- **Door:** ${4:-one-way}
- **Discipline:** product-strategy
- **Deciders:** Dana Reyes
- **Options:**
  - go — commits the venture
  - wait — keeps the option open
- **Outcome:** open
- **Consequences:** none
- **Feed-forward:** none${5:-}
EOF
}
v="$(fresh)"
out="$("$FANOUT" triage "$v")"
assert_contains "triage: a low-stake bundle gets the default three" "seats	3" "$out"
assert_contains "triage: names the signal" "signal	1" "$out"
decision "$v" 3
assert_contains "triage: signal two is still three seats" "seats	3" "$("$FANOUT" triage "$v")"
decision "$v" 4 deferred
out="$("$FANOUT" triage "$v")"
assert_contains "triage: a deferred one-way door counts" "signal	3" "$out"
assert_contains "triage: signal three adds a seat" "seats	4" "$out"
decision "$v" 5 open two-way
decision "$v" 6 open one-way '
- **Superseded-by:** DEC-3 (2026-08-20)'
decision "$v" 7 decided
assert_contains "triage: two-way, superseded, and decided doors do not count" "signal	3" "$("$FANOUT" triage "$v")"
decision "$v" 8
decision "$v" 9
assert_contains "triage: signal five is still four seats" "seats	4" "$("$FANOUT" triage "$v")"
decision "$v" 10
assert_contains "triage: signal six caps at five" "seats	5" "$("$FANOUT" triage "$v")"
decision "$v" 11
decision "$v" 12
assert_contains "triage: a heavier signal stays at five" "seats	5" "$("$FANOUT" triage "$v")"

# ---------------------------------------------------------------------------
# 3. The Gate 1 roster: staffing, backend, sessions, cost, degradations, and
#    the frame snapshot (REQ-P1.6, REQ-P1.7, D-7).
# ---------------------------------------------------------------------------
v="$(fresh)"
"$FANOUT" frame "$v" >/dev/null 2>&1
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist@haiku "$v" 2>&1)"
rc=$?
assert_eq "roster: exit 0" "0" "$rc"
assert_file "roster: writes the roster" "$run/roster.tsv"
assert_file "roster: records the backend" "$run/backend"
assert_file "roster: snapshots the frame into the run" "$run/frame.md"
assert_eq "roster: the snapshot is the confirmed frame" "$(cat "$v/exports/frame.md")" "$(cat "$run/frame.md")"
assert_contains "roster: discloses the backend" "backend	subagent" "$out"
assert_contains "roster: lists a seat with its card and model" "seat	seat-1	product-strategy	Product strategy	none	opus" "$out"
assert_contains "roster: lists a pole" "seat	seat-2	ops-design	Operations design	skeptic	sonnet" "$out"
assert_contains "roster: counts the sessions (seats, synthesis, challenge, amendment)" "sessions	6" "$out"
assert_contains "roster: discloses the per-session overhead" "overhead	light per session" "$out"
assert_contains "roster: discloses the estimated cost" "cost	about 255k tokens" "$out"
assert_contains "roster: names an unstaffed discipline" "unstaffed	org-design	unstaffed" "$out"
assert_not_contains "roster: varied models on a model-capable launch lose nothing" "decorrelation" "$out"
assert_contains "roster: says per-seat models are on" "per-seat-model	yes" "$out"

run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent --seat product-strategy "$v" 2>&1)"
assert_contains "roster: one seat is four sessions" "sessions	4" "$out"
assert_contains "roster: and costs one seat" "cost	about 175k tokens" "$out"

run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend in-session \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist "$v" 2>&1)"
assert_contains "roster: a launch that cannot set a model reports the lost decorrelation" \
  "degraded	the in-session seat launch cannot set a per-seat model" "$out"
assert_contains "roster: a one-session rung reports the lost independence" \
  "degraded	the in-session rung runs the seats one after another in one session" "$out"
assert_contains "roster: says per-seat models are off" "per-seat-model	no" "$out"
assert_contains "roster: records its degradations in the run" "one after another" "$(cat "$run/degraded")"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend in-session --seat product-strategy@opus "$v" 2>&1)"
assert_contains "roster: one seat asking for a model it cannot get is reported" "cannot set a per-seat model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend tmux \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet "$v" 2>&1)"
assert_contains "roster: the tmux seat launch applies one tier, so it reports the loss" \
  "degraded	the tmux seat launch cannot set a per-seat model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend print --seat product-strategy "$v" 2>&1)"
assert_contains "roster: the print rung reports hand launches" "launch by hand" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy --seat ops-design:skeptic --seat ops-design:optimist "$v" 2>&1)"
assert_contains "roster: seats on one model report the lost decorrelation" \
  "degraded	every seat runs on the same model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent --seat product-strategy@opus --seat product-strategy@opus "$v" 2>&1)"
assert_contains "roster: two seats naming the same model are one model" "every seat runs on the same model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent --seat product-strategy --seat product-strategy@opus "$v" 2>&1)"
assert_contains "roster: a mix of inherited and named models is flagged" "seats that name no model run on the session model" "$out"
run="$(newrun)"
out="$("$FANOUT" roster --run "$run" --backend subagent --seat pricing-sim --seat product-strategy@opus/high "$v" 2>&1)"
assert_contains "roster: a card's model override is the seat's model" "seat	seat-1	pricing-sim	Pricing	none	haiku" "$out"
assert_contains "roster: an effort the launch cannot set is dropped and reported" "seat-2 asked for effort high" "$out"
assert_contains "roster: and the seat keeps its model" "seat	seat-2	product-strategy	Product strategy	none	opus" "$out"
assert_contains "roster: a fast-rot card is flagged for re-verification" "card-review	pricing-sim	fast rot rate" "$out"
assert_not_contains "roster: a slow-rot card is not" "card-review	product-strategy" "$out"

run="$(newrun)"
"$FANOUT" roster --run "$run" --backend subagent --seat product-strategy:skeptic "$v" >/dev/null 2>&1
assert_eq "roster: a pole on a card without a stance axis is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat ops-design:sideways "$v" >/dev/null 2>&1
assert_eq "roster: a pole the axis does not name is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat no-such-card "$v" >/dev/null 2>&1
assert_eq "roster: an unknown card is refused" "1" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat broken-card "$v" >/dev/null 2>&1
assert_eq "roster: a card that does not lint is refused" "1" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat 'product-strategy@op us' "$v" >/dev/null 2>&1
assert_eq "roster: a malformed model token is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend no-such --seat product-strategy "$v" >/dev/null 2>&1
assert_eq "roster: a backend the fan-out cannot dispatch is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend headless-oneshot --seat product-strategy "$v" >/dev/null 2>&1
assert_eq "roster: a real backend with no fan-out launch arm is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent \
  --seat product-strategy --seat product-strategy --seat product-strategy \
  --seat product-strategy --seat product-strategy --seat product-strategy "$v" >/dev/null 2>&1
assert_eq "roster: more than five seats is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat "$(printf 'product-strategy\nproduct-strategy')" "$v" >/dev/null 2>&1
assert_eq "roster: a seat spec carrying a newline is refused" "2" "$?"
"$FANOUT" roster --run "$run" --backend subagent --seat "" "$v" >/dev/null 2>&1
assert_eq "roster: an empty seat spec is refused" "2" "$?"
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
run="$(newrun)"
chmod 555 "$run"
out="$("$FANOUT" roster --run "$run" --backend subagent --seat product-strategy "$v" 2>&1)"
assert_eq "roster: an unwritable run fails rather than disclosing a roster" "2" "$?"
assert_not_contains "roster: and prints no disclosure" "sessions	" "$out"
chmod 755 "$run"

# ---------------------------------------------------------------------------
# 4. A seat brief: the card's task framing plus the run's frame, the mandatory
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
assert_contains "brief: names the card's default tier" "default tier is
  structure-only" "$b1"
assert_eq "brief: the template's table gains the typed columns (two six-column headers, no four-column one)" \
  "2 0" "$(printf '%s\n' "$b1" | grep -cxF '| Decision | Tier and reason | Owning role | Evidence needed | Trigger | Powers |') $(printf '%s\n' "$b1" | grep -cxF '| Decision | Tier and reason | Owning role | Evidence needed |')"
assert_contains "brief: forbids talking to the human" "never ask the human" "$b1"
assert_contains "brief: forbids writing the registers" "read-only" "$b1"
assert_not_contains "brief: no synthesizer-facing anti-patterns" "## Anti-patterns" "$b1"
assert_not_contains "brief: no blind spots" "## Blind spots" "$b1"
assert_not_contains "brief: no other seat's card" "Maps the operating workflow" "$b1"
assert_not_contains "brief: a stance-free seat gets no pole" "## Stance" "$b1"
assert_contains "brief: by default the artifact is the final answer" "as the final answer" "$b1"
b2="$("$FANOUT" brief --run "$run" seat-2 "$v" 2>&1)"
assert_contains "brief: a pole seat argues its own pole" "Argue from the skeptic pole" "$b2"
b3="$("$FANOUT" brief --deliver-file --run "$run" seat-3 "$v" 2>&1)"
assert_contains "brief: the other pole seat argues the other pole" "Argue from the optimist pole" "$b3"
assert_contains "brief: --deliver-file writes a partial file, then renames it" \
  "to \`$run/seat-3.md.partial\`, then rename it to \`$run/seat-3.md\`" "$b3"
assert_not_contains "brief: --deliver-file drops the final-answer form" "as the final answer" "$b3"
sed_i "$v/exports/frame.md" 's/^# Northwind Signals — Frame$/# A Changed Frame — Frame/'
assert_contains "brief: reads the run's frame, not a frame regenerated mid-run" "# Northwind Signals — Frame" \
  "$("$FANOUT" brief --run "$run" seat-1 "$v" 2>&1)"
"$FANOUT" frame "$v" >/dev/null 2>&1
"$FANOUT" brief --run "$run" seat-9 "$v" >/dev/null 2>&1
assert_eq "brief: an unknown seat is refused" "2" "$?"
"$FANOUT" brief --run "$run" '../x' "$v" >/dev/null 2>&1
assert_eq "brief: a hostile seat id is refused" "2" "$?"
chmod 000 "$run/frame.md"
out="$("$FANOUT" brief --run "$run" seat-1 "$v" 2>/dev/null)"
assert_eq "brief: an unreadable frame fails" "2" "$?"
assert_eq "brief: and hands out no partial brief" "" "$out"
chmod 644 "$run/frame.md"

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
expect_fail() {
  # $1 label, $2 sed expression applied to the good artifact, $3 expected finding text
  sed "$2" "$art" >"$tmp/mut.md"
  ef_out="$("$FANOUT" check-seat "$tmp/mut.md" 2>&1)"
  assert_eq "check-seat: $1 fails" "1" "$?"
  assert_contains "check-seat: $1 is named" "$3" "$ef_out"
}
expect_fail "an untyped trigger" 's/| irreversibility |/| it seems risky |/' "it seems risky"
expect_fail "a power outside the four" 's/| halt, override |/| halt, veto |/' "veto"
expect_fail "an empty powers cell" 's/| halt, override |/|  |/' "names no human power"
expect_fail "a reason without its tier" 's/| human-authority — a one-way door |/| because it matters |/' "tier token"
expect_fail "an empty decision" 's/^| Commit the handover moment publicly |/|  |/' "names no decision"
expect_fail "an empty owning role" 's/| gate decider |/|  |/' "no owning role"
expect_fail "a row with a missing cell" 's/| irreversibility | halt, override |/| irreversibility |/' "six cells"
expect_fail "the untyped four-column table" 's/| Trigger | Powers |$/|/; s/| --- | --- |$/|/' "needs the header"
expect_fail "a tab inside a cell" 's/| gate decider |/| gate	decider |/' "tab character"
expect_fail "verbalized self-confidence" 's/the workflow audit/I am highly confident the workflow audit/' "confidence"
expect_fail "a stated probability" 's/the workflow audit/with 80% probability the workflow audit/' "probability"
expect_fail "a confidence label" 's/the workflow audit/Confidence: high, the workflow audit/' "confidence"
expect_fail "a stated likelihood" 's/the workflow audit/the likelihood is 0.7 that the workflow audit/' "probability"
expect_fail "a claim of being sure" "s/the workflow audit/I'm sure the workflow audit/" "confidence"
expect_fail "an unclosed fence" 's/^shows the dead time.$/shows the dead time.\n```/' "fence is left open"
sed 's/the workflow audit/the sure-footed workflow audit, a confidence-floor case,/' "$art" >"$tmp/nofalse.md"
"$FANOUT" check-seat "$tmp/nofalse.md" >/dev/null 2>&1
assert_eq "check-seat: ordinary words near the confidence patterns pass" "0" "$?"
sed 's/^| Commit the handover moment publicly | human-authority — a one-way door |/| Commit it | human-authority. A one-way door. |/' "$art" >"$tmp/period.md"
"$FANOUT" check-seat "$tmp/period.md" >/dev/null 2>&1
assert_eq "check-seat: a tier closed by a full stop passes" "0" "$?"
sed 's/$/\r/' "$art" >"$tmp/crlf.md"
"$FANOUT" check-seat "$tmp/crlf.md" >/dev/null 2>&1
assert_eq "check-seat: a CRLF artifact passes" "0" "$?"

cp "$art" "$tmp/notlast.md"
printf '\n## Afterword\n\nMore text.\n' >>"$tmp/notlast.md"
out="$("$FANOUT" check-seat "$tmp/notlast.md" 2>&1)"
assert_eq "check-seat: the section must come last" "1" "$?"
assert_contains "check-seat: names the rule" "Decisions I cannot make" "$out"
sed '/^## Decisions I cannot make$/,$d' "$art" >"$tmp/nosection.md"
"$FANOUT" check-seat "$tmp/nosection.md" >/dev/null 2>&1
assert_eq "check-seat: a missing section fails" "1" "$?"
out="$("$FANOUT" check-seat "$tmp/nosection.md" "$art" 2>&1)"
assert_eq "check-seat: a bad first file fails the whole check" "1" "$?"
assert_contains "check-seat: and names that file" "$tmp/nosection.md" "$out"
"$FANOUT" check-seat "$art" "$tmp/nosection.md" >/dev/null 2>&1
assert_eq "check-seat: a bad last file fails the whole check" "1" "$?"
# shellcheck disable=SC2016 # literal backtick fences
printf '```\nx\n```\njunk with no section\n' >"$tmp/fencefirst.md"
out="$("$FANOUT" check-seat "$art" "$tmp/fencefirst.md" 2>&1)"
assert_eq "check-seat: a file opening with a fence is still checked" "1" "$?"
assert_contains "check-seat: and named" "$tmp/fencefirst.md" "$out"
: >"$tmp/empty-art.md"
out="$("$FANOUT" check-seat "$tmp/empty-art.md" "$tmp/nosection.md" 2>&1)"
assert_contains "check-seat: an empty artifact is reported" "the artifact is empty" "$out"
assert_contains "check-seat: without hiding the next file's findings" "$tmp/nosection.md" "$out"
sed '/^| Commit the handover/d' "$art" >"$tmp/empty.md"
"$FANOUT" check-seat "$tmp/empty.md" >/dev/null 2>&1
assert_eq "check-seat: an empty table without none fails" "1" "$?"
printf 'none\n' >>"$tmp/empty.md"
"$FANOUT" check-seat "$tmp/empty.md" >/dev/null 2>&1
assert_eq "check-seat: an empty table stating none passes" "0" "$?"

# ---------------------------------------------------------------------------
# 6. The synthesis input is anonymized and order-shuffled; the orchestrator's
#    map matches it and stays outside it (REQ-P1.3).
# ---------------------------------------------------------------------------
seat_artifact "$run/seat-1.md" "MARK-ONE" "As the Product strategy seat (product-strategy, seat-1), this"
seat_artifact "$run/seat-2.md" "MARK-TWO" "As the skeptic seat on the ops-design card, this"
seat_artifact "$run/seat-3.md" "MARK-THREE" "The optimist pole reading"
# Seat 1 also titles itself and names another card inside a fence, both before
# its final section.
awk '/^## Job and segment$/ { print "# Product strategy seat output"; print "" }
  /^## Assumptions to test$/ { print "```"; print "fenced note naming ops-design and opuses"; print "```"; print "" }
  { print }' "$run/seat-1.md" >"$run/seat-1.new" && mv "$run/seat-1.new" "$run/seat-1.md"
out="$(PLANWRIGHT_FANOUT_SEED=7 "$FANOUT" anonymize --run "$run" 2>&1)"
assert_eq "anonymize: exit 0" "0" "$?"
assert_contains "anonymize: a pinned shuffle is reported" "degraded	the shuffle is pinned" "$out"
assert_file "anonymize: writes the synthesis input" "$run/synthesis-input.md"
assert_file "anonymize: writes the orchestrator's label map" "$run/labels.tsv"
si="$(cat "$run/synthesis-input.md")"
for leak in "product-strategy" "ops-design" "Product strategy seat" "skeptic seat" "optimist pole" \
  "seat-1" "seat-2" "seat-3" "opus " "sonnet" "haiku"; do
  assert_not_contains "anonymize: no seat identity ($leak)" "$leak" "$si"
done
assert_contains "anonymize: redaction is visible" "[redacted]" "$si"
assert_contains "anonymize: a longer word is left whole" "opuses" "$si"
assert_not_contains "anonymize: a seat's own H1 is dropped" "seat output" "$si"
assert_contains "anonymize: keeps the content" "MARK-ONE" "$si"
assert_contains "anonymize: labels input A" "## Input A" "$si"
assert_contains "anonymize: labels input C" "## Input C" "$si"
assert_contains "anonymize: demotes seat headings under the label" "### Job and segment" "$si"
assert_eq "anonymize: the map covers every seat once" "seat-1 seat-2 seat-3" \
  "$(cut -f2 "$run/labels.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
map_ok=yes
while IFS='	' read -r lab seat; do
  case $seat in seat-1) mk=MARK-ONE ;; seat-2) mk=MARK-TWO ;; seat-3) mk=MARK-THREE ;; *) mk=none ;; esac
  blk="$(input_block "$run/synthesis-input.md" "$lab")"
  case $blk in *"$mk"*) ;; *) map_ok=no ;; esac
  [ "$(printf '%s\n' "$blk" | grep -o 'MARK-[A-Z]*' | sort -u | wc -l | tr -d ' ')" = 1 ] || map_ok=no
done <"$run/labels.tsv"
assert_eq "anonymize: each label's input is the seat the map names" "yes" "$map_ok"
o7="$(mark_order "$run/synthesis-input.md")"
cp "$run/synthesis-input.md" "$tmp/si.seed7"
rm -f "$run/synthesis-input.md" "$run/labels.tsv"
PLANWRIGHT_FANOUT_SEED=7 "$FANOUT" anonymize --run "$run" >/dev/null 2>&1
assert_eq "anonymize: a pinned seed is deterministic" "$(cat "$tmp/si.seed7")" "$(cat "$run/synthesis-input.md")"
seen_other=no
for seed in 1 2 3 4 5 6 8 9 10 11; do
  rm -f "$run/synthesis-input.md" "$run/labels.tsv"
  PLANWRIGHT_FANOUT_SEED=$seed "$FANOUT" anonymize --run "$run" >/dev/null 2>&1
  o="$(mark_order "$run/synthesis-input.md")"
  if [ "$o" != "$o7" ] && [ "$o" != "MARK-ONE MARK-TWO MARK-THREE " ]; then
    seen_other=yes
    break
  fi
done
assert_eq "anonymize: the order is shuffled, not the seat order" "yes" "$seen_other"
"$FANOUT" anonymize --run "$run" >/dev/null 2>&1
assert_eq "anonymize: an existing synthesis input is never overwritten" "5" "$?"
rm -f "$run/synthesis-input.md" "$run/labels.tsv"
cp "$run/seat-3.md" "$tmp/seat-3.keep"
sed_i "$run/seat-3.md" 's/| irreversibility |/| vibes |/'
"$FANOUT" anonymize --run "$run" >/dev/null 2>&1
assert_eq "anonymize: a seat artifact failing the check is refused" "1" "$?"
assert_no_file "anonymize: a refusal writes no input" "$run/synthesis-input.md"
assert_no_file "anonymize: nor a map" "$run/labels.tsv"
cp "$tmp/seat-3.keep" "$run/seat-3.md"
sed_i "$run/seat-3.md" 's/| halt, override |/| reverse |/'
out="$("$FANOUT" anonymize --run "$run" 2>&1)"
assert_eq "anonymize: a power the card does not give for that trigger is refused" "1" "$?"
assert_contains "anonymize: and named against the card" "the card gives no reverse power for irreversibility" "$out"
cp "$tmp/seat-3.keep" "$run/seat-3.md"
PLANWRIGHT_FANOUT_SEED=7 "$FANOUT" anonymize --run "$run" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 7. Synthesis and challenge prompts are persona-free and carry no roster or
#    map; the challenge sees the synthesis and frame, never per-seat output,
#    and runs once (REQ-P1.4).
#    Scenario: the challenge runs once post-synthesis, sees synthesis and frame
#    only; the synthesis amends at most once; both steps run persona-free.
# ---------------------------------------------------------------------------
no_roster_leak() {
  # $1 label, $2 prompt
  for nl in seat-1 seat-2 seat-3 skeptic optimist opus sonnet haiku ops-design product-strategy; do
    nr_hits=$(printf '%s\n' "$2" | grep -cw -- "$nl")
    assert_eq "$1: carries nothing from the roster or map ($nl)" "0" "$nr_hits"
  done
}
synthesis_prompt="$("$FANOUT" synthesis-brief --run "$run" "$v" 2>&1)"
assert_eq "synthesis-brief: exit 0" "0" "$?"
assert_contains "synthesis-brief: carries the anonymized inputs" "MARK-TWO" "$synthesis_prompt"
assert_contains "synthesis-brief: carries the frame" "# Northwind Signals — Frame" "$synthesis_prompt"
assert_contains "synthesis-brief: withholds the staffed card ids from the frame" "| product-strategy | agent-persona | (withheld) |" "$synthesis_prompt"
assert_contains "synthesis-brief: names the mandatory table" \
  "| Kind | Claim | Claim type | Convergence | Outliers | Grounding |" "$synthesis_prompt"
assert_contains "synthesis-brief: passes the staffed cards' anti-patterns, unattributed" "Discount any input passage of these shapes" "$synthesis_prompt"
assert_not_contains "synthesis-brief: no card role line" "Lays out the venture" "$synthesis_prompt"
assert_not_contains "synthesis-brief: no identity framing" "You are" "$synthesis_prompt"
# The discipline column of the staffing table names the venture's disciplines,
# which is frame content, not a seat; the card column is what is withheld.
no_roster_leak "synthesis-brief" "$(printf '%s\n' "$synthesis_prompt" | grep -v '^| product-strategy | agent-persona |')"
assert_contains "synthesis-brief: --deliver-file writes synthesis.md" "$run/synthesis.md" \
  "$("$FANOUT" synthesis-brief --deliver-file --run "$run" "$v" 2>&1)"

good_synthesis() {
  cat >"$1" <<'EOF'
## Synthesis

The inputs agree on the segment and split on the sinks; Input A and Input B agree on the audit.

## Synthesis table

| Kind | Claim | Claim type | Convergence | Outliers | Grounding |
| --- | --- | --- | --- | --- | --- |
| agreement | The end-of-shift ops lead is the sharpest segment | extractive | 3 of 3 | none | workflow audit |
| tension | Whether the sinks accept direct writes | interpretive | 2 of 3 | Input B | none |
| open-question | Who owns the surface after launch | interpretive | 1 of 3 | Input A, Input C | none |
EOF
}
good_synthesis "$run/synthesis.md"
"$FANOUT" check-synthesis --run "$run" "$run/synthesis.md" >/dev/null 2>&1
assert_eq "check-synthesis: a well-formed table passes" "0" "$?"
synth_fail() {
  # $1 label, $2 sed expression
  sed "$2" "$run/synthesis.md" >"$tmp/s.md"
  "$FANOUT" check-synthesis --run "$run" "$tmp/s.md" >/dev/null 2>&1
  assert_eq "check-synthesis: $1 fails" "1" "$?"
}
synth_fail "an unknown claim type" 's/| extractive |/| obvious |/'
synth_fail "a percentage instead of a count" 's/| 3 of 3 |/| 90% |/'
synth_fail "more converging inputs than inputs" 's/| 3 of 3 |/| 4 of 3 |/'
synth_fail "a count over the wrong number of inputs" 's/| 3 of 3 |/| 3 of 4 |/'
synth_fail "a split claim that names no outlier" 's/| 2 of 3 | Input B |/| 2 of 3 | none |/'
synth_fail "an empty outliers cell" 's/| 2 of 3 | Input B |/| 2 of 3 |  |/'
synth_fail "outliers named although every input agrees" 's/| 3 of 3 | none |/| 3 of 3 | Input A |/'
synth_fail "an outlier named twice" 's/| Input A, Input C |/| Input A, Input A |/'
synth_fail "an outlier that is no input of this run" 's/| Input B |/| Input D |/'
synth_fail "an unknown kind" 's/| agreement |/| consensus |/'
synth_fail "an empty claim" 's/| agreement | The end-of-shift ops lead is the sharpest segment |/| agreement |  |/'
synth_fail "an empty grounding cell" 's/| none | workflow audit |/| none |  |/'
synth_fail "the wrong header" 's/| Grounding |$/| Sources |/'
synth_fail "a row with a missing cell" 's/| none | workflow audit |$/| none |/'
synth_fail "a seat id in the blind synthesis" 's/The inputs agree/The seat-2 input and the others agree/'
synth_fail "a card id in the blind synthesis" 's/The inputs agree/The ops-design input and the others agree/'
# shellcheck disable=SC2016 # literal backtick fences
synth_fail "a seat identity only inside a fence" 's/^## Synthesis table$/```\nops-design said so\n```\n\n## Synthesis table/'
synth_fail "a later whole-word model after a longer word" 's/The inputs agree/The opuses and opus agree/'
sed '/^## Synthesis table$/,$d' "$run/synthesis.md" >"$tmp/s.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s.md" >/dev/null 2>&1
assert_eq "check-synthesis: a missing table fails" "1" "$?"
sed '/^| /d' "$run/synthesis.md" >"$tmp/s.md"
printf '| Kind | Claim | Claim type | Convergence | Outliers | Grounding |\n| --- | --- | --- | --- | --- | --- |\n' >>"$tmp/s.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s.md" >/dev/null 2>&1
assert_eq "check-synthesis: a table with no rows fails" "1" "$?"
sed 's/| 3 of 3 | none |/| 5 of 5 | none |/' "$run/synthesis.md" >"$tmp/s.md"
"$FANOUT" check-synthesis "$tmp/s.md" >/dev/null 2>&1
assert_eq "check-synthesis: without a run any input count stands" "0" "$?"
sed 's/| 3 of 3 |/| 0 of 0 |/' "$run/synthesis.md" >"$tmp/s.md"
"$FANOUT" check-synthesis "$tmp/s.md" >/dev/null 2>&1
assert_eq "check-synthesis: a count over no inputs fails" "1" "$?"
sed 's/The inputs agree/The product strategy reading and the others agree/' "$run/synthesis.md" >"$tmp/s.md"
"$FANOUT" check-synthesis --run "$run" "$tmp/s.md" >/dev/null 2>&1
assert_eq "check-synthesis: a discipline named as the venture's own subject passes" "0" "$?"

"$FANOUT" challenge-brief --run "$(newrun)" "$v" >/dev/null 2>&1
assert_eq "challenge-brief: no synthesis yet is refused" "2" "$?"
cp "$run/synthesis.md" "$tmp/synthesis.keep"
sed_i "$run/synthesis.md" 's/| extractive |/| obvious |/'
"$FANOUT" challenge-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "challenge-brief: a synthesis failing the check is refused" "1" "$?"

out="$("$FANOUT" synthesis-brief --retry --run "$run" "$v" 2>&1)"
assert_eq "synthesis-brief --retry: re-asks a failing synthesis" "0" "$?"
assert_contains "synthesis-brief --retry: carries the findings" "claim type must be extractive or interpretive" "$out"
assert_contains "synthesis-brief --retry: and the failed answer" "| obvious |" "$out"
assert_file "synthesis-brief --retry: sets the failed answer aside" "$run/synthesis-attempt-1.md"
assert_no_file "synthesis-brief --retry: so the next answer lands fresh" "$run/synthesis.md"
cp "$run/synthesis-attempt-1.md" "$run/synthesis.md"
"$FANOUT" synthesis-brief --retry --run "$run" "$v" >/dev/null 2>&1
assert_eq "synthesis-brief --retry: a second re-ask is refused" "1" "$?"
cp "$tmp/synthesis.keep" "$run/synthesis.md"
rm -f "$run/synthesis-attempt-1.md"
"$FANOUT" synthesis-brief --retry --run "$run" "$v" >/dev/null 2>&1
assert_eq "synthesis-brief --retry: a passing synthesis has nothing to re-ask" "1" "$?"

challenge_prompt="$("$FANOUT" challenge-brief --run "$run" "$v" 2>&1)"
assert_eq "challenge-brief: exit 0" "0" "$?"
assert_contains "challenge-brief: carries the synthesis" "The inputs agree on the segment" "$challenge_prompt"
assert_contains "challenge-brief: carries the frame" "# Northwind Signals — Frame" "$challenge_prompt"
assert_contains "challenge-brief: asks for a premortem" "premortem" "$challenge_prompt"
assert_contains "challenge-brief: asks for a key-assumptions check" "key-assumptions check" "$challenge_prompt"
assert_not_contains "challenge-brief: never per-seat output" "MARK-ONE" "$challenge_prompt"
assert_not_contains "challenge-brief: no card role line" "Lays out the venture" "$challenge_prompt"
assert_not_contains "challenge-brief: no identity framing" "You are" "$challenge_prompt"
no_roster_leak "challenge-brief" "$(printf '%s\n' "$challenge_prompt" | grep -v '^| product-strategy | agent-persona |')"
assert_contains "challenge-brief: --deliver-file writes challenge.md" "rename it to \`$run/challenge.md\`" \
  "$("$FANOUT" challenge-brief --deliver-file --run "$run" "$v" 2>&1)"

"$FANOUT" amend-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "amend-brief: needs the challenge first" "2" "$?"
printf '## Premortem\n\nThe sinks reject writes.\n\n## Key-assumptions check\n\nA-2 carries the venture.\n' >"$run/challenge.md"
"$FANOUT" challenge-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "challenge-brief: the challenge runs once" "1" "$?"
amend_prompt="$("$FANOUT" amend-brief --run "$run" "$v" 2>&1)"
assert_eq "amend-brief: exit 0" "0" "$?"
assert_contains "amend-brief: carries the challenge" "The sinks reject writes" "$amend_prompt"
assert_contains "amend-brief: carries the synthesis" "The inputs agree on the segment" "$amend_prompt"
assert_contains "amend-brief: carries the anonymized inputs" "MARK-THREE" "$amend_prompt"
assert_not_contains "amend-brief: no card role line" "Lays out the venture" "$amend_prompt"
no_roster_leak "amend-brief" "$(printf '%s\n' "$amend_prompt" | grep -v '^| product-strategy | agent-persona |')"
assert_contains "amend-brief: --deliver-file writes amended.md" "rename it to \`$run/amended.md\`" \
  "$("$FANOUT" amend-brief --deliver-file --run "$run" "$v" 2>&1)"
sed 's/| 2 of 3 |/| 2 of 4 |/' "$run/synthesis.md" >"$run/amended.md"
"$FANOUT" amend-brief --run "$run" "$v" >/dev/null 2>&1
assert_eq "amend-brief: the synthesis amends at most once" "1" "$?"
"$FANOUT" attribute --run "$run" >/dev/null 2>&1
assert_eq "attribute: a failing amendment is refused" "1" "$?"
assert_no_file "attribute: and writes no table" "$run/table.md"
out="$("$FANOUT" amend-brief --retry --run "$run" "$v" 2>&1)"
assert_eq "amend-brief --retry: re-asks a failing amendment once" "0" "$?"
assert_contains "amend-brief --retry: carries the findings" "the run has 3" "$out"
"$FANOUT" amend-brief --retry --run "$run" "$v" >/dev/null 2>&1
assert_eq "amend-brief --retry: not twice" "1" "$?"
cp "$run/synthesis.md" "$run/amended.md"
sed_i "$run/amended.md" 's/The inputs agree on the segment/The amended inputs agree on the segment/'

# ---------------------------------------------------------------------------
# 8. Attribution returns only in the final table (REQ-P1.3, REQ-P1.9).
# ---------------------------------------------------------------------------
out="$("$FANOUT" attribute --run "$run" 2>&1)"
assert_eq "attribute: exit 0" "0" "$?"
assert_file "attribute: writes the final table" "$run/table.md"
tbl="$(cat "$run/table.md")"
attr_of() {
  case $(awk -F '\t' -v l="$1" '$1 == l { print $2 }' "$run/labels.tsv") in
    seat-1) printf 'Input %s (Product strategy, opus)' "$1" ;;
    seat-2) printf 'Input %s (Operations design, skeptic pole, sonnet)' "$1" ;;
    seat-3) printf 'Input %s (Operations design, optimist pole, haiku)' "$1" ;;
    *) printf unmapped ;;
  esac
}
for l in A B C; do
  assert_contains "attribute: Input $l is named with its seat" "$(attr_of $l)" "$tbl"
done
assert_contains "attribute: reads the amended synthesis when there is one" "The amended inputs agree" "$tbl"
assert_contains "attribute: prose outside the table stays blind" "Input A and Input B agree on the audit." "$tbl"
assert_not_contains "attribute: the synthesis input stays blind" "Product strategy" "$(cat "$run/synthesis-input.md")"
"$FANOUT" attribute --run "$run" >/dev/null 2>&1
assert_eq "attribute: an existing final table is never overwritten" "5" "$?"

r2="$(newrun)"
cp "$run/roster.tsv" "$run/labels.tsv" "$run/frame.md" "$r2/"
good_synthesis "$r2/synthesis.md"
sed_i "$r2/synthesis.md" 's/| Who owns the surface after launch |/| Who owns the surface after launch, as Input C (already noted) asks |/'
"$FANOUT" attribute --run "$r2" >/dev/null 2>&1
assert_eq "attribute: without an amendment it reads the synthesis" "0" "$?"
assert_contains "attribute: a label already followed by a note is not annotated twice" "as Input C (already noted) asks" "$(cat "$r2/table.md")"

# ---------------------------------------------------------------------------
# 9. Gate 2: escalations as typed human-power choices, the table's forks, and
#    the five outcomes (REQ-P1.5, REQ-P1.7, D-6).
# ---------------------------------------------------------------------------
printf '| Hide a \033[31mcolour\033[0m | human-authority — a one-way door | gate decider | none | irreversibility | halt |\n' >>"$run/seat-2.md"
out="$("$FANOUT" gate2 --run "$run" 2>&1)"
assert_eq "gate2: exit 0" "0" "$?"
assert_contains "gate2: an escalation becomes a choice with its powers" \
  "choice	1	seat-1	Commit the handover moment publicly	human-authority	gate decider	irreversibility	halt, override" "$out"
assert_eq "gate2: every seat's escalations are choices" "4" "$(printf '%s\n' "$out" | grep -c '^choice	')"
assert_contains "gate2: seat-3's escalation is choice four" "choice	4	seat-3	" "$out"
assert_eq "gate2: no control character reaches the choices" "0" "$(printf '%s\n' "$out" | grep -c "$esc")"
assert_contains "gate2: a tension is a fork" "fork	1	tension	Whether the sinks accept direct writes" "$out"
assert_contains "gate2: an open question is a fork" "fork	2	open-question	Who owns the surface after launch" "$out"
assert_contains "gate2: offers the five outcomes" "outcomes	proceed park kill re-run-seat pull-bench" "$out"
cp "$run/seat-2.md" "$tmp/seat-2.keep"
sed_i "$run/seat-2.md" 's/| irreversibility | halt |$/| vibes | halt |/'
"$FANOUT" gate2 --run "$run" >/dev/null 2>&1
assert_eq "gate2: a malformed seat artifact is refused" "1" "$?"
cp "$tmp/seat-2.keep" "$run/seat-2.md"

# ---------------------------------------------------------------------------
# 10. Recording a run in the venture: the final table, the challenge, the
#     roster, the frame, and every seat artifact, never the private map, and
#     once per run (REQ-P1.3).
# ---------------------------------------------------------------------------
out="$("$FANOUT" record --run "$run" "$v" 2>&1)"
assert_eq "record: exit 0" "0" "$?"
dest="$(printf '%s\n' "$out" | awk -F '\t' '$1 == "recorded" { print $2 }')"
assert_eq "record: lands under fanout/ dated" "fanout/2026-08-26-1" "$dest"
for f in table.md challenge.md roster.tsv frame.md seat-1.md seat-2.md seat-3.md; do
  assert_file "record: keeps $f" "$v/fanout/2026-08-26-1/$f"
done
for f in labels.tsv synthesis-input.md synthesis.md amended.md backend recorded; do
  assert_no_file "record: never keeps $f" "$v/fanout/2026-08-26-1/$f"
done
assert_eq "record: no staging or claim directory is left" "2026-08-26-1" "$(ls -A "$v/fanout")"
out="$("$FANOUT" record --run "$run" "$v" 2>&1)"
assert_contains "record: a second record of the same run is a no-op" "recorded	fanout/2026-08-26-1" "$out"
assert_no_file "record: and makes no second directory" "$v/fanout/2026-08-26-2"
r3="$(newrun)"
cp "$run/roster.tsv" "$run/table.md" "$run/frame.md" "$run/seat-1.md" "$run/seat-2.md" "$run/seat-3.md" "$r3/"
"$FANOUT" record --run "$r3" "$v" >/dev/null 2>&1
assert_file "record: another run takes the next number" "$v/fanout/2026-08-26-2/table.md"
r4="$(newrun)"
cp "$run/roster.tsv" "$run/table.md" "$run/frame.md" "$run/seat-1.md" "$r4/"
"$FANOUT" record --run "$r4" "$v" >/dev/null 2>&1
assert_eq "record: a run missing a seat artifact is refused" "2" "$?"
assert_no_file "record: and leaves no partial record" "$v/fanout/2026-08-26-3"
# shellcheck disable=SC2012 # the entry names of one directory, dotfiles included
assert_eq "record: nor a staging directory" "2026-08-26-1 2026-08-26-2" "$(ls -A "$v/fanout" | tr '\n' ' ' | sed 's/ $//')"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "record: the bundle still validates" "0" "$?"

# ---------------------------------------------------------------------------
# 11. re-run-seat: a new run carries the kept seats from the old one.
# ---------------------------------------------------------------------------
r5="$(newrun)"
"$FANOUT" roster --run "$r5" --backend subagent \
  --seat product-strategy@opus --seat ops-design:skeptic@sonnet --seat ops-design:optimist@haiku "$v" >/dev/null 2>&1
out="$("$FANOUT" carry --from "$run" --run "$r5" --seat seat-1 --seat seat-3 2>&1)"
assert_eq "carry: exit 0" "0" "$?"
assert_contains "carry: reports each carried seat" "carried	seat-3" "$out"
assert_file "carry: copies a kept seat" "$r5/seat-1.md"
assert_no_file "carry: leaves the re-run seat to its new session" "$r5/seat-2.md"
assert_no_file "carry: carries nothing downstream" "$r5/synthesis-input.md"
r6="$(newrun)"
"$FANOUT" roster --run "$r6" --backend subagent --seat product-strategy@sonnet "$v" >/dev/null 2>&1
"$FANOUT" carry --from "$run" --run "$r6" --seat seat-1 >/dev/null 2>&1
assert_eq "carry: a seat that differs between the rosters is refused" "2" "$?"

# ---------------------------------------------------------------------------
# 12. Staffing honesty: unstaffed disciplines auto-file coverage risks, a
#     missing card counts as unstaffed, a zero-seat run collapses, and a stale
#     collapse is superseded (REQ-P1.8).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$FANOUT" staff "$v" 2>&1)"
assert_eq "staff: exit 0" "0" "$?"
assert_contains "staff: files the unstaffed discipline" "filed	A-5	org-design" "$out"
am="$(cat "$v/assumptions.md")"
assert_contains "staff: the entry is a coverage risk" "### A-5 — coverage risk: org-design unstaffed" "$am"
assert_contains "staff: in the standard skeleton" "believe this venture's org-design calls" "$am"
assert_eq "staff: the register keeps a readable mode" "-rw-r--r--" "$(mode_of "$v/assumptions.md")"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: the filed bundle validates" "0" "$?"
before="$(cat "$v/assumptions.md")"
out="$("$FANOUT" staff "$v" 2>&1)"
assert_eq "staff: a re-run files nothing new" "$before" "$(cat "$v/assumptions.md")"
assert_contains "staff: a re-run reports the existing entry" "exists	A-5	org-design" "$out"

v="$(fresh)"
out="$("$FANOUT" staff --no-stake org-design "$v" 2>&1)"
assert_not_contains "staff: a discipline judged stake-free is not filed" "coverage risk" "$(cat "$v/assumptions.md")"
assert_contains "staff: and says so" "skipped	org-design	judged stake-free" "$out"

v="$(fresh)"
sed_i "$v/disciplines.md" 's/^| product-strategy | agent-persona | product-strategy |$/| product-strategy | agent-persona | no-such-card |/'
out="$("$FANOUT" staff "$v" 2>&1)"
assert_contains "staff: a seat with no card is unstaffed" "filed	A-5	product-strategy	no card" "$out"
assert_contains "staff: and the next discipline takes the next number" "filed	A-6	org-design" "$out"

v="$(fresh)"
sed_i "$v/disciplines.md" '/^| org-design | unstaffed | none |$/p'
"$FANOUT" staff "$v" >/dev/null 2>&1
assert_eq "staff: a discipline listed twice is filed once" "1" "$(grep -c 'coverage risk: org-design' "$v/assumptions.md")"

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
before="$(cat "$v/assumptions.md")"
out="$("$FANOUT" staff "$v" 2>&1)"
assert_contains "staff: a re-run of an unchanged zero-seat table reports the entry" "exists	A-5	personas waived" "$out"
assert_eq "staff: and files nothing" "$before" "$(cat "$v/assumptions.md")"
sed_i "$v/disciplines.md" 's/^| org-design | unstaffed | none |$/| org-design | named-human | Dana Reyes |/'
out="$("$FANOUT" staff "$v" 2>&1)"
am="$(cat "$v/assumptions.md")"
assert_contains "staff: a changed zero-seat table supersedes the stale collapse" "superseded	A-5	by A-6" "$out"
assert_contains "staff: with the annotation on the old entry" "- **Superseded-by:** A-6 (2026-08-26)" "$am"
assert_contains "staff: and a collapse that keeps the literal plural" "### A-6 — personas waived (zero-seat); 1 disciplines unstaffed" "$am"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: the superseding bundle validates" "0" "$?"
assert_contains "staff: entries stay separated by a blank line" "(2026-08-26)

### A-6" "$am"
sed_i "$v/disciplines.md" 's/^| product-strategy | unstaffed | none |$/| product-strategy | agent-persona | product-strategy |/'
out="$("$FANOUT" staff "$v" 2>&1)"
assert_contains "staff: a waiver that persona seats now contradict is reported" "stale	A-6	persona seats now staff this venture" "$out"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: and the bundle still validates" "0" "$?"

v="$(fresh)"
sed_i "$v/disciplines.md" 's/^| product-strategy | agent-persona | product-strategy |$/| product-strategy | unstaffed | none |/'
"$FANOUT" staff "$v" >/dev/null 2>&1
sed_i "$v/disciplines.md" 's/^| product-strategy | unstaffed | none |$/| product-strategy | agent-persona | product-strategy |/'
out="$("$FANOUT" staff "$v" 2>&1)"
assert_contains "staff: once seats are staffed the unstaffed discipline is filed on its own" "filed	A-6	org-design" "$out"
assert_contains "staff: and supersedes the waiver it replaces" "superseded	A-5	by A-6" "$out"
"$VALIDATE" "$v" >/dev/null 2>&1
assert_eq "staff: that bundle validates" "0" "$?"

v="$(fresh)"
cp -R "$REPO_ROOT/scripts" "$tmp/scripts-broken"
rm "$tmp/scripts-broken/resolve-catalog.sh"
"$tmp/scripts-broken/inception-fanout.sh" staff "$v" >/dev/null 2>&1
assert_eq "staff: a broken install is an environment error" "2" "$?"
assert_not_contains "staff: and files nothing" "coverage risk" "$(cat "$v/assumptions.md")"

# ---------------------------------------------------------------------------
# 13. The design-level wiring: the skill loads the procedure where the fan-out
#     runs, and both gates sit in the main conversation (REQ-P1.3, REQ-P1.7).
# ---------------------------------------------------------------------------
"$REPO_ROOT/scripts/resolve-rule-doc.sh" persona-fanout >/dev/null 2>&1
assert_eq "wiring: the procedure resolves through the rule-doc chain" "0" "$?"
skill="$(cat "$REPO_ROOT/skills/inception/SKILL.md")"
assert_contains "wiring: the skill loads it at point of use" "Doctrine: point-of-use persona-fanout" "$skill"
assert_contains "wiring: the skill asks the fan-out's gates in its own conversation" "its gates asked here" "$skill"
assert_contains "wiring: the skill files coverage risks through the helper" "inception-fanout.sh staff" "$skill"
proc="$(cat "$REPO_ROOT/doctrine/persona-fanout.md")"
assert_contains "wiring: Gate 1 is in the main conversation" "**Gate 1, in the main conversation.**" "$proc"
assert_contains "wiring: Gate 2 is in the main conversation" "**Gate 2, in the main conversation.**" "$proc"
assert_contains "wiring: a seat never prompts the human" "A seat never prompts the human" "$proc"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-fanout: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-fanout: all assertions passed"
