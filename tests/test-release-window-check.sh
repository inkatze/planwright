#!/bin/bash
# Tests for scripts/release-window-check.sh — the untagged-window lock, a
# required CI check reusing the shared release comparator (autopilot-reflex
# Task 6; D-7; REQ-E1.1, REQ-E1.2).
#
# Contract under test:
#   - IN the window (version of truth ahead of the latest tag) → exit 1, and the
#     failure names the publish command (scripts/release-publish.sh);
#   - a first release (no tags yet, so a version is pending) → exit 1, command
#     named — the window is open;
#   - OUTSIDE the window (version equals the latest tag) → exit 0;
#   - a non-bump PR (an extra commit that does not touch the version, version
#     still equal to the tag) → exit 0, unaffected (REQ-E1.2);
#   - a malformed/unreadable version of truth → the comparator exits 2 and the
#     check FAILS CLOSED (exit 2), never passing silently;
#   - any argument → usage error (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
CHECK="$here/../scripts/release-window-check.sh"
PUBLISH_CMD="scripts/release-publish.sh"
failures=0

[ -x "$CHECK" ] || {
  echo "FAIL: scripts/release-window-check.sh missing or not executable" >&2
  exit 1
}

gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# make_repo <dir> <version> — a fixture repo whose plugin.json holds <version>.
make_repo() {
  mkdir -p "$1/.claude-plugin"
  cat >"$1/.claude-plugin/plugin.json" <<EOF
{
  "name": "fixture",
  "version": "$2"
}
EOF
  gitc "$1" init -q
  gitc "$1" add -A
  gitc "$1" commit -q -m "version $2"
}

# run_check <dir> — run the check inside <dir>, capturing combined output and the
# exit code (globals: OUT, RC). Global git config is neutralized so a developer's
# signing/config never leaks into the fixture.
run_check() {
  RC=0
  OUT=$(cd "$1" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    "$CHECK" 2>&1) || RC=$?
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$3], got [$2]" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 — output did not contain [$3]" >&2
      echo "  output was: $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. In the window: version of truth ahead of the latest tag → fail (exit 1),
#    naming the publish command (REQ-E1.1).
r="$tmp/in-window"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
run_check "$r"
assert_eq "in-window: fails with exit 1" "$RC" "1"
assert_contains "in-window: names the publish command" "$OUT" "$PUBLISH_CMD"

# 2. First release (no tags yet) → the window is open → fail, command named.
r="$tmp/first-release"
make_repo "$r" 0.1.0
run_check "$r"
assert_eq "first-release (no tags): fails with exit 1" "$RC" "1"
assert_contains "first-release: names the publish command" "$OUT" "$PUBLISH_CMD"

# 3. Outside the window: version equals the latest tag → pass (exit 0).
r="$tmp/out-of-window"
make_repo "$r" 0.1.0
gitc "$r" tag v0.1.0
run_check "$r"
assert_eq "out-of-window (version == tag): passes with exit 0" "$RC" "0"

# 4. Non-bump PR unaffected: an extra commit that does NOT touch the version,
#    version still equal to the latest tag → pass (REQ-E1.2).
r="$tmp/non-bump-pr"
make_repo "$r" 0.1.0
gitc "$r" tag v0.1.0
echo "a feature change, no version bump" >"$r/FEATURE.txt"
gitc "$r" add -A
gitc "$r" commit -q -m "feat: something unrelated to releases"
run_check "$r"
assert_eq "non-bump PR (version still == tag): unaffected, exit 0" "$RC" "0"

# 5. Fail closed: a malformed version of truth makes the comparator exit 2; the
#    check must FAIL (exit 2), never pass silently.
r="$tmp/malformed"
make_repo "$r" "not-a-version"
run_check "$r"
assert_eq "malformed version of truth fails closed (exit 2)" "$RC" "2"

# 6. Usage error: any argument → exit 2.
RC=0
OUT=$(cd "$tmp" && "$CHECK" unexpected-arg 2>&1) || RC=$?
assert_eq "an argument is a usage error (exit 2)" "$RC" "2"

# 7. CDPATH regression (REQ-D1.9 portability): a hostile CDPATH with a decoy
#    `scripts/` must not corrupt the script's `cd "$(dirname "$0")"` (it calls
#    `unset CDPATH`). Per the house pattern (test-release-pending.sh), the
#    script and its siblings are copied under `scripts/` in the cwd and invoked
#    by the BARE relative name — the only shape where CDPATH actually bites.
work="$tmp/cdpath"
mkdir -p "$work/scripts" "$work/.claude-plugin" "$tmp/decoy/scripts"
cp "$here/../scripts/release-window-check.sh" "$here/../scripts/release-pending.sh" \
  "$here/../scripts/release-lib.sh" "$here/../scripts/echo-safety.sh" "$work/scripts/"
printf '{\n  "name": "fixture",\n  "version": "0.2.0"\n}\n' \
  >"$work/.claude-plugin/plugin.json"
gitc "$work" init -q
gitc "$work" add -A
gitc "$work" commit -q -m "version 0.2.0"
gitc "$work" tag v0.1.0
RC=0
OUT=$(cd "$work" && CDPATH="$tmp/decoy" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null scripts/release-window-check.sh 2>&1) || RC=$?
assert_eq "a hostile CDPATH does not corrupt the check (in-window → exit 1)" "$RC" "1"
assert_contains "cdpath fixture still names the publish command" "$OUT" "$PUBLISH_CMD"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-window-check.sh"
