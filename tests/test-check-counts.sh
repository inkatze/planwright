#!/bin/bash
# Tests for scripts/check-counts.sh, the count-versus-list guard (REQ-F1.3).
#
# Each fixture is a small git repository: the guard reads tracked files only,
# so a fixture file it should see is added to the index.
#
# shellcheck disable=SC2016 # fixture prose carries literal code spans.
set -u
unset CDPATH
LC_ALL=C
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export LC_ALL GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-counts.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*)
      echo "FAIL: $1 (output mentioned '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-check-counts.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

# make_repo <dir>: an empty git repository with an empty exemption list.
make_repo() {
  mkdir -p "$1" || exit 1
  git -C "$1" init -q 2>/dev/null || exit 1
  printf '# file\tsentence excerpt\treason\n' >"$1/exempt.tsv"
}

# put <repo> <path> <line>...: write the file verbatim and track it.
put() {
  p_repo=$1 p_path=$2
  shift 2
  mkdir -p "$(dirname "$p_repo/$p_path")" || exit 1
  printf '%s\n' "$@" >"$p_repo/$p_path" || exit 1
  git -C "$p_repo" add -- "$p_path" || exit 1
}

# bundle <repo> <name> <status>: a bundle whose requirements.md declares the
# status, its design.md carrying a count that disagrees with its list.
bundle() {
  put "$1" "specs/$2/requirements.md" "# $2" "" "**Status:** $3" ""
  put "$1" "specs/$2/design.md" "# Design" "" \
    "The decision has three parts:" "" "- one" "- two"
}

check() { /bin/bash "$CHECKER" --exempt "$1/exempt.tsv" "$1" 2>&1; }

MATCH_LINES='The guard reads three inputs:|- the first|- the second|- the third'
MISMATCH_LINES='The guard reads four inputs:|- the first|- the second|- the third'

lines_of() {
  old_ifs=$IFS
  IFS='|'
  # shellcheck disable=SC2086 # the split on | is the point
  set -- $1
  IFS=$old_ifs
  printf '%s\n' "$@"
}

# REQ-F1.3: a matching count passes and a mismatched one fails, in every
# surface the guard covers.
for surface in doctrine/rule.md skills/demo/SKILL.md docs/guide.md \
  specs/_pending/note.md specs/drafted/design.md; do
  r="$tmp/match-$(printf '%s' "$surface" | tr '/.' '__')"
  make_repo "$r"
  put "$r" specs/drafted/requirements.md "# drafted" "" "**Status:** Draft"
  mkdir -p "$(dirname "$r/$surface")"
  lines_of "$MATCH_LINES" >"$r/$surface"
  git -C "$r" add -- "$surface"
  out=$(check "$r")
  assert "REQ-F1.3: a matching count passes in $surface" 0 $?

  lines_of "$MISMATCH_LINES" >"$r/$surface"
  git -C "$r" add -- "$surface"
  out=$(check "$r")
  assert "REQ-F1.3: a mismatched count fails in $surface" 1 $?
  assert_contains "REQ-F1.3: the finding names $surface" "$out" "$surface"
  assert_contains "REQ-F1.3: the finding states both numbers in $surface" "$out" "states 4, lists 3"
done

# REQ-F1.3: a bundle at Ready, Active, or Done is skipped; the same bundle at
# Draft is checked.
r="$tmp/signed"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
bundle "$r" ready-one Ready
bundle "$r" active-one Active
bundle "$r" done-one Done
out=$(check "$r")
assert "REQ-F1.3: Ready, Active, and Done bundles are skipped" 0 $?
assert_not_contains "REQ-F1.3: no signed bundle is reported" "$out" "specs/"
bundle "$r" draft-one Draft
out=$(check "$r")
assert "REQ-F1.3: the same mismatch in a Draft bundle fails" 1 $?
assert_contains "REQ-F1.3: the Draft bundle's file is named" "$out" "specs/draft-one/design.md"

# Numerals, tables, and nested lists.
r="$tmp/shapes"
make_repo "$r"
put "$r" doctrine/table.md "It keeps 2 columns:" "" \
  "| a | b |" "| --- | --- |" "| 1 | 2 |" "| 3 | 4 |" "| 5 | 6 |"
put "$r" doctrine/nested.md "The scaffold offers two templates:" "" \
  "- first" "  - a detail of the first" "  - another detail" "" \
  "  A continuation paragraph of the first." "- second" "" "Closing prose."
put "$r" doctrine/item.md "- **Facet.** It offers two things:" \
  "  - the first" "  - the second" "  - the third"
out=$(check "$r")
assert "a numeral, a table, and a nested lead are each checked" 1 $?
assert_contains "a table counts its body rows" "$out" "doctrine/table.md"
assert_contains "the table finding states both numbers" "$out" "states 2, lists 3"
assert_not_contains "a nested list counts its top level only" "$out" "doctrine/nested.md"
assert_contains "a list item can lead a sub-list" "$out" "doctrine/item.md"

# Prose that states no count, two counts, or a reference number is not read as
# a count, and code is not prose.
r="$tmp/quiet"
make_repo "$r"
put "$r" doctrine/quiet.md \
  "The parts:" "- a" "" \
  "Between two and five of these:" "- a" "" \
  "Task 2 wired these guards:" "- a" "" \
  "It uses two-space indentation:" "- a" "" \
  'The `three` word is code here:' "- a" "" \
  "One sentence names three things. The next one leads the list:" "- a" "" \
  '```' "Three lines:" "- a" '```'
out=$(check "$r")
assert "prose without a single plain count is not checked" 0 $?

# Untracked files are not read.
r="$tmp/untracked"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
lines_of "$MISMATCH_LINES" >"$r/doctrine/scratch.md"
out=$(check "$r")
assert "an untracked file is not read" 0 $?

# Exemptions: a row clears its finding, and a row matching no finding fails.
r="$tmp/exempt"
make_repo "$r"
mkdir -p "$r/doctrine"
lines_of "$MISMATCH_LINES" >"$r/doctrine/x.md"
git -C "$r" add doctrine/x.md
printf 'doctrine/x.md\treads four inputs\tthe fourth is named in the prose above\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "an exemption row clears its finding" 0 $?
printf 'doctrine/x.md\tno such sentence\tstale\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "a stale exemption fails" 1 $?
assert_contains "the stale exemption is named" "$out" "no such sentence"
printf 'malformed row\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "a malformed exemption row fails closed" 2 $?

# Fail closed: no repository, nothing in scope, an unreadable exemption list.
mkdir -p "$tmp/plain"
out=$(/bin/bash "$CHECKER" --exempt "$tmp/exempt/exempt.tsv" "$tmp/plain" 2>&1)
assert "a root that is not a git work tree fails closed" 2 $?
make_repo "$tmp/empty"
out=$(check "$tmp/empty")
assert "a scan reaching no files fails closed" 2 $?
assert_contains "the empty scan says so" "$out" "no files"
out=$(/bin/bash "$CHECKER" --exempt "$tmp/nope.tsv" "$tmp/shapes" 2>&1)
assert "an unreadable exemption list fails closed" 2 $?
out=$(/bin/bash "$CHECKER" --bogus 2>&1)
assert "an unknown option is a usage error" 2 $?

# The shipped tree is green under the shipped exemption list.
out=$(/bin/bash "$CHECKER" 2>&1)
rc=$?
assert "this repository's tracked prose is green" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "PASS: check-counts"
