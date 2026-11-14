#!/bin/bash
# Tests for scripts/mc-session-root.sh — a session's recorded plugin root
# judged against the installed version: older is stale, the installed version
# or newer is current, and an absent or unreadable record is unknown, never
# current.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-session-root.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

command -v jq >/dev/null 2>&1 || {
  echo "ok: jq absent, the installed version cannot be read; skipped"
  exit 0
}

cache="$tmp/claude/plugins/cache/mkt/planwright"
mkdir -p "$tmp/9.9-hotfix" "$cache/0.62.0" "$cache/0.75.2" "$cache/0.75.10" "$cache/0.80.0" "$tmp/checkout/.claude-plugin" "$tmp/bare"
printf '{"name":"planwright","version":"0.70.0"}\n' >"$tmp/checkout/.claude-plugin/plugin.json"
jq -n --arg p "$cache/0.75.2" '{version: 2, plugins: {"planwright@planwright": [{scope: "user", installPath: $p, version: "0.75.2"}]}}' \
  >"$tmp/claude/plugins/installed_plugins.json"

verdict() { CLAUDE_DIR="$tmp/claude" /bin/sh "$repo_root/scripts/mc-session-root.sh" verdict "$1"; }
expect() { # expect <label> <root> <want line>
  got=$(verdict "$2")
  if [ "$got" = "$3" ]; then ok "$1"; else fail "$1: expected '$3', got '$got'"; fi
}
tab=$(printf '\t')

expect "an older cached version is stale" "$cache/0.62.0" "stale${tab}0.62.0${tab}0.75.2"
expect "the installed version is current" "$cache/0.75.2" "current"
expect "a newer version is current" "$cache/0.80.0" "current"
expect "a two-digit patch compares numerically, not as text" "$cache/0.75.10" "current"
expect "a checkout's version is read from its plugin.json" "$tmp/checkout" "stale${tab}0.70.0${tab}0.75.2"
expect "no recorded root (a row from before the field) is unknown" "-" "unknown${tab}no plugin root recorded at launch"
expect "an empty recorded root is unknown" "" "unknown${tab}no plugin root recorded at launch"
expect "a root naming no version is unknown, not current" "$tmp/bare" "unknown${tab}the recorded root names no readable version"

expect "a directory merely named like a version outside the cache is unknown" "$tmp/9.9-hotfix" "unknown${tab}the recorded root names no readable version"

rm -f "$tmp/claude/plugins/installed_plugins.json"
expect "an unreadable installed record is unknown, not current" "$cache/0.62.0" "unknown${tab}the installed version could not be read"

CLAUDE_DIR="$tmp/claude" /bin/sh "$repo_root/scripts/mc-session-root.sh" verdict >/dev/null 2>&1
[ $? = 2 ] && ok "a missing argument is a usage error" || fail "a missing argument was not exit 2"

cr=$(/bin/sh "$repo_root/scripts/mc-session-root.sh" current-root)
[ "$cr" = "$repo_root" ] && ok "current-root is this install's canonical root" || fail "current-root printed '$cr'"

[ "$failures" = 0 ] || exit 1
echo "all passed"
