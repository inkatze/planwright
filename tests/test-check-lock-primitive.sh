#!/bin/bash
# Tests for scripts/check-lock-primitive.sh — the retired-mkdir guard.
#
# The guard flags a `mkdir` WITHOUT -p whose exit status is read, because that
# pair is what makes a mkdir a lock: the script is asking the kernel "did I win
# this path", and the mkdir answer to that question was measured wrong. The
# cases below are organised around the two ways such a guard fails. It can
# MISS — the status consumed by a form nobody thought of, nested in a subshell,
# or read on the line below — and it can FLAG WHAT IT MUST NOT: the ~40
# `mkdir -p` error checks the tree already carries, the prose in a comment or a
# heredoc, an identifier that merely contains the letters.
#
# The annotation is the third axis. It exempts only with a reason, only on the
# mkdir line or the line directly above it, and a reasonless one is an offense
# of its own — otherwise the escape hatch becomes a blanket.
#
# The fail-closed arm is the last. Anything that would make the scan cover less
# than it claims — an absent root or scope directory, an unreadable file, a
# scan reaching nothing — must exit 2 rather than report a clean tree.
#
# shellcheck disable=SC2016 # every fixture body below is literal shell text
# the guard must read as written; expanding it here would defeat the fixture.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-lock-primitive.sh"

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
    printf '%s\n' "$wf_line"
  done >"$wf_path" || exit 1
}

# write_script <path> <line>... — a shebang-bearing file.
write_script() {
  ws_path="$1"
  shift
  write_file "$ws_path" '#!/bin/sh' 'set -u' "$@"
}

# ---------------------------------------------------------------------------
# 1. Each offending form, one fixture each. A guard that catches `if mkdir` and
#    nothing else would look healthy on this repo's most visible lock and still
#    let every other spelling through.
# ---------------------------------------------------------------------------
make_root "$tmp/forms"
write_script "$tmp/forms/scripts/if.sh" \
  'if mkdir "$lock" 2>/dev/null; then' \
  '  exit 0' \
  'fi'
write_script "$tmp/forms/scripts/elif.sh" \
  'if [ -d "$lock" ]; then' \
  '  exit 1' \
  'elif mkdir "$lock"; then' \
  '  exit 0' \
  'fi'
write_script "$tmp/forms/scripts/bang.sh" \
  'if ! mkdir "$lock" 2>/dev/null; then' \
  '  exit 1' \
  'fi'
write_script "$tmp/forms/scripts/while.sh" \
  'while mkdir "$lock" 2>/dev/null; do' \
  '  break' \
  'done'
write_script "$tmp/forms/scripts/until.sh" \
  'until mkdir "$lock" 2>/dev/null; do' \
  '  sleep 1' \
  'done'
write_script "$tmp/forms/scripts/and.sh" 'mkdir "$lock" && exit 0'
write_script "$tmp/forms/scripts/or.sh" 'mkdir -- "$lock" || return 1'
write_script "$tmp/forms/scripts/besteffort.sh" 'mkdir "$lock" 2>/dev/null || true'
write_script "$tmp/forms/tests/then.sh" \
  'if' \
  '  mkdir "$lock"; then' \
  '  exit 0' \
  'fi'
