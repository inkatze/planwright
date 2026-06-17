#!/bin/bash
# Tests for scripts/resolve-overlay-root.sh — the overlay-root resolution
# primitive the three per-kind resolvers (config, doctrine, catalog) share
# (Task 2; REQ-A1.1, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-E1.2,
# REQ-E1.5; D-1, D-3, D-4, D-8). Plain bash 3.2, no test framework (the
# sibling suites follow the same inline-assert convention).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-overlay-root.sh"

failures=0
assert() {
  # assert <description> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

assert_ne() {
  # assert_ne <description> <unexpected> <actual>
  if [ "$2" != "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (got '$3', expected something different)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

# Canonicalize the temp dir up front: on macOS /var symlinks to /private/var,
# and the resolver canonicalizes (pwd -P), so expected paths must match the
# canonical form.
tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A clean base env: strip every overlay-affecting variable so each case sets
# only what it exercises. (env -i would also drop PATH, so unset explicitly.)
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT "$@"
}

# ---------------------------------------------------------------------------
# core layer
# ---------------------------------------------------------------------------
mkdir -p "$tmp/core/config" "$tmp/core/doctrine"
out="$(base PLANWRIGHT_ROOT="$tmp/core" /bin/bash "$RESOLVER" core)"
assert "core resolves via PLANWRIGHT_ROOT" 0 $?
assert_eq "core root is the planwright root" "$tmp/core" "$out"

# core falls through to the plugin root when PLANWRIGHT_ROOT is unset.
mkdir -p "$tmp/plugin/config"
out="$(base CLAUDE_PLUGIN_ROOT="$tmp/plugin" /bin/bash "$RESOLVER" core)"
assert "core resolves via CLAUDE_PLUGIN_ROOT" 0 $?
assert_eq "core root is the plugin root" "$tmp/plugin" "$out"

# core skips a set-but-nonexistent root and falls through to the next arm.
out="$(base PLANWRIGHT_ROOT="$tmp/no-such-core" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" core)"
assert "core skips a nonexistent PLANWRIGHT_ROOT" 0 $?
assert_eq "core falls through to the plugin root" "$tmp/plugin" "$out"

# ---------------------------------------------------------------------------
# adopter layer
# ---------------------------------------------------------------------------
# Explicit override wins over everything.
mkdir -p "$tmp/data/id1" "$tmp/claude/planwright"
echo '{"name": "planwright"}' >"$tmp/claude/planwright/plugin.json"
out="$(base PLANWRIGHT_ADOPTER_OVERLAY="$tmp/explicit" \
  CLAUDE_PLUGIN_DATA="$tmp/data/id1" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" adopter)"
assert "adopter explicit override resolves" 0 $?
assert_eq "adopter override wins" "$tmp/explicit" "$out"

# Plugin mode: $CLAUDE_PLUGIN_DATA/overlay.
out="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id1" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" adopter)"
assert "adopter plugin-mode resolves" 0 $?
assert_eq "adopter plugin path" "$tmp/data/id1/overlay" "$out"

# Two distinct CLAUDE_PLUGIN_DATA ids resolve to distinct adopter roots
# (REQ-A1.5 multi-install coexistence).
out1="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id1" /bin/bash "$RESOLVER" adopter)"
out2="$(base CLAUDE_PLUGIN_DATA="$tmp/data/id2" /bin/bash "$RESOLVER" adopter)"
assert_ne "distinct plugin-data ids give distinct adopter roots" "$out1" "$out2"

# Writer mode: namespace derived from the manifest name.
out="$(base CLAUDE_DIR="$tmp/claude" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode resolves" 0 $?
assert_eq "adopter writer path" "$tmp/claude/planwright/planwright/overlay" "$out"

