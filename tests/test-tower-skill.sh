#!/bin/bash
# Structural guard over the /tower skill (tower-front-door Task 4; D-1, D-3,
# D-4, D-5, D-12, D-14, D-15; REQ-A1.1, REQ-A1.3, REQ-A1.5, REQ-B1.1,
# REQ-B1.3, REQ-B1.4, REQ-C1.6, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4,
# REQ-F1.6, REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-H1.4).
#
# The skill is procedure the agent reads, not a script, so the [test] and
# [design-level] halves of its verification paths are a structural guard over
# skills/tower/SKILL.md (the same shape as tests/test-offload-skill.sh). Not
# covered here, by design: the routing judgment itself (Task 11's
# behavioral-eval gate), the scripted bring-up turn and REQ-A1.2's frugality
# (Task 13's demo, exercised by the operator; the kept prompt-eval suite is
# guarded-inoperative), REQ-A1.4's primitives-only review (design-level), and
# the posture floor's guard tests (Task 10). The literal-path shape check is a
# local copy of tests/test-skill-literal-path.sh's, whose list is scoped to
# the three dispatching skills that requirement names.
#
# Every phrase assertion runs over the body with newlines folded and runs of
# spaces squeezed (prose wraps at the lint width), and the checks that could pass with the property absent
# are probed at the end against deliberately violating strings, so a vacuous
# assertion fails this file rather than passing quietly.
#
# Asserted properties:
#   - the skill exists, is named `tower`, and its description reads as a
#     selector: it names the trigger (the front door) and the boundary (never
#     merges, never marks a PR ready, never starts a kickoff), and carries no
#     numbered procedure;
#   - the doctrine manifest loads flight-rules, work-placement, interaction-style
#     and tower-comms at run start and exactly spec-format and security-posture
#     at point of use, each named in the body (the guard's reverse use-site
#     check);
#   - the resolved-literal-path invocation pointer is present and no
#     variable-rooted `/scripts/` invocation shape remains, braced or bare;
#   - the flight rules are glossed with the analogy at first use in the body
#     (REQ-H1.4; the frontmatter description glosses by function, and is not
#     the doc surface this check reads);
#   - routing is per request, grounds are stated at routing time, and the text
#     carries no flight-rule flag or route-selecting knob (REQ-B1.1, REQ-B1.3);
#   - the override forces either rule in either direction and a crossed
#     automatic trigger states a reservation then complies (REQ-B1.4);
#   - escalation runs through /spec-draft with fold-detection, presents the
#     one-page case, and offers /spec-kickoff without starting it — no sentence
#     tells the agent to run or start the kickoff (REQ-D1.1–D1.3); orchestration
#     dispatches on an explicit go only, never on sign-off or on the spec PR's
#     merge (REQ-D1.4);
#   - status on demand is stated with the never-poll boundary (REQ-A1.5);
#   - bring-up checks the tower posture's deny floor and names the
#     reconstruction-from-evidence hook point inside its own section, and the
#     tower never edits a settings file (REQ-A1.3, D-14); that check fails
#     closed on a missing shipped deny list, separates an absent layer from
#     an unreadable one, covers `--settings`, resolves the hook path, reads
#     by projection only, and re-runs before lifting its block;
#   - branch, flight-id, and <spec> values are grammar-checked before any
#     command; a worker-surfaced mutation need becomes a request only on the
#     operator's own ask; the drift --text value is one argument, never
#     quoted; a failed /offload report is sanitized, and hand-off hygiene
#     and markup-neutralization cite their doctrine;
#   - merge, the ready flip, and sign-off are refused as reserved human
#     controls; force-push, amend, squash and rebase are never run; the tower
#     never edits the repository itself (REQ-G1.1–G1.4, REQ-C1.6);
#   - survival claims use the bounded-or-surfaced form, never an absolute one
#     (REQ-F1.6).
#
# Runs standalone: ./tests/test-tower-skill.sh
set -u
# Pin the C locale so grep character classes do not vary by host collation;
# disable pathname expansion so a parsed token is never glob-expanded.
LC_ALL=C
export LC_ALL
set -f
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/tower/SKILL.md"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'ok: %s\n' "$1"
}

if [ ! -f "$skill" ]; then
  fail "tower SKILL.md missing at $skill"
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
ok "skills/tower/SKILL.md exists"

