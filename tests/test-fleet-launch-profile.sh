#!/bin/bash
# scripts/fleet-launch-profile.sh — the settings profile a fleet launch seam
# passes with --settings (fleet-messaging Task 4; D-19, REQ-F1.1). It resolves
# the profile under the planwright root the core root chain names, so
# PLANWRIGHT_ROOT pointing at a copy is the one injector, and refuses visibly,
# naming the profile, when it cannot be read (obs:eea622de).
#   p1  `worker` and `tower` print the absolute profile path under the root
#   p2  --root names the root explicitly, over PLANWRIGHT_ROOT
#   p3  a missing, unreadable, non-regular, or symlinked profile (or config
#       directory) exits 1 naming it
#   p4  an unknown kind or a relative --root is a usage error (2)
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
FLP="$REPO_ROOT/scripts/fleet-launch-profile.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

tmp=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-fleet-launch-profile.XXXXXX")" && pwd -P)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# copy_root <dir> — a planwright root holding the two shipped profiles.
copy_root() {
  mkdir -p "$1/config" "$1/scripts"
  cp "$REPO_ROOT/config/worker-settings.json" "$REPO_ROOT/config/tower-settings.json" "$1/config/"
}

copy_root "$tmp/r1"
for kind in worker tower; do
  out=$(PLANWRIGHT_ROOT="$tmp/r1" /bin/sh "$FLP" "$kind") || fail "p1: $kind exited non-zero"
  [ "$out" = "$tmp/r1/config/$kind-settings.json" ] || fail "p1: $kind printed '$out'"
done
out=$(env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT CLAUDE_DIR="$tmp/nodir" /bin/sh "$FLP" worker) \
  || fail "p1: the self-located root did not resolve"
[ "$out" = "$REPO_ROOT/config/worker-settings.json" ] || fail "p1: the self-located root printed '$out'"

copy_root "$tmp/r2"
out=$(PLANWRIGHT_ROOT="$tmp/r1" /bin/sh "$FLP" tower --root "$tmp/r2") || fail "p2: --root exited non-zero"
[ "$out" = "$tmp/r2/config/tower-settings.json" ] || fail "p2: --root printed '$out'"

check_refused() {
  local label=$1 root=$2 kind=$3 rc=0 out
  out=$(PLANWRIGHT_ROOT="$root" /bin/sh "$FLP" "$kind" 2>"$tmp/err") || rc=$?
  [ "$rc" = 1 ] || fail "p3: $label exited $rc, not 1"
  [ -z "$out" ] || fail "p3: $label printed a path: $out"
  grep -qF "$root/config/$kind-settings.json" "$tmp/err" || fail "p3: $label does not name the profile: $(cat "$tmp/err")"
}
mkdir -p "$tmp/r3/config" "$tmp/r3/scripts"
check_refused "a missing profile" "$tmp/r3" worker
copy_root "$tmp/r4"
chmod 000 "$tmp/r4/config/tower-settings.json"
if [ -r "$tmp/r4/config/tower-settings.json" ]; then
  echo "skip p3: mode 000 does not make a file unreadable to this user"
else
  check_refused "an unreadable profile" "$tmp/r4" tower
fi
chmod 644 "$tmp/r4/config/tower-settings.json"
mkdir -p "$tmp/r6/config" "$tmp/r6/scripts"
ln -s "$REPO_ROOT/config/worker-settings.json" "$tmp/r6/config/worker-settings.json"
check_refused "a symlinked profile" "$tmp/r6" worker
mkdir -p "$tmp/r7/scripts"
ln -s "$REPO_ROOT/config" "$tmp/r7/config"
check_refused "a symlinked config directory" "$tmp/r7" worker
mkdir -p "$tmp/r5/config/worker-settings.json" "$tmp/r5/scripts"
check_refused "a directory in the profile's place" "$tmp/r5" worker

rc=0
/bin/sh "$FLP" operator >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "p4: an unknown kind exited $rc, not 2"
rc=0
/bin/sh "$FLP" worker --root relative/root >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "p4: a relative --root exited $rc, not 2"
rc=0
/bin/sh "$FLP" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "p4: no kind exited $rc, not 2"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: test-fleet-launch-profile.sh ($fails)" >&2
  exit 1
fi
echo "PASS: test-fleet-launch-profile.sh"
