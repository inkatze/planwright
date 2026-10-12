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
# The format gate comes before anything else, the fence check included: a
# future major may fence differently.
# shellcheck disable=SC2016 # an awk program printing a literal fence
seed FMT-UNSUPPORTED 3 '{ sub(/^\*\*Card-format:\*\* 1$/, "**Card-format:** 2"); print } END { print "```" }'

# Header block.
seed HDR-ID 1 '{ sub(/^\*\*Card-id:\*\* .*/, "**Card-id:** other-discipline"); print }'
seed HDR-ID 1 '{ sub(/^\*\*Card-id:\*\* .*/, "**Card-id:** Bad_Id"); print }'
seed HDR-REVIEWED 1 '{ sub(/^\*\*Reviewed:\*\* .*/, "**Reviewed:** 2026-02-30"); print }'
seed HDR-REVIEWED 1 '!/^\*\*Reviewed:\*\*/'
seed HDR-ROT 1 '{ sub(/^\*\*Rot-rate:\*\* .*/, "**Rot-rate:** sometimes"); print }'
seed HDR-TIER 1 '{ sub(/^\*\*Default-tier:\*\* .*/, "**Default-tier:** senior"); print }'
seed HDR-RAPID 1 '{ sub(/^\*\*RAPID:\*\* .*/, "**RAPID:** I, D"); print }'
seed HDR-RAPID 1 '{ sub(/^\*\*RAPID:\*\* .*/, "**RAPID:** X"); print }'
seed HDR-RAPID 1 '{ sub(/^\*\*RAPID:\*\* .*/, "**RAPID:** I, I"); print }'
long_id=$(printf 'a%.0s' $(seq 1 65))
seed HDR-BENCH 1 '{ sub(/^\*\*Bench:\*\* .*/, "**Bench:** maybe"); print }'
seed HDR-STANCE 1 '{ sub(/^\*\*Stance-axis:\*\* .*/, "**Stance-axis:** skeptical"); print }'
seed HDR-MODEL 1 '/^\*\*Stance-axis:\*\*/ { print; print "**Model-override:** two words"; next } { print }'
seed HDR-UNKNOWN 1 '/^\*\*Stance-axis:\*\*/ { print; print "**Backstory:** A long career in consulting."; next } { print }'
seed HDR-UNKNOWN 1 '/^\*\*Bench:\*\*/ { print; print "**Bench:** no"; next } { print }'
seed FMT-MISSING 3 '/^\*\*Bench:\*\*/ { print; print "**Card-format:** 7"; next } { print }'

# Section set.
# Every required section, one at a time (Pull-in triggers is the bench-only
# exception, covered by BENCH-TRIGGERS).
required="Role|Mandate|Frameworks|Grounding|Input subscription|Artifact template|Capability boundary|Escalation contract|Register rules|Anti-patterns|Blind spots|Conflict and deference|Independence|Sources"
old_ifs=$IFS
IFS='|'
for sec in $required; do
  IFS=$old_ifs
  seed SEC-MISSING 1 "/^\`\`\`/ { f = !f } /^## $sec\$/ { skip = 1; next } skip && !f && /^## / { skip = 0 } !skip"
done
IFS=$old_ifs
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "## Backstory"; print ""; print "A long career."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Role$/ { print "Shaped by a long career in consulting."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "# Backstory"; print ""; print "A long career."; print "" } { print }'
seed SEC-UNKNOWN 1 '/^## Sources$/ { print "Backstory"; print "---------"; print ""; print "A long career."; print "" } { print }'
seed SEC-EMPTY 1 '/^## Anti-patterns$/ { print; print ""; skip = 1; next } skip && /^## / { skip = 0 } !skip'
# A section holding only a fence holds no card content.
# shellcheck disable=SC2016 # an awk program printing a literal fence
seed SEC-EMPTY 1 '/^Implementation cost;/ { print "```text"; print "Implementation cost."; print "```"; next } { print }'
# Moves the Role section to after the Mandate section.
# shellcheck disable=SC2016 # an awk program: $0 is awk's, not the shell's
seed SEC-ORDER 1 '/^## Role$/ { held = 1 } held && /^## / && !/^## Role$/ { held = 0 } held { buf = buf $0 "\n"; next } /^## Frameworks$/ { printf "%s", buf } { print }'

