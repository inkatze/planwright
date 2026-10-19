#!/bin/bash
# Tests for scripts/check-script-invocation.sh — the guard that a skill
# instruction never runs a bash-shebanged script through `sh`.
#
# Called by path, a script gets the interpreter its shebang names; `sh <path>`
# overrides that with whatever /bin/sh is, and under dash a bash-only script
# dies on its first bashism. The skills call scripts by path, so the breakage
# reaches only a reader who copies an `sh` form, and nothing else would catch
# it.
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

tab="$(printf '\t')"
cr="$(printf '\r')"

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
assert_contains "the shebang's interpreter is named" "$out" "shebang names bash"

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
  'Run `git status && sh scripts/bash-tool.sh`.' \
  'Run `sh <root>/scripts/bash-tool.sh`.' \
  'Run `sh "<plugin-root>/scripts/bash-tool.sh"`.' \
  'Run `sh "${ROOT}"/scripts/bash-tool.sh`.' \
  'Run `sh -- scripts/bash-tool.sh`.' \
  'Run `sh -o errexit scripts/bash-tool.sh`.' \
  'Run `sh +x scripts/bash-tool.sh`.' \
  'Run `sh < scripts/bash-tool.sh`.' \
  'Run `/usr/bin/sh scripts/bash-tool.sh`.' \
  'Run `/usr/local/bin/sh scripts/bash-tool.sh`.' \
  'Run `sh $(pwd)/scripts/bash-tool.sh`.' \
  "Run sh${tab}scripts/bash-tool.sh with a tab." \
  "Run sh scripts/bash-tool.sh${cr}" \
  'Run sh scripts/bash-tool.sh, in prose.' \
  'Run `sh scripts/bash-tool.sh>/dev/null`.' \
  'Run `sh scripts/bash-tool.sh<in`.' \
  'Run `sh 2>/dev/null scripts/bash-tool.sh`.' \
  'Run `sh - scripts/bash-tool.sh`.' \
  'Run `sh --posix scripts/bash-tool.sh`.' \
  'Run `sh +o errexit scripts/bash-tool.sh`.' \
  'Run `sh -e<scripts/bash-tool.sh`.' \
  'Run `"sh" scripts/bash-tool.sh`.' \
  'Run **sh scripts/bash-tool.sh** or [sh scripts/bash-tool.sh](x).' \
  'Run `bash -c "sh scripts/bash-tool.sh"`.'; do
  variant form "$form"
  out="$("$CHECKER" --repo-root "$tmp/form" 2>&1)"
  assert "flagged: $form" 1 $?
  assert_contains "the line is named: $form" "$out" "skills/demo/SKILL.md:6"
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
  'Say sh, then scripts/bash-tool.sh, in prose.' \
  'Run `sh tests/fixtures/other/bash-tool.sh` (not under scripts/).' \
  'Run `bashful scripts/bash-tool.sh` or `ssh scripts/bash-tool.sh`.'; do
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
# 6b. Shebang spellings: each names bash, so the sh call through it fails.
# ---------------------------------------------------------------------------
for shebang in '#!/usr/bin/env bash' "#!/bin/bash${cr}" "#!/usr/bin/env${tab}bash" \
  '#!/usr/bin/env -S bash -e' '#! /bin/bash'; do
  variant shebang 'Run `sh scripts/posix-tool.sh`.'
  printf '%s\n:\n' "$shebang" >"$tmp/shebang/scripts/posix-tool.sh"
  "$CHECKER" --repo-root "$tmp/shebang" >/dev/null 2>&1
  assert "shebang counts as bash: $shebang" 1 $?
  rm -rf "$tmp/shebang"
done

variant shebang 'Run `sh scripts/posix-tool.sh`.'
printf '#!/bin/bash' >"$tmp/shebang/scripts/posix-tool.sh"
"$CHECKER" --repo-root "$tmp/shebang" >/dev/null 2>&1
assert "a shebang with no trailing newline is read" 1 $?
rm -rf "$tmp/shebang"

variant shebang 'Run `sh scripts/posix-tool.sh`.'
printf '#!/bin/bashful\n' >"$tmp/shebang/scripts/posix-tool.sh"
"$CHECKER" --repo-root "$tmp/shebang" >/dev/null 2>&1
assert "an interpreter merely starting with bash does not count" 0 $?
rm -rf "$tmp/shebang"

# Only top-level scripts/*.sh count: a nested bash namesake is not the script
# the operand names.
variant nested 'Run `sh scripts/posix-tool.sh`.'
mkdir -p "$tmp/nested/scripts/lib" || exit 1
printf '#!/bin/bash\n' >"$tmp/nested/scripts/lib/posix-tool.sh"
"$CHECKER" --repo-root "$tmp/nested" >/dev/null 2>&1
assert "a nested bash namesake is not compared against" 0 $?

