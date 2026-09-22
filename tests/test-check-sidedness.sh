#!/bin/bash
# Tests for scripts/check-sidedness.sh, the advisory check that flags emit
# mandates declaring no destination side (operator-dialogue REQ-M1.3, REQ-I1.4).
#
# The claims pinned here are the check's own behavior, never its findings over
# the live corpus: it detects the planted side-less mandates, stays quiet on
# sided ones and inside code fences, always exits zero while reporting, never
# scans its own planted fixture on the default corpus pass, and is wired into
# the `check` aggregate reporting-only.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-sidedness.sh"
PLANTED="$REPO_ROOT/tests/fixtures/sidedness/side-less-mandate.md"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)
      bad "$1 (missing '$2')"
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      bad "$1 (unexpected '$2')"
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      ;;
    *) ok "$1" ;;
  esac
}

for f in "$CHECK" "$PLANTED"; do
  [ -f "$f" ] || {
    echo "FAIL: required file missing at $f" >&2
    exit 1
  }
done

TMP="$(mktemp -d)" || {
  echo "FAIL: mktemp -d failed" >&2
  exit 1
}
trap 'rm -rf "$TMP"' EXIT

echo "== the planted fixture: side-less mandates are reported =="
out="$(/bin/sh "$CHECK" "$PLANTED" 2>&1)"
rc=$?
assert_exit "reporting findings still exits zero" 0 "$rc"
assert_contains "an imperative side-less mandate is reported" "side-less-mandate.md:8:" "$out"
assert_contains "a modal side-less mandate is reported" "side-less-mandate.md:12:" "$out"
assert_contains "a mandate after a bold bullet label is reported" "side-less-mandate.md:16:" "$out"
assert_not_contains "a mandate naming the operator is not reported" "side-less-mandate.md:10:" "$out"
assert_not_contains "a mandate naming the artifact is not reported" "side-less-mandate.md:14:" "$out"
assert_not_contains "a mandate inside a code fence is not reported" "side-less-mandate.md:20:" "$out"
assert_not_contains "a prohibition is not an emit mandate" "side-less-mandate.md:23:" "$out"
assert_contains "the summary counts the three planted findings" "3 emit mandate(s)" "$out"
assert_contains "the summary says the check is advisory" "advisory" "$out"

echo "== the default corpus pass never scans the planted fixture =="
out="$(/bin/sh "$CHECK" 2>&1)"
rc=$?
assert_exit "the live corpus pass exits zero whatever it finds" 0 "$rc"
assert_not_contains "the planted fixture is outside the scanned corpus" "tests/fixtures/sidedness" "$out"
assert_contains "the live pass prints its advisory summary" "advisory" "$out"

echo "== corpus discovery: skills and doctrine under --root are scanned =="
mkdir -p "$TMP/root/doctrine" "$TMP/root/skills/demo" "$TMP/root/tests"
printf '# Demo\n\nRender the whole history.\n' >"$TMP/root/doctrine/demo.md"
printf '# Demo skill\n\nDisplay every finding.\n\nShow the summary to the operator.\n' \
  >"$TMP/root/skills/demo/SKILL.md"
cp "$PLANTED" "$TMP/root/tests/"
out="$(/bin/sh "$CHECK" --root "$TMP/root" 2>&1)"
rc=$?
assert_exit "a corpus with findings exits zero" 0 "$rc"
assert_contains "a doctrine file is scanned" "doctrine/demo.md:3:" "$out"
assert_contains "a skill file is scanned" "skills/demo/SKILL.md:3:" "$out"
assert_not_contains "a sided skill mandate is not reported" "skills/demo/SKILL.md:5:" "$out"
assert_not_contains "tests/ under the root is not part of the corpus" "side-less-mandate" "$out"

echo "== a clean corpus reports zero =="
mkdir -p "$TMP/clean/doctrine"
printf '# Clean\n\nPresent the counts turn-side.\n' >"$TMP/clean/doctrine/clean.md"
out="$(/bin/sh "$CHECK" --root "$TMP/clean" 2>&1)"
rc=$?
assert_exit "a clean corpus exits zero" 0 "$rc"
assert_contains "a clean corpus reports zero findings" "0 emit mandate(s)" "$out"

echo "== usage errors are distinct from findings =="
/bin/sh "$CHECK" --root >/dev/null 2>&1
assert_exit "--root without a value is a usage error" 2 "$?"
/bin/sh "$CHECK" --bogus >/dev/null 2>&1
assert_exit "an unknown option is a usage error" 2 "$?"

echo "== wiring: reporting-only inside the check aggregate =="
MISE="$REPO_ROOT/mise.toml"
task_body="$(awk '/^\[tasks\."check:sidedness"\]/{f=1;next} /^\[/{f=0} f' "$MISE")"
assert_contains "check:sidedness runs the script" "scripts/check-sidedness.sh" "$task_body"
check_deps="$(awk '/^\[tasks\.check\]/{f=1;next} /^\[/{f=0} f' "$MISE")"
assert_contains "check depends on check:sidedness" '"check:sidedness"' "$check_deps"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-sidedness tests passed"
