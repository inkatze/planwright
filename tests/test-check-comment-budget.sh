#!/bin/bash
# Tests for scripts/check-comment-budget.sh. Sections follow the guard's
# coverage list in the prose-disposition bundle (REQ-F1.9), then the wiring,
# the audit reproduction, and the real tree.
# shellcheck disable=SC2016 # fixture and workflow text is matched literally
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GUARD="$REPO_ROOT/scripts/check-comment-budget.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3): $(head -n 5 "$TMP/out")"; fi
}
assert_out() {
  if grep -qF -e "$2" "$TMP/out"; then ok "$1"; else fail "$1 (no '$2' in: $(head -n 5 "$TMP/out"))"; fi
}
refute_out() {
  if grep -qF -e "$2" "$TMP/out"; then fail "$1 ('$2' found)"; else ok "$1"; fi
}

if [ ! -x "$GUARD" ]; then
  echo "FAIL: $GUARD missing or not executable" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Hermetic configuration: only the fixture's own layers resolve, and a
# machine-local overlay on this host never reaches the real-tree runs.
export CLAUDE_PLUGIN_ROOT="" CLAUDE_PLUGIN_DATA="" PLANWRIGHT_ROOT=""
export PLANWRIGHT_LOCAL_CONFIG="$TMP/no-local.yml" PLANWRIGHT_ADOPTER_OVERLAY="$TMP/no-adopter"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# comments <n>: n comment lines.
comments() {
  local i=0
  while [ "$i" -lt "$1" ]; do
    printf '# line %d\n' "$i"
    i=$((i + 1))
  done
}

# mkrepo <dir> [warn error]: a git fixture with the two knobs and nothing else.
mkrepo() {
  local r=$1
  mkdir -p "$r/config" "$r/scripts"
  printf 'comment_block_warn: %s\ncomment_block_error: %s\n' "${2:-12}" "${3:-25}" >"$r/config/defaults.yml"
  git init -q "$r"
}

track() { git -C "$1" add -A; }

# mkscript <file> <block lines>: a script whose one block has that many lines.
mkscript() {
  mkdir -p "$(dirname "$1")"
  {
    printf '#!/bin/sh\n'
    comments "$2"
    printf 'echo hi\n'
  } >"$1"
}

run() {
  local r=$1
  shift
  "$GUARD" --root "$r" "$@" >"$TMP/out" 2>&1
}

echo "## threshold arithmetic and boundary inclusivity"
r="$TMP/thresh"
mkrepo "$r"
mkscript "$r/scripts/at-warn.sh" 12
mkscript "$r/scripts/below-warn.sh" 11
mkscript "$r/scripts/below-error.sh" 24
track "$r"
run "$r"
assert_exit "warnings alone leave the exit zero" 0 $?
assert_out "a block exactly at warn warns" "WARN: scripts/at-warn.sh:2: a 12-line comment block"
refute_out "a block one below warn does not" "below-warn.sh"
assert_out "a block one below error only warns" "WARN: scripts/below-error.sh:2: a 24-line"
mkscript "$r/scripts/at-error.sh" 25
track "$r"
run "$r"
assert_exit "a block exactly at error fails" 1 $?
assert_out "the error names the file and starting line" "ERROR: scripts/at-error.sh:2: a 25-line comment block"

echo "## shebang exclusion"
r="$TMP/shebang"
mkrepo "$r"
{
  printf '#!/bin/sh\n'
  comments 11
  printf 'x=1\n'
} >"$r/scripts/a.sh"
{
  printf 'cat <<EOF\n#!/bin/sh\n'
  comments 11
  printf 'EOF\n'
} >"$r/scripts/b.sh"
track "$r"
run "$r"
assert_exit "a shebang is not a comment line" 0 $?
refute_out "neither file reaches 12 lines with its shebang excluded" "WARN"

