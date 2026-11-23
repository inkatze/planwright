#!/bin/bash
# Tests for scripts/uuid-lib.sh and the two scripts that require it.
#
#   u1: uuid_v4 prints a lowercase v4 uuid, a different one each call.
#   u2: with no randomness to read it prints nothing and returns 1.
#   u3: fleet-streamjson.sh and fleet-messaging.sh refuse to start without it.
#
# Hermetic: scratch copies only. Runs standalone under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../scripts"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -r "$S/uuid-lib.sh" ] || fail "scripts/uuid-lib.sh missing or unreadable"
tmp=$(mktemp -d) || fail "no scratch directory"
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=scripts/uuid-lib.sh
. "$S/uuid-lib.sh"
seen=''
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  u=$(uuid_v4) || fail "u1: uuid_v4 failed on call $i"
  printf '%s\n' "$u" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' \
    || fail "u1: not a lowercase v4 uuid: '$u'"
  case " $seen " in *" $u "*) fail "u1: the same uuid twice: $u" ;; esac
  seen="$seen $u"
done
echo "ok: u1 uuid_v4 prints a fresh lowercase v4 uuid"

# An od that prints nothing, non-hex, or too few bytes: each is refused.
mkdir -p "$tmp/bin"
for u2_body in 'exit 0' "echo ' zz zz zz zz zz zz zz zz zz zz zz zz zz zz zz zz'" "echo ' 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a 0a'"; do
  printf '#!/bin/sh\n%s\n' "$u2_body" >"$tmp/bin/od"
  chmod +x "$tmp/bin/od"
  u2_out=$(PATH="$tmp/bin:$PATH" uuid_v4)
  u2_rc=$?
  [ "$u2_rc" = 1 ] || fail "u2: od printing [$u2_body] must return 1, got $u2_rc"
  [ -z "$u2_out" ] || fail "u2: od printing [$u2_body] must print nothing, got '$u2_out'"
done
echo "ok: u2 missing, non-hex, or short randomness prints nothing and returns 1"

for s in fleet-streamjson.sh fleet-messaging.sh; do
  mkdir -p "$tmp/$s"
  cp "$S/$s" "$S/echo-safety.sh" "$S/lock-lib.sh" "$tmp/$s/"
  case $s in
    fleet-streamjson.sh) u3_out=$(/bin/sh "$tmp/$s/$s" status w1 2>&1) ;;
    *) u3_out=$(/bin/sh "$tmp/$s/$s" self-name 2>&1) ;;
  esac
  u3_rc=$?
  [ "$u3_rc" = 2 ] || fail "u3: $s without uuid-lib.sh must exit 2, got $u3_rc: $u3_out"
  case $u3_out in
    *uuid-lib.sh*) : ;;
    *) fail "u3: $s must name the missing helper: $u3_out" ;;
  esac
done
echo "ok: u3 both scripts refuse to start without the uuid library"
