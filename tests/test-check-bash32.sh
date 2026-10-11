#!/bin/sh
# Tests for scripts/check-bash32.sh, the bash 3.2 regression guards
# (test-throughput REQ-E1.6, REQ-E1.7).
#
# The misparse half needs a real bash 3.2: every later bash parses the
# fixtures under tests/fixtures/bash32/. When the bash on PATH is 3.2 (the CI
# step runs this file inside the bash:3.2 image), the parse cases run against
# it; elsewhere they skip, unless PLANWRIGHT_TEST_REQUIRE_BASH32=1 makes a
# missing 3.2 a failure, so the CI step cannot pass by skipping. Cases that
# read the repository's own tracked files or history need git and skip
# without it (the image has none); `mise run check` runs them.
#
# shellcheck disable=SC2016 # fixture bodies are literal shell text
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECKER="$REPO_ROOT/scripts/check-bash32.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/bash32"
WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

failures=0
pass() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then pass "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1 (output did not mention '$3'): $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1 (output mentioned '$3'): $2" ;;
    *) pass "$1" ;;
  esac
}

[ -f "$CHECKER" ] || {
  printf 'FAIL: checker missing at %s\n' "$CHECKER" >&2
  exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-check-bash32.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
tab="$(printf '\t')"

# The fixture directory's file list, as the CI step would feed it.
(cd "$FIXTURES" && ls -1) >"$tmp/fixture-list" || exit 1

# ---------------------------------------------------------------------------
# 1. Dialect: shebang, else the leading-comment directive; a .sh file
#    declaring neither is a finding.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/d/lib" "$tmp/d/hooks" || exit 1
printf '#!/bin/sh\n:\n' >"$tmp/d/a.sh"
printf '#!/usr/bin/env bash\n:\n' >"$tmp/d/b.sh"
printf '#!/usr/bin/env -S bash -e\n:\n' >"$tmp/d/c.sh"
printf '#!/bin/dash\n:\n' >"$tmp/d/e.sh"
printf '#!/bin/sh\r\n:\r\n' >"$tmp/d/crlf.sh"
printf '# shellcheck shell=sh\n# a library\nf() { :; }\n' >"$tmp/d/lib/l.sh"
printf '# Title\n\n# shellcheck shell=bash\nf() { :; }\n' >"$tmp/d/lib/m.sh"
printf '# shellcheck shell=dash\nf() { :; }\n' >"$tmp/d/lib/n.sh"
printf '#!/bin/bash\n:\n' >"$tmp/d/hooks/pre-commit"
printf '#!/usr/bin/env python3\npass\n' >"$tmp/d/tool"
printf 'not shell\n' >"$tmp/d/notes.txt"
printf 'f() { :; }\n# shellcheck shell=sh\n' >"$tmp/d/late.sh"
printf '%s\n' a.sh b.sh c.sh e.sh crlf.sh lib/l.sh lib/m.sh lib/n.sh \
  hooks/pre-commit tool notes.txt >"$tmp/d-list"
out="$(/bin/sh "$CHECKER" list --root "$tmp/d" --files-from "$tmp/d-list" 2>&1)"
assert_exit "a tree of declared files lists clean" 0 $?
assert_contains "a /bin/sh shebang is sh" "$out" "sh${tab}a.sh"
assert_contains "env bash is bash" "$out" "bash${tab}b.sh"
assert_contains "env -S with flags still finds bash" "$out" "bash${tab}c.sh"
assert_contains "a dash shebang is sh" "$out" "sh${tab}e.sh"
assert_contains "a CRLF shebang still names its interpreter" "$out" "sh${tab}crlf.sh"
assert_contains "a shebang-less library takes its directive" "$out" "sh${tab}lib/l.sh"
assert_contains "the directive is read past a markdown-like heading" "$out" "bash${tab}lib/m.sh"
assert_contains "a dash directive is sh" "$out" "sh${tab}lib/n.sh"
assert_contains "an extension-less hook is covered by its shebang" "$out" "bash${tab}hooks/pre-commit"
assert_not_contains "another interpreter is out of scope" "$out" "tool"
assert_not_contains "a non-shell file is out of scope" "$out" "notes.txt"

printf 'late.sh\n' >>"$tmp/d-list"
out="$(/bin/sh "$CHECKER" list --root "$tmp/d" --files-from "$tmp/d-list" 2>&1)"
assert_exit "a directive after the first command does not declare" 1 $?
assert_contains "the undeclared file is named" "$out" "late.sh: a .sh file declaring no dialect"

out="$(/bin/sh "$CHECKER" list --root "$FIXTURES" --files-from "$tmp/fixture-list" 2>&1)"
assert_exit "the no-dialect fixture fails the step" 1 $?
assert_contains "and is named" "$out" "no-dialect.sh: a .sh file declaring no dialect"

# Only the misparse fixtures are excluded, not their siblings.
mkdir -p "$tmp/x/tests/fixtures/bash32" "$tmp/x/tests/fixtures/other" || exit 1
printf '#!/bin/sh\n:\n' >"$tmp/x/tests/fixtures/bash32/skip.sh"
printf '#!/bin/sh\n:\n' >"$tmp/x/tests/fixtures/other/keep.sh"
printf '%s\n' tests/fixtures/bash32/skip.sh tests/fixtures/other/keep.sh >"$tmp/x-list"
out="$(/bin/sh "$CHECKER" list --root "$tmp/x" --files-from "$tmp/x-list" 2>&1)"
assert_not_contains "the misparse fixtures directory is excluded" "$out" "skip.sh"
assert_contains "a sibling fixtures directory is not" "$out" "tests/fixtures/other/keep.sh"

# ---------------------------------------------------------------------------
# 2. Enumeration refusals: anything that would read outside the root, or be
#    covered less than claimed, exits 2.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/p" || exit 1
printf '#!/bin/sh\n:\n' >"$tmp/p/ok-sh.sh"
printf '#!/bin/bash\n:\n' >"$tmp/p/ok-bash.sh"
printf '#!/bin/bash\n# MISPARSE\n' >"$tmp/p/bad.sh"
printf '#!/bin/sh\n:\n' >"$tmp/outside.sh"

: >"$tmp/empty-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/empty-list" >/dev/null 2>&1
assert_exit "an empty file set is a broken enumeration" 2 $?
printf 'missing.sh\n' >"$tmp/missing-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/missing-list" >/dev/null 2>&1
assert_exit "a listed file that cannot be read fails closed" 2 $?
printf '"quoted\\tname.sh"\n' >"$tmp/quoted-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/quoted-list" >/dev/null 2>&1
assert_exit "a path git had to quote fails closed" 2 $?
printf 'ok-sh.sh\n../outside.sh\n' >"$tmp/escape-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/escape-list" >/dev/null 2>&1
assert_exit "a path climbing out of the root is refused" 2 $?
printf 'ok-sh.sh\n/etc/hostname\n' >"$tmp/abs-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/abs-list" >/dev/null 2>&1
assert_exit "an absolute path is refused" 2 $?
mkdir -p "$tmp/s" || exit 1
printf '#!/bin/sh\n:\n' >"$tmp/s/real.sh"
ln -s ../outside.sh "$tmp/s/link.sh" || exit 1
printf 'real.sh\nlink.sh\n' >"$tmp/s-list"
/bin/sh "$CHECKER" list --root "$tmp/s" --files-from "$tmp/s-list" >/dev/null 2>&1
assert_exit "a tracked symlink is refused rather than skipped" 2 $?

esc="$(printf 'a\033]0;x\007.sh')"
printf '#!/bin/sh\n:\n' >"$tmp/p/$esc"
printf '%s\n' "$esc" >"$tmp/esc-list"
out="$(/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/esc-list" 2>&1)"
case "$out" in
  *"$(printf '\033')"*) fail "list prints a filename's control bytes raw" ;;
  *) pass "list sanitizes the filenames it prints" ;;