echo "## run-breaking on blank and code lines"
r="$TMP/runs"
mkrepo "$r"
{
  comments 6
  printf '\n'
  comments 6
  printf 'x=1\n'
  comments 6
  printf '  # indented\n'
} >"$r/scripts/a.sh"
track "$r"
run "$r"
assert_exit "short runs pass" 0 $?
refute_out "a blank line and a code line each end a run" "WARN"
{
  comments 11
  printf '\t# a tab-indented comment line continues the run\n'
} >"$r/scripts/a.sh"
run "$r"
assert_out "leading whitespace before # is still a comment line" "WARN: scripts/a.sh:1: a 12-line"

echo "## heredoc limit"
r="$TMP/heredoc"
mkrepo "$r"
{
  printf '#!/bin/sh\ncat <<EOF\n'
  comments 25
  printf 'EOF\n'
} >"$r/scripts/template.sh"
track "$r"
run "$r"
assert_exit "a heredoc body of # lines counts as a comment block, as documented" 1 $?
assert_out "the heredoc block is reported" "ERROR: scripts/template.sh:3: a 25-line"
"$GUARD" --help >"$TMP/out" 2>&1
assert_out "the usage text names the heredoc limit" "a heredoc body line"

echo "## surface and its exclusions"
r="$TMP/surface"
mkrepo "$r"
for f in scripts/a.sh scripts/sub/b.sh tests/c.sh tests/lib/d.sh githooks/e.sh hooks/f.sh; do
  mkscript "$r/$f" 25
done
mkscript "$r/githooks/pre-commit" 25
mkdir -p "$r/.github/workflows" "$r/docs"
for f in config/g.yml config/h.yaml lefthook.yml mise.toml .github/workflows/ci.yml .github/workflows/x.yaml; do
  mkdir -p "$(dirname "$r/$f")"
  {
    comments 25
    printf 'key: value\n'
  } >"$r/$f"
done
for f in docs/out.sh config/list.txt config/x.json scripts/notes.txt githooks/README lefthook.yaml specs/s.sh; do
  mkdir -p "$(dirname "$r/$f")"
  {
    comments 25
    printf 'x\n'
  } >"$r/$f"
done
track "$r"
mkscript "$r/scripts/untracked.sh" 25
run "$r"
assert_exit "the surface errors" 1 $?
for f in scripts/a.sh scripts/sub/b.sh tests/c.sh tests/lib/d.sh githooks/e.sh hooks/f.sh githooks/pre-commit \
  config/g.yml config/h.yaml lefthook.yml mise.toml .github/workflows/ci.yml .github/workflows/x.yaml; do
  assert_out "$f is measured" "ERROR: $f:"
done
for f in docs/out.sh config/list.txt config/x.json scripts/notes.txt githooks/README lefthook.yaml specs/s.sh scripts/untracked.sh; do
  refute_out "$f is outside the surface" "$f:"
done

echo "## suppression forms"
r="$TMP/supp"
mkrepo "$r"
mkscript "$r/scripts/big.sh" 30
mkscript "$r/scripts/pending.sh" 30
mkscript "$r/scripts/clean.sh" 3
track "$r"
exempt="$r/config/comment-budget-exemptions.txt"
printf '# header\n\nexempt|scripts/big.sh|a usage section with no other home\npending-cleanup|scripts/pending.sh|Task 8|over at landing\n' >"$exempt"
run "$r"
assert_exit "exempt and pending-cleanup entries suppress their files" 0 $?
refute_out "no cleanup warning for files still over" "cleanup:"
printf 'pending-cleanup|scripts/clean.sh|Task 6|over at landing\nexempt|scripts/gone.sh|was over\n' >>"$exempt"
run "$r"
assert_exit "a stale entry is a warning, never an error" 0 $?
assert_out "the stale pending entry is named" "WARN: cleanup: scripts/clean.sh trips no threshold; remove its pending-cleanup entry"
assert_out "an entry for a missing file is named" "WARN: cleanup: scripts/gone.sh trips no threshold; remove its exempt entry"
for bad in 'exempt|scripts/clean.sh|' 'exempt|scripts/clean.sh|   ' 'pending-cleanup|scripts/clean.sh|Task 6|' \
  'exempt|scripts/clean.sh' 'pending-cleanup|scripts/clean.sh|reason only' 'pending-cleanup|scripts/clean.sh|Phase 6|why' \
  'allow|scripts/clean.sh|why' 'exempt||why' 'exempt| scripts/clean.sh|why'; do
  printf 'exempt|scripts/big.sh|own surface\npending-cleanup|scripts/pending.sh|Task 8|over\n%s\n' "$bad" >"$exempt"
  run "$r"
  rc=$?
  assert_exit "a reason-less or malformed entry fails loud: $bad" 1 "$rc"
  assert_out "the malformed entry is reported with its line" "ERROR: config/comment-budget-exemptions.txt:3:"
