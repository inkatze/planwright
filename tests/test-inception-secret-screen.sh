#!/bin/bash
# Tests for the venture commit-time secret screen (inception Task 2; REQ-A1.9).
#
# The screen is what the scaffolded pre-commit hook calls, so it has to work on
# a machine with no gitleaks: `PLANWRIGHT_SECRET_SCREEN_TOOL=none` pins the
# built-in pattern path, which is the one every assertion here exercises. The
# gitleaks path is a preference, not a dependency.
#
# The load-bearing property beyond "it finds things" is that it never prints
# what it found: a hook that echoes the secret it caught has moved the secret
# from the diff into the terminal scrollback and the CI log.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN="$REPO_ROOT/scripts/inception-secret-screen.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      printf '%s\n' "$3" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$SCREEN" ]; then
  echo "FAIL: screen missing or not executable at $SCREEN" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

export PLANWRIGHT_SECRET_SCREEN_TOOL=none

# A bundle-shaped file with nothing sensitive in it.
cat >"$tmp/clean.md" <<'EOF'
# Northwind Signals — Brief

The ops leads file once. The integration token lives in the operator keychain
and is never committed; see the wiring notes for how to point the adapter at it.
EOF
out="$("$SCREEN" "$tmp/clean.md" 2>&1)"
rc=$?
assert_eq "clean file: exit 0" "0" "$rc"

# Every seeded credential is assembled at run time from split literals, so this
# file carries no complete credential shape for a scanner to trip over — the
# repo's own `scan:secrets` reads it too, and a fixture that fails the guard it
# was written to exercise is a poor fixture.
mk() { printf '%s\n' "$2" >"$tmp/$1.md"; }
mk aws "aws_key = AKIA""IOSFODNN7EXAMPLE"
mk github "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz"
mk slack "hook = xoxb-""1234567890-abcdefghijklmno"
mk pem "-----BEGIN RSA PRIVATE KEY""-----"
mk generic "api_key = ""s3cr3tVALUE0123456789abcdefXYZ"

for case in aws github slack pem generic; do
  out="$("$SCREEN" "$tmp/$case.md" 2>&1)"
  rc=$?
  assert_eq "$case: exit 1" "1" "$rc"
  assert_contains "$case: names the file" "$case.md" "$out"
  assert_contains "$case: names a line number" "$case.md:1" "$out"
done

# Redaction: the matched text never reaches the output.
out="$("$SCREEN" "$tmp/aws.md" 2>&1)"
assert_not_contains "aws: the matched value is redacted" "IOSFODNN7EXAMPLE" "$out"
out="$("$SCREEN" "$tmp/generic.md" 2>&1)"
assert_not_contains "generic: the matched value is redacted" "s3cr3tVALUE" "$out"

# Echo discipline (doctrine/security-posture.md): a file NAME is repo-controlled
# input, so an escape sequence in one must not reach the terminal raw and drive
# it. The finding is still reported; only the bytes are neutralized.
esc="$(printf '\033')"
mkdir -p "$tmp/esc"
cp "$tmp/pem.md" "$tmp/esc/lea${esc}[31mk.md"
out="$("$SCREEN" "$tmp/esc" 2>&1)"
rc=$?
assert_eq "hostile filename: still reported" "1" "$rc"
assert_not_contains "hostile filename: the escape byte is stripped" "$esc" "$out"
assert_contains "hostile filename: the printable part survives" "31mk.md" "$out"

# A directory argument screens the files under it.
mkdir -p "$tmp/tree/sub"
cp "$tmp/clean.md" "$tmp/tree/ok.md"
out="$("$SCREEN" "$tmp/tree" 2>&1)"
rc=$?
assert_eq "clean directory: exit 0" "0" "$rc"
cp "$tmp/aws.md" "$tmp/tree/sub/leak.md"
out="$("$SCREEN" "$tmp/tree" 2>&1)"
rc=$?
assert_eq "directory with a leak: exit 1" "1" "$rc"
assert_contains "directory: names the offending file" "leak.md" "$out"

# --staged screens the index, not the working tree: the whole point in a hook.
repo="$tmp/repo"
mkdir -p "$repo"
(
  cd "$repo" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
  cp "$tmp/clean.md" brief.md
  git add brief.md
  git commit --no-verify -qm init
) >/dev/null 2>&1 || exit 1

(cd "$repo" && cp "$tmp/aws.md" brief.md)
out="$(cd "$repo" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "unstaged leak: exit 0 (the index is clean)" "0" "$rc"

(cd "$repo" && git add brief.md)
out="$(cd "$repo" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "staged leak: exit 1" "1" "$rc"
assert_contains "staged leak: names the file" "brief.md" "$out"
assert_not_contains "staged leak: the matched value is redacted" "IOSFODNN7EXAMPLE" "$out"

# --staged outside a work tree is an environment error, not a silent pass.
out="$(cd "$tmp" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "--staged outside a work tree: exit 2" "2" "$rc"