# --- parse: frontmatter, description, body ---------------------------------------
# The frontmatter is the block between the opening `---` on line 1 and the
# next `---`; the body is everything after it. Fail closed on a file that does
# not open with the delimiter, so no later check runs on mis-split text.
if [ "$(sed -n '1p' "$skill")" != "---" ]; then
  fail "SKILL.md does not open with a frontmatter delimiter"
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
frontmatter=$(awk 'NR==1{next} $0=="---"{exit} {print}' "$skill")
body=$(awk 'NR==1{f=1; next} f==1 && $0=="---"{f=2; next} f==2{print}' "$skill")
description=$(printf '%s\n' "$frontmatter" \
  | awk '/^description:/{d=1; sub(/^description:[ >-]*/, ""); if (length($0)) print; next} d && /^[a-z-]+:/{exit} d{print}' \
  | tr '\n' ' ' | tr -s ' ')
flat=$(printf '%s\n' "$body" | tr '\n' ' ' | tr -s ' ')
if [ -z "$body" ] || [ -z "$flat" ]; then
  fail "SKILL.md has no body after the frontmatter"
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi

has_phrase() { # has_phrase <extended-regex>: case-insensitive, over the folded body
  printf '%s\n' "$flat" | grep -qiE -- "$1"
}

# section <heading-text>: the folded body of one `## ` section.
section() {
  printf '%s\n' "$body" | awk -v h="## $1" '
    $0 == h {on=1; next}
    on && /^## / {exit}
    on {print}' | tr '\n' ' ' | tr -s ' '
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
  && printf '%s\n' "$description" | grep -qiE 'never marks? a PR ready' \
  && printf '%s\n' "$description" | grep -qiE 'never starts? a kickoff'; then
  ok "description names the boundary (never merges, never marks a PR ready, never starts a kickoff)"
else
  fail "description does not state the boundary: never merges, never marks a PR ready, never starts a kickoff"
fi

numbered_re='^[[:space:]]*[0-9]+[.)][[:space:]]|^[[:space:]]*(Step|step) [0-9]'
if printf '%s\n' "$frontmatter" | grep -qE -- "$numbered_re"; then
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

# The point-of-use set is pinned (spec-format, security-posture) and every
# member must be named in the body prose outside the manifest block.
pou_expected="security-posture spec-format"
pou_actual=$(grep -E '^Doctrine: point-of-use ' "$skill" | awk '{print $3}' | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$pou_actual" = "$pou_expected" ]; then
  ok "manifest point-of-use set is exactly: $pou_expected"
else
  fail "manifest point-of-use set is '$pou_actual', expected '$pou_expected'"
fi
for doc in $pou_expected; do
  if printf '%s\n' "$body" | grep -v '^Doctrine:' | grep -qF -- "$doc"; then
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

# The forbidden shape is a variable-rooted /scripts/ or /tests/ path, bare or
# braced; the pointer's own negative example (`$VAR/scripts/<name>.sh`) is the
# one permitted mention.
# shellcheck disable=SC2016
var_shape='\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?/(scripts|tests)/'
# var_rooted <text>: prints what matches the forbidden shape once the one
# permitted mention is set aside.
# shellcheck disable=SC2016
var_rooted() {
  printf '%s\n' "$1" | sed 's/`\$VAR\/scripts\/<name>\.sh`//g' | grep -E -- "$var_shape"
}
if [ -n "$(var_rooted "$(cat "$skill")")" ]; then
  fail "skill carries a variable-rooted /scripts/ invocation shape (the flooding shape the convention forbids)"
else
  ok "no variable-rooted /scripts/ invocation shape remains"
fi

# --- the flight rules: gloss, per-request routing, stated grounds --------------

# first_use_paragraph <body>: the paragraph (blank-line delimited) holding the
# first mention of either flight rule, folded to one line.
first_use_paragraph() {
  printf '%s\n' "$1" | awk '
    BEGIN{RS=""; IGNORECASE=1}
    tolower($0) ~ /(visual|instrument) flight/ {gsub(/\n/, " "); print; exit}'
}
gloss_re='fly by what you can see[^.]*file a plan'
first_para=$(first_use_paragraph "$body")
if printf '%s\n' "$first_para" | tr -s ' ' | grep -qiE -- "$gloss_re"; then
  ok "flight rules glossed with the analogy in the paragraph of first use (REQ-H1.4)"
else
  fail "the flight rules' first use lacks the one-sentence analogy gloss in the same paragraph (REQ-H1.4)"
fi

if has_phrase 'flight rules are never a user-selected mode, flag, or persistent setting'; then
  ok "routing is per request and never a mode (REQ-B1.1)"
else
  fail "skill does not state that flight rules are never a user-selected mode, flag, or persistent setting (REQ-B1.1)"
fi

# No flight-rule flag anywhere in the file, and no backticked route-selecting
# knob (a `word:` token naming a route or a flight rule).
flag_re='--(visual|instrument|vfr|ifr|specless|filed)\b'
knob_tick_re='`[a-z_]*(route|flight|mode)[a-z_]*:'
knob_bare_re='(flight_rules?|routing_mode|default_route|route_default)[[:space:]]*:'
if grep -qiE -- "$flag_re" "$skill"; then
  fail "skill offers a flight-rule flag; flight rules are never a mode"
else
  ok "no flight-rule flag is offered"
fi

if grep -qiE -- "$knob_tick_re" "$skill" || grep -qiE -- "$knob_bare_re" "$skill"; then
  fail "skill names a route-selecting config knob; v1 mints no knob (D-12)"
else
  ok "no route-selecting config knob is named (D-12)"
fi

if has_phrase 'routing is never silent' && has_phrase 'route and its grounds'; then
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

if has_phrase 'forces either rule in either direction|forces either rule in both directions'; then
  ok "the override forces either rule in either direction (REQ-B1.4)"
else
  fail "skill does not state the two-way override (REQ-B1.4)"
fi

if has_phrase 'states its reservation[^.]*then compl(y|ies)'; then
  ok "a crossed automatic trigger states a reservation, then complies (REQ-B1.4)"
else
  fail "skill does not state reservation-then-comply for an override crossing a trigger (REQ-B1.4)"
fi

if has_phrase 'no override crosses a hard invariant: merge[^.]*overridden or not'; then
  ok "no override crosses a hard invariant, merge included (REQ-B1.4)"
else
  fail "skill does not state that no override crosses a hard invariant such as merge (REQ-B1.4)"
fi

# --- escalation: /spec-draft, the one-page case, /spec-kickoff offered ---------

if grep -q '/spec-draft' "$skill" && has_phrase 'fold-detection'; then
  ok "escalation runs through /spec-draft with fold-detection (REQ-D1.1)"
else
  fail "escalation does not name /spec-draft with fold-detection (REQ-D1.1)"
fi

if has_phrase 'one-page case'; then
  ok "escalation presents the one-page case (REQ-D1.2)"
else
  fail "skill does not present the one-page case at escalation (REQ-D1.2)"
fi

if has_phrase 'offers `/spec-kickoff' && has_phrase 'never starts the kickoff'; then
  ok "/spec-kickoff is offered and never started (REQ-D1.3)"
else
  fail "skill does not offer /spec-kickoff without starting it (REQ-D1.3)"
fi

# No sentence may tell the agent to run or start the kickoff. A clause is the
# text between sentence boundaries; one whose "never", "not", or "no" governs
# the verb (at most one word between) is a prohibition and is allowed.
# shellcheck disable=SC2016
kickoff_run_sentence() { # kickoff_run_sentence <text>: prints the offending clause, or nothing
  printf '%s\n' "$1" | tr ';' '.' | tr '.' '\n' \
    | grep -iE '(invoke|run|start|dispatch|relay|launch|hand)(e?s|ed|n?ing)? (off )?(the kickoff|`?/spec-kickoff)' \
    | grep -viE '(^|[^a-z])(never|not|no)\** ([a-z]+ )?(invoke|run|start|dispatch|relay|launch|hand)' | head -1
}
kickoff_run=$(kickoff_run_sentence "$flat")
if [ -n "$kickoff_run" ]; then
  fail "a sentence tells the agent to run or start the kickoff: '$kickoff_run'"
else
  ok "no sentence tells the agent to run or start the kickoff"
fi

if has_phrase 'only on an explicit, per-request go' \
  && has_phrase 'never self-starts on sign-off[^.]*never on the spec PR.s merge'; then
  ok "orchestration dispatches on an explicit go only, never on sign-off or merge (REQ-D1.4)"
else
  fail "skill does not bind the explicit-go rule against self-start on sign-off or merge (REQ-D1.4)"
fi

# --- status on demand, without supervision --------------------------------------

if has_phrase 'status on demand' && has_phrase 'never supervises or polls'; then
  ok "status on demand with the never-poll boundary (REQ-A1.5)"
else
  fail "skill does not state status on demand and the never-supervise boundary (REQ-A1.5)"
fi

if grep -q 'spec-status.sh' "$skill"; then
  ok "status on demand renders through the existing status surface"
else
  fail "status on demand does not name the existing spec-status surface"
fi

# --- bring-up: posture floor and the reconstruction hook point ------------------

bringup=$(section "Session bring-up")
if [ -z "$bringup" ]; then
  fail "no '## Session bring-up' section"
fi

if printf '%s\n' "$bringup" | grep -q 'tower-settings.json' \
  && printf '%s\n' "$bringup" | grep -qiE 'deny block is the floor'; then
  ok "bring-up checks the tower posture's deny floor (REQ-A1.3)"
else
  fail "bring-up does not check the tower posture's deny floor against config/tower-settings.json (REQ-A1.3)"
fi

if printf '%s\n' "$bringup" | grep -qiE 'no repo-mutating route'; then
  ok "an absent deny floor blocks repo-mutating routes"
else
  fail "bring-up does not block repo-mutating routes when the deny floor is absent (REQ-A1.3)"
fi

if printf '%s\n' "$bringup" | grep -qi 'reconstruct' \
  && printf '%s\n' "$bringup" | grep -qi 'durable evidence'; then
  ok "bring-up names the reconstruction-from-evidence hook point"
else
  fail "bring-up does not name reconstruction from durable evidence"
fi

if printf '%s\n' "$bringup" | grep -qiE 'fails closed[^.]*shipped deny list[^.]*absent or unreadable'; then
  ok "the posture check fails closed on an absent or unreadable shipped deny list"
else
  fail "bring-up does not fail closed when the shipped deny list is absent or unreadable"
fi

if printf '%s\n' "$bringup" | grep -qiE 'absent layer counts as empty' \
  && printf '%s\n' "$bringup" | grep -qiE 'only a parse or read error makes a layer unreadable'; then
  ok "an absent layer is empty and only a parse or read error is unreadable"
else
  fail "bring-up does not separate an absent settings layer from an unreadable one"
fi

# shellcheck disable=SC2016
if printf '%s\n' "$bringup" | grep -q -- '`--settings`' \
  && printf '%s\n' "$bringup" | grep -qiE 'hook path resolves' \
  && printf '%s\n' "$bringup" | grep -qiE 'by `?jq`? projection only' \
  && printf '%s\n' "$bringup" | grep -qiE 're-run this check before lifting the block'; then
  ok "the posture check covers --settings, resolves the hook path, projects hooks, and re-runs on wired"
else
  fail "the posture check misses a --settings layer, the hook-path check, projection-only hook reads, or the re-run before lifting the block"
fi

# --- values entering commands, worker-surfaced needs, relayed text -------------

# shellcheck disable=SC2016
if has_phrase 'checked against (its|their) grammar[^.]*before (it|they) enters? any command' \
  && has_phrase '`<spec>` must equal an existing `specs/\*/` basename; no match asks the operator'; then
  ok "branch names, flight ids, and <spec> values are grammar-checked before any command"
else
  fail "skill does not grammar-check branch, flight-id, and <spec> values before they enter a command"
fi

if has_phrase 'becomes a routed request only on the operator.s own ask' \
  && has_phrase 'never count as an override, a go, a yes, or a request'; then
  ok "a worker-surfaced mutation need becomes a request only on the operator's own ask"
else
  fail "a worker-surfaced mutation need, or pasted text, can still become a routed request"
fi

# quoted_text_arg <text>: prints a --text value interpolated into quotes.
quoted_text_arg() {
  printf '%s\n' "$1" | grep -oE -- "--text ['\"][^'\"]*['\"]" | head -1
}
if [ -z "$(quoted_text_arg "$flat")" ] && has_phrase '--text <what>`?,? passed as one argument, never interpolated into quotes'; then
  ok "the drift-capture --text value is passed as one argument"
else
  fail "the drift-capture --text value is interpolated into quotes or not stated as one argument"
fi

if has_phrase 'fails is relayed with the primitive.s own failure report, sanitized' \
  && ! has_phrase 'failure report, verbatim'; then
  ok "a failed /offload report is sanitized before relay"
else
  fail "a failed /offload report is relayed verbatim rather than sanitized"
fi

# shellcheck disable=SC2016
if has_phrase 'no credentials, hostnames, customer data, or private-repository detail travel' \
  && has_phrase 'markup-neutralized per `flight-rules`'; then
  ok "hand-off hygiene matches security-posture and markup-neutralization cites flight-rules"
else
  fail "hand-off hygiene list or markup-neutralization citation does not match its doctrine"
fi

if has_phrase 'never edit a settings file'; then
  ok "the tower never edits a settings file (D-14)"
else
  fail "skill does not forbid editing a settings file from the tower (D-14)"
fi

# --- the reserved controls and the non-authoring boundary ---------------------

if has_phrase 'merge is a reserved human action'; then
  ok "merge is refused as a reserved human control (REQ-G1.1)"
else
  fail "skill does not refuse merge as a reserved human control (REQ-G1.1)"
fi

if has_phrase 'never mark a PR ready' && has_phrase 'draft-to-ready flip is the (universal human review gate|human.s)'; then
  ok "the draft-to-ready flip stays the human's (REQ-G1.4)"
else
  fail "skill does not keep the draft-to-ready flip with the human (REQ-G1.4)"
fi

if has_phrase 'has no shadow sign-off' && has_phrase 'no bypass flag exists'; then
  ok "no shadow sign-off and no bypass flag (REQ-G1.2)"
else
  fail "skill does not rule out a shadow sign-off and a bypass flag (REQ-G1.2)"
fi

if has_phrase 'force-push, amend, squash, rebase' && has_phrase 'new commits only, on both rules' && has_phrase 'tower never runs them'; then
  ok "force-push, amend, squash and rebase are never run (REQ-G1.3)"
else
  fail "skill does not state that force-push, amend, squash and rebase are never run (REQ-G1.3)"
fi

if has_phrase 'never\** edit the repository from the tower' && has_phrase 'never edits the repository itself'; then
  ok "the tower never edits the repository itself (REQ-C1.6)"
else
  fail "skill does not state that the tower never edits the repository itself (REQ-C1.6)"
fi

# --- survival claims: bounded-or-surfaced, never absolute -----------------------

if has_phrase 'bounded-or-surfaced' && has_phrase 'bounded and swept, or durably surfaced'; then
  ok "survival claims use the bounded-or-surfaced form (REQ-F1.6)"
else
  fail "skill does not state survival in the bounded-or-surfaced form (REQ-F1.6)"
fi

# absolute_claim <folded-text>: prints the first absolute survival claim, or
# nothing. "never silently lost" is the bounded form; a negated promise ("not
# a promise that nothing is ever left behind") is the doctrine's own wording.
absolute_claim() {
  printf '%s\n' "$1" | tr ';' '.' | tr '.' '\n' \
    | sed -E 's/(never )?silently lost//g; s/not a promise that nothing is ever (lost|left behind)//g' \
    | grep -iE '(never|not|cannot|can.t) (be )?(ever )?lost|nothing (is|will be|gets) (ever )?(lost|left behind)|no work is (ever )?lost|always surviv|guaranteed to surviv' \
    | head -1
}
absolute=$(absolute_claim "$flat")
if [ -n "$absolute" ]; then
  fail "skill carries an absolute survival claim: '$absolute'"
else
  ok "no absolute survival claim"
fi

# --- self-check: the vacuity probes --------------------------------------------
# Each probe feeds a deliberately violating string through the same predicate
# the live check uses and expects it to be caught, so a check that would pass
# with the property absent fails here.

probe_absolute() { # probe_absolute <text>: the claim must be caught
  if [ -n "$(absolute_claim "$1")" ]; then ok "probe: absolute claim caught: '$1'"; else fail "probe: absolute claim NOT caught: '$1'"; fi
}
probe_absolute "work will never be lost"
probe_absolute "no work is ever lost"
probe_absolute "work always survives the tower"
probe_absolute "nothing is ever left behind"
probe_absolute "work is never silently lost and nothing is ever lost"
probe_absolute "it is not a promise, yet nothing is ever lost"
if [ -n "$(absolute_claim "it is not a promise that nothing is ever left behind")" ]; then
  fail "probe: the doctrine's negated promise is misread as an absolute claim"
else
  ok "probe: the doctrine's negated promise is not an absolute claim"
fi
if [ -n "$(absolute_claim "every residue is bounded and swept, or durably surfaced, never silently lost")" ]; then
  fail "probe: the bounded form is misread as an absolute claim"
else
  ok "probe: the bounded form is not an absolute claim"
fi

# shellcheck disable=SC2016
if printf '%s\n' '"${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh' | grep -qE -- "$var_shape" \
  && printf '%s\n' '$PLANWRIGHT_ROOT/scripts/x.sh' | grep -qE -- "$var_shape" \
  && printf '%s\n' '${root}/tests/x.sh' | grep -qE -- "$var_shape"; then
  ok "probe: braced and bare variable-rooted shapes are caught"
else
  fail "probe: a variable-rooted /scripts/ shape escapes the pattern"
fi

# shellcheck disable=SC2016
if [ -n "$(var_rooted 'never `$VAR/scripts/<name>.sh`; run $PLANWRIGHT_ROOT/scripts/x.sh')" ]; then
  ok "probe: a variable-rooted path beside the permitted mention is caught"
else
  fail "probe: a variable-rooted path hides behind the permitted mention on its line"
fi
# shellcheck disable=SC2016
if [ -n "$(var_rooted 'never `$VAR/scripts/<name>.sh`')" ]; then
  fail "probe: the permitted negative example is misread as an invocation"
else
  ok "probe: the permitted negative example alone is not flagged"
fi

# shellcheck disable=SC2016
if [ -n "$(kickoff_run_sentence 'Offer the kickoff, never start it. Then run `/spec-kickoff` automatically')" ]; then
  ok "probe: a sentence running the kickoff is caught"
else
  fail "probe: a sentence running the kickoff escapes the check"
fi
# shellcheck disable=SC2016
if [ -n "$(kickoff_run_sentence 'On a yes, the tower dispatches `/spec-kickoff specs/<spec>` as an `/offload` petition')" ]; then
  ok "probe: a sentence dispatching the kickoff is caught"
else
  fail "probe: a sentence dispatching the kickoff escapes the check"
fi
for kickoff_probe in 'the tower does not wait and runs the kickoff' \
  'the tower is starting the kickoff' \
  'with no objection the tower starts the kickoff'; do
  if [ -n "$(kickoff_run_sentence "$kickoff_probe")" ]; then
    ok "probe: a kickoff run past an unrelated negation or in -ing form is caught: '$kickoff_probe'"
  else
    fail "probe: a kickoff run escapes the check: '$kickoff_probe'"
  fi
done
if [ -n "$(kickoff_run_sentence 'this step is the fallback that runs it; the tower never runs it on the operator behalf')" ]; then
  fail "probe: a prohibition or an unrelated 'runs it' is misread as running the kickoff"
else
  ok "probe: prohibitions and unrelated verbs are not misread"
fi

if printf '%s\n' 'the tower in v1. It never merges. cites REQ-A1.1. It routes' \
  | grep -qE -- "$numbered_re"; then
  fail "probe: a version or id string is misread as a numbered procedure"
else
  ok "probe: version and id strings are not numbered procedures"
fi
if printf '%s\n' '1. Take the ask' | grep -qE -- "$numbered_re" \
  && printf '%s\n' 'Step 2 routes it' | grep -qE -- "$numbered_re"; then
  ok "probe: numbered and Step-N steps are caught"
else
  fail "probe: a numbered or Step-N step escapes the check"
fi

# shellcheck disable=SC2016
if printf '%s\n' 'pass --visual to skip the spec' | grep -qiE -- "$flag_re" \
  && printf '%s\n' 'set `route_mode: visual`' | grep -qiE -- "$knob_tick_re" \
  && printf '%s\n' 'default_route: instrument' | grep -qiE -- "$knob_bare_re"; then
  ok "probe: a flight-rule flag and route-selecting knobs are caught"
else
  fail "probe: a flight-rule flag or route-selecting knob escapes the pattern"
fi

if [ -n "$(quoted_text_arg "obs-record.sh --slug skill-drift --text '...'")" ] \
  && [ -n "$(quoted_text_arg 'obs-record.sh --text "<what>"')" ] \
  && [ -z "$(quoted_text_arg 'obs-record.sh --text <what>')" ]; then
  ok "probe: a quoted --text value is caught and a bare argument is not"
else
  fail "probe: the --text quoting check misreads a quoted or bare argument"
fi

late_gloss=$(printf '%s\n\n%s\n' 'The tower routes onto visual flight or instrument flight.' 'Later: visual rules when you fly by what you can see, instrument rules when you file a plan.')
if first_use_paragraph "$late_gloss" | grep -qiE -- "$gloss_re"; then
  fail "probe: a gloss placed after the first use is accepted"
else
  ok "probe: a gloss placed after the first use is caught"
fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all tower-skill structural tests passed"
