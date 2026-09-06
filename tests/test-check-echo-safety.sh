#!/bin/bash
# Tests for scripts/check-echo-safety.sh — the printf-not-echo guard over
# sanitize_printable output.
#
# `sanitize_printable` strips control BYTES but legitimately preserves the four
# printable characters `\` `0` `3` `3`. /bin/sh on Linux is dash, whose `echo`
# expands backslash escapes, so `echo "$(sanitize_printable "$x")"` turns that
# literal text back into a live ESC and hands the terminal to whoever authored
# the input. `printf '%s\n'` does not. The sanitizer is correct; the call site
# is where the class lives, which is why this guard reads call sites.
#
# The cases below are organised around the ways such a call site can hide (a
# comment, a heredoc, a single-quoted string, a variable holding the sanitized
# value, a continuation line) and around the ways a guard can cry wolf, which
# is how a guard earns a reputation for noise and gets switched off.
#
# The fail-closed arm is the other half: anything that would make the scan
# cover less than it claims must exit 2 rather than report a clean tree. The
# allowlist has its own fail-closed rule — an entry that no longer violates is
# exit 2, so the allowlist cannot outlive the PRs it exists for.
#
# shellcheck disable=SC2016 # every fixture body below is literal shell text
# the guard must read as written; expanding it here would defeat the fixture.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-echo-safety.sh"

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

make_root() {
  mkdir -p "$1/scripts" "$1/tests" "$1/githooks" || exit 1
}

# write_file <path> <line>... — verbatim, no shebang added.
write_file() {
  wf_path="$1"
  shift
  mkdir -p "$(dirname "$wf_path")" || exit 1
  for wf_line in "$@"; do
    echo "$wf_line"
  done >"$wf_path" || exit 1
}

# write_script <path> <line>... — a file with the at-risk interpreter.
write_script() {
  ws_path="$1"
  shift
  write_file "$ws_path" '#!/bin/sh' 'set -u' "$@"
}

# Every fixture root needs at least one file in each scope directory or the
# zero-file fail-closed arm fires instead of the case under test. `filler`
# calls the sanitizer safely, so it also proves the clean shape stays clean in
# every one of these roots.
filler() {
  write_script "$1/tests/filler.sh" 'printf "%s\n" "$(sanitize_printable "$x")"'
  write_script "$1/githooks/filler" 'printf "%s\n" "ok"'
}

# ---------------------------------------------------------------------------
# 1. The real tree passes, and the count is asserted rather than discarded.
#    The count is the only evidence distinguishing "scanned the tree and found
#    nothing" from "scanned almost nothing and found nothing".
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" 2>&1)"
assert "the repo's own tree is echo-safety-clean" 0 $?
assert_contains "the clean run reports a file count" "$out" "check-echo-safety: clean ("
assert_contains "the clean run reports the skipped bash-interpreter files" "$out" "not at risk"
real_count="$(printf '%s' "$out" | sed -n 's/.*clean (\([0-9]*\) files.*/\1/p')"
if [ -n "$real_count" ] && [ "$real_count" -ge 100 ]; then
  echo "ok: the scan reached the whole tree ($real_count files)"
else
  echo "FAIL: the scan covered implausibly few files (got '$real_count')" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 2. The defect itself: echo interpolating a sanitize_printable substitution.
#    The printf spelling of the same line is the remedy and must stay clean.
# ---------------------------------------------------------------------------
make_root "$tmp/bad"
filler "$tmp/bad"
write_script "$tmp/bad/scripts/offend.sh" \
  'echo "prefix $(sanitize_printable "$x") suffix" >&2'
out="$(/bin/bash "$CHECKER" "$tmp/bad" 2>&1)"
assert "echo with a sanitize_printable substitution fails" 1 $?
assert_contains "the failure names the offending file" "$out" "scripts/offend.sh"
assert_contains "the failure carries a line number" "$out" "scripts/offend.sh:3"
assert_contains "the failure states the remedy" "$out" "printf"
assert_not_contains "the failure names it relative to the root" "$out" "$tmp/bad/scripts"