# Awkward staged PATHS, in a repo of their own: the cases below turn on the
# screen finding nothing in the file it was pointed at, so a leak left staged by
# an earlier case would mask the very thing being asserted.
awk_repo="$tmp/paths"
mkdir -p "$awk_repo"
(
  cd "$awk_repo" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
  cp "$tmp/clean.md" brief.md
  git add brief.md
  git commit --no-verify -qm init
) >/dev/null 2>&1 || exit 1

# `core.quotePath` defaults on, so a non-ASCII name arrives from `--name-only`
# as a C-quoted string; reading the blob under that literal spelling finds
# nothing, and a screen that treats "could not read it" as "nothing in it"
# reports a credential-bearing file clean.
(cd "$awk_repo" && cp "$tmp/aws.md" "café.md" && git add "café.md") >/dev/null 2>&1
out="$(cd "$awk_repo" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "staged non-ASCII filename: still exit 1" "1" "$rc"
assert_contains "staged non-ASCII filename: names the file" "café.md" "$out"
assert_not_contains "staged non-ASCII filename: the value is redacted" "IOSFODNN7EXAMPLE" "$out"
(cd "$awk_repo" && git rm -q --cached -- "café.md" >/dev/null 2>&1 && rm -f "café.md")

# A newline in a staged path is the other end of the same problem: the name
# survives quoting but not the line-oriented read that follows it, and POSIX sh
# cannot split on NUL. Splitting is not merely lossy — name the pieces after
# other staged files and each piece resolves, so the crafted path is screened
# zero times while the walk still reports clean. The screen must refuse the run
# (exit 2), not flag a leak and not pass.
nl_name="$(printf 'two\nlines.md')"
(cd "$awk_repo" && cp "$tmp/aws.md" "$nl_name" && git add -- "$nl_name") >/dev/null 2>&1
out="$(cd "$awk_repo" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "staged newline-bearing path: refuses the run" "2" "$rc"
assert_contains "staged newline-bearing path: says why" "contains a newline" "$out"
assert_not_contains "staged newline-bearing path: the value is redacted" "IOSFODNN7EXAMPLE" "$out"
(cd "$awk_repo" && git rm -q --cached -- "$nl_name" >/dev/null 2>&1 && rm -f "$nl_name")

# The split-and-hide case explicitly: the crafted path is named so its pieces
# collide with two other staged files, which is what makes every piece resolve
# and the payload itself get read zero times.
(
  cd "$awk_repo" || exit 1
  printf 'nothing here\n' >a
  printf 'nothing here\n' >b.md
  cp "$tmp/aws.md" "$(printf 'a\nb.md')"
  git add -A
) >/dev/null 2>&1
out="$(cd "$awk_repo" && "$SCREEN" --staged 2>&1)"
rc=$?
assert_eq "staged path crafted to split into siblings: not reported clean" "2" "$rc"
assert_not_contains "staged path crafted to split into siblings: value redacted" "IOSFODNN7EXAMPLE" "$out"
(
  cd "$awk_repo" || exit 1
  git rm -q --cached -- a b.md "$(printf 'a\nb.md')" >/dev/null 2>&1
  rm -f a b.md "$(printf 'a\nb.md')"
) >/dev/null 2>&1

# grep decides on its own what counts as binary, and a file it classifies that
# way is skipped entirely rather than merely matched differently. A venture repo
# picks such files up routinely (a UTF-16 note, an exported keystore), so the
# screen must read them as text instead of stepping over them.
printf 'PNG\r\n\032\n\000\000api_key = %s\000\000\377\376' "Abcdefghij0123456789KLMNOP" >"$tmp/blob.bin"
out="$("$SCREEN" "$tmp/blob.bin" 2>&1)"
rc=$?
assert_eq "binary-classified file: still screened" "1" "$rc"
assert_not_contains "binary-classified file: the value is redacted" "Abcdefghij0123456789KLMNOP" "$out"

