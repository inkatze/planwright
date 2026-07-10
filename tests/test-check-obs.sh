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
# Exit codes asserted: 0 clean, 1 violation, 2 usage or internal error — the
# header contract of scripts/check-obs.sh.
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
# NAME is the violation, assert exit 1 AND that the guard failed for the name
# reason (not some unrelated failure — a wrong-reason exit 1 must not pass).
name_reject() {
  _label=$1
  _name=$2
  _o="$tmp/nr-$(printf '%s' "$_label" | tr -c 'a-z0-9' -)"
  new_tree "$_o"
  entry "$_o/entries/$_name"
  run_guard "$_o"
  [ "$RC" -eq 1 ] || fail "3: $_label expected exit 1, got $RC"
  grep -q 'invalid fragment filename' "$ERR" \
    || fail "3: $_label did not fail for the filename-grammar reason: $(cat "$ERR")"
}
name_reject "bad name" "not-a-fragment.md"
name_reject "traversal-shaped slug" "2026-07-09-..-deadbeef.md"
name_reject "non-calendar date" "2026-02-30-topic-deadbeef.md"
name_reject "non-calendar month" "2026-13-01-topic-deadbeef.md"
# Leap-year discrimination (the %4/%100/%400 branch is otherwise unexercised):
# a non-leap and a century-non-leap Feb 29 must reject; the leap accepts are
# asserted in the clean-tree-ish accept check below.
name_reject "non-leap Feb 29 (2026)" "2026-02-29-topic-deadbeef.md"
name_reject "century non-leap Feb 29 (1900)" "1900-02-29-topic-deadbeef.md"
name_reject "uppercase slug" "2026-07-09-BadSlug-deadbeef.md"
name_reject "underscore slug" "2026-07-09-bad_slug-deadbeef.md"
name_reject "short UID" "2026-07-09-topic-dead.md"
name_reject "non-hex UID" "2026-07-09-topic-nothex01.md"
name_reject "missing slug" "2026-07-09-deadbeef.md"
name_reject "non-md extension" "2026-07-09-topic-deadbeef.txt"
# Slug-length boundary: 41 chars rejects (the `-le 40` guard).
slug41=$(printf 'a%.0s' $(seq 1 41))
name_reject "overlong slug (41)" "2026-07-09-$slug41-deadbeef.md"

# Accept side of the same rules (a fragment the guard must PASS): a 40-char slug
# and the two leap-year Feb-29 dates that ARE valid (/4-non-/100, and /400).
oacc="$tmp/name-accept"
new_tree "$oacc"
slug40=$(printf 'a%.0s' $(seq 1 40))
entry "$oacc/entries/2026-07-09-$slug40-deadbeef.md"
entry "$oacc/entries/2024-02-29-leap-cafebabe.md"
entry "$oacc/entries/2000-02-29-leap-cafed00d.md"
run_guard "$oacc"
[ "$RC" -eq 0 ] || fail "3: a 40-char slug and valid leap dates must pass: $(cat "$ERR")"
echo "ok 3: filename-grammar violations fail; boundary/leap accepts pass"

# --- 4. Content-shape violations fail ------------------------------------

# body_reject <label> <content> <reason> — seed a grammar-valid-NAMED fragment
# whose CONTENT is the violation, assert exit 1, that it failed on a CONTENT
# reason (never the filename path — the name is valid here), AND that the finding
# names the SPECIFIC <reason>. Asserting the exact message keeps the distinct
# content branches (bad-first-line / multi-entry / unexpected-line / empty) from
# collapsing into each other under a future regression that swaps their messages
# (the file's "wrong-reason exit 1 must not pass" discipline, applied per case).
body_reject() {
  _label=$1
  _content=$2
  _reason=$3
  _o="$tmp/br-$(printf '%s' "$_label" | tr -c 'a-z0-9' -)"
  new_tree "$_o"
  printf '%s' "$_content" >"$_o/entries/2026-07-09-topic-deadbeef.md"
  run_guard "$_o"
  [ "$RC" -eq 1 ] || fail "4: $_label expected exit 1, got $RC"
  grep -q 'invalid fragment filename' "$ERR" \
    && fail "4: $_label failed on the filename path, not a content reason"
  [ -s "$ERR" ] || fail "4: $_label produced no finding message"
  grep -q "$_reason" "$ERR" \
    || fail "4: $_label did not fail for the expected reason ($_reason): $(cat "$ERR")"
}
body_reject "multi-entry file" \
  '- 2026-07-09 [planwright] first entry
