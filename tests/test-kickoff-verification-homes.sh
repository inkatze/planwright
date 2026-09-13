#!/bin/sh
# Verification homes for the thin /spec-kickoff behaviors that the founding
# bundle under-covered (format-grammar Task 7; REQ-F1.2, REQ-F1.3; D-17).
#
# Properties verified (numbered to match the body's sections):
#   1. Captured, not authored (REQ-F1.2): the fixture under
#      tests/fixtures/kickoff-entries/ is byte-identical to the entry as the
#      landing commit wrote it into the real bundle's kickoff brief. A
#      hand-edited fixture fails here before any parsing claim is made.
#   2. Execution-validity marks (REQ-F1.2; spec-format's execution-validity
#      rule for expression-only entries): the entry is explicitly marked
#      `Class: expression-only`, cites a dated `## Changelog` entry that exists
#      in the bundle's requirements at that commit, and ends on its anchor
#      record: the `Anchor:` line and its command (anchor-written-last).
#   3. The freshness-gate parser accepts it (REQ-F1.2): over the bundle as it
#      stood at the landing commit, scripts/check-anchor-freshness.sh reads the
#      captured entry as the most recent one, accepts its command form, and
#      reports its hash as a clean recompute.
#   4. Discriminating, not vacuous (REQ-F1.2): the same bundle with the
#      entry's hash rewritten is a stale-anchor error naming that hash, and
#      with a non-sanctioned command form is refused — so section 3's `ok`
#      came from this entry's parse.
#   5. Catalog-absent degradation, script half (REQ-F1.3): the gap check's
#      catalog read, `scripts/resolve-catalog.sh decision-domains`, with no
#      catalog resolvable in any layer exits 0 with empty stdout and no stderr
#      noise; the contrast arm with the shipped seed present resolves non-empty.
#
# Needs the repository's history reachable (CI checks out with full depth):
# the landing commit is the provenance the fixture is checked against.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

# An inherited repository override (a `git bisect run` or `rebase --exec`
# parent exports one) would redirect every `git -C "$repo"` read below.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
GUARD="$repo/scripts/check-anchor-freshness.sh"
RESOLVER="$repo/scripts/resolve-catalog.sh"
FIXTURE="$repo/tests/fixtures/kickoff-entries/invariant-tasks-amendment-6.md"

# The captured entry's provenance: the commit that landed format-grammar
# Task 4's expression-only self-re-anchor into the invariant-tasks brief, and
# the heading that opens the entry there.
LANDING=ff1f67b86cb363fa724de922c34473a83fbf3eb4
BUNDLE=invariant-tasks
HEADING='### Amendment 6 '

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$GUARD" ] || fail "scripts/check-anchor-freshness.sh missing or not executable"
[ -x "$RESOLVER" ] || fail "scripts/resolve-catalog.sh missing or not executable"
[ -f "$FIXTURE" ] && [ -r "$FIXTURE" ] || fail "fixture missing or unreadable at $FIXTURE"

# The explicit template is not decoration: BSD mktemp supplies no default
# one, so a bare `mktemp -d` is a usage error on macOS.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-kickoff-verification-homes.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# Every overlay-affecting variable stripped, so a catalog on the host cannot
# leak into an arm that claims one is absent; the startup files bash and sh
# read when non-interactive too, since anything they print fails the arm
# that expects a silent stderr.
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME -u BASH_ENV -u ENV "$@"
}

git -C "$repo" cat-file -e "$LANDING^{commit}" 2>/dev/null \
  || fail "landing commit $LANDING is not reachable (a shallow clone, or git itself unavailable); the fixture's provenance cannot be checked"

# The bundle exactly as the landing commit left it, read once: every section
# works from these files, so a failed read fails here by name instead of
# surfacing downstream as a content claim about the fixture.
landed="$tmp/landed"
mkdir -p "$landed"
for f in requirements design tasks test-spec kickoff-brief; do
  git -C "$repo" show "$LANDING:specs/$BUNDLE/$f.md" >"$landed/$f.md" \
    || fail "could not read specs/$BUNDLE/$f.md at $LANDING"
done

