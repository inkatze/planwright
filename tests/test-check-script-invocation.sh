#!/bin/bash
# Tests for scripts/check-script-invocation.sh — the guard that a skill
# instruction never runs a bash-shebanged script through `sh`.
#
# Called by path, a script gets the interpreter its shebang names; `sh <path>`
# overrides that with whatever /bin/sh is (dash, or bash in POSIX mode), and a
# bash-only script dies on its first bashism there. The skills call scripts by
# path, so the breakage reaches only a reader who copies an `sh` form, and
# nothing else would catch it.
#
# Requirement verified: test-throughput REQ-E1.2 (D-12).
# shellcheck disable=SC2016 # the backticks and unexpanded $ forms are the inputs under test
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-script-invocation.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/script-invocation"

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

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# variant <name> <line>... — a copy of the clean fixture whose demo skill
# gains the given lines.
variant() {
  cp -R "$FIXTURES/clean" "$tmp/$1" || exit 1
  v_dir="$tmp/$1"
  shift
  printf '%s\n' "$@" >>"$v_dir/skills/demo/SKILL.md" || exit 1
}

# ---------------------------------------------------------------------------
# 1. The repository's own tree is clean.
# ---------------------------------------------------------------------------
out="$("$CHECKER" 2>&1)"
assert "the shipped tree passes" 0 $?
assert_contains "the tree's scan reports clean" "$out" "clean ("

# ---------------------------------------------------------------------------
# 2. The clean fixture: by path, through bash, and an sh script through sh.
# ---------------------------------------------------------------------------
out="$("$CHECKER" --repo-root "$FIXTURES/clean" 2>&1)"
assert "invocations that honor the shebang pass" 0 $?
assert_contains "the clean fixture reports its scan" "$out" "clean ("

# ---------------------------------------------------------------------------
# 3. The fixture skill running a bash-shebanged script through sh fails,
#    naming the file, the line, and the script.
# ---------------------------------------------------------------------------
out="$("$CHECKER" --repo-root "$FIXTURES/sh-runs-bash" 2>&1)"
assert "a bash script run through sh fails" 1 $?
assert_contains "the offending line is named" "$out" "skills/demo/SKILL.md:3"
assert_contains "the script is named" "$out" "scripts/bash-tool.sh"
assert_contains "the shebang's interpreter is named" "$out" "bash"

# ---------------------------------------------------------------------------
# 4. Every spelling of running it through sh is caught.
# ---------------------------------------------------------------------------
for form in \
  'Run `/bin/sh scripts/bash-tool.sh`.' \
  'Run `sh "$ROOT/scripts/bash-tool.sh" --check`.' \
  'Run `sh /abs/planwright/scripts/bash-tool.sh`.' \
  'Run `sh -e scripts/bash-tool.sh`.' \
  'Run `/usr/bin/env sh scripts/bash-tool.sh`.' \
  '    out=$(sh scripts/bash-tool.sh)' \
  'Run `git status && sh scripts/bash-tool.sh`.'; do
  variant form "$form"
  out="$("$CHECKER" --repo-root "$tmp/form" 2>&1)"
  assert "flagged: $form" 1 $?
  rm -rf "$tmp/form"
done

# ---------------------------------------------------------------------------
# 5. Forms that honor the shebang, or are not an sh invocation, pass.
# ---------------------------------------------------------------------------
for form in \
  'Run `sh -c "scripts/bash-tool.sh --check"`.' \
  'Run `/bin/bash scripts/bash-tool.sh`.' \
  'Run `git push scripts/bash-tool.sh` (a word ending in sh).' \
  'Run `sh scripts/missing-tool.sh` (no such script).' \
  'Say sh, then scripts/bash-tool.sh, in prose.'; do
  variant form "$form"
  out="$("$CHECKER" --repo-root "$tmp/form" 2>&1)"
  assert "not flagged: $form" 0 $?
  rm -rf "$tmp/form"
done

# ---------------------------------------------------------------------------
# 6. A #!/bin/bash shebang counts, and doctrine is scanned like a skill.
# ---------------------------------------------------------------------------
cp -R "$FIXTURES/clean" "$tmp/binbash" || exit 1
printf '#!/bin/bash\n:\n' >"$tmp/binbash/scripts/posix-tool.sh"
printf '\nOr run `sh scripts/posix-tool.sh`.\n' >>"$tmp/binbash/doctrine/demo.md"
out="$("$CHECKER" --repo-root "$tmp/binbash" 2>&1)"
assert "a #!/bin/bash script run through sh fails" 1 $?
assert_contains "the doctrine line is named" "$out" "doctrine/demo.md:5"
assert_contains "the skill line is named" "$out" "skills/demo/SKILL.md:5"

# ---------------------------------------------------------------------------
# 7. Every finding is reported in one run, not just the first.
# ---------------------------------------------------------------------------
variant many 'Run `sh scripts/bash-tool.sh` here.' 'And `sh scripts/bash-tool.sh` again.'
out="$("$CHECKER" --repo-root "$tmp/many" 2>&1)"
assert "two offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "skills/demo/SKILL.md:6"
assert_contains "the second offender is named" "$out" "skills/demo/SKILL.md:7"

# ---------------------------------------------------------------------------
# 8. Fail closed: no bash-shebanged script to compare against, or no
#    instruction file to scan, is exit 2, never clean.
# ---------------------------------------------------------------------------
cp -R "$FIXTURES/clean" "$tmp/noscripts" || exit 1
rm -rf "$tmp/noscripts/scripts"
out="$("$CHECKER" --repo-root "$tmp/noscripts" 2>&1)"
assert "a root without scripts/ fails closed" 2 $?
assert_not_contains "the scriptless scan does not read as clean" "$out" "clean ("

cp -R "$FIXTURES/clean" "$tmp/noskills" || exit 1
rm -rf "$tmp/noskills/skills" "$tmp/noskills/doctrine"
out="$("$CHECKER" --repo-root "$tmp/noskills" 2>&1)"
assert "a root without instruction files fails closed" 2 $?
assert_not_contains "the empty scan does not read as clean" "$out" "clean ("

"$CHECKER" --bogus >/dev/null 2>&1
assert "an unknown argument is a usage error" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "test-check-script-invocation: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-script-invocation: all passed"