- 2026-07-09 [planwright] second entry
' 'multiple entry lines'
body_reject "missing entry line (leading blank)" \
  '
- 2026-07-09 [planwright] entry not on the first line
' 'first line is not the entry form'
body_reject "missing entry line (leading metadata)" \
  'Consumed-by: specs/foo (2026-06-02)
- 2026-07-09 [planwright] entry after metadata
' 'first line is not the entry form'
body_reject "free-prose body" \
  '- 2026-07-09 [planwright] a real observation
some free prose that is not metadata
' 'unexpected content line'
body_reject "unrecognized metadata key" \
  '- 2026-07-09 [planwright] a real observation
Author: someone
' 'unexpected content line'
body_reject "empty file (missing entry line)" '' 'empty fragment'
echo "ok 4: content-shape violations fail the guard, each for its specific reason"

# --- 5. UID uniqueness across entries/ + archive/ ------------------------

# 5a. Cross-directory duplicate: same UID on a fragment in entries/ and archive/.
o="$tmp/dupuid-cross"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-abcd1234.md"
printf -- '- 2026-06-01 [planwright] older\nConsumed-by: specs/foo (2026-06-02)\n' \
  >"$o/archive/2026-06-01-old-abcd1234.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "5a: a cross-dir duplicate UID expected exit 1, got $RC"
grep -q 'abcd1234' "$ERR" || fail "5a: the duplicate UID is not named in the finding"
# Both colliding paths are named (not just the bare UID) — the finding must let
# a human locate each fragment.
grep -q 'entries/2026-07-09-topic-abcd1234.md' "$ERR" \
  || fail "5a: the entries/ fragment is not named in the finding"
grep -q 'archive/2026-06-01-old-abcd1234.md' "$ERR" \
  || fail "5a: the archive/ fragment is not named in the finding"

# 5b. Same-directory duplicate: two entries/ fragments under different slugs but
# the same UID (the check keys on the UID, not the full filename).
o="$tmp/dupuid-same"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-a-abcd1234.md"
entry "$o/entries/2026-07-09-topic-b-abcd1234.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "5b: a same-dir duplicate UID expected exit 1, got $RC"
grep -q 'abcd1234' "$ERR" || fail "5b: the same-dir duplicate UID is not named"
echo "ok 5: a UID reused across or within directories fails, naming both fragments"

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

# --- 7. Content edge cases: metadata whitelist, CRLF -----------------------

# 7a. A positive whitelist case in isolation: an entry followed by a valid
# non-empty Consumed-by: line passes (the accept side of the whitelist).
o="$tmp/consumed-ok"
new_tree "$o"
printf -- '- 2026-07-09 [planwright] a real observation\nConsumed-by: specs/foo (2026-07-08)\n' \
  >"$o/entries/2026-07-09-topic-deadbeef.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "7a: a valid Consumed-by: metadata line must pass: $(cat "$ERR")"

# 7b. An empty-valued Consumed-by: line fails (whitelist exactness — the key
# alone, with no value, is not a legitimate annotation).
body_reject "empty-valued Consumed-by" \
  '- 2026-07-09 [planwright] a real observation
Consumed-by:
' 'unexpected content line'

# 7b'. A whitespace-only Consumed-by: value fails too — effectively empty, so it
# must reject like the bare-key case rather than sneaking through on `.+`. The
# spaces sit mid-string before `\n` in the printf format (not at a source
# line-end) so trailing-whitespace trimming cannot silently defang the case.
o="$tmp/ws-consumed"
new_tree "$o"
printf -- '- 2026-07-09 [planwright] a real observation\nConsumed-by:   \n' \
  >"$o/entries/2026-07-09-topic-deadbeef.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "7b': a whitespace-only Consumed-by must fail (got $RC): $(cat "$ERR")"
grep -q 'unexpected content line' "$ERR" \
  || fail "7b': whitespace-only Consumed-by failed for the wrong reason: $(cat "$ERR")"

