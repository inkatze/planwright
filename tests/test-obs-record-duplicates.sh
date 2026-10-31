#!/bin/sh
# Unit test for scripts/obs-record.sh's duplicate refusal and its
# --recurrence escape (review-effectiveness REQ-I1.1, D-20). Each numbered
# section states the property it verifies in its `ok` line.
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
for pair in 'ffff0006|is not a fragment this text duplicates' \
  '12345678|is not a fragment this text duplicates' \
  'NOTAUID|8 lowercase hex' 'FFFF0005|8 lowercase hex' '|8 lowercase hex'; do
  uid=${pair%%|*}
  rc=0
  err=$(rec --obs-dir "$o" --slug gate-lock --scope planwright --recurrence "$uid" \
    --text "$DUP_TEXT" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "5: --recurrence '$uid' expected exit 1, got $rc"
  case $err in
    *"${pair#*|}"*) ;;
    *) fail "5: --recurrence '$uid' refused for the wrong reason: $err" ;;
  esac
done
rc=0
err=$(rec --obs-dir "$o" --slug fresh --scope planwright --recurrence ffff0005 \
  --text 'a text that matches nothing' 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 1 ] || fail "5: --recurrence on a text matching nothing expected exit 1, got $rc"
case $err in
  *"is not a fragment this text duplicates"*) ;;
  *) fail "5: a recurrence of nothing refused for the wrong reason: $err" ;;
esac
[ "$(frags "$o")" -eq 2 ] || fail "5: a refused recurrence was written"
echo "ok 5: a --recurrence uid the refusal did not match is refused"

# --- 6. miss-ledger fragments are exempt ----------------------------------
o=$(store s6)
seed "$o" entries review-miss abab0006 planwright "$LIVE_TEXT"
rec --obs-dir "$o" --slug review-miss --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "6: a miss-ledger fragment matching another was refused"
o=$(store s6new)
seed "$o" entries gate-lock abab0016 planwright "$LIVE_TEXT"
rec --obs-dir "$o" --slug review-miss --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "6: a new miss-ledger fragment matching an ordinary one was refused"
o=$(store s6old)
seed "$o" entries review-miss abab0026 planwright "$LIVE_TEXT"
rec --obs-dir "$o" --slug gate-lock --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "6: an ordinary fragment matching a stored miss-ledger one was refused"
o=$(store s6ci)
seed "$o" entries ci-review-miss abab0036 planwright "$LIVE_TEXT"
rc=0
rec --obs-dir "$o" --slug gate-lock --scope planwright --text "$DUP_TEXT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "6: a ci-review-miss slug was exempted as a miss-ledger fragment"
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

# --- 9. a test path is a whole token, compared in full ---------------------
o=$(store s9)
seed "$o" entries x abcd0009 planwright 'skills/a/tests/run.sh logged "err"'
seed "$o" entries y abcd0019 planwright 'tests/a+b.sh said "e"'
seed "$o" entries z abcd0029 planwright 'mytests/m.sh printed "m"'
for t in 'plugins/b/tests/run.sh logged "err"' 'tests/a+c.sh said "e"' \
  'mytests/m.sh printed "m"'; do
  rec --obs-dir "$o" --slug n --scope planwright --text "$t" >/dev/null \
    || fail "9: a distinct or non-test path was refused: $t"
done
for t in 'see ./tests/a+b.sh: it said "e".' 'again skills/a/tests/run.sh. "err"'; do
  rc=0
  rec --obs-dir "$o" --slug n --scope planwright --text "$t" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "9: the same path in other punctuation was not refused: $t"
done
echo "ok 9: a test path matches only the same whole path"

