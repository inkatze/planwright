#!/bin/bash
# Tests for scripts/check-retired-phrasings.sh, the sentence-length screen for
# rule phrasings doctrine/human-gates.md retired (human-gates REQ-H1.2,
# REQ-D1.6, REQ-A1.3).
#
# Properties: a fixture tree with no retired phrasing passes; a retired
# sentence reintroduced under docs/, skills/, or doctrine/ fails, including one
# wrapped across lines; the same sentence under specs/, the changelog, or the
# observations log is ignored; doctrine/human-gates.md and gate-wiring's one
# legacy-marker mapping line are exempt, the marker anywhere else is not; a
# scan over nothing, or with no pattern file, fails closed; the real tree
# passes; and the screen is wired into the check aggregate.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCREEN="$REPO_ROOT/scripts/check-retired-phrasings.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}

if [ ! -x "$SCREEN" ]; then
  echo "FAIL: $SCREEN missing or not executable" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkfixture() {
  local r=$1
  mkdir -p "$r/doctrine" "$r/skills/demo" "$r/docs" "$r/specs/demo" "$r/specs/_observations/entries" "$r/config"
  cp "$REPO_ROOT/config/retired-phrasings.txt" "$r/config/"
  printf '# Demo\n\nA plain doc with nothing retired in it.\n' >"$r/doctrine/demo.md"
  printf '# Skill\n\nMerge follows `merge_policy`.\n' >"$r/skills/demo/SKILL.md"
  printf '# Guide\n\nThe flip approves nothing.\n' >"$r/docs/guide.md"
  printf '# README\n\nNothing here.\n' >"$r/README.md"
}

run() { "$SCREEN" --root "$1" >"$TMP/out" 2>&1; }

r="$TMP/clean"
mkfixture "$r"
run "$r"
assert_exit "a tree with no retired phrasing passes" 0 $?

retired_sentence='Your draft→ready flip is the universal review gate, and merge is always yours.'

for where in docs/guide.md skills/demo/SKILL.md doctrine/demo.md README.md; do
  r="$TMP/hit-$(printf '%s' "$where" | tr '/.' '--')"
  mkfixture "$r"
  printf '\n%s\n' "$retired_sentence" >>"$r/$where"
  run "$r"
  assert_exit "a retired sentence in $where fails" 1 $?
  if grep -q "$where:" "$TMP/out"; then
    ok "the report names $where"
  else
    fail "the report does not name $where: $(cat "$TMP/out")"
  fi
done

r="$TMP/wrapped"
mkfixture "$r"
printf '\nplanwright never\nauto-merges, at any tier.\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "a retired phrasing wrapped across lines fails" 1 $?

r="$TMP/historical"
mkfixture "$r"
printf '%s\n' "$retired_sentence" >"$r/specs/demo/requirements.md"
printf '%s\n' "$retired_sentence" >"$r/specs/_observations/entries/x.md"
printf '# Changelog\n\n%s\n' "$retired_sentence" >"$r/CHANGELOG.md"
run "$r"
assert_exit "specs/, the changelog, and the observations log are not screened" 0 $?

r="$TMP/exempt"
mkfixture "$r"
printf '%s\n' "$retired_sentence" >"$r/doctrine/human-gates.md"
printf '# Gate Wiring\n\nA legacy `[pending-sign-off]` subject suffix counts as a `Planwright-Sign-Off: PS-legacy-<sha7>` trailer.\n' \
  >"$r/doctrine/gate-wiring.md"
run "$r"
assert_exit "human-gates.md and the gate-wiring mapping line are exempt" 0 $?

r="$TMP/marker"
mkfixture "$r"
printf '\nStamp the subject with `[pending-sign-off]`.\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "the legacy marker outside the mapping line fails" 1 $?

r="$TMP/marker-gw"
mkfixture "$r"
printf '# Gate Wiring\n\nStamp the subject with `[pending-sign-off]`.\n' >"$r/doctrine/gate-wiring.md"
run "$r"
assert_exit "the legacy marker in gate-wiring off the mapping line fails" 1 $?

r="$TMP/empty"
mkdir -p "$r/config"
cp "$REPO_ROOT/config/retired-phrasings.txt" "$r/config/"
run "$r"
assert_exit "a scan over no files fails closed" 2 $?

r="$TMP/nopat"
mkfixture "$r"
rm "$r/config/retired-phrasings.txt"
run "$r"
assert_exit "a missing pattern file fails closed" 2 $?

r="$TMP/blankpat"
mkfixture "$r"
printf '# only a comment\n\n' >"$r/config/retired-phrasings.txt"
run "$r"
assert_exit "a pattern file with no patterns fails closed" 2 $?

"$SCREEN" >"$TMP/out" 2>&1
assert_exit "the real tree carries no retired phrasing" 0 $?
[ "$failures" -eq 0 ] || cat "$TMP/out" >&2

if grep -q '^\[tasks."check:retired-phrasings"\]$' "$REPO_ROOT/mise.toml" \
  && grep -q '^  "check:retired-phrasings",$' "$REPO_ROOT/mise.toml"; then
  ok "check:retired-phrasings is defined and a member of the check aggregate"
else
  fail "check:retired-phrasings is not wired into the check aggregate in mise.toml"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all retired-phrasing screen checks passed"