done
printf 'exempt|scripts/big.sh|one\nexempt|scripts/big.sh|two\npending-cleanup|scripts/pending.sh|Task 7|x\n' >"$exempt"
run "$r"
assert_exit "a second entry for one path fails" 1 $?
assert_out "the duplicate is named" "a second entry for scripts/big.sh"
printf 'exempt|scripts/big.sh|a reason | with a pipe\npending-cleanup|scripts/pending.sh|Task 7.5|over\n' >"$exempt"
run "$r"
assert_exit "a reason may hold a pipe and a task id a point" 0 $?

echo "## closeout"
printf 'exempt|scripts/big.sh|own surface\npending-cleanup|scripts/pending.sh|Task 8|over\npending-cleanup|scripts/clean.sh|Task 6|over\n' >"$exempt"
run "$r" --closeout
assert_exit "--closeout fails on pending-cleanup entries" 1 $?
assert_out "a still-over pending file errors under closeout" "pending-cleanup entry for scripts/pending.sh under --closeout"
assert_out "an already-clean pending file errors under closeout too" "pending-cleanup entry for scripts/clean.sh under --closeout"
refute_out "an exempt entry is not a closeout error" "scripts/big.sh"
printf 'exempt|scripts/big.sh|own surface\nexempt|scripts/pending.sh|own surface\n' >"$exempt"
run "$r" --closeout
assert_exit "--closeout passes with only exempt entries" 0 $?

echo "## audit output shape and its block floor"
r="$TMP/audit"
mkrepo "$r"
{
  printf '#!/bin/sh\n# a lone comment line is not a block\nx=1\n'
  printf '# per REQ-A1.1 and D-9\n# the second line\n# the third line\n\n'
  printf '# kept because the order matters\n# otherwise it races\nx=2\n'
  printf '# just restating\n# what follows\n# here and\n# there\ny=3\n'
} >"$r/scripts/a.sh"
mkscript "$r/scripts/b.sh" 30
track "$r"
run "$r" --audit
assert_exit "--audit exits zero" 0 $?
grep '^file' "$TMP/out" >"$TMP/files"
if [ "$(head -n 1 "$TMP/files" | cut -f 8)" = scripts/b.sh ] && [ "$(sed -n 2p "$TMP/files" | cut -f 8)" = scripts/a.sh ]; then
  ok "file rows are ranked by largest block"
else
  fail "file rows are not ranked by largest block: $(cat "$TMP/files")"
fi
if [ "$(sed -n 2p "$TMP/files" | cut -f 2-7)" = "$(printf '4\t11\t3\t9\t10\t4')" ]; then
  ok "a file row carries largest, start, blocks, block lines, comment lines, code lines"
else
  fail "unexpected file row: $(sed -n 2p "$TMP/files")"
