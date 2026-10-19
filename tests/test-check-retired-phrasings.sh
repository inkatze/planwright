#!/bin/bash
# Tests for scripts/check-retired-phrasings.sh, the sentence-length screen for
# rule phrasings doctrine/human-gates.md retired (human-gates REQ-H1.2,
# REQ-D1.6, REQ-A1.3).
#
# Properties: a fixture tree with no retired phrasing passes; a retired
# sentence reintroduced under docs/, skills/, or doctrine/ fails, including one
# wrapped across lines, set in emphasis or a blockquote, or spelled with a
# typographic apostrophe or an ASCII arrow; the same sentence under specs/, the changelog, or the
# observations log is ignored; doctrine/human-gates.md and gate-wiring's one
# legacy-marker mapping line are exempt, the marker anywhere else is not;
# every pattern fires on its own known-bad sentence; a scan over nothing, with
# no pattern file, or through a symlink fails closed; the real tree
# passes; and the screen is wired into the check aggregate.
# shellcheck disable=SC2016 # fixture text quotes Markdown code spans
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

r="$TMP/indented"
mkfixture "$r"
printf '\n- planwright never\n  auto-merges, at any tier.\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "a phrasing wrapped onto an indented list continuation fails" 1 $?
if grep -q '^docs/guide.md:6:' "$TMP/out"; then
  ok "the hit is reported on the line the phrasing ends on"
else
  fail "the hit is not reported on its closing line: $(cat "$TMP/out")"
fi

for variant in 'planwright **never** auto-merges.' '> planwright never
> auto-merges.' "planwright never$(printf '\302\240')auto-merges." \
  "the draft-to-ready flip is the human$(printf '\342\200\231')s." \
  'the draft->ready flip is yours.' 'the draft to ready flip is yours.' \
  'planwright never&nbsp;auto-merges.' 'planwright never auto\-merges.' \
  'planwright <em>never</em> auto-merges.' \
  '<!-- planwright never auto-merges -->' 'A <placeholder: never auto-merge> here.' \
  "planwright never$(printf '\342\200\257')auto-merges." 'the draft&rarr;ready flip is yours.'; do
  r="$TMP/variant"
  rm -rf "$r"
  mkfixture "$r"
  printf '\n%s\n' "$variant" >>"$r/docs/guide.md"
  run "$r"
  rc=$?
  assert_exit "a variant spelling fails: $(printf '%s' "$variant" | tr '\n' ' ')" 1 "$rc"
done

r="$TMP/crlf"
mkfixture "$r"
printf '\r\nplanwright never  \r\nauto-merges.\r\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "a CRLF file with a trailing-space break still fails" 1 $?

# One known-bad sentence per pattern line, in the pattern file's order; each
# pattern must fire on its own sentence's line, so a typo that kills a pattern
# fails here even when another pattern also matches.
r="$TMP/each"
mkfixture "$r"
npat=0
while IFS= read -r sentence; do
  npat=$((npat + 1))
  printf '\n%s\n' "$sentence" >>"$r/docs/guide.md"
done <<'EOF'
the flip is the review gate.
it is the universal gate.
we never auto-merge.
there is no auto-merge.
workers never force-push.
new commits only.
history is never rewritten.
the two reserved controls hold.
merge is a reserved human action.
autonomous PR-ready marking is reserved.
the all-drafts rule holds.
task PRs stay drafts.
all framework-created PRs are drafts.
two actions are human-reserved, permanently.
a subject ending in [pending-sign-off] is legacy.
see bootstrap REQ-J1.4.
the draft→ready flip is the human's.
the flip and the merge are yours.
every PR the framework opens is a draft.
EOF
pats=$(grep -c -v -e '^#' -e '^[[:space:]]*$' "$REPO_ROOT/config/retired-phrasings.txt")
if [ "$npat" -eq "$pats" ]; then
  ok "one known-bad sentence per pattern"
else
  fail "$pats patterns but $npat known-bad sentences; add one per new pattern"
fi
run "$r"
k=0
while IFS= read -r p; do
  case "$p" in '#'* | '') continue ;; esac
  k=$((k + 1))
  if grep -qF -- ":$((3 + 2 * k)): retired phrasing /$p/" "$TMP/out"; then
    ok "pattern $k fires on its known-bad sentence"
  else
    fail "pattern $k (/$p/) does not fire on its known-bad sentence"
  fi
done <"$REPO_ROOT/config/retired-phrasings.txt"

