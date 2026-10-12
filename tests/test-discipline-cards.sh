#!/bin/bash
# Tests for the discipline-card schema, its linter, the card resolver, and the
# shipped cards (inception Task 4; REQ-P1.1, REQ-P1.2, REQ-P1.10 · D-3, D-4).
#
# Shape, mirroring test-inception-validate.sh: one golden card
# (tests/lib/discipline-card-fixture.sh) that must lint clean, then one seeded
# violation per enforced rule; the closing loop checks both ways that every
# code `card-lint.sh --rules` advertises has a fixture and every fixture's
# code is advertised. Then every shipped core card lints clean and matches the
# core catalog one-for-one, and an overlay fixture shows a team card resolving
# through the catalog merge while the core cards stay put (REQ-P1.10).
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/card-lint.sh"
RESOLVE="$REPO_ROOT/scripts/resolve-card.sh"
RULEDOC="$REPO_ROOT/scripts/resolve-rule-doc.sh"

# shellcheck source=tests/lib/discipline-card-fixture.sh
. "$REPO_ROOT/tests/lib/discipline-card-fixture.sh"

failures=0
exercised=""

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

for script in "$LINT" "$RESOLVE" "$RULEDOC"; do
  if [ ! -f "$script" ]; then
    echo "FAIL: script missing at $script" >&2
    exit 1
  fi
done

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME "$@"
}

# ---------------------------------------------------------------------------
# 1. The golden card lints clean.
# ---------------------------------------------------------------------------
write_golden_card "$tmp/golden"
out="$("$LINT" "$tmp/golden/fixture-discipline.md" 2>&1)"
rc=$?
assert_eq "golden card: exit 0" "0" "$rc"
assert_eq "golden card: no findings" "" "$out"

# ---------------------------------------------------------------------------
# 2. Seeded violations, one rule each (REQ-P1.1, REQ-P1.2).
#    seed <code> <expected-exit> <awk-program>: copy the golden card through
#    the awk program, lint it, and expect the code in the output.
# ---------------------------------------------------------------------------
n=0
seed() {
  code=$1
  want_rc=$2
  prog=$3
  n=$((n + 1))
  d="$tmp/seed-$n"
  write_golden_card "$d"
  awk "$prog" "$d/fixture-discipline.md" >"$d/mutated" || {
    echo "FAIL: seed $code: awk program failed" >&2
    failures=$((failures + 1))
    return
  }
  mv "$d/mutated" "$d/fixture-discipline.md"
  out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
  rc=$?
  assert_eq "$code (seed $n): exit $want_rc" "$want_rc" "$rc"
  assert_contains "$code (seed $n): finding reported" "[$code]" "$out"
  exercised="$exercised $code"
}

# Fail-closed gate: nothing else is checked.
seed FMT-MISSING 3 '!/^\*\*Card-format:\*\*/'
seed FMT-UNSUPPORTED 3 '{ sub(/^\*\*Card-format:\*\* 1$/, "**Card-format:** 2"); print }'
seed FENCE-UNBALANCED 3 '{ print } END { print "```" }'

# Header block.
seed HDR-ID 1 '{ sub(/^\*\*Card-id:\*\* .*/, "**Card-id:** other-discipline"); print }'
seed HDR-ID 1 '{ sub(/^\*\*Card-id:\*\* .*/, "**Card-id:** Bad_Id"); print }'
seed HDR-REVIEWED 1 '{ sub(/^\*\*Reviewed:\*\* .*/, "**Reviewed:** 2026-02-30"); print }'
seed HDR-REVIEWED 1 '!/^\*\*Reviewed:\*\*/'
seed HDR-ROT 1 '{ sub(/^\*\*Rot-rate:\*\* .*/, "**Rot-rate:** sometimes"); print }'
seed HDR-TIER 1 '{ sub(/^\*\*Default-tier:\*\* .*/, "**Default-tier:** senior"); print }'
seed HDR-RAPID 1 '{ sub(/^\*\*RAPID:\*\* .*/, "**RAPID:** I, D"); print }'
seed HDR-RAPID 1 '{ sub(/^\*\*RAPID:\*\* .*/, "**RAPID:** X"); print }'
seed HDR-BENCH 1 '{ sub(/^\*\*Bench:\*\* .*/, "**Bench:** maybe"); print }'
seed HDR-STANCE 1 '{ sub(/^\*\*Stance-axis:\*\* .*/, "**Stance-axis:** skeptical"); print }'
seed HDR-MODEL 1 '/^\*\*Stance-axis:\*\*/ { print; print "**Model-override:** two words"; next } { print }'
seed HDR-UNKNOWN 1 '/^\*\*Stance-axis:\*\*/ { print; print "**Backstory:** A long career in consulting."; next } { print }'
seed HDR-UNKNOWN 1 '/^\*\*Bench:\*\*/ { print; print "**Bench:** no"; next } { print }'
seed FMT-MISSING 3 '/^\*\*Bench:\*\*/ { print; print "**Card-format:** 7"; next } { print }'