# ---------------------------------------------------------------------------
# 7. Every finding is reported in one run, not just the first.
# ---------------------------------------------------------------------------
variant many 'Run `sh scripts/bash-tool.sh` here.' 'And `sh scripts/bash-tool.sh` again.'
out="$("$CHECKER" --repo-root "$tmp/many" 2>&1)"
assert "two offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "skills/demo/SKILL.md:6"
assert_contains "the second offender is named" "$out" "skills/demo/SKILL.md:7"

# ---------------------------------------------------------------------------
# 8. Fail closed: no shebanged script to compare against, no instruction
#    file to scan, or a name or file the scan cannot trust, is exit 2.
# ---------------------------------------------------------------------------
cp -R "$FIXTURES/clean" "$tmp/noscripts" || exit 1
rm -rf "$tmp/noscripts/scripts"
out="$("$CHECKER" --repo-root "$tmp/noscripts" 2>&1)"
assert "a root without scripts/ fails closed" 2 $?
assert_not_contains "the scriptless scan does not read as clean" "$out" "clean ("

cp -R "$FIXTURES/clean" "$tmp/libsonly" || exit 1
printf '# shellcheck shell=bash\n' >"$tmp/libsonly/scripts/bash-tool.sh"
printf '# shellcheck shell=sh\n' >"$tmp/libsonly/scripts/posix-tool.sh"
out="$("$CHECKER" --repo-root "$tmp/libsonly" 2>&1)"
assert "a scripts/ with no shebanged script fails closed" 2 $?
assert_not_contains "the libraries-only scan does not read as clean" "$out" "clean ("

cp -R "$FIXTURES/clean" "$tmp/link" || exit 1
ln -s ../../doctrine/demo.md "$tmp/link/skills/demo/LINK.md" || exit 1
out="$("$CHECKER" --repo-root "$tmp/link" 2>&1)"
assert "a symbolic link under skills/ fails closed" 2 $?
assert_contains "the link is named" "$out" "symbolic link"

# A newline in a name would split the file list; a forged `found=0` entry
# once reset the finding count to a clean exit.
cp -R "$FIXTURES/sh-runs-bash" "$tmp/newline" || exit 1
: >"$tmp/newline/skills/demo/a
found=0
zz.md" || exit 1
out="$("$CHECKER" --repo-root "$tmp/newline" 2>&1)"
assert "a name containing a newline fails closed" 2 $?
assert_not_contains "the forged list does not read as clean" "$out" "clean ("

for d in scripts doctrine; do
  cp -R "$FIXTURES/clean" "$tmp/odd" || exit 1
  ln -s demo.md "$tmp/odd/$d/LINK.md" || exit 1
  "$CHECKER" --repo-root "$tmp/odd" >/dev/null 2>&1
  assert "a symbolic link under $d/ fails closed" 2 $?
  rm -f "$tmp/odd/$d/LINK.md"
  : >"$tmp/odd/$d/a
b.md" || exit 1
  "$CHECKER" --repo-root "$tmp/odd" >/dev/null 2>&1
  assert "a name containing a newline under $d/ fails closed" 2 $?
  rm -rf "$tmp/odd"
done

# Names reach the terminal: C0 and C1 control bytes are stripped from them.
cp -R "$FIXTURES/sh-runs-bash" "$tmp/ctl" || exit 1
esc="$(printf '\033')"
csi="$(printf '\233')"
mv "$tmp/ctl/skills/demo" "$tmp/ctl/skills/de${esc}[2Jmo${csi}2J" || exit 1
out="$("$CHECKER" --repo-root "$tmp/ctl" 2>&1)"
assert "the control-byte fixture still fails" 1 $?
assert_not_contains "no ESC reaches the output" "$out" "$esc"
assert_not_contains "no 8-bit CSI reaches the output" "$out" "$csi"

if [ "$(id -u)" -ne 0 ]; then
  cp -R "$FIXTURES/clean" "$tmp/unreadable" || exit 1
  chmod 000 "$tmp/unreadable/doctrine/demo.md" || exit 1
  "$CHECKER" --repo-root "$tmp/unreadable" >/dev/null 2>&1
  assert "an unreadable instruction file fails closed" 2 $?
  chmod 644 "$tmp/unreadable/doctrine/demo.md"
  chmod 000 "$tmp/unreadable/scripts/bash-tool.sh" || exit 1
  "$CHECKER" --repo-root "$tmp/unreadable" >/dev/null 2>&1
  assert "an unreadable script fails closed" 2 $?
  chmod 755 "$tmp/unreadable/scripts/bash-tool.sh"
fi

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
