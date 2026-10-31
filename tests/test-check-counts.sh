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
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

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

check() { /bin/sh "$CHECKER" --exempt "$1/exempt.tsv" "$1" </dev/null 2>&1; }

# three_inputs <repo> <path> <stated>: an introducing sentence stating the
# count over a three-item list.
three_inputs() {
  put "$1" "$2" "The guard reads $3 inputs:" "- the first" "- the second" "- the third"
}

# REQ-F1.3: a matching count passes and a mismatched one fails, in every
# surface the guard covers.
for surface in doctrine/rule.md skills/demo/SKILL.md docs/guide.md \
  specs/_pending/note.md specs/drafted/design.md; do
  r="$tmp/match-$(printf '%s' "$surface" | tr '/.' '__')"
  make_repo "$r"
  put "$r" specs/drafted/requirements.md "# drafted" "" "**Status:** Draft"
  three_inputs "$r" "$surface" three
  out=$(check "$r")
  assert "REQ-F1.3: a matching count passes in $surface" 0 $?

  three_inputs "$r" "$surface" four
  out=$(check "$r")
  assert "REQ-F1.3: a mismatched count fails in $surface" 1 $?
  assert_contains "REQ-F1.3: the finding names the file, line and both numbers in $surface" \
    "$out" "$surface:1: states 4, lists 3"
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

# expect_count <name> <stated> <listed> <path> <line>...: the lines, alone in a
# repository, fail naming the path and both numbers.
expect_count() {
  e_r="$tmp/$1" e_want="states $2, lists $3" e_path=$4
  shift 4
  make_repo "$e_r"
  put "$e_r" "$e_path" "$@"
  out=$(check "$e_r")
  assert "a mismatch is found in $e_path" 1 $?
  assert_contains "the finding in $e_path reads: $e_want" "$out" "$e_path:"
  assert_contains "the finding in $e_path states: $e_want" "$out" "$e_want"
}

# expect_quiet <name> <line>...: the lines, alone in doctrine/, are not a finding.
expect_quiet() {
  q_name=$1 q_r="$tmp/$1"
  shift
  make_repo "$q_r"
  put "$q_r" doctrine/quiet.md "$@"
  out=$(check "$q_r")
  assert "not read as a mismatch: $q_name" 0 $?
}

expect_count table 2 3 doctrine/table.md "It keeps 2 columns:" "" \
  "| a | b |" "| --- | --- |" "| 1 | 2 |" "| 3 | 4 |" "| 5 | 6 |"
expect_count item-lead 2 3 doctrine/item.md "- **Facet.** It offers two things:" \
  "  - the first" "  - the second" "  - the third"
expect_count eleven 11 2 doctrine/eleven.md "It has eleven parts:" "- a" "- b"
expect_count closed-fence 2 1 doctrine/fence.md '```sh' "Three lines:" "- a" '```' \
  "Two parts:" "- a"
expect_count long-fence 2 3 doctrine/long.md '````md' '```sh' "Five items:" '```' "- a" '````' \
  "Two parts:" "- a" "- b" "- c"
expect_count heading-stop 3 2 doctrine/head.md "Three parts:" "- a" "- b" "## Next" "- c"
expect_count break-stop 3 2 doctrine/break.md "Three rules:" "- a" "- b" "" "* * *"
expect_count link 2 1 doctrine/link.md "See [the doc](a.b.md#x) for two items:" "- a"
expect_count abbreviation 2 3 doctrine/abbr.md "Three devs. Here are two items:" "- a" "- b" "- c"
expect_count one-row-table 2 1 doctrine/one.md "A table of two rows:" "| x |" "---"
expect_count paren-cut 2 3 doctrine/paren.md "Two files hold this (see the guide. It is long):" "- a" "- b" "- c"
expect_count wrapped 3 2 doctrine/w.md "The guard reads three" "inputs:" "- a" "- b"
assert_contains "a wrapped sentence is reported on its last line" "$out" "doctrine/w.md:2:"
expect_count inline-span 3 2 doctrine/span.md '```x``` is a span.' "" "Three items:" "- a" "- b"
expect_quiet aligned-table "It keeps 2 rows:" "" "| a | b |" "| :--- | ---: |" "| 1 | 2 |" "| 3 | 4 |"
expect_quiet short-delimiter "Three rows:" "" "| a |" "|:-:|" "| 1 |" "| 2 |" "| 3 |"
expect_count paren-end 3 2 doctrine/pend.md "Run two passes (the second is the check.) The guard has three inputs:" "- a" "- b"
expect_quiet bare-pipe-table "It keeps two rows:" "| a" "| ---" "| 1" "| 2"
expect_count mid-paren-question 3 2 doctrine/mq.md "The checker asks three questions (is it fresh? is it signed?) before it runs:" "- a" "- b"
expect_count mid-paren-ellipsis 3 2 doctrine/me.md "Three read-only commands (ls, cat, ...) run without a prompt:" "- a" "- b"
expect_quiet paren-end-code 'Run two passes (the second is the check.) `check` takes these inputs:' "- a" "- b" "- c"
expect_count paren-ellipsis-end 3 2 doctrine/pe.md "Three tools (ls, cat, ...) The guard keeps these:" "- a" "- b"
expect_count paren-emph-lower 3 2 doctrine/pl.md "Three rules apply *(see the note.)* to these files:" "- a" "- b"
expect_count paren-quote-lower 3 2 doctrine/pq.md 'Three labels appear, "(On-demand lane.)" for lane one, in these places:' "- a" "- b"
expect_count reference-plural 2 1 doctrine/ref.md "Two parts follow Task 12 rules:" "- a"