write_script "$tmp/forms/scripts/bslash.sh" '\mkdir "$lock" && exit 0'
write_script "$tmp/forms/scripts/dq.sh" '"mkdir" "$lock" && exit 0'
write_script "$tmp/forms/scripts/sq.sh" "'mkdir' \"\$lock\" && exit 0"
write_script "$tmp/forms/scripts/split.sh" 'mk"dir" "$lock" && exit 0'
out="$(/bin/bash "$CHECKER" "$tmp/forms" 2>&1)"
assert "every status-consuming mkdir form fails" 1 $?
assert_contains "the if form is named" "$out" "scripts/if.sh:3:"
assert_contains "the elif form is named" "$out" "scripts/elif.sh:5:"
assert_contains "the negated form is named" "$out" "scripts/bang.sh:3:"
assert_contains "the while form is named" "$out" "scripts/while.sh:3:"
assert_contains "the until form is named" "$out" "scripts/until.sh:3:"
assert_contains "the && form is named" "$out" "scripts/and.sh:3:"
assert_contains "the || form is named" "$out" "scripts/or.sh:3:"
assert_contains "a best-effort '|| true' counts as consuming the status" "$out" "scripts/besteffort.sh:3:"
# A quoting spelling is still the command. `\mkdir` is the documented way to
# bypass a function or alias of the same name, and it runs the same binary, so
# a guard that reads it as a different word is one escaped character away from
# being bypassed on purpose.
assert_contains "a backslash-escaped mkdir is still mkdir" "$out" "scripts/bslash.sh:3:"
assert_contains "a double-quoted mkdir is still mkdir" "$out" "scripts/dq.sh:3:"
assert_contains "a single-quoted mkdir is still mkdir" "$out" "scripts/sq.sh:3:"
assert_contains "a mkdir split across a quote is still mkdir" "$out" "scripts/split.sh:3:"
# The same reading applied to the options, where it cuts the other way: a
# quoted `-p` is still `-p`, so flagging it would be a false report against a
# site that is not a lock at all.
make_root "$tmp/quotedopt"
write_script "$tmp/quotedopt/scripts/esc.sh" 'mkdir \-p "$d" || exit 1'
write_script "$tmp/quotedopt/scripts/dqopt.sh" 'mkdir "-p" "$d" || exit 1'
out2="$(/bin/bash "$CHECKER" "$tmp/quotedopt" 2>&1)"
assert "a quoted -p is read as -p, so the tree is clean" 0 $?
assert_not_contains "an escaped -p is not reported" "$out2" "esc.sh"
assert_not_contains "a double-quoted -p is not reported" "$out2" "dqopt.sh"
assert_contains "the '; then' form is named" "$out" "tests/then.sh:4:"
assert_contains "the '; then' offense says which form it is" "$out" "tested by a following 'then'"
assert_contains "the remedy names the lock library" "$out" "scripts/lock-lib.sh"
assert_contains "the remedy names the annotation" "$out" "not-a-lock:"

# ---------------------------------------------------------------------------
# 2. The same forms nested, where a line-anchored match loses them: inside a
#    subshell, inside a brace group, and after `;`, `|`, `&&` or `||`.
# ---------------------------------------------------------------------------
make_root "$tmp/nested"
write_script "$tmp/nested/scripts/subshell.sh" '(mkdir "$lock" 2>/dev/null && printf held) &'
write_script "$tmp/nested/scripts/group.sh" '{ mkdir "$lock" || exit 1; }'
write_script "$tmp/nested/scripts/semi.sh" 'printf start; mkdir "$lock" && printf held'
write_script "$tmp/nested/scripts/pipe.sh" 'printf x | grep -q x; mkdir "$lock" || exit 1'
write_script "$tmp/nested/tests/chained.sh" '[ -d "$lock" ] || mkdir "$lock" || exit 1'
write_script "$tmp/nested/tests/subcond.sh" \
  'if (mkdir "$lock"); then' \
  '  exit 0' \
  'fi'
out="$(/bin/bash "$CHECKER" "$tmp/nested" 2>&1)"
assert "nested status consumption fails" 1 $?
assert_contains "the subshell form is named" "$out" "scripts/subshell.sh:3:"
assert_contains "the brace-group form is named" "$out" "scripts/group.sh:3:"
assert_contains "the form after ';' is named" "$out" "scripts/semi.sh:3:"
assert_contains "the form after a pipeline is named" "$out" "scripts/pipe.sh:3:"
assert_contains "the form reached through '||' is named" "$out" "tests/chained.sh:3:"
assert_contains "a subshell inside a condition is named" "$out" "tests/subcond.sh:3:"

# ---------------------------------------------------------------------------
# 3. The status read on the NEXT line. `mkdir` then `rc=$?` is the same lock
#    with the test moved one line down, and nothing on the mkdir line shows it.
# ---------------------------------------------------------------------------
make_root "$tmp/rc"
write_script "$tmp/rc/scripts/next.sh" \
  'mkdir "$lock"' \
  'rc=$?' \
  '[ "$rc" -eq 0 ] || exit 1'
write_script "$tmp/rc/tests/spaced.sh" \
  'mkdir "$lock"' \
  '' \
  '# the acquire either won or it did not' \
  'status=$?'
out="$(/bin/bash "$CHECKER" "$tmp/rc" 2>&1)"
assert "a status read on the next line fails" 1 $?
assert_contains "the next-line read names the mkdir line" "$out" "scripts/next.sh:3:"
assert_contains "the offense says the status is read as \$?" "$out" "read on the next line"
assert_contains "blank and comment lines do not break the next-line read" "$out" "tests/spaced.sh:3:"

# A plain mkdir whose status nobody reads is not a lock, and neither is one
# followed by ordinary code.
make_root "$tmp/unread"
write_script "$tmp/unread/scripts/plain.sh" \
  'mkdir "$dir"' \
  'printf done'
write_script "$tmp/unread/tests/later.sh" \
  'mkdir "$dir"' \
  'run_thing "$dir" >/dev/null 2>&1' \
  'rc=$?'
