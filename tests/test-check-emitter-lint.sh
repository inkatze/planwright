#!/bin/bash
# Tests for the emitter-output-lint guard (review-effectiveness REQ-F1.2):
# scripts/check-emitter-lint.sh over the fixture roots under
# tests/fixtures/emitter-lint/, the lint helper tests/lib/emitter-lint.sh on a
# clean and a defective artifact per format, the catalog entry, and the gate
# wiring. The helper is called through a variable format here so the guard
# never reads these calls as linting a real emitter.
# shellcheck disable=SC2016 # fixture bodies are literal shell text
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECK="$REPO_ROOT/scripts/check-emitter-lint.sh"
FIX="$REPO_ROOT/tests/fixtures/emitter-lint"

failures=0
pass() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-emitter-lint.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# expect <label> <root> <exit> <substring>
expect() {
  out=$(/bin/sh "$CHECK" "$2" 2>&1)
  rc=$?
  if [ "$rc" -ne "$3" ]; then
    fail "$1: exit $rc, not $3: $out"
    return
  fi
  case "$out" in
    *"$4"*) pass "$1" ;;
    *) fail "$1: output did not mention '$4': $out" ;;
  esac
}

expect "every declared format linted is clean" "$FIX/clean" 0 "clean (2 declared"
expect "a declared format no test lints fails" "$FIX/unlinted" 1 "emits yaml, but no test lints it"
expect "a lint of an undeclared emitter fails" "$FIX/undeclared" 1 "lints markdown output of other.sh"
expect "an unknown declared format fails" "$FIX/unknown" 1 "declares an unknown format"
expect "no declared emitter fails closed" "$FIX/none" 2 "a broken scan"
expect "a root without scripts/ fails closed" "$tmp" 2 "no scripts/ and tests/"
expect "this repository's emitters are each linted" "$REPO_ROOT" 0 "each linted"

# scratch_root <dir> <emits-line> — a root whose one script carries the line
# and whose one test lints its markdown.
le=lint_emitted
scratch_root() {
  mkdir -p "$1/scripts" "$1/tests" || exit 1
  printf '#!/bin/sh\n%s\n' "$2" >"$1/scripts/emit.sh"
  printf '#!/bin/sh\n%s markdown emit.sh "$out"\n' "$le" >"$1/tests/test-emit.sh"
}
scratch_root "$tmp/trail" '# Emits: markdown  '
expect "trailing blanks after a declared format are not part of it" "$tmp/trail" 0 "clean (1 declared"
scratch_root "$tmp/crlf" "$(printf '# Emits: markdown\r')"
expect "a CRLF header line declares its format" "$tmp/crlf" 0 "clean (1 declared"
scratch_root "$tmp/empty" '# Emits:'
printf '# Emits: markdown\n' >"$tmp/empty/scripts/other.sh"
printf '%s markdown other.sh "$out"\n' "$le" >>"$tmp/empty/tests/test-emit.sh"
expect "an empty declaration is a finding" "$tmp/empty" 1 'unknown format "(none)"'
scratch_root "$tmp/badfmt" '# Emits: markdown, html'
expect "an unknown format is named in the finding" "$tmp/badfmt" 1 'unknown format "html"'
scratch_root "$tmp/commented" '# Emits: markdown'
printf '#!/bin/sh\n# %s markdown emit.sh "$out"\n' "$le" >"$tmp/commented/tests/test-emit.sh"
expect "a commented-out lint call lints nothing" "$tmp/commented" 1 "emits markdown, but no test lints it"
# at_line <n> <format> — a script whose declaration of <format> sits on line <n>.
at_line() {
  printf '#!/bin/sh\n'
  i=2
  while [ "$i" -lt "$1" ]; do
    printf 'true\n'
    i=$((i + 1))
  done
  printf '# Emits: %s\n' "$2"
}
scratch_root "$tmp/late" '# Emits: markdown'
at_line 41 yaml >"$tmp/late/scripts/late.sh"
expect "a declaration on line 41 declares nothing" "$tmp/late" 0 "clean (1 declared"
at_line 40 yaml >"$tmp/late/scripts/late.sh"
expect "a declaration on line 40 still counts" "$tmp/late" 1 "late.sh emits yaml, but no test lints it"
scratch_root "$tmp/a=b" '# Emits: markdown'
out=$(cd "$tmp" && /bin/sh "$CHECK" a=b 2>&1 </dev/null)
case "$?:$out" in
  0:*"clean (1 declared"*) pass "a relative root holding = is read as a path" ;;
  *) fail "a relative root holding = was not read as a path: $out" ;;
esac
out=$(/bin/sh "$CHECK" --help extra 2>&1)
if [ $? -eq 2 ]; then pass "--help with another argument is a usage error"; else fail "--help took another argument: $out"; fi
out=$(/bin/sh "$CHECK" "$(printf -- '-\233[2J')" 2>&1)
case "$out" in
  *"$(printf '\233')"*) fail "a C1 control byte in an option reached the message" ;;
  *) pass "an option's control bytes, C1 included, are stripped from the message" ;;
esac
out=$(/bin/sh "$CHECK" --bogus 2>&1)
case "$?:$out" in
  2:*"--bogus"*) pass "an unknown option is refused by name" ;;
  *) fail "an unknown option was not refused by name: $out" ;;
esac
if [ "$(id -u)" -ne 0 ]; then
  scratch_root "$tmp/locked" '# Emits: markdown'
  chmod 000 "$tmp/locked/tests"
  expect "an unlistable tests/ directory fails closed" "$tmp/locked" 2 "cannot be listed"
  chmod 755 "$tmp/locked/tests"