make_root "$tmp/good"
filler "$tmp/good"
write_script "$tmp/good/scripts/fine.sh" \
  'printf "%s\n" "prefix $(sanitize_printable "$x") suffix" >&2' \
  'printf >&2 "%s\n" "$(sanitize_printable "$y" "(unprintable)")"'
/bin/bash "$CHECKER" "$tmp/good" >/dev/null 2>&1
assert "the printf spelling of the same call is clean" 0 $?

# ---------------------------------------------------------------------------
# 3. An extensionless githooks/ hook is reached — the case a *.sh glob misses.
# ---------------------------------------------------------------------------
make_root "$tmp/hook"
filler "$tmp/hook"
write_script "$tmp/hook/githooks/pre-commit" \
  'echo "rejected: $(sanitize_printable "$branch")"'
out="$(/bin/bash "$CHECKER" "$tmp/hook" 2>&1)"
assert "an offending extensionless hook fails" 1 $?
assert_contains "the failure names the hook" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 4. A shebang-less .sh library is reached — the mirror gap. The repo's own
#    sourced libraries open with a `# shellcheck shell=` line, and the shared
#    diagnostic helpers that would carry this defect live in exactly such a
#    file.
# ---------------------------------------------------------------------------
make_root "$tmp/lib"
filler "$tmp/lib"
write_file "$tmp/lib/scripts/helper.sh" \
  '# shellcheck shell=bash' \
  'warn() { echo "warn: $(sanitize_printable "$1")" >&2; }'
out="$(/bin/bash "$CHECKER" "$tmp/lib" 2>&1)"
assert "an offending shebang-less .sh library fails" 1 $?
assert_contains "the failure names the library" "$out" "scripts/helper.sh"

# ---------------------------------------------------------------------------
# 5. Prose is not code. A comment mentioning the pattern — which every file
#    that documents this rule contains, including the guard itself — must not
#    be a violation, or the guard cannot describe its own rule.
# ---------------------------------------------------------------------------
make_root "$tmp/prose"
filler "$tmp/prose"
write_script "$tmp/prose/scripts/documented.sh" \
  '# Never write echo "$(sanitize_printable "$x")" — dash re-expands it.' \
  '    # Indented prose about echo "$(sanitize_printable "$y")" is still prose.' \
  'printf "%s\n" "ok" # not echo "$(sanitize_printable "$z")", deliberately' \
  'printf "%s\n" "$(sanitize_printable "$w")"'
out="$(/bin/bash "$CHECKER" "$tmp/prose" 2>&1)"
assert "a comment mentioning the pattern is not a violation" 0 $?
assert_not_contains "the documented file is not named" "$out" "documented.sh"

# ---------------------------------------------------------------------------
# 6. A heredoc body is not code either — a usage message quoting the wrong
#    spelling would otherwise flag the very script that warns against it. And
#    a heredoc operator quoted inside a string opens no heredoc, so believing
#    otherwise would swallow every later line of the file.
# ---------------------------------------------------------------------------
make_root "$tmp/heredoc"
filler "$tmp/heredoc"
write_script "$tmp/heredoc/scripts/usage.sh" \
  "cat <<'DOC'" \
  'Wrong: echo "$(sanitize_printable "$x")"' \
  'DOC' \
  'printf "%s\n" "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/heredoc" 2>&1)"
assert "a heredoc body is not a violation" 0 $?

make_root "$tmp/heredoc-str"
filler "$tmp/heredoc-str"
write_script "$tmp/heredoc-str/scripts/quoted-op.sh" \
  'printf "%s\n" "<<DOC"' \
  'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/heredoc-str" 2>&1)"
assert "a quoted heredoc operator hides nothing after it" 1 $?
assert_contains "the offender after the quoted operator is named" "$out" "quoted-op.sh"

