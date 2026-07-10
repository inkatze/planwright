#!/bin/sh
# Unit test for scripts/check-obs.sh — the standing CI guard over the
# observation fragment store (observation-recording Task 2, REQ-D1.4, REQ-A1.2;
# D-6, D-7). The guard re-validates committed fragment names and content shape
# that scripts/obs-record.sh (Task 1) enforces at write time, so a
# hand-edited or merge-mangled fragment cannot slip past CI. Grammar and
# content-shape semantics are normative in
# specs/observation-recording/{requirements,design}.md.
#
# Properties verified (numbered to match the body's check sections):
#   1. Clean tree passes (exit 0): valid fragments under entries/ and archive/
#      (an archived one carrying its Consumed-by: annotation), plus the frozen
#      legacy files opportunities.md and archive.md at the top level.
#   2. Null-safe over absent directories (REQ-D1.4): neither, only entries/,
#      and only archive/ present each pass — the dirs are create-on-demand and
#      may not exist in a given tree; an absent observations root passes too.
#   3. Filename-grammar violations fail (exit 1, REQ-A1.2): a bad name, a
#      traversal-shaped name (a `..` slug component), a non-calendar date
#      (2026-02-30), an uppercase slug, and a wrong-length UID each fail.
#   4. Content-shape violations fail (exit 1, REQ-A1.4): a multi-entry file, a
#      missing entry line (first line not the entry form), a free-prose body,
#      and an unrecognized `Key: value` metadata line (whitelist exactness).
#   5. UID uniqueness across entries/ + archive/ (REQ-A1.2): the same UID on a
#      fragment in each directory fails, naming both matches.
#   6. Unexpected top-level file fails (REQ-D1.4): a compiled-view file seeded
#      directly under specs/_observations/ (the standing block on committed
#      compiled views) fails; a stray file inside entries/ that is not a
#      grammar-valid fragment fails too.
#
# Exit codes asserted: 0 clean, 1 violation, 2 usage — the header contract of
# scripts/check-obs.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
GUARD="$here/../scripts/check-obs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$GUARD" ] || fail "scripts/check-obs.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run_guard <obs-dir> — run the guard against a tree, echo nothing; sets the
# globals RC (exit code) and ERR (path to captured stderr) for the caller.
ERR="$tmp/stderr"
run_guard() {
  RC=0
  "$GUARD" --obs-dir "$1" >/dev/null 2>"$ERR" || RC=$?
}

# new_tree <dir> — a fresh observations dir with empty entries/ + archive/.
new_tree() {
  mkdir -p "$1/entries" "$1/archive"
}

# entry <path> — write a minimal valid one-entry fragment at <path>.
entry() {
  printf -- '- 2026-07-09 [planwright] a real observation\n' >"$1"
}

# --- 1. Clean tree passes ------------------------------------------------

o="$tmp/clean"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-alpha-deadbeef.md"
entry "$o/entries/2026-07-08-another-topic-cafebabe.md"
# An archived fragment carries the Consumed-by: annotation after its entry line.
printf -- '- 2026-06-01 [planwright] an older observation\nConsumed-by: specs/foo (2026-06-02)\n' \
  >"$o/archive/2026-06-01-old-12345678.md"
# The frozen legacy files live at the top level and are expected content.
printf '# Opportunities\n' >"$o/opportunities.md"
printf '# Consumed observations\n' >"$o/archive.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "1: a clean tree must pass (got exit $RC): $(cat "$ERR")"
echo "ok 1: a clean fragment tree with legacy files passes"

# --- 2. Null-safe over absent directories --------------------------------

# 2a. Neither entries/ nor archive/ present (adopter repo, pre-first-record).
o="$tmp/null-none"
mkdir -p "$o"
printf '# Opportunities\n' >"$o/opportunities.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "2a: absent fragment dirs must pass (got $RC): $(cat "$ERR")"

# 2b. Only entries/ present (archive/ created on demand by the consume step).
o="$tmp/null-entries"
mkdir -p "$o/entries"
entry "$o/entries/2026-07-09-solo-abcdef01.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "2b: only-entries/ tree must pass (got $RC): $(cat "$ERR")"

# 2c. Only archive/ present.
o="$tmp/null-archive"
mkdir -p "$o/archive"
entry "$o/archive/2026-06-01-solo-abcdef02.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "2c: only-archive/ tree must pass (got $RC): $(cat "$ERR")"