OUT=
RC=0
# The fixture tree carries no scripts/ of its own, so the guard resolves its
# anchor tool through the root chain; pinning the chain's head at this
# checkout keeps a planwright installed elsewhere on the host from supplying
# the recompute.
run_guard() {
  RC=0
  OUT=$(PLANWRIGHT_ROOT="$repo" "$GUARD" "$@" 2>&1) || RC=$?
}

assert_rc() {
  [ "$RC" = "$2" ] || fail "$1: expected exit $2, got $RC. Output:
$OUT"
}

assert_has() {
  case $OUT in
    *"$2"*) ;;
    *) fail "$1: expected output to contain '$2'. Output:
$OUT" ;;
  esac
}

########################################################################
# 1. Captured, not authored
########################################################################
# The entry runs from its heading to the next heading at its level or above
# (a deeper heading inside the entry is content), or the end of the brief,
# so a re-capture of a non-terminal entry cannot pull in the entries or the
# section after it. A second heading opening the same way ends it too.
awk -v h="$HEADING" '
  index($0, h) == 1 { if (p) exit; p = 1; print; next }
  p && /^#(#|##)? / { exit }
  p
' "$landed/kickoff-brief.md" >"$tmp/captured.md"
[ -s "$tmp/captured.md" ] || fail "the landing commit's brief carries no entry opening with '$HEADING'"
cmp -s "$tmp/captured.md" "$FIXTURE" \
  || fail "fixture diverges from the entry at $LANDING; re-capture it rather than editing it"
echo "ok: fixture is byte-identical to the entry at $LANDING"

########################################################################
# 2. Execution-validity marks
########################################################################
grep -q '^Class: expression-only$' "$FIXTURE" \
  || fail "entry is not marked 'Class: expression-only'"
echo "ok: entry carries the expression-only mark"

# The first date on the citation line is the cited one; a later date on the
# same line (a PR's, say) is not.
cited=$(grep 'Cites the changelog line' "$FIXTURE" \
  | sed -n 's/^[^0-9]*\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' | head -n 1)
[ -n "$cited" ] || fail "entry cites no dated changelog line"
# Scoped to the `## Changelog` section, as the guard's pairing check scopes
# its own scan: a dated bullet elsewhere in the file is not a citation
# target. Only requirements.md is read, the changelog's home per the
# meta-spec.
awk -v d="- $cited" '
  /^## / { in_ch = ($0 ~ /^## Changelog[ \t]*$/); next }
  in_ch && index($0, d) == 1 { found = 1 }
  END { exit !found }
' "$landed/requirements.md" || fail "cited changelog date $cited has no dated bullet under ## Changelog at $LANDING"
echo "ok: entry cites a changelog entry that exists ($cited)"

# Anchor-written-last: the final two non-blank lines are the `Anchor:` line
# and its backticked command.
tail_pair=$(grep -v '^[[:space:]]*$' "$FIXTURE" | tail -n 2)
case $tail_pair in
  "Anchor: "*"
"'`'*'`') ;;
  *) fail "entry does not end on its anchor record. Tail:
$tail_pair" ;;
esac
echo "ok: entry ends on its anchor record"

# One entry carries one anchor record; the guard reads a brief's most recent
# entry, so a fixture holding two would have the sections below disagree on
# which hash they mean.
anchors=$(grep -c '^Anchor:' "$FIXTURE")
[ "$anchors" -eq 1 ] || fail "fixture carries $anchors Anchor: lines; a captured entry carries exactly one"
# SC2016: the backticks are Markdown, not command substitution.
# shellcheck disable=SC2016
hash=$(grep '^Anchor:' "$FIXTURE" | sed -n 's/.*`\([0-9a-f]\{40\}\)`.*/\1/p')
[ -n "$hash" ] || fail "entry's Anchor line carries no 40-hex hash"