fi
grep -c '^block' "$TMP/out" >"$TMP/n"
if [ "$(cat "$TMP/n")" -eq 4 ]; then ok "a one-line comment is not a block"; else fail "expected 4 block rows, got $(cat "$TMP/n")"; fi
assert_out "a block citing ids is classed cites" "$(printf 'block\t3\t10\tcites\tscripts/a.sh:4')"
assert_out "a block with rationale language is classed rationale" "$(printf 'block\t2\t8\trationale\tscripts/a.sh:8')"
assert_out "a block with neither is evidence-free" "$(printf 'block\t4\t7\tnone\tscripts/a.sh:11')"
assert_out "the corpus counts blocks of two or more lines" "$(printf 'total\tblocks\t4')"
assert_out "the corpus counts block lines" "$(printf 'total\tblock_lines\t39')"
assert_out "blocks at the error threshold are counted" "$(printf 'total\tblocks_at_error\t1')"
assert_out "the largest block is named" "$(printf 'total\tlargest\t30\tscripts/b.sh:2')"
assert_out "class totals are emitted" "$(printf 'total\tnone_blocks\t2')"
mkdir -p "$TMP/tree/scripts"
cp "$r/scripts/a.sh" "$TMP/tree/scripts/"
run "$r" --audit "$TMP/tree"
assert_out "--audit <tree> measures an untracked tree" "$(printf 'total\tfiles\t1')"
mkdir -p "$TMP/classes/scripts"
printf '%s\n' 'x=0' '# see Task 7' '# here' 'x=1' '# obs:a81cee76 noted' '# again' 'x=2' \
  '# build XD-9 here' '# and more' 'x=3' '# REQ-A1.1 because' '# both' 'x=4' '#' '# word ' 'x=5' \
  '# keep it so that callers work' '# y' 'x=6' >"$TMP/classes/scripts/c.sh"
printf 'x\n# solo\ny\n' >"$TMP/classes/scripts/d.sh"
run "$r" --audit "$TMP/classes/"
assert_exit "--audit <tree/> with a trailing slash runs" 0 $?
assert_out "a task id alone is a citation" "$(printf 'block\t2\t4\tcites\tscripts/c.sh:2')"
assert_out "an observation id alone is a citation" "$(printf 'block\t2\t3\tcites\tscripts/c.sh:5')"
assert_out "D-<n> inside a word is not a citation" "$(printf 'block\t2\t5\tnone\tscripts/c.sh:8')"
assert_out "a citation wins over rationale language" "$(printf 'block\t2\t3\tcites\tscripts/c.sh:11')"
assert_out "a one-word block counts one word" "$(printf 'block\t2\t1\tnone\tscripts/c.sh:14')"
assert_out "a phrase alone is rationale language" "$(printf 'block\t2\t7\trationale\tscripts/c.sh:17')"
assert_out "a lone comment line is no file's largest block" "$(printf 'file\t0\t0\t0\t0\t1\t2\tscripts/d.sh')"

