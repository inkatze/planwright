#!/bin/bash
# Structural guard over the /tower skill (tower-front-door Task 4; D-1, D-3,
# D-4, D-5, D-12, D-15; REQ-A1.1, REQ-A1.3, REQ-A1.5, REQ-B1.1, REQ-B1.3,
# REQ-B1.4, REQ-D1.1, REQ-D1.3, REQ-D1.4, REQ-G1.1, REQ-G1.2, REQ-H1.4).
#
# The skill is procedure the agent reads, not a script, so the [test] and
# [design-level] halves of its verification paths are a structural guard over
# skills/tower/SKILL.md (the same shape as tests/test-offload-skill.sh). The
# routing judgment itself is Task 11's behavioral-eval gate; this file pins
# what the text must state and what it must not contain.
#
# Asserted properties:
#   - the skill exists, is named `tower`, and its description reads as a
#     selector: it names the trigger (the front door) and the boundary (never
#     merges, never marks a PR ready, never starts a kickoff), and carries no
#     numbered procedure;
#   - the doctrine manifest loads flight-rules, work-placement, interaction-style
#     and tower-comms at run start, on machine-parseable lines, and every
#     point-of-use doc is named in the body (the guard's reverse use-site check);
#   - the resolved-literal-path invocation pointer is present and no
#     `$VAR/scripts/x.sh` shape remains (the plugin-script-invocation convention);
#   - the flight rules are glossed in one sentence at first use (REQ-H1.4);
#   - routing is per request, grounds are stated at routing time, and the text
#     carries no mode flag or persistent setting (REQ-B1.1, REQ-B1.3);
#   - the override forces either rule in either direction and a crossed
#     automatic trigger states a reservation then complies (REQ-B1.4);
#   - escalation runs through /spec-draft with fold-detection, presents the
#     one-page case, and offers /spec-kickoff without starting it (REQ-D1.1,
#     REQ-D1.2, REQ-D1.3); orchestration dispatches on an explicit go only,
#     never on sign-off or on the spec PR's merge (REQ-D1.4);
#   - status on demand is stated with the never-poll boundary (REQ-A1.5);
#   - the tower posture is checked at bring-up (REQ-A1.3) and the
#     reconstruction hook point is named;
#   - merge, the ready flip, and sign-off are refused as reserved human
#     controls, and the tower never edits the repository itself (REQ-G1.1,
#     REQ-G1.2, the flight boundary);
#   - survival claims use the bounded-or-surfaced form, never an absolute one.
#
# Runs standalone: ./tests/test-tower-skill.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation.
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/tower/SKILL.md"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

if [ ! -f "$skill" ]; then
  fail "tower SKILL.md missing at $skill"
  echo "$failures failure(s)" >&2
  exit 1
fi
ok "skills/tower/SKILL.md exists"

# The frontmatter is the block between the first two `---` lines; the body is
# everything after it. The description is the folded scalar under
# `description:` up to the next top-level key.
frontmatter=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$skill")
body=$(awk 'f>=2{print} $0=="---"{f++}' "$skill")
description=$(printf '%s\n' "$frontmatter" \
  | awk '/^description:/{d=1; sub(/^description:[ >-]*/, ""); if (length($0)) print; next} d && /^[a-z-]+:/{exit} d{print}')
# Prose wraps at the lint width, so a multi-word phrase can straddle a line
# break; phrase assertions run over the body with newlines folded to spaces.
flat=$(printf '%s\n' "$body" | tr '\n' ' ')

has_phrase() { # has_phrase <extended-regex>: case-insensitive, over the folded body
  printf '%s\n' "$flat" | grep -qiE -- "$1"
}

# --- frontmatter: name and the selector-shaped description ---------------------

if printf '%s\n' "$frontmatter" | grep -qE '^name: tower$'; then
  ok "frontmatter names the skill tower"
else
  fail "frontmatter does not carry 'name: tower'"
fi

if [ -n "$description" ]; then
  ok "frontmatter carries a description"
else
  fail "frontmatter carries no description"
fi

if printf '%s\n' "$description" | grep -qi 'front door'; then
  ok "description names the trigger (the front door)"
else
  fail "description does not name the front door (the selector's trigger)"
fi

if printf '%s\n' "$description" | grep -qi 'never merges' \
  && printf '%s\n' "$description" | grep -qi 'ready' \
  && printf '%s\n' "$description" | grep -qi 'kickoff'; then
  ok "description names the boundary (never merges, never flips ready, never starts a kickoff)"
else
  fail "description does not state the boundary: never merges, the ready flip, the kickoff (REQ-A1.1 selector)"
fi

