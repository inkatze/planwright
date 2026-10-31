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
  'Run **sh scripts/bash-tool.sh** in bold.' \
  'Run [sh scripts/bash-tool.sh](x) as a link.' \
  'Run ${sh scripts/bash-tool.sh} in braces.' \
  'Run `sh ~/dev/<repo>/scripts/bash-tool.sh`.' \
  'Run `sh "${ROOT:-<root>}/scripts/bash-tool.sh"`.' \
  'Run `sh > /dev/null scripts/bash-tool.sh`.' \
  'Run `sh 2> /dev/null scripts/bash-tool.sh`.' \
  'Run `sh < /dev/null scripts/bash-tool.sh`.' \
  'Run `sh</dev/null scripts/bash-tool.sh`.' \
  'Run `sh>/dev/null scripts/bash-tool.sh`.' \
  'Run `sh< /dev/null scripts/bash-tool.sh`.' \
  'Run `sh<scripts/bash-tool.sh`.' \
  'Run `./sh scripts/bash-tool.sh`.' \
  'Run `bin/sh scripts/bash-tool.sh`.' \
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
  'Run `bashful scripts/bash-tool.sh` or `ssh scripts/bash-tool.sh`.' \
  'Run `fish scripts/bash-tool.sh` or `scripts/fish scripts/bash-tool.sh`.' \
  'Run `scripts/posix-tool.sh scripts/bash-tool.sh`.'; do
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
printf '#!/bin/bashful\n# Usage:\n#   posix-tool.sh\n' >"$tmp/shebang/scripts/posix-tool.sh"
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
for lib in "$tmp/libsonly/scripts/"*.sh; do
  printf '# shellcheck shell=sh\n' >"$lib"
done
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
# A UTF-8-normalizing file system (macOS/APFS) refuses the lone 8-bit CSI byte
# in a name, so there the name carries ESC only and the CSI case is skipped;
# the Linux runs are where it has teeth.
if mv "$tmp/ctl/skills/demo" "$tmp/ctl/skills/de${esc}[2Jmo${csi}2J" 2>/dev/null; then
  c1_name=1
else
  mv "$tmp/ctl/skills/demo" "$tmp/ctl/skills/de${esc}[2Jmo" || exit 1
  c1_name=0
fi
out="$("$CHECKER" --repo-root "$tmp/ctl" 2>&1)"
assert "the control-byte fixture still fails" 1 $?
assert_not_contains "no ESC reaches the output" "$out" "$esc"
if [ "$c1_name" -eq 1 ]; then
  assert_not_contains "no 8-bit CSI reaches the output" "$out" "$csi"
else
  echo "ok: no 8-bit CSI reaches the output (skipped: this file system refuses the byte in a name)"
fi

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

# ---------------------------------------------------------------------------
# 9. Usage headers (review-effectiveness REQ-F1.7): an invocation in a code
#    span or fenced command line is checked against the invoked script's
#    `# Usage` header. The clean fixture's usage skill holds the conforming
#    and the unchecked forms; each case below appends to it.
# ---------------------------------------------------------------------------
# uvariant <name> <line>... — the clean fixture, its usage skill extended.
uvariant() {
  cp -R "$FIXTURES/clean" "$tmp/$1" || exit 1
  v_dir="$tmp/$1"
  shift
  printf '%s\n' "$@" >>"$v_dir/skills/usage/SKILL.md" || exit 1
}
u_line=$(($(wc -l <"$FIXTURES/clean/skills/usage/SKILL.md") + 1))

# usage_fails <offset> <reason> <line>... — the appended lines fail, the
# finding naming the reason and the appended line <offset> past the first.
usage_fails() {
  uf_at=$((u_line + $1))
  uf_reason="$2"
  shift 2
  uf_label="$*"
  uvariant uf "$@"
  out="$("$CHECKER" --repo-root "$tmp/uf" 2>&1)"
  assert "flagged: $uf_label" 1 $?
  assert_contains "the line is named: $uf_label" "$out" "skills/usage/SKILL.md:$uf_at:"
  assert_contains "the reason is given: $uf_label" "$out" "$uf_reason"
  rm -rf "$tmp/uf"
}

