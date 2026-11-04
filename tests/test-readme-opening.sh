#!/bin/bash
# Pin-checks for the README's opening (its lead and "Why planwright"): the
# first screen a newcomer reads speaks plain language. It names none of the
# internal vocabulary the later sections and docs explain (the literal
# `/tower` command excepted, since the lead must name what to type), carries
# no em dash, and makes no multiplier claim. Each screen refuses a known-bad
# fixture first, so a screen that matches nothing cannot pass.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
if [ ! -f "$README" ]; then
  echo "FAIL: README missing at $README" >&2
  exit 1
fi

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# opening <file>: the title through the end of "## Why planwright", badge
# lines dropped.
opening() {
  awk '
    /^\[!\[/ { next }
    /^## / { if (index($0, "## Why planwright") == 1) { print; next } exit }
    { print }
  ' "$1"
}

# Link targets and the backticked command are not prose a reader decodes.
VOCAB='(^|[^[:alnum:]])(towers?|flights?|fleets?|mission control|harness(es)?|autopilot|spec-driven|agentic|software factory)([^[:alnum:]]|$)'
vocab_hits() {
  # shellcheck disable=SC2016 # the backticks are literal Markdown
  printf '%s\n' "$1" | sed -e 's/`\/tower`//g' -e 's/](\([^)]*\))/]()/g' | grep -n -i -E "$VOCAB"
}
EMDASH=$(printf '\342\200\224')
emdash_hits() { printf '%s\n' "$1" | grep -n -F "$EMDASH"; }
MULTIPLIER='(^|[^[:alnum:]])[0-9]+(\.[0-9]+)?x([^[:alnum:]]|$)'
multiplier_hits() { printf '%s\n' "$1" | grep -n -i -E "$MULTIPLIER"; }

bad_vocab=$(vocab_hits "Type \`/tower\` to start
the tower routes it
a visual flight lands it
run a fleet of workers
one mission control session
a guardrailed agent harness
autopilot for your repo
spec-driven development
an agentic workflow
a software factory" | grep -c '^[0-9]*:')
if [ "$bad_vocab" -eq 9 ]; then ok "the vocabulary screen fires on known-bad lines and spares \`/tower\`"; else fail "the vocabulary screen fired on $bad_vocab of 9 known-bad lines"; fi
if [ -z "$(vocab_hits "See [the guide](docs/mission-control.md) or type \`/tower\`.")" ]; then ok "the vocabulary screen spares link targets"; else fail "the vocabulary screen fired on a link target"; fi
if [ -n "$(emdash_hits "a pause ${EMDASH} then more")" ]; then ok "the em dash screen fires on an em dash"; else fail "the em dash screen missed an em dash"; fi
if [ -n "$(multiplier_hits "ship 10x faster")" ] && [ -z "$(multiplier_hits "a 0x1f flag, box size")" ]; then ok "the multiplier screen fires on a multiplier only"; else fail "the multiplier screen misjudged its fixtures"; fi

text=$(opening "$README")
case "$text" in
  *"## Why planwright"*) ok "the opening reaches the Why planwright section" ;;
  *) fail "the README has no '## Why planwright' section directly after its lead" ;;
esac

hits=$(vocab_hits "$text")
if [ -z "$hits" ]; then ok "the opening names no internal vocabulary"; else fail "the opening names internal vocabulary:
$hits"; fi
hits=$(emdash_hits "$text")
if [ -z "$hits" ]; then ok "the opening has no em dash"; else fail "the opening has an em dash:
$hits"; fi
hits=$(multiplier_hits "$text")
if [ -z "$hits" ]; then ok "the opening makes no multiplier claim"; else fail "the opening makes a multiplier claim:
$hits"; fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all README-opening pin checks passed"