# The gitleaks arm is the PREFERRED path, so it gets exercised wherever the
# tool is present rather than left to the fallback's coverage. Skipped cleanly
# where it is not: a venture host without gitleaks is the supported case, not a
# broken one.
if command -v gitleaks >/dev/null 2>&1; then
  # A key block, not one of the token fixtures above: gitleaks ships an
  # allowlist for documentation placeholders, so the canonical AWS example key
  # is deliberately NOT a leak to it. Asserting on a shape it does flag is what
  # makes these assertions about our invocation rather than about its ruleset.
  # Split literals again, for the same reason as the fixtures above.
  pk_begin="-----BEGIN RSA PRIVATE KEY""-----"
  pk_end="-----END RSA PRIVATE KEY""-----"
  # Named pk_body, not keybody: gitleaks generic-api-key rule fires on a
  # high-entropy value assigned to a key-shaped name, and this file is inside
  # the repo it is scanning.
  pk_body="MIIEowIBAAKCAQEA7Zx2Lm""9Rt4Wb8Nc1Yv6Ha3Pd5Sj0Ug2EfKq"
  printf -- '%s\n%s\n%s\n' "$pk_begin" "$pk_body" "$pk_end" >"$tmp/key.pem"

  out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/clean.md" 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: clean file exits 0" "0" "$rc"

  out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/key.pem" 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: a leak exits 1" "1" "$rc"
  assert_not_contains "gitleaks arm: the matched value is redacted" "$pk_body" "$out"

  # Each path reports its own result. A shared status would make every clean
  # path after the first hit re-print the previous path's captured output, so
  # one leak across two arguments would read as two.
  mkdir -p "$tmp/leaky" "$tmp/tidy"
  cp "$tmp/key.pem" "$tmp/leaky/k.pem"
  cp "$tmp/clean.md" "$tmp/tidy/ok.md"
  out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/leaky" "$tmp/tidy" 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: a leak in one of two paths exits 1" "1" "$rc"
  assert_eq "gitleaks arm: the clean path reports nothing of its own" "1" \
    "$(printf '%s\n' "$out" | grep -c 'leaks found')"

  (cd "$repo" && cp "$tmp/key.pem" key.pem && git add key.pem) >/dev/null 2>&1
  out="$(cd "$repo" && PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" --staged 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: a staged leak exits 1" "1" "$rc"
  assert_not_contains "gitleaks arm: the staged value is redacted" "$pk_body" "$out"
else
  echo "ok: gitleaks arm: gitleaks absent, preferred-path checks skipped"
fi

# The pre-8.19 subcommand spelling, against a stub rather than an old binary
# nobody has installed. `detect --source` is two words, and the path loop runs
# under IFS=<newline>, so passing it as one string reaches gitleaks as an
# unknown subcommand — whose non-zero exit the loop then reads as a leak. The
# arm would report a leak on every path while scanning none of them.
stub="$tmp/stub"
mkdir -p "$stub"
cat >"$stub/gitleaks" <<'STUB'
#!/bin/sh
# `gitleaks git --help` is the probe for the 8.19+ spelling; fail it so the
# caller falls back to `detect --source`.
[ "$1" = git ] && exit 1
case $1 in
  detect | protect) ;;
  *)
    echo "gitleaks: unknown command \"$1\"" >&2
    exit 1
    ;;
esac
exit 0
STUB
chmod 755 "$stub/gitleaks"

out="$(PATH="$stub:$PATH" PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/tree" 2>&1)"
rc=$?
assert_not_contains "legacy gitleaks: the subcommand reaches it split" "unknown command" "$out"
assert_eq "legacy gitleaks: a clean scan is not reported as a leak" "0" "$rc"

# A path whose NAME carries a newline. The --staged reader refuses these outright
# because it cannot read them unambiguously; the directory walk can, because the
# names go to the screen as arguments rather than as lines of text. The failure
# this pins is the silent one: the walk used to split such a name into pieces
# that resolve to nothing, screen the file zero times, and exit 0 over an
# unexamined credential.
nl_dir="$tmp/newline-name"
mkdir -p "$nl_dir"
nl_file="$nl_dir/$(printf 'we\nird').txt"
printf '%s\n' "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$nl_file"

out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=none "$SCREEN" "$nl_dir" 2>&1)"
rc=$?
assert_eq "newline-named file: the walk finds it rather than reporting clean" "1" "$rc"
assert_contains "newline-named file: the rule is named" "github-token" "$out"
assert_not_contains "newline-named file: the value is still redacted" \
  "0123456789abcdefghijklmnopqrstuvwxyz" "$out"

# The same name handed over directly, which is how the walk re-enters the screen.
out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=none "$SCREEN" -- "$nl_file" 2>&1)"
rc=$?
assert_eq "newline-named file: named as an argument, it is screened" "1" "$rc"

# The walk's aggregate verdict still has to be right in both directions: one hit
# among clean siblings reports once, and a tree with nothing in it stays 0.
mixed="$tmp/mixed-tree"
mkdir -p "$mixed"
printf '%s\n' "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$mixed/hit.md"
printf 'nothing to see here\n' >"$mixed/clean.md"
out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=none "$SCREEN" "$mixed" 2>&1)"
rc=$?
assert_eq "mixed tree: exit 1" "1" "$rc"
assert_contains "mixed tree: the hit is named" "hit.md:1" "$out"
assert_eq "mixed tree: the summary is printed once, not once per batch" "1" \
  "$(printf '%s\n' "$out" | grep -c 'candidate secrets found')"

allclean="$tmp/clean-tree"
mkdir -p "$allclean"
printf 'nothing to see here\n' >"$allclean/clean.md"
out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=none "$SCREEN" "$allclean" 2>&1)"
rc=$?
assert_eq "clean tree: exit 0" "0" "$rc"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-secret-screen: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-secret-screen: all assertions passed"
