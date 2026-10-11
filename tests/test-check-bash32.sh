#!/bin/sh
# Tests for scripts/check-bash32.sh, the bash 3.2 regression guards
# (test-throughput REQ-E1.6, REQ-E1.7).
#
# The misparse half needs a real bash 3.2: every later bash parses the
# fixtures under tests/fixtures/bash32/. When the bash on PATH is 3.2 (the CI
# step runs this file inside the bash:3.2 image), the parse cases run against
# it; elsewhere they skip, unless PLANWRIGHT_TEST_REQUIRE_BASH32=1 makes a
# missing 3.2 a failure, so the CI step cannot pass by skipping. Cases that
# read the repository's own tracked files need git and skip without it (the
# image has none); `mise run check` runs them.
#
# shellcheck disable=SC2016 # fixture bodies are literal shell text
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECKER="$REPO_ROOT/scripts/check-bash32.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/bash32"

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
printf '# shellcheck shell=sh\n# a library\nf() { :; }\n' >"$tmp/d/lib/l.sh"
printf '# Title\n\n# shellcheck shell=bash\nf() { :; }\n' >"$tmp/d/lib/m.sh"
printf '#!/bin/bash\n:\n' >"$tmp/d/hooks/pre-commit"
printf '#!/usr/bin/env python3\npass\n' >"$tmp/d/tool"
printf 'not shell\n' >"$tmp/d/notes.txt"
printf 'f() { :; }\n# shellcheck shell=sh\n' >"$tmp/d/late.sh"
printf '%s\n' a.sh b.sh c.sh lib/l.sh lib/m.sh hooks/pre-commit tool notes.txt \
  >"$tmp/d-list"
out="$(/bin/sh "$CHECKER" list --root "$tmp/d" --files-from "$tmp/d-list" 2>&1)"
assert_exit "a tree of declared files lists clean" 0 $?
tab="$(printf '\t')"
assert_contains "a /bin/sh shebang is sh" "$out" "sh${tab}a.sh"
assert_contains "env bash is bash" "$out" "bash${tab}b.sh"
assert_contains "env -S with flags still finds bash" "$out" "bash${tab}c.sh"
assert_contains "a shebang-less library takes its directive" "$out" "sh${tab}lib/l.sh"
assert_contains "the directive is read past a markdown-like heading" "$out" "bash${tab}lib/m.sh"
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

# ---------------------------------------------------------------------------
# 2. parse mode, with a stub parser so the dialect-to-flag mapping and the
#    reporting are checked on any host.
# ---------------------------------------------------------------------------
cat >"$tmp/stub-bash" <<'EOF'
#!/bin/sh
if [ "$1" = -c ]; then printf '3.2.57(1)-stub'; exit 0; fi
printf '%s\n' "$*" >>"${0%/*}/stub.log"
for last; do :; done
if grep -q MISPARSE "$last"; then
  printf '%s: line 2: syntax error\n' "$last" >&2
  exit 2
fi
exit 0
EOF
chmod 755 "$tmp/stub-bash" || exit 1
mkdir -p "$tmp/p" || exit 1
printf '#!/bin/sh\n:\n' >"$tmp/p/ok-sh.sh"
printf '#!/bin/bash\n:\n' >"$tmp/p/ok-bash.sh"
printf '#!/bin/bash\n# MISPARSE\n' >"$tmp/p/bad.sh"
printf '%s\n' ok-sh.sh ok-bash.sh >"$tmp/p-list"
out="$(/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" --expect-version 3.2 2>&1)"
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

out="$(/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/p-list" --bash "$tmp/stub-bash" --expect-version 9.9 2>&1)"
assert_exit "the wrong parser version is refused, not reported clean" 2 $?
assert_contains "naming the version found" "$out" "parser is bash 3.2.57(1)-stub, not 9.9"

: >"$tmp/empty-list"
/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/empty-list" --bash "$tmp/stub-bash" >/dev/null 2>&1
assert_exit "an empty file set is a broken enumeration" 2 $?

printf 'missing.sh\n' >"$tmp/missing-list"
/bin/sh "$CHECKER" parse --root "$tmp/p" --files-from "$tmp/missing-list" --bash "$tmp/stub-bash" >/dev/null 2>&1
assert_exit "a listed file that cannot be read fails closed" 2 $?

printf '"quoted\\tname.sh"\n' >"$tmp/quoted-list"
/bin/sh "$CHECKER" list --root "$tmp/p" --files-from "$tmp/quoted-list" >/dev/null 2>&1
assert_exit "a path git had to quote fails closed" 2 $?