# Section set.
seed SEC-MISSING 1 '/^## Blind spots$/ { skip = 1; next } skip && /^## / { skip = 0 } !skip'
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "## Backstory"; print ""; print "A long career."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Role$/ { print "Shaped by a long career in consulting."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "# Backstory"; print ""; print "A long career."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "Backstory"; print "---------"; print ""; print "A long career."; print "" } { print }'
seed SEC-EMPTY 1 '/^## Anti-patterns$/ { print; print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip'
# Moves the Role section to after the Mandate section.
# shellcheck disable=SC2016 # an awk program: $0 is awk's, not the shell's
seed SEC-ORDER 1 '/^## Role$/ { held = 1 } held && /^## / && !/^## Role$/ { held = 0 } held { buf = buf $0 "\n"; next } /^## Frameworks$/ { printf "%s", buf } { print }'

# Role, mandate, frameworks.
seed ROLE-FORM 1 '/^Frames the fixture/ { print "Frames options for this venture. It also ranks them."; next } { print }'
seed MANDATE-SIZE 1 '/^3\. Which constraint/ { next } { print }'
seed MANDATE-SIZE 1 '/^3\. Which constraint/ { print; for (i = 4; i <= 8; i++) print i ". Which risk in the frame matters most?"; next } { print }'
seed MANDATE-GENERIC 1 '/^1\. Which problem/ { print "1. Who is the target customer?"; next } { print }'
seed MANDATE-GENERIC 1 '/^1\. Which problem/ { print "1. Which of the frameworks below applies first?"; next } { print }'
seed MANDATE-FORM 1 '/^1\. Which problem/ { print "1. Name the problem in the frame this venture solves first."; next } { print }'
seed FRAMEWORK-SEQUENCE 1 '{ sub(/^1\. \*\*First method/, "- **First method"); print }'
seed FRAMEWORK-MISUSE 1 '!/^   Misuse: skipping/'

# Grounding and the artifact template.
seed GROUNDING-REFUSE 1 '!/^- \*\*Refuse without:\*\*/'
seed TEMPLATE-FORM 1 '{ sub(/^## Decisions I cannot make$/, "## Open questions"); print }'
seed TEMPLATE-FORM 1 '/^```/ { next } { print }'
seed TEMPLATE-DONE 1 '!/^\*\*Done when:\*\*/'

# Capability boundary (REQ-P1.2).
seed BOUNDARY-EXCEPTIONS 1 '{ sub(/^  - agent-senior:/, "  - senior:"); print }'
seed BOUNDARY-EXCEPTIONS 1 '/^- \*\*Per-activity exceptions:\*\*/ { next } /^  - (agent-senior|human-authority):/ { next } { print }'
seed BOUNDARY-ONEWAY 1 '{ sub(/^- \*\*One-way doors:\*\* human-authority/, "- **One-way doors:** structure-only"); print }'
seed BOUNDARY-OUTSCOPE 1 '!/^- \*\*Out of scope:\*\*/'

# Escalation contract (REQ-P1.5's typed triggers, carried by the card).
seed ESC-TYPED 1 '/^- \*\*irreversibility\*\*/ { print; print "- **gut-feel** (powers: halt): it feels risky."; next } { print }'
seed ESC-TYPED 1 '{ sub(/\(powers: disregard\)/, "(powers: ignore)"); print }'
seed ESC-COVERAGE 1 '!/^- \*\*contract-policy-change\*\*/'
# A fenced line is illustration, never structure.
# shellcheck disable=SC2016 # an awk program printing a literal fence
seed ESC-COVERAGE 1 '/^## Escalation contract$/ { print; print ""; print "```text"; skip = 1; next } skip && /^## / { print "```"; print ""; skip = 0 } { print }'
# shellcheck disable=SC2016 # an awk program printing a literal fence
seed GROUNDING-REFUSE 1 '/^- \*\*Refuse without:\*\*/ { print "```text"; print; print "```"; next } { print }'