# ---------------------------------------------------------------------------
# 7. A single-quoted string performs no substitution, so it is a mention and
#    not a call. Flagging it would make every script that prints the wrong
#    spelling as advice go red.
# ---------------------------------------------------------------------------
make_root "$tmp/singlequote"
filler "$tmp/singlequote"
write_script "$tmp/singlequote/scripts/advice.sh" \
  'echo '"'"'never write echo "$(sanitize_printable "$x")"'"'"''
out="$(/bin/bash "$CHECKER" "$tmp/singlequote" 2>&1)"
assert "a single-quoted mention is not a call" 0 $?

# ---------------------------------------------------------------------------
# 8. Nesting does not launder the value. `echo "$(printf ... "$(sanitize ...)")"`
#    is still an echo re-expanding sanitized text; only the outermost command
#    decides whether the escapes come back to life.
# ---------------------------------------------------------------------------
make_root "$tmp/nested"
filler "$tmp/nested"
write_script "$tmp/nested/scripts/laundered.sh" \
  'echo "$(printf "%s" "$(sanitize_printable "$x")")"'
out="$(/bin/bash "$CHECKER" "$tmp/nested" 2>&1)"
assert "an inner printf does not launder an outer echo" 1 $?
assert_contains "the nested offender is named" "$out" "scripts/laundered.sh"

# ---------------------------------------------------------------------------
# 9. The value reaching echo through a variable is the same defect one alias
#    away. A guard that only reads the literal call site invites the rename.
# ---------------------------------------------------------------------------
make_root "$tmp/via-var"
filler "$tmp/via-var"
write_script "$tmp/via-var/scripts/aliased.sh" \
  'safe="$(sanitize_printable "$x" "(unprintable)")"' \
  'echo "path: $safe" >&2'
out="$(/bin/bash "$CHECKER" "$tmp/via-var" 2>&1)"
assert "a sanitized value echoed through a variable fails" 1 $?
assert_contains "the variable-indirection offender is named" "$out" "scripts/aliased.sh"
assert_contains "the failure points at the echo, not the assignment" "$out" "aliased.sh:4"

# The braced expansion is the same reference.
make_root "$tmp/via-var-braced"
filler "$tmp/via-var-braced"
write_script "$tmp/via-var-braced/scripts/braced.sh" \
  'safe=$(sanitize_printable "$x")' \
  'echo "path: ${safe}" >&2'
out="$(/bin/bash "$CHECKER" "$tmp/via-var-braced" 2>&1)"
assert "a braced expansion of the sanitized variable fails" 1 $?

# A variable that is also assigned from somewhere else is no longer evidence
# of anything, and guessing there is how a guard starts crying wolf.
make_root "$tmp/reassigned"
filler "$tmp/reassigned"
write_script "$tmp/reassigned/scripts/mixed.sh" \
  'msg="$(sanitize_printable "$x")"' \
  'msg="a fixed string"' \
  'echo "$msg"'
out="$(/bin/bash "$CHECKER" "$tmp/reassigned" 2>&1)"
assert "a variable with a non-sanitized assignment too is not flagged" 0 $?

# ---------------------------------------------------------------------------
# 10. The spellings of `echo` that a word-anchored grep misses.
# ---------------------------------------------------------------------------
make_root "$tmp/spellings"
filler "$tmp/spellings"
write_script "$tmp/spellings/scripts/cmd.sh" 'command echo "$(sanitize_printable "$x")"'
write_script "$tmp/spellings/scripts/bltn.sh" 'builtin echo "$(sanitize_printable "$x")"'
write_script "$tmp/spellings/scripts/chained.sh" 'true && echo "$(sanitize_printable "$x")"'
write_script "$tmp/spellings/scripts/piped.sh" 'true | echo "$(sanitize_printable "$x")"'
write_script "$tmp/spellings/scripts/semi.sh" 'true; echo "$(sanitize_printable "$x")"'
write_script "$tmp/spellings/tests/branch.sh" \
  'if true; then echo "$(sanitize_printable "$x")"; else echo no; fi'