# 7c. A CRLF-saved (merge-mangled) but otherwise valid fragment passes: the
# guard strips the trailing CR before validating, so line endings alone never
# decide the verdict. Includes a blank separator line, the case that would
# false-reject without the CR strip.
o="$tmp/crlf-ok"
new_tree "$o"
printf -- '- 2026-07-09 [planwright] a real observation\r\n\r\nConsumed-by: specs/foo (2026-07-08)\r\n' \
  >"$o/entries/2026-07-09-topic-deadbeef.md"
run_guard "$o"
[ "$RC" -eq 0 ] || fail "7c: a CRLF-saved valid fragment must pass (CR stripped): $(cat "$ERR")"
echo "ok 7: metadata whitelist accepts a valid Consumed-by, rejects an empty one; CRLF is normalized"

# --- 8. Symlink / type containment (D-7) ----------------------------------

# 8a. A symlinked fragment file is refused (never read through a symlink), even
# when it points at a grammar-valid, well-formed fragment.
o="$tmp/symlink-frag"
new_tree "$o"
real="$tmp/real-frag.md"
entry "$real"
ln -s "$real" "$o/entries/2026-07-09-topic-deadbeef.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8a: a symlinked fragment expected exit 1, got $RC"
grep -q 'symlink' "$ERR" || fail "8a: the finding does not name the symlink cause"

# 8b. A symlinked entries/ directory is refused (not traversed through).
o="$tmp/symlink-entries"
mkdir -p "$o"
realdir="$tmp/realdir-entries"
mkdir -p "$realdir"
entry "$realdir/2026-07-09-topic-deadbeef.md"
ln -s "$realdir" "$o/entries"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8b: a symlinked entries/ dir expected exit 1, got $RC"

# 8c. A regular FILE named `entries` under the root is refused (type confusion —
# it would otherwise be whitelisted by name and then -d-skipped, a silent pass).
o="$tmp/entries-not-dir"
mkdir -p "$o"
printf 'not a dir\n' >"$o/entries"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8c: a non-directory named entries/ expected exit 1, got $RC"

# 8d. A symlinked observations root is refused before it resolves to its target.
realroot="$tmp/realroot"
new_tree "$realroot"
entry "$realroot/entries/2026-07-09-topic-deadbeef.md"
linkroot="$tmp/linkroot"
ln -s "$realroot" "$linkroot"
run_guard "$linkroot"
[ "$RC" -eq 1 ] || fail "8d: a symlinked observations root expected exit 1, got $RC"

# 8e. A DANGLING symlink fragment (points at a nonexistent target) is still
# refused — `-e` is false for it, so the empty-glob guard must not skip it.
o="$tmp/dangling-frag"
new_tree "$o"
ln -s "$tmp/no-such-target" "$o/entries/2026-07-09-topic-deadbeef.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8e: a dangling symlink fragment expected exit 1, got $RC"
grep -q 'symlink' "$ERR" || fail "8e: the dangling-symlink finding does not name the cause"

# 8f. A dangling symlink with an UNEXPECTED name directly under the root is still
# caught (it must not slip past the compiled-view block as "absent").
o="$tmp/dangling-top"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
ln -s "$tmp/no-such-target" "$o/rendered-log.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8f: a dangling top-level symlink expected exit 1, got $RC"
echo "ok 8: symlinked (incl. dangling) fragments/dirs/root and a mistyped entries/ are refused"

# --- 8g-8i. Dotfile containment (a POSIX `*` glob skips leading-dot names) ------

# 8g. A hidden compiled view committed directly under the root is still caught as
# an unexpected file (it must not slip past the REQ-B1.3 block via a leading dot).
o="$tmp/dotfile-top"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
printf '# hidden compiled view\n' >"$o/.rendered-log.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8g: a hidden top-level file expected exit 1, got $RC"
grep -q '.rendered-log.md' "$ERR" || fail "8g: the hidden unexpected file is not named"

# 8h. A hidden file inside entries/ is name-checked (and rejected) rather than
# skipped — e.g. a leftover obs-record `.obs-record.XXXXXX` temp or a `.`-hand-edit.
o="$tmp/dotfile-entry"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
printf 'stray\n' >"$o/entries/.obs-record.hidden"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8h: a hidden file under entries/ expected exit 1, got $RC"