# ---------------------------------------------------------------------------
# 3. parse mode under a real bash 3.2: each construct fixture fails.
# ---------------------------------------------------------------------------
host_version="$(bash -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null)" || host_version=''
case "$host_version" in
  3.2*)
    out="$(/bin/sh "$CHECKER" parse --root "$FIXTURES" --files-from "$tmp/fixture-list" --expect-version 3.2 2>&1)"
    assert_exit "bash 3.2 rejects the fixture directory" 1 $?
    assert_contains "the heredoc-in-substitution fixture fails to parse" "$out" \
      "heredoc-in-substitution.sh does not parse as bash"
    assert_contains "the case-in-substitution fixture fails to parse" "$out" \
      "case-in-substitution.sh does not parse as sh"
    assert_contains "the no-dialect fixture fails" "$out" "no-dialect.sh: a .sh file declaring no dialect"
    ;;
  *)
    if [ "${PLANWRIGHT_TEST_REQUIRE_BASH32:-}" = 1 ]; then
      fail "PLANWRIGHT_TEST_REQUIRE_BASH32=1 but bash on PATH is ${host_version:-missing}, not 3.2"
    else
      printf 'skip: no bash 3.2 on PATH (bash %s); the CI step runs these\n' "${host_version:-missing}"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# 4. lint: each construct fixture fails; near misses that bash 3.2 parses
#    pass.
# ---------------------------------------------------------------------------
out="$(/bin/sh "$CHECKER" lint --root "$FIXTURES" --files-from "$tmp/fixture-list" 2>&1)"
assert_exit "the lint rejects the fixture directory" 1 $?
assert_contains "the lint flags the heredoc fixture" "$out" "heredoc-in-substitution.sh:6: a heredoc inside a \$( )"
assert_contains "the lint flags the case fixture" "$out" "case-in-substitution.sh:7: a case pattern without its leading ("

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
out="$(lint_one same-line.sh 'v=$(case $x in a) echo 1 ;; esac)')"
assert_exit "a case written on the substitution line is flagged" 1 $?
out="$(lint_one dq-comment.sh 'x="$(' "  cat <<'EOF'" "# the child's" 'EOF' ')"')"
assert_exit "inside \"\$( )\" a comment's quote counts" 1 $?
out="$(lint_one paren.sh 'x=$(' "  cat <<'EOF'" 'a ( paren' 'EOF' ')')"
assert_exit "an unclosed ( in the body is flagged" 1 $?
out="$(lint_one inline-heredoc.sh "x=\$(cat <<'EOF'" '`' 'EOF' ')')"
assert_exit "a heredoc opened on the substitution line is checked" 1 $?

out="$(lint_one balanced.sh 'x="$(' "  cat <<'EOF'" '{ print "it'"'"'s" }' 'EOF' ')"')"
assert_exit "a balanced heredoc body passes" 0 $?
out="$(lint_one bare-comment.sh 'x=$(' "  cat <<'EOF'" "x  # the child's" 'EOF' ')')"
assert_exit "inside a bare \$( ) a commented quote passes" 0 $?
out="$(lint_one paren-form.sh 'x=$(' '  case $f in' '    (.*) continue ;;' '  esac' ')')"
assert_exit "a case pattern with its leading ( passes" 0 $?
out="$(lint_one outside.sh 'case $f in' '  .*) continue ;;' 'esac' 'y=$(printf x)')"
assert_exit "a case outside any substitution passes" 0 $?
out="$(lint_one literal.sh "s='v=\$(case \$x in a) echo 1 ;; esac)'")"
assert_exit "a single-quoted string is not code" 0 $?
out="$(lint_one shift.sh 'x=$(' '  echo $((1 << 2))' ')' 'case $f in' '  a) : ;;' 'esac')"
assert_exit "an arithmetic shift is not a heredoc" 0 $?
out="$(lint_one herestring.sh 'x=$(' '  cat <<<"$y"' ')' 'z=1')"
assert_exit "a here-string is not a heredoc" 0 $?

# ---------------------------------------------------------------------------
# 5. pin: the step's image reference carries an @sha256: digest.
# ---------------------------------------------------------------------------
digest=0fd7cb8499c63a3c9345e7088a9cd83bb69f6e895e83833859aff838a0312091
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
printf 'a: bash:3.2@sha256:0fd7\n' >"$tmp/short.yml"
/bin/sh "$CHECKER" pin "$tmp/short.yml" >/dev/null 2>&1
assert_exit "a truncated digest fails" 1 $?
printf 'a: ubuntu-latest\n' >"$tmp/none.yml"
/bin/sh "$CHECKER" pin "$tmp/none.yml" >/dev/null 2>&1
assert_exit "a workflow with no bash:3.2 reference fails" 1 $?
/bin/sh "$CHECKER" pin "$REPO_ROOT/.github/workflows/ci.yml" >/dev/null 2>&1
assert_exit "the CI workflow's bash:3.2 reference is digest-pinned" 0 $?

# ---------------------------------------------------------------------------
# 6. The repository's own file set (needs git).
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
  out="$(/bin/sh "$CHECKER" lint 2>&1)"
  assert_exit "the lint passes on the tree" 0 $?
else
  printf 'skip: no git repository; the tree cases run under mise run check\n'
fi

if [ "$failures" -ne 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all tests passed\n'