write_script "$tmp/spellings/tests/loop.sh" \
  'for f in a; do echo "$(sanitize_printable "$f")"; done'
write_script "$tmp/spellings/githooks/subshell" '( echo "$(sanitize_printable "$x")" )'
out="$(/bin/bash "$CHECKER" "$tmp/spellings" 2>&1)"
assert "every echo spelling is caught" 1 $?
for f in scripts/cmd.sh scripts/bltn.sh scripts/chained.sh scripts/piped.sh \
  scripts/semi.sh tests/branch.sh tests/loop.sh githooks/subshell; do
  assert_contains "the $f spelling is named" "$out" "$f"
done

# ---------------------------------------------------------------------------
# 11. A sanitize_printable call that never reaches an echo is not a violation.
#     The assignment form is the house pattern and is exactly what the remedy
#     produces, so flagging it would make the fix unrepresentable.
# ---------------------------------------------------------------------------
make_root "$tmp/notecho"
filler "$tmp/notecho"
write_script "$tmp/notecho/scripts/assign.sh" \
  'safe="$(sanitize_printable "$x")"' \
  'printf "%s\n" "$safe"'
write_script "$tmp/notecho/scripts/sequenced.sh" \
  'echo done; other="$(sanitize_printable "$x")"' \
  'printf "%s\n" "$other"'
write_script "$tmp/notecho/tests/compared.sh" \
  'if [ "$p" != "$(sanitize_printable "$p")" ]; then echo refused; fi'
out="$(/bin/bash "$CHECKER" "$tmp/notecho" 2>&1)"
assert "a sanitize call that reaches no echo is clean" 0 $?
assert_not_contains "the sequenced echo does not capture a later assignment" "$out" "sequenced.sh"
assert_not_contains "an echo of unrelated text is not flagged" "$out" "compared.sh"

# ---------------------------------------------------------------------------
# 12. A call split across a continuation line is the same call.
# ---------------------------------------------------------------------------
make_root "$tmp/continued"
filler "$tmp/continued"
# The trailing backslash is built from its octal code rather than written
# literally: every literal spelling of a lone backslash next to a quote trips
# SC1003, and dropping it would stop this being the continuation case at all.
bslash="$(printf '\134')"
write_script "$tmp/continued/scripts/split.sh" \
  "echo \"prefix\" $bslash" \
  '  "$(sanitize_printable "$x")" >&2'
out="$(/bin/bash "$CHECKER" "$tmp/continued" 2>&1)"
assert "a continued echo is caught" 1 $?
assert_contains "the continued offender is named" "$out" "scripts/split.sh"

# ---------------------------------------------------------------------------
# 12b. The interpreter is the hazard, not the directory. Only a shell whose
#      `echo` expands backslash escapes can revive the sanitizer's surviving
#      escape TEXT, and bash's does not. Flagging a bash-shebang file would be
#      a false positive that pushes churn onto a file that is already safe;
#      skipping a shebang-less library would miss the likeliest real one, since
#      a sourced file runs under whichever interpreter sourced it.
# ---------------------------------------------------------------------------
make_root "$tmp/interp"
filler "$tmp/interp"
write_file "$tmp/interp/scripts/dash-sh.sh" '#!/bin/sh' 'echo "$(sanitize_printable "$x")"'
write_file "$tmp/interp/scripts/env-sh.sh" '#!/usr/bin/env sh' 'echo "$(sanitize_printable "$x")"'
write_file "$tmp/interp/githooks/dash-hook" '#!/bin/dash' 'echo "$(sanitize_printable "$x")"'
# No shebang: a sourced library, at risk through its caller. The shellcheck
# directive names bash and must NOT be read as the interpreter — the repo's own
# echo-safety.sh carries exactly such a line and is sourced by /bin/sh scripts.
write_file "$tmp/interp/tests/lib/sourced.sh" '# shellcheck shell=bash' 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/interp" 2>&1)"
assert "the at-risk interpreters are flagged" 1 $?
assert_contains "a /bin/sh script is flagged" "$out" "scripts/dash-sh.sh"
assert_contains "an env sh script is flagged" "$out" "scripts/env-sh.sh"
assert_contains "a dash hook is flagged" "$out" "githooks/dash-hook"
assert_contains "a shebang-less sourced library is flagged" "$out" "tests/lib/sourced.sh"

