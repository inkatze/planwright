#!/bin/sh
# test-echo-safety.sh — regression coverage for the shared echo-discipline
# sanitizer in scripts/echo-safety.sh. Runs standalone under /bin/bash (the
# bash 3.2 floor); the `test` mise task sources every tests/*.sh under bash.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$here/../scripts/echo-safety.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# C1 controls (0x80-0x9F) must be stripped. Notably CSI (0x9B) is a single-byte
# equivalent of ESC-[; leaving it through would reopen the escape-injection hole
# that C0/DEL stripping alone does not close.
# ---------------------------------------------------------------------------
csi=$(printf 'a\233b') # a <CSI=0x9B> b
out=$(sanitize_printable "$csi")
[ "$out" = "ab" ] || fail "C1 CSI (0x9B) not stripped: got '$out'"

edges=$(printf 'x\200y\237z') # first + last C1 byte
out=$(sanitize_printable "$edges")
[ "$out" = "xyz" ] || fail "C1 range endpoints (0x80/0x9F) not stripped: got '$out'"
echo "ok: sanitize_printable strips C1 controls including CSI (0x9B)"

# ---------------------------------------------------------------------------
# The pre-existing posture still holds: C0 controls (e.g. ESC 0x1B) and DEL
# (0x7F) are stripped; the surviving literal '[0m' is inert with the ESC gone.
# ---------------------------------------------------------------------------
c0=$(printf 'p\033[0mq\177r')
out=$(sanitize_printable "$c0")
[ "$out" = "p[0mqr" ] || fail "C0 (ESC) / DEL not stripped: got '$out'"
echo "ok: sanitize_printable still strips C0 controls and DEL"

# ---------------------------------------------------------------------------
# Printable ASCII passes through untouched.
# ---------------------------------------------------------------------------
out=$(sanitize_printable "hello-world_123 (ok)")
[ "$out" = "hello-world_123 (ok)" ] || fail "printable ASCII altered: got '$out'"
echo "ok: sanitize_printable preserves printable ASCII"

# ---------------------------------------------------------------------------
# When nothing printable remains, the caller's placeholder is used.
# ---------------------------------------------------------------------------
allctl=$(printf '\001\233\177')
out=$(sanitize_printable "$allctl" "(unprintable)")
[ "$out" = "(unprintable)" ] || fail "placeholder not used for all-control input: got '$out'"
echo "ok: sanitize_printable falls back to the placeholder when nothing prints"

echo "PASS: test-echo-safety.sh"
