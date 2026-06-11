#!/bin/bash
# Tests for scripts/resolve-rule-doc.sh — the stable rule-doc resolution path
# (REQ-I1.1, REQ-I1.2, D-24). Plain bash 3.2, no test framework (the shared
# runner arrives with Task 2).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-rule-doc.sh"

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

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Fixture: a fake plugin root and a fake writer-mode claude dir.
mkdir -p "$tmp/plugin/doctrine" "$tmp/claude/planwright/doctrine" "$tmp/override/doctrine"
echo "plugin copy" > "$tmp/plugin/doctrine/sample-doc.md"
echo "writer copy" > "$tmp/claude/planwright/doctrine/sample-doc.md"
echo "writer only" > "$tmp/claude/planwright/doctrine/writer-only.md"
echo "override copy" > "$tmp/override/doctrine/sample-doc.md"

# 1. Plugin mode: CLAUDE_PLUGIN_ROOT set resolves to the plugin copy.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "plugin mode resolves" 0 $?
assert_eq "plugin mode path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 2. Writer mode: no plugin root; falls back to <claude-dir>/planwright.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" writer-only)"
assert "writer mode resolves" 0 $?
assert_eq "writer mode path" "$tmp/claude/planwright/doctrine/writer-only.md" "$out"

# 3. Explicit PLANWRIGHT_ROOT override wins over both.
out="$(PLANWRIGHT_ROOT="$tmp/override" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "override mode resolves" 0 $?
assert_eq "override wins" "$tmp/override/doctrine/sample-doc.md" "$out"

# 4. A '.md' suffix is accepted and normalized to the same path.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc.md)"
assert "md suffix accepted" 0 $?
assert_eq "md suffix path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 5. Missing doc: non-zero exit, message on stderr, nothing on stdout.
out="$(PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" no-such-doc 2>/dev/null)"
assert "missing doc fails" 1 $?
assert_eq "missing doc prints nothing on stdout" "" "$out"

# 6. Hostile names are refused before any path is formed (REQ-D1.6
#    framework-script security; same charset discipline as REQ-A1.8).
for hostile in "../escape" "a/b" ".hidden" "UPPER" "name with space" "-leading-dash"; do
  PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
    /bin/bash "$RESOLVER" "$hostile" >/dev/null 2>&1
  assert "hostile name refused: $hostile" 2 $?
done

# 7. No argument: usage error.
/bin/bash "$RESOLVER" >/dev/null 2>&1
assert "no argument is a usage error" 2 $?

# 8. Fallthrough: a root earlier in the chain that lacks the doc falls
#    through to the next root instead of failing.
mkdir -p "$tmp/empty-root/doctrine"
out="$(PLANWRIGHT_ROOT="$tmp/empty-root" CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claude" \
  /bin/bash "$RESOLVER" sample-doc)"
assert "fallthrough past a doc-less root" 0 $?
assert_eq "fallthrough lands on the next root" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 9. HOME fallback: with CLAUDE_DIR unset, the writer-mode root derives from
#    $HOME/.claude.
mkdir -p "$tmp/home/.claude/planwright/doctrine"
echo "home copy" > "$tmp/home/.claude/planwright/doctrine/home-doc.md"
out="$(HOME="$tmp/home" PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" \
  /bin/bash -c 'unset CLAUDE_DIR; exec /bin/bash "$1" home-doc' _ "$RESOLVER")"
assert "HOME fallback resolves" 0 $?
assert_eq "HOME fallback path" "$tmp/home/.claude/planwright/doctrine/home-doc.md" "$out"

# 10. Plugin mode must work without HOME or CLAUDE_DIR in the environment
#     (minimal containers): the earlier chain arms do not depend on the
#     writer-mode arm being derivable.
out="$(env -u HOME -u CLAUDE_DIR PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" sample-doc 2>/dev/null)"
assert "plugin mode resolves without HOME" 0 $?
assert_eq "HOME-less plugin path" "$tmp/plugin/doctrine/sample-doc.md" "$out"

# 11. With no usable root at all (no override, no plugin root, no CLAUDE_DIR,
#     no HOME), the resolver reports its own not-found message (exit 1)
#     rather than crashing with a bash unbound-variable error.
err="$(env -u HOME -u CLAUDE_DIR PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" \
  /bin/bash "$RESOLVER" sample-doc 2>&1 >/dev/null)"
rc=$?
assert "rootless environment exits 1" 1 "$rc"
case "$err" in
  *"not found"*"PLANWRIGHT_ROOT"*) echo "ok: rootless failure is the resolver's diagnostic with checked roots" ;;
  *)
    echo "FAIL: rootless failure lacks the evaluated-roots diagnostic: $err" >&2
    failures=$((failures + 1))
    ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-rule-doc tests passed"