if printf '%s\n' "$description" | grep -qE '(^|[^0-9])[0-9]+\.[[:space:]]|^[[:space:]]*(Step|step) [0-9]'; then
  fail "description carries a numbered procedure; a selector states trigger and boundary only"
else
  ok "description carries no numbered procedure"
fi

desc_words=$(printf '%s\n' "$description" | wc -w | tr -d ' ')
if [ "$desc_words" -le 120 ]; then
  ok "description stays selector-sized ($desc_words words)"
else
  fail "description runs to $desc_words words; a selector is trigger and boundary, not procedure"
fi

# --- the doctrine manifest -----------------------------------------------------

for doc in flight-rules work-placement interaction-style tower-comms; do
  if grep -qE "^Doctrine: run-start $doc( |$)" "$skill"; then
    ok "manifest loads $doc at run start"
  else
    fail "manifest missing 'Doctrine: run-start $doc'"
  fi
done

# Every point-of-use doc must be named in the body prose outside the manifest
# block (the guard's reverse use-site check warns on a miss; this pins it).
pou_docs=$(grep -E '^Doctrine: point-of-use ' "$skill" | awk '{print $3}')
for doc in $pou_docs; do
  if printf '%s\n' "$body" | grep -v '^Doctrine:' | grep -q -- "$doc"; then
    ok "point-of-use doc $doc is named at its use site"
  else
    fail "point-of-use doc $doc is never named in the body prose"
  fi
done

# --- plugin-script invocation ---------------------------------------------------

if has_phrase 'resolved literal absolute path' && grep -q 'plugin-script-invocation' "$skill"; then
  ok "skill carries the resolved-literal-path pointer"
else
  fail "skill missing the resolved-literal-path pointer to doctrine/plugin-script-invocation.md"
fi

# The forbidden shape is the literal, unexpanded variable text in the prose.
# shellcheck disable=SC2016
if grep -qE '\$(CLAUDE_PLUGIN_ROOT|PLANWRIGHT_ROOT)/(scripts|tests)/' "$skill"; then
  fail "skill carries a \$VAR/scripts/ invocation shape (the flooding shape the convention forbids)"
else
  ok "no \$VAR/scripts/ invocation shape remains"
fi

# --- the flight rules: gloss, per-request routing, stated grounds --------------

first_visual=$(printf '%s\n' "$body" | grep -n -i 'visual flight' | head -1 | cut -d: -f1)
if [ -n "$first_visual" ]; then
  window=$(printf '%s\n' "$body" | sed -n "${first_visual},$((first_visual + 8))p" | tr '\n' ' ')
  if printf '%s\n' "$window" | grep -qi 'instrument' \
    && printf '%s\n' "$window" | grep -qiE 'file a plan|gauges|what you can see'; then
    ok "flight rules glossed in one sentence at first use (REQ-H1.4)"
  else
    fail "first use of the flight rules lacks the one-sentence analogy gloss (REQ-H1.4)"
  fi
else
  fail "skill never names visual flight"
fi

if has_phrase 'per request' && has_phrase 'never a (user-selected )?mode'; then
  ok "routing is per request and never a mode (REQ-B1.1)"
else
  fail "skill does not state per-request routing that is never a mode (REQ-B1.1)"
fi

# No mode flag or persistent setting in the text: no flight-rule flag in the
# argument hint, no config knob naming a route.
if printf '%s\n' "$frontmatter" | grep -qiE -- '--(visual|instrument|vfr|ifr|specless|filed)'; then
  fail "argument-hint offers a flight-rule flag; flight rules are never a mode"
else
  ok "argument-hint offers no flight-rule flag"
fi

if grep -qiE '(flight_rules?|routing_mode|default_route|route_default)[[:space:]]*:' "$skill"; then
  fail "skill names a route-selecting config knob; v1 mints no knob (D-12)"
else
  ok "no route-selecting config knob is named (D-12)"
fi

if grep -qi 'grounds' "$skill" && has_phrase 'routing is never silent'; then
  ok "grounds are stated and routing is never silent (REQ-B1.3)"
else
  fail "skill does not bind stated grounds and never-silent routing (REQ-B1.3)"
fi

if has_phrase 'trigger that fired|which trigger fired|the fired trigger'; then
  ok "the stated-grounds form names the fired trigger"
else
  fail "the stated-grounds form does not name the fired trigger and its evidence"
fi

# --- the override --------------------------------------------------------------

if grep -qi 'override' "$skill" && has_phrase 'either direction|both directions'; then
  ok "the override forces either rule in either direction (REQ-B1.4)"
else
  fail "skill does not state the two-way override (REQ-B1.4)"
fi

