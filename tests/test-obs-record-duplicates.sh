#!/bin/sh
# Unit test for scripts/obs-record.sh's duplicate refusal and its
# --recurrence escape (review-effectiveness REQ-I1.1, D-20).
#
# Properties verified:
#   1. A shared slug alone is never a duplicate: two skill-drift fragments
#      with unrelated text are both written.
#   2. A fragment sharing the scope token, a test path and a quoted string
#      with a live fragment is refused (exit 1) naming obs:<uid>, nothing
#      written; the same against an archived fragment.
#   3. Half a key is not a match: a shared test path alone, a shared quoted
#      string alone, and a backticked test path as the only shared span are
#      each written.
#   4. --recurrence <uid> naming the matched fragment writes the
#      `recurrence of obs:<uid>:` marker after a skill-drift(...) prefix, and
#      at the start of a text with no kind prefix.
#   5. A --recurrence uid the refusal did not match is refused (a real
#      fragment that is not the match, a uid with no match at all, a
#      malformed uid), nothing written.
#   6. A miss-ledger fragment (slug review-miss) matching another is written.
#   7. A matching fragment in another scope does not refuse.
#   8. scripts/check-obs.sh accepts a store carrying recurrence markers.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REC="$here/../scripts/obs-record.sh"
CHK="$here/../scripts/check-obs.sh"

fail() {
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}

[ -x "$REC" ] || fail "scripts/obs-record.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# store <name> — a fresh observations dir with empty entries/ and archive/.
store() {
  mkdir -p "$tmp/$1/entries" "$tmp/$1/archive"
  printf '%s' "$tmp/$1"
}

# seed <obs-dir> <sub> <slug> <uid> <scope> <text> — place a fragment by hand.
seed() {
  printf '%s\n' "- 2026-10-01 [$5] $6" >"$1/$2/2026-10-01-$3-$4.md"
}

# frags <obs-dir> — number of fragments under entries/ and archive/.
frags() {
  find "$1/entries" "$1/archive" -name '*.md' | wc -l | tr -d ' '
}

rec() {
  "$REC" --today 2026-10-31 "$@"
}

# shellcheck disable=SC2016 # the backticks are fragment text, not substitution
LIVE_TEXT='`tests/test-gate.sh` fails with "lock held by another gate" under load'
DUP_TEXT='again: tests/test-gate.sh reports "lock held by another gate" on CI'

# --- 1. a shared slug alone ------------------------------------------------
o=$(store s1)
seed "$o" entries skill-drift aaaa0001 planwright 'skill-drift(polish): the Points section names a removed step'
rec --obs-dir "$o" --slug skill-drift --scope planwright \
  --text 'skill-drift(self-review): the Maintenance step cites a moved doc' >/dev/null \
  || fail "1: a fragment sharing only the slug was refused"
[ "$(frags "$o")" -eq 2 ] || fail "1: expected two fragments"
echo "ok 1: a shared slug alone is written"

# --- 2. live and archived matches refuse, naming the match ---------------
for sub in entries archive; do
  o=$(store "s2$sub")
  seed "$o" "$sub" gate-lock bbbb0002 planwright "$LIVE_TEXT"
  rc=0
  err=$(rec --obs-dir "$o" --slug gate-lock-again --scope planwright --text "$DUP_TEXT" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "2: a duplicate of an $sub fragment expected exit 1, got $rc"
  case $err in
    *"obs:bbbb0002"*) ;;
    *) fail "2: the refusal does not name the matched $sub fragment: $err" ;;
  esac
  [ "$(frags "$o")" -eq 1 ] || fail "2: a refused duplicate of an $sub fragment was written"
done
echo "ok 2: a path-plus-quote match against a live or archived fragment is refused naming it"

# --- 3. half a key is not a match ----------------------------------------
o=$(store s3)
seed "$o" entries gate-lock cccc0003 planwright "$LIVE_TEXT"
rec --obs-dir "$o" --slug a --scope planwright \
  --text 'tests/test-gate.sh is slow, "a different message" here' >/dev/null \
  || fail "3: a shared test path alone was refused"