expect_quiet nested "The scaffold offers two templates:" "" \
  "- first" "  - a detail of the first" "  - another detail" "" \
  "  A continuation paragraph of the first." "- second" "" "Closing prose."
expect_quiet no-count "The parts:" "- a"
expect_quiet two-counts "Between two and five of these:" "- a"
expect_quiet task-reference "Task 12 lands these guards:" "- a"
expect_quiet pr-reference "Since PR 408 fixes these:" "- a" "- b"
expect_quiet low-numeral "The 1 rules:" "- a" "- b"
expect_quiet hyphenated "It uses two-space indentation:" "- a"
expect_quiet code-span 'The `three` word is code here:' "- a"
expect_quiet parenthetical "These (the last 16 chars) apply:" "- a"
expect_quiet earlier-sentence "One sentence names three things. The next leads the list:" "- a"
expect_quiet fenced '```' "Three lines:" "- a" '```'
expect_quiet sibling "- **Facet.** It offers two things:" "- next" "- other" "- last"

# Untracked files are not read, and a tracked file removed from the work tree
# is not either.
r="$tmp/untracked"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
three_inputs "$r" doctrine/gone.md four
rm "$r/doctrine/gone.md"
mkdir -p "$r/doctrine"
printf '%s\n' "The guard reads four inputs:" "- a" >"$r/doctrine/scratch.md"
out=$(check "$r")
assert "untracked and removed files are not read" 0 $?

# Exemptions: a row clears its own file's finding only, a row matching no
# finding fails, and an excerpt may carry an abbreviation.
r="$tmp/exempt"
make_repo "$r"
three_inputs "$r" doctrine/x.md four
three_inputs "$r" doctrine/y.md four
printf 'doctrine/x.md\treads four inputs\tthe fourth is named in the prose above\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "an exemption clears only its own file" 1 $?
assert_contains "the unexempted twin is still reported" "$out" "doctrine/y.md:1:"
assert_not_contains "the exempted file is cleared" "$out" "doctrine/x.md:1:"
put "$r" doctrine/y.md "Pick, e.g. by hand, two things:" "- a"
printf 'doctrine/y.md\te.g. by hand, two things\tthe second is implied\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "an excerpt carrying an abbreviation clears its finding" 0 $?
printf 'doctrine/x.md\tno such sentence\tstale\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "a stale exemption fails" 1 $?
assert_contains "the stale exemption is named" "$out" "no such sentence"
cp "$r/exempt.tsv" "$r/exempt.bak"
printf 'doctrine/x.md\treads four inputs\ta repeat\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "a repeated exemption row fails closed" 2 $?
cp "$r/exempt.bak" "$r/exempt.tsv"
printf 'malformed row\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "a malformed exemption row fails closed" 2 $?

# One exemption row clears one finding: a second sentence sharing its excerpt
# is reported, not silently cleared with the first.
r="$tmp/exempt-twice"
make_repo "$r"
put "$r" doctrine/x.md "The guard reads four inputs:" "- a" "- b" "- c" "" \
  "Later it reads four inputs:" "- a" "- b"
printf 'doctrine/x.md\treads four inputs\tthe fourth is named in the prose above\n' >>"$r/exempt.tsv"
out=$(check "$r")
assert "an exemption row matching two findings fails" 1 $?
assert_contains "the over-broad exemption is named" "$out" "clears more than one finding"

# A Draft bundle whose requirements.md is not committed yet is read by its
# siblings' status, so it is still checked.
r="$tmp/no-req"
make_repo "$r"
put "$r" doctrine/ok.md "Prose."
put "$r" specs/partial/design.md "# Design" "" "**Status:** Draft" "" \
  "The decision has three parts:" "" "- one" "- two"
out=$(check "$r")
assert "a Draft bundle without requirements.md is checked" 1 $?
assert_contains "its sibling's mismatch is reported" "$out" "specs/partial/design.md:5:"
put "$r" specs/partial/design.md "# Design" "" "**Status:** Ready" "" \
  "The decision has three parts:" "" "- one" "- two"
out=$(check "$r")
assert "a Ready bundle without requirements.md is still skipped" 0 $?