esac
rm -f "$tmp/p/$esc"

# ---------------------------------------------------------------------------
# 3. parse mode, with a stub parser so the dialect-to-flag mapping and the
#    reporting are checked on any host.
# ---------------------------------------------------------------------------
cat >"$tmp/stub-bash" <<'EOF'
#!/bin/sh
if [ "$1" = -c ]; then printf '%s' "${STUB_VERSION:-3.2.57(1)-stub}"; exit 0; fi
printf '%s\n' "$*" >>"${0%/*}/stub.log"
for last; do :; done
if grep -q MISPARSE "$last"; then
  printf '%s: line 2: syntax error\n' "$last" >&2
  exit 2
fi
exit 0
EOF
chmod 755 "$tmp/stub-bash" || exit 1
printf '%s\n' ok-sh.sh ok-bash.sh >"$tmp/p-list"
out="$(/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" 2>&1)"
assert_exit "parse passes when every file parses" 0 $?
assert_contains "and reports the parser version" "$out" "bash 3.2.57(1)-stub"
log="$(cat "$tmp/stub.log")"
assert_contains "an sh file parses in POSIX mode" "$log" "--posix -n $tmp/p/ok-sh.sh"
assert_contains "a bash file parses as bash" "$log" "-n $tmp/p/ok-bash.sh"
assert_not_contains "a bash file does not parse in POSIX mode" "$log" "--posix -n $tmp/p/ok-bash.sh"