# Role, mandate, frameworks.
seed ROLE-FORM 1 '/^Frames the fixture/ { print "Frames options for this venture. It also ranks them."; next } { print }'
seed ROLE-FORM 1 '/^Frames the fixture/ { print "Frames options for this venture?"; next } { print }'
seed SEC-ORDER 1 '{ print } END { print ""; print "## Sources"; print ""; print "- Another source."; }'
seed MANDATE-SIZE 1 '/^3\. Which constraint/ { next } { print }'
seed MANDATE-SIZE 1 '/^3\. Which constraint/ { print; for (i = 4; i <= 8; i++) print i ". Which risk in the frame matters most?"; next } { print }'
seed MANDATE-GENERIC 1 '/^1\. Which problem/ { print "1. Who is the target customer?"; next } { print }'
seed MANDATE-GENERIC 1 '/^1\. Which problem/ { print "1. Which of the frameworks below applies first?"; next } { print }'
seed MANDATE-FORM 1 '/^1\. Which problem/ { print "1. Name the problem in the frame this venture solves first."; next } { print }'
seed MANDATE-FORM 1 '/^3\. Which constraint/ { print; print "- Who is the target customer?"; print "- How big is the market?"; next } { print }'
seed FRAMEWORK-SEQUENCE 1 '{ sub(/^1\. \*\*First method/, "- **First method"); print }'
# An unnumbered paragraph would otherwise add a framework with no caveat.
seed FRAMEWORK-SEQUENCE 1 '/^   Misuse: skipping/ { print; print "Then run a SWOT pass when time allows."; next } { print }'
seed FRAMEWORK-MISUSE 1 '!/^   Misuse: skipping/'

# Grounding and the artifact template.
seed GROUNDING-REFUSE 1 '!/^- \*\*Refuse without:\*\*/'
seed TEMPLATE-FORM 1 '{ sub(/^## Decisions I cannot make$/, "## Open questions"); print }'
seed TEMPLATE-FORM 1 '/^```/ { next } { print }'
seed TEMPLATE-DONE 1 '!/^\*\*Done when:\*\*/'
seed TEMPLATE-DONE 1 '/^\*\*Done when:\*\*/ { next } /^## Artifact template$/ { print; print ""; print "**Done when:** every question has an answer."; next } { print }'

# Capability boundary (REQ-P1.2).
seed BOUNDARY-EXCEPTIONS 1 '{ sub(/^  - agent-senior:/, "  - senior:"); print }'
seed BOUNDARY-EXCEPTIONS 1 '/^- \*\*Per-activity exceptions:\*\*/ { next } /^  - (agent-senior|human-authority):/ { next } { print }'
seed BOUNDARY-ONEWAY 1 '{ sub(/^- \*\*One-way doors:\*\* human-authority/, "- **One-way doors:** structure-only"); print }'
seed BOUNDARY-OUTSCOPE 1 '!/^- \*\*Out of scope:\*\*/'
seed BOUNDARY-OUTSCOPE 1 '{ sub(/^- \*\*Out of scope:\*\* .*/, "- **Out of scope:**"); print }'