# Writer mode honors HOME when CLAUDE_DIR is unset.
mkdir -p "$tmp/home/.claude/planwright"
echo '{"name": "planwright"}' >"$tmp/home/.claude/planwright/plugin.json"
out="$(base HOME="$tmp/home" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode via HOME resolves" 0 $?
assert_eq "adopter writer path via HOME" "$tmp/home/.claude/planwright/planwright/overlay" "$out"

# The manifest `name` is extracted even when displayName precedes it.
mkdir -p "$tmp/claude2/planwright"
cat >"$tmp/claude2/planwright/plugin.json" <<'JSON'
{
  "displayName": "Planwright Display",
  "name": "workfork",
  "version": "0.1.0"
}
JSON
out="$(base CLAUDE_DIR="$tmp/claude2" /bin/bash "$RESOLVER" adopter)"
assert "adopter writer-mode resolves with displayName present" 0 $?
assert_eq "manifest name not confused by displayName" \
  "$tmp/claude2/planwright/workfork/overlay" "$out"

# Absent manifest: adopter layer degrades to absent (empty, zero exit) —
# REQ-A1.5 / REQ-A1.4 / F9.
mkdir -p "$tmp/claude-nomanifest/planwright"
out="$(base CLAUDE_DIR="$tmp/claude-nomanifest" /bin/bash "$RESOLVER" adopter)"
assert "absent manifest degrades to absent (zero exit)" 0 $?
assert_eq "absent manifest yields empty adopter root" "" "$out"

# Manifest present but no name field: degrade to absent.
mkdir -p "$tmp/claude-noname/planwright"
echo '{"version": "1.0.0"}' >"$tmp/claude-noname/planwright/plugin.json"
out="$(base CLAUDE_DIR="$tmp/claude-noname" /bin/bash "$RESOLVER" adopter)"
assert "manifest without name degrades to absent" 0 $?
assert_eq "name-less manifest yields empty adopter root" "" "$out"

# Hostile manifest name: never interpolated into a path; degrade to absent
# with a stderr warning (REQ-E1.2 charset validation, F9 degrade).
mkdir -p "$tmp/claude-evil/planwright"
echo '{"name": "../escape"}' >"$tmp/claude-evil/planwright/plugin.json"
err="$(base CLAUDE_DIR="$tmp/claude-evil" /bin/bash "$RESOLVER" adopter 2>&1 >/dev/null)"
rc=$?
assert "hostile manifest name degrades (zero exit)" 0 "$rc"
out="$(base CLAUDE_DIR="$tmp/claude-evil" /bin/bash "$RESOLVER" adopter 2>/dev/null)"
assert_eq "hostile manifest name yields empty adopter root" "" "$out"
case "$err" in
  *name*) echo "ok: hostile manifest name warns on stderr" ;;
  *)
    echo "FAIL: hostile manifest name did not warn: $err" >&2
    failures=$((failures + 1))
    ;;
esac

# A set-but-nonexistent CLAUDE_DIR has no readable manifest: degrade to absent.
out="$(base CLAUDE_DIR="$tmp/no-such-claude" /bin/bash "$RESOLVER" adopter)"
assert "nonexistent CLAUDE_DIR degrades adopter to absent" 0 $?
assert_eq "nonexistent CLAUDE_DIR yields empty adopter root" "" "$out"

# No adopter arm derivable at all (no override, no plugin data, no HOME/CLAUDE_DIR):
# absent, zero exit.
out="$(base /bin/bash "$RESOLVER" adopter)"
assert "no adopter arm derivable degrades (zero exit)" 0 $?
assert_eq "no adopter arm yields empty root" "" "$out"

# ---------------------------------------------------------------------------
# repo-tracked & machine-local layers (both under <repo>/.claude, per D-4)
# ---------------------------------------------------------------------------
mkdir -p "$tmp/repo/.claude"
out="$(base PLANWRIGHT_REPO_ROOT="$tmp/repo" /bin/bash "$RESOLVER" repo-tracked)"
assert "repo-tracked resolves" 0 $?
assert_eq "repo-tracked root" "$tmp/repo/.claude" "$out"