printf 'bad.sh\n' >>"$tmp/p-list"
out="$(/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" 2>&1)"
assert_exit "a parse error fails the step" 1 $?
assert_contains "naming the file and dialect" "$out" "bad.sh does not parse as bash"
assert_contains "with the parser's message" "$out" "line 2: syntax error"

out="$(STUB_VERSION='5.2.21(1)-release' /bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" 2>&1)"
assert_exit "a non-3.2 parser is refused by default, not reported clean" 2 $?
assert_contains "naming the version found" "$out" "parser is bash 5.2.21(1)-release, not 3.2"
out="$(/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" --expect-version 9.9 2>&1)"
assert_exit "an explicit expected version is enforced" 2 $?

# ---------------------------------------------------------------------------
# 4. parse mode against the fixtures: every later bash accepts them, so a
#    3.2 rejection is the misparse and not a broken file; bash 3.2 rejects
#    each construct.
# ---------------------------------------------------------------------------
host_version="$(bash -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null)" || host_version=''
case "$host_version" in
  3.2*)
    out="$(/bin/sh "$CHECKER" parse --root "$FIXTURES" --files-from "$tmp/fixture-list" 2>&1)"
    assert_exit "bash 3.2 rejects the fixture directory" 1 $?
    assert_contains "the heredoc-in-substitution fixture fails to parse" "$out" \
      "heredoc-in-substitution.sh does not parse as bash"
    assert_contains "the case-in-substitution fixture fails to parse" "$out" \
      "case-in-substitution.sh does not parse as sh"
    assert_contains "the no-dialect fixture fails" "$out" "no-dialect.sh: a .sh file declaring no dialect"
    ;;
  '')
    fail "no bash on PATH"
    ;;
  *)
    out="$(/bin/sh "$CHECKER" parse --root "$FIXTURES" --files-from "$tmp/fixture-list" --expect-version '' 2>&1)"
    assert_exit "a later bash flags only the undeclared fixture" 1 $?
    assert_not_contains "and parses both construct fixtures" "$out" "does not parse"
    if [ "${PLANWRIGHT_TEST_REQUIRE_BASH32:-}" = 1 ]; then
      fail "PLANWRIGHT_TEST_REQUIRE_BASH32=1 but bash on PATH is $host_version, not 3.2"
    else
      printf 'skip: no bash 3.2 on PATH (bash %s); the CI step runs the 3.2 cases\n' "$host_version"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# 5. lint: each construct fixture fails; each misparse shape is flagged and