make_root "$tmp/interp-safe"
filler "$tmp/interp-safe"
write_file "$tmp/interp-safe/scripts/envbash.sh" '#!/usr/bin/env bash' 'echo "$(sanitize_printable "$x")"'
write_file "$tmp/interp-safe/scripts/binbash.sh" '#!/bin/bash' 'echo "$(sanitize_printable "$x")"'
write_file "$tmp/interp-safe/scripts/optbash.sh" '#!/usr/bin/env -S bash -eu' 'echo "$(sanitize_printable "$x")"'
write_file "$tmp/interp-safe/githooks/zsh-hook" '#!/bin/zsh' 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/interp-safe" 2>&1)"
assert "a bash-family interpreter is not at risk and is not flagged" 0 $?
assert_not_contains "the env-bash file is not named" "$out" "envbash.sh"
assert_not_contains "the bin-bash file is not named" "$out" "binbash.sh"
assert_not_contains "the option-bearing env shebang is not named" "$out" "optbash.sh"
assert_not_contains "the zsh hook is not named" "$out" "zsh-hook"

# ---------------------------------------------------------------------------
# 13. The allowlist. It exempts the exact paths of files open in other PRs, and
#     nothing else. An entry that no longer violates is a bookkeeping error, so
#     the allowlist cannot outlive the merges it was created for.
# ---------------------------------------------------------------------------
make_root "$tmp/allow"
filler "$tmp/allow"
write_script "$tmp/allow/scripts/fleet-liveness.sh" 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/allow" 2>&1)"
assert "an allowlisted path is exempt" 0 $?
assert_not_contains "the exempt file is not reported as an offender" "$out" "check-echo-safety: scripts/fleet-liveness.sh"
assert_contains "the clean run says how many files are allowlisted" "$out" "allowlisted"

# The exemption is by exact repo-relative path, not by basename: the same name
# under another directory is a different file and is not exempt.
make_root "$tmp/allow-path"
filler "$tmp/allow-path"
write_script "$tmp/allow-path/scripts/fleet-liveness.sh" 'echo "$(sanitize_printable "$x")"'
write_script "$tmp/allow-path/tests/fleet-liveness.sh" 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/allow-path" 2>&1)"
assert "the allowlist matches a path, not a basename" 1 $?
assert_contains "the same basename elsewhere is still an offender" "$out" "tests/fleet-liveness.sh"

# A stale entry — the file merged and got fixed — must be loud, not silent.
make_root "$tmp/allow-stale"
filler "$tmp/allow-stale"
write_script "$tmp/allow-stale/scripts/fleet-liveness.sh" \
  'printf "%s\n" "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/allow-stale" 2>&1)"
assert "an allowlist entry that no longer violates fails closed" 2 $?
assert_contains "the stale-entry failure names the entry" "$out" "scripts/fleet-liveness.sh"
assert_contains "the stale-entry failure says to remove it" "$out" "remove"

# ---------------------------------------------------------------------------
# 14. Every offender is reported, not just the first.
# ---------------------------------------------------------------------------
make_root "$tmp/many"
filler "$tmp/many"
write_script "$tmp/many/scripts/one.sh" 'echo "$(sanitize_printable "$x")"'
write_script "$tmp/many/tests/two.sh" 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/many" 2>&1)"
assert "multiple offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "scripts/one.sh"
assert_contains "the second offender is named" "$out" "tests/two.sh"