out="$(/bin/bash "$CHECKER" "$tmp/unread" 2>&1)"
assert "a mkdir whose status nobody reads passes" 0 $?
assert_contains "the clean run reports a file count" "$out" "check-lock-primitive: clean ("

# ---------------------------------------------------------------------------
# 4. Every `-p` spelling is exempt. A mkdir -p succeeds on a directory that
#    already exists, so its status cannot signal exclusion — and the tree
#    carries dozens of `if ! mkdir -p ...; then` error checks that a guard
#    flagging them would bury.
# ---------------------------------------------------------------------------
make_root "$tmp/parents"
write_script "$tmp/parents/scripts/check.sh" \
  'if ! mkdir -p "$dir"; then' \
  '  exit 1' \
  'fi'
write_script "$tmp/parents/scripts/long.sh" 'mkdir --parents "$dir" || exit 1'
write_script "$tmp/parents/scripts/cluster.sh" 'mkdir -pv "$dir" && printf made'
write_script "$tmp/parents/scripts/mode.sh" 'mkdir -m 0700 -p "$dir" 2>/dev/null || true'
write_script "$tmp/parents/tests/after-operand.sh" 'mkdir "$a" -p && printf made'
write_script "$tmp/parents/tests/nextline.sh" \
  'mkdir -p "$dir"' \
  'rc=$?'
write_script "$tmp/parents/githooks/pre-commit" 'mkdir -p "$dir" || exit 1'
out="$(/bin/bash "$CHECKER" "$tmp/parents" 2>&1)"
assert "no -p spelling is flagged" 0 $?
assert_not_contains "the -p error check is not named" "$out" "scripts/check.sh"

# ---------------------------------------------------------------------------
# 5. Prose is not code. Every file that documents this rule quotes the shape it
#    forbids, so a guard that reads a comment, a heredoc body or a
#    single-quoted string as a call would flag its own explanation.
# ---------------------------------------------------------------------------
make_root "$tmp/prose"
write_script "$tmp/prose/scripts/commented.sh" \
  '# if mkdir "$lock"; then ... was the old shape' \
  '    # mkdir "$lock" || exit 1' \
  'printf fine'
write_script "$tmp/prose/scripts/heredoc.sh" \
  "cat <<'DOC'" \
  'if mkdir "$lock"; then' \
  '  exit 0' \
  'fi' \
  'DOC' \
  'printf fine'
write_script "$tmp/prose/scripts/heredoc-unquoted.sh" \
  'cat <<DOC' \
  'mkdir "$lock" || exit 1' \
  'DOC' \
  'printf fine'
write_script "$tmp/prose/tests/quoted.sh" \
  "printf '%s\\n' 'mkdir \"\$lock\" || exit 1'" \
  'printf fine'
write_script "$tmp/prose/tests/message.sh" \
  'printf "%s\n" "mkdir failed" || exit 1'
write_script "$tmp/prose/githooks/pre-push" \
  'for t in awk mkdir sed; do' \
  '  command -v "$t" >/dev/null || exit 1' \
  'done'
out="$(/bin/bash "$CHECKER" "$tmp/prose" 2>&1)"
assert "prose mentioning the shape is not flagged" 0 $?

# An identifier that merely contains the letters is not the command.
make_root "$tmp/ident"
write_script "$tmp/ident/scripts/idents.sh" \
  'mkdir_failure_kind=none' \
  '_mkdir_rc=0' \
  'printf "%s" "$mkdir_out" || exit 1' \
  '[ "$_mkdir_rc" -eq 0 ] && printf ok'
out="$(/bin/bash "$CHECKER" "$tmp/ident" 2>&1)"
assert "identifiers containing the letters are not flagged" 0 $?
assert_not_contains "no identifier is reported" "$out" "scripts/idents.sh"

# ---------------------------------------------------------------------------
# 6. The annotation, in both placements, exempts a real status read.
# ---------------------------------------------------------------------------
make_root "$tmp/annot"
write_script "$tmp/annot/scripts/trailing.sh" \
  'mkdir -m 0700 "$d" 2>/dev/null || true # not-a-lock: best-effort bootstrap, EEXIST is success'
write_script "$tmp/annot/scripts/above.sh" \
  '# not-a-lock: a deliberate mkdir-atomicity probe, not an acquisition' \
  'if mkdir "$probe" 2>/dev/null; then' \
  '  printf won' \
  'fi'
write_script "$tmp/annot/tests/nextline.sh" \
  '# not-a-lock: mode-pinned bootstrap where EEXIST is success' \
  'mkdir -m 0700 "$d"' \
  'rc=$?'