#    each near miss bash 3.2 parses passes.
# ---------------------------------------------------------------------------
out="$(/bin/sh "$CHECKER" lint --root "$FIXTURES" --files-from "$tmp/fixture-list" 2>&1)"
assert_exit "the lint rejects the fixture directory" 1 $?
heredoc_line=$(grep -n '<<' "$FIXTURES/heredoc-in-substitution.sh" | cut -d: -f1)
case_line=$(grep -n ' in \.\*)' "$FIXTURES/case-in-substitution.sh" | cut -d: -f1)
assert_contains "the lint flags the heredoc fixture" "$out" \
  "heredoc-in-substitution.sh:$heredoc_line: a heredoc inside a \$( )"
assert_contains "the lint flags the case fixture" "$out" \
  "case-in-substitution.sh:$case_line: a case pattern without its leading ("

mkdir -p "$tmp/l" || exit 1
lint_one() {
  # lint_one <name> <line>...: write a bash file, lint it alone.
  _n=$1
  shift
  {
    printf '#!/bin/bash\n'
    printf '%s\n' "$@"
  } >"$tmp/l/$_n"
  printf '%s\n' "$_n" >"$tmp/l-list"
  /bin/sh "$CHECKER" lint --root "$tmp/l" --files-from "$tmp/l-list" 2>&1
}
expect_flag() {
  # expect_flag <description> <name> <line>...
  _d=$1
  shift
  out="$(lint_one "$@")"
  assert_exit "flagged: $_d" 1 $?
}
expect_clean() {
  _d=$1
  shift
  out="$(lint_one "$@")"
  assert_exit "clean: $_d" 0 $?
}
tabc="$(printf '\t')"

expect_flag "a case written on the substitution line" same-line.sh \
  'v=$(case $x in a) echo 1 ;; esac)'
expect_flag "a bare pattern on its own line" own-line.sh \
  'x=$(' '  case $f in' '    .*) continue ;;' '  esac' ')'
expect_flag "a case whose in is on the next line" next-in.sh \
  'x=$(' '  case a' '  in' '    a) echo 1 ;;' '  esac' ')'
expect_flag "an outer pattern after a nested esac" nested.sh \
  'x=$(' '  case a in' '    (a)' '      case b in (b) : ;; esac' '      ;;' \
  '    c) echo 1 ;;' '  esac' ')'
expect_flag "a case after a subshell inside the substitution" subshell.sh \
  'x=$(' '  (' '    cd /' '  )' '  case a in' '    a) echo 1 ;;' '  esac' ')'
expect_flag "inside \"\$( )\" a comment's quote counts" dq-comment.sh \
  'x="$(' "  cat <<'EOF'" "# the child's" 'EOF' ')"'
expect_flag "an unclosed ( in the body" paren.sh \
  'x=$(' "  cat <<'EOF'" 'a ( paren' 'EOF' ')'
expect_flag "a stray ) in the body of a bare substitution" stray.sh \
  'x=$(' '  cat <<EOF' 'a ) b' 'EOF' ')'
expect_flag "a heredoc opened on the substitution line" inline-heredoc.sh \
  "x=\$(cat <<'EOF'" '`' 'EOF' ')'
expect_flag "the second heredoc on a line" two-heredocs.sh \
  'x=$(' "  cat <<'A' <<'B'" 'a' 'A' "it's" 'B' ')'
expect_flag "a <<- heredoc whose tab-indented body has a backtick" dash-heredoc.sh \
  'x=$(' "  cat <<-'EOF'" "${tabc}\`" "${tabc}EOF" ')'
expect_flag "a heredoc after an arithmetic expansion" arith.sh \
  'x=$(' '  : $((1)); cat <<EOF' 'a ( b' 'EOF' ')'
expect_flag "a case after an escaped quote" escaped.sh \
  "echo don\\'t" 'x=$(' '  case a in' '    a) echo 1 ;;' '  esac' ')'