out="$(base PLANWRIGHT_REPO_ROOT="$tmp/repo" /bin/bash "$RESOLVER" machine-local)"
assert "machine-local resolves" 0 $?
assert_eq "machine-local root" "$tmp/repo/.claude" "$out"

# Outside any git repo and with no override: both degrade to absent.
out="$(cd "$tmp" && base /bin/bash "$RESOLVER" repo-tracked)"
assert "repo-tracked outside a repo degrades (zero exit)" 0 $?
assert_eq "repo-tracked absent yields empty root" "" "$out"

out="$(cd "$tmp" && base /bin/bash "$RESOLVER" machine-local)"
assert "machine-local outside a repo degrades (zero exit)" 0 $?
assert_eq "machine-local absent yields empty root" "" "$out"

# ---------------------------------------------------------------------------
# layer-argument validation
# ---------------------------------------------------------------------------
base /bin/bash "$RESOLVER" >/dev/null 2>&1
assert "no layer argument is a usage error" 2 $?

base /bin/bash "$RESOLVER" bogus-layer >/dev/null 2>&1
assert "unknown layer is rejected" 2 $?

for hostile in "../escape" "core/sub" "UPPER" "core layer"; do
  out="$(base /bin/bash "$RESOLVER" "$hostile" 2>/dev/null)"
  rc=$?
  assert "hostile layer name refused: $hostile" 2 "$rc"
  assert_eq "hostile layer prints nothing on stdout: $hostile" "" "$out"
done

# ---------------------------------------------------------------------------
# --contain: canonicalize-then-contain path-confinement helper (D-8, REQ-E1.5)
# ---------------------------------------------------------------------------
mkdir -p "$tmp/root/doctrine" "$tmp/outside"
echo "inside" >"$tmp/root/doctrine/ok.md"
echo "outside" >"$tmp/outside/evil.md"

# A path inside the root is accepted and the canonical path is printed.
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/doctrine/ok.md")"
assert "contained path accepted" 0 $?
assert_eq "contained path canonicalized" "$tmp/root/doctrine/ok.md" "$out"

# A not-yet-existing file whose parent is inside the root is accepted
# (confinement is checked before the read, the file need not exist yet).
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/doctrine/new.md")"
assert "contained nonexistent path accepted" 0 $?
assert_eq "contained nonexistent path canonicalized" "$tmp/root/doctrine/new.md" "$out"

# A ../ traversal escaping the root is rejected.
base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/../outside/evil.md" >/dev/null 2>&1
assert "dotdot traversal rejected" 2 $?

# An absolute path outside the root is rejected.
base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/outside/evil.md" >/dev/null 2>&1
assert "absolute escape rejected" 2 $?

# A symlink that escapes the root after canonicalization is rejected.
ln -s "$tmp/outside/evil.md" "$tmp/root/doctrine/escape.md"
base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/doctrine/escape.md" >/dev/null 2>&1
assert "symlink escape rejected" 2 $?

# A symlink that stays within the root is accepted.
ln -s "$tmp/root/doctrine/ok.md" "$tmp/root/doctrine/alias.md"
out="$(base /bin/bash "$RESOLVER" --contain "$tmp/root" "$tmp/root/doctrine/alias.md")"
assert "contained symlink accepted" 0 $?
assert_eq "contained symlink resolves to its target" "$tmp/root/doctrine/ok.md" "$out"

# --contain with a missing argument is a usage error.
base /bin/bash "$RESOLVER" --contain "$tmp/root" >/dev/null 2>&1
assert "--contain missing path is a usage error" 2 $?

# --contain against a nonexistent root is an error (the root must exist).
base /bin/bash "$RESOLVER" --contain "$tmp/no-such-root" "$tmp/no-such-root/x" >/dev/null 2>&1
assert "--contain nonexistent root errors" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-overlay-root tests passed"