else
  printf '%s\n' "skip: unlistable tests/ directory: running as root, which lists it anyway"
fi

# The helper itself: each format passes a clean artifact and fails a defect.
# shellcheck source=tests/lib/emitter-lint.sh
. "$REPO_ROOT/tests/lib/emitter-lint.sh"
# lint_case <format> <label> <want-status>[:<rule named>] <content> [<dialect>]
lint_case() {
  lc_want=${3%%:*} lc_rule=${3#*:}
  [ "$lc_rule" != "$3" ] || lc_rule=""
  printf '%s\n' "$4" >"$tmp/artifact"
  lint_emitted "$1" fixture "$tmp/artifact" ${5:+"$5"} >"$tmp/lint.out" 2>&1
  got=$?
  if grep -q '^skip:' "$tmp/lint.out"; then
    printf '%s\n' "skip: $2: $(cat "$tmp/lint.out")"
  elif [ "$got" -ne "$lc_want" ]; then
    fail "$2: status $got, not $lc_want: $(cat "$tmp/lint.out")"
  elif [ -n "$lc_rule" ] && ! grep -qF -e "$lc_rule" "$tmp/lint.out"; then
    fail "$2: the lint output does not name $lc_rule: $(cat "$tmp/lint.out")"
  else
    pass "$2"
  fi
}
md=markdown
yml=yaml
sh_=shell
lint_case "$md" "a clean Markdown fragment passes" 0 "$(printf 'Some text.\n\n| a | b |\n| --- | --- |\n| 1 | 2 |')"
lint_case "$md" "a Markdown heading without its blank line fails" 1:MD022 "$(printf '## Heading\ntext right below')"
lint_case "$md" "a details/summary collapse is allowed in a fragment" 0 "$(printf 'Text.\n\n<details>\n<summary>More</summary>\n\nBody.\n\n</details>')"
lint_case "$md" "other inline HTML still fails" 1:MD033 "$(printf 'Text with <span>html</span>.')"
lint_case "$md" "a list straight under a line fails under the baseline" 1:MD032 "$(printf '**Label:**\n- item')"
lint_case "$md" "the spec dialect takes the spec bundle relaxation" 0 "$(printf '# T\n\n**Label:**\n- item')" spec
lint_case "$md" "the spec dialect keeps the structural rules" 1:MD001 "$(printf '# T\n\n### Skipped level')" spec
lint_case "$yml" "clean YAML passes" 0 "$(printf 'key: value\nlist:\n  - one\n')"
lint_case "$yml" "YAML with a duplicate key fails" 1:key-duplicates "$(printf 'key: a\nkey: b\n')"
lint_case "$sh_" "a clean shell script passes" 0 "$(printf '#!/bin/sh\nprintf "%%s\\\\n" "$1"\n')"
lint_case "$sh_" "a shell script that does not parse fails" 1 "$(printf '#!/bin/sh\nif true; then\n')"
lint_case "$sh_" "an unquoted expansion fails shellcheck" 1:SC2086 "$(printf '#!/bin/sh\nrm $1\n')"
lint_case "$sh_" "a bash-only construct under the sh dialect fails" 1:SC3030 "$(printf 'a=(1 2)\nprintf "%%s\\\\n" "${a[0]}"\n')" sh
# A linter missing in CI is a failure, never a skip; outside CI, a skip line.
printf 'key: value\n' >"$tmp/artifact"
mkdir -p "$tmp/notools" || exit 1
for tool in mktemp rm dirname cat sed head; do
  t_path=$(command -v "$tool") && ln -sf "$t_path" "$tmp/notools/$tool"
done
out=$(CI=1 PATH="$tmp/notools" lint_emitted "$yml" fixture "$tmp/artifact" 2>&1)
case "$?:$out" in
  1:*"yamllint is not on PATH in CI"*) pass "a linter missing in CI fails the lint" ;;
  *) fail "a linter missing in CI did not fail the lint: $out" ;;
esac
out=$(CI='' PATH="$tmp/notools" lint_emitted "$yml" fixture "$tmp/artifact" 2>&1)
case "$?:$out" in
  0:*"skip: lint_emitted: fixture: yamllint is not on PATH"*) pass "a linter missing outside CI is a named skip" ;;
  *) fail "a linter missing outside CI was not a named skip: $out" ;;
esac
bogus=nonsense
if lint_emitted "$bogus" fixture "$tmp/artifact" 2>/dev/null; then
  fail "an unknown format was accepted"
else
  pass "an unknown format is refused"
fi

# Catalog and wiring.
if awk '/^  - id:/ { on = ($3 == "emitter-output-lint") } on && /^    disposition:/ { f = 1 } END { exit !f }' \
  "$REPO_ROOT/config/guard-catalog.yaml"; then
  pass "the guard catalog names emitter-output-lint with a disposition"
else
  fail "the guard catalog has no emitter-output-lint entry with a disposition"
fi
if grep -q '`emitter-output-lint`' "$REPO_ROOT/doctrine/guard-catalog.md"; then
  pass "doctrine/guard-catalog.md names the guard"
else
  fail "doctrine/guard-catalog.md does not name the guard"
fi
if grep -q '^\[tasks\."check:emitter-lint"\]' "$REPO_ROOT/mise.toml" && grep -q '^  "check:emitter-lint",$' "$REPO_ROOT/mise.toml"; then
  pass "check:emitter-lint is a task inside the check aggregate"
else
  fail "check:emitter-lint is not a task inside the check aggregate"
fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all check-emitter-lint tests passed"