echo "## code invariance"
r="$TMP/inv"
mkrepo "$r"
printf '#!/bin/sh\n# why\nx=1\n\ny=2\n' >"$r/scripts/a.sh"
printf '# doc\n' >"$r/README.md"
track "$r"
git -C "$r" commit -qm base
git -C "$r" branch -q base
printf '#!/bin/sh\n# a new why\n# over two lines\nx=1\ny=2\n\n' >"$r/scripts/a.sh"
printf 'prose\n' >"$r/README.md"
run "$r" --code-invariant base
assert_exit "comment and blank changes pass" 0 $?
printf '#!/bin/sh\nx=1\ny=3\n' >"$r/scripts/a.sh"
run "$r" --code-invariant base
assert_exit "a changed code line fails" 1 $?
assert_out "the changed file is named" "code changed: scripts/a.sh"
git -C "$r" checkout -q -- scripts/a.sh
mkscript "$r/scripts/new.sh" 1
run "$r" --code-invariant base
assert_exit "an added surface file fails" 1 $?
assert_out "the added file is named" "code changed: scripts/new.sh (added"
git -C "$r" add scripts/new.sh
run "$r" --code-invariant base
assert_exit "a staged added surface file fails" 1 $?
git -C "$r" rm -q -f scripts/new.sh
git -C "$r" rm -q scripts/a.sh
run "$r" --code-invariant base
assert_exit "a deleted surface file fails" 1 $?
assert_out "the deleted file is named" "code changed: scripts/a.sh (deleted"
git -C "$r" reset -q --hard
mkdir -p "$r/sub"
run "$r/sub" --code-invariant base
assert_exit "a root below the top level is refused, not passed vacuously" 2 $?
git -C "$r" checkout -q -b feature
printf '#!/bin/sh\n# feature comment\nx=1\n\ny=2\n' >"$r/scripts/a.sh"
git -C "$r" commit -qam feature
git -C "$r" checkout -q base
printf '#!/bin/sh\n# why\nx=10\n\ny=2\n' >"$r/scripts/a.sh"
git -C "$r" commit -qam "code on base"
git -C "$r" checkout -q feature
run "$r" --code-invariant base
assert_exit "a code change on the base after the branch point does not fail the branch" 0 $?
run "$r" --code-invariant no-such-ref
assert_exit "an unresolvable ref fails closed" 2 $?
run "$r" --code-invariant --upload-pack=x
assert_exit "a ref shaped like an option is refused" 2 $?

echo "## knob resolution and the fail-loud abort"
r="$TMP/knobs"
mkrepo "$r"
mkscript "$r/scripts/a.sh" 5
track "$r"
run "$r"
assert_exit "the default knobs resolve" 0 $?
refute_out "five lines are under the default warn" "WARN"
mkdir -p "$r/.claude"
printf 'comment_block_warn: 5\n' >"$r/.claude/planwright.yml"
run "$r"
assert_out "a repo-tracked overlay value overrides the default" "WARN: scripts/a.sh:2: a 5-line comment block (warn threshold 5)"
rm "$r/.claude/planwright.yml"
printf 'comment_block_warn: 12\n' >"$r/config/defaults.yml"
run "$r"
assert_exit "a missing knob aborts" 2 $?
assert_out "the abort names the knob" "comment_block_error"
printf 'comment_block_warn: 12\ncomment_block_error: lots\n' >"$r/config/defaults.yml"
run "$r"
assert_exit "a non-numeric knob aborts" 2 $?
printf 'comment_block_warn: 0\ncomment_block_error: 25\n' >"$r/config/defaults.yml"
run "$r"
assert_exit "a zero knob aborts" 2 $?
printf 'comment_block_warn: 30\ncomment_block_error: 25\n' >"$r/config/defaults.yml"
run "$r"
assert_exit "warn above error aborts" 2 $?