# Nested directories are scanned; the real tree keeps shell under tests/lib/.
make_root "$tmp/deep"
filler "$tmp/deep"
write_script "$tmp/deep/tests/lib/helper.sh" 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/deep" 2>&1)"
assert "an offender below the top level fails" 1 $?
assert_contains "the nested offender is named with its path" "$out" "tests/lib/helper.sh"

# ---------------------------------------------------------------------------
# 15. Fail-closed. Each of these would otherwise be a scan that covered less
#     than it claims while reporting a clean tree.
# ---------------------------------------------------------------------------
make_root "$tmp/empty"
out="$(/bin/bash "$CHECKER" "$tmp/empty" 2>&1)"
assert "a zero-file enumeration fails closed" 2 $?
assert_contains "the zero-file failure says so" "$out" "no sh-interpreted shell files"

mkdir -p "$tmp/partial/scripts"
write_script "$tmp/partial/scripts/ok.sh" 'printf "%s\n" fine'
out="$(/bin/bash "$CHECKER" "$tmp/partial" 2>&1)"
assert "a missing scope directory fails closed" 2 $?
assert_contains "the missing-scope failure names every missing directory" "$out" "tests githooks"

make_root "$tmp/unreadable"
filler "$tmp/unreadable"
write_script "$tmp/unreadable/scripts/secret.sh" 'printf "%s\n" fine'
chmod 000 "$tmp/unreadable/scripts/secret.sh"
out="$(/bin/bash "$CHECKER" "$tmp/unreadable" 2>&1)"
assert "an unreadable file fails closed" 2 $?
assert_contains "the unreadable failure names the file" "$out" "scripts/secret.sh"
chmod 644 "$tmp/unreadable/scripts/secret.sh"

make_root "$tmp/linkdir"
filler "$tmp/linkdir"
mkdir -p "$tmp/linkdir-target"
write_script "$tmp/linkdir-target/foreign.sh" 'echo "$(sanitize_printable "$x")"'
ln -s "$tmp/linkdir-target" "$tmp/linkdir/scripts/vendored"
out="$(/bin/bash "$CHECKER" "$tmp/linkdir" 2>&1)"
assert "a symlinked scope subdirectory fails closed" 2 $?
assert_not_contains "the scan does not reach outside the root" "$out" "foreign.sh"

make_root "$tmp/linkbroken"
filler "$tmp/linkbroken"
ln -s "$tmp/linkbroken/scripts/absent.sh" "$tmp/linkbroken/scripts/dangling.sh"
out="$(/bin/bash "$CHECKER" "$tmp/linkbroken" 2>&1)"
assert "a dangling symlink fails closed" 2 $?
assert_contains "the dangling-symlink failure names it" "$out" "scripts/dangling.sh"

out="$(/bin/bash "$CHECKER" "$tmp/no-such-root" 2>&1)"
assert "a missing root fails closed" 2 $?
assert_contains "the missing-root failure says so" "$out" "root not found"

out="$(/bin/bash "$CHECKER" "$tmp/good" "$tmp/bad" 2>&1)"
assert "a second root argument fails closed" 2 $?
assert_contains "the extra-argument failure says so" "$out" "too many arguments"

out="$(/bin/bash "$CHECKER" --docs 2>&1)"
assert "an unknown option fails closed" 2 $?
assert_contains "the unknown-option failure names the option" "$out" "--docs"

# ---------------------------------------------------------------------------
# 16. A root path containing whitespace scans correctly rather than degrading
#     into a misleading empty-tree report.
# ---------------------------------------------------------------------------
make_root "$tmp/with space"
filler "$tmp/with space"
write_script "$tmp/with space/githooks/pre-commit" 'echo "$(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/with space" 2>&1)"
assert "a root containing whitespace still scans" 1 $?
assert_contains "the whitespace-root run names the real offender" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 17. --help and -h both work and record why the remedy is printf.
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" --help 2>&1)"
assert "--help exits clean" 0 $?
assert_contains "--help names the remedy" "$out" "printf"
assert_contains "--help explains why the sanitizer is not enough" "$out" "dash"
assert_contains "--help documents the allowlist" "$out" "allowlist"
assert_contains "--help says bash-interpreter files are skipped" "$out" "bash"
assert_contains "--help says a shebang-less file is still scanned" "$out" "NO shebang"
/bin/bash "$CHECKER" -h >/dev/null 2>&1
assert "-h is accepted too" 0 $?