########################################################################
# 3. The freshness-gate parser accepts it
########################################################################
# The bundle exactly as the landing commit left it: the captured entry is the
# brief's most recent, and the content it anchored is what the guard
# recomputes over.
f3="$tmp/f3/specs"
mkdir -p "$f3/$BUNDLE"
cp "$landed"/*.md "$f3/$BUNDLE/"
run_guard "$f3"
assert_rc "captured entry recomputes clean over its landed content" 0
assert_has "the ok record names the entry's hash" "ok     $BUNDLE — anchor $hash"
assert_has "the summary counts exactly one ok and no errors" "check-anchor-freshness: 1 ok, 0 notice(s), 0 error(s)"
echo "ok: the freshness guard recomputes the captured entry clean"

########################################################################
# 4. Discriminating, not vacuous
########################################################################
stale=0000000000000000000000000000000000000000
f4="$tmp/f4/specs"
mkdir -p "$f4/$BUNDLE"
cp "$f3/$BUNDLE"/*.md "$f4/$BUNDLE/"
sed "/^Anchor:/s/$hash/$stale/" "$f3/$BUNDLE/kickoff-brief.md" >"$f4/$BUNDLE/kickoff-brief.md"
grep -q "$stale" "$f4/$BUNDLE/kickoff-brief.md" || fail "the hash rewrite did not apply"
run_guard "$f4"
assert_rc "a rewritten hash in the captured entry is a stale-anchor error" 1
assert_has "the stale record names the rewritten hash" "$stale"
assert_has "the stale record names the recomputed hash" "$hash"

f4b="$tmp/f4b/specs"
mkdir -p "$f4b/$BUNDLE"
cp "$f3/$BUNDLE"/*.md "$f4b/$BUNDLE/"
# The payload's last token is still a valid spec directory, so the guard's
# argument-grammar arm accepts it and only the recomposition of the whole
# command can refuse it: the check this control exists to exercise. A
# payload ending in a foreign token would be refused one arm earlier and
# prove nothing about recomposition.
# shellcheck disable=SC2016
sed 's|^`scripts/spec-anchor.sh specs/'"$BUNDLE"'`$|`scripts/spec-anchor.sh specs/'"$BUNDLE"' specs/'"$BUNDLE"'`|' \
  "$f3/$BUNDLE/kickoff-brief.md" >"$f4b/$BUNDLE/kickoff-brief.md"
grep -q "specs/$BUNDLE specs/$BUNDLE" "$f4b/$BUNDLE/kickoff-brief.md" || fail "the command-form rewrite did not apply"
run_guard "$f4b"
assert_rc "a non-sanctioned command form on the captured entry is refused" 1
assert_has "the refusal names the non-sanctioned form" "non-sanctioned command form"
echo "ok: a rewritten hash and a non-sanctioned form are both refused"

########################################################################
# 5. Catalog-absent degradation, script half
########################################################################
# Each layer root pointed at an empty directory: no decision-domains catalog
# is resolvable anywhere.
absent="$tmp/absent"
mkdir -p "$absent/core" "$absent/adopter" "$absent/repo"
resolver_rc=0
base PLANWRIGHT_ROOT="$absent/core" PLANWRIGHT_ADOPTER_OVERLAY="$absent/adopter" \
  PLANWRIGHT_REPO_ROOT="$absent/repo" \
  /bin/bash "$RESOLVER" decision-domains >"$absent/out" 2>"$absent/err" || resolver_rc=$?
[ "$resolver_rc" -eq 0 ] || fail "absent decision-domains catalog: expected exit 0, got $resolver_rc. stderr:
$(cat "$absent/err")"
[ ! -s "$absent/out" ] || fail "absent decision-domains catalog: expected empty stdout, got:
$(cat "$absent/out")"
[ ! -s "$absent/err" ] || fail "absent decision-domains catalog: expected no stderr noise, got:
$(cat "$absent/err")"
echo "ok: absent decision-domains catalog resolves to a clean empty result"

# Contrast: with the shipped seed present the same read is non-empty, so the
# empty result above is the absent verdict, not a resolver that prints nothing.
present="$tmp/present"
mkdir -p "$present/repo"
resolver_rc=0
base PLANWRIGHT_ROOT="$repo" PLANWRIGHT_REPO_ROOT="$present/repo" \
  /bin/bash "$RESOLVER" decision-domains >"$present/out" 2>"$present/err" || resolver_rc=$?
[ "$resolver_rc" -eq 0 ] || fail "present decision-domains catalog: expected exit 0, got $resolver_rc. stderr:
$(cat "$present/err")"
grep -q '^  - id: ' "$present/out" \
  || fail "present decision-domains catalog: expected at least one entry on stdout, got:
$(cat "$present/out")"
echo "ok: the shipped decision-domains seed resolves non-empty"

echo "All kickoff-verification-homes tests passed."