# Bench and styling.
seed BENCH-TRIGGERS 1 '{ sub(/^\*\*Bench:\*\* no$/, "**Bench:** yes"); print }'
seed BENCH-TRIGGERS 1 '/^## Sources$/ { print "## Pull-in triggers"; print ""; print "- The frame names a regulator."; print "" } { print }'
seed STYLE-IDENTITY 1 '/^A recommendation with no cited evidence\.$/ { print "You are a seasoned strategist with 20 years of experience."; next } { print }'

# A bench card with its pull-in triggers is clean (the positive arm of
# BENCH-TRIGGERS), and so is a card that omits both optional keys.
d="$tmp/bench-ok"
write_golden_card "$d"
awk '{ sub(/^\*\*Bench:\*\* no$/, "**Bench:** yes") }
  /^## Sources$/ { print "## Pull-in triggers"; print ""; print "- The frame names a regulator."; print "" }
  { print }' "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "bench card with pull-in triggers: exit 0" "0" "$?"
assert_eq "bench card with pull-in triggers: no findings" "" "$out"

d="$tmp/no-optional"
write_golden_card "$d"
awk '!/^\*\*Stance-axis:\*\*/' "$d/fixture-discipline.md" >"$d/m" \
  && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "card without optional keys: exit 0" "0" "$?"

# The frame anchor accepts the frame's possessive and a typographic apostrophe.
d="$tmp/anchors"
write_golden_card "$d"
awk '/^1\. Which problem/ { print "1. Which problem in the frame'"'"'s scope comes first?"; next }
  /^3\. Which constraint/ { print "3. Which constraint does the venture\342\200\231s appetite impose?"; next }
  { print }' "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "frame anchors: possessive and typographic apostrophe accepted" "" "$out"

# A fenced example is never parsed as card structure: a `## Backstory` inside
# the artifact template is template text, not a section.
d="$tmp/fenced"
write_golden_card "$d"
awk '/^## Findings$/ { print "## Backstory"; print "" } { print }' \
  "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_not_contains "fenced heading is not a section" "[SEC-UNKNOWN]" "$out"

# Usage and environment errors.
"$LINT" >/dev/null 2>&1
assert_eq "no arguments: exit 2" "2" "$?"
"$LINT" "$tmp/does-not-exist.md" >/dev/null 2>&1
assert_eq "missing file: exit 2" "2" "$?"

# Several files: every file is linted, and the exit is the worst outcome.
out="$("$LINT" "$tmp/golden/fixture-discipline.md" "$tmp/seed-1/fixture-discipline.md" \
  "$tmp/seed-4/fixture-discipline.md" 2>&1)"
rc=$?
assert_eq "several files: worst outcome wins (refusal)" "3" "$rc"
assert_contains "several files: the later file is still linted" "[HDR-ID]" "$out"

# ---------------------------------------------------------------------------
# 3. Every shipped core card lints clean, and the core catalog and cards/
#    agree one-for-one (REQ-P1.1, REQ-P1.2; task Done-when).
# ---------------------------------------------------------------------------
shipped=""
for f in "$REPO_ROOT"/cards/*.md; do
  [ -f "$f" ] || continue
  shipped="$shipped $f"
done
if [ -z "$shipped" ]; then
  echo "FAIL: no shipped cards under $REPO_ROOT/cards" >&2
  failures=$((failures + 1))
fi
for f in $shipped; do
  out="$("$LINT" "$f" 2>&1)"
  rc=$?
  assert_eq "shipped card ${f##*/}: lints clean" "0" "$rc"
  [ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2
done
assert_contains "the product-strategy card ships" "/cards/product-strategy.md" "$shipped"

card_ids="$(for f in $shipped; do
  b=${f##*/}
  echo "${b%.md}"
done | sort)"
catalog_ids="$(awk '/^  - id: / { print $3 }' "$REPO_ROOT/config/discipline-cards.yaml" | sort)"
if [ -z "$catalog_ids" ]; then
  echo "FAIL: core discipline-cards catalog lists no ids" >&2
  failures=$((failures + 1))
fi
assert_eq "core catalog ids match the shipped card files" "$card_ids" "$catalog_ids"

# ---------------------------------------------------------------------------
# 4. REQ-P1.10 — the resolver maps a catalog id to its card, through the
#    catalog merge, and a team card in an overlay resolves without touching
#    the core cards.
# ---------------------------------------------------------------------------
core_env="PLANWRIGHT_ROOT=$REPO_ROOT"
out="$(base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" product-strategy 2>&1)"
assert_eq "core: product-strategy resolves" "0" "$?"
assert_eq "core: product-strategy resolves to the core card" \
  "$REPO_ROOT/cards/product-strategy.md" "$out"

ad="$tmp/adopter"
write_golden_card "$ad/cards" acme-regulatory
mkdir -p "$ad/catalogs"
cat >"$ad/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: acme-regulatory
    discipline: "Acme regulatory affairs"