expect_flag "a case after an apostrophe in a comment" comment-quote.sh \
  ": # do not touch it's" 'x=$(' '  case a in' '    a) echo 1 ;;' '  esac' ')'
expect_flag "a case after a heredoc operator in a comment" comment-heredoc.sh \
  ': # see cat <<EOF' 'x=$(' '  case a in' '    a) echo 1 ;;' '  esac' ')'
expect_flag "a heredoc whose delimiter never appears" unclosed.sh \
  'cat <<EOF' 'body'

expect_clean "a balanced heredoc body" balanced.sh \
  'x="$(' "  cat <<'EOF'" '{ print "it'"'"'s" }' 'EOF' ')"'
expect_clean "a stray ) in the body of a double-quoted substitution" dq-stray.sh \
  'x="$(' '  cat <<EOF' 'a ) b' 'EOF' ')"'
expect_clean "inside a bare \$( ) a commented quote" bare-comment.sh \
  'x=$(' "  cat <<'EOF'" "x  # the child's" 'EOF' ')'
expect_clean "a case pattern with its leading (" paren-form.sh \
  'x=$(' '  case $f in' '    (.*) continue ;;' '  esac' ')'
expect_clean "a case outside any substitution" outside.sh \
  'case $f in' '  .*) continue ;;' 'esac' 'y=$(printf x)'
expect_clean "a substitution closed mid-line, then a case" closed-mid.sh \
  'x=$(' '  echo a)' 'case $f in' '  a) : ;;' 'esac'
expect_clean "a quoted ) in a case body" quoted-paren.sh \
  'x=$(' '  case a in' '    (a)' '      echo "a)" ;;' '  esac' ')'
expect_clean "a single-quoted string" literal.sh \
  "s='v=\$(case \$x in a) echo 1 ;; esac)'"
expect_clean "a multi-line single-quoted program" program.sh \
  "awk '" '  x = "$("' '  a) y' "'" 'case $f in' '  a) : ;;' 'esac'
expect_clean "a quote spliced into a single-quoted program" splice.sh \
  "awk '" "  q = \"'\"'\"'\"" '  a) y' "'" 'case $f in' '  a) : ;;' 'esac'
expect_clean "an escaped \$( in a double-quoted string" escaped-sub.sh \
  's="v=\$(case $x in a) echo 1 ;; esac)"'
expect_clean "an arithmetic shift" shift.sh \
  'x=$(' '  echo $((1 << 2))' ')' 'case $f in' '  a) : ;;' 'esac'
expect_clean "a here-string" herestring.sh \
  'x=$(' '  cat <<<"$y"' ')' 'z=1'

# The lint catches the two regressions it exists for, in their original
# form (needs the repository's history).
fixed=90e3b4bed821e1456d5d1c41bcbdbbf4c203d0f9
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" cat-file -e "$fixed^" 2>/dev/null; then
  mkdir -p "$tmp/h" || exit 1
  git -C "$REPO_ROOT" show "$fixed^:scripts/check-no-ci-evals.sh" >"$tmp/h/evals.sh" || exit 1
  git -C "$REPO_ROOT" show "$fixed^:scripts/tower-queue.sh" >"$tmp/h/queue.sh" || exit 1
  printf '%s\n' evals.sh queue.sh >"$tmp/h-list"
  out="$(/bin/sh "$CHECKER" lint --root "$tmp/h" --files-from "$tmp/h-list" 2>&1)"
  assert_exit "the lint rejects the original regressions" 1 $?
  assert_contains "the heredoc regression is flagged" "$out" "evals.sh:307:"
  assert_contains "the case regression is flagged" "$out" "queue.sh:5605:"
else
  printf 'skip: the original regressions need the repository history\n'
fi