# --- 10. what counts as a kind prefix ----------------------------------------
o=$(store s10)
seed "$o" entries gate-lock abcd0010 planwright "$LIVE_TEXT"
P='tests/test-gate.sh "lock held by another gate"'
for pair in \
  "skill-drift(execute-task, polish): |$P|skill-drift(execute-task, polish): recurrence of obs:abcd0010: $P" \
  "see (flaky): |$P|recurrence of obs:abcd0010: see (flaky): $P" \
  "Drift(x): |$P|recurrence of obs:abcd0010: Drift(x): $P" \
  "9x(y): |$P|recurrence of obs:abcd0010: 9x(y): $P" \
  "a(b(c): |$P|recurrence of obs:abcd0010: a(b(c): $P" \
  "(x): |$P|recurrence of obs:abcd0010: (x): $P"; do
  pre=${pair%%|*}
  rest=${pair#*|}
  body=${rest%%|*}
  want=${rest#*|}
  out=$(rec --obs-dir "$o" --slug k --scope planwright --recurrence abcd0010 --text "$pre$body") \
    || fail "10: a recurrence was refused: $pre"
  [ "$(cat "$out")" = "- 2026-10-31 [planwright] $want" ] \
    || fail "10: marker misplaced for '$pre': $(cat "$out")"
done
echo "ok 10: the marker follows only a lowercase name(arg) prefix with no nested parentheses"

# --- 11. an unreadable store refuses cleanly ---------------------------------
if [ "$(id -u)" -ne 0 ]; then
  o=$(store s11)
  seed "$o" entries gate-lock abcd0011 planwright "$LIVE_TEXT"
  chmod 000 "$o/entries/2026-10-01-gate-lock-abcd0011.md"
  rc=0
  err=$(rec --obs-dir "$o" --slug n --scope planwright --text 'a new "thing"' 2>&1 >/dev/null) || rc=$?
  chmod 644 "$o/entries/2026-10-01-gate-lock-abcd0011.md"
  [ "$rc" -eq 1 ] || fail "11: an unreadable fragment expected exit 1, got $rc"
  case $err in
    *"cannot read the store"*) ;;
    *) fail "11: the refusal does not name the unreadable store: $err" ;;
  esac
  case $err in
    *"$o"*) fail "11: the refusal echoes a store path: $err" ;;
  esac
  [ "$(frags "$o")" -eq 1 ] || fail "11: a fragment was written past an unreadable store"
  echo "ok 11: an unreadable fragment refuses with the recorder's own message only"
else
  echo "ok 11: skipped (root reads an unreadable file)"
fi

# --- 12. store shape: stray files, no archive/, two matches ---------------
o=$(store s12)
printf '%s\n' "- 2026-10-01 [planwright] $LIVE_TEXT" >"$o/entries/notes.md"
printf '%s\n' "- 2026-10-01 [planwright] $LIVE_TEXT" >"$o/entries/2026-10-01-x-abcd0012.txt"
printf '%s\n' "* 2026-10-01 [planwright] $LIVE_TEXT" >"$o/entries/2026-10-01-x-abcd0022.md"
rec --obs-dir "$o" --slug n --scope planwright --text "$DUP_TEXT" >/dev/null \
  || fail "12: a file outside the fragment grammar was read as a fragment"
o=$(store s12b)
rmdir "$o/archive"
seed "$o" entries gate-lock abcd0032 planwright "$LIVE_TEXT"
seed "$o" entries gate-lock abcd0042 planwright "$LIVE_TEXT"
rc=0
err=$(rec --obs-dir "$o" --slug n --scope planwright --text "$DUP_TEXT" 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 1 ] || fail "12: a duplicate in a store with no archive/ expected exit 1, got $rc"
case $err in
  *obs:abcd0032*obs:abcd0042* | *obs:abcd0042*obs:abcd0032*) ;;
  *) fail "12: the refusal does not name both matches: $err" ;;
esac
rec --obs-dir "$o" --slug n --scope planwright --recurrence abcd0042 --text "$DUP_TEXT" >/dev/null \
  || fail "12: a recurrence of the second match was refused"
echo "ok 12: only grammar-shaped fragments are read; no archive/ is fine; every match is named"

echo "PASS: test-obs-record-duplicates.sh"