echo "## untrusted-input refusals"
r="$TMP/untrusted"
mkrepo "$r"
mkscript "$r/scripts/a.sh" 2
printf '#!/bin/sh\n# $(touch %s/pwned) `touch %s/pwned2`; rm -rf /\n# $HOME * ?\nx=1\n' "$TMP" "$TMP" >"$r/scripts/meta.sh"
track "$r"
printf 'exempt|../outside.sh|escape\nexempt|/etc/passwd|absolute\n' >"$r/config/comment-budget-exemptions.txt"
run "$r"
assert_exit "a path-traversal or absolute entry is an error" 1 $?
assert_out "the traversal entry is refused" "the path ../outside.sh leaves the root; refused"
assert_out "the absolute entry is refused" "the path /etc/passwd leaves the root; refused"
if [ -e "$TMP/pwned" ] || [ -e "$TMP/pwned2" ]; then fail "comment text was evaluated"; else ok "shell metacharacters in a comment are never evaluated"; fi
rm "$r/config/comment-budget-exemptions.txt"
run "$r" ../outside.sh
assert_exit "a path argument leaving the root is refused" 2 $?
mkdir -p "$TMP/outside"
mkscript "$TMP/outside/secret.sh" 30
ln -s "$TMP/outside/secret.sh" "$r/link"
run "$r" "$(printf 'scripts/a.sh\nlink')"
assert_exit "a path argument carrying a newline is refused" 2 $?
refute_out "the smuggled line is never measured" "link:"
rm "$r/link"
esc=$(printf 'x\033[31my')
mkscript "$r/scripts/$esc.sh" 25
track "$r"
run "$r"
assert_exit "a surface path carrying a control byte fails closed" 2 $?
if LC_ALL=C grep -q '[[:cntrl:]]' "$TMP/out"; then fail "a control byte reached the output"; else ok "the refusal carries no control byte"; fi
git -C "$r" rm -q --cached "scripts/$esc.sh"
mkdir -p "$TMP/esctree/scripts"
mkscript "$TMP/esctree/scripts/$esc.sh" 25
run "$r" --audit "$TMP/esctree"
assert_exit "--audit over a tree with an escape in a file name runs" 0 $?
if LC_ALL=C tr -d '\t\n' <"$TMP/out" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  fail "a control byte reached the audit output"
else
  ok "the audit output is stripped of control bytes"
fi
rm -f "$r/scripts/$esc.sh"
ln -s a.sh "$r/scripts/link.sh"
track "$r"
run "$r"
assert_exit "a symlinked surface file fails closed" 2 $?
git -C "$r" rm -q -f scripts/link.sh
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$r/githooks"
  mkscript "$r/githooks/pre-commit" 30
  track "$r"
  chmod 000 "$r/githooks/pre-commit"
  run "$r"
  assert_exit "an unreadable extensionless hook fails closed, never skipped" 2 $?
  chmod 644 "$r/githooks/pre-commit"
fi

echo "## a path mid-merge is measured once"
r="$TMP/conflict"
mkrepo "$r"
printf 'x\n' >"$r/scripts/c.sh"
track "$r"
git -C "$r" commit -qm base
git -C "$r" checkout -q -b one
printf 'y\n' >"$r/scripts/c.sh"
chmod 755 "$r/scripts/c.sh"
git -C "$r" commit -qam one
git -C "$r" checkout -q -
printf 'z\n' >"$r/scripts/c.sh"
git -C "$r" commit -qam two
git -C "$r" merge -q one >/dev/null 2>&1
if [ -n "$(git -C "$r" ls-files -u)" ]; then ok "the fixture is mid-merge"; else fail "the fixture merge did not conflict"; fi
run "$r"
assert_out "each conflict stage, whatever its mode, does not count as another file" "2 file(s) measured"

echo "## pre-commit scoping"
r="$TMP/scoped"
mkrepo "$r"
mkscript "$r/scripts/big.sh" 25
mkscript "$r/scripts/ok.sh" 3
printf 'x\n' >"$r/README.md"
track "$r"
run "$r" scripts/ok.sh README.md scripts/ok.sh
assert_exit "staged paths that are clean pass" 0 $?
assert_out "only the surface path is measured, once" "1 file(s) measured"
run "$r" scripts/big.sh
assert_exit "a staged path over the error threshold fails" 1 $?
run "$r" README.md
assert_exit "no surface path among the staged ones passes" 0 $?
utf=$(printf 'scripts/a\342\200\224b.sh')
mkscript "$r/$utf" 3
track "$r"
run "$r" "$utf"
assert_exit "a staged path with a multibyte character is measured, not refused" 0 $?
mkscript "$r/scripts/mid.sh" 15
track "$r"
printf 'pending-cleanup|scripts/big.sh|Task 8|over\nexempt|scripts/mid.sh|own surface\n' >"$r/config/comment-budget-exemptions.txt"
run "$r" scripts/big.sh scripts/mid.sh
assert_exit "a staged file its pending-cleanup entry covers passes" 0 $?
refute_out "an entry silences its file's warning too" "WARN: scripts/mid.sh"
rm "$r/config/comment-budget-exemptions.txt"