# Escalation contract (REQ-P1.5's typed triggers, carried by the card).
seed ESC-TYPED 1 '/^- \*\*irreversibility\*\*/ { print; print "- **gut-feel** (powers: halt): it feels risky."; next } { print }'
seed ESC-TYPED 1 '{ sub(/\(powers: disregard\)/, "(powers: ignore)"); print }'
seed ESC-TYPED 1 '{ sub(/^- \*\*irreversibility\*\* \(powers: halt, override\):/, "- **irreversibility** halt:"); print }'
seed ESC-TYPED 1 '/^- \*\*irreversibility\*\*/ { print; print "- **irreversibility** (powers: halt): the call is a one-way door."; next } { print }'
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
# Each identity pattern on its own, credentials included (REQ-P1.1).
for line in "You are an analyst for this venture." "Brings ten years of experience." \
  "A world-class analysis." "Answers as a senior partner would." "Written with PhD rigor."; do
  seed STYLE-IDENTITY 1 "/^A recommendation with no cited evidence\\.\$/ { print \"$line\"; next } { print }"
done
seed STYLE-IDENTITY 1 '/^\*\*Bench:\*\*/ { print; print "**Credentials:** PhD, award-winning"; next } { print }'

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

for model in none opus/high; do
  d="$tmp/model-${model%%/*}"
  write_golden_card "$d"
  awk -v m="$model" '/^\*\*Stance-axis:\*\*/ { print; print "**Model-override:** " m; next } { print }' \
    "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
  out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
  assert_eq "Model-override $model: lints clean" "" "$out"
done

# The frame anchor accepts the frame's possessive and a typographic apostrophe.
d="$tmp/anchors"
write_golden_card "$d"
awk '/^1\. Which problem/ { print "1. Which problem in the frame'"'"'s scope comes first?"; next }
  /^3\. Which constraint/ { print "3. Which constraint does the venture\342\200\231s appetite impose?"; next }
  { print }' "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "frame anchors: possessive and typographic apostrophe accepted" "" "$out"
d="$tmp/anchor-venture"
write_golden_card "$d"
awk '/^1\. Which problem/ { print "1. Which problem does the venture'"'"'s first segment feel?"; next } { print }' \
  "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "frame anchors: the venture's possessive accepted" "" "$out"

# A fenced example is never parsed as card structure: a `## Backstory` inside
# the artifact template is template text, not a section.
d="$tmp/fenced"
write_golden_card "$d"
awk '/^## Findings$/ { print "## Backstory"; print "" } { print }' \
  "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_eq "fenced heading is not a section: exit 0" "0" "$?"
assert_not_contains "fenced heading is not a section" "[SEC-UNKNOWN]" "$out"
assert_eq "fenced heading is not a section: no findings" "" "$out"

# The Done-when line follows the template fence, not an earlier example fence.
d="$tmp/done-order"
write_golden_card "$d"
awk '/^\*\*Done when:\*\*/ { next }
  /^## Artifact template$/ { print; print ""; print "```text"; print "an example"; print "```"; print "";
    print "**Done when:** every question has an answer."; next } { print }' \
  "$d/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/fixture-discipline.md"
out="$("$LINT" "$d/fixture-discipline.md" 2>&1)"
assert_contains "Done-when between an example fence and the template: flagged" "[TEMPLATE-DONE]" "$out"

# The Card-id length limit, on a card whose file name matches its id.
d="$tmp/long-id"
write_golden_card "$d" "$long_id"
out="$("$LINT" "$d/$long_id.md" 2>&1)"
assert_contains "65-character Card-id: the length rule fires" "max 64" "$out"

# Usage and environment errors.
"$LINT" >/dev/null 2>&1
assert_eq "no arguments: exit 2" "2" "$?"
"$LINT" "$tmp/does-not-exist.md" >/dev/null 2>&1
assert_eq "missing file: exit 2" "2" "$?"

# A file name is never reinterpreted: `-` is a file, not stdin, and the stem
# reaches the Card-id check byte for byte (no awk escape processing).
d="$tmp/names"
write_golden_card "$d"
cp "$d/fixture-discipline.md" "$d/-"
out="$(cd "$d" && "$LINT" fixture-discipline.md - </dev/null 2>&1)"
assert_eq "a file named -: linted as a file (findings, not a refusal)" "1" "$?"
assert_contains "a file named -: its Card-id is checked against its stem" "[HDR-ID]" "$out"
cp "$d/fixture-discipline.md" "$d/fixture\\055discipline.md"
out="$("$LINT" "$d/fixture\\055discipline.md" 2>&1)"
assert_contains "a backslash in the file name is not an escape" "[HDR-ID]" "$out"