usage_fails 0 "unknown subcommand 'launch' (its usage header lists: run, list)" 'Run `scripts/sub-tool.sh launch --spec <dir> 5`.'
usage_fails 0 "unknown subcommand 'lst'" 'Run `git log | scripts/sub-tool.sh lst`.'
usage_fails 0 "flag '--verbose' is not in its usage header" 'Run `scripts/sub-tool.sh list --verbose`.'
usage_fails 0 "flag '--dry-run' is not in its usage header" 'Run `scripts/sub-tool.sh list --dry-run`.'
usage_fails 0 "missing required argument <task>" 'Run `scripts/sub-tool.sh run --spec <dir>`.'
usage_fails 0 "missing required flag --spec" 'Run `scripts/sub-tool.sh run 5`.'
usage_fails 0 "missing required flag --spec" 'Run `scripts/sub-tool.sh run ...`, an ellipsis standing for nothing.'
usage_fails 0 "missing required argument <task>" 'Run `scripts/sub-tool.sh run --spec <dir> ...`.'
usage_fails 0 "missing a value for --spec" 'Run `scripts/sub-tool.sh run 5 --spec`.'
usage_fails 0 "unexpected argument 'extra'" 'Run `scripts/sub-tool.sh list extra`.'
usage_fails 0 "no usage header" 'Run `scripts/nohdr-tool.sh --any`.'
usage_fails 0 "no usage header" 'Run `sh scripts/nohdr-tool.sh`.'
usage_fails 1 "missing a subcommand" '```sh' 'scripts/sub-tool.sh' '```'
usage_fails 0 "flag '--bogus' is not in its usage header" 'Run `scripts/sub-tool.sh run' '--bogus <x>` across a wrapped span.'
usage_fails 1 "flag '--bogus' is not in its usage header" '```sh' "scripts/sub-tool.sh run \\" '  --bogus' '```'
usage_fails 1 "flag '--bogus' is not in its usage header" '```' 'x=$(scripts/sub-tool.sh list --bogus)' '```'

for hdr in '# Usage: badhdr-tool.sh {start,stop}' '# Usage:' '# Usage: something else entirely' \
  '# Usage: badhdr-tool.sh <id> | --all' '# Usage: badhdr-tool.sh [start'; do
  uvariant badhdr 'Run `scripts/badhdr-tool.sh start`.'
  printf '#!/bin/sh\n%s\n:\n' "$hdr" >"$tmp/badhdr/scripts/badhdr-tool.sh"
  out="$("$CHECKER" --repo-root "$tmp/badhdr" 2>&1)"
  assert "an unparseable header fails: $hdr" 1 $?
  assert_contains "the unparseable header is named: $hdr" "$out" "no usage header the grammar parses"
  rm -rf "$tmp/badhdr"
done

for form in \
  'Run `scripts/sub-tool.sh run --spec <dir> <task>`.' \
  'Run `scripts/sub-tool.sh <verb> --spec <dir> <task>`, the subcommand a placeholder.' \
  'Run `scripts/sub-tool.sh run --spec x --mode fast 1 2 3`.' \
  'Run `scripts/sub-tool.sh list` alone.' \
  'Mention `scripts/nohdr-tool.sh` alone, or `scripts/nohdr-tool.sh`'"'"'s header.' \
  'Source it: `. scripts/nohdr-tool.sh --any`.' \
  'Run `scripts/posix-tool.sh scripts/nohdr-tool.sh`, a path argument.' \
  'Say scripts/nohdr-tool.sh --any in prose, outside code.' \
  'Run `scripts/missing-tool.sh --any` (no such script).' \
  '    scripts/nohdr-tool.sh --any (an indented block is not a fence)'; do
  uvariant up "$form"
  out="$("$CHECKER" --repo-root "$tmp/up" 2>&1)"
  assert "not flagged: $form" 0 $?
  rm -rf "$tmp/up"
done

# Each rule of the header grammar and of command position, against
# feat-tool.sh, whose header uses all of them.
usage_fails 0 "missing required flag --to|--to-worker" 'Run `scripts/feat-tool.sh send --message-file f`.'
usage_fails 0 "missing required flag --pid|--session" 'Run `scripts/feat-tool.sh wait`.'
usage_fails 0 "unexpected argument 'b'" 'Run `scripts/feat-tool.sh pick a b`.'
usage_fails 0 "missing a value for --name" 'Run `scripts/feat-tool.sh pick --name`.'
usage_fails 0 "missing a value for -n" 'Run `scripts/feat-tool.sh pick -n`.'
usage_fails 0 "unexpected argument 'a'" 'Run `scripts/feat-tool.sh rows a`.'
usage_fails 0 "flag '--' is not in its usage header" 'Run `scripts/feat-tool.sh rows -- x`.'
usage_fails 0 "missing required argument <label>" 'Run `scripts/feat-tool.sh tag 7 on`.'
usage_fails 0 "missing required argument <task>" 'Run `scripts/sub-tool.sh run --spec <dir> …`, the one-character ellipsis.'
usage_fails 0 "flag '-hx' is not in its usage header" 'Run `scripts/sub-tool.sh -hx`.'
usage_fails 0 "flag '--bogus' is not in its usage header" 'Run `scripts/sub-tool.sh --spec x run 5 --bogus`.'
usage_fails 0 "missing a subcommand" 'Run `scripts/feat-tool.sh | jq .`, not a bare mention.'
for form in \
  'Run `FOO=1 scripts/feat-tool.sh lst`.' \
  'Run `env FOO=1 scripts/feat-tool.sh lst`.' \
  'Run `env -i scripts/feat-tool.sh lst`.' \
  'Run `time -p scripts/feat-tool.sh lst`.' \
  'Run `! scripts/feat-tool.sh lst`.' \
  'Run `>/dev/null scripts/feat-tool.sh lst`.' \
  'Run `bash -euo pipefail scripts/feat-tool.sh lst`.' \
  'A stray ``` here, then `scripts/feat-tool.sh lst` there.'; do
  usage_fails 0 "unknown subcommand 'lst'" "$form"