rec --obs-dir "$o" --slug b --scope planwright \
  --text 'tests/test-other.sh prints "lock held by another gate" too' >/dev/null \
  || fail "3: a shared quoted string alone was refused"
# shellcheck disable=SC2016 # the backticks are fragment text, not substitution
rec --obs-dir "$o" --slug c --scope planwright \
  --text '`tests/test-gate.sh` needs a timeout' >/dev/null \
  || fail "3: a backticked test path as the only shared span was refused"
[ "$(frags "$o")" -eq 4 ] || fail "3: expected four fragments"
echo "ok 3: a test path or quoted string alone is written"

# --- 4. a recurrence writes the marker ------------------------------------
o=$(store s4)
seed "$o" entries skill-drift dddd0004 planwright \
  'skill-drift(polish): tests/test-polish.sh asserts "converged" but the skill says "drained"'
out=$(rec --obs-dir "$o" --slug skill-drift --scope planwright --recurrence dddd0004 \
  --text 'skill-drift(polish): tests/test-polish.sh still asserts "converged" over "drained"') \
  || fail "4: a recurrence naming the matched fragment was refused"
want='- 2026-10-31 [planwright] skill-drift(polish): recurrence of obs:dddd0004: tests/test-polish.sh still asserts "converged" over "drained"'
[ "$(cat "$out")" = "$want" ] || fail "4: marker not after the kind prefix: $(cat "$out")"

seed "$o" archive gate-lock eeee0004 planwright "$LIVE_TEXT"
out=$(rec --obs-dir "$o" --slug gate-lock --scope planwright --recurrence eeee0004 --text "$DUP_TEXT") \
  || fail "4: a recurrence of an archived fragment was refused"
[ "$(cat "$out")" = "- 2026-10-31 [planwright] recurrence of obs:eeee0004: $DUP_TEXT" ] \
  || fail "4: marker not at the start of an unprefixed text: $(cat "$out")"
echo "ok 4: --recurrence writes the marker after a kind prefix, else at the start"

# --- 5. a uid the refusal did not match is refused -----------------------
o=$(store s5)
seed "$o" entries gate-lock ffff0005 planwright "$LIVE_TEXT"
seed "$o" entries other ffff0006 planwright 'an unrelated fragment'
for uid in ffff0006 12345678 NOTAUID; do
  rc=0
  rec --obs-dir "$o" --slug gate-lock --scope planwright --recurrence "$uid" \
    --text "$DUP_TEXT" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "5: --recurrence $uid expected exit 1, got $rc"
done
rc=0
rec --obs-dir "$o" --slug fresh --scope planwright --recurrence ffff0005 \
  --text 'a text that matches nothing' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "5: --recurrence on a text matching nothing expected exit 1, got $rc"
[ "$(frags "$o")" -eq 2 ] || fail "5: a refused recurrence was written"
echo "ok 5: a --recurrence uid the refusal did not match is refused"

# --- 6. miss-ledger fragments are exempt ----------------------------------
o=$(store s6)
seed "$o" entries review-miss abab0006 planwright "$LIVE_TEXT"
rec --obs-dir "$o" --slug review-miss --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "6: a miss-ledger fragment matching another was refused"
echo "ok 6: a miss-ledger fragment is not refused"

# --- 7. no match across scopes ---------------------------------------------
o=$(store s7)
seed "$o" entries gate-lock acac0007 dotfiles "$LIVE_TEXT"
rec --obs-dir "$o" --slug gate-lock --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "7: a match in another scope refused"
echo "ok 7: a matching fragment in another scope does not refuse"

# --- 8. check-obs accepts the marker --------------------------------------
"$CHK" --obs-dir "$tmp/s4" >/dev/null 2>&1 || fail "8: check-obs rejects a store with recurrence markers"
echo "ok 8: check-obs accepts the recurrence marker"

echo "PASS: test-obs-record-duplicates.sh"