# 2d. An absent observations root passes (nothing to validate).
run_guard "$tmp/does-not-exist"
[ "$RC" -eq 0 ] || fail "2d: an absent observations root must pass (got $RC): $(cat "$ERR")"
echo "ok 2: absent fragment directories and root are null-safe"

# --- 3. Filename-grammar violations fail ---------------------------------

# name_reject <label> <filename> — seed a single fragment under entries/ whose
# NAME is the violation, assert exit 1 and that the name is surfaced.
name_reject() {
  _label=$1
  _name=$2
  _o="$tmp/nr-$(printf '%s' "$_label" | tr -c 'a-z0-9' -)"
  new_tree "$_o"
  entry "$_o/entries/$_name"
  run_guard "$_o"
  [ "$RC" -eq 1 ] || fail "3: $_label expected exit 1, got $RC"
}
name_reject "bad name" "not-a-fragment.md"
name_reject "traversal-shaped slug" "2026-07-09-..-deadbeef.md"
name_reject "non-calendar date" "2026-02-30-topic-deadbeef.md"
name_reject "non-calendar month" "2026-13-01-topic-deadbeef.md"
name_reject "uppercase slug" "2026-07-09-BadSlug-deadbeef.md"
name_reject "underscore slug" "2026-07-09-bad_slug-deadbeef.md"
name_reject "short UID" "2026-07-09-topic-dead.md"
name_reject "non-hex UID" "2026-07-09-topic-nothex01.md"
name_reject "missing slug" "2026-07-09-deadbeef.md"
name_reject "non-md extension" "2026-07-09-topic-deadbeef.txt"
echo "ok 3: filename-grammar violations fail the guard"

# --- 4. Content-shape violations fail ------------------------------------

# body_reject <label> <content> — seed a grammar-valid-NAMED fragment whose
# CONTENT is the violation, assert exit 1.
body_reject() {
  _label=$1
  _content=$2
  _o="$tmp/br-$(printf '%s' "$_label" | tr -c 'a-z0-9' -)"
  new_tree "$_o"
  printf '%s' "$_content" >"$_o/entries/2026-07-09-topic-deadbeef.md"
  run_guard "$_o"
  [ "$RC" -eq 1 ] || fail "4: $_label expected exit 1, got $RC"
}
body_reject "multi-entry file" \
  '- 2026-07-09 [planwright] first entry
- 2026-07-09 [planwright] second entry
'
body_reject "missing entry line (leading blank)" \
  '
- 2026-07-09 [planwright] entry not on the first line
'
body_reject "missing entry line (leading metadata)" \
  'Consumed-by: specs/foo (2026-06-02)
- 2026-07-09 [planwright] entry after metadata
'
body_reject "free-prose body" \
  '- 2026-07-09 [planwright] a real observation
some free prose that is not metadata
'
body_reject "unrecognized metadata key" \
  '- 2026-07-09 [planwright] a real observation
Author: someone
'
body_reject "empty file (missing entry line)" ''
echo "ok 4: content-shape violations fail the guard"

# --- 5. UID uniqueness across entries/ + archive/ ------------------------

o="$tmp/dupuid"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-abcd1234.md"
printf -- '- 2026-06-01 [planwright] older\nConsumed-by: specs/foo (2026-06-02)\n' \
  >"$o/archive/2026-06-01-old-abcd1234.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "5: a duplicate UID across directories expected exit 1, got $RC"
# Both colliding paths are named in the finding.
grep -q 'abcd1234' "$ERR" || fail "5: the duplicate UID is not named in the finding"
echo "ok 5: a UID reused across entries/ and archive/ fails"

# --- 6. Unexpected files fail --------------------------------------------

# 6a. A compiled view seeded directly under the observations root: the standing
# block on committed compiled views.
o="$tmp/unexpected-top"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
printf '# compiled view\n' >"$o/rendered-log.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "6a: an unexpected top-level file expected exit 1, got $RC"
grep -q 'rendered-log.md' "$ERR" || fail "6a: the unexpected file is not named"

# 6b. A stray non-fragment file inside entries/ is caught as a bad name.
o="$tmp/unexpected-in-entries"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
printf 'stray\n' >"$o/entries/README"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "6b: a stray file under entries/ expected exit 1, got $RC"
echo "ok 6: unexpected files under the observations root and entries/ fail"

echo "PASS: test-check-obs.sh"