out="$(/bin/bash "$CHECKER" "$tmp/annot" 2>&1)"
assert "an annotated site with a reason is exempt in both placements" 0 $?

# The annotation must sit on the mkdir line or the line directly above it. One
# that can drift away from its site stops being about that site.
make_root "$tmp/drift"
write_script "$tmp/drift/scripts/gap.sh" \
  '# not-a-lock: this reason belongs to something else entirely' \
  '' \
  'if mkdir "$lock"; then' \
  '  exit 0' \
  'fi'
out="$(/bin/bash "$CHECKER" "$tmp/drift" 2>&1)"
assert "an annotation separated by a blank line exempts nothing" 1 $?
assert_contains "the drifted-annotation site is still named" "$out" "scripts/gap.sh:5:"

# A reasonless annotation exempts nothing and is reported distinctly.
make_root "$tmp/noreason"
write_script "$tmp/noreason/scripts/bare.sh" \
  '# not-a-lock:' \
  'if mkdir "$lock"; then' \
  '  exit 0' \
  'fi'
write_script "$tmp/noreason/tests/trailing.sh" \
  'mkdir "$d" || true # not-a-lock:   '
out="$(/bin/bash "$CHECKER" "$tmp/noreason" 2>&1)"
assert "a reasonless annotation fails" 1 $?
assert_contains "the reasonless annotation is reported on its own line" "$out" "scripts/bare.sh:3:"
assert_contains "the reasonless annotation is named as such" "$out" "annotation with no reason"
assert_contains "the site it failed to exempt is still named" "$out" "scripts/bare.sh:4:"
assert_contains "a reasonless trailing annotation is reported too" "$out" "tests/trailing.sh:3:"

# ---------------------------------------------------------------------------
# 7. Reach: an extensionless githooks/ hook (the case a *.sh glob misses) and a
#    shebang-less sourced library (the mirror gap). lock-lib.sh itself is such
#    a library, so a shared lock helper would live in exactly that shape.
# ---------------------------------------------------------------------------
make_root "$tmp/reach"
write_file "$tmp/reach/githooks/pre-commit" \
  '#!/bin/sh' \
  'if mkdir "$lock"; then exit 0; fi'
write_file "$tmp/reach/scripts/helper.sh" \
  '# shellcheck shell=sh' \
  'take() { mkdir "$1" || return 1; }'
write_file "$tmp/reach/tests/lib/support.sh" \
  '# shellcheck shell=bash' \
  'hold() { mkdir "$1" && return 0; }'
write_file "$tmp/reach/tests/notes.txt" 'if mkdir "$lock"; then :; fi'
out="$(/bin/bash "$CHECKER" "$tmp/reach" 2>&1)"
assert "hooks, libraries and nested directories are reached" 1 $?
assert_contains "the extensionless hook is named" "$out" "githooks/pre-commit:2:"
assert_contains "the shebang-less library is named" "$out" "scripts/helper.sh:2:"
assert_contains "the nested test library is named" "$out" "tests/lib/support.sh:2:"
assert_not_contains "a non-shell file is not scanned" "$out" "notes.txt"

# ---------------------------------------------------------------------------
# 8. Every offender is reported, not just the first, and the paths are
#    relative to the scanned root rather than absolute.
# ---------------------------------------------------------------------------
make_root "$tmp/many"
write_script "$tmp/many/scripts/one.sh" 'if mkdir "$lock"; then exit 0; fi'
write_script "$tmp/many/tests/two.sh" 'mkdir "$lock" || exit 1'
out="$(/bin/bash "$CHECKER" "$tmp/many" 2>&1)"
assert "multiple offenders fail" 1 $?
assert_contains "the first offender is named" "$out" "scripts/one.sh"
assert_contains "the second offender is named" "$out" "tests/two.sh"
assert_not_contains "offenders are named relative to the root" "$out" "$tmp/many/scripts"

# ---------------------------------------------------------------------------
# 9. Fail-closed. Each of these would otherwise be a scan that covered less
#    than it claims while reporting a clean tree.
# ---------------------------------------------------------------------------
make_root "$tmp/empty"
out="$(/bin/bash "$CHECKER" "$tmp/empty" 2>&1)"
assert "a zero-file enumeration fails closed" 2 $?
assert_contains "the zero-file failure says so" "$out" "no shell files"

mkdir -p "$tmp/partial/scripts"
write_script "$tmp/partial/scripts/ok.sh" 'printf fine'
out="$(/bin/bash "$CHECKER" "$tmp/partial" 2>&1)"
assert "a missing scope directory fails closed" 2 $?
assert_contains "the missing-scope failure names every missing directory" "$out" "tests githooks"