# Several files: every file is linted, and the exit is the worst outcome.
d="$tmp/multi"
write_golden_card "$d/refused"
awk '!/^\*\*Card-format:\*\*/' "$d/refused/fixture-discipline.md" >"$d/m" \
  && mv "$d/m" "$d/refused/fixture-discipline.md"
write_golden_card "$d/findings"
awk '{ sub(/^\*\*Card-id:\*\* .*/, "**Card-id:** other-discipline"); print }' \
  "$d/findings/fixture-discipline.md" >"$d/m" && mv "$d/m" "$d/findings/fixture-discipline.md"
out="$("$LINT" "$tmp/golden/fixture-discipline.md" "$d/refused/fixture-discipline.md" \
  "$d/findings/fixture-discipline.md" 2>&1)"
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
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" Product-Strategy >/dev/null 2>&1
assert_eq "uppercase id: exit 2" "2" "$?"
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" "$long_id" >/dev/null 2>&1
assert_eq "65-character id: exit 2" "2" "$?"
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" >/dev/null 2>&1
assert_eq "resolver, no argument: exit 2" "2" "$?"
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" a b >/dev/null 2>&1
assert_eq "resolver, two arguments: exit 2" "2" "$?"
base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" -x >/dev/null 2>&1
assert_eq "resolver, unknown flag: exit 2" "2" "$?"
out="$(base "$core_env" PLANWRIGHT_REPO_ROOT=none /bin/bash "$RESOLVE" no-such-card 2>&1)"
assert_eq "unknown id: exit 1" "1" "$?"
assert_contains "unknown id: says so" "not in the merged discipline-cards catalog" "$out"

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

# No fallback: an overlay that supersedes a core entry but ships no card file
# fails the lookup rather than handing back the core card.
nf="$tmp/no-fallback"
mkdir -p "$nf/catalogs"
cat >"$nf/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: product-strategy
    discipline: "Product strategy (company edition)"
    supersede: true
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$nf" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" product-strategy 2>/dev/null)"
assert_eq "supersede with no card file: exit 1" "1" "$?"
assert_eq "supersede with no card file: no fallback to the core card" "" "$out"

esc="$tmp/escape"
mkdir -p "$esc/catalogs" "$esc/cards" "$tmp/outside"
write_golden_card "$tmp/outside" escapee
ln -s "$tmp/outside/escapee.md" "$esc/cards/escapee.md"
cat >"$esc/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: escapee
    discipline: "Escapee"
YAML
err="$tmp/escape.err"
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$esc" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" escapee 2>"$err")"
assert_eq "symlink escaping the layer root: exit 1" "1" "$?"
assert_eq "symlink escaping the layer root: no path printed" "" "$out"
assert_contains "symlink escaping the layer root: says so" "does not resolve inside its layer root" "$(cat "$err")"
assert_not_contains "symlink escaping the layer root: the helper's own text stays silent" \
  "$tmp/outside" "$(cat "$err")"

# A contained card whose canonical path carries a control byte (here through a
# symlink target's name) is refused, never printed to the terminal.
ctl="$tmp/control"
mkdir -p "$ctl/catalogs" "$ctl/cards"
esc_byte=$(printf '\033')
write_golden_card "$ctl/cards" ctl-card
mv "$ctl/cards/ctl-card.md" "$ctl/cards/real${esc_byte}name.md"
ln -s "real${esc_byte}name.md" "$ctl/cards/ctl-card.md"
cat >"$ctl/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: ctl-card
    discipline: "Control"
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$ctl" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" ctl-card 2>/dev/null)"
assert_eq "control byte in the canonical path: exit 1" "1" "$?"
assert_eq "control byte in the canonical path: nothing printed" "" "$out"