echo "## stdin is never read"
# A pre-commit hook runs with the terminal on stdin; a passing run must not wait on it.
mkfifo "$TMP/stdin"
sleep 120 >"$TMP/stdin" &
holder=$!
"$GUARD" --root "$r" scripts/ok.sh <"$TMP/stdin" >"$TMP/out" 2>&1 &
gpid=$!
i=0
while kill -0 "$gpid" 2>/dev/null && [ "$i" -lt 600 ]; do
  sleep 0.1
  i=$((i + 1))
done
if kill -0 "$gpid" 2>/dev/null; then
  fail "a passing run blocks on an open stdin"
  kill "$gpid" 2>/dev/null
else
  wait "$gpid"
  assert_exit "a passing run never waits on stdin" 0 $?
fi
kill "$holder" 2>/dev/null
wait 2>/dev/null

echo "## shipped defaults"
if grep -qx 'comment_block_warn: 12' "$REPO_ROOT/config/defaults.yml" && grep -qx 'comment_block_error: 25' "$REPO_ROOT/config/defaults.yml"; then
  ok "the shipped defaults are 12 and 25"
else
  fail "config/defaults.yml does not ship comment_block_warn 12 and comment_block_error 25"
fi
for k in comment_block_warn comment_block_error; do
  if grep -q "^| \`$k\` |" "$REPO_ROOT/docs/options-reference.md"; then ok "$k has an options-reference row"; else fail "$k has no options-reference row"; fi
done

echo "## the generated baseline"
if awk -F '|' '
  /^#/ || /^[ \t]*$/ { next }
  $1 != "pending-cleanup" { next }
  {
    want = 8
    if ($2 ~ /^scripts\/fleet-[^\/]*\.sh$/) want = 6
    else if ($2 ~ /^scripts\/(orchestrate|allocation|spec|release)-[^\/]*\.sh$/ ||
             $2 ~ /^scripts\/(tasks-pr-sync|main-currency|converge-sync-main|dispatch-fetch|offload-dispatch)\.sh$/) want = 7
    if ($3 != "Task " want) { print "wrong task for " $2 ": " $3; bad = 1 }
  }
  END { exit bad }' "$REPO_ROOT/config/comment-budget-exemptions.txt"; then
  ok "every pending-cleanup entry names the Phase B task whose family owns the file"
else
  fail "a pending-cleanup entry names the wrong task"
fi
for form in 'exempt|<path>|<reason>' 'pending-cleanup|<path>|Task <N>|<reason>'; do
  if grep -qF "$form" "$REPO_ROOT/config/comment-budget-exemptions.txt"; then
    ok "the suppression list header documents $form"
  else
    fail "the suppression list header does not document $form"
  fi
done

echo "## the guard header cites the rule doc"
if head -n 8 "$GUARD" | grep -q 'doctrine/comment-hygiene\.md'; then
  ok "the guard header cites doctrine/comment-hygiene.md"
else
  fail "the guard header does not cite doctrine/comment-hygiene.md"
fi

echo "## wiring"
if grep -q '^\[tasks."check:comment-budget"\]$' "$REPO_ROOT/mise.toml" \
  && grep -q '^  "check:comment-budget",$' "$REPO_ROOT/mise.toml"; then
  ok "check:comment-budget is defined and in the check aggregate"
else
  fail "check:comment-budget is not wired into the check aggregate in mise.toml"
fi
awk '/- name: comment-budget/ { on = 1; print; next } on && /- name:/ { exit } on' "$REPO_ROOT/lefthook.yml" >"$TMP/job"
if grep -qF 'run: /bin/sh scripts/check-comment-budget.sh {staged_files}' "$TMP/job"; then
  ok "the pre-commit job passes the staged paths"