# ---------------------------------------------------------------------------
# 6. pin: the step's image reference carries an @sha256: digest, and the CI
#    job runs the parse and this file under it.
# ---------------------------------------------------------------------------
digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf 'env:\n  IMAGE: bash:3.2@sha256:%s\n' "$digest" >"$tmp/pinned.yml"
/bin/sh "$CHECKER" pin "$tmp/pinned.yml" >/dev/null 2>&1
assert_exit "a digest-pinned reference passes" 0 $?
printf 'env:\n  IMAGE: bash:3.2\n' >"$tmp/tag.yml"
out="$(/bin/sh "$CHECKER" pin "$tmp/tag.yml" 2>&1)"
assert_exit "a tag-only reference fails" 1 $?
assert_contains "naming the reference" "$out" "without an @sha256: digest"
printf 'a: bash:3.2@sha256:%s\nb: docker.io/library/bash:3.2\n' "$digest" >"$tmp/mixed.yml"
/bin/sh "$CHECKER" pin "$tmp/mixed.yml" >/dev/null 2>&1
assert_exit "one unpinned reference among pinned ones fails" 1 $?
printf 'a: bash:3.2  # was bash:3.2@sha256:%s\n' "$digest" >"$tmp/comment.yml"
/bin/sh "$CHECKER" pin "$tmp/comment.yml" >/dev/null 2>&1
assert_exit "a digest in a trailing comment does not pin the line" 1 $?
printf 'a: x=bash:3.2@sha256:%s y=bash:3.2\n' "$digest" >"$tmp/two.yml"
/bin/sh "$CHECKER" pin "$tmp/two.yml" >/dev/null 2>&1
assert_exit "every reference on a line is checked" 1 $?
printf 'a: bash:3.2@sha256:0fd7\n' >"$tmp/short.yml"
/bin/sh "$CHECKER" pin "$tmp/short.yml" >/dev/null 2>&1
assert_exit "a truncated digest fails" 1 $?
printf 'a: ubuntu-latest\n# bash:3.2 in prose\n' >"$tmp/none.yml"
/bin/sh "$CHECKER" pin "$tmp/none.yml" >/dev/null 2>&1
assert_exit "a workflow with no bash:3.2 reference fails" 1 $?
/bin/sh "$CHECKER" pin "$WORKFLOW" >/dev/null 2>&1
assert_exit "the CI workflow's bash:3.2 reference is digest-pinned" 0 $?

wf="$(cat "$WORKFLOW")"
assert_contains "CI parses the tracked files under 3.2" "$wf" \
  'bash scripts/check-bash32.sh parse --files-from - --expect-version 3.2'
assert_contains "CI runs this file under the same parser" "$wf" 'bash tests/test-check-bash32.sh'
assert_contains "CI makes a missing 3.2 a failure here" "$wf" 'PLANWRIGHT_TEST_REQUIRE_BASH32=1'
runs=$(grep -c 'docker run' "$WORKFLOW")
images=$(grep -c '"$BASH32_IMAGE"' "$WORKFLOW")
if [ "$runs" -ge 2 ] && [ "$images" -eq "$runs" ]; then
  pass "every docker run in CI uses the pinned image"
else
  fail "every docker run in CI uses the pinned image ($runs runs, $images pinned)"
fi

# ---------------------------------------------------------------------------
# 7. The repository's own file set (needs git; check:bash32 lints it).
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  out="$(/bin/sh "$CHECKER" list 2>&1)"
  assert_exit "every tracked .sh file declares a dialect" 0 $?
  assert_contains "the lock library is covered" "$out" "sh${tab}scripts/lock-lib.sh"
  assert_contains "the spec parser library is covered" "$out" "sh${tab}scripts/spec-parse.sh"
  assert_contains "a bash test library is covered" "$out" "bash${tab}tests/lib/fleet-home.sh"
  assert_contains "the pre-commit hook is covered" "$out" "githooks/pre-commit"
  assert_contains "the commit-msg hook is covered" "$out" "githooks/commit-msg"
  assert_not_contains "the misparse fixtures are excluded" "$out" "tests/fixtures/bash32/"
else
  printf 'skip: no git repository; the tree cases run under mise run check\n'
fi

if [ "$failures" -ne 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all tests passed\n'