# A single-id lookup's exit answers for the requested id only: an unrelated
# malformed entry never fails it, while --list still reports it.
mixed="$tmp/mixed"
mkdir -p "$mixed/catalogs"
write_golden_card "$mixed/cards" good-card
cat >"$mixed/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: Bad_Id
    discipline: "Bad"
  - id: good-card
    discipline: "Good"
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$mixed" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" good-card 2>/dev/null)"
assert_eq "unrelated malformed entry: the requested id still resolves (exit 0)" "0" "$?"
assert_eq "unrelated malformed entry: the requested id's path" \
  "$mixed/cards/good-card.md" "$out"
base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$mixed" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" --list >/dev/null 2>&1
assert_eq "unrelated malformed entry: --list still reports it (exit 1)" "1" "$?"

# An id carrying a tab splits into an extra field in the merged listing; that
# entry is malformed and never matches, so the real id prints exactly once.
tabbed="$tmp/tabbed"
mkdir -p "$tabbed/catalogs"
write_golden_card "$tabbed/cards" good-card
tab_byte=$(printf '\t')
cat >"$tabbed/catalogs/discipline-cards.yaml" <<YAML
cards:
  - id: "good-card${tab_byte}core"
    discipline: "Tabbed"
  - id: good-card
    discipline: "Good"
YAML
out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$tabbed" PLANWRIGHT_REPO_ROOT=none \
  /bin/bash "$RESOLVE" good-card 2>/dev/null)"
assert_eq "tab in an id: the real id resolves (exit 0)" "0" "$?"
assert_eq "tab in an id: the real id prints exactly once" \
  "$tabbed/cards/good-card.md" "$out"

# An unreadable card file is refused, not returned.
unr="$tmp/unreadable"
mkdir -p "$unr/catalogs"
write_golden_card "$unr/cards" locked-card
chmod 000 "$unr/cards/locked-card.md"
cat >"$unr/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: locked-card
    discipline: "Locked"
YAML
if [ -r "$unr/cards/locked-card.md" ]; then
  echo "ok: unreadable card skipped (running with read-anything privileges)"
else
  err="$tmp/unreadable.err"
  out="$(base "$core_env" PLANWRIGHT_ADOPTER_OVERLAY="$unr" PLANWRIGHT_REPO_ROOT=none \
    /bin/bash "$RESOLVE" locked-card 2>"$err")"
  assert_eq "unreadable card file: exit 1" "1" "$?"
  assert_eq "unreadable card file: nothing printed" "" "$out"
  assert_contains "unreadable card file: says so" "unreadable" "$(cat "$err")"
fi
chmod 644 "$unr/cards/locked-card.md"

# The repo-tracked and machine-local layers each supply their own card from
# their own card home.
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
mkdir -p "$repo/.claude/catalogs" "$repo/.claude/catalogs.local"
write_golden_card "$repo/.claude/cards" team-discipline
write_golden_card "$repo/.claude/cards.local" local-discipline
cat >"$repo/.claude/catalogs/discipline-cards.yaml" <<'YAML'
cards:
  - id: team-discipline
    discipline: "Team discipline"
YAML
cat >"$repo/.claude/catalogs.local/discipline-cards.yaml" <<'YAML'
cards:
  - id: local-discipline
    discipline: "Local discipline"
YAML
repo_c="$(cd "$repo" && pwd -P)"
out="$(base "$core_env" PLANWRIGHT_REPO_ROOT="$repo" /bin/bash "$RESOLVE" team-discipline 2>&1)"
assert_eq "repo-tracked: the team card resolves to .claude/cards" \
  "$repo_c/.claude/cards/team-discipline.md" "$out"
out="$(base "$core_env" PLANWRIGHT_REPO_ROOT="$repo" /bin/bash "$RESOLVE" local-discipline 2>&1)"
assert_eq "machine-local: the local card resolves to .claude/cards.local" \
  "$repo_c/.claude/cards.local/local-discipline.md" "$out"

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