r="$TMP/actthen"
mkfixture "$r"
printf '\nThe act-then-review gate routes findings.\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "the act-then-review gate is not the retired review gate" 0 $?

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

r="$TMP/twomaps"
mkfixture "$r"
printf '# Gate Wiring\n\nA legacy `[pending-sign-off]` subject suffix counts as a `Planwright-Sign-Off: PS-legacy-<sha7>` trailer.\n\nA legacy `[pending-sign-off]` suffix again maps to `Planwright-Sign-Off: PS-legacy-<sha7>`.\n' \
  >"$r/doctrine/gate-wiring.md"
run "$r"
assert_exit "a second mapping paragraph in gate-wiring fails" 1 $?

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

r="$TMP/symlink"
mkfixture "$r"
mv "$r/docs" "$r/real-docs"
ln -s real-docs "$r/docs"
run "$r"
assert_exit "a symlinked surface directory fails closed" 2 $?

r="$TMP/c1"
mkfixture "$r"
printf '\nwe never auto-merge.\n' >>"$r/docs/guide.md"
mv "$r/docs/guide.md" "$r/docs/x$(printf '\302\233\033')y.md"
run "$r"
if grep -q "$(printf '\302\233')" "$TMP/out" || grep -q "$(printf '\033')" "$TMP/out"; then
  fail "a control byte in a path reaches the report"
else
  ok "C0 and C1 control bytes in a path are stripped from the report"
fi

r="$TMP/huge"
mkfixture "$r"
yes 'ordinary prose that never states a retired rule at all' | head -n 5000 >>"$r/docs/guide.md"
run "$r"
assert_exit "a paragraph over the size cap fails closed" 2 $?

r="$TMP/longhit"
mkfixture "$r"
{
  printf '\n'
  yes a | head -n 60000
  printf 'the review gate.\n'
} >>"$r/docs/guide.md"
SECONDS=0
run "$r"
rc=$?
assert_exit "a hit at the end of a long paragraph is reported" 1 "$rc"
if [ "$SECONDS" -le 20 ]; then
  ok "a hit in a long paragraph is located without a quadratic rebuild"
else
  fail "locating a hit in a long paragraph took ${SECONDS}s"
fi
grep -q '^docs/guide.md:60005:' "$TMP/out" || fail "the long-paragraph hit is not reported on its own line: $(head -n 3 "$TMP/out")"

r="$TMP/filelink"
mkfixture "$r"
printf 'we never auto-merge.\n' >"$r/specs/demo/hidden.md"
ln -s ../../specs/demo/hidden.md "$r/skills/demo/LINKED.md"
run "$r"
assert_exit "a symlinked file under a surface fails closed" 2 $?

r="$TMP/readmelink"
mkfixture "$r"
mv "$r/README.md" "$r/real.md"
ln -s real.md "$r/README.md"
run "$r"
assert_exit "a symlinked README fails closed" 2 $?

r="$TMP/onlyexempt"
mkdir -p "$r/config" "$r/doctrine"
cp "$REPO_ROOT/config/retired-phrasings.txt" "$r/config/"
printf 'x\n' >"$r/doctrine/human-gates.md"
run "$r"
assert_exit "a tree holding only the exempt doc fails closed" 2 $?

r="$TMP/crlfpat"
mkfixture "$r"
sed 's/$/\r/' "$REPO_ROOT/config/retired-phrasings.txt" >"$r/config/retired-phrasings.txt"
printf '\nplanwright never auto-merges.\n' >>"$r/docs/guide.md"
run "$r"
assert_exit "a CRLF pattern file still matches" 1 $?

r="$TMP/upperpat"
mkfixture "$r"
printf 'Foo Bar\n' >"$r/config/retired-phrasings.txt"
run "$r"
assert_exit "an uppercase pattern fails closed" 2 $?

if [ "$(id -u)" -ne 0 ]; then
  r="$TMP/unreadable"
  mkfixture "$r"
  printf 'planwright never auto-merges.\n' >"$r/docs/locked.md"
  chmod 000 "$r/docs/locked.md"
  run "$r"
  assert_exit "an unreadable file fails closed" 2 $?
  chmod 644 "$r/docs/locked.md"
fi

"$SCREEN" >"$TMP/out" 2>&1
real=$?
assert_exit "the real tree carries no retired phrasing" 0 "$real"
[ "$real" -eq 0 ] || cat "$TMP/out" >&2

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