# The guard never reads stdin: a caller's input stays unread.
r="$tmp/stdin"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
left=$(printf 'kept\n' | {
  /bin/sh "$CHECKER" --exempt "$r/exempt.tsv" "$r" >/dev/null 2>&1
  IFS= read -r l
  printf '%s' "$l"
})
assert_contains "stdin is left to the caller" "$left" "kept"

# An inherited GIT_DIR does not redirect the scan away from <root>.
r="$tmp/gitdir"
make_repo "$r"
three_inputs "$r" doctrine/x.md four
make_repo "$tmp/decoy"
put "$tmp/decoy" doctrine/clean.md "Nothing to count here."
out=$(GIT_DIR="$tmp/decoy/.git" /bin/sh "$CHECKER" --exempt "$r/exempt.tsv" "$r" </dev/null 2>&1)
assert "an inherited GIT_DIR is ignored" 1 $?

# Fail closed: no repository, nothing in scope, an unreadable file or
# exemption list, an unparseable Draft candidate, a name holding a newline.
mkdir -p "$tmp/plain"
out=$(/bin/sh "$CHECKER" --exempt "$tmp/exempt/exempt.tsv" "$tmp/plain" </dev/null 2>&1)
assert "a root that is not a git work tree fails closed" 2 $?
make_repo "$tmp/empty"
out=$(check "$tmp/empty")
assert "a scan reaching no files fails closed" 2 $?
assert_contains "the empty scan says so" "$out" "no files"
out=$(/bin/sh "$CHECKER" --exempt "$tmp/nope.tsv" "$tmp/untracked" </dev/null 2>&1)
assert "an unreadable exemption list fails closed" 2 $?
out=$(/bin/sh "$CHECKER" --bogus </dev/null 2>&1)
assert "an unknown option is a usage error" 2 $?

r="$tmp/unparsed"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
put "$r" specs/broken/requirements.md "# broken" "" "**Status:** Draft" "**Status:** Ready"
put "$r" specs/broken/design.md "Nothing."
out=$(check "$r")
assert "a bundle whose status cannot be parsed fails closed" 2 $?

r="$tmp/newline"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
put "$r" "doctrine/we
ird.md" "Two things:" "- a"
out=$(check "$r")
assert "a tracked name holding a newline fails closed" 2 $?

r="$tmp/unreadable"
make_repo "$r"
put "$r" doctrine/locked.md "Nothing to count here."
chmod 000 "$r/doctrine/locked.md"
if [ -r "$r/doctrine/locked.md" ]; then
  echo "ok: skipped the unreadable-file case: the running user reads mode-000 files"
else
  out=$(check "$r")
  assert "an unreadable tracked file fails closed" 2 $?
fi
chmod 644 "$r/doctrine/locked.md"

# A tracked symlink is refused rather than followed out of the tree, and
# printed text loses its 8-bit control bytes.
r="$tmp/symlink"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
printf '%s\n' "The three tokens SECRET:" "- a" >"$tmp/outside.md"
ln -s "$tmp/outside.md" "$r/doctrine/leak.md"
git -C "$r" add doctrine/leak.md
out=$(check "$r")
assert "a tracked symlink fails closed" 2 $?
assert_not_contains "nothing behind the symlink is printed" "$out" "SECRET"
r="$tmp/c1"
make_repo "$r"
put "$r" doctrine/c1.md "$(printf 'The three \302\233tokens:')" "- a"
out=$(check "$r")
assert "a mismatch carrying a C1 control byte is reported" 1 $?
case "$out" in
  *"$(printf '\233')"*)
    echo "FAIL: a C1 control byte reached the output" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: C1 control bytes are stripped from the output" ;;
esac

# A CRLF file is read like an LF one.
r="$tmp/crlf"
make_repo "$r"
mkdir -p "$r/doctrine"
printf 'Three parts:\r\n- a\r\n- b\r\n' >"$r/doctrine/crlf.md"
git -C "$r" add doctrine/crlf.md
out=$(check "$r")
assert "a CRLF file's mismatch is found" 1 $?
assert_contains "the CRLF finding states both numbers" "$out" "states 3, lists 2"

# A bundle's requirements.md reached through a symlink is refused, whatever
# status it names.
r="$tmp/req-link"
make_repo "$r"
put "$r" doctrine/clean.md "Nothing to count here."
printf '%s\n' "# x" "" "**Status:** Ready" >"$tmp/outside-req.md"
mkdir -p "$r/specs/linked"
ln -s "$tmp/outside-req.md" "$r/specs/linked/requirements.md"
git -C "$r" add specs/linked/requirements.md
put "$r" specs/linked/design.md "Nothing."
out=$(check "$r")
assert "a symlinked requirements.md fails closed" 2 $?

# The shipped tree is green under the shipped exemption list.
out=$(/bin/sh "$CHECKER" </dev/null 2>&1)
rc=$?
assert "this repository's tracked prose is green" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "PASS: check-counts"