# ---------------------------------------------------------------------------
# 18. Done-when, on the real corpus: planting the defect in a copy of the real
#     tree turns the check red. Synthetic fixtures cannot show that the guard
#     still works against 300-odd real files, and the converted files are the
#     thing that has to stay converted.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/work"
cp -R "$REPO_ROOT/scripts" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/tests" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/githooks" "$tmp/work/" || exit 1
/bin/bash "$CHECKER" "$tmp/work" >/dev/null 2>&1
assert "the copied real tree is clean" 0 $?

write_script "$tmp/work/scripts/planted-offender.sh" \
  'echo "planted: $(sanitize_printable "$x")"'
out="$(/bin/bash "$CHECKER" "$tmp/work" 2>&1)"
assert "planting the defect in the real tree turns the check red" 1 $?
assert_contains "the red run names the planted file" "$out" "scripts/planted-offender.sh"
rm -f "$tmp/work/scripts/planted-offender.sh"

# Reverting one converted script to its echo spelling must also go red — this
# is what stops the 28 conversions from silently regressing.
victim="$tmp/work/scripts/spec-status.sh"
if [ ! -f "$victim" ]; then
  echo "FAIL: expected a converted script at scripts/spec-status.sh" >&2
  failures=$((failures + 1))
else
  printf '%s\n' 'echo "reverted: $(sanitize_printable "$x")"' >>"$victim"
  out="$(/bin/bash "$CHECKER" "$tmp/work" 2>&1)"
  assert "reverting a converted script turns the check red" 1 $?
  assert_contains "the red run names the reverted script" "$out" "scripts/spec-status.sh"
  cp "$REPO_ROOT/scripts/spec-status.sh" "$victim"
fi

# ---------------------------------------------------------------------------
# 19. The CDPATH regression convention that scripts/check-cdpath.sh --help
#     prescribes, applied to this guard: it derives its own root through a `cd`
#     substitution, so it gets the CDPATH=. test.
#
#     The decoy is a complete, clean scope tree placed FIRST in CDPATH, and the
#     tree under test holds an offender. A guard whose root derivation survives
#     CDPATH scans the tree under test and goes red naming the offender; one
#     that resolves through the decoy scans the wrong tree and reports clean.
# ---------------------------------------------------------------------------
make_root "$tmp/decoy"
filler "$tmp/decoy"
write_script "$tmp/decoy/scripts/innocuous.sh" 'printf "%s\n" decoy'
write_script "$tmp/work/scripts/planted-offender.sh" \
  'echo "planted: $(sanitize_printable "$x")"'
out="$(cd "$tmp/work" && CDPATH="$tmp/decoy:." /bin/bash scripts/check-echo-safety.sh 2>&1)"
assert "under CDPATH the guard resolves its own root correctly" 1 $?
assert_contains "it scanned the real tree, not the decoy" "$out" "scripts/planted-offender.sh"
assert_not_contains "it did not scan the decoy" "$out" "innocuous.sh"

# ---------------------------------------------------------------------------
# 20. The guard is wired into the `check` aggregate, so a red run is reachable
#     from `mise run check` rather than only by direct invocation.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks\."check:echo-safety"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:echo-safety is defined as a mise task"
else
  echo "FAIL: mise.toml defines no check:echo-safety task" >&2
  failures=$((failures + 1))
fi
if grep -q '"check:echo-safety",' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:echo-safety is wired into the check aggregate"
else
  echo "FAIL: check:echo-safety is not in the check aggregate's depends list" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-echo-safety tests passed"