# 8i. A hidden fragment cannot smuggle in a duplicate UID: a `.`-prefixed name
# fails the filename grammar (the leading dot breaks the date prefix) and so is
# rejected before it could reach the UID ledger — the hidden file is enumerated
# and caught, never silently skipped as it was before the `.*` glob was added.
o="$tmp/dotfile-dup"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-abcd1234.md"
printf -- '- 2026-07-09 [planwright] hidden dup\n' >"$o/entries/.2026-07-09-hidden-abcd1234.md"
run_guard "$o"
[ "$RC" -eq 1 ] || fail "8i: a hidden fragment-shaped name expected exit 1, got $RC"
grep -q 'invalid fragment filename' "$ERR" || fail "8i: the hidden name was not caught by the grammar check"
echo "ok 8g-i: hidden (dot-prefixed) files under the root and entries/ are enumerated, not skipped"

# --- 9. Usage contract + mise wiring --------------------------------------

# 9a. An unknown flag is a usage error (exit 2), distinct from a violation (1).
RC=0
"$GUARD" --bogus >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || fail "9a: an unknown flag expected exit 2 (usage), got $RC"
# 9b. --obs-dir without a value is a usage error.
RC=0
"$GUARD" --obs-dir >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || fail "9b: --obs-dir without a value expected exit 2, got $RC"
# 9c. A hyphen-leading --obs-dir is refused (exit 2), never used as a path.
RC=0
"$GUARD" --obs-dir -x >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ] || fail "9c: a hyphen-leading --obs-dir expected exit 2, got $RC"

# 9d. The guard is wired into the aggregate `mise run check` that CI runs
# (REQ-D1.4 "wired into the aggregate"): the task exists and is a dependency of
# `check`. Asserted mechanically so dropping it from the depends array fails CI.
misefile="$here/../mise.toml"
grep -q '\[tasks."check:obs"\]' "$misefile" \
  || fail "9d: mise.toml defines no [tasks.\"check:obs\"] task"
grep -q '"check:obs"' "$misefile" \
  || fail "9d: check:obs is not referenced in mise.toml (aggregate depends)"
# The reference must sit inside the aggregate `check` task's depends list, not
# only in its own task header: extract the depends array and look for it there.
awk '
  /^\[tasks\.check\]/ { in_check = 1; next }
  /^\[/ { in_check = 0 }
  in_check && /"check:obs"/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$misefile" \
  || fail "9d: check:obs is not in the aggregate check.depends array"
echo "ok 9: usage contract holds; check:obs is wired into the aggregate check"

# --- 10. Echo discipline: C1 control bytes are stripped from findings ----------

# 10. A fragment name carrying a raw C1 byte (0x9B, 8-bit CSI) must not reach the
# finding message intact — safe() strips the C0+DEL+C1 set so a terminal reading
# 8-bit control codes cannot be driven from a committed filename. Seed an
# unexpected top-level file whose name embeds 0x9B, assert the guard fails (exit
# 1) and that the captured stderr contains ZERO 0x9B bytes while still naming the
# file's printable remainder. Fails on the pre-C1-strip guard (the byte survives).
#
# The injection vector is a *committed* filename, so it is reachable on the Linux
# filesystems CI runs on (arbitrary bytes but `/`\0 allowed). A UTF-8-normalizing
# filesystem (macOS/APFS) refuses to create the name at all, which neutralizes the
# vector there; when file creation is refused, skip rather than fail — CI on Linux
# is where the assertion has teeth.
o="$tmp/c1-strip"
new_tree "$o"
entry "$o/entries/2026-07-09-topic-deadbeef.md"
c1=$(printf '\233') # 0x9B, 8-bit CSI, under LC_ALL=C
if (: >"$o/stray${c1}view.md") 2>/dev/null; then
  run_guard "$o"
  [ "$RC" -eq 1 ] || fail "10: an unexpected C1-named file expected exit 1, got $RC"
  c1count=$(tr -cd "$c1" <"$ERR" | wc -c | tr -d ' ')
  [ "$c1count" -eq 0 ] || fail "10: a 0x9B byte survived into the finding ($c1count present)"
  grep -q 'strayview.md' "$ERR" \
    || fail "10: the C1-stripped name is not shown in the finding: $(cat "$ERR")"
  echo "ok 10: a C1 (0x9B) byte in a fragment name is stripped from the finding message"
else
  echo "ok 10: SKIP — this filesystem refuses C1-byte filenames (vector needs a Linux-class FS)"
fi

echo "PASS: test-check-obs.sh"