done
usage_fails 1 "unknown subcommand 'lst'" '- a stray ` tick' '- run `scripts/feat-tool.sh lst`'
usage_fails 1 "unknown subcommand 'lst'" '```sh' '$ scripts/feat-tool.sh lst' '```'
usage_fails 1 "unknown subcommand 'lst'" '```sh' 'if scripts/feat-tool.sh lst; then :; fi' '```'
usage_fails 1 "unknown subcommand 'lst'" '```sh' 'x="`scripts/feat-tool.sh lst`"' '```'
usage_fails 1 "unknown subcommand 'lst'" '```sh' "scripts/feat-tool.sh lst \\" '```'
usage_fails 1 "unknown subcommand 'lst'" '- ```sh' '  scripts/feat-tool.sh lst' '  ```'

for form in \
  'Run `scripts/feat-tool.sh show <the spec dir>`.' \
  'Run `scripts/feat-tool.sh show x --json < e.jsonl > out.txt`.' \
  'Run `scripts/feat-tool.sh show x [--json]`, the flag marked optional.' \
  'Run `scripts/feat-tool.sh send --to /run/s --message-file f`.' \
  'Run `scripts/feat-tool.sh tag '"'"'7'"'"' on x`.' \
  'Run `scripts/feat-tool.sh pick --name v a`.' \
  'Run `scripts/feat-tool.sh exec -- ls -la`.' \
  'Run `scripts/feat-tool.sh wait --session 3`.' \
  'Run `scripts/feat-tool.sh rows --tag a --tag b -1`.' \
  'Run `scripts/feat-tool.sh peek 4`, a path-named synopsis.' \
  'Run `bash -n scripts/feat-tool.sh`, which runs nothing.' \
  'Run `sh -c "scripts/feat-tool.sh lst"`, a string.' \
  'Run `scripts/feat-tool.sh show x # lst`, the rest a comment.' \
  'Open `scripts/feat-tool.sh' '' 'lst` after a blank line.'; do
  uvariant up "$form"
  out="$("$CHECKER" --repo-root "$tmp/up" 2>&1)"
  assert "not flagged: $form" 0 $?
  rm -rf "$tmp/up"
done
uvariant up '```sh' "cat >note.md <<'EOF'" 'scripts/feat-tool.sh lst is data' 'EOF' 'scripts/feat-tool.sh peek 1' '```'
out="$("$CHECKER" --repo-root "$tmp/up" 2>&1)"
assert "a heredoc body is not a command" 0 $?
rm -rf "$tmp/up"

# A header with CRLF line ends reads like one without.
uvariant crlf 'Run `scripts/feat-tool.sh peek 4`.' 'Run `scripts/feat-tool.sh lst`.'
printf '#!/bin/sh\r\n# Usage:\r\n#   feat-tool.sh peek <id>\r\n:\r\n' >"$tmp/crlf/scripts/feat-tool.sh"
out="$("$CHECKER" --repo-root "$tmp/crlf" 2>&1)"
assert "a CRLF header is read" 1 $?
assert_contains "the CRLF header's subcommand is known" "$out" "lists: peek)"
assert_not_contains "the conforming call against the CRLF header passes" "$out" "SKILL.md:$u_line:"
rm -rf "$tmp/crlf"

# Every usage finding is reported in one run, beside an sh finding.
uvariant umany 'Run `scripts/sub-tool.sh lst`.' 'Run `sh scripts/bash-tool.sh --nope`.'
out="$("$CHECKER" --repo-root "$tmp/umany" 2>&1)"
assert "two kinds of finding fail together" 1 $?
assert_contains "the usage finding is named" "$out" "skills/usage/SKILL.md:$u_line:"
assert_contains "the sh finding is named" "$out" "shebang names bash"
assert_contains "the second line's usage finding is named" "$out" "skills/usage/SKILL.md:$((u_line + 1)): scripts/bash-tool.sh: flag '--nope'"

if [ "$failures" -gt 0 ]; then
  echo "test-check-script-invocation: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-script-invocation: all passed"