else
  fail "lefthook.yml has no comment-budget job over {staged_files}"
fi
for g in '"scripts/*.sh"' '"tests/*.sh"' '"githooks/*"' '"hooks/*.sh"' '"config/*.{yml,yaml}"' \
  '"lefthook.yml"' '"mise.toml"' '".github/workflows/*.{yml,yaml}"'; do
  if grep -qF -- "- $g" "$TMP/job"; then ok "the pre-commit job globs $g"; else fail "the pre-commit job does not glob $g"; fi
done
ci="$REPO_ROOT/.github/workflows/ci.yml"
awk '/check-comment-budget.sh --code-invariant/ { print buf $0; exit } /^      - / { buf = "" } { buf = buf $0 "\n" }' "$ci" >"$TMP/step"
if grep -qF "if: github.event_name == 'pull_request'" "$TMP/step" \
  && grep -qF 'gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq .title' "$TMP/step" \
  && grep -qF '\(comments\)' "$TMP/step"; then
  ok "ci.yml runs --code-invariant in one PR-only step on comments-scoped titles, fetched live"
else
  fail "ci.yml lacks the PR-only comments-scoped --code-invariant step: $(cat "$TMP/step")"
fi
title_re=$(sed -n "s/.*grep -Eq '\([^']*\)'.*/\1/p" "$TMP/step")
for t in 'refactor(comments): x' 'fix(comments)!: x'; do
  if printf '%s\n' "$t" | grep -Eq "$title_re"; then ok "title '$t' runs the check"; else fail "title '$t' does not run the check"; fi
done
for t in 'docs: comments' 'chore(comments-x): y' 'feat(guards): comments'; do
  if printf '%s\n' "$t" | grep -Eq "$title_re"; then fail "title '$t' runs the check"; else ok "title '$t' does not run the check"; fi
done
if grep -qF 'github.event.pull_request.title' "$ci"; then
  fail "ci.yml reads the title from the event payload, which a rerun replays stale"
else
  ok "ci.yml never reads the title from the event payload"
fi

echo "## the audit reproduces the v0.36.0 headline figures"
if git -C "$REPO_ROOT" rev-parse -q --verify 'v0.36.0^{commit}' >/dev/null; then
  # The tag's scripts/ holds only top-level *.sh files; the files count pins that.
  # Knobs come from a root holding only the shipped defaults, so no overlay moves the threshold.
  mkdir -p "$TMP/v036" "$TMP/pinned/config"
  cp "$REPO_ROOT/config/defaults.yml" "$TMP/pinned/config/"
  git -C "$REPO_ROOT" archive v0.36.0 scripts/ | tar -x -C "$TMP/v036"
  "$GUARD" --root "$TMP/pinned" --audit "$TMP/v036" >"$TMP/out" 2>&1
  for want in 'files	128' 'blocks	2526' 'block_lines	20119' 'blocks_at_error	138' 'block_lines_at_error	8729'; do
    assert_out "v0.36.0 scripts/*.sh: ${want%%	*} ${want#*	}" "total	$want"
  done
else
  fail "the v0.36.0 tag is not in this clone; fetch tags to run the audit reproduction"
fi

echo "## the real tree"
"$GUARD" >"$TMP/out" 2>&1
real=$?
assert_exit "the real tree passes with the transitional baseline" 0 "$real"
mkdir -p "$TMP/own/scripts"
cp "$GUARD" "$TMP/own/scripts/"
"$GUARD" --audit "$TMP/own" >"$TMP/out" 2>&1
own=$(awk -F '\t' '$1 == "file" && $8 == "scripts/check-comment-budget.sh" { print $2 }' "$TMP/out")
if [ -n "$own" ] && [ "$own" -lt 12 ]; then
  ok "the guard's own largest block ($own lines) is under the warn threshold"
else
  fail "the guard's own largest block is not under the warn threshold: '$own'"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all comment-budget guard checks passed"
