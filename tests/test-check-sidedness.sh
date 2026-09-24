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
assert_contains "the summary counts the three planted findings" "check-sidedness: 3 emit mandate(s)" "$out"
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
assert_contains "a clean corpus reports zero findings" "check-sidedness: 0 emit mandate(s)" "$out"

echo "== a multi-digit count still reads as a determiner =="
printf '# Counts\n\nPresent 42 tables.\n' >"$TMP/counts.md"
out="$(/bin/sh "$CHECK" "$TMP/counts.md" 2>&1)"
assert_contains "a mandate over a multi-digit count is reported" "counts.md:3:" "$out"

echo "== a terminal state is not the terminal =="
printf '# Terminal\n\nPresent the terminal status of each task.\n\nShow the summary in the terminal.\n\nPrint the digest at the terminal.\n' >"$TMP/terminal.md"
out="$(/bin/sh "$CHECK" "$TMP/terminal.md" 2>&1)"
assert_contains "a mandate over a terminal state is reported" "terminal.md:3:" "$out"
assert_not_contains "a mandate naming the terminal is not reported" "terminal.md:5:" "$out"
assert_not_contains "a mandate at the terminal is not reported" "terminal.md:7:" "$out"

echo "== the terminal phrase needs whole words and no state noun =="
printf '# Terminal\n\nReport that the terminal state was reached.\n\nShow what the terminal status is.\n\nPresent each task at the terminal state.\n\nPresent each task in the terminal state.\n\nShow the updates to the terminally idle.\n\nPrint the digest at the terminal, then stop.\n' >"$TMP/terminal-words.md"
out="$(/bin/sh "$CHECK" "$TMP/terminal-words.md" 2>&1)"
assert_contains "\"that the terminal\" does not read as \"at the terminal\"" "terminal-words.md:3:" "$out"
assert_contains "\"what the terminal\" does not read as \"at the terminal\"" "terminal-words.md:5:" "$out"
assert_contains "a mandate at a terminal state is reported" "terminal-words.md:7:" "$out"
assert_contains "a mandate in a terminal state is reported" "terminal-words.md:9:" "$out"
assert_contains "\"terminally\" does not read as the terminal" "terminal-words.md:11:" "$out"
assert_not_contains "the terminal before punctuation still names the turn" "terminal-words.md:13:" "$out"

echo "== a hard-wrapped terminal state is still a state =="
printf '# Wrap\n\nPresent each task at the terminal  \nstate.\n' >"$TMP/wrap.md"
out="$(/bin/sh "$CHECK" "$TMP/wrap.md" 2>&1)"
assert_contains "a terminal state split by a hard line break is reported" "wrap.md:3:" "$out"

echo "== a sentence ending inside a quote or parenthesis ends there =="
printf '# Close\n\nPresent the four tables." Record it in tasks.md.\n\nShow the digest (as above.) Write the rest to tasks.md.\n' >"$TMP/close.md"
out="$(/bin/sh "$CHECK" "$TMP/close.md" 2>&1)"
assert_contains "a mandate closed by a quote is not hidden by the next sentence" "close.md:3: Present the four tables.\"" "$out"
assert_contains "a mandate closed by a parenthesis is not hidden by the next sentence" "close.md:5: Show the digest" "$out"

printf '# Tab\n\nPresent the four tables.\tRecord it in tasks.md.\n' >"$TMP/tab.md"
out="$(/bin/sh "$CHECK" "$TMP/tab.md" 2>&1)"
assert_contains "a sentence ended by a tab is not hidden by the next one" "tab.md:3: Present the four tables." "$out"

echo "== a file name that looks like an awk assignment is scanned as a file =="
mkdir -p "$TMP/eq"
printf '# Eq\n\nPresent the counts.\n' >"$TMP/eq/a=b.md"
printf '# Next\n\nRender the history.\n' >"$TMP/eq/next.md"
out="$(cd "$TMP/eq" && /bin/sh "$CHECK" a=b.md next.md 2>&1)"
assert_contains "the assignment-shaped file is scanned" "a=b.md:3:" "$out"
assert_contains "the file after it is still scanned" "next.md:3:" "$out"
assert_contains "both files are counted" "in 2 file(s)" "$out"

echo "== an explicit directory is skipped, not scanned =="
out="$(/bin/sh "$CHECK" "$TMP/clean" 2>&1)"
rc=$?
assert_exit "a directory argument still exits zero" 0 "$rc"
assert_contains "a directory argument is named as skipped" "skipped" "$out"
assert_contains "a skipped directory is not counted as scanned" "in 0 file(s)" "$out"

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