if grep -qi 'reservation' "$skill" && has_phrase 'then compl(y|ies)'; then
  ok "a crossed automatic trigger states a reservation, then complies (REQ-B1.4)"
else
  fail "skill does not state reservation-then-comply for an override crossing a trigger (REQ-B1.4)"
fi

# --- escalation: /spec-draft, the one-page case, /spec-kickoff offered ---------

if grep -q '/spec-draft' "$skill" && grep -qi 'fold-detection' "$skill"; then
  ok "escalation runs through /spec-draft with fold-detection (REQ-D1.1)"
else
  fail "escalation does not name /spec-draft with fold-detection (REQ-D1.1)"
fi

if has_phrase 'one-page case'; then
  ok "escalation presents the one-page case (REQ-D1.2)"
else
  fail "skill does not present the one-page case at escalation (REQ-D1.2)"
fi

# The backticked skill name is literal regex text, not a command substitution.
# shellcheck disable=SC2016
if grep -q '/spec-kickoff' "$skill" \
  && has_phrase 'never start(s|ed)? (it|the kickoff|`/spec-kickoff`|/spec-kickoff)|offer(s|ed)?[^.]*never start'; then
  ok "/spec-kickoff is offered and never started (REQ-D1.3)"
else
  fail "skill does not offer /spec-kickoff without starting it (REQ-D1.3)"
fi

if grep -qi 'explicit' "$skill" \
  && has_phrase 'never self-start|not self-start|never start(s)? (orchestration|it) on' \
  && grep -qi 'merge' "$skill"; then
  ok "orchestration dispatches on an explicit go only (REQ-D1.4)"
else
  fail "skill does not bind the explicit-go rule against self-start on sign-off or merge (REQ-D1.4)"
fi

# --- status on demand, without supervision --------------------------------------

if has_phrase 'on demand' && has_phrase 'never (supervise|poll)'; then
  ok "status on demand with the never-poll boundary (REQ-A1.5)"
else
  fail "skill does not state status on demand and the never-supervise boundary (REQ-A1.5)"
fi

if grep -q 'spec-status.sh' "$skill"; then
  ok "status on demand renders through the existing status surface"
else
  fail "status on demand does not name the existing spec-status surface"
fi

# --- bring-up: posture check and the reconstruction hook point ------------------

if grep -q 'tower-settings.json' "$skill" && grep -qi 'posture' "$skill"; then
  ok "bring-up checks the tower posture (REQ-A1.3)"
else
  fail "bring-up does not check the tower posture against config/tower-settings.json (REQ-A1.3)"
fi

if grep -qi 'reconstruct' "$skill" && has_phrase 'durable evidence'; then
  ok "bring-up names the reconstruction-from-evidence hook point"
else
  fail "bring-up does not name reconstruction from durable evidence"
fi

# --- the reserved controls and the non-authoring boundary ---------------------

if has_phrase 'never merge|never auto-merge|merge (is|stays|remains) (the human|a reserved)'; then
  ok "merge is refused as a reserved human control (REQ-G1.1)"
else
  fail "skill does not refuse merge as a reserved human control (REQ-G1.1)"
fi

if has_phrase 'never mark(s)? (a|the) PR ready|ready flip|draft.to.ready'; then
  ok "the draft-to-ready flip stays the human's"
else
  fail "skill does not keep the draft-to-ready flip with the human (REQ-G1.4)"
fi

if has_phrase 'shadow sign-off|no sign-off' && grep -qi 'bypass' "$skill"; then
  ok "no shadow sign-off and no bypass flag (REQ-G1.2)"
else
  fail "skill does not rule out a shadow sign-off and a bypass flag (REQ-G1.2)"
fi

if has_phrase 'never (edits|writes|authors) the (repo|repository)|does not author'; then
  ok "the tower never edits the repository itself (the flight boundary)"
else
  fail "skill does not state that the tower never edits the repository itself (REQ-C1.6)"
fi

# --- survival claims: bounded-or-surfaced, never absolute -----------------------

if grep -qi 'bounded' "$skill" && grep -qi 'surfaced' "$skill"; then
  ok "survival claims use the bounded-or-surfaced form (REQ-F1.6)"
else
  fail "skill does not state survival in the bounded-or-surfaced form (REQ-F1.6)"
fi

# "never silently lost" is the bounded form; a bare "never lost" or "nothing is
# ever lost" is the absolute claim the doctrine forbids.
absolute=$(printf '%s\n' "$flat" | grep -oiE 'nothing is ever (lost|left behind)|never (silently )?lost' | grep -viE 'silently' | head -1)
if [ -n "$absolute" ]; then
  fail "skill carries an absolute survival claim: '$absolute'"
else
  ok "no absolute survival claim"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all tower-skill structural tests passed"