make_root "$tmp/unreadable"
write_script "$tmp/unreadable/scripts/secret.sh" 'printf fine'
chmod 000 "$tmp/unreadable/scripts/secret.sh"
out="$(/bin/bash "$CHECKER" "$tmp/unreadable" 2>&1)"
assert "an unreadable file fails closed" 2 $?
assert_contains "the unreadable failure names the file" "$out" "scripts/secret.sh"
chmod 644 "$tmp/unreadable/scripts/secret.sh"

out="$(/bin/bash "$CHECKER" "$tmp/no-such-root" 2>&1)"
assert "a missing root fails closed" 2 $?
assert_contains "the missing-root failure says so" "$out" "root not found"

make_root "$tmp/linkdir"
mkdir -p "$tmp/linkdir-target"
write_script "$tmp/linkdir-target/foreign.sh" 'if mkdir "$lock"; then exit 0; fi'
write_script "$tmp/linkdir/tests/ok.sh" 'printf fine'
ln -s "$tmp/linkdir-target" "$tmp/linkdir/scripts/vendored"
out="$(/bin/bash "$CHECKER" "$tmp/linkdir" 2>&1)"
assert "a symlinked scope subdirectory fails closed" 2 $?
assert_not_contains "the scan does not reach outside the root" "$out" "foreign.sh"

out="$(/bin/bash "$CHECKER" "$tmp/forms" "$tmp/many" 2>&1)"
assert "a second root argument fails closed" 2 $?
assert_contains "the extra-argument failure says so" "$out" "too many arguments"

out="$(/bin/bash "$CHECKER" --strict 2>&1)"
assert "an unknown option fails closed" 2 $?
assert_contains "the unknown-option failure names the option" "$out" "--strict"

# ---------------------------------------------------------------------------
# 10. A root path containing whitespace scans correctly rather than degrading
#     into a misleading empty-tree report.
# ---------------------------------------------------------------------------
make_root "$tmp/with space"
write_script "$tmp/with space/githooks/pre-commit" 'if mkdir "$lock"; then exit 0; fi'
out="$(/bin/bash "$CHECKER" "$tmp/with space" 2>&1)"
assert "a root containing whitespace still scans" 1 $?
assert_contains "the whitespace-root run names the real offender" "$out" "githooks/pre-commit"

# ---------------------------------------------------------------------------
# 11. --help and -h both work and record the escape hatch.
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" --help 2>&1)"
assert "--help exits clean" 0 $?
assert_contains "--help records the annotation" "$out" "# not-a-lock: <reason>"
assert_contains "--help names the replacement primitive" "$out" "pw_lock_acquire"
/bin/bash "$CHECKER" -h >/dev/null 2>&1
assert "-h is accepted too" 0 $?

# ---------------------------------------------------------------------------
# 12. Done-when, on the real corpus. Synthetic fixtures cannot show that the
#     scan survives 300-odd real files: the tree is mid-migration, so the
#     verdict is deliberately not asserted, but a fail-closed exit 2 would mean
#     the enumeration itself broke, and a planted offender must still surface.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/work"
cp -R "$REPO_ROOT/scripts" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/tests" "$tmp/work/" || exit 1
cp -R "$REPO_ROOT/githooks" "$tmp/work/" || exit 1
/bin/bash "$CHECKER" "$tmp/work" >/dev/null 2>&1
real_rc=$?
if [ "$real_rc" -eq 0 ] || [ "$real_rc" -eq 1 ]; then
  echo "ok: the real corpus scans to a verdict rather than failing closed"
else
  echo "FAIL: the real corpus did not scan (exit $real_rc)" >&2
  failures=$((failures + 1))
fi

write_script "$tmp/work/scripts/planted-lock.sh" \
  'if mkdir "$spec_dir/.orchestrate.lock" 2>/dev/null; then' \
  '  exit 0' \
  'fi'
out="$(/bin/bash "$CHECKER" "$tmp/work" 2>&1)"
assert "a lock planted in the real corpus turns the check red" 1 $?
assert_contains "the planted lock is named" "$out" "scripts/planted-lock.sh:3:"

# The guard must not flag the library that replaces the primitive, nor itself:
# both describe the forbidden shape at length.
assert_not_contains "the lock library is not flagged" "$out" "scripts/lock-lib.sh:"
assert_not_contains "the guard does not flag itself" "$out" "scripts/check-lock-primitive.sh:"
assert_not_contains "the guard does not flag its own tests" "$out" "tests/test-check-lock-primitive.sh:"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-lock-primitive tests passed"
