#!/bin/bash
# Tests for scripts/check-platform-claims.sh — the platform-claims register
# guard (inception Task 14; D-11, REQ-H1.4; the design's staleness concern).
#
# Two modes. The gate mode fails only a malformed register, and names a claim
# past its re-verify date without failing, so the suite never turns red on a
# calendar. The release mode (--strict) fails on a due claim too: a release
# does not ship platform claims nobody has re-checked.
#
# Plain bash 3.2, inline asserts (sibling convention).
#
# shellcheck disable=SC2016 # fixture backticks are markdown code spans.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-platform-claims.sh"

failures=0
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
      echo "FAIL: $1 (expected to find '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$CHECKER" ]; then
  echo "FAIL: $CHECKER is missing or not executable" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A fixture repo root: the register's `Relied on by` paths resolve against it.
root="$tmp/repo"
mkdir -p "$root/scripts"
: >"$root/scripts/uses-claim.sh"

# entry <id> <title> [verified] [re-verify-by] [relied-on] [source]
entry() {
  printf '### %s — %s\n\n' "$1" "$2"
  printf -- '- **Claim:** something a platform does.\n'
  printf -- '- **Relied on by:** `%s`\n' "${5:-scripts/uses-claim.sh}"
  printf -- '- **Source:** %s\n' "${6:-https://example.com/docs}"
  printf -- '- **Verified:** %s\n' "${3:-2026-10-01}"
  printf -- '- **Re-verify-by:** %s\n\n' "${4:-2027-01-01}"
}

reg="$tmp/claims.md"
write_reg() {
  {
    printf '# Platform claims\n\n## Claims\n\n'
    cat
  } >"$reg"
}

check() {
  out=$(/bin/sh "$CHECKER" --root "$root" --today "${TODAY:-2026-11-01}" "$@" "$reg" 2>&1)
  rc=$?
}

# --- a clean register ------------------------------------------------------

{
  entry PC-1 'first claim'
  entry PC-2 'second claim'
} | write_reg
check
assert_eq "clean register passes (exit)" 0 "$rc"
assert_contains "clean register says how many it checked" "2 claim" "$out"
check --strict
assert_eq "clean register passes strict mode" 0 "$rc"

# --- due claims: named in the gate, failing only under --strict ------------

{
  entry PC-1 'first claim'
  entry PC-2 'stale claim' 2026-06-01 2026-09-01
} | write_reg
check
assert_eq "a due claim does not fail the gate mode" 0 "$rc"
assert_contains "a due claim is named" "$(printf 'due\tPC-2\t2026-09-01\tstale claim')" "$out"
assert_not_contains "a current claim is not named as due" "$(printf 'due\tPC-1')" "$out"
check --strict
assert_eq "a due claim fails strict mode" 1 "$rc"

{ entry PC-2 'stale claim' 2026-06-01 2026-09-01; } | write_reg
TODAY=2026-09-01 check --strict
assert_eq "a claim is not due on its re-verify date" 0 "$rc"

# --- malformed registers fail in every mode --------------------------------

{
  entry PC-1 'first claim'
  entry PC-1 'duplicate'
} | write_reg
check
assert_eq "a duplicate ID fails" 1 "$rc"
assert_contains "a duplicate ID is named" "PC-1" "$out"

{ entry PC-1 'bad date' 2026-13-01; } | write_reg
check
assert_eq "an invalid Verified date fails" 1 "$rc"

{ entry PC-1 'backwards' 2026-10-01 2026-09-01; } | write_reg
check
assert_eq "a re-verify date before the verified date fails" 1 "$rc"

{ entry PC-1 'future' 2026-12-01 2027-01-01; } | write_reg
check
assert_eq "a Verified date after today fails" 1 "$rc"

{ entry PC-1 'gone' 2026-10-01 2027-01-01 scripts/no-such.sh; } | write_reg
check
assert_eq "a Relied-on path that does not exist fails" 1 "$rc"
assert_contains "the missing path is named" "scripts/no-such.sh" "$out"

{ entry PC-1 'autolink' 2026-10-01 2027-01-01 scripts/uses-claim.sh '<https://example.com/docs>'; } | write_reg
check
assert_eq "an autolinked https source passes" 0 "$rc"

