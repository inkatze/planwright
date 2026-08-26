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

# Each seeded credential is assembled at run time so this test file itself
# carries no token-shaped literal for a scanner to trip over.
mk() { printf '%s\n' "$2" >"$tmp/$1.md"; }
mk aws "aws_key = AKIA""IOSFODNN7EXAMPLE"
mk github "token: ghp_""0123456789abcdefghijklmnopqrstuvwxyz"
mk slack "hook = xoxb-""1234567890-abcdefghijklmno"
mk pem "-----BEGIN RSA PRIVATE KEY-----"
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

# The gitleaks arm is the PREFERRED path, so it gets exercised wherever the
# tool is present rather than left to the fallback's coverage. Skipped cleanly
# where it is not: a venture host without gitleaks is the supported case, not a
# broken one.
if command -v gitleaks >/dev/null 2>&1; then
  # A key block, not one of the token fixtures above: gitleaks ships an
  # allowlist for documentation placeholders, so the canonical AWS example key
  # is deliberately NOT a leak to it. Asserting on a shape it does flag is what
  # makes these assertions about our invocation rather than about its ruleset.
  keybody="MIIEowIBAAKCAQEA7Zx2Lm9Rt4Wb8Nc1Yv6Ha3Pd5Sj0Ug2EfKq"
  printf -- '-----BEGIN RSA PRIVATE KEY-----\n%s\n-----END RSA PRIVATE KEY-----\n' "$keybody" >"$tmp/key.pem"

  out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/clean.md" 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: clean file exits 0" "0" "$rc"

  out="$(PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" "$tmp/key.pem" 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: a leak exits 1" "1" "$rc"
  assert_not_contains "gitleaks arm: the matched value is redacted" "$keybody" "$out"

  (cd "$repo" && cp "$tmp/key.pem" key.pem && git add key.pem) >/dev/null 2>&1
  out="$(cd "$repo" && PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks "$SCREEN" --staged 2>&1)"
  rc=$?
  assert_eq "gitleaks arm: a staged leak exits 1" "1" "$rc"
  assert_not_contains "gitleaks arm: the staged value is redacted" "$keybody" "$out"
else
  echo "ok: gitleaks arm: gitleaks absent, preferred-path checks skipped"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-inception-secret-screen: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-secret-screen: all assertions passed"
