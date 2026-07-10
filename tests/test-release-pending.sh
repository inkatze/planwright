#!/bin/bash
# Tests for scripts/release-pending.sh — the release comparator, the one
# definition of "pending" the untagged-window lock and the bookkeeping surface
# share (autopilot-reflex Task 4; D-7, D-8; REQ-D1.8).
#
# Contract under test:
#   - version of truth ahead of the latest release tag → `pending<TAB><version>`;
#   - equal → `none`;
#   - no release tags yet → `pending<TAB><version>` (the first release);
#   - a malformed version of truth → exit 2, no `pending`/`none` on stdout;
#   - the "latest" tag is chosen by SemVer precedence, not lexically
#     (v0.10.0 > v0.2.0).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
PENDING="$here/../scripts/release-pending.sh"
TAB=$(printf '\t')
failures=0

[ -x "$PENDING" ] || {
  echo "FAIL: scripts/release-pending.sh missing or not executable" >&2
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

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$3], got [$2]" >&2
    failures=$((failures + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Ahead of the latest tag → pending with the version of truth.
r="$tmp/ahead"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "ahead-of-tag reports pending with the version" "$out" "pending${TAB}0.2.0"

# 2. Equal to the latest tag → none.
r="$tmp/equal"
make_repo "$r" 0.1.0
gitc "$r" tag v0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "version equal to the latest tag reports none" "$out" "none"

# 3. No release tags at all → pending (the first release).
r="$tmp/first"
make_repo "$r" 0.1.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "no tags reports the first release as pending" "$out" "pending${TAB}0.1.0"

# 4. Malformed version of truth → exit 2, nothing on stdout.
r="$tmp/bad"
make_repo "$r" "not-a-version"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "malformed version exits 2" "$rc" "2"
assert_eq "malformed version prints nothing on stdout" "$out" ""

# 4b. A numeric prerelease identifier with a leading zero is malformed per
#     SemVer 2.0.0 §9 ("Numeric identifiers MUST NOT include leading zeroes"):
#     the grammar is strict on the version core, so it must be strict on the
#     prerelease numeric identifiers too, or two spellings of one version
#     (1.0.0-01 vs 1.0.0-1) collapse and a pending release can be misreported.
r="$tmp/leadingzero"
make_repo "$r" "1.0.0-01"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING" 2>/dev/null) || rc=$?
assert_eq "leading-zero numeric prerelease identifier exits 2" "$rc" "2"
assert_eq "leading-zero numeric prerelease prints nothing on stdout" "$out" ""

# 5. Latest tag chosen by SemVer precedence, not lexically (0.10.0 > 0.2.0).
r="$tmp/precedence"
make_repo "$r" 0.10.0
gitc "$r" tag v0.1.0
gitc "$r" tag v0.2.0
gitc "$r" tag v0.10.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "0.10.0 == latest (numeric precedence, not lexical) → none" "$out" "none"
# And one past it is pending.
r="$tmp/precedence2"
make_repo "$r" 0.11.0
gitc "$r" tag v0.2.0
gitc "$r" tag v0.10.0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$PENDING")
assert_eq "0.11.0 ahead of v0.10.0 → pending" "$out" "pending${TAB}0.11.0"

# 6. CDPATH regression (REQ-D1.9): a hostile CDPATH with a decoy `scripts/` must
#    not corrupt the script's `cd "$(dirname "$0")"` (it calls `unset CDPATH`).
#    Per the house pattern (tests/test-check-options-reference.sh:124), the script
#    is copied under `scripts/` in the cwd and invoked by the BARE relative name
#    `scripts/release-pending.sh` — the only shape where CDPATH actually bites an
#    un-guarded cd (a `../`-prefixed or absolute path bypasses CDPATH entirely, so
#    invoking "$PENDING" by its absolute path would prove nothing).
work="$tmp/cdpath"
mkdir -p "$work/scripts" "$work/.claude-plugin" "$tmp/decoy/scripts"
cp "$here/../scripts/release-pending.sh" "$here/../scripts/release-lib.sh" \
  "$here/../scripts/echo-safety.sh" "$work/scripts/"
printf '{\n  "name": "fixture",\n  "version": "0.2.0"\n}\n' >"$work/.claude-plugin/plugin.json"
gitc "$work" init -q
gitc "$work" add -A
gitc "$work" commit -q -m "version 0.2.0"
gitc "$work" tag v0.1.0
out=$(cd "$work" && CDPATH="$tmp/decoy" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  scripts/release-pending.sh)
assert_eq "a hostile CDPATH does not corrupt the comparator (unset CDPATH)" \
  "$out" "pending${TAB}0.2.0"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-pending.sh"
