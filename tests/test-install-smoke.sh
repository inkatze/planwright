#!/bin/sh
# Tests for scripts/install-smoke.sh (universal-binary REQ-B1.1, REQ-B1.3):
# the allowlist PATH is real (an entry point invoking cargo, go, node, or
# python fails even when the host carries all four), the writer delivery mode
# installs and runs the named entry point, and an entry point that lost its
# execute bit fails. The marketplace mode needs the Claude CLI and is
# exercised by the workflow's install smoke step on every platform.
set -u
unset CDPATH

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SMOKE="$REPO_ROOT/scripts/install-smoke.sh"

failures=0
ok() { printf 'ok: %s\n' "$1"; }
bad() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
expect() {
  # expect <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# A host carrying every toolchain the constraint excludes: each stands in as
# a stub that succeeds, ahead of everything else on PATH.
toolchain="$TMP/toolchain"
mkdir "$toolchain"
for t in cargo go node python; do
  printf '#!/bin/sh\nexit 0\n' >"$toolchain/$t"
  chmod 755 "$toolchain/$t"
done
HOST_PATH="$toolchain:$PATH"

# A minimal tree install.sh accepts, with fixture entry points under scripts/.
src="$TMP/src"
mkdir -p "$src/scripts" "$src/doctrine" "$src/config"
cp -p "$REPO_ROOT/scripts/install.sh" "$src/scripts/install.sh"
printf '#!/bin/sh\nprintf %s\\\\n posix | awk %s >/dev/null && git --version >/dev/null\n' \
  "'%s'" "'{ print }'" >"$src/scripts/uses-posix.sh"
chmod 755 "$src/scripts/uses-posix.sh"
for t in cargo go node python; do
  printf '#!/bin/sh\n%s --version\n' "$t" >"$src/scripts/uses-$t.sh"
  chmod 755 "$src/scripts/uses-$t.sh"
done
printf '#!/bin/sh\nexit 0\n' >"$src/scripts/no-exec.sh"
chmod 644 "$src/scripts/no-exec.sh"

smoke() { PATH="$HOST_PATH" sh "$SMOKE" "$@" >"$TMP/out" 2>&1; }

# The fixtures themselves run on the host: what fails below is the allowlist.
for t in cargo go node python; do
  PATH="$HOST_PATH" "$src/scripts/uses-$t.sh" >/dev/null 2>&1
  expect "the uses-$t fixture runs on the toolchain host" 0 $?
done

smoke --modes writer --source "$src" --entry scripts/uses-posix.sh
expect "a POSIX-and-git entry point passes under the allowlist" 0 $?

for t in cargo go node python; do
  smoke --modes writer --source "$src" --entry "scripts/uses-$t.sh"
  rc=$?
  expect "an entry point invoking $t fails under the allowlist" 1 "$rc"
  if grep -q "scripts/uses-$t.sh failed under the allowlist PATH" "$TMP/out"; then
    ok "the $t failure names the entry point"
  else
    bad "the $t failure names the entry point"
    cat "$TMP/out" >&2
  fi
done

smoke --modes writer --source "$src" --entry scripts/no-exec.sh
expect "an entry point without its execute bit fails" 1 $?

# The named entry point through the real writer install.
smoke --modes writer
rc=$?
expect "the writer mode runs scripts/step-record.sh under the allowlist" 0 "$rc"
[ "$rc" -eq 0 ] || cat "$TMP/out" >&2

smoke --modes writer,carrier
expect "an unknown delivery mode is a usage error" 2 $?
smoke --modes ''
expect "an empty mode list is a usage error" 2 $?
smoke --modes writer --source "$src" --entry /bin/true
expect "an absolute entry path is a usage error" 2 $?
smoke --modes writer --source "$src" --entry ../src/scripts/uses-posix.sh
expect "an entry path climbing out of the installed root is a usage error" 2 $?

if [ "$failures" -gt 0 ]; then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all install-smoke tests passed\n'