{ entry PC-1 'http' 2026-10-01 2027-01-01 scripts/uses-claim.sh http://example.com; } | write_reg
check
assert_eq "a non-https source fails" 1 "$rc"

{
  printf '### PC-1 — missing a field\n\n'
  printf -- '- **Claim:** x\n- **Relied on by:** `scripts/uses-claim.sh`\n'
  printf -- '- **Source:** https://example.com\n- **Verified:** 2026-10-01\n\n'
} | write_reg
check
assert_eq "a missing field fails" 1 "$rc"
assert_contains "the missing field is named" "missing field Re-verify-by" "$out"

{
  printf '### PC-1 — empty claim\n\n'
  printf -- '- **Claim:** \n- **Relied on by:** `scripts/uses-claim.sh`\n'
  printf -- '- **Source:** https://example.com\n- **Verified:** 2026-10-01\n'
  printf -- '- **Re-verify-by:** 2027-01-01\n\n'
} | write_reg
check
assert_eq "an empty field fails" 1 "$rc"
assert_contains "the empty field is named as missing" "missing field Claim" "$out"

{
  printf '### PC-1 — blank claim\n\n'
  printf -- '- **Claim:**   \n- **Relied on by:** `scripts/uses-claim.sh`\n'
  printf -- '- **Source:** https://example.com\n- **Verified:** 2026-10-01\n'
  printf -- '- **Re-verify-by:** 2027-01-01\n\n'
} | write_reg
check
assert_eq "a field holding only spaces fails" 1 "$rc"
assert_contains "the blank field is named as missing" "missing field Claim" "$out"

{
  entry PC-1 'repeated date' 2026-10-01 2027-01-01
  printf -- '- **Verified:** 2026-09-01\n\n'
} | write_reg
check
assert_eq "a repeated field fails" 1 "$rc"
assert_contains "the repeated field is named" "duplicate field Verified" "$out"

{
  entry PC-1 'first claim'
  printf '### Claim one\n\n'
} | write_reg
check
assert_eq "a heading without a PC id fails" 1 "$rc"
assert_contains "the bad heading is named" "heading is not" "$out"

{
  printf '### PC-1 — tab\there\n\n'
  printf -- '- **Claim:** x\n- **Relied on by:** `scripts/uses-claim.sh`\n'
  printf -- '- **Source:** https://example.com\n- **Verified:** 2026-10-01\n'
  printf -- '- **Re-verify-by:** 2027-01-01\n\n'
} | write_reg
check
assert_eq "a tab in a title does not shift the fields" 0 "$rc"

for d in 2026-02-29 2026-04-31 2026-02-30 1900-02-29; do
  { entry PC-1 'impossible date' "$d" 2027-01-01; } | write_reg
  check
  assert_eq "an impossible Verified date ($d) fails" 1 "$rc"
done
{ entry PC-1 'leap day' 2024-02-29 2027-01-01; } | write_reg
check
assert_eq "a leap day passes" 0 "$rc"
{ entry PC-1 'century leap day' 2000-02-29 2027-01-01; } | write_reg
check
assert_eq "a leap day in a year divisible by 400 passes" 0 "$rc"

{ entry PC-1 'bad re-verify' 2026-10-01 2027-1-01; } | write_reg
check
assert_eq "an invalid Re-verify-by date fails" 1 "$rc"
assert_contains "the invalid Re-verify-by is named" "Re-verify-by is not" "$out"

{ entry PC-1 'same day' 2026-10-01 2026-10-01; } | write_reg
check
assert_eq "a re-verify date equal to the verified date fails" 1 "$rc"

for p in /etc/hosts ../repo/scripts/uses-claim.sh; do
  { entry PC-1 'outside' 2026-10-01 2027-01-01 "$p"; } | write_reg
  check
  assert_eq "a Relied-on path outside the repository ($p) fails" 1 "$rc"
  assert_contains "the outside path is refused by name" "must name a repository path" "$out"
done

printf '# Platform claims\n\n## Claims\n\n' >"$reg"
check
assert_eq "a register with no claims fails closed" 1 "$rc"

check_missing() {
  out=$(/bin/sh "$CHECKER" --root "$root" --today 2026-11-01 "$tmp/absent.md" 2>&1)
  rc=$?
}
check_missing
assert_eq "an absent register fails closed" 1 "$rc"

out=$(/bin/sh "$CHECKER" --today 2026-1-01 "$reg" 2>&1)
assert_eq "a malformed --today is a usage error" 2 "$?"

# --- the shipped register --------------------------------------------------

out=$(/bin/sh "$CHECKER" 2>&1)
assert_eq "the shipped register is well formed" 0 "$?"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all tests passed"