YAML
list="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$ad" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" --list 2>&1)"
assert_eq "overlay: --list exits 0" "0" "$?"
assert_contains "overlay: the team card is listed from the adopter layer" \
  "acme-regulatory	adopter	$ad/cards/acme-regulatory.md" "$list"
assert_contains "overlay: the core card is unaffected" \
  "product-strategy	core	$REPO_ROOT/cards/product-strategy.md" "$list"
team="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$ad" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" acme-regulatory 2>&1)"
assert_eq "overlay: the team card resolves to its overlay file" \
  "$ad/cards/acme-regulatory.md" "$team"
"$LINT" "$team" >/dev/null 2>&1
assert_eq "overlay: the resolved team card lints clean" "0" "$?"

# Supersede: an overlay that replaces a core entry by id ships its own card,
# and the id resolves to that file.
sd="$tmp/supersede"
write_golden_card "$sd/cards" product-strategy
mkdir -p "$sd/catalogs"
cat >"$sd/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: product-strategy
    discipline: "Product strategy (company edition)"
    supersede: true
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$sd" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" product-strategy 2>&1)"
assert_eq "supersede: the id resolves to the overlay's card" \
  "$sd/cards/product-strategy.md" "$out"

# Refusals: a bad id never reaches a path; an unknown id and a listed id with
# no card file are not-found; an overlay card symlinked outside its layer root
# is never returned.
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" ../etc/passwd >/dev/null 2>&1
assert_eq "bad id: exit 2" "2" "$?"
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" no-such-card >/dev/null 2>&1
assert_eq "unknown id: exit 1" "1" "$?"

nc="$tmp/no-card"
mkdir -p "$nc/catalogs"
cat >"$nc/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: ghost-discipline
    discipline: "Ghost"
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$nc" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" ghost-discipline 2>&1)"
assert_eq "listed id with no card file: exit 1" "1" "$?"
assert_contains "listed id with no card file: says so" "no card file" "$out"

esc="$tmp/escape"
mkdir -p "$esc/catalogs" "$esc/cards" "$tmp/outside"
write_golden_card "$tmp/outside" escapee
ln -s "$tmp/outside/escapee.md" "$esc/cards/escapee.md"
cat >"$esc/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: escapee
    discipline: "Escapee"
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$esc" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" escapee 2>/dev/null)"
assert_eq "symlink escaping the layer root: exit 1" "1" "$?"
assert_eq "symlink escaping the layer root: no path printed" "" "$out"

# ---------------------------------------------------------------------------
# 5. Task Done-when — the schema and recipe docs resolve via the rule-doc
#    chain, and the anti-authority styling rules are explicit.
# ---------------------------------------------------------------------------
for doc in discipline-cards card-authoring; do
  path="$(base "$core_env" /bin/bash "$RULEDOC" "$doc" 2>/dev/null)"
  assert_eq "rule-doc chain resolves $doc to the core doctrine" \
    "$REPO_ROOT/doctrine/$doc.md" "$path"
done
schema="$(cat "$REPO_ROOT/doctrine/discipline-cards.md" 2>/dev/null)"
assert_contains "schema doc: anti-authority styling section" "## Anti-authority styling" "$schema"
assert_contains "schema doc: typed escalation taxonomy" "## Escalation trigger taxonomy" "$schema"
recipe="$(cat "$REPO_ROOT/doctrine/card-authoring.md" 2>/dev/null)"
assert_contains "recipe doc: names the linter as its last gate" "card-lint.sh" "$recipe"

# ---------------------------------------------------------------------------
# 6. Coverage: the advertised rule set and the exercised rule set agree.
# ---------------------------------------------------------------------------
rules="$("$LINT" --rules 2>&1)"
assert_eq "--rules: exit 0" "0" "$?"
missing_fixture=
for code in $(printf '%s\n' "$rules" | awk 'NF { print $1 }'); do
  case " $exercised " in
    *" $code "*) ;;
    *) missing_fixture="$missing_fixture $code" ;;
  esac
done
assert_eq "every advertised rule has a seeded-violation fixture" "" "$missing_fixture"
unadvertised=
for code in $exercised; do
  if ! printf '%s\n' "$rules" | awk 'NF { print $1 }' | grep -qx -- "$code"; then
    unadvertised="$unadvertised $code"
  fi
done
assert_eq "every exercised rule is advertised by --rules" "" "$unadvertised"

if [ "$failures" -ne 0 ]; then
  echo "test-discipline-cards: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-discipline-cards: all assertions passed"
